import Foundation

/// Tolerant parser for Claude usage JSON, shared by the OAuth and cookie providers.
///
/// It accepts BOTH field-name dialects so a single code path serves both endpoints
/// — `FetcherCoreTests` proves the two fixtures normalize to *identical* metrics:
///   • OAuth  (`api.anthropic.com/api/oauth/usage`):
///       `utilization`, `resets_at`, `used_credits`, `monthly_limit`
///   • cookie (`claude.ai/api/organizations/{id}/usage`):
///       `utilization_pct`, `reset_at`, `current_spending`, `budget_limit`
///
/// Missing / null fields never throw: a window that isn't present is simply
/// skipped, so a plan without Opus / Sonnet / extra-usage just yields fewer
/// metrics. Only malformed JSON (not a usable object) raises `ProviderError.parse`.
public enum ClaudeUsageParser {

    /// Map raw usage JSON (either dialect) to normalized metrics.
    /// Emitted order is stable: 5-hour, Weekly, Opus weekly, Sonnet weekly, Extra usage.
    public static func parse(_ data: Data, providerId: String) throws -> [UsageMetric] {
        let decoder = JSONDecoder()
        // JSON `five_hour`→`fiveHour`, `utilization_pct`→`utilizationPct`, etc.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto: UsageDTO
        do {
            dto = try decoder.decode(UsageDTO.self, from: data)
        } catch {
            throw ProviderError.parse("\(error)")
        }

        var metrics: [UsageMetric] = []

        // Percent windows. Only emit windows the account actually has — a null
        // bucket (e.g. no Opus) or one without a utilization figure is skipped.
        func addWindow(_ bucket: UsageDTO.Bucket?, label: String) {
            guard let bucket, let pct = bucket.pct else { return }
            metrics.append(UsageMetric(
                label: label,
                pct: pct,
                resetAt: parseResetDate(bucket.reset),
                providerId: providerId
            ))
        }
        addWindow(dto.fiveHour, label: "5-hour")
        addWindow(dto.sevenDay, label: "Weekly")
        addWindow(dto.sevenDayOpus, label: "Opus weekly")
        addWindow(dto.sevenDaySonnet, label: "Sonnet weekly")

        // "Claude Extra" overage → dollar balance. OAuth reports `used_credits` /
        // `monthly_limit` in minor units alongside `decimal_places`; the cookie
        // endpoint reports `current_spending` / `budget_limit` already in dollars
        // (no `decimal_places`, so the divisor is 1). `is_enabled` is honored when
        // present (OAuth) and assumed enabled when absent but spending data exists.
        if let extra = dto.extraUsage, extra.enabled != false, let usedRaw = extra.used {
            let divisor = pow(10.0, Double(extra.decimalPlaces ?? 0))
            let used = usedRaw / divisor
            let limit = extra.limit.map { $0 / divisor }
            metrics.append(UsageMetric(
                label: "Extra usage ($)",
                pct: extra.pct,
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
    public static func parseResetDate(_ raw: String?) -> Date? {
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

// MARK: - Tolerant wire format

/// Decoded with `.convertFromSnakeCase`. Every field is optional: the endpoints
/// return many null buckets that vary per account/plan, and the two dialects use
/// different inner key names — handled by the per-field `init(from:)` fallbacks.
private struct UsageDTO: Decodable {
    let fiveHour: Bucket?
    let sevenDay: Bucket?
    let sevenDayOpus: Bucket?
    let sevenDaySonnet: Bucket?
    let extraUsage: Extra?

    /// One utilization window. Accepts `utilization` (OAuth) or `utilization_pct`
    /// (cookie); `resets_at` (OAuth) or `reset_at` (cookie).
    struct Bucket: Decodable {
        let pct: Double?
        let reset: String?

        private enum Keys: String, CodingKey {
            case utilization, utilizationPct, resetsAt, resetAt
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            pct = try c.decodeIfPresent(Double.self, forKey: .utilization)
                ?? c.decodeIfPresent(Double.self, forKey: .utilizationPct)
            reset = try c.decodeIfPresent(String.self, forKey: .resetsAt)
                ?? c.decodeIfPresent(String.self, forKey: .resetAt)
        }
    }

    /// "Claude Extra" overage. Accepts `used_credits`/`monthly_limit` (OAuth, minor
    /// units + `decimal_places`) or `current_spending`/`budget_limit` (cookie,
    /// dollars). `utilization`/`utilization_pct` give the percentage either way.
    struct Extra: Decodable {
        let enabled: Bool?
        let used: Double?
        let limit: Double?
        let pct: Double?
        let decimalPlaces: Int?

        private enum Keys: String, CodingKey {
            case isEnabled, usedCredits, currentSpending, monthlyLimit, budgetLimit
            case utilization, utilizationPct, decimalPlaces
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled)
            used = try c.decodeIfPresent(Double.self, forKey: .usedCredits)
                ?? c.decodeIfPresent(Double.self, forKey: .currentSpending)
            limit = try c.decodeIfPresent(Double.self, forKey: .monthlyLimit)
                ?? c.decodeIfPresent(Double.self, forKey: .budgetLimit)
            pct = try c.decodeIfPresent(Double.self, forKey: .utilization)
                ?? c.decodeIfPresent(Double.self, forKey: .utilizationPct)
            decimalPlaces = try c.decodeIfPresent(Int.self, forKey: .decimalPlaces)
        }
    }
}
