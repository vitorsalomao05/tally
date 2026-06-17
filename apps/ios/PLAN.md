# Tally for iPhone — plan

Status: **planning + scaffold only.** No iOS build has happened (this machine has
CommandLineTools only — no Xcode, no iOS SDK, no Apple Developer account). Every
"done" below means *source written and the shared core made iOS-compilable*, not
*shipped*. See [BLOCKED_ON](#8--what-is-blocked-on-xcode--99) for the honest line
between the two.

The north star is unchanged from the Mac app: **the number you already see on
claude.ai, on a surface you actually look at, with credentials that never leave
your device.** On iPhone "the surface you look at" is the Home Screen and the
Lock Screen.

---

## 1. Auth on iOS — cookie login, native `URLSession`, iOS Keychain

There is **no Claude Code on iPhone**, so the Mac app's flagship path (reuse the
Claude Code OAuth token from the Keychain) does not exist on iOS. The only Claude
credential a phone can obtain is the **claude.ai session cookie** — exactly the
Mac app's *fallback* path, which is already the cross-platform half of FetcherCore.

Flow (mirrors `apps/menubar/.../ClaudeLoginWindow.swift`, ported to UIKit/SwiftUI):

1. **Login** — present a `WKWebView` pointed at `https://claude.ai/login` inside
   the app. Use a **non-persistent** `WKWebsiteDataStore` so the cookie never
   lands in WebKit's on-disk jar (the Keychain is the only store — ADR-005).
2. **Capture** — observe `WKHTTPCookieStore` (`cookiesDidChange`, plus a
   `didFinish` backstop) and read `getAllCookies()`. Pull the `sessionKey` cookie
   (`sk-ant-sid01-…`). **Key fact that makes this work:** `WKHTTPCookieStore`
   returns **httpOnly** cookies — the native cookie store is privileged in a way
   `document.cookie` / a plain browser is not. This is why a native app can do
   what a PWA cannot (see §2).
3. **Store** — write the value to the **iOS Keychain** via
   `CredentialStore.nativeWriteGenericPassword` (service `Tally-claude-session`,
   account `sessionKey`, accessible `AfterFirstUnlock` so the widget can read it).
   `Security.framework` / Keychain Services is fully available on iOS.
4. **Fetch** — `ClaudeCookieProvider.fetch()` runs unchanged: native
   `URLSession` `GET https://claude.ai/api/organizations` → pick the org →
   `GET …/organizations/{id}/usage` → normalize with `ClaudeUsageParser`.
   A native app calls claude.ai **server-to-server from the device** — **no CORS**
   (CORS is a browser policy; `URLSession` is not a browser).

**Reused verbatim from FetcherCore:** `ClaudeCookieProvider`, `ClaudeUsageParser`,
`ClaudeAuthResolver`, `CredentialStore` (native paths), `HTTPRedirectGuard`,
`Models`, `UsageProvider`. The iOS app writes **zero** new networking or parsing
code — it provides UI + the login WebView + the Keychain write, all of which the
core already exposes.

> `ASWebAuthenticationSession` is the usual iOS "log in to a website" API, but it
> is built for **OAuth/OIDC redirect** flows: it hands back only the final
> callback URL and deliberately does **not** expose the cookie jar. claude.ai sets
> a session cookie with no custom-scheme callback, so `ASWebAuthenticationSession`
> can't capture `sessionKey`. **`WKWebView` + `WKHTTPCookieStore` is the correct
> tool** and is what the scaffold uses. (We still get the privacy benefit of the
> non-persistent store.)

---

## 2. Why **not** a pure PWA / web app

A browser-only "open tally.salomao.org and it shows your usage" cannot work
honestly, for two independent reasons:

- **CORS.** A page served from `tally.salomao.org` calling
  `claude.ai/api/organizations/{id}/usage` is a cross-origin request. claude.ai
  does not send `Access-Control-Allow-Origin` for us, so the browser blocks the
  response. (`URLSession` in a native app is not subject to CORS — §1.)
- **The httpOnly cookie is unreachable from JS.** Even on claude.ai itself, the
  `sessionKey` cookie is **httpOnly**: `document.cookie` cannot read it by design.
  A web app has no privileged cookie-store API; only a **native** `WKHTTPCookieStore`
  (or the browser itself) can read it.

The only way to make a PWA work would be a **server proxy** that holds the user's
cookie and calls claude.ai on their behalf — which **breaks the entire privacy
promise** ("no server ever sees your credentials", ADR-005). That is a
non-starter for this product.

