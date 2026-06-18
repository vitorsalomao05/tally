#!/usr/bin/env bash
#
# install.sh — install Houdini (the menu bar app + houdini) on macOS.
#
# What it does, in order — nothing hidden:
#   1. Refuses to run anywhere but macOS 14+ on Apple Silicon.
#   2. Downloads Houdini.app.zip + houdini from the *pinned* GitHub Release
#      (TAG below) and VERIFIES their SHA-256 against SHASUMS256.txt. It aborts
#      on any mismatch — it never installs unverified bytes, and downloads only
#      from this one release.
#   3. Installs WITHOUT sudo:  app → ~/Applications,  cli → ~/.local/bin.
#   4. Offers — never forces — "start at login" and the Übersicht desktop widget.
#   5. Is idempotent (safe to re-run) and prints exactly how to uninstall.
#
# It never reads or prints your Claude token. Read this whole file before piping
# it to bash — that's the point of pinning it to a tag:
#   https://raw.githubusercontent.com/vitorsalomao05/houdini/v0.2.0/install.sh
#
# Interactive run:
#   curl -fsSL https://raw.githubusercontent.com/vitorsalomao05/houdini/v0.2.0/install.sh | bash
# Unattended (also accept the optional login item + widget):
#   curl -fsSL .../install.sh | HOUDINI_YES=1 bash
#
set -euo pipefail

# ── Pinned source of truth ───────────────────────────────────────────────────
REPO="vitorsalomao05/houdini"
TAG="v0.2.0"
REL="https://github.com/$REPO/releases/download/$TAG"

APP_NAME="Houdini.app"
APP_DIR="$HOME/Applications"
APP="$APP_DIR/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
WIDGET_DIR="$HOME/Library/Application Support/Übersicht/widgets/houdini"

