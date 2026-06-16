import Foundation

/// Errors surfaced by a `UsageProvider.fetch()`.
public enum ProviderError: Error, CustomStringConvertible, Sendable {
    case authExpired                       // 401 / 403, or empty access token
    case rateLimited                       // 429
    case http(status: Int, body: String)   // any other non-2xx
    case network(String)
    case parse(String)
    case credential(String)

    public var description: String {
        switch self {
        case .authExpired:
            return "Claude OAuth token expired or unauthorized (401/403). Re-authenticate Claude Code (`claude`) and retry."
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

    /// Keychain service name Claude Code writes its OAuth credentials under on
    /// this machine. (The classic `Claude Code` item is absent here.)
    public static let keychainService = "Claude Code-credentials"

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let fallbackVersion = "2.1.178"

    private let store: CredentialStore
    private let explicitVersion: String?

    public init(store: CredentialStore = CredentialStore(), clientVersion: String? = nil) {
        self.store = store
        self.explicitVersion = clientVersion
    }

    public func fetch() async throws -> [UsageMetric] {
        let token = try readAccessToken()

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
            (data, response) = try await URLSession.shared.data(for: request)
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

    // MARK: - Token

    /// Read & decode the access token from the Keychain blob. Never logs it.
    private func readAccessToken() throws -> String {
        let blob: Data
        do {
            blob = try store.readGenericPassword(service: Self.keychainService)
        } catch {
            throw ProviderError.credential("\(error)")
        }

        let creds: KeychainBlob
        do {
            // The blob's keys are already camelCase ("claudeAiOauth", "accessToken"),
            // so no snake_case conversion here.
            creds = try JSONDecoder().decode(KeychainBlob.self, from: blob)
        } catch {
            throw ProviderError.credential("could not decode Claude Code OAuth blob")
        }

        let token = creds.claudeAiOauth.accessToken
        guard !token.isEmpty else { throw ProviderError.authExpired }
        return token
    }

    /// `claude-code/<version>` UA. Resolve the live Claude Code version when the
    /// caller didn't pin one; fall back to a known-good constant.
    private var clientVersion: String {
        explicitVersion ?? Self.detectedClientVersion()
    }

    /// Best-effort `claude --version` lookup (output like "2.1.178 (Claude Code)").
    public static func detectedClientVersion() -> String {
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
        return fallbackVersion
    }

    // MARK: - Parsing

    /// Map the raw OAuth usage JSON to normalized metrics. `internal` for testing.
    static func parse(_ data: Data, providerId: String) throws -> [UsageMetric] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto: OAuthUsageDTO
        do {
            dto = try decoder.decode(OAuthUsageDTO.self, from: data)
        } catch {
            throw ProviderError.parse("\(error)")
        }

        var metrics: [UsageMetric] = []

        // Utilization windows. `utilization` is already a 0–100 percentage; only
        // emit windows the account actually has (e.g. `seven_day_opus` is null
        // for non-Opus accounts).
        func addWindow(_ bucket: OAuthUsageDTO.Bucket?, label: String) {
            guard let bucket, let pct = bucket.utilization else { return }
            metrics.append(UsageMetric(
                label: label,
                pct: pct,
                resetAt: parseResetDate(bucket.resetsAt),
                providerId: providerId
            ))
        }
        addWindow(dto.fiveHour, label: "5-hour")
        addWindow(dto.sevenDay, label: "Weekly")
        addWindow(dto.sevenDayOpus, label: "Opus weekly")
        addWindow(dto.sevenDaySonnet, label: "Sonnet weekly")

        // "Claude Extra" overage → dollar balance. `used_credits`/`monthly_limit`
        // are minor units; divide by 10^decimal_places to get currency amounts.
        if let extra = dto.extraUsage, extra.isEnabled == true, let usedRaw = extra.usedCredits {
            let divisor = pow(10.0, Double(extra.decimalPlaces ?? 0))
            let used = usedRaw / divisor
            let limit = extra.monthlyLimit.map { $0 / divisor }
            metrics.append(UsageMetric(
                label: "Extra usage ($)",
                pct: extra.utilization,
                used: used,
                limit: limit,
                dollars: used,
                providerId: providerId
            ))
        }

        return metrics
    }

    /// Parse an Anthropic reset timestamp, tolerating microsecond precision
    /// (e.g. "2026-06-16T06:40:00.602994+00:00") which `ISO8601DateFormatter`
    /// rejects unless the fractional part is normalized to milliseconds.
    static func parseResetDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        // Trim fractional seconds to 3 digits for the fractional formatter.
        let normalized = raw.replacingOccurrences(
            of: #"\.(\d{3})\d+"#, with: ".$1", options: .regularExpression
        )
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: normalized) { return date }

        // Fall back: strip fractional seconds entirely.
        let stripped = raw.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression
        )
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: stripped)
    }
}

// MARK: - Wire format (GET /api/oauth/usage)

/// Shape of the Keychain credential blob written by Claude Code.
private struct KeychainBlob: Decodable {
    let claudeAiOauth: OAuth
    struct OAuth: Decodable {
        let accessToken: String
    }
}

/// Decoded with `.convertFromSnakeCase`, so JSON `five_hour` → `fiveHour`, etc.
/// Every field is optional because the endpoint returns many `null` buckets that
/// vary per account/plan.
private struct OAuthUsageDTO: Decodable {
    let fiveHour: Bucket?
    let sevenDay: Bucket?
    let sevenDayOpus: Bucket?
    let sevenDaySonnet: Bucket?
    let extraUsage: ExtraUsage?

    struct Bucket: Decodable {
        let utilization: Double?
        let resetsAt: String?
    }

    struct ExtraUsage: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?
        let currency: String?
        let decimalPlaces: Int?
    }
}
