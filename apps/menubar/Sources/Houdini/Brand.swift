import SwiftUI

/// Houdini brand accent — violet #8B5CF6. Applied as the app `.tint` so tinted
/// controls (the header glyph, prominent buttons, pickers) read as Houdini
/// rather than the system blue. Usage gauges keep their functional
/// green/amber/red thresholds — those are deliberately not the brand color.
extension Color {
    static let brand = Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)
}
