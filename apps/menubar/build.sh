#!/usr/bin/env bash
# Build Houdini and assemble a runnable .app bundle (no full Xcode required).
#   ./build.sh [debug|release]   → builds build/Houdini.app
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
CONFIG="${1:-release}"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BINDIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$HERE/build/Houdini.app"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# SPM product is "HoudiniApp" (case-distinct from the core `houdini` CLI so their
# build trees don't collide on case-insensitive APFS); the bundle binary is "Houdini".
cp "$BINDIR/HoudiniApp" "$APP/Contents/MacOS/Houdini"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

# Bundle assets (app icon + menu bar glyph). Source artwork lives under design/;
# regenerate with design/icon/render-icon.sh and design/glyph/render-glyph.swift.
# AppIcon.icns is referenced by Info.plist (CFBundleIconFile); ClaudeGlyph.pdf is
# loaded at runtime as a template image (Bundle.main).
if [[ -d "$HERE/Resources" ]]; then
	cp -R "$HERE/Resources/." "$APP/Contents/Resources/"
fi
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || \
	echo "warning: AppIcon.icns missing — run design/icon/render-icon.sh" >&2
[[ -f "$APP/Contents/Resources/ClaudeGlyph.pdf" ]] || \
	echo "warning: ClaudeGlyph.pdf missing — run design/glyph/render-glyph.swift" >&2

# Ad-hoc sign with hardened runtime + entitlements. App Sandbox stays OFF (see
# Houdini.entitlements) so we can read the Claude Code Keychain item.
echo "==> codesign (ad-hoc, hardened runtime)"
codesign --force --options runtime \
	--entitlements "$HERE/Houdini.entitlements" \
	--sign - "$APP"

echo "==> built: $APP"
echo "    run:      open \"$APP\""
echo "    snapshot: \"$APP/Contents/MacOS/Houdini\" --snapshot \"$HERE/docs/screenshots\""
