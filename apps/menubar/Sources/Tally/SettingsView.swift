import SwiftUI
import AppKit

/// The Settings panel — reachable from the gear in the popover footer (a
/// `SettingsLink`) or the standard ⌘, shortcut.
///
/// The controls are **native** AppKit-backed SwiftUI primitives (`Picker`,
/// `Toggle`): they carry full keyboard navigation, VoiceOver labels and the
/// system focus ring for free, which matters more than pixel control on a
/// settings screen. Trade-off: `ImageRenderer` draws native controls as an
/// "unsupported" placeholder, so the `settings-*.png` docs screenshots are now
/// placeholders (the popover screenshot — pure shapes — still renders faithfully).
/// We deliberately do **not** reintroduce custom controls just to satisfy the
/// renderer; native UX/accessibility wins.
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
                metricPicker
                caption("Which figure shows in the menu bar.")
            }

            section("Refresh") {
                row("Interval") { intervalPicker }
                caption("Applied live — the running timer reschedules, no restart.")
            }

            section("General") {
                launchToggle
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

    // MARK: - Primary metric (native radio group)

    private var metricPicker: some View {
        Picker("Primary metric", selection: $settings.primaryMetric) {
            ForEach(PrimaryMetricChoice.allCases) { choice in
                Text(choice.displayName).tag(choice)
            }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
        .accessibilityLabel("Menu bar metric")
    }

    // MARK: - Refresh interval (native segmented)

    private var intervalPicker: some View {
        Picker("Interval", selection: $settings.refreshInterval) {
            ForEach(AppSettings.allowedIntervals, id: \.self) { iv in
                Text("\(Int(iv))s").tag(iv)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Refresh interval")
    }

    // MARK: - Launch at login (native switch)

    private var launchToggle: some View {
        Toggle(isOn: Binding(
            get: { launch.isEnabled },
            set: { launch.setEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at login").font(.system(size: 13))
                Text(launch.statusText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(.green)
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
