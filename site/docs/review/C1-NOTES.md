# C1 — Routed screens (site only)

Restructured the home from one long 8-section scroll into **separate, viewport-first routes**, with the
home reworked as a **download page** whose single job is to get Houdini installed. App/popover untouched.
Production and the v0.3.0 release are untouched — this round ships to a Vercel **preview** only.

## Architecture

| Route | Screen | Signature interaction |
|-------|--------|-----------------------|
| `/` | Download-focused home | Dominant install one-liner + Copy, product shot, providers line, trust line, version chip |
| `/reveals` | What it reveals | APG **tabs** — Limits · Sessions · Tokens · Spend, animated panel swap + sliding indicator |
| `/surfaces` | Where it shows up | Segmented **toggle** — Menu bar ⇄ Desktop widget, visual morphs |
| `/privacy` | 4 pillars | Cards that lift/expand on hover + focus-within |
| `/faq` | FAQ | **Accordion**, one open at a time |
| `/install` | Wizard | Existing Stepper, reframed into the new frame |
| `/guide` | Tour | Existing 9-card Stepper + jump menu, reframed |

- **Removed** `HowItWorks` (redundant with `/install`). **Providers** demoted to a single honest line on the
  home (`Built for Claude — more providers as they open up.`). The old section components (Hero, TrustStrip,
  Reveals, Surfaces, Providers, Privacy, FAQ) were deleted — their copy is re-hosted verbatim in the routes.
- **Shared frame** (`Layout.astro`): `ClientRouter` (View Transitions); `Nav`/`Footer` persist via
  `transition:persist`; a single `astro:page-load` handler runs all enhancements (reveal, nav-active sync,
  tabs engine, faq single-open) so they re-init after every route swap.
- **Viewport-first with a safety scroll**: each `.screen` centres its content with auto margins (never clips
  on overflow/zoom, unlike `justify-content:center`); the body simply grows past `100dvh` and scrolls.

## Motion

Orchestrated entrance (`[data-enter]` stagger), View-Transition cross-fades between routes with a steady
persisted nav/footer, hover micro-interactions, animated tab/toggle swaps with a sliding gradient indicator.
All of it is gated on `html.js` and fully neutralised under `prefers-reduced-motion` (entrance, panel/answer
animations, indicator transition, hero-logo, privacy hover — all collapse to instant).

## Progressive enhancement (no-JS)

Verified in a browser by reproducing the exact no-JS DOM/CSS state:

- **Tabs** (`/reveals`, `/surfaces`): panels are **not** `hidden` in the markup. With no JS the tablist is
  hidden and **all panels render stacked**, each with its own `<h2>` — content complete. Confirmed live:
  `tablist → display:none`, `4/4 panels visible`. With JS, the engine shows one panel via `[hidden]` and
  marks the group `[data-ready]`. The display-toggle rules are **unlayered** so they reliably beat Tailwind's
  `flex`/`grid` utilities (utilities sit in a later cascade layer and would otherwise win).
- **Accordion** (`/faq`): native `<details>` (first open); JS only adds one-open-at-a-time.
- **Wizards** (`/install`, `/guide`): existing PE intact — confirmed `1` card visible with JS, **all `4`
  stacked** with chrome hidden under no-JS.
- **Entrance**: `[data-enter]`'s hidden state is `.js`-gated → no-JS shows everything immediately.

## QA evidence (preview build, Playwright)

- APG tabs: ArrowRight moves focus + roving tabindex + `aria-selected` + panel swap + indicator slide. ✓
- View Transitions: client-side swap (window marker survived, no full reload), nav is the same persisted
  DOM node, `aria-current` follows the route. ✓
- Reflow (WCAG 1.4.10): **no horizontal overflow at 320px** on any of the 7 routes. ✓
- Links: every internal href resolves to a built route; no stale `/#how`,`/#reveals`,`/#faq` anchors. ✓
- Mobile (390px): degrades to scroll; the home install column uses `min-w-0` so the long command and H1
  wrap/scroll instead of being clipped. ✓

Screenshots: `c1-*-desktop.png`, `c1-*-mobile.png`, `c1-reveals-nojs-stacked-fallback.png`,
`c1-reveals-spend-tab-desktop.png`, `c1-surfaces-widget-toggle-desktop.png`.
