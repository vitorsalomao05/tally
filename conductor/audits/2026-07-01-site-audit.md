# Houdini landing page — visual + accessibility audit (2026-07-01)

> Source: Claude-in-Chrome live audit of https://houdini.salomao.org/ (desktop ~1084px,
> mobile ~406px). Feeds BACKLOG P3.
>
> **Cross-link with ADR-012 (Claude subscription-auth ToS review):** two findings are
> ToS-gated — do NOT action them until the ADR-012 direction is chosen:
>   - B/[P1] "sharpen H1 toward Claude/menu-bar" — leaning harder into "Claude subscription"
>     may be the wrong move if we pivot away from subscription reads. HOLD.
>   - D "add an explicit 'Mac → Anthropic, no Houdini server' trust sentence" — doubles down
>     on exactly the OAuth/cookie flow under review. HOLD.
> Everything else (mobile screenshot, curl readability, footer contrast, aria-hidden,
> small-text) is direction-independent and safe to ship anytime.

============================================================
HOUDINI LANDING PAGE — DEEP VISUAL + ACCESSIBILITY AUDIT
URL: https://houdini.salomao.org/   |  Audited live in-browser
Widths inspected: desktop ~1084px CSS, mobile ~406px CSS
============================================================

A. SUMMARY
Single-screen, dark-themed landing page. Genuinely calm and low-clutter: one hero headline,
one clearly framed curl|bash install block with a working Copy button, two secondary CTAs
(Guided install / Read the guide), three trust chips, compact footer. Technically strong on
a11y — skip link, single H1, semantic landmarks, lang="en", visible focus rings, aria-live
copy feedback, descriptive alt on the one product screenshot. Close to the "zero clutter +
calm" goal and mostly WCAG-AA clean. Concrete gaps: product screenshot HIDDEN on mobile;
hero H1 generic ("AI usage") vs the intended Claude/menu-bar pitch; curl command visually
truncated with no obvious full view; a couple of small-text/contrast items at/below AA. No
console errors observed on load.

B. VISUAL FINDINGS
[P1] Product screenshot completely HIDDEN on mobile. The only real product visual (menu-bar
  popover webp, 380x362, descriptive alt) is in a wrapper with display:none at ~406px —
  mobile visitors see zero product imagery. FIX: show it below the hero copy at narrow
  widths, scaled down.
[P1] Hero headline doesn't land the intended pitch. Live H1 = "See your AI usage and spend,
  revealed." — generic "AI", no "menu bar" in the headline. FIX: tighten toward the
  differentiator (e.g. "See your Claude usage and spend, right in your menu bar").
  [ToS-GATED — hold for ADR-012.]
[P2] curl one-liner visually truncated with no obvious full view. Renders as
  "curl -fsSL https://raw.githubusercontent.com/vitorsalomao05/hou…"; <pre> is overflow-x:auto
  (scrollbar hidden until scroll), no wrap/ellipsis. Bad for a "verify before pasting into
  Terminal" flow. FIX: white-space:pre-wrap or a persistent scroll/fade affordance.
[P2] "Surfaces" nav label + "menu bar and on your desktop" phrasing risks implying two
  things. Stays ONE app on this page (Section E), but plural "Surfaces" is the closest
  two-product smell. FIX: keep copy explicitly one-app; consider a clearer nav label.
[P3] Two <nav> landmarks expose the same links (desktop "Primary" vs mobile "Sections");
  only one shown per breakpoint (no duplicate tab stops). Slightly redundant structurally.
[P3] Very small (12px) supporting text throughout (meta lines, trust chips, footer). Legible
  but near the floor. FIX: bump the key reassurance line to 13–14px or lighten (see C).

C. ACCESSIBILITY FINDINGS (WCAG 2.1 AA; contrast vs bg rgb(11,10,16), approximate)
[P2] Footer "Local-first · No trapdoors" FAILS AA: ~rgb(111,106,128), 12px ≈ 3.8:1 (<4.5:1).
  FIX: lighten to ~4.6:1+ or enlarge/bolden.
[P2] Multiple 12px muted lines sit right at the AA edge (~4.66:1): "No Gatekeeper prompt ·
  checksum-verified · nothing leaves your Mac", bottom meta, and the "GET HOUDINI — PASTE
  INTO TERMINAL" label (violet ~rgb(139,92,246)). Pass AA but only just. FIX: nudge to
  ~5.5:1+, especially the terminal label (a key instruction).
[P3] Decorative hat SVG logos lack aria-hidden (3 SVGs; link name is fine via "Houdini"
  text). FIX: add aria-hidden="true" to purely decorative logo SVGs.
PASSES (verified): lang="en"; skip link is first focusable → #main (tabindex=-1); exactly
  one H1; landmarks present (banner/nav×2/main/contentinfo/status); descriptive alt +
  width/height on hero image; icon controls named ("Houdini on GitHub", "Copy command");
  copy feedback role="status" aria-live="polite"; visible 2px focus outlines everywhere;
  logical tab order, no positive tabindex; prefers-reduced-motion rule present; no horizontal
  overflow at 406px. NOTE: no H2/H3 (single hero section) — acceptable but no in-page heading
  structure to navigate by.

D. INSTALL & TRUST OBSERVATIONS
Install: single clear copy-the-one-liner flow; labeled code block with the v0.4.0 curl|bash;
  Copy button works ("Copied!", full command in clipboard despite visual truncation);
  reassurance line "No Gatekeeper prompt · checksum-verified · nothing leaves your Mac"; two
  secondary CTAs (Guided install → /install, Read the guide → /guide); free/no-account/
  no-payment communicated; v0.4.0 chip → GitHub releases. One clear path, nothing competes.
Trust: stated via hero ("No account, no server. Nothing leaves your Mac."), trust chips
  ("Runs on your Mac", "Keychain-kept credentials", "Open source"), footer ("Local-first ·
  No trapdoors"). The explicit "requests go straight Mac → provider, no Houdini server"
  narrative is only IMPLIED on the landing page (/privacy linked, not audited). Suggested one
  explicit sentence. [ToS-GATED — hold for ADR-012.]

E. ADR-COMPLIANCE FLAGS
1) Menu bar vs desktop widget as two products? NOT branded as two. "widget" appears 0 times;
   copy = one app across two places ("menu bar and on your desktop"). COMPLIANT. Watch-item:
   "Surfaces" plural + "menu bar AND on your desktop". (/surfaces, /reveals not audited.)
2) Notification Center widget mention? NONE ("Notification Center/Centre"/"widget" absent).
   COMPLIANT.

F. TOP 5 QUICK WINS
1. Stop hiding the product screenshot on mobile. [P1]
2. Make the curl command fully readable (wrap or scroll/fade affordance). [P2]
3. Fix footer contrast ("Local-first · No trapdoors" 3.8:1 → 4.6:1+). [P2]
4. Sharpen the H1 toward the real pitch. [P1 messaging] — ToS-GATED, hold for ADR-012.
5. aria-hidden on decorative hat SVGs + nudge ~4.66:1 12px lines to ~5.5:1. [P3]

COULD NOT / DID NOT CHECK
Sub-pages (/install, /guide, /privacy, /reveals, /surfaces, /faq) out of scope — landing page
only, so the two-product / Notification-Center checks cover THIS page only (a /surfaces page
could still describe multiple surfaces). Console: "none observed" (tracking began post-load).
Screen-reader/keyboard were DOM/focus-simulated, not a live AT session. Contrast ratios
approximate — verify borderline ~4.66:1 with a formal tool. Window wouldn't render below
~406px, so 390px approximated at 406px.
