#!/usr/bin/env bash
# Regenerate the Houdini app icon from AppIcon.svg (the source of truth).
# CommandLineTools-only pipeline: qlmanage (SVG→PNG) → sips (sizes) → iconutil.
#   ./render-icon.sh
# Outputs:
#   design/icon/AppIcon-1024.png        (versioned master raster)
#   apps/menubar/Resources/AppIcon.icns (shipped, embedded by build.sh)
#   apps/menubar/docs/screenshots/app-icon.png (512 preview)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

SVG="AppIcon.svg"
PNG="AppIcon-1024.png"
ICONSET="Houdini.iconset"
ICNS="../../Resources/AppIcon.icns"
PREVIEW="../../docs/screenshots/app-icon.png"

echo "==> rasterize $SVG → $PNG (1024×1024)"
rm -f AppIcon.svg.png "$PNG"
qlmanage -t -s 1024 -o . "$SVG" >/dev/null 2>&1
mv AppIcon.svg.png "$PNG"

echo "==> build $ICONSET (16/32/128/256/512 @1x + @2x)"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
gen() { sips -z "$1" "$1" "$PNG" --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "$PNG" "$ICONSET/icon_512x512@2x.png"   # 1024 master, no resample

echo "==> iconutil → $ICNS"
mkdir -p "$(dirname "$ICNS")"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> preview (512) → $PREVIEW"
mkdir -p "$(dirname "$PREVIEW")"
cp "$ICONSET/icon_512x512.png" "$PREVIEW"

echo "done."
