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

    /// Numeric-label color (popover rows) — "normal" stays adaptive (primary) so
    /// it doesn't shout when usage is low; amber/red kick in as the limit tightens.
    static func labelColor(_ pct: Double?) -> Color {
        guard let p = pct else { return .primary }
        switch p {
        case ..<60: return .primary
        case ..<85: return .orange
        default:    return .red
        }
    }

    /// Menu bar label color — full green/amber/red threshold scale (matches the
    /// popover gauges) so the at-a-glance number reads "comfortable" when low.
    /// Stays adaptive (primary) only when there's no percentage to color.
    static func menuBarColor(_ pct: Double?) -> Color {
        guard let p = pct else { return .primary }
        switch p {
        case ..<60: return .green
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

    /// The tightest *percentage* window — excludes the dollar overage so a missing
    /// pinned window falls back to a real "%" limit rather than the "$" figure.
    var tightestPercentage: UsageMetric? {
        filter { $0.dollars == nil }.tightest
    }

    /// Back-compat alias for the auto/tightest pick.
    var primary: UsageMetric? { tightest }

    /// The metric to surface in the menu bar for the user's chosen mode.
    /// • `auto` → the tightest limit (may be the dollar overage — that's its job).
    /// • a pinned window → that exact window; if it isn't on the account (rare,
    ///   e.g. no 5-hour reading yet) fall back to the tightest *percentage* window
    ///   so the bar stays a clean "<window> N%", only resorting to the dollar
    ///   overage when there's no percentage window at all.
    func primary(for choice: PrimaryMetricChoice) -> UsageMetric? {
        guard let label = choice.metricLabel else { return tightest }
        if let exact = first(where: { $0.label == label }) { return exact }
        return tightestPercentage ?? tightest
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

    /// Menu bar text: percent-only for "%" windows ("6%"), used/limit for the
    /// dollar overage ("$93/100"). The metric name is intentionally dropped — the
    /// bar shows just the number; the popover keeps the full labels.
    static func barLabel(_ m: UsageMetric) -> String {
        if let dollars = m.dollars {
            let used = Int((m.used ?? dollars).rounded())
            if let limit = m.limit {
                return "$\(used)/\(Int(limit.rounded()))"
            }
            return "$\(used)"
        }
        return "\(Int((m.pct ?? 0).rounded()))%"
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
