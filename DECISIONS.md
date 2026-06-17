# Architecture Decision Records (ADRs)

Short, dated, reversible. Each records *what* we decided and *why*, grounded in the June 2026 research.

## ADR-001 — Read JSON endpoints, don't scrape a background browser
**Decision:** Default fetch path is a native `URLSession` call to the provider's JSON endpoint, authenticated with a credential read from the Keychain. The "open Chrome in background and reload" idea is demoted to a last-resort fallback adapter.
**Why:** A proven reference (`ttar-p/claude-usage-widget`) reads the Claude Code OAuth token from Keychain and calls `api.anthropic.com/api/oauth/usage` directly. This is ~6 MB vs hundreds of MB of bundled Chromium, survives UI redesigns, and avoids JIT entitlements / nested-binary notarization hell.
**Trade-off:** Endpoints are undocumented/unversioned and can break; we mitigate with last-good caching and clear auth-expiry handling.

## ADR-002 — WidgetKit cannot do 60s; menu bar app is the flagship
**Decision:** The true-60s experience is the **menu bar app** (and Übersicht). The Notification Center WidgetKit widget is shipped as a *glanceable, ~15-min* surface with honest copy.
**Why:** Apple gives widgets a daily budget of ~40–70 reloads (effective ~15–60 min); minimum entry spacing ~5 min; even host-app `reloadAllTimelines()` is throttled and deferred. Debugger has no limit, which misleads. This is a hard platform constraint, not a bug we can engineer around.
**Trade-off:** We must set user expectations; we market the widget as "glanceable," not "live."

## ADR-003 — All-Swift shared core (no bundled Node/Chromium by default)
**Decision:** `FetcherCore` is a Swift package consumed directly by the menu bar app and widget; the Übersicht `.jsx` calls a tiny Swift CLI (`tally-cli`) or curls directly. No Node/Playwright in the default build.
**Why:** Bundling Chromium roughly doubles engineering effort *just for code signing* (bottom-up signing, JIT entitlements `allow-jit` / `allow-unsigned-executable-memory`, library-validation disable). All-Swift keeps hardened-runtime signing trivial. Only adopt a bundled headless browser if a target provider truly has no readable endpoint.

## ADR-004 — Claude first, OpenAI/Console secondary, ChatGPT Plus experimental
**Decision:** Build the Claude Pro/Max adapter first (cleanest signal). Anthropic Console + OpenAI Platform admin-API adapters second (zero ToS risk, documented). ChatGPT Plus quota is experimental/best-effort.
**Why:** Claude exposes `utilization_pct` directly behind the user's progress bars. OpenAI has no clean consumer quota number; only "limit reached" signals. Don't promise a gauge we can't reliably fill.

## ADR-005 — Credentials in Keychain, never on a server
**Decision:** All tokens/cookies stored in macOS Keychain; no Tally backend ever receives them. Embedded WebView login for cookie-based providers; offer to reuse Claude Code's OAuth token when present.
**Why:** The app touches logins; trust is the core adoption barrier. This also becomes the landing-site privacy story.

## ADR-006 — Distribution: notarized DMG for MVP; DMG + Homebrew cask (+ Sparkle) for mature release
**Decision (provisional, revisit after signing setup):** MVP ships a **signed + notarized DMG** ($99 Apple Developer Program). Mature release adds a **Homebrew cask** secondary channel and **Sparkle** auto-update. `curl|bash` only as a documented developer-tester stopgap.
**Why:** macOS 15 (Sequoia) removed the Control-click→Open Gatekeeper bypass; an un-notarized app now forces a multi-step System Settings ordeal that non-technical users won't complete. Notarized DMG is the only one-click-clean path. `curl|bash` skips Gatekeeper (quarantine attr not set) — convenient but reads as sketchy for a consumer GUI app and trains bad habits. Homebrew now also requires notarization and only reaches technical users.
**Open question for later:** confirm whether the user wants to pay the $99 now (enables the clean path) or ship an interim developer build first.

## ADR-007 — Pluggable provider adapters
**Decision:** Every provider implements one `UsageProvider` protocol with capability flags (`usagePct`, `resetTimer`, `dollarBalance`). The registry + UI adapt to whatever a provider can supply.
**Why:** Providers differ wildly (Claude has %, OpenAI Platform has $, ChatGPT Plus has almost nothing). A capability-driven model lets us add providers without touching the UI core.

## ADR-008 — Mobile is a native iOS app (cookie auth), not a PWA
**Decision:** The iPhone version is a **native SwiftUI app** (+ WidgetKit Home/Lock Screen widgets) that signs into claude.ai in an in-app `WKWebView`, captures the `sessionKey` cookie, stores it in the **iOS Keychain**, and calls the same `claude.ai` JSON endpoints via native `URLSession`. It reuses `FetcherCore`'s **cookie** path verbatim (`ClaudeCookieProvider` + `ClaudeUsageParser`); there is no Claude Code OAuth token on a phone, so the cookie path — the Mac app's *fallback* — becomes the iOS *primary*. FetcherCore was made iOS-compilable by guarding its only macOS-only dependency (`Foundation.Process`, in `CredentialStore.cliReadGenericPassword` and `ClaudeOAuthProvider.detectedClientVersion`) behind `#if os(macOS)`; the macOS build is unchanged (see `apps/ios/PLAN.md` §5).
**Why a native app, not a PWA:** A browser can't do this honestly. (1) **CORS** — a page on `tally.salomao.org` calling `claude.ai/api/.../usage` is cross-origin and claude.ai doesn't allow it; native `URLSession` is not a browser and isn't subject to CORS. (2) **httpOnly** — `sessionKey` is an httpOnly cookie, unreadable from `document.cookie`; only a privileged native cookie store (`WKHTTPCookieStore`) can read it. The only way to make a PWA work is a **server proxy holding the user's cookie**, which would break the core privacy promise (ADR-005). So native is the *only* honest path.
**Trade-off / consequences:** (a) **Refresh** — iOS widgets inherit the same Apple budget as ADR-002 (~15–30 min, *not* 60s); the app refreshes on open/foreground; copy stays "updated X min ago". We promise 60s nowhere on iOS. (b) **Distribution** — unlike the Mac app there is **no free install-by-link**: shipping to others requires the **Apple Developer Program ($99/yr) + Xcode**, via TestFlight then the App Store (extends ADR-006; iOS removes macOS's un-paid escape hatches). (c) **Android** is a *future*, separate Kotlin app using the same cookie approach — not built now. None of the build/ship steps are possible on this CommandLineTools-only machine, so today's work is scaffold + an iOS-ready core only.
