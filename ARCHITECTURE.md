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
- A thin **`houdini`** executable target that prints the current snapshot as JSON to stdout. This is what the Übersicht widget calls, and what we use to validate against a real account before building UI.

### Menu bar app (flagship) — `apps/menubar`
- SwiftUI `MenuBarExtra` (macOS 13+), `.menuBarExtraStyle(.window)` popover.
- Timer lives in an `ObservableObject` owned at scene level (NOT inside the menu view — known macOS bug where menu-hosted timers stall).
- `SMAppService.mainApp.register()` for launch-at-login, gated behind a user toggle.
- Writes latest value into the **App Group** container and calls `WidgetCenter.shared.reloadAllTimelines()` so the WidgetKit widget stays as fresh as Apple allows.
- True 60s refresh — the only surface that fully meets the original requirement.

### Übersicht widget — `apps/ubersicht`
- A single `.jsx` with `export const refreshFrequency = 60000`.
- `command` calls `houdini` (or curls the endpoint directly with the Keychain token).
- `render({ output })` draws color-coded gauges. Zero signing/notarization needed. Reference impl exists (`ttar-p/claude-usage-widget`).

### WidgetKit widget — `apps/widget`
- `TimelineProvider` reads only the **cached** value from the App Group (cheap reloads).
- Steady-state `.after(~15min)` policy; host app pushes `reloadTimelines` on meaningful change.
- Honest UX copy ("updated a few minutes ago"). Cannot do 60s — Apple budget ~40–70 reloads/day. See `DECISIONS.md` ADR-002.

### Provider switcher & key handling — app Settings (design; see ADR-011, `PROVIDERS.md`)
The user picks/configures providers **inside the native app's Settings**, never on the
website. The Settings list is rendered from `ProviderRegistry`, so adding a provider in
`FetcherCore` surfaces a row with no UI rewrite (capability flags drive each row — ADR-007).
`.adminApiKey` providers (OpenAI Platform, Anthropic Console) take a key in a single secure
Settings field that is written **straight to the macOS Keychain** and read only by native
code at fetch time. **Hard rule:** a provider API/admin key is **never** placed in the
website, any frontend/JS bundle, browser env vars, `config.ts`, or the repo/git history —
Keychain only, no server (ADR-005, ADR-011). The site shows no key UI and no visible
OpenAI placeholder — just one honest capability line. *(Switcher + OpenAI adapter are not
built yet; this fixes the direction and the key-safety rule.)*

### Landing site — `site`
- Astro + Tailwind v4, dark "stage" identity. Static build → `dist/`, deployed on **Vercel**
  at `houdini.salomao.org`. App + CLI artifacts hosted on GitHub Releases.
- Information architecture (Houdini is the only brand; "Menu bar" and "Desktop widget" are
  co-equal **features**, never separate products/logos):
  - **Home** (`index.astro`) — hero (Install / How-it-works CTAs), trust strip, how-it-works,
    a compact "what it reveals" strip, "where it shows up" (menu bar + desktop, co-equal),
    one honest provider line, **privacy/trust**, FAQ, footer CTA. Detailed install lives off
    the home.
  - **`/install`** — three-step guided flow (run the one-liner → connect Claude → done),
    "what's included" (one app, two surfaces), build-from-source behind a "For developers"
    disclosure.
  - **`/guide`** — didactic walkthrough of what Houdini tracks and how to read the gauges.
- No "coming soon" placeholders in production (ADR-010). Copy-to-clipboard install block.

## Fetch mechanism priority (per provider)
1. **JSON endpoint + Keychain token/cookie** (BEST — native `URLSession`, no browser).
2. **WKWebView with injected cookies** (native fallback if JS render needed).
3. **Bundled headless Chromium / background Chrome reload** (LAST RESORT — heavy, signing pain, brittle DOM).

## Key constraints to honor
- Always send the `User-Agent` header on the Anthropic OAuth usage endpoint (`claude-code/<version>`). Omitting it **may cause throttling under sustained use**; keep it for safety. (Phase 1 note: a single call without the UA still returned 200, so the "persistent 429" behavior is load-dependent, not absolute.)
- Poll politely (30–120s), cache, fail gracefully on auth expiry, re-prompt before cookies die (~24h warning for session cookies).
- Never log tokens. Keychain only.
