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
# Render the real popover + menu-bar views to PNGs with live data:
./build/Tally.app/Contents/MacOS/Tally --snapshot docs/screenshots

# Prove the refresh timer fires (interval, duration in seconds):
./build/Tally.app/Contents/MacOS/Tally --selftest 60 75
```

## Design notes

- **Timer lives in `AppDelegate`/`UsageModel`, not in the menu view.** A timer hosted
  inside the `MenuBarExtra` content stalls (known macOS bug — ARCHITECTURE.md).
- **Primary metric = highest utilization %** (the tightest limit). When the `extra_usage`
  overage is the tightest, the bar shows dollars (e.g. `$93`). Will become configurable later.
- **Thresholds:** `<60%` normal, `60–85%` amber, `>85%` red.
- **Last-good cache:** on a fetch error the previous reading stays visible with a warning;
  a credential/auth error before any reading shows "Claude token expired / not found".
- **No App Sandbox** (see `Tally.entitlements`): we must read the Claude Code Keychain item.
  Hardened runtime is on; entitlement is `com.apple.security.network.client`.

## Not in this phase

Launch-at-login, Settings UI, other providers, WidgetKit/App-Group writes — later phases.
