# Tally — menu bar app (flagship)

SwiftUI `MenuBarExtra` agent app that shows your tightest Claude usage limit in the
menu bar and the full breakdown in a popover. True 60s refresh (ADR-002). Consumes
`FetcherCore` directly (path dependency on `../../core`).

## Build & run

This machine has **CommandLineTools only** (no full Xcode), so the app is built as a
SwiftPM executable and wrapped into a `.app` bundle by `build.sh` (XcodeGen/`.xcodeproj`
both need `xcodebuild`, which requires full Xcode).

```sh
./build.sh release          # → build/Tally.app (ad-hoc signed, hardened runtime)
open build/Tally.app        # runs as a menu bar agent (no Dock icon, LSUIElement)
```

Headless helpers (no GUI needed):

```sh
# Render the real popover + settings + menu-bar views to PNGs, light AND dark
# (falls back to sample data if no Claude token is present):
./build/Tally.app/Contents/MacOS/Tally --snapshot docs/screenshots

# Prove the refresh timer fires AND reschedules live (interval, duration in seconds):
./build/Tally.app/Contents/MacOS/Tally --selftest 60 75

# Print the menu-bar text for every primary-metric choice (switch proof):
./build/Tally.app/Contents/MacOS/Tally --metrictest

# Exercise SMAppService.register()/unregister() and report the real result:
./build/Tally.app/Contents/MacOS/Tally --launchtest
```

## Settings (⌘, or the gear in the popover footer)

Preferences persist to `UserDefaults` and are mirrored live by the running model —
no restart needed:

- **Primary metric** — `Auto (tightest limit)` · `5-hour` · `Weekly` · `Sonnet weekly` ·
  `Extra usage`. Changes what the menu bar shows.
- **Refresh interval** — `30s` · `60s` · `120s` (default 60s). The `UsageModel` timer
  reschedules immediately.
- **Launch at login** — `SMAppService.mainApp` register/unregister. The toggle reflects the
  real system status; on this machine an **ad-hoc** signed build registers fine, but a
  Developer ID signature is what guarantees it everywhere.

## Design notes

- **Timer lives in `AppDelegate`/`UsageModel`, not in the menu view.** A timer hosted
  inside the `MenuBarExtra` content stalls (known macOS bug — ARCHITECTURE.md).
- **Primary metric** follows the Settings choice; `Auto` = highest utilization %. When the
  `extra_usage` overage is shown, the bar uses used/limit dollars (e.g. `$93/100`).
- **Thresholds:** `<60%` normal, `60–85%` amber, `>85%` red.
- **Dark mode:** popover and settings use semantic colors (`.primary`, `.secondary`,
  `windowBackgroundColor`) so they adapt to the system appearance. Settings controls are
  drawn in pure SwiftUI (not native `Picker`/`Toggle`) so they also render via `ImageRenderer`.
- **Last-good cache:** on a fetch error the previous reading stays visible with a warning;
  a credential/auth error before any reading shows "Claude token expired / not found".
- **No App Sandbox** (see `Tally.entitlements`): we must read the Claude Code Keychain item.
  Hardened runtime is on; entitlement is `com.apple.security.network.client`.

## Not in this phase

Other providers, WidgetKit/App-Group writes, Übersicht, distribution — later phases.
