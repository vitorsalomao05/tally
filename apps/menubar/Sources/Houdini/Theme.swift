import SwiftUI

/// The single source of visual truth for the flagship app's two SwiftUI surfaces —
/// the menu bar popover (`UsagePopover`) and the desktop widget (`DesktopWidgetView`)
/// — plus the components they share (`SharedUI`, `WidgetRingGauge`, `WidgetGlass`).
/// Both surfaces read every color, spacing, radius, tracking, and motion value from
/// here so the two can never drift into two different visual languages.
///
/// Design intent: a calm, low-clutter dark-glass card. The accent violet is brand;
/// green/amber/red stay *functional* threshold colors (see `Thresholds`) and are
/// deliberately NOT tokenized here. Accessibility values tuned in the P2 a11y slice
/// (Dynamic Type via `scaledFont`, the brighter AA secondary-text tone, and the
/// Increase-Contrast lifts) are folded IN as tokens so they remain the single source
/// and are preserved, not reverted.
enum Theme {

    // MARK: - Color tokens

    /// Every non-functional color used on the glass cards. Brand accent + the glass
    /// "ink"/wash/border hexes (previously buried in `GlassCardBackground`) and the
    /// family of faint-white overlays (track / hairline / hover / skeleton), which
    /// were five near-identical raw opacities scattered across the surfaces.
    enum Colors {
        /// Brand accent violet (#8B5CF6) — the app tint. Aliases `Color.brand`.
        static let accent = Color.brand
        /// Warm end of the brand identity gradient (#D946EF).
        static let accentMagenta = Color.brandMagenta
        /// Opaque card fill for the Reduce-Transparency fallback (#15101F).
        static let ink = Color.widgetInk

        /// Dark violet→magenta wash stops layered over the blur (~20% so the glass
        /// tints without going flat gray). Kept here as the one place the glass hues live.
        static let washTop = Color(hex: 0x2A1B4A, alpha: 0.24)
        static let washBottom = Color(hex: 0x3A1340, alpha: 0.18)
        /// Headless `ImageRenderer` stand-in for the live blur (can't capture offscreen).
        static let snapshotBase = Color(hex: 0x1A1426, alpha: 0.92)
        /// Translucent ink scrim the popover lays over the host window material.
        static let hostScrim = Color.widgetInk.opacity(0.6)

        /// 1px card border gradient (top→bottom). Increase Contrast lifts both stops so
        /// the edge holds against a busy or light wallpaper (a11y slice).
        static func borderTop(increasedContrast: Bool) -> Color {
            Color.white.opacity(increasedContrast ? 0.40 : 0.14)
        }
        static func borderBottom(increasedContrast: Bool) -> Color {
            Color.white.opacity(increasedContrast ? 0.16 : 0.04)
        }

        /// Unified faint-white overlays on the dark glass. One named tone per role
        /// instead of five stray opacities (0.05–0.10) sprinkled across both surfaces.
        static let track = Color.white.opacity(0.08)      // gauge + progress-bar track
        static let hairline = Color.white.opacity(0.07)   // popover content↔footer divider
        static let hover = Color.white.opacity(0.05)      // widget card hover lift
        static let highlight = Color.white.opacity(0.10)  // footer icon active highlight
        static let skeleton = Color.white.opacity(0.06)   // loading placeholder fill

        /// AA-legible secondary/caption tone on the #15101F glass — brighter than the
        /// system `.secondary` so 9–12pt type clears WCAG AA, and lifts under Increase
        /// Contrast (a11y slice: the contrast path raises TEXT, not just the border).
        static func secondaryText(increasedContrast: Bool) -> Color {
            Color.white.opacity(increasedContrast ? 0.9 : 0.66)
        }

        /// Header status glyph tones (kept legible on the dark card, not `.secondary`).
        static let statusLoading = Color.white.opacity(0.55) // calm gray loading dot
        static let statusMutedIcon = Color.white.opacity(0.7) // signed-out person glyph

        /// Stale / last-value warning accent (amber). Functional, but shared so the
        /// popover banner and widget chip pull the same hue.
        static let warning = Color.orange
    }

    // MARK: - Spacing tokens

    /// The card rhythm, named by role. Exact values from the a11y-tuned layout — this
    /// centralizes the scattered literals (the ring gap `16` alone appeared in three
    /// files) without disturbing Dynamic Type sizing.
    enum Spacing {
        static let hairline: CGFloat = 1    // divider thickness
        static let footer: CGFloat = 4      // popover footer icon gap
        static let rowInternal: CGFloat = 5 // label / bar / reset within one row
        static let tight: CGFloat = 6       // ring-gauge vstack + stale-banner icon gap
        static let header: CGFloat = 7      // wordmark ↔ status dot
        static let state: CGFloat = 8       // centered empty/error/needs-auth internal
        static let sectionCompact: CGFloat = 10 // compact-widget rhythm + popover rows
        static let section: CGFloat = 12    // primary vertical rhythm
        static let cardPadding: CGFloat = 14 // popover + compact-widget card inset
        static let ringStack: CGFloat = 14  // vertical gap: ring group → spend
        static let ringGap: CGFloat = 16    // horizontal gap between the two rings
        static let cardPaddingLarge: CGFloat = 18 // regular-widget card inset
    }

    // MARK: - Corner radii

    /// One rounded-card family so the two surfaces share a rounding language. The
    /// popover previously sat at 14 — noticeably squarer than the widget's 20/24; it
    /// now joins the family at `card` (20).
    enum Radius {
        static let card: CGFloat = 20      // popover + compact widget
        static let cardLarge: CGFloat = 24 // regular widget
        static let chip: CGFloat = 8       // stale banner
        static let control: CGFloat = 7    // footer icon hit-target
        static let bar: CGFloat = 5        // skeleton placeholder bar
    }

    // MARK: - Typography

    enum Typography {
        /// Letter-spacing for tiny uppercased labels (ring title, spend caption). Was
        /// 0.5 on the ring but 0.4 on the spend label — unified to one value.
        static let microTracking: CGFloat = 0.5
    }

    // MARK: - Motion

    /// Animation timings (all already gated by Reduce Motion at the call sites). The
    /// two hover durations (0.12 / 0.15) are unified to one `hover`.
    enum Motion {
        static let hover: Double = 0.15   // card + footer hover
        static let value: Double = 0.18   // numeric-text / ring-fill transitions
        static let pulse: Double = 1.0    // loading skeleton breathe
    }
}
