import SwiftUI
import AppKit

/// The Settings panel — reachable from the gear in the popover footer (a
/// `SettingsLink`) or the standard ⌘, shortcut.
///
/// The controls are built from pure SwiftUI primitives (shapes + text + tap
/// gestures) rather than native `Picker`/`Toggle`. Two reasons: they adapt to
/// light/dark via semantic colors, and — unlike AppKit-backed controls — they
/// render faithfully through `ImageRenderer` for the docs screenshots
/// (`ImageRenderer` draws native controls as an "unsupported" placeholder).
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var launch: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(.tint)
                Text("Tally Settings").font(.system(size: 15, weight: .semibold))
            }

            section("Menu bar") {
                metricList
                caption("Which figure shows in the menu bar.")
            }

            section("Refresh") {
                row("Interval") { intervalSegments }
                caption("Applied live — the running timer reschedules, no restart.")
            }

            section("General") {
                launchRow
                if let error = launch.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Primary metric (radio list)

    private var metricList: some View {
        VStack(spacing: 3) {
            ForEach(PrimaryMetricChoice.allCases) { choice in
                let selected = settings.primaryMetric == choice
                HStack(spacing: 8) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Text(choice.displayName).font(.system(size: 13)).foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { settings.primaryMetric = choice }
            }
        }
    }

    // MARK: - Refresh interval (segmented)

    private var intervalSegments: some View {
        HStack(spacing: 0) {
            ForEach(AppSettings.allowedIntervals, id: \.self) { iv in
                let selected = settings.refreshInterval == iv
                Text("\(Int(iv))s")
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .frame(width: 54, height: 24)
                    .background(selected ? Color.accentColor : Color.secondary.opacity(0.12))
                    .contentShape(Rectangle())
                    .onTapGesture { settings.refreshInterval = iv }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.25)))
    }

    // MARK: - Launch at login (switch)

    private var launchRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at login").font(.system(size: 13))
                Text(launch.statusText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            switchControl(isOn: launch.isEnabled)
                .contentShape(Rectangle())
                .onTapGesture { launch.setEnabled(!launch.isEnabled) }
        }
    }

    private func switchControl(isOn: Bool) -> some View {
        Capsule()
            .fill(isOn ? Color.green : Color.secondary.opacity(0.35))
            .frame(width: 42, height: 24)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                    .shadow(radius: 0.5)
            }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row<Trailing: View>(_ label: String,
                                     @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 12)
            trailing()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