**Verdict: the honest mobile path is a native iOS app.** A thin marketing PWA /
"add to Home Screen" shortcut that just *links* to the native app is fine; a PWA
that *reads your usage* is not buildable without betraying the trust model.

---

## 3. iOS surfaces & refresh — honest budgets

Three surfaces, one shared core:

| Surface | Tech | Refresh reality |
|---|---|---|
| **App screen** | SwiftUI, `UsageViewModel` | Refreshes **on open / on foreground**, and on pull-to-refresh. This is the only "fresh on demand" surface. |
| **Home Screen widget** | WidgetKit `TimelineProvider` | **~15–30 min**, *not* 60s. |
| **Lock Screen widget** | WidgetKit accessory family (iOS 16+) | Same ~15–30 min budget. |

**Refresh honesty (this is non-negotiable, and identical to ADR-002 on macOS):**
Apple gives widgets a small daily reload budget (order ~40–70 timeline reloads/day,
≈ every 15–60 min; minimum entry spacing ~5 min). Background app refresh
(`BGAppRefreshTask`) is *also* scheduled at the system's discretion, not on a timer
we control. So:

- The widgets show **"updated X min ago"** copy and a cached value — never a fake
  live gauge.
- The **app** updates when you open it / bring it to the foreground; opening the
  app is also what most cheaply refreshes the widget (the app writes the latest
  snapshot to the shared App Group container and calls
  `WidgetCenter.shared.reloadAllTimelines()`).
