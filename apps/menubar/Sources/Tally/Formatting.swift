import SwiftUI
import FetcherCore

/// Threshold colors: <60% normal, 60–85% amber, >85% red.
enum Thresholds {
    static func barColor(_ pct: Double?) -> Color {
        guard let p = pct else { return .gray }
        switch p {
        case ..<60: return .green
        case ..<85: return .orange
        default:    return .red
        }
    }

    /// Menu bar text color — "normal" stays adaptive (primary) so it doesn't
    /// shout when usage is low; amber/red kick in as the limit tightens.
    static func labelColor(_ pct: Double?) -> Color {
        guard let p = pct else { return .primary }
        switch p {
        case ..<60: return .primary
        case ..<85: return .orange
        default:    return .red
        }
    }
}

extension Array where Element == UsageMetric {
    /// The "tightest limit" — the metric with the highest utilization %.
    var tightest: UsageMetric? {
        self.max { ($0.pct ?? -1) < ($1.pct ?? -1) }
    }

    /// Back-compat alias for the auto/tightest pick.
    var primary: UsageMetric? { tightest }

    /// The metric to surface in the menu bar for the user's chosen mode. A pinned
    /// choice falls back to `tightest` if that window isn't present on the account
    /// (e.g. no Opus/extra-usage), so the bar never goes blank.
    func primary(for choice: PrimaryMetricChoice) -> UsageMetric? {
        guard let label = choice.metricLabel else { return tightest }
        return first { $0.label == label } ?? tightest
    }
}

enum Format {
    static func shortLabel(_ label: String) -> String {
        switch label {
        case "5-hour":          return "5h"
        case "Weekly":          return "Weekly"
        case "Opus weekly":     return "Opus"
        case "Sonnet weekly":   return "Sonnet"
        case "Extra usage ($)": return "Extra"
        default:                return label
        }
    }

    /// Compact menu bar text. For the dollar overage we show used/limit, e.g.
    /// "$93/100" (or "$93" if no limit is known); percent windows stay
    /// "<short> <pct>%", e.g. "Weekly 8%".
    static func compactPrimary(_ m: UsageMetric) -> String {
        if let dollars = m.dollars {
            let used = Int((m.used ?? dollars).rounded())
            if let limit = m.limit {
                return "$\(used)/\(Int(limit.rounded()))"
            }
            return "$\(used)"
        }
        let pct = Int((m.pct ?? 0).rounded())
        return "\(shortLabel(m.label)) \(pct)%"
    }

    static func pctText(_ pct: Double?) -> String {
        guard let p = pct else { return "—" }
        return p == p.rounded() ? "\(Int(p))%" : String(format: "%.1f%%", p)
    }

    static func dollars(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "$%.2f", value)
    }

    /// Relative reset, e.g. "resets in 2h 14m" / "resets in 14m" / "resets in 5d 3h".
    static func resetString(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let total = Int(date.timeIntervalSince(now))
        if total <= 0 { return "resets now" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "resets in \(days)d \(hours % 24)h"
        }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }
}
