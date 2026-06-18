import Foundation
import Security

/// Errors surfaced while reading secrets from the macOS Keychain.
public enum CredentialError: Error, CustomStringConvertible, Sendable {
    case notFound(service: String)
    case interactionNotAllowed(service: String)
    case keychain(status: OSStatus)
    case cliFailure(status: Int32, message: String)
    case malformed(String)

    public var description: String {
        switch self {
        case .notFound(let s):
            return "Keychain item not found for service '\(s)'. Is Claude Code logged in on this machine?"
        case .interactionNotAllowed(let s):
            return "Keychain denied non-interactive access to '\(s)' (the item's ACL would require a user prompt). Use the security-CLI path or a signed app added to the item's ACL."
        case .keychain(let st):
            return "Keychain error (OSStatus \(st))."
        case .cliFailure(let st, let m):
            return "`security` exited \(st): \(m.isEmpty ? "no detail" : m)"
        case .malformed(let m):
            return "Malformed secret: \(m)"
        }
    }
}

/// Abstraction over the macOS Keychain for reading provider secrets.
///
/// Two read paths exist, by design:
///
///  - ``cliReadGenericPassword(service:account:)`` — shells out to `/usr/bin/security`.
///    A *generic-password* item is ACL-bound to the app that created it (Claude
///    Code). On this machine the `security` tool reads that item silently, so
///    this is the **default** for Phase 1 / `houdini`.
///
///  - ``nativeReadGenericPassword(service:account:)`` — the Security framework
///    (`SecItemCopyMatching`). Cleaner API, but a *different* unsigned binary
///    (e.g. `swift run houdini`) trips the item's ACL and triggers a blocking
///    interactive Keychain prompt. Switch to this once Houdini ships as a signed
///    app that has been added to the item's ACL.
public struct CredentialStore: Sendable {
    public init() {}

    /// Default read path: the `security` CLI (empirically silent for the Claude
    /// Code credential). Returns the raw secret bytes.
    ///
    /// TODO(phase ≥2, signed app): migrate this default to
    /// ``nativeReadGenericPassword(service:account:)`` once Houdini ships as a
    /// **code-signed** app that has been **added to the Keychain item's ACL**.
    /// The native path avoids spawning `/usr/bin/security` on every poll (the
    /// menu bar refreshes every 60s), which is wasteful and ~10ms slower per call.
    /// Until then the CLI path is the only one that reads silently from an
    /// unsigned/ad-hoc binary (see the type doc above).
    public func readGenericPassword(service: String, account: String? = nil) throws -> Data {
        #if os(macOS)
        return try cliReadGenericPassword(service: service, account: account)
        #else
        // iOS/iPadOS have neither the `security` CLI nor `Foundation.Process`, so the
        // CLI path cannot exist there. Read natively via the Security framework. The
        // only credential the iOS app reads is the `sessionKey` cookie it captured and
        // wrote itself, so the native path reads it back without a prompt (see the
        // cookie provider). FetcherCore's cookie path never depends on the CLI.
        return try nativeReadGenericPassword(service: service, account: account)
        #endif
    }

    // MARK: - security CLI path (macOS only — uses Foundation.Process)

    #if os(macOS)
    public func cliReadGenericPassword(service: String, account: String? = nil) throws -> Data {
        var args = ["find-generic-password", "-s", service, "-w"]
        if let account { args += ["-a", account] }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        try proc.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // `security` exits 44 when the item is absent.
            if proc.terminationStatus == 44 || msg.localizedCaseInsensitiveContains("could not be found") {
                throw CredentialError.notFound(service: service)
            }
            throw CredentialError.cliFailure(status: proc.terminationStatus, message: msg)
        }

        // `security -w` prints the secret followed by a single trailing newline.
        var text = String(data: outData, encoding: .utf8) ?? ""
        if text.hasSuffix("\n") { text.removeLast() }
        guard let data = text.data(using: .utf8) else {
            throw CredentialError.malformed("secret was not valid UTF-8")
        }
        return data
    }
    #endif // os(macOS)

    // MARK: - native Security framework path (cross-platform — Security.framework)

    public func nativeReadGenericPassword(service: String, account: String? = nil) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account { query[kSecAttrAccount as String] = account }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw CredentialError.malformed("Keychain returned no data")
            }
            return data
        case errSecItemNotFound:
            throw CredentialError.notFound(service: service)
        case errSecInteractionNotAllowed:
            throw CredentialError.interactionNotAllowed(service: service)
        default:
            throw CredentialError.keychain(status: status)
        }
    }

    // MARK: - native write / delete (for Houdini's own secrets, e.g. the cookie)

    /// Upsert a generic-password item Houdini owns (e.g. the captured `sessionKey`).
    /// Stored `AfterFirstUnlock` so the menu bar agent can read it when launched at
    /// login. Houdini creates the item, so it reads it back later without a prompt.
    public func nativeWriteGenericPassword(service: String, account: String, data: Data) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let addQuery = base.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]) { _, new in new }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update = SecItemUpdate(base as CFDictionary,
                                       [kSecValueData as String: data] as CFDictionary)
            guard update == errSecSuccess else { throw CredentialError.keychain(status: update) }
        default:
            throw CredentialError.keychain(status: status)
        }
    }

    /// Remove a generic-password item Houdini owns. A missing item is not an error.
    public func nativeDeleteGenericPassword(service: String, account: String? = nil) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account { query[kSecAttrAccount as String] = account }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychain(status: status)
        }
    }
}
