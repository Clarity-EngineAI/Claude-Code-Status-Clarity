#!/usr/bin/env bash
# Simple test harness for clarity-statusline
# Runs statusline.sh against fixtures and compares to golden outputs.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE="$REPO_ROOT/statusline.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
EXPECTED_SUFFIX=".expected.txt"

ANSI_STRIP_CMD='s/\x1B\[[0-9;]*[A-Za-z]//g'

usage() {
  cat <<EOF
Usage: $(basename "$0") [all|NAME...]

Examples:
  $(basename "$0") all
  $(basename "$0") 02-normal-42pct
EOF
}

require_statusline() {
  if [ ! -x "$STATUSLINE" ]; then
    echo "error: statusline.sh not found or not executable at $STATUSLINE" >&2
    exit 1
  fi
}

run_one_fixture() {
  local base="$1"
  local json="$FIXTURES_DIR/$base.json"
  local expected="$FIXTURES_DIR/$base$EXPECTED_SUFFIX"

  if [ ! -f "$json" ]; then
    echo "skipping $base (no JSON fixture)" >&2
    return 0
  fi

  if [ ! -f "$expected" ]; then
    echo "skipping $base (no expected file)" >&2
    return 0
  fi

  echo "== $base"

  # Extract session_id from JSON for sidecar injection
  local session_id
  session_id="$(jq -r '.session_id // empty' "$json" 2>/dev/null || true)"

  # .setup.sh sidecar: run before test (receives SESSION_ID env var)
  if [ -f "$FIXTURES_DIR/$base.setup.sh" ]; then
    SESSION_ID="$session_id" bash "$FIXTURES_DIR/$base.setup.sh"
  fi

  # .env sidecar: per-fixture env vars
  local extra_env=()
  if [ -f "$FIXTURES_DIR/$base.env" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^# ]] && continue
      extra_env+=("$line")
    done <"$FIXTURES_DIR/$base.env"
  fi

  # .history sidecar: install to /tmp history path expected by the script
  if [ -f "$FIXTURES_DIR/$base.history" ] && [ -n "$session_id" ]; then
    cp "$FIXTURES_DIR/$base.history" "/tmp/claude-statusline-history-$session_id"
  fi

  # Run statusline, strip ANSI, compare
  # CLAUDE_STATUSLINE_SESSIONS_DIR points to a non-existent path by default so that
  # multi-instance detection is suppressed in all tests except 11-multi-instance,
  # which overrides via its .env sidecar.
  local actual_tmp
  actual_tmp="$(mktemp)"
  if ! env CLAUDE_STATUSLINE_THEME="warm" CLAUDE_STATUSLINE_ASCII=1 CLAUDE_STATUSLINE_NO_GIT=1 \
       CLAUDE_STATUSLINE_SESSIONS_DIR=/tmp/nonexistent-sessions-for-testing \
       ${extra_env[@]+"${extra_env[@]}"} "$STATUSLINE" <"$json" >"$actual_tmp"; then
    echo "  statusline.sh exited non-zero for $base" >&2
    rm -f "$actual_tmp"
    return 1
  fi

  # Normalise actual: strip ANSI escapes and trailing whitespace per line.
  # Trailing whitespace would otherwise force golden files to encode invisible
  # noise; we keep the goldens readable and match on visible content only.
  if sed -E -e "$ANSI_STRIP_CMD" -e 's/[[:space:]]+$//' "$actual_tmp" >"$actual_tmp.stripped" 2>/dev/null; then
    mv "$actual_tmp.stripped" "$actual_tmp"
  fi

  if diff -u "$expected" "$actual_tmp"; then
    echo "  ok"
  else
    echo "  FAIL (diff above)" >&2
    rm -f "$actual_tmp"
    return 1
  fi

  rm -f "$actual_tmp"
}

run_all() {
  local failures=0
  for json in "$FIXTURES_DIR"/*.json; do
    [ -e "$json" ] || continue
    local base
    base="$(basename "$json" .json)"
    if ! run_one_fixture "$base"; then
      failures=$((failures + 1))
    fi
  done

  if [ "$failures" -gt 0 ] ; then
    echo "$failures test(s) failed" >&2
    return 1
  fi
}

run_visual_all() {
  # Manual smoke test: render all fixtures into the current terminal
  for json in "$FIXTURES_DIR"/*.json; do
    [ -e "$json" ] || continue
    local base
    base="$(basename "$json" .json)"
    echo
    echo "=== $base ==="
    CLAUDE_STATUSLINE_THEME="warm" "$STATUSLINE" <"$json"
    echo
  done
}

main() {
  if [ $# -eq 0 ]; then
    usage
    exit 1
  fi

  require_statusline

  case "$1" in
    all)
      run_all
      ;;
    visual)
      run_visual_all
      ;;
    *)
      local failures=0
      while [ $# -gt 0 ]; do
        if ! run_one_fixture "$1"; then
          failures=$((failures + 1))
        fi
        shift
      done
      if [ "$failures" -gt 0 ]; then
        exit 1
      fi
      ;;
  esac
}

main "$@"