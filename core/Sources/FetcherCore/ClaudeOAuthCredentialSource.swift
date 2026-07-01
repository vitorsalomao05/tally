import Foundation

/// The single, testable source of the **Claude Code OAuth credential**.
///
/// It collapses what used to be two private blob structs and two Keychain read
/// call-sites (`ClaudeAuth.hasUsableOAuthToken()` and `ClaudeOAuthProvider.readAccessToken()`)
/// into one place, and broadens the P1 login path (BACKLOG.md → "(a)"):
///
///  1. **Ordered Keychain discovery** — tries `candidateKeychainServices` in order,
///     first item that yields a blob with a non-empty access token wins. A
///     `CredentialError.notFound` for one candidate falls through to the next.
///  2. **On-disk fallback** — when no Keychain item yields a usable blob, it reads
///     the file Claude Code itself already wrote at `~/.claude/.credentials.json`
///     (read-only; macOS only). A missing/unreadable/unparseable file is simply
///     "credential absent".
///  3. **In-memory refresh** — when the discovered access token is expired and a
///     `refreshToken` is present, it refreshes via an **injected** `Refresher` and
///     uses the fresh token *for the current fetch only*.
///
/// ### Security posture (see CLAUDE.md guardrails / ADR-005)
/// No token value is ever printed, logged, written, or cached. The only disk read is
/// the user's existing `~/.claude/.credentials.json` — never written, moved, or copied.
/// Refresh is **injected** so tests never hit the network; the production default wires
/// **no** refresher yet (`refresher == nil`), so an expired token behaves exactly as it
/// does today (degrade to `.authExpired`) until the refresh endpoint is signed off and
/// wired in a follow-up. The refreshed token is held in memory only — never persisted
/// back to the Keychain item Claude Code owns, nor to disk (that is slice (c)'s job).
///
/// The seam is `public` for the same reason `ClaudeUsageParser` / `selectOrganization`
/// are: the `houdini-selftest` mirror (a separate executable, plain `import FetcherCore`)
/// must be able to inject the Keychain/file/refresh closures and observe the assertions.
public struct ClaudeOAuthCredentialSource: Sendable {

    /// Keychain service names tried in order; the first decodable hit wins.
    /// `"Claude Code-credentials"` stays **first** so existing users read exactly the
    /// item they do today (no behavior change). `"Claude Code"` is the classic item some
    /// installs use instead — previously noted in the code but never actually queried.
    public static let candidateKeychainServices = [ClaudeOAuthProvider.keychainService, "Claude Code"]

    /// Refreshes a stale access token **in memory**, returning a fresh blob. Injected so
    /// tests never touch the network and production can stay unwired until sign-off.
    public typealias Refresher = @Sendable (_ refreshToken: String) async throws -> Blob

    // MARK: - Blob

    /// The Claude Code OAuth blob shape: `{ "claudeAiOauth": { accessToken, expiresAt,
    /// refreshToken } }`. Keys are already camelCase, so no snake_case conversion. This is
    /// the *one* decode shape that replaces the former private `OAuthBlob` / `KeychainBlob`.
    public struct Blob: Decodable, Sendable, Equatable {
        public var accessToken: String?
        public var expiresAt: Double?
        public var refreshToken: String?

        public init(accessToken: String?, expiresAt: Double? = nil, refreshToken: String? = nil) {
            self.accessToken = accessToken
            self.expiresAt = expiresAt
            self.refreshToken = refreshToken
        }

        private enum Root: String, CodingKey { case claudeAiOauth }
        private enum Inner: String, CodingKey { case accessToken, expiresAt, refreshToken }

