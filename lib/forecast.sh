#!/usr/bin/env bash
# Forecast helpers for Claude Code statusline (Clarity Engine)
#
# Public API (called from statusline.sh):
#   forecast_compute_burn_and_velocity
#
# Exposed variables (to be consumed in statusline.sh):
#   FORECAST_SESSION_RATE_PER_HR        # float-like string, e.g. "1.23"
#   FORECAST_RECENT_RATE_PER_HR         # float-like string, e.g. "4.56"
#   FORECAST_HAS_SPIKE                  # "0" or "1"
#   FORECAST_CTX_VELOCITY_PPM           # context percentage points per minute (string)
#   FORECAST_HAS_CTX_TICK               # "0" or "1"

set -u

FORECAST_SESSION_RATE_PER_HR="0.00"
FORECAST_RECENT_RATE_PER_HR="0.00"
FORECAST_HAS_SPIKE="0"

FORECAST_CTX_VELOCITY_PPM="0.0"
FORECAST_HAS_CTX_TICK="0"

FORECAST_COMPACT_ETA_TURNS="0"
FORECAST_COMPACT_ETA_AVAILABLE="0"

forecast__history_file() {
  # Reuse helper from history.sh if loaded; fall back otherwise.
  if command -v history_get_file_path >/dev/null 2>&1; then
    history_get_file_path
  else
    printf '/tmp/claude-statusline-history-%s' "${SESSION_ID:-unknown}"
  fi
}

forecast__now_unix() {
  date +%s
}

forecast__read_history() {
  # Reads entire history file into a list of lines on stdout.
  local file
  file="$(forecast__history_file)"
  [ -f "$file" ] || return 1
  cat "$file"
}

forecast__compute_session_rate() {
  # session_rate = total_cost_usd / (total_duration_ms / 3_600_000)  → $/hr
  local cost dur
  cost="${COST_TOTAL_USD:-0}"
  dur="${COST_DURATION_MS:-0}"

  FORECAST_SESSION_RATE_PER_HR="$(awk -v cost="$cost" -v dur="$dur" \
    'BEGIN {
       if (dur + 0 <= 0) { printf "0.00"; exit }
       printf "%.2f", (cost * 3600000.0) / dur
     }')"
}

forecast__compute_recent_rate() {
  # Cost delta over the last 60 seconds, extrapolated to hourly.
  # Anchor on the earliest history row whose ts is >= now - 60.
  local file now cost
  file="$(forecast__history_file)"
  now="$(forecast__now_unix)"
  cost="${COST_TOTAL_USD:-0}"

  if [ ! -f "$file" ]; then
    FORECAST_RECENT_RATE_PER_HR="0.00"
    return 0
  fi

  FORECAST_RECENT_RATE_PER_HR="$(awk -F'|' \
    -v now="$now" -v cost_now="$cost" '
    BEGIN { found = 0 }
    {
      ts = $1 + 0
      c  = $2 + 0
      if (!found && (now - ts) <= 60) {
        ts_then = ts
        cost_then = c
        found = 1
      }
    }
    END {
      if (!found) { printf "0.00"; exit }
      dt = now - ts_then
      if (dt < 1) { printf "0.00"; exit }
      dc = cost_now - cost_then
      if (dc < 0) dc = 0
      printf "%.2f", (dc / dt) * 3600.0
    }
  ' "$file")"
}

forecast__compute_spike_flag() {
  # recent_rate > 2.0 × session_rate AND recent_rate > 1 USD/hr
  FORECAST_HAS_SPIKE="$(awk \
    -v sr="$FORECAST_SESSION_RATE_PER_HR" \
    -v rr="$FORECAST_RECENT_RATE_PER_HR" '
    BEGIN {
      if ((rr + 0) > 2.0 * (sr + 0) && (rr + 0) > 1.0) printf "1";
      else printf "0";
    }')"
}