- We will **not** promise 60s anywhere on iOS. (On macOS the menu bar app can do
  true 60s because it's a always-running agent; an iOS app cannot run like that.)

Shared data path: app fetches → writes `UsageSnapshot` (Codable, already in
FetcherCore) to the **App Group** container → widget reads that cached snapshot.
The widget itself can also fetch directly when its timeline refreshes (it has the
Keychain cookie), but the cheap/normal path is "read the app's cached snapshot."

---

## 4. Distribution — TestFlight + App Store only ($99 + Xcode, explicit)

**There is no free "install by link" on iOS.** This is the single biggest
difference from the Mac app, and the copy must say so plainly:

- The Mac app ships an ad-hoc-signed `.app` / notarized DMG and even a
  `curl … | bash` developer stopgap — all installable **without** the App Store.
- iOS has **no equivalent**. Every realistic distribution channel runs through
  Apple and requires the **Apple Developer Program ($99/yr)** and **Xcode**:
  - **TestFlight** — beta. Up to 10,000 external testers, builds expire after 90
    days, requires App Store Connect + a (lightweight) Beta App Review.
  - **App Store** — public. Full App Review.
- Sideloading caveats, stated honestly so nobody thinks there's a loophole:
  - Free personal-team provisioning (build to *your own* device from Xcode) gives
    a **7-day** signature — a dev convenience, not a distribution channel.
  - AltStore / third-party sideloading is fragile, region-dependent (EU
    alternative marketplaces under the DMA), and not something we'll ask users to
    do.
  - **Bottom line:** to put Tally for iPhone in someone else's hands, you pay the
    $99 and go through TestFlight → App Store. No way around it.

This reuses **ADR-006**'s "$99 buys the clean path" conclusion; iOS just removes
the un-paid escape hatches that macOS still has.

---

## 5. Core reuse — FetcherCore is now iOS-ready

**Audit goal:** make the data layer (cookie provider + parser + Keychain + models)
compile and run on iOS **without breaking the macOS build**. Result: the only
macOS-only dependency in FetcherCore was **`Foundation.Process`** (unavailable on
iOS), in two places. Everything else was already cross-platform.

| FetcherCore file | macOS-only? | Action |
|---|---|---|
| `ClaudeCookieProvider.swift` | No — `URLSession` + native Keychain | **none** (already iOS-ready; this *is* the iOS auth path) |
| `ClaudeUsageParser.swift` | No — pure Foundation | none |
| `HTTPRedirectGuard.swift` | No — `URLSession` delegate | none |
| `Models.swift`, `UsageProvider.swift` | No | none |
| `ClaudeAuth.swift` | No (reads via `CredentialStore`) | none |
| `CredentialStore.swift` | **Yes** — `cliReadGenericPassword` uses `Process` + `/usr/bin/security` | `#if os(macOS)` around the CLI method; `readGenericPassword` routes to the **native** path on iOS |
| `ClaudeOAuthProvider.swift` | **Yes** — `detectedClientVersion()` shells `claude --version` via `Process` | `#if os(macOS)` around the probe; iOS returns the pinned `fallbackVersion` (the OAuth provider is a desktop-only concept anyway — iOS uses the cookie provider) |

`import Security` is **cross-platform** (Keychain Services exists on iOS), so no
guard needed there.

**Changes applied (this commit set):**

- `core/Package.swift`: added `.iOS(.v17)` to `platforms`. `tally-cli` /
  `tally-selftest` remain macOS-only host tools (they use `Process`) and are never
  built for / linked into iOS — only the `FetcherCore` **library** product is.
- `CredentialStore.readGenericPassword`: `#if os(macOS)` → CLI; `#else` → native.
- `CredentialStore.cliReadGenericPassword`: whole method wrapped in `#if os(macOS)`.
- `ClaudeOAuthProvider.detectedClientVersion`: `Process` probe wrapped in
  `#if os(macOS)`; falls through to the constant elsewhere.

**Validation:** `swift build` (macOS host) still succeeds and `swift run
tally-selftest` still passes all 14 checks — the macOS build is untouched. iOS
compilation itself can only be *verified in Xcode* (no iOS SDK here), so it stays
a documented assumption until then, but the guards are mechanical and the
remaining code is plain Foundation.

> Note: the macOS **app** (`apps/menubar`) uses AppKit / `SMAppService` / `NSImage`
> — all macOS-only — but those live in the app, **not** in FetcherCore, so they
> don't affect iOS reuse. The iOS app re-implements its own SwiftUI UI on top of
> the same core (just like Übersicht and the widget are separate frontends).

---

## 6. Android — future, not now

Registered as a **future** option, not implemented:

- Separate **Kotlin/Jetpack Compose** app (you can't reuse Swift core on Android
  without extra tooling like Skip or a KMP rewrite — out of scope).
- **Same approach**: a `WebView` login to claude.ai, capture the `sessionKey`
  cookie (Android `CookieManager` can read httpOnly cookies natively, same as
  `WKHTTPCookieStore`), store in the Android Keystore / EncryptedSharedPreferences,
  call the same two JSON endpoints with `OkHttp`/`HttpURLConnection` (no CORS).
- Surfaces: app screen + a home-screen **App Widget** (Glance), same ~15-min-ish
  refresh honesty.
- Distribution is *easier* than iOS (APK sideload + Play Store both exist), but
  it's a second codebase to maintain — so it waits until the iOS app proves the
  mobile thesis.

---

## 7. Recommended MVP + sequence to TestFlight

**MVP (smallest honest thing):**

1. One **app screen**: sign in to claude.ai (WebView) → show the same gauges as the
   Mac app (5-hour / weekly / Opus / extra-usage $), "updated X ago", pull to
   refresh. Sign out clears the Keychain item.
2. One **Home Screen widget** (systemSmall + systemMedium) reading the cached
   snapshot, with honest "updated X min ago" copy.
3. (Stretch, same release) a **Lock Screen** accessory widget — cheap once the
   widget exists.

**Sequence to TestFlight (what unblocks once $99 + Xcode exist):**

1. In Xcode: create the App + Widget Extension targets, add `core/` as a local
   Swift Package dependency, enable the **App Group** capability on both
   (`group.org.salomao.tally`), and add the Keychain sharing entitlement.
   (`apps/ios/project.yml` documents exactly this target layout for XcodeGen.)
2. Build to a **personal-team** device (free) to smoke-test the WebView login,
   the Keychain write, the live fetch, and the widget timeline.
3. Enroll in the **Apple Developer Program ($99)**.
4. Set bundle IDs, signing, and App Store Connect record; archive; upload to
   **TestFlight**; pass Beta App Review; invite testers.
5. Iterate on widget refresh copy + error states; then submit to the **App Store**.

---

## 8 · What is blocked on Xcode / $99

Everything in this folder is **source + plan only**. To actually run on a phone you
need, in order:

- **Xcode** (full IDE + iOS SDK + Simulator) — to compile the app/widget at all.
  `swift build` on CommandLineTools cannot build an iOS app or a WidgetKit
  extension.
- An **Apple Developer Program** membership (**$99/yr**) — to run on a real device
  beyond 7 days, and for TestFlight / App Store.
- A confirmed **Team ID / bundle-ID prefix** — the scaffold uses placeholders
  (`org.salomao.tally.*`, `group.org.salomao.tally`) marked `TODO`.

None of those can be produced on this machine, so the scaffold is intentionally
**not compiled here**. See each scaffold file's header `// TODO(xcode)` notes.
