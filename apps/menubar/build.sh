#!/usr/bin/env bash
# Build Tally and assemble a runnable .app bundle (no full Xcode required).
#   ./build.sh [debug|release]   → builds build/Tally.app
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
CONFIG="${1:-release}"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BINDIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$HERE/build/Tally.app"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/Tally" "$APP/Contents/MacOS/Tally"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc sign with hardened runtime + entitlements. App Sandbox stays OFF (see
# Tally.entitlements) so we can read the Claude Code Keychain item.
echo "==> codesign (ad-hoc, hardened runtime)"
codesign --force --options runtime \
	--entitlements "$HERE/Tally.entitlements" \
	--sign - "$APP"

echo "==> built: $APP"
echo "    run:      open \"$APP\""
echo "    snapshot: \"$APP/Contents/MacOS/Tally\" --snapshot \"$HERE/docs/screenshots\""