# ── Output helpers ───────────────────────────────────────────────────────────
BOLD=$'\033[1m'; BLUE=$'\033[1;34m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; RST=$'\033[0m'
say()  { printf '%s==>%s %s\n'  "$BLUE"   "$RST" "$1"; }
ok()   { printf '%s  ✓%s %s\n'  "$GREEN"  "$RST" "$1"; }
warn() { printf '%s  !%s %s\n'  "$YELLOW" "$RST" "$1"; }
die()  { printf '%s  ✗ %s%s\n'  "$RED" "$1" "$RST" >&2; exit 1; }

# Ask a yes/no question. Works under `curl | bash` by reading the controlling
# terminal (/dev/tty), since stdin there is the script itself. HOUDINI_YES=1 makes
# it unattended; with no terminal and no HOUDINI_YES the answer defaults to No, so
# the optional extras are never forced on.
ask() {
  local prompt="$1" ans=""
  [ "${HOUDINI_YES:-0}" = "1" ] && return 0
  # Probe the controlling terminal silently. Under `curl | bash` stdin is the
  # script, so we read the user's answer from /dev/tty. No terminal (piped,
  # CI) → default No, so the optional extras are never forced on.
  { true > /dev/tty; } 2>/dev/null || return 1
  printf '%s%s [y/N]%s ' "$BOLD" "$prompt" "$RST" > /dev/tty
  read -r ans < /dev/tty || ans=""
  case "$ans" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ── 1. Preflight ─────────────────────────────────────────────────────────────
say "Checking your Mac…"
[ "$(uname -s)" = "Darwin" ] || die "Houdini is macOS-only (this is $(uname -s))."
[ "$(uname -m)" = "arm64" ]  || die "Houdini needs Apple Silicon (this Mac reports $(uname -m)); no Intel build is shipped."
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "${OS_MAJOR:-0}" -ge 14 ]  || die "Houdini needs macOS 14 or newer (you're on $(sw_vers -productVersion))."
for tool in curl shasum ditto open; do
  command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' not found."
done
ok "macOS $(sw_vers -productVersion) on Apple Silicon"

# ── 2. Download + verify (from the pinned release only) ──────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fetch() { curl -fSL --proto '=https' --tlsv1.2 -o "$TMP/$1" "$REL/$1" || die "download failed: $1"; }
verify() { # $1.. = asset names to check against the downloaded SHASUMS256.txt
  local pat
  pat="$(printf '%s\n' "$@" | sed 's/\./\\./g' | paste -sd'|' -)"
  grep -E "  ($pat)\$" "$TMP/SHASUMS256.txt" > "$TMP/.check" || die "no checksums for: $*"
  [ "$(wc -l < "$TMP/.check")" -eq "$#" ] || die "SHASUMS256.txt is missing an entry for one of: $*"
  ( cd "$TMP" && shasum -a 256 -c .check >/dev/null ) \
    || die "checksum mismatch — refusing to install. Re-run; if it persists, open an issue."
}

say "Downloading Houdini $TAG from github.com/$REPO …"
fetch "SHASUMS256.txt"
fetch "Houdini.app.zip"
fetch "houdini"
ok "downloaded Houdini.app.zip + houdini (+ SHASUMS256.txt)"

say "Verifying SHA-256 against SHASUMS256.txt…"
verify "Houdini.app.zip" "houdini"
ok "checksums match — these are the exact bytes published in $TAG"

# ── 3. Install (no sudo) ─────────────────────────────────────────────────────
say "Installing $APP_NAME → $APP_DIR"
mkdir -p "$APP_DIR"
rm -rf "$APP"
ditto -x -k "$TMP/Houdini.app.zip" "$APP_DIR"
[ -d "$APP" ] || die "extraction did not produce $APP"
# Downloaded over HTTPS by curl (no quarantine flag set), but strip it defensively
# so the ad-hoc-signed app opens without a Gatekeeper prompt.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
ok "installed $APP"

say "Installing houdini → $BIN_DIR/houdini"
mkdir -p "$BIN_DIR"
cp -f "$TMP/houdini" "$BIN_DIR/houdini"
chmod +x "$BIN_DIR/houdini"
ok "installed (the widget finds it here even if ~/.local/bin isn't on your PATH)"
case ":${PATH}:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "to run 'houdini' directly, add ~/.local/bin to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# ── 4. Launch ────────────────────────────────────────────────────────────────
say "Launching Houdini — look for it in the menu bar (top-right)…"
open "$APP" || warn "couldn't auto-launch; open it from $APP_DIR"

# ── 5. Offer: start at login (never forced) ──────────────────────────────────
if ask "Start Houdini automatically at login?"; then
  if "$APP/Contents/MacOS/Houdini" --register-login-item; then
    ok "login item set (if it says it needs approval, enable Houdini in System Settings ▸ General ▸ Login Items)"
  else
    warn "could not register the login item — you can toggle it any time in Houdini ▸ Settings"
  fi
else
  ok "skipped login item — toggle it any time in Houdini ▸ Settings"
fi

# ── 6. Offer: Übersicht desktop widget (optional) ────────────────────────────
# Mirrors apps/ubersicht/install.sh's widget-deploy step, but verified from the
# pinned release and reusing the houdini just installed (no source build).
if ask "Also install the Übersicht desktop widget?"; then
  say "Downloading + verifying the widget…"
  fetch "houdini.jsx"
  fetch "houdini-usage.sh"
  verify "houdini.jsx" "houdini-usage.sh"
  mkdir -p "$WIDGET_DIR"
  cp -f "$TMP/houdini.jsx"      "$WIDGET_DIR/houdini.jsx"
  cp -f "$TMP/houdini-usage.sh" "$WIDGET_DIR/houdini-usage.sh"
  chmod +x "$WIDGET_DIR/houdini-usage.sh"
  ok "widget deployed → $WIDGET_DIR"
  UB=""
  for p in "/Applications/Übersicht.app" "$HOME/Applications/Übersicht.app"; do
    [ -d "$p" ] && UB="$p" && break
  done
  if [ -z "$UB" ] && command -v mdfind >/dev/null 2>&1; then
    UB="$(mdfind "kMDItemCFBundleIdentifier == 'tracesOf.Uebersicht'" 2>/dev/null | head -1)"
  fi
  if [ -n "$UB" ]; then
    ok "Übersicht found — open it (or its menu ▸ Refresh All Widgets) to see Houdini top-right"
  else
    warn "Übersicht isn't installed yet. Install it, then it picks up the widget:"
    printf '      brew install --cask ubersicht\n'
  fi
else
  ok "skipped the Übersicht widget"
fi

# ── 7. Summary + uninstall ───────────────────────────────────────────────────
printf '\n%sHoudini %s is installed.%s\n' "$BOLD" "$TAG" "$RST"
printf '  • App : %s\n' "$APP"
printf '  • CLI : %s/houdini   (try: houdini --json)\n' "$BIN_DIR"
[ -d "$WIDGET_DIR" ] && printf '  • Widget: %s\n' "$WIDGET_DIR"
printf '\nTo uninstall:\n'
printf '  "%s/Contents/MacOS/Houdini" --unregister-login-item   # if you enabled login\n' "$APP"
printf '  rm -rf "%s"\n' "$APP"
printf '  rm -f  "%s/houdini"\n' "$BIN_DIR"
[ -d "$WIDGET_DIR" ] && printf '  rm -rf "%s"\n' "$WIDGET_DIR"
printf '\nRe-running this installer is safe — it verifies and overwrites in place.\n'