        public init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: Root.self)
            let o = try root.nestedContainer(keyedBy: Inner.self, forKey: .claudeAiOauth)
            accessToken = try o.decodeIfPresent(String.self, forKey: .accessToken)
            expiresAt = try o.decodeIfPresent(Double.self, forKey: .expiresAt)
            refreshToken = try o.decodeIfPresent(String.self, forKey: .refreshToken)
        }

        static func decode(_ data: Data) -> Blob? { try? JSONDecoder().decode(Blob.self, from: data) }

        var nonEmptyAccessToken: String? {
            guard let t = accessToken, !t.isEmpty else { return nil }
            return t
        }
        var nonEmptyRefreshToken: String? {
            guard let t = refreshToken, !t.isEmpty else { return nil }
            return t
        }

        /// Past its `expiresAt`? Claude Code stores epoch **milliseconds**; tolerate seconds
        /// too. An absent/unknown expiry is treated as still-valid (never wrongly demote).
        func isExpired(now: Date) -> Bool {
            guard let raw = expiresAt else { return false }
            let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
            return Date(timeIntervalSince1970: seconds) < now
        }
    }

    /// A credential resolved and ready for one usage fetch.
    public struct Resolved: Sendable, Equatable {
        /// The access token to send (already refreshed in memory if it was stale).
        public let accessToken: String
        /// The refresh token, if any — enables a single refresh-retry after a live 401/403.
        public let refreshToken: String?
    }

    // MARK: - Stored seams

    private let services: [String]
    private let blobLoader: @Sendable () -> Blob?
    private let refresher: Refresher?
    private let now: @Sendable () -> Date

    // MARK: - Init

    /// Production source: ordered Keychain discovery via `store`, `~/.claude/.credentials.json`
    /// fallback, and (by default) **no** refresher wired — an expired token degrades exactly
    /// as it does today until the refresh endpoint is signed off.
    public init(store: CredentialStore = CredentialStore(), refresher: Refresher? = nil) {
        self.init(
            keychainRead: { try store.readGenericPassword(service: $0) },
            fileRead: { Self.readCredentialsFileData() },
            refresher: refresher
        )
    }

    /// Injection seam (tests / `houdini-selftest`): supply the per-service Keychain read,
    /// the file-contents read, an optional refresher, and a clock — no real Keychain, disk,
    /// or network is touched.
    public init(
        services: [String] = candidateKeychainServices,
        keychainRead: @escaping @Sendable (String) throws -> Data,
        fileRead: @escaping @Sendable () -> Data? = { nil },
        refresher: Refresher? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.services = services
        self.refresher = refresher
        self.now = now
        self.blobLoader = {
            Self.discover(services: services, keychainRead: keychainRead, fileRead: fileRead)
        }
    }

    // MARK: - Discovery

    /// First candidate Keychain item that decodes to a blob with a non-empty access token
    /// wins; else the on-disk file. Any read/decode failure for a candidate is skipped
    /// (best-effort — discovery never throws).
    static func discover(
        services: [String],
        keychainRead: (String) throws -> Data,
        fileRead: () -> Data?
    ) -> Blob? {
        for service in services {
            if let data = try? keychainRead(service),
               let blob = Blob.decode(data), blob.nonEmptyAccessToken != nil {
                return blob
            }
        }
        if let data = fileRead(), let blob = Blob.decode(data), blob.nonEmptyAccessToken != nil {
            return blob
        }
        return nil
    }

    // MARK: - Queries

    /// Resolver gating (sync, best-effort, never throws). A token is "usable" if it is
    /// present and either **unexpired**, or **expired but refreshable** (a `refreshToken`
    /// is present *and* a refresher is wired). Keeps a stale-but-refreshable token on the
    /// OAuth path instead of demoting it to the cookie fallback.
    public func hasUsableToken() -> Bool {
        guard let blob = blobLoader(), blob.nonEmptyAccessToken != nil else { return false }
        if !blob.isExpired(now: now()) { return true }
        return blob.nonEmptyRefreshToken != nil && refresher != nil
    }

    /// Provider fetch (async). Lenient, matching today's provider: returns the discovered
    /// token as-is, **unless** it is expired *and* we can refresh it in memory (then the
    /// fresh token is returned). Throws `.credential` only when there is no credential at
    /// all (no Keychain item, no file).
    public func resolveForFetch() async throws -> Resolved {
        guard let blob = blobLoader(), let token = blob.nonEmptyAccessToken else {
            throw ProviderError.credential(
                "no Claude Code OAuth credential found (checked Keychain items "
                + "\(services.joined(separator: ", ")) and ~/.claude/.credentials.json). "
                + "Is Claude Code logged in on this machine?")
        }
        if blob.isExpired(now: now()), let rt = blob.nonEmptyRefreshToken, let refresher {
            let refreshed = try await refresher(rt)
            if let fresh = refreshed.nonEmptyAccessToken {
                return Resolved(accessToken: fresh, refreshToken: refreshed.nonEmptyRefreshToken ?? rt)
            }
            // Refresh produced no token → fall through and let the server reject the old one.
        }
        return Resolved(accessToken: token, refreshToken: blob.nonEmptyRefreshToken)
    }

    /// One in-memory refresh after a live 401/403. Returns `nil` when it can't help
    /// (no refresher wired, or the refresh yielded no token). Never persists anything.
    public func refreshedTokenAfterAuthFailure(refreshToken: String) async throws -> String? {
        guard let refresher else { return nil }
        return try await refresher(refreshToken).nonEmptyAccessToken
    }

    // MARK: - On-disk fallback (read-only; the file Claude Code itself wrote)

    #if os(macOS)
    /// Read `~/.claude/.credentials.json` (read-only). Missing/unreadable → `nil`.
    /// Never writes, moves, or copies the file. macOS only — iOS has no OAuth path.
    static func readCredentialsFileData() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }
    #else
    static func readCredentialsFileData() -> Data? { nil }
    #endif
}
