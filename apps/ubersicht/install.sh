#!/usr/bin/env bash
#
# install.sh — install the Tally Übersicht widget (Phase 3).
#
#   1. builds tally-cli (release) and installs it to ~/.local/bin/tally-cli
#   2. deploys tally.jsx + tally-usage.sh to the Übersicht widgets folder
#   3. checks Übersicht is installed; if not, prints the brew command
#
# Idempotent: safe to re-run. It rebuilds, overwrites the installed copies, and
# leaves your usage data untouched.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd)"
CORE_DIR="$REPO_ROOT/core"
BIN_DIR="$HOME/.local/bin"
WIDGET_DIR="$HOME/Library/Application Support/Übersicht/widgets/tally"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$1"; }

# ── 1. Build + install tally-cli ─────────────────────────────────────────────
say "Building tally-cli (release)…"
if ! command -v swift >/dev/null 2>&1; then
  echo "error: 'swift' not found. Install the Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi
( cd "$CORE_DIR" && swift build -c release >/dev/null )
CLI_SRC="$(cd "$CORE_DIR" && swift build -c release --show-bin-path)/tally-cli"
[ -x "$CLI_SRC" ] || { echo "error: build did not produce $CLI_SRC" >&2; exit 1; }
ok "built $CLI_SRC"

say "Installing tally-cli → $BIN_DIR/tally-cli"
mkdir -p "$BIN_DIR"
cp -f "$CLI_SRC" "$BIN_DIR/tally-cli"
chmod +x "$BIN_DIR/tally-cli"
ok "installed (the widget finds it here even if ~/.local/bin isn't on your PATH)"

# ── 2. Deploy the widget ─────────────────────────────────────────────────────
say "Deploying widget → $WIDGET_DIR"
mkdir -p "$WIDGET_DIR"
cp -f "$SCRIPT_DIR/tally.jsx"       "$WIDGET_DIR/tally.jsx"
cp -f "$SCRIPT_DIR/tally-usage.sh"  "$WIDGET_DIR/tally-usage.sh"
chmod +x "$WIDGET_DIR/tally-usage.sh"
ok "copied tally.jsx + tally-usage.sh"

# Smoke-test the installed wrapper (uses the just-installed ~/.local/bin binary).
if out="$("$WIDGET_DIR/tally-usage.sh" 2>/dev/null)" \
   && command -v jq >/dev/null 2>&1 \
   && printf '%s' "$out" | jq -e '.metrics // .error' >/dev/null 2>&1; then
  if printf '%s' "$out" | jq -e '.error' >/dev/null 2>&1; then
    warn "wrapper ran but reported: $(printf '%s' "$out" | jq -r '.error')"
  else
    ok "wrapper emits valid JSON ($(printf '%s' "$out" | jq -r '.metrics | length') metrics)"
  fi
else
  warn "could not verify the wrapper output (jq missing or no credential yet)"
fi

# ── 3. Übersicht presence ────────────────────────────────────────────────────
UB_APP=""
for p in "/Applications/Übersicht.app" "$HOME/Applications/Übersicht.app"; do
  [ -d "$p" ] && UB_APP="$p" && break
done
if [ -z "$UB_APP" ] && command -v mdfind >/dev/null 2>&1; then
  UB_APP="$(mdfind "kMDItemCFBundleIdentifier == 'tracesOf.Uebersicht'" 2>/dev/null | head -1)"
fi

if [ -n "$UB_APP" ]; then
  ok "Übersicht found: $UB_APP"
  say "Done. Open Übersicht (or its menu ▸ Refresh All Widgets) to see Tally top-right."
else
  warn "Übersicht not installed."
  echo
  echo "    brew install --cask ubersicht"
  echo
  echo "  Then launch Übersicht and re-run this script (or just refresh widgets)."
fi
