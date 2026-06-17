import SwiftUI
import FetcherCore

/// One usage gauge — Tally's signature: a label, the percentage (or dollar
/// balance), and a threshold-colored bar. Renders whatever a `UsageMetric`
/// supplies (capability-driven, ADR-007): a `pct` becomes a bar; a `dollars`-only
/// metric (Claude Extra overage) becomes a "$" line with no bar.
struct GaugeRow: View {
    let metric: UsageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metric.label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(valueText)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(valueColor)
            }
            if let pct = metric.pct {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        Capsule()
                            .fill(Theme.color(forPct: pct))
                            .frame(width: geo.size.width * min(max(pct, 0), 100) / 100)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    /// Percentage when present; otherwise a dollar balance (Claude Extra).
    private var valueText: String {
        if let pct = metric.pct { return "\(Int(pct.rounded()))%" }
        if let dollars = metric.dollars { return String(format: "$%.2f", dollars) }
        return "—"
    }

    private var valueColor: Color {
        metric.pct.map(Theme.color(forPct:)) ?? Theme.accent
    }
}
