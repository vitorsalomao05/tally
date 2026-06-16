import SwiftUI
import FetcherCore

/// The content shown in the menu bar itself: primary metric, compact + colored.
/// The metric shown follows `settings.primaryMetric`; changing it in Settings
/// updates the bar live (this view observes `settings`).
struct MenuBarLabelContent: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        if let primary = model.metrics.primary(for: settings.primaryMetric) {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                Text(Format.compactPrimary(primary))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Thresholds.menuBarColor(primary.pct))
        } else if model.state.isSignedOut {
            // No Claude credential → invite sign-in from the menu bar.
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                Text("Sign in")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
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
