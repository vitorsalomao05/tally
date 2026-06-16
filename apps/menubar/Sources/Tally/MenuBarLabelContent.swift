import SwiftUI
import FetcherCore

/// The content shown in the menu bar itself: primary metric, compact + colored.
struct MenuBarLabelContent: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        if let primary = model.metrics.primary {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                Text(Format.compactPrimary(primary))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Thresholds.labelColor(primary.pct))
        } else {
            // No data yet, or an error before any good reading.
            HStack(spacing: 4) {
                Image(systemName: model.state.isError ? "exclamationmark.triangle.fill"
                                                      : "gauge.with.dots.needle.67percent")
                Text(model.state.isError ? "—" : "…")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(model.state.isError ? Color.orange : Color.primary)
        }
    }
}
