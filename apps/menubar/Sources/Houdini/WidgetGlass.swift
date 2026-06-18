import SwiftUI
import AppKit

// MARK: - Brand palette (widget)

/// Widget-only brand colors. The menu bar app keeps the single `Color.brand`
/// accent (violet #8B5CF6); the desktop widget leans on the full violet→magenta
/// identity plus a dark "ink" used for the Reduce-Transparency solid fallback.
extension Color {
    /// Convenience hex initializer (0xRRGGBB).
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Brand violet (matches `Color.brand`, #8B5CF6).
    static let brandViolet = Color(hex: 0x8B5CF6)
    /// Brand magenta — the warm end of the identity gradient.
    static let brandMagenta = Color(hex: 0xD946EF)
    /// Solid card color used when Reduce Transparency is on (spec: #15101F).
    static let widgetInk = Color(hex: 0x15101F)
}

// MARK: - Behind-window blur (AppKit material)

/// Thin `NSVisualEffectView` wrapper. The desktop widget uses `.hudWindow` +
/// `.behindWindow` so it samples the wallpaper/desktop behind the panel — the
/// premium "glass" base on macOS 14/15. On macOS 26 we prefer the system
/// `.glassEffect()` (see `GlassCardBackground`); this remains the fallback.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active          // stay blurred even when the app isn't key
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        v.state = .active
    }
}

// MARK: - Glass card background

/// The widget's layered "glass" background, composed as a single reusable
/// modifier so every state (data / loading / needs-auth / error) shares the exact
/// same shell. Honors accessibility:
///
/// • **Reduce Transparency** → a flat, opaque `#15101F` card (same layout, no
///   blur, no translucency) — the required accessible fallback.
/// • **Increase Contrast** → a brighter, more opaque border so the card edge
///   reads against a busy or light wallpaper.
///
/// Rendering path, brightest-first:
/// 1. Reduce Transparency on  → solid ink fill.
/// 2. macOS 26+               → system `.glassEffect()` (Liquid Glass) + violet wash.
/// 3. macOS 14/15            → `NSVisualEffectView(.hudWindow, .behindWindow)` + wash.
struct GlassCardBackground: View {
    var cornerRadius: CGFloat = 22
    /// Force the opaque fallback. The system Reduce-Transparency flag is a get-only
    /// environment value (can't be injected), so the snapshotter sets this to render
    /// the accessible variant.
    var forceSolid: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// In headless `ImageRenderer` snapshots the live blur can't be captured, so a
    /// faithful translucent approximation is drawn instead. Set by the snapshotter.
    @Environment(\.widgetRenderMode) private var renderMode

    private var solid: Bool { reduceTransparency || forceSolid }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    /// Violet→magenta dark wash — ~20% so it tints the glass without going flat gray.
    private var violetWash: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x2A1B4A, alpha: 0.24), Color(hex: 0x3A1340, alpha: 0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// 1px gradient border: lighter at the top (white@14%) fading to white@4% at the
    /// base. Increase Contrast lifts both stops so the edge stays legible.
    private var borderGradient: LinearGradient {
        let top = contrast == .increased ? 0.40 : 0.14
        let bottom = contrast == .increased ? 0.16 : 0.04
        return LinearGradient(
            colors: [Color.white.opacity(top), Color.white.opacity(bottom)],
            startPoint: .top, endPoint: .bottom
        )
    }

    var body: some View {
        Group {
            if solid {
                // Accessible fallback: flat, opaque #15101F — no blur, no wash.
                shape.fill(Color.widgetInk)
            } else {
                ZStack {
                    base
                    violetWash
                }
                .clipShape(shape)
            }
        }
        .overlay(shape.strokeBorder(borderGradient, lineWidth: 1))
    }

    @ViewBuilder
    private var base: some View {
        if renderMode == .snapshot {
            // Headless render approximation of the blurred glass.
            Color(hex: 0x1A1426, alpha: 0.92)
        } else if #available(macOS 26, *) {
            // Liquid Glass (system). Clear so the system effect shows through.
            Color.clear.glassEffect(in: shape)
        } else {
            VisualEffectBlur(material: .hudWindow, blending: .behindWindow)
        }
    }
}

// MARK: - Snapshot render mode (environment)

/// Whether the widget is drawn live (real `NSVisualEffectView` / Liquid Glass) or
/// in a headless `ImageRenderer` snapshot (translucent approximation, since the
/// behind-window blur can't be captured offscreen).
enum WidgetRenderMode { case live, snapshot }

private struct WidgetRenderModeKey: EnvironmentKey {
    static let defaultValue: WidgetRenderMode = .live
}

extension EnvironmentValues {
    var widgetRenderMode: WidgetRenderMode {
        get { self[WidgetRenderModeKey.self] }
        set { self[WidgetRenderModeKey.self] = newValue }
    }
}
