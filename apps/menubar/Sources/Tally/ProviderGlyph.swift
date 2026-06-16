import SwiftUI
import AppKit

/// The provider mark shown at the left of the menu bar label. Centralized in one
/// place so it can become provider-aware later (per-account icon); today it is
/// fixed to Claude. The artwork (`Resources/ClaudeGlyph.pdf`) is loaded as a
/// TEMPLATE image — only its alpha matters — so AppKit/SwiftUI tint it to the
/// menu bar's foreground color (black on a light bar, white on a dark bar).
struct ProviderGlyph: View {
    /// Glyph height in points — sized to sit alongside the 13pt label text.
    var height: CGFloat = 15

    var body: some View {
        if let image = ProviderGlyph.claude {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
                .foregroundStyle(.primary) // adaptive: follows the bar (light/dark)
                .accessibilityLabel("Claude")
        } else {
            // Asset missing (e.g. run outside the .app bundle) — stay visible.
            Image(systemName: "sparkles")
                .foregroundStyle(.primary)
                .accessibilityLabel("Claude")
        }
    }

    /// The Claude template image, loaded once from the app bundle. Setting
    /// `isTemplate = true` is what lets the system tint it for the bar appearance.
    static let claude: NSImage? = loadTemplate(named: "ClaudeGlyph")

    private static func loadTemplate(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}
