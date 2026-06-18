import SwiftUI
import FetcherCore

/// A three-quarter (270°) ring gauge for a percentage window (5-hour / Weekly).
/// The 90° gap sits centered at the bottom; the fill grows clockwise from the
/// bottom-left. Track is white@8%; the fill uses the shared green/amber/red
/// threshold scale (`Thresholds.barColor`) so the widget reads identically to the
/// popover. A hero numeral sits in the center with a tiny window label beneath it,
/// and the relative reset ("resets in 2h 14m") prints below the ring.
struct WidgetRingGauge: View {
    let title: String          // short window label, e.g. "5-hour", "Weekly"
    let pct: Double?           // 0–100; nil → dashes
    let resetText: String?     // "resets in 2h 14m"
    var diameter: CGFloat = 96
    /// Loading skeleton: track only, no numeral/fill.
    var isPlaceholder: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 270° of the circle is drawn; rotate 135° so the open quarter is at the bottom.
    private let sweep = 0.75
    private var fraction: Double { max(0, min(1, (pct ?? 0) / 100)) }
    private var lineWidth: CGFloat { max(6, min(13, diameter * 0.12)) }
    private var fillColor: Color { isPlaceholder ? .clear : Thresholds.barColor(pct) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Track
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(135))

                // Threshold fill
                if !isPlaceholder {
                    Circle()
                        .trim(from: 0, to: sweep * fraction)
                        .stroke(fillColor,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: fraction)
                }

                // Center: hero numeral + window label
                VStack(spacing: 1) {
                    if isPlaceholder {
                        Text("—")
                            .font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(numeral)
                            .font(.system(size: diameter * 0.27, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: pct)
                    }
                    Text(title.uppercased())
                        .font(.system(size: max(8, diameter * 0.095), weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, lineWidth)
            }
            .frame(width: diameter, height: diameter)

            if let resetText {
                Text(resetText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var numeral: String {
        guard let pct else { return "—" }
        return "\(Int(pct.rounded()))%"
    }

    private var accessibilityValue: String {
        guard let pct else { return "no reading" }
        let base = "\(Int(pct.rounded())) percent used"
        return resetText.map { "\(base), \($0)" } ?? base
    }
}
