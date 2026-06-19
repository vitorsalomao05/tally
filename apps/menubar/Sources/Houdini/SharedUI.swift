import SwiftUI
import FetcherCore

// Components shared by the desktop widget (`DesktopWidgetView`) and the menu bar
// popover (`UsagePopover`) so the two finishes never drift: the brand wordmark,
// the status dot, the needs-auth / error / loading states, the metric row, and the
// threshold-colored progress bar. Glass/material styling lives in `WidgetGlass`;
// gauges in `WidgetRingGauge`; threshold colors + formatting in `Formatting`.

// MARK: - Brand wordmark

/// The "Houdini" wordmark in the violet→magenta brand gradient. Sized by the host
/// (the widget header is compact at 13pt; the popover header is a touch larger).
struct BrandWordmark: View {
    var size: CGFloat = 13

    var body: some View {
        Text("Houdini")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(
                LinearGradient(colors: [.brandViolet, .brandMagenta],
                               startPoint: .leading, endPoint: .trailing)
            )
    }
}

// MARK: - Status dot

/// The header status indicator: a green dot when fresh, a calm gray dot while
/// loading (no spinner), an amber triangle on error, a person glyph when signed
/// out. Shared so the widget and popover read identically.
struct StatusDot: View {
    let state: UsageModel.State

    @ViewBuilder
    var body: some View {
        switch state {
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
}

// MARK: - Needs-auth CTA

/// "Connect Claude" empty state: the wand glyph in the brand gradient, a one-line
/// invitation, and the sign-in button (present only with a live session — headless
/// snapshots pass nil). Centered; the caller sizes the surrounding frame.
struct NeedsAuthView: View {
    var session: ClaudeSession?

    var body: some View {
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
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Error state

/// Generic "can't read usage" empty state — a real fetch/credential failure (not a
/// sign-in prompt, which is `NeedsAuthView`). Centered; the caller sizes the frame.
struct ErrorStateView: View {
    let message: String

    var body: some View {
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
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Loading skeleton

/// The shared loading skeleton: two track-only ring gauges over a placeholder bar,
/// with a calm pulse (disabled under Reduce Motion). No spinner — the widget and
/// popover both use this so loading reads the same everywhere. The caller frames it.
struct RingPairSkeleton: View {
    var diameter: CGFloat = 92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                WidgetRingGauge(title: "5h", pct: nil, resetText: nil,
                                diameter: diameter, isPlaceholder: true)
                WidgetRingGauge(title: "Weekly", pct: nil, resetText: nil,
                                diameter: diameter, isPlaceholder: true)
            }
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.06))
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
        .modifier(SkeletonPulse(enabled: !reduceMotion))
    }
}

/// Calm loading pulse (opacity), disabled under Reduce Motion. Shared by every
/// skeleton so the cadence matches across surfaces.
struct SkeletonPulse: ViewModifier {
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

// MARK: - Metric row

/// A compact metric line — label, threshold-colored value, a thin progress bar, and
/// the relative reset. Uses the same threshold scale + `numericText` transition as
/// the widget's gauges so the popover and widget never drift. Used by the popover
/// for the windows not promoted to hero rings (e.g. Sonnet/Opus weekly, Extra $).
struct MetricRow: View {
    let metric: UsageMetric

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isDollar = metric.dollars != nil
        let amount = metric.used ?? metric.dollars
        let label = isDollar ? "Extra usage" : metric.label
        let value = isDollar
            ? (metric.limit.map { "\(Format.dollars(amount)) / \(Format.dollars($0))" }
                ?? Format.dollars(amount))
            : Format.pctText(metric.pct)
        // The bar represents a limit being filled — hide it when there's nothing to
        // fill (a dollar overage with no known budget), exactly like the widget's
        // spend bar (`DesktopWidgetView.spendBlock`), rather than drawing an empty
        // track that reads as "no spend".
        let barPct: Double? = {
            if isDollar {
                guard let limit = metric.limit, limit > 0, let used = amount else { return nil }
                return min(100, used / limit * 100)
            }
            return metric.pct
        }()

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Thresholds.labelColor(metric.pct))
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: value)
            }
            if let barPct {
                ProgressBar(pct: barPct, color: Thresholds.barColor(metric.pct))
                    .frame(height: 4)
            }
            if let reset = Format.resetString(metric.resetAt) {
                Text(reset).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Progress bar

/// Threshold-colored progress bar (`ProgressView`'s tint can't vary per value
/// cleanly). Shared by the popover rows and the widget's spend bar.
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

// MARK: - Footer hover

/// Subtle hover affordance for the popover footer icons: the glyph brightens from
/// secondary to full and a faint rounded highlight fades in. Motion is gated by
/// Reduce Motion (the state still flips, just without the transition).
struct FooterHover: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .opacity(hovering ? 1.0 : 0.6)
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.10 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { h in
                if reduceMotion { hovering = h }
                else { withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
            }
    }
}

extension View {
    /// Apply the shared popover-footer hover affordance to an icon button's label.
    func footerHover() -> some View { modifier(FooterHover()) }
}
