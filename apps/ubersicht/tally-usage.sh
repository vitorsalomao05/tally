#!/usr/bin/env bash
#
# tally-usage.sh — data wrapper for the Tally Übersicht widget.
#
# Prints the current Claude usage snapshot as JSON on stdout. Two paths:
#
#   1. PRIMARY  — run `tally-cli --json`. Output is passed through verbatim, so
#                 it is byte-identical to running tally-cli directly (the
#                 normalized {providerId, displayName, capturedAt, metrics[]}
#                 snapshot from FetcherCore).
#   2. FALLBACK — if tally-cli is nowhere to be found, curl the Anthropic OAuth
#                 usage endpoint directly, reading the token from the macOS
#                 Keychain, and normalize the raw response (via jq) into the SAME
#                 shape. Marked with "source":"curl-fallback" so it is traceable.
#
# CONTRACT: always prints valid JSON and exits 0 — even on error, where it emits
# {"error":"<message>"} so the widget can render a clear message instead of
# breaking. The OAuth token is NEVER printed.
#
# tally-cli is searched on PATH and in: /usr/local/bin, ~/.local/bin, the dev
# release build (../../core/.build/release), and next to this script.

# Deliberately no `set -e`: every path must reach an emit() so stdout is always
# valid JSON. pipefail is safe and helps detect broken pipes.
set -o pipefail

KEYCHAIN_SERVICE="Claude Code-credentials"
USAGE_URL="https://api.anthropic.com/api/oauth/usage"
FALLBACK_VERSION="2.1.178"

# Resolve this script's own directory (so the dev-tree binary path is stable
# regardless of the caller's working directory).
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# ---------------------------------------------------------------------------

# Emit {"error": "..."} as valid JSON. Uses jq when present; otherwise a minimal
# hand-rolled escape so the primary path never hard-depends on jq.
emit_error() {
  local msg="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$msg" '{error: $m}'
  else
    local esc
    esc=$(printf '%s' "$msg" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  ')
    printf '{"error":"%s"}\n' "$esc"
  fi
}

# First existing tally-cli, or empty string.
find_cli() {
  local c
  if c="$(command -v tally-cli 2>/dev/null)" && [ -n "$c" ]; then
    printf '%s' "$c"; return 0
  fi
  local candidates=(
    "/usr/local/bin/tally-cli"
    "$HOME/.local/bin/tally-cli"
    "$SCRIPT_DIR/../../core/.build/release/tally-cli"
    "$SCRIPT_DIR/tally-cli"
  )
  for c in "${candidates[@]}"; do
    if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

# FALLBACK: curl the endpoint with the Keychain token and normalize via jq into
# the same snapshot shape tally-cli produces.
fallback_curl() {
  if ! command -v jq >/dev/null 2>&1; then
    emit_error "tally-cli not found and jq is unavailable for the curl fallback"
    return
  fi

  local blob token ver raw
  blob="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)"
  if [ -z "$blob" ]; then
    emit_error "no Claude Code credential in Keychain — run \`claude\` to log in"
    return
  fi
  token="$(printf '%s' "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)"
  if [ -z "$token" ]; then
    emit_error "Claude OAuth token missing or empty — re-authenticate Claude Code"
    return
  fi

  ver="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  [ -n "$ver" ] || ver="$FALLBACK_VERSION"

  raw="$(curl -fsS "$USAGE_URL" \
          -H "Authorization: Bearer $token" \
          -H "User-Agent: claude-code/$ver" \
          -H "Accept: application/json" 2>/dev/null)"
  if [ $? -ne 0 ] || [ -z "$raw" ]; then
    emit_error "usage endpoint request failed (network, auth or rate limit)"
    return
  fi

  # Mirror ClaudeOAuthProvider.parse: only windows with a non-null utilization;
  # extra_usage credits divided by 10^decimal_places. Null-valued keys are
  # stripped at the end so the shape matches tally-cli's nil-omitting Codable.
  printf '%s' "$raw" | jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    def window(b; lbl):
      if (b != null and b.utilization != null)
      then [{label: lbl, pct: b.utilization, resetAt: b.resets_at, providerId: "claude"}]
      else [] end;

    ( window(.five_hour;       "5-hour")
    + window(.seven_day;       "Weekly")
    + window(.seven_day_opus;  "Opus weekly")
    + window(.seven_day_sonnet;"Sonnet weekly")
    + ( if (.extra_usage != null and .extra_usage.is_enabled == true
            and .extra_usage.used_credits != null)
        then ( .extra_usage as $e
             | (pow(10; ($e.decimal_places // 0))) as $div
             | ($e.used_credits / $div) as $used
             | [{label: "Extra usage ($)",
                 pct: $e.utilization,
                 used: $used,
                 limit: (if $e.monthly_limit != null then ($e.monthly_limit / $div) else null end),
                 dollars: $used,
                 providerId: "claude"}] )
        else [] end )
    ) as $metrics
    | { providerId:  "claude",
        displayName: "Claude (Pro/Max)",
        capturedAt:  $now,
        source:      "curl-fallback",
        metrics:     ($metrics | map(with_entries(select(.value != null)))) }
  ' 2>/dev/null || emit_error "could not parse the usage response"
}

# ---------------------------------------------------------------------------

main() {
  local cli out rc
  if cli="$(find_cli)"; then
    # PRIMARY: pass tally-cli's JSON through verbatim. On success stdout is pure
    # JSON and stderr is empty; on failure stdout is empty and stderr carries the
    # message, which we surface as {"error": ...}.
    out="$("$cli" --json 2>&1)"
    rc=$?
    if [ $rc -eq 0 ] && [ -n "$out" ]; then
      printf '%s\n' "$out"
    else
      emit_error "tally-cli failed: ${out:-exit $rc}"
    fi
  else
    fallback_curl
  fi
}

main
exit 0
