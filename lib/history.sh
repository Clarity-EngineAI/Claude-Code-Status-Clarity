#!/usr/bin/env bash
# History helpers for Claude Code statusline (Clarity Engine)
# Format per spec:
#   {unix_ts}|{cost_usd}|{ctx_pct}|{tokens_used}|{tools_csv}
#
# Public API (called from statusline.sh):
#   history_append_row
#   history_get_file_path   # echo path for callers that need it

set -u

HISTORY_MAX_LINES=200
HISTORY_MAX_AGE_SECONDS=$((24 * 60 * 60))

history_get_file_path() {
  # SESSION_ID is expected to be set by statusline.sh
  printf '/tmp/claude-statusline-history-%s' "${SESSION_ID:-unknown}"
}

history__now_unix() {
  # Seconds since epoch, portable
  date +%s
}

history__ensure_dir() {
  # /tmp always exists, but keep hook for future changes
  :
}

history__truncate_to_last_n_lines() {
  # Keep last HISTORY_MAX_LINES lines if file exists
  local file="$1"
  [ -f "$file" ] || return 0

  # Use tail into tmp then move back, to avoid in‑place truncation issues
  local tmp
  tmp="$(mktemp "${file}.XXXXXX")" || return 1
  if ! tail -n "$HISTORY_MAX_LINES" "$file" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  if ! cat "$tmp" >"$file"; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

history__prune_by_age() {
  local file="$1"
  [ -f "$file" ] || return 0

  local cutoff
  cutoff=$(( $(history__now_unix) - HISTORY_MAX_AGE_SECONDS ))

  local tmp
  tmp="$(mktemp "${file}.XXXXXX")" || return 1
  if ! awk -F'|' -v cutoff="$cutoff" '$1 >= cutoff' "$file" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  if ! cat "$tmp" >"$file"; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

history_append_row() {
  # Append one row, then bound size and prune by age.
  # Returns 0 on success, non‑zero if the history file cannot be written.

  local file
  file="$(history_get_file_path)"

  history__ensure_dir || return 1

  # unix_ts
  local now
  now="$(history__now_unix)"

  # values come from global vars set by statusline.sh
  # COST_TOTAL_USD, CTX_PCT, CTX_TOKENS_USED
  local cost ctx_pct tokens_used tools_csv
  cost="${COST_TOTAL_USD:-0}"
  ctx_pct="${CTX_PCT:-0}"
  tokens_used="${CTX_TOKENS_USED:-0}"

  # Read tools from the PostToolUse tool log (consecutive-dedup, comma-joined)
  local tool_log="/tmp/claude-statusline-tools-${SESSION_ID:-unknown}"
  tools_csv=""
  if [ -f "$tool_log" ] && [ -s "$tool_log" ]; then
    tools_csv=$(awk 'prev != $0 { printf "%s%s", sep, $0; sep=","; prev=$0 }' "$tool_log" 2>/dev/null) || tools_csv=""
  fi

  # Best effort append
  {
    printf '%s|%s|%s|%s|%s\n' \
      "$now" "$cost" "$ctx_pct" "$tokens_used" "$tools_csv" >>"$file"
  } 2>/dev/null || return 1

  # Truncate to last N lines, ignore failures
  history__truncate_to_last_n_lines "$file" || true

  # Prune by age (stub)
  history__prune_by_age "$file" || true

  return 0
}