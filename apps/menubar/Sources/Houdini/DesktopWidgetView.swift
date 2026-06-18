import SwiftUI
import AppKit
import FetcherCore

/// The desktop widget card. A squircle glass panel that mirrors the menu bar's
/// data (same `UsageModel`, same 60s refresh) as draggable, resizable desktop
/// furniture. Two responsive breakpoints reflow the content:
///
/// • **regular** (≥260pt wide) — two ¾-ring gauges side by side + a spend block.
/// • **compact** (<260pt wide) — one hero ring + spend + a one-line secondary.
///
/// States: loading skeleton (no spinner), needs-auth CTA (no fake 0%), error,
/// last-value (stale data kept on error), and a subtle hover. Accessibility is
/// handled in `GlassCardBackground` (Reduce Transparency → solid, Increase
/// Contrast → border) and per-view (`accessibilityReduceMotion` gates animation).
struct DesktopWidgetView: View {
    @ObservedObject var model: UsageModel
    /// Present in the live app (drives the "Connect Claude" CTA); nil in headless
    /// snapshots without an auth session.
    var session: ClaudeSession?
    /// Force the opaque Reduce-Transparency card (snapshots only — the live flag is
    /// read from the environment).
    var forceReduceTransparency: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    /// Transparent margin around the squircle so the drop shadow has room to render
    /// (the card itself stays opaque; the panel window is clear).
    private let shadowInset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let cardWidth = max(0, geo.size.width - shadowInset * 2)
            let compact = cardWidth < 260
            let corner: CGFloat = compact ? 20 : 24

