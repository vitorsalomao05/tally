# Roadmap (phased delegation plan)

Each phase = one or more prompts handed to Claude Code. We build the data layer before any UI, then frontends, then distribution and site. Order is chosen to de-risk early.

## Phase 0 — Repo foundation ✅ (done by the Brain)
Docs (README, ARCHITECTURE, DECISIONS, PROVIDERS, WORKFLOW), directory skeleton, ADRs. Git init + first commit handled in Phase 1 prompt.

## Phase 1 — FetcherCore + Claude adapter (data layer)  ← WE ARE HERE
- SwiftPM workspace: `FetcherCore` library + `tally-cli` executable.
- `UsageProvider` protocol, `CredentialStore` (Keychain), models.
- **Claude `.keychainOAuth` adapter**: read Claude Code OAuth token, call `api.anthropic.com/api/oauth/usage` with mandatory `claude-code/<ver>` UA, parse 5h/weekly/Opus.
- `tally-cli` prints the live snapshot as JSON.
- **Validation gate:** run `tally-cli` against the real account; confirm numbers match `claude.ai/settings/usage`.

## Phase 2 — Menu bar app (flagship)
- SwiftUI `MenuBarExtra` + popover; timer in scene-level `ObservableObject` (60s).
- Settings: choose provider, launch-at-login (`SMAppService`), thresholds/colors.
- Writes to App Group + `reloadTimelines()`.

## Phase 3 — Übersicht widget
- Single `.jsx`, `refreshFrequency = 60000`, calls `tally-cli`, color-coded gauges, install instructions.

## Phase 4 — WidgetKit widget (glanceable)
- Widget extension + App Group shared container; `.after(~15min)`; honest "updated X min ago" copy.

## Phase 5 — More providers
- Claude `.sessionCookie` fallback (embedded WebView login).
- OpenAI Platform + Anthropic Console admin-API adapters.
- ChatGPT Plus experimental.

## Phase 6 — Distribution
- Decision finalized (DMG notarized vs curl|bash vs Homebrew) per ADR-006.
- Sign + notarize + staple script; `install.sh` if used; release automation.

## Phase 7 — Landing site
- Astro + Tailwind, dark Linear-style, Cloudflare Pages, DMG on GitHub Releases.
- Hero + demo, install CTA, how-it-works, providers grid, privacy/trust, FAQ.

## Phase 8 — Polish & launch
- Icon/branding, accessibility pass, auto-update (Sparkle) for mature release, README badges, screenshots/video.

## Phase 9 — Mobile: Tally for iPhone (iOS)  — NEW DIRECTION
See `apps/ios/PLAN.md` and `DECISIONS.md` ADR-008. Native iOS app (no PWA — CORS + httpOnly cookie + the "no server sees your creds" promise rule it out).
- **FetcherCore iOS-ready** ✅ — only macOS-only dep was `Foundation.Process`; guarded behind `#if os(macOS)`, macOS build unchanged. Cookie path (`ClaudeCookieProvider` + `ClaudeUsageParser`) reused verbatim.
- **App scaffold** ✅ (source only — *not* compiled; needs Xcode) — SwiftUI app + `UsageViewModel`, in-app `WKWebView` claude.ai login → capture `sessionKey` → iOS Keychain → native `URLSession` fetch.
- **WidgetKit** — Home Screen + Lock Screen widgets reading the App Group cached snapshot; honest ~15–30 min refresh ("updated X min ago"), **not** 60s (same Apple budget as Phase 4 / ADR-002).
- **Distribution** — needs **Apple Developer Program ($99/yr) + Xcode**; TestFlight (beta) → App Store. No free install-by-link on iOS (unlike the Mac app).
- **Blocked on:** Xcode + the $99 program + a confirmed Team ID / bundle-ID prefix. None producible on this CommandLineTools-only machine.

## Phase 10 — Android (future, not scheduled)
- Separate Kotlin/Compose app, same cookie approach (`WebView` login → `CookieManager` reads httpOnly → Keystore → `OkHttp`, no CORS), Glance home-screen widget. Waits until the iOS app proves the mobile thesis.
