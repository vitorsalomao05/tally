import Foundation

/// Which credential is driving the Claude provider right now.
public enum ClaudeAuthKind: String, Sendable {
    case oauth   // Claude Code OAuth token (no new login required)
    case cookie  // claude.ai session cookie captured via the WebView login
    case none    // signed out — neither credential available
}

/// Decides *which* Claude credential to use, and builds the matching provider.
///
/// Preference order (PROVIDERS.md: OAuth is primary, cookie is the fallback):
///   1. a usable Claude Code OAuth token  → `ClaudeOAuthProvider`
///   2. else a captured claude.ai cookie  → `ClaudeCookieProvider`
///   3. else signed out                   → `nil`
///
/// `preferCookie` (a Settings escape hatch for testing the cookie path) flips 1↔2,
/// but still falls back to OAuth if no cookie exists yet — so toggling it never
/// strands a working Claude Code user with no data.
///
/// All Keychain reads are best-effort: any failure (missing item, denied access)
/// is treated as "credential absent", never thrown — resolution must not crash the
/// poll loop. OAuth presence is checked via the silent `security` CLI path; the
/// cookie via Houdini's own native item. The OAuth check runs first in the default
/// order, so a Claude Code user never triggers a read of the cookie item.
public struct ClaudeAuthResolver: Sendable {
    private let store: CredentialStore

    public init(store: CredentialStore = CredentialStore()) {
        self.store = store
    }

    /// True when a Claude Code OAuth token is present, non-empty, and (if the blob
    /// carries an `expiresAt`) not past its expiry. Unknown/unparseable expiry is
    /// treated as still-valid so we never wrongly demote a working token.
    public func hasUsableOAuthToken() -> Bool {
        guard let blob = try? store.readGenericPassword(service: ClaudeOAuthProvider.keychainService),
              let creds = try? JSONDecoder().decode(OAuthBlob.self, from: blob) else {
            return false
        }
        guard let token = creds.claudeAiOauth.accessToken, !token.isEmpty else { return false }

        if let raw = creds.claudeAiOauth.expiresAt {
            // Claude Code stores epoch milliseconds; tolerate seconds too.
            let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
            if Date(timeIntervalSince1970: seconds) < Date() { return false }
        }
        return true
    }

    /// True when Houdini has a non-empty captured `sessionKey` cookie in its Keychain.
    public func hasSessionCookie() -> Bool {
        guard let data = try? store.nativeReadGenericPassword(
            service: ClaudeCookieProvider.keychainService,
            account: ClaudeCookieProvider.keychainAccount
        ) else { return false }
        let value = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty
    }

    /// The active auth kind under the current preference.
    public func resolve(preferCookie: Bool = false) -> ClaudeAuthKind {
        if preferCookie {
            if hasSessionCookie() { return .cookie }
            return hasUsableOAuthToken() ? .oauth : .none
        }
        if hasUsableOAuthToken() { return .oauth }
        return hasSessionCookie() ? .cookie : .none
    }

    /// The concrete provider to poll, or `nil` when signed out.
    public func makeProvider(preferCookie: Bool = false) -> (any UsageProvider)? {
        switch resolve(preferCookie: preferCookie) {
        case .oauth:  return ClaudeOAuthProvider(store: store)
        case .cookie: return ClaudeCookieProvider(store: store)
        case .none:   return nil
        }
    }

    /// Claude Code's Keychain blob (camelCase keys, no snake-case conversion).
    private struct OAuthBlob: Decodable {
        let claudeAiOauth: OAuth
        struct OAuth: Decodable {
            let accessToken: String?
            let expiresAt: Double?
        }
    }
}