forecast__compute_ctx_velocity() {
  # Velocity = ctx_pct_now - ctx_pct_then, where "then" is the earliest
  # history row within the last 60s. Tick suppressed when:
  #   - oldest history row is younger than 60s (history not yet 60s old), or
  #   - velocity is negative (post-compact).
  local file now ctx_now result
  file="$(forecast__history_file)"
  now="$(forecast__now_unix)"
  ctx_now="${CTX_PCT:-0}"

  FORECAST_CTX_VELOCITY_PPM="0.0"
  FORECAST_HAS_CTX_TICK="0"

  [ -f "$file" ] || return 0

  result="$(awk -F'|' \
    -v now="$now" -v ctx_now="$ctx_now" '
    BEGIN { found = 0; ts_oldest = -1 }
    {
      ts  = $1 + 0
      ctx = $3 + 0
      if (ts_oldest < 0) ts_oldest = ts
      if (!found && (now - ts) <= 60) {
        ts_then  = ts
        ctx_then = ctx
        found = 1
      }
    }
    END {
      if (ts_oldest < 0)            { printf "0.0|0"; exit }
      if ((now - ts_oldest) < 60)   { printf "0.0|0"; exit }
      if (!found)                   { printf "0.0|0"; exit }
      v = ctx_now - ctx_then
      if (v < 0)                    { printf "%.1f|0", v; exit }
      printf "%.1f|1", v
    }
  ' "$file")"

  FORECAST_CTX_VELOCITY_PPM="${result%|*}"
  FORECAST_HAS_CTX_TICK="${result##*|}"
}

forecast__compute_compact_eta() {
  # Innovation 3: auto-compact countdown.
  # Trigger: ctx_pct >= 70.
  # Counts turns as history rows where tokens_used (field 4) strictly
  # increased over the previous row. avg_tokens_per_turn uses the live
  # session totals (input + output). Suppressed when turn count is 0.
  local file ctx_pct ctx_size tokens_used in_tok out_tok

  FORECAST_COMPACT_ETA_TURNS="0"
  FORECAST_COMPACT_ETA_AVAILABLE="0"

  ctx_pct="${CTX_PCT:--1}"
  if [ "$ctx_pct" -lt 70 ] 2>/dev/null; then
    return 0
  fi

  ctx_size="${CTX_WINDOW_SIZE:-0}"
  if [ "$ctx_size" -le 0 ] 2>/dev/null; then
    return 0
  fi

  tokens_used="${CTX_TOKENS_USED:-0}"
  in_tok="${COST_INPUT_TOKENS:-0}"
  out_tok="${COST_OUTPUT_TOKENS:-0}"
  file="$(forecast__history_file)"
  [ -f "$file" ] || return 0

  FORECAST_COMPACT_ETA_TURNS="$(awk -F'|' \
    -v ctx_size="$ctx_size" -v tokens_used="$tokens_used" \
    -v in_tok="$in_tok" -v out_tok="$out_tok" '
    BEGIN { prev = -1; turns = 0 }
    {
      t = $4 + 0
      if (prev >= 0 && t > prev) turns++
      prev = t
    }
    END {
      if (turns < 1)         { printf "0"; exit }
      total = in_tok + out_tok
      if (total <= 0)        { printf "0"; exit }
      avg = total / turns
      remain = ctx_size * 0.95 - tokens_used
      if (remain <= 0)       { printf "1"; exit }
      eta = int(remain / avg)
      if (eta < 1) eta = 1
      printf "%d", eta
    }
  ' "$file")"

  if [ "${FORECAST_COMPACT_ETA_TURNS:-0}" -gt 0 ] 2>/dev/null; then
    FORECAST_COMPACT_ETA_AVAILABLE="1"
  fi
}

forecast_compute_burn_and_velocity() {
  # Top-level entry point. Called once from statusline.sh.
  #
  # session_rate is derived purely from globals so it always runs.
  # The other three need a readable history file; if missing, leave defaults.
  forecast__compute_session_rate

  if ! forecast__read_history >/dev/null 2>&1; then
    return 0
  fi

  forecast__compute_recent_rate
  forecast__compute_spike_flag
  forecast__compute_ctx_velocity
  forecast__compute_compact_eta

  return 0
}