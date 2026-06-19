import SwiftUI
import AppKit
import FetcherCore

/// The menu bar popover, finished to the same visual language as the desktop
/// widget: a dark glass card with the brand wordmark header, two hero ring gauges
/// (5-hour / Weekly) on top, the remaining windows as compact rows below, and a
/// footer of actions. It shares the widget's components (wordmark, status dot, ring
/// gauges, skeleton, needs-auth, glass styling) so the two never drift.
///
/// Glass: the popover is hosted by `MenuBarExtra(.window)`, which already supplies a
/// system material — so it uses `GlassCardBackground(surface: .hostMaterial)`, which
/// layers the violet wash + gradient hairline (and a translucent ink scrim, not a
/// second blur) over that material. The card is forced dark so it reads as the same
/// dark glass in either system appearance, exactly like the widget. Accessibility:
/// Reduce Transparency → solid `#15101F`; Increase Contrast → brighter hairline
/// (both via `GlassCardBackground`); Reduce Motion gates every animation.
struct UsagePopover: View {
    @ObservedObject var model: UsageModel
    /// Optional so headless renders (`--snapshot`) can build the popover without an
    /// auth session; the sign-in CTA only appears when a session is present.
    var session: ClaudeSession?
    /// Force the opaque Reduce-Transparency card (snapshots only — the live flag is
    /// read from the environment by `GlassCardBackground`), mirroring the widget.
    var forceReduceTransparency: Bool = false

    /// Fixed for the popover's fixed width; the skeleton reuses it so loading matches
    /// the populated layout.
    private let ringDiameter: CGFloat = 84
    private let width: CGFloat = 344
    private let corner: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            // A faint hairline divides the data from the actions, echoing the glass edge.
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            footer
        }
        .padding(14)
        .frame(width: width)
        .background(GlassCardBackground(cornerRadius: corner,
                                        forceSolid: forceReduceTransparency,
                                        surface: .hostMaterial))
        // The card reads as dark glass in either system appearance, like the widget.
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            BrandWordmark(size: 15)
            Spacer()
            StatusDot(state: model.state)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.metrics.isEmpty {
            emptyState
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if case .error(let message) = model.state {
                    staleBanner(message) // stale data: show last-good + reason
                }
                if !heroRings.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(heroRings.enumerated()), id: \.offset) { _, m in
                            WidgetRingGauge(title: Format.shortLabel(m.label), pct: m.pct,
                                            resetText: Format.resetString(m.resetAt),
                                            diameter: ringDiameter)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                if !rowMetrics.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Array(rowMetrics.enumerated()), id: \.offset) { _, m in
                            MetricRow(metric: m)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.state {
        case .loading:
            RingPairSkeleton(diameter: ringDiameter)
        case .signedOut:
            NeedsAuthView(session: session)
        case .error(let message):
            // Credential/auth error before any good reading → CTA or message, not a number.
            if model.needsLogin { NeedsAuthView(session: session) }
            else { ErrorStateView(message: message) }
        case .ok:
            Text("No usage metrics available.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Stale banner: a restyled glass chip kept when an error lands on top of a
    /// last-good reading (the rings/rows still show the previous value).
    private func staleBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(.orange)
            Text("Showing last value — \(message)")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Group {
                if let updated = model.lastUpdated {
                    (Text("Updated ") + Text(updated, style: .relative))
                } else {
                    Text("Never updated")
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)

            Spacer()

            Button { model.refreshNow() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .footerHover()
            .help("Refresh now")

            // Opens the standard Settings scene (also reachable via ⌘,). Bring the app
            // forward since we're an .accessory (no Dock) agent.
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .footerHover()
            .help("Settings…")
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .footerHover()
            .help("Quit Houdini")
        }
    }

    // MARK: - Metric selection (shared with the widget via `[UsageMetric]`)

    /// The two hero rings: 5-hour → Weekly (or the tightest windows available).
    private var heroRings: [UsageMetric] { Array(model.metrics.rankedRingWindows.prefix(2)) }

    /// Rows below the rings: the percentage windows not promoted to a ring (e.g.
    /// Sonnet/Opus weekly), then the dollar overage (Extra usage).
    private var rowMetrics: [UsageMetric] {
        Array(model.metrics.rankedRingWindows.dropFirst(2))
            + (model.metrics.dollarOverage.map { [$0] } ?? [])
    }
}
