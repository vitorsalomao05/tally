import SwiftUI
import AppKit
import FetcherCore

/// The window-style popover: header, every metric with a gauge + reset time, and
/// a footer (last-updated, manual refresh, quit).
struct UsagePopover: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(.tint)
            Text("Tally").font(.system(size: 14, weight: .semibold))
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch model.state {
        case .loading:
            Text("Updating…").font(.system(size: 11)).foregroundStyle(.secondary)
        case .ok:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(.orange)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.metrics.isEmpty {
            switch model.state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading usage…").foregroundStyle(.secondary)
                }
            case .error(let message):
                // Credential / auth error before any good reading → message, not a number.
                VStack(alignment: .leading, spacing: 6) {
                    Label("Can't read usage", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .ok:
                Text("No usage metrics available.").foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if case .error(let message) = model.state {
                    warningBanner(message) // stale data: show last-good + reason
                }
                ForEach(Array(model.metrics.enumerated()), id: \.offset) { _, metric in
                    metricRow(metric)
                }
            }
        }
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Showing last value — \(message)")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func metricRow(_ metric: UsageMetric) -> some View {
        let isDollar = metric.dollars != nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metric.label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(isDollar
                     ? "\(Format.dollars(metric.used)) / \(Format.dollars(metric.limit))"
                     : Format.pctText(metric.pct))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Thresholds.labelColor(metric.pct))
                    .monospacedDigit()
            }
            ProgressBar(pct: metric.pct ?? 0, color: Thresholds.barColor(metric.pct))
            if let reset = Format.resetString(metric.resetAt) {
                Text(reset).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let updated = model.lastUpdated {
                (Text("Updated ") + Text(updated, style: .relative))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("Never updated").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refreshNow() } label: {
                Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh now")

            // Opens the standard Settings scene (also reachable via ⌘,). Bring
            // the app forward since we're an .accessory (no Dock) agent.
            SettingsLink {
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings…")
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit Tally")
        }
    }
}

/// Simple threshold-colored progress bar (ProgressView's tint can't vary per value cleanly).
struct ProgressBar: View {
    let pct: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, pct / 100)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}
