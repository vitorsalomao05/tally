import Foundation

/// Errors surfaced by a `UsageProvider.fetch()`.
public enum ProviderError: Error, CustomStringConvertible, Sendable {
    case authExpired                       // 401 / 403 on the OAuth path, or empty access token
    case needsLogin                        // 401 / 403 on the cookie path → re-run the WebView login
    case rateLimited                       // 429
    case http(status: Int, body: String)   // any other non-2xx
    case network(String)
    case parse(String)
    case credential(String)

    public var description: String {
        switch self {
        case .authExpired:
            return "Claude OAuth token expired or unauthorized (401/403). Re-authenticate Claude Code (`claude`) and retry."
        case .needsLogin:
            return "Claude.ai session expired or signed out (401/403). Sign in to Claude.ai again to refresh the cookie."
        case .rateLimited:
            return "Rate limited (429). The usage endpoint throttles requests that omit the `claude-code/<version>` User-Agent; back off and retry."
        case .http(let status, let body):
            return "Unexpected HTTP \(status) from the usage endpoint. Body: \(body)"
        case .network(let m):
            return "Network error: \(m)"
        case .parse(let m):
            return "Could not parse usage response: \(m)"
        case .credential(let m):
            return "Credential error: \(m)"
        }
    }
}

/// Flagship provider: reads the Claude Code OAuth token from the Keychain and
/// calls the Anthropic OAuth usage endpoint (PROVIDERS.md → "claude").
public struct ClaudeOAuthProvider: UsageProvider {
    public let id = "claude"
    public let displayName = "Claude (Pro/Max)"
    public let authMethod: AuthMethod = .keychainOAuth
    // usagePct + resetTimer always; dollarBalance when "Claude Extra" overage is on.
    public let capabilities: Capabilities = [.usagePct, .resetTimer, .dollarBalance]
    public let refreshInterval: TimeInterval = 60

    /// Primary Keychain service name Claude Code writes its OAuth credentials under, and the
    /// head of ``ClaudeOAuthCredentialSource/candidateKeychainServices`` (the classic
    /// `Claude Code` item is tried next). Kept as a public constant so the ordered list re-uses it.
    public static let keychainService = "Claude Code-credentials"

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let fallbackVersion = "2.1.178"

    private let source: ClaudeOAuthCredentialSource
    private let explicitVersion: String?

    public init(store: CredentialStore = CredentialStore(), clientVersion: String? = nil) {
        self.source = ClaudeOAuthCredentialSource(store: store)
        self.explicitVersion = clientVersion
    }

    /// Injection seam (tests): supply a preconfigured credential source — e.g. one with an
    /// injected refresher — instead of the default Keychain-backed one.
    init(source: ClaudeOAuthCredentialSource, clientVersion: String? = nil) {
        self.source = source
        self.explicitVersion = clientVersion
    }

    public func fetch() async throws -> [UsageMetric] {
        // Discovery (ordered Keychain items → on-disk fallback) + in-memory refresh of a
        // stale token all live in `source`. The token value is never logged.
        let resolved = try await source.resolveForFetch()
        do {
            return try await fetchUsage(token: resolved.accessToken)
        } catch ProviderError.authExpired {
            // A live 401/403: try one in-memory refresh with the stored refresh token and
            // retry once. No-op today (no refresher wired) → preserves `.authExpired`.
            guard let refreshToken = resolved.refreshToken,
                  let fresh = try await source.refreshedTokenAfterAuthFailure(refreshToken: refreshToken)
            else {
                throw ProviderError.authExpired
            }
            return try await fetchUsage(token: fresh)
        }
    }

    // MARK: - Usage request

    /// One authenticated GET against the OAuth usage endpoint with the given bearer token.
    /// The token is sent only in the `Authorization` header (never logged) and never
    /// follows a cross-host redirect (``CredentialRedirectGuard``). Maps status → typed error.
    private func fetchUsage(token: String) async throws -> [UsageMetric] {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        // MANDATORY headers. Per ARCHITECTURE.md/PROVIDERS.md the endpoint throttles
        // (429) requests without a `claude-code/<version>` User-Agent, so we always
        // send it. The bearer token is never logged.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("claude-code/\(clientVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            // Redirect guard: never let the bearer token follow a cross-host redirect.
            (data, response) = try await URLSession.shared.data(
                for: request, delegate: CredentialRedirectGuard.shared
            )
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.network("response was not HTTP")
        }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw ProviderError.authExpired
        case 429:
            throw ProviderError.rateLimited
        default:
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
            throw ProviderError.http(status: http.statusCode, body: snippet)
        }

        return try Self.parse(data, providerId: id)
    }

    /// `claude-code/<version>` UA. Resolve the live Claude Code version when the
    /// caller didn't pin one; fall back to a known-good constant.
    private var clientVersion: String {
        explicitVersion ?? Self.detectedClientVersion()
    }

    /// Best-effort `claude --version` lookup (output like "2.1.178 (Claude Code)").
    /// macOS only: Claude Code exists only on the desktop, and the probe needs
    /// `Foundation.Process` (unavailable on iOS). On other platforms we fall straight
    /// through to the pinned `fallbackVersion`. (The OAuth provider itself is a
    /// desktop-only concept — iOS authenticates via the cookie provider — so the
    /// constant is never actually exercised on iOS.)
    public static func detectedClientVersion() -> String {
        #if os(macOS)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["claude", "--version"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            if let token = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
                .first(where: { $0.first?.isNumber == true }) {
                return String(token)
            }
        } catch {
            // fall through to the constant
        }
        #endif // os(macOS)
        return fallbackVersion
    }

    // MARK: - Parsing

    /// Map the raw OAuth usage JSON to normalized metrics. Delegates to the shared
    /// `ClaudeUsageParser`, which is tolerant of both the OAuth and cookie dialects
    /// (`FetcherCoreTests` proves the two map identically). `internal` for testing.
    static func parse(_ data: Data, providerId: String) throws -> [UsageMetric] {
        try ClaudeUsageParser.parse(data, providerId: providerId)
    }
}
