# Architecture

## Principle: de-risk the data layer first

The riskiest part of this product is **"can we reliably read the number the user sees?"** — not the UI. So we build and validate the data layer (FetcherCore + Claude provider) before any pixels. All three frontends are thin consumers of one shared core.

## High-level diagram

```
                  ┌─────────────────────────────────────────────┐
                  │              FetcherCore (Swift)            │
                  │                                             │
                  │  CredentialStore (Keychain)                 │
                  │  ProviderRegistry → [UsageProvider]         │
                  │  Scheduler (per-provider interval, backoff) │
                  │  Cache (last-good value, never flash empty) │
                  │                                             │
                  │  fetch() → [UsageMetric]                    │
                  │   {label, pct?, used?, limit?, resetAt?,    │
                  │    dollars?, providerId}                    │
                  └───────┬───────────────┬──────────────┬──────┘
            links direct  │               │ CLI (JSON)   │ App Group cache
                          ▼               ▼              ▼
              ┌────────────────┐  ┌────────────────┐  ┌────────────────────┐
              │  MENU BAR APP  │  │  ÜBERSICHT .jsx │  │  WIDGETKIT WIDGET  │
              │  Timer 60s     │  │  refresh 60s    │  │  reads cache only  │
              │  MenuBarExtra  │  │  runs CLI/curl  │  │  ~15min .after()   │
              │  + popover     │  │  render(output) │  │  host pushes reload│
              │  TRUE 60s ✅   │  │  TRUE 60s ✅    │  │  NOT 60s ⚠️        │
              └───────┬────────┘  └────────────────┘  └────────────────────┘
                      │ writes value to App Group + WidgetCenter.reloadTimelines()
                      └──────────────────────────────────────────►
```

## Components

### FetcherCore (Swift Package)
The single source of truth for data. No UI. Exposes:
- `UsageProvider` protocol (see `PROVIDERS.md`).
- `CredentialStore` — reads/writes secrets in the macOS Keychain; can also read the Claude Code OAuth token (`~/.claude` / Keychain item `Claude Code`).
- `Scheduler` — per-provider polling interval (default 60s), jitter, exponential backoff on 401/403/429, last-good caching.
- `UsageSnapshot` — normalized result `[UsageMetric]` consumed by every frontend.
- A thin **`tally-cli`** executable target that prints the current snapshot as JSON to stdout. This is what the Übersicht widget calls, and what we use to validate against a real account before building UI.

### Menu bar app (flagship) — `apps/menubar`
- SwiftUI `MenuBarExtra` (macOS 13+), `.menuBarExtraStyle(.window)` popover.
- Timer lives in an `ObservableObject` owned at scene level (NOT inside the menu view — known macOS bug where menu-hosted timers stall).
- `SMAppService.mainApp.register()` for launch-at-login, gated behind a user toggle.
- Writes latest value into the **App Group** container and calls `WidgetCenter.shared.reloadAllTimelines()` so the WidgetKit widget stays as fresh as Apple allows.
- True 60s refresh — the only surface that fully meets the original requirement.

### Übersicht widget — `apps/ubersicht`
- A single `.jsx` with `export const refreshFrequency = 60000`.
- `command` calls `tally-cli` (or curls the endpoint directly with the Keychain token).
- `render({ output })` draws color-coded gauges. Zero signing/notarization needed. Reference impl exists (`ttar-p/claude-usage-widget`).

### WidgetKit widget — `apps/widget`
- `TimelineProvider` reads only the **cached** value from the App Group (cheap reloads).
- Steady-state `.after(~15min)` policy; host app pushes `reloadTimelines` on meaningful change.
- Honest UX copy ("updated a few minutes ago"). Cannot do 60s — Apple budget ~40–70 reloads/day. See `DECISIONS.md` ADR-002.

### Landing site — `site`
- Astro + Tailwind, dark Linear-style. Hosted on Cloudflare Pages. DMG hosted on GitHub Releases.
- Sections: hero + screenshot/video, install CTA, how-it-works, providers grid, **privacy/trust**, FAQ, footer CTA. Copy-to-clipboard install block.

## Fetch mechanism priority (per provider)
1. **JSON endpoint + Keychain token/cookie** (BEST — native `URLSession`, no browser).
2. **WKWebView with injected cookies** (native fallback if JS render needed).
3. **Bundled headless Chromium / background Chrome reload** (LAST RESORT — heavy, signing pain, brittle DOM).

## Key constraints to honor
- `User-Agent` header is **mandatory** on the Anthropic OAuth usage endpoint (`claude-code/<version>`), else you hit an aggressively rate-limited bucket (persistent 429s).
- Poll politely (30–120s), cache, fail gracefully on auth expiry, re-prompt before cookies die (~24h warning for session cookies).
- Never log tokens. Keychain only.