            card(compact: compact, size: CGSize(width: cardWidth,
                                                height: max(0, geo.size.height - shadowInset * 2)),
                 corner: corner)
                .frame(width: cardWidth, height: max(0, geo.size.height - shadowInset * 2))
                .frame(width: geo.size.width, height: geo.size.height) // center within window
        }
    }

    // MARK: - Card shell

    private func card(compact: Bool, size: CGSize, corner: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content(compact: compact, size: size)
            .padding(compact ? 14 : 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(GlassCardBackground(cornerRadius: corner, forceSolid: forceReduceTransparency))
            .overlay {
                // Subtle hover lift — a faint top highlight, never animating shadow.
                if hovering {
                    shape.fill(Color.white.opacity(0.05))
                }
            }
            .clipShape(shape)
            .compositingGroup()
            // Two stacked shadows: a deep soft one + a tight contact one (static).
            // Tuned to fall within the 16pt transparent margin without clipping.
            .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 8)
            .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
            .contentShape(Rectangle())
            .onHover { h in
                if reduceMotion { hovering = h }
                else { withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
            }
            // The glass card is dark in both appearances, so its content is always
            // light — this keeps text at AA contrast even over a light wallpaper.
            .environment(\.colorScheme, .dark)
    }

    // MARK: - Content router

    @ViewBuilder
    private func content(compact: Bool, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            header
            if model.metrics.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if compact {
                    compactBody(size: size)
                } else {
                    regularBody(size: size)
                }
                Spacer(minLength: 0)
                footer
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            Text("Houdini")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.brandViolet, .brandMagenta],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Spacer()
            statusDot
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch model.state {
        case .ok:
            Circle().fill(.green).frame(width: 7, height: 7)
        case .loading:
            Circle().fill(Color.secondary.opacity(0.6)).frame(width: 7, height: 7)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundStyle(.orange)
        case .signedOut:
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Regular body (two rings + spend)

    private func regularBody(size: CGSize) -> some View {
        let rings = Array(ringMetrics.prefix(2))
        let ringD = min((size.width - 36 - 16) / max(1, CGFloat(rings.count)),
                        size.height * 0.46)
            .clamped(to: 60...150)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ForEach(Array(rings.enumerated()), id: \.offset) { _, m in
                    WidgetRingGauge(title: Format.shortLabel(m.label), pct: m.pct,
                                    resetText: Format.resetString(m.resetAt), diameter: ringD)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            if let dollar = dollarMetric { spendBlock(dollar, compact: false) }
        }
    }

    // MARK: - Compact body (one ring + spend + secondary line)

    private func compactBody(size: CGSize) -> some View {
        let primary = ringMetrics.first
        let ringD = min(size.width - 28, size.height * 0.50).clamped(to: 68...150)
        return VStack(alignment: .leading, spacing: 8) {
            if let primary {
                WidgetRingGauge(title: Format.shortLabel(primary.label), pct: primary.pct,
                                resetText: Format.resetString(primary.resetAt), diameter: ringD)
                    .frame(maxWidth: .infinity)
            }
            if let dollar = dollarMetric { spendBlock(dollar, compact: true) }
            if let secondary = secondaryLine {
                Text(secondary).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: - Spend block ($ hero + optional budget bar)

    private func spendBlock(_ m: UsageMetric, compact: Bool) -> some View {
        let amount = m.used ?? m.dollars
        let label = Format.shortLabel(m.label) == "Extra" ? "Extra usage" : m.label
        return VStack(alignment: .leading, spacing: 5) {
            if compact {
                // Compact: label as a tiny caption above; the hero on its own line so
                // the dollar figure is never clipped.
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold)).tracking(0.4)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    spendHero(amount, m: m, size: 22)
                    if let limit = m.limit {
                        Text("/ \(Format.dollars(limit))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .monospacedDigit().fixedSize()
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    spendHero(amount, m: m, size: 26)
                    if let limit = m.limit {
                        Text("/ \(Format.dollars(limit))")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .monospacedDigit().fixedSize()
                    }
                    Spacer(minLength: 8)
                    Text(label)
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            if let limit = m.limit, limit > 0, let used = amount {
                // Thin budget bar — only when a real budget exists.
                ProgressBar(pct: min(100, used / limit * 100), color: Thresholds.barColor(m.pct))
                    .frame(height: 4)
            }
        }
    }

    /// The spend hero numeral — `fixedSize` so it is never truncated, whatever the
    /// breakpoint or trailing label width.
    private func spendHero(_ amount: Double?, m: UsageMetric, size: CGFloat) -> some View {
        Text(Format.dollars(amount))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Thresholds.labelColor(m.pct))
            .lineLimit(1).fixedSize()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: amount)
    }

    // MARK: - Footer (last-updated)

    @ViewBuilder
    private var footer: some View {
        if isStale {
            staleChip
        } else if let updated = model.lastUpdated {
            (Text("Updated ") + Text(updated, style: .relative))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var staleChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9))
            Text("Showing last value").font(.system(size: 9))
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Empty states (loading / needs-auth / error)

    @ViewBuilder
    private var emptyState: some View {
        switch model.state {
        case .loading:
            loadingSkeleton
        case .signedOut:
            needsAuth
        case .error(let message):
            if model.needsLogin { needsAuth } else { errorState(message) }
        case .ok:
            Text("No usage metrics available.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Skeleton: track-only rings + a placeholder bar. No spinner; a calm pulse
    /// only when motion is allowed.
    private var loadingSkeleton: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                WidgetRingGauge(title: "5h", pct: nil, resetText: nil, diameter: 92, isPlaceholder: true)
                WidgetRingGauge(title: "Weekly", pct: nil, resetText: nil, diameter: 92, isPlaceholder: true)
            }
            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)).frame(height: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(SkeletonPulse(enabled: !reduceMotion))
    }

    private var needsAuth: some View {
        VStack(spacing: 9) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 26))
                .foregroundStyle(LinearGradient(colors: [.brandViolet, .brandMagenta],
                                                startPoint: .top, endPoint: .bottom))
            Text("Connect Claude")
                .font(.system(size: 14, weight: .semibold))
            Text("Sign in to see your Claude usage and spend.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let session {
                Button { session.signIn() } label: {
                    Text("Connect Claude").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.brandViolet)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22)).foregroundStyle(.orange)
            Text("Can't read usage")
                .font(.system(size: 13, weight: .medium))
            Text(message)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metric selection

    /// Percentage windows (no dollar overage), ordered 5-hour → Weekly → the rest
    /// by tightness, so the two prominent rings are the figures users glance at.
    private var ringMetrics: [UsageMetric] {
        let pct = model.metrics.filter { $0.dollars == nil }
        let priority: [String: Int] = ["5-hour": 0, "Weekly": 1]
        return pct.sorted { a, b in
            let pa = priority[a.label] ?? 9, pb = priority[b.label] ?? 9
            if pa != pb { return pa < pb }
            return (a.pct ?? -1) > (b.pct ?? -1)
        }
    }

    private var dollarMetric: UsageMetric? { model.metrics.first { $0.dollars != nil } }

    /// Compact mode's one-line summary of the windows not shown as the hero ring.
    private var secondaryLine: String? {
        let rest = ringMetrics.dropFirst()
        guard !rest.isEmpty else { return nil }
        return rest.map { "\(Format.shortLabel($0.label)) \(Int(($0.pct ?? 0).rounded()))%" }
            .joined(separator: " · ")
    }

    private var isStale: Bool {
        if case .error = model.state { return !model.metrics.isEmpty }
        return false
    }
}

/// Calm loading pulse (opacity), disabled under Reduce Motion.
private struct SkeletonPulse: ViewModifier {
    let enabled: Bool
    @State private var dim = false
    func body(content: Content) -> some View {
        content
            .opacity(enabled ? (dim ? 0.55 : 1.0) : 1.0)
            .animation(enabled ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : nil,
                       value: dim)
            .onAppear { if enabled { dim = true } }
    }
}

extension Comparable {
    /// Clamp a value into a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
