import SwiftUI

/// Tally's dark/blue palette — kept in lockstep with the website's design tokens
/// (`site/src/styles/global.css`) so the app, the widget, and tally.salomao.org
/// read as one product. Hex values mirror the CSS custom properties.
///
/// Lives in `Shared/` so BOTH the app and the widget targets compile it (the
/// widget's gauges use the same threshold colors as the app).
enum Theme {
    static let bg        = Color(hex: 0x0a0b0e) // --color-bg
    static let surface   = Color(hex: 0x14161b) // --color-surface
    static let surface2  = Color(hex: 0x1b1e26) // --color-surface-2
    static let border    = Color(hex: 0x232733) // --color-border
    static let text      = Color(hex: 0xe7e9ee) // --color-text
    static let muted     = Color(hex: 0x9aa3b2) // --color-muted
    static let accent    = Color(hex: 0x3b82f6) // --color-accent

    // Threshold colors for the gauges (green → amber → red), same as the site.
    static let ok        = Color(hex: 0x34d399) // --color-ok
    static let warn      = Color(hex: 0xf5a623) // --color-warn
    static let danger    = Color(hex: 0xf2555f) // --color-danger

    /// The gauge color for a utilization percentage. Mirrors the menu bar app's
    /// thresholds so every surface colors a number the same way.
    static func color(forPct pct: Double) -> Color {
        switch pct {
        case ..<60:  return ok
        case ..<85:  return warn
        default:     return danger
        }
    }
}

extension Color {
    /// Build a `Color` from a `0xRRGGBB` literal (opaque). Tiny helper so the
    /// palette above reads like the CSS it mirrors.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue:  Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}
