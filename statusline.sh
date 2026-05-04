#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155

# Claude Code Status Line – Clarity Engine edition
# Entry point for the statusLine hook. Reads JSON on stdin, prints 2–3 lines on stdout.

set -u  # no -e: we want to degrade gracefully

###############################################################################
# Globals and defaults
###############################################################################

CLAUDE_STATUSLINE_VERSION="0.1.0"
STATUSLINE_DEBUG_LOG="${CLAUDE_STATUSLINE_DEBUG_LOG:-/tmp/claude-statusline.log}"

# Parsed fields (initial defaults follow kcchien style: empty / -1 / 0)
MODEL_DISPLAY_NAME=""
MODEL_ID=""
SESSION_ID=""

CTX_PCT="-1"
CTX_WINDOW_SIZE="-1"
CTX_TOKENS_USED="-1"

COST_TOTAL_USD="0"
COST_DURATION_MS="-1"
COST_LINES_ADDED="0"
COST_LINES_REMOVED="0"
COST_INPUT_TOKENS="0"
COST_OUTPUT_TOKENS="0"

RL_5H_PCT="-1"
RL_5H_RESETS_AT=""
RL_7D_PCT="-1"
RL_7D_RESETS_AT=""

WORKSPACE_DIR=""
WORKTREE_BRANCH=""
SESSION_NAME=""
AGENT_NAME=""

MCP_SERVERS_JSON=""  # raw array
STATE_VALUE=""

THINKING_ENABLED="0"
FAST_MODE="0"
EXCEEDS_200K="0"
EFFORT_LEVEL=""

###############################################################################
# Debug helpers
###############################################################################

debug_log() {
  # Log only when CLAUDE_STATUSLINE_DEBUG=1
  if [ "${CLAUDE_STATUSLINE_DEBUG:-0}" != "1" ]; then
    return 0
  fi
  # Best-effort logging, ignore failures
  {
    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >>"$STATUSLINE_DEBUG_LOG"
  } 2>/dev/null || true
}

time_ms() {
  # Millisecond timestamp, Bash 3.2 compatible (macOS / Linux)
  # Uses `date +%s` plus `date +%N` when available; falls back to seconds only.
  if date +%N >/dev/null 2>&1; then
    # nanoseconds available
    local now_s now_ns
    now_s=$(date +%s)
    now_ns=$(date +%N)
    # integer division, no bc
    echo "$now_s$((10#$now_ns / 1000000))"
  else
    echo "$(date +%s)000"
  fi
}

###############################################################################
# Safe section wrapper
###############################################################################

safe_section() {
  # Usage: SECTION_OUTPUT="$(safe_section section_function arg1 arg2)"
  # Runs a function and suppresses any non-zero exit into an empty string.
  # Errors are logged in debug mode.
  local func="$1"
  shift || true

  local out
  if out="$("$func" "$@" 2>/dev/null)"; then
    printf '%s' "$out"
    return 0
  fi

  debug_log "safe_section: $func failed, suppressing section"
  printf '%s' ""
  return 0
}

###############################################################################
# Terminal capability detection
###############################################################################

TERM_TRUECOLOR=0
TERM_ASCII=0
TERM_NERDFONT=0

detect_terminal_capabilities() {
  # Truecolour heuristics
  case "${COLORTERM:-}" in
    truecolor|24bit)
      TERM_TRUECOLOR=1
      ;;
    *)
      TERM_TRUECOLOR=0
      ;;
  esac

  # ASCII mode from env or dumb terminals
  if [ "${CLAUDE_STATUSLINE_ASCII:-0}" = "1" ] || [ "${TERM:-dumb}" = "dumb" ]; then
    TERM_ASCII=1
  fi

  # Nerdfont hint (env only; we cannot auto-detect reliably)
  if [ "${CLAUDE_STATUSLINE_NERDFONT:-0}" = "1" ]; then
    TERM_NERDFONT=1
  fi
}

###############################################################################
# Theme loading
###############################################################################

# Theme variables (will be set by lib/theme.sh)
THEME_NAME="warm"
SYMBOL_BAR_SEPARATOR="│"
SYMBOL_RATE_WARN="!"
SYMBOL_POWERLINE_LEFT=""
COLOUR_ACCENT=""
COLOUR_FAINT=""
COLOUR_RESET=$'\033[0m'

load_theme_library() {
  # Expect lib/theme.sh next to this script or in ~/.claude/
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
  # Prefer local lib, fall back to ~/.claude
  if [ -f "$script_dir/lib/theme.sh" ]; then
    # shellcheck source=lib/theme.sh
    . "$script_dir/lib/theme.sh"
  elif [ -f "$HOME/.claude/theme.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.claude/theme.sh"
  else
    debug_log "theme.sh not found, using hard-coded minimal defaults"
  fi
}

apply_theme_preset() {
  THEME_NAME="${CLAUDE_STATUSLINE_THEME:-warm}"
  theme_load_preset "$THEME_NAME" \
    "$TERM_TRUECOLOR" "$TERM_ASCII" "$TERM_NERDFONT"
}

apply_explicit_overrides() {
  # Override glyph sets and separators based on env flags
  if [ "${CLAUDE_STATUSLINE_ASCII:-0}" = "1" ]; then
    theme_force_ascii
  fi
  if [ "${CLAUDE_STATUSLINE_POWERLINE:-0}" = "1" ]; then
    theme_force_powerline
  fi
  if [ "${CLAUDE_STATUSLINE_NERDFONT:-0}" = "1" ]; then
    theme_force_nerdfont
  fi
}

###############################################################################
# JSON parsing (single jq call with sentinel)
###############################################################################

parse_input_json() {
  local start_ms end_ms jq_program raw input_json

  start_ms="$(time_ms)"

  input_json=$(cat)
  if [ "${CLAUDE_STATUSLINE_DEBUG:-0}" = "1" ]; then
    printf '%s' "$input_json" > "/tmp/claude-statusline-last-input.json"
  fi

  jq_program='
    def f(x): (try x // empty);
    [
      f(.model.display_name),
      f(.model.id),
      f(.session_id),

      (f(.context_window.used_percentage) // -1),
      (f(.context_window.context_window_size) // -1),
      (f(.context_window.tokens_used) // -1),

      (f(.cost.total_cost_usd) // 0),
      (f(.cost.total_duration_ms) // -1),
      (f(.cost.total_lines_added) // 0),
      (f(.cost.total_lines_removed) // 0),
      (f(.cost.total_input_tokens) // 0),
      (f(.cost.total_output_tokens) // 0),

      (f(.rate_limits.five_hour.used_percentage) // -1),
      (f(.rate_limits.five_hour.resets_at) // ""),
      (f(.rate_limits.seven_day.used_percentage) // -1),
      (f(.rate_limits.seven_day.resets_at) // ""),

      (f(.workspace.current_dir) // ""),
      (f(.worktree.branch) // ""),
      (f(.session_name) // ""),
      (f(.agent.name) // ""),

      (f(.mcp_servers) // [] | tostring),
      (f(.state) // ""),

      (f(.thinking.enabled) // false | if . then "1" else "0" end),
      (f(.fast_mode) // false | if . then "1" else "0" end),
      (f(.exceeds_200k_tokens) // false | if . then "1" else "0" end),
      (f(.effort.level) // ""),

      "END"
    ]
    | .[]
  '

  if ! raw=$(printf '%s' "$input_json" | jq -r "$jq_program" 2>/dev/null); then
    # jq missing or parse error – kcchien-style fallback
    printf '─ │ jq not found'
    printf '\n'
    printf '   │ parse error'
    printf '\n'
    exit 0
  fi

  # Read fields line-by-line to preserve empties
  local idx=0
  while IFS= read -r line; do
    if [ "$line" = "END" ]; then
      break
    fi
    case "$idx" in
      0)  MODEL_DISPLAY_NAME=$line ;;
      1)  MODEL_ID=$line ;;
      2)  SESSION_ID=$line ;;
      3)  CTX_PCT=$line ;;
      4)  CTX_WINDOW_SIZE=$line ;;
      5)  CTX_TOKENS_USED=$line ;;
      6)  COST_TOTAL_USD=$line ;;
      7)  COST_DURATION_MS=$line ;;
      8)  COST_LINES_ADDED=$line ;;
      9)  COST_LINES_REMOVED=$line ;;
      10) COST_INPUT_TOKENS=$line ;;
      11) COST_OUTPUT_TOKENS=$line ;;
      12) RL_5H_PCT=$line ;;
      13) RL_5H_RESETS_AT=$line ;;
      14) RL_7D_PCT=$line ;;
      15) RL_7D_RESETS_AT=$line ;;
      16) WORKSPACE_DIR=$line ;;
      17) WORKTREE_BRANCH=$line ;;
      18) SESSION_NAME=$line ;;
      19) AGENT_NAME=$line ;;
      20) MCP_SERVERS_JSON=$line ;;
      21) STATE_VALUE=$line ;;
      22) THINKING_ENABLED=$line ;;
      23) FAST_MODE=$line ;;
      24) EXCEEDS_200K=$line ;;
      25) EFFORT_LEVEL=$line ;;
      *)  ;;
    esac
    idx=$((idx + 1))
  done <<EOF
$raw
EOF

  end_ms="$(time_ms)"
  debug_log "parse_input_json ms=$((end_ms - start_ms))"
}

###############################################################################
# History + forecast (innovations 1–3, stubs)
###############################################################################

source_history_lib() {
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
  if [ -f "$script_dir/lib/history.sh" ]; then
    # shellcheck source=lib/history.sh
    . "$script_dir/lib/history.sh"
  fi
}

source_forecast_lib() {
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
  if [ -f "$script_dir/lib/forecast.sh" ]; then
    # shellcheck source=lib/forecast.sh
    . "$script_dir/lib/forecast.sh"
  fi
}

append_history_row() {
  # Innovation 1–3: write {unix_ts}|{cost_usd}|{ctx_pct}|{tokens_used}|{tools_csv}
  if [ "${CLAUDE_STATUSLINE_FORECAST:-0}" != "1" ] && \
     [ "${CLAUDE_STATUSLINE_COMPACT_ETA:-0}" != "1" ] && \
     [ "${CLAUDE_STATUSLINE_TRACE:-0}" != "1" ]; then
    return 0
  fi

  if [ -z "${SESSION_ID:-}" ]; then
    return 0
  fi

  if ! history_append_row; then
    debug_log "history_append_row failed (unwritable?), skipping forecast features"
  fi
}

compute_burn_rate_and_velocity() {
  if [ "${CLAUDE_STATUSLINE_FORECAST:-0}" != "1" ]; then
    return 0
  fi
  forecast_compute_burn_and_velocity
}

###############################################################################
# Rendering helpers (mostly stubs)
###############################################################################

_build_gradient_bar() {
  # Render a 10-block gradient bar. $1=pct, $2=width, $3=tick_pos (-1 = none)
  local pct="${1:-0}" width="${2:-10}" tick_pos="${3:--1}"
  local filled="█" empty="░" tick_char="▏"
  if [ "${TERM_ASCII:-0}" = "1" ]; then
    filled="#" empty="-" tick_char="|"
  fi

  if [ "${TERM_TRUECOLOR:-0}" = "1" ] && [ "${TERM_ASCII:-0}" != "1" ] && [ "$width" -gt 1 ]; then
    # Single awk call: green → yellow → red true-color gradient
    awk -v pct="$pct" -v w="$width" -v tick="$tick_pos" \
        -v filled="$filled" -v empty="$empty" -v tc="$tick_char" \
        'BEGIN {
          # Danger (90%+): force full bar for visual urgency
          if (pct >= 90) { used = w }
          else { used = int(pct * w / 100 + 0.5) }
          if (used > w) used = w
          for (i = 0; i < w; i++) {
            if (i == tick+0 && i >= used) {
              printf "\033[2m%s\033[0m", tc
            } else if (i < used) {
              r = i / (w - 1)
              if (r < 0.5) { R = int(r*2*255); G = 200 }
              else         { R = 255; G = int((1-(r-0.5)*2)*200) }
              printf "\033[38;2;%d;%d;0m%s\033[0m", R, G, filled
            } else {
              printf "\033[2m%s\033[0m", empty
            }
          }
        }'
    return
  fi

  # ANSI 8-colour fallback: green → yellow → red zones
  local bar="" i used zone
  if [ "$pct" -ge 90 ] 2>/dev/null; then
    used="$width"
  else
    used=$(( (pct * width + 50) / 100 ))
  fi
  [ "$used" -gt "$width" ] && used="$width"
  i=0
  while [ "$i" -lt "$width" ]; do
    if [ "$i" -eq "$tick_pos" ] && [ "$i" -ge "$used" ]; then
      bar="${bar}${COLOUR_FAINT}${tick_char}${COLOUR_RESET}"
    elif [ "$i" -lt "$used" ]; then
      zone=$((i * 10 / width))
      if [ "$zone" -lt 5 ]; then
        bar="${bar}${COLOUR_GREEN}${filled}${COLOUR_RESET}"
      elif [ "$zone" -lt 8 ]; then
        bar="${bar}${COLOUR_YELLOW}${filled}${COLOUR_RESET}"
      else
        bar="${bar}${COLOUR_RED}${filled}${COLOUR_RESET}"
      fi
    else
      bar="${bar}${COLOUR_FAINT}${empty}${COLOUR_RESET}"
    fi
    i=$((i + 1))
  done
  printf '%s' "$bar"
}

build_bar_section() {
  # Returns: {bar} {pct}% {ctx_size?} {warn?}  — the bar chunk for line 1
  local pct width tick_pos
  pct="${CTX_PCT:-0}"
  width=10

  if ! [ "$pct" -ge 0 ] 2>/dev/null; then
    pct=0
  fi

  # Innovation 2: velocity tick position
  tick_pos=-1
  if [ "${FORECAST_HAS_CTX_TICK:-0}" = "1" ] && [ "${TERM_ASCII:-0}" != "1" ]; then
    tick_pos=$(awk -v c="$pct" -v v="${FORECAST_CTX_VELOCITY_PPM:-0}" -v w="$width" \
      'BEGIN { ct = c - v; if (ct < 0) ct = 0; printf "%d", int(w * ct / 100) }')
    if ! [ "$tick_pos" -ge 0 ] 2>/dev/null || ! [ "$tick_pos" -lt "$width" ] 2>/dev/null; then
      tick_pos=-1
    fi
  fi

  local bar
  bar="$(_build_gradient_bar "$pct" "$width" "$tick_pos")"
  # Structural guard: bar must always render; empty → force dim placeholders
  if [ -z "$bar" ]; then
    local _e; _e="-"; [ "${TERM_ASCII:-0}" != "1" ] && _e="░"
    local _i=0; bar=""
    while [ "$_i" -lt "$width" ]; do bar="${bar}${COLOUR_FAINT}${_e}${COLOUR_RESET}"; _i=$((_i+1)); done
  fi

  local pct_display
  if [ "$pct" -ge 0 ] 2>/dev/null; then
    pct_display="${pct}%"
  else
    pct_display="--%"
  fi

  # Compact context window size (e.g. 200k, 1M) — shown only at warning level (70%+)
  local ctx_size=""
  if [ "$pct" -ge 70 ] 2>/dev/null && [ "${CTX_WINDOW_SIZE:-0}" -gt 0 ] 2>/dev/null; then
    if [ "$CTX_WINDOW_SIZE" -ge 500000 ]; then
      ctx_size=" $((CTX_WINDOW_SIZE / 1000000))M"
    elif [ "$CTX_WINDOW_SIZE" -ge 1000 ]; then
      ctx_size=" $((CTX_WINDOW_SIZE / 1000))k"
    fi
  fi

  # Innovation 3: warning glyph + auto-compact countdown
  # 70-89%: countdown replaces glyph (glyph hidden when no countdown)
  # 90%+:   glyph always shows, countdown appended if available
  local warn warn_glyph
  warn=""
  if [ "${TERM_ASCII:-0}" = "1" ]; then
    warn_glyph="!"
  else
    warn_glyph="△"
  fi
  if [ "$pct" -ge 90 ] 2>/dev/null; then
    warn=" ${COLOUR_RED}${warn_glyph}${COLOUR_RESET}"
    if [ "${FORECAST_COMPACT_ETA_AVAILABLE:-0}" = "1" ]; then
      warn="${warn} ~${FORECAST_COMPACT_ETA_TURNS} turns"
    fi
  elif [ "$pct" -ge 70 ] 2>/dev/null; then
    if [ "${FORECAST_COMPACT_ETA_AVAILABLE:-0}" = "1" ]; then
      warn=" ~${FORECAST_COMPACT_ETA_TURNS} turns"
    fi
  elif [ "${EXCEEDS_200K:-0}" = "1" ]; then
    warn=" ${COLOUR_YELLOW}${warn_glyph}${COLOUR_RESET}"
  fi

  # Compact token count: 420000 → 420k, 1200000 → 1.2M
  local tok_display=""
  if [ "${CTX_TOKENS_USED:-0}" -gt 0 ] 2>/dev/null; then
    local t="$CTX_TOKENS_USED"
    if [ "$t" -ge 1000000 ]; then
      tok_display=" $(awk -v t="$t" 'BEGIN { printf "%.1fM", t/1000000 }')"
    elif [ "$t" -ge 1000 ]; then
      tok_display=" $((t / 1000))k"
    else
      tok_display=" ${t}"
    fi
    tok_display="${COLOUR_FAINT}${tok_display}${COLOUR_RESET}"
  fi

  # Order: bar pct% tokens warn ctx_size
  printf '%s %s%s%s%s' "$bar" "$pct_display" "$tok_display" "$warn" "$ctx_size"
}

build_state_glyph() {
  # Innovation 7: map STATE_VALUE to glyphs + colours per spec §7.7
  # Glyph colour matches model tier: faint=Haiku, accent=Sonnet, brand=Opus.
  local glyph colour tier_colour
  case "${MODEL_ID:-}" in
    *haiku*)  tier_colour="$COLOUR_FAINT" ;;
    *sonnet*) tier_colour="${COLOUR_ACCENT}" ;;
    *opus*)   tier_colour="${COLOUR_BRAND:-$COLOUR_ACCENT}" ;;
    *)        tier_colour="${COLOUR_BRAND:-$COLOUR_ACCENT}" ;;
  esac
  if [ "${TERM_ASCII:-0}" = "1" ]; then
    case "$STATE_VALUE" in
      streaming) glyph="<>";  colour="$tier_colour" ;;
      thinking)  glyph="<.>"; colour="$tier_colour" ;;
      *)         glyph="< >"; colour="$COLOUR_FAINT" ;;
    esac
  else
    case "$STATE_VALUE" in
      streaming) glyph="◆"; colour="$tier_colour" ;;
      thinking)  glyph="◈"; colour="$tier_colour" ;;
      *)         glyph="◇"; colour="$COLOUR_FAINT" ;;
    esac
  fi
  printf '%s%s%s' "$colour" "$glyph" "$COLOUR_RESET"
}

cost_colour_for_model() {
  # Innovation 4: model-aware cost colouring.
  # Args: $1=model_id, $2=cost_usd. Prints ANSI colour code or empty string.
  # Caller must emit COLOUR_RESET after the coloured value.
  local mid="${1:-}" cost="${2:-0}"
  local red yellow

  case "$mid" in
    claude-haiku-*)  red=2;  yellow=0.50 ;;
    claude-sonnet-*) red=8;  yellow=3 ;;
    claude-opus-*)   red=15; yellow=5 ;;
    *)               red=10; yellow=5 ;;
  esac

  awk -v c="$cost" -v r="$red" -v y="$yellow" \
      -v cr="${COLOUR_RED:-}" -v cy="${COLOUR_YELLOW:-}" '
    BEGIN {
      c+=0; r+=0; y+=0
      if (c >= r)      printf "%s", cr
      else if (c >= y) printf "%s", cy
    }'
}

build_cost_and_burn() {
  # Cost display with model-aware tier colouring (innovation 4),
  # burn-rate spike arrow (innovation 1), and $/hr secondary figure.
  #
  # Per spec §7.4:
  #   - Cost text turns yellow / red at thresholds keyed off model.id prefix.
  #   - When total_duration_ms > 300_000, append " ($X.XX/hr)" in faint ink.

  local cost arrow rate_str show_rate cost_colour

  # Base cost (always 2dp)
  cost="$(printf '%.2f' "${COST_TOTAL_USD:-0}")"

  # Tier colour for the cost number itself
  cost_colour="$(cost_colour_for_model "${MODEL_ID:-}" "$cost")"

  # Innovation 1: spike arrow. Glyph ↑ (Unicode) / ^ (ASCII).
  # Colour is accent for the warm theme, red elsewhere (spec §7.1).
  arrow=""
  if [ "${FORECAST_HAS_SPIKE:-0}" = "1" ]; then
    local arrow_glyph arrow_colour
    if [ "$TERM_ASCII" -eq 1 ]; then
      arrow_glyph="^"
    else
      arrow_glyph="↑"
    fi
    case "${THEME_NAME:-warm}" in
      warm) arrow_colour="$COLOUR_ACCENT" ;;
      *)    arrow_colour="$COLOUR_RED" ;;
    esac
    arrow="${arrow_colour}${arrow_glyph}${COLOUR_RESET} "
  fi

  show_rate=0
  if [ "${COST_DURATION_MS:-0}" -gt 300000 ] 2>/dev/null; then
    case "${FORECAST_SESSION_RATE_PER_HR:-0.00}" in
      0|0.0|0.00|"") show_rate=0 ;;
      *)             show_rate=1 ;;
    esac
  fi

  rate_str=""
  if [ "$show_rate" -eq 1 ]; then
    rate_str=$(printf ' %s($%s/hr)%s' \
      "$COLOUR_FAINT" "${FORECAST_SESSION_RATE_PER_HR:-0.00}" "$COLOUR_RESET")
  fi

  if [ -n "$cost_colour" ]; then
    printf '%s%s$%s%s%s' "$arrow" "$cost_colour" "$cost" "$COLOUR_RESET" "$rate_str"
  else
    printf '%s$%s%s' "$arrow" "$cost" "$rate_str"
  fi
}

build_session_tokens() {
  local total
  total=$(( ${COST_INPUT_TOKENS:-0} + ${COST_OUTPUT_TOKENS:-0} ))
  [ "$total" -le 0 ] 2>/dev/null && return 0

  local display
  if [ "$total" -ge 1000000 ]; then
    display="$(awk -v t="$total" 'BEGIN { printf "%.1fM tok", t/1000000 }')"
  elif [ "$total" -ge 1000 ]; then
    display="$((total / 1000))k tok"
  else
    display="${total} tok"
  fi

  printf '%s%s%s' "$COLOUR_FAINT" "$display" "$COLOUR_RESET"
}

build_duration() {
  if [ "${COST_DURATION_MS:-0}" -lt 0 ] 2>/dev/null; then
    printf '--'
    return 0
  fi
  local total_s=$((COST_DURATION_MS / 1000))
  local h=$(( total_s / 3600 ))
  local m=$(( (total_s % 3600) / 60 ))
  local s=$(( total_s % 60 ))

  local dur_str
  if [ "$h" -ge 1 ] 2>/dev/null; then
    dur_str="$(printf '%dh%dm' "$h" "$m")"
  elif [ "$m" -ge 1 ] 2>/dev/null; then
    dur_str="$(printf '%dm%ds' "$m" "$s")"
  else
    dur_str="$(printf '%ds' "$s")"
  fi

  # Colour by session age: <15m faint, 15-60m default, 1-3h amber, 3h+ red
  local dur_colour=""
  if [ "$total_s" -ge 10800 ] 2>/dev/null; then
    dur_colour="$COLOUR_RED"
  elif [ "$total_s" -ge 3600 ] 2>/dev/null; then
    dur_colour="$COLOUR_ACCENT"
  elif [ "$total_s" -lt 900 ] 2>/dev/null; then
    dur_colour="$COLOUR_FAINT"
  fi

  if [ -n "$dur_colour" ]; then
    printf '%s%s%s' "$dur_colour" "$dur_str" "$COLOUR_RESET"
  else
    printf '%s' "$dur_str"
  fi
}

format_eta_secs() {
  # Convert seconds to human-readable: 47m / 2h 14m / 3d 6h (no seconds shown)
  local secs="${1:-0}"
  if [ "$secs" -le 0 ] 2>/dev/null; then
    printf 'now'
    return
  fi
  local days hours mins
  days=$((secs / 86400))
  hours=$(( (secs % 86400) / 3600 ))
  mins=$(( (secs % 3600) / 60 ))
  if [ "$days" -ge 1 ] 2>/dev/null; then
    if [ "$hours" -gt 0 ] 2>/dev/null; then
      printf '%dd %dh' "$days" "$hours"
    else
      printf '%dd' "$days"
    fi
  elif [ "$hours" -ge 1 ] 2>/dev/null; then
    if [ "$mins" -gt 0 ] 2>/dev/null; then
      printf '%dh %dm' "$hours" "$mins"
    else
      printf '%dh' "$hours"
    fi
  else
    printf '%dm' "$mins"
  fi
}

build_rate_limits() {
  # Show ↑X% for the worse window; prefix "7d" when the weekly window dominates
  # so the reader knows the pressure won't clear in hours.
  # Hidden when both are ≤0. Red at >=80%; faint otherwise.
  # At >=80% append reset ETA when available.
  local now
  now="${CLAUDE_STATUSLINE_NOW:-$(date +%s)}"

  local pct5="${RL_5H_PCT:--1}"
  local pct7="${RL_7D_PCT:--1}"

  local max_pct=0
  local max_resets_at=""
  local window_label=""
  if [ "$pct5" -ge 0 ] 2>/dev/null && [ "$pct5" -gt "$max_pct" ] 2>/dev/null; then
    max_pct="$pct5"
    max_resets_at="${RL_5H_RESETS_AT:-}"
    window_label=""
  fi
  if [ "$pct7" -ge 0 ] 2>/dev/null && [ "$pct7" -gt "$max_pct" ] 2>/dev/null; then
    max_pct="$pct7"
    max_resets_at="${RL_7D_RESETS_AT:-}"
    window_label="7d"
  fi

  [ "$max_pct" -le 0 ] 2>/dev/null && return 0

  local trend_glyph
  if [ "${TERM_ASCII:-0}" = "1" ]; then
    trend_glyph="^"
  else
    trend_glyph="↑"
  fi

  local eta_str=""
  if [ "$max_pct" -ge 80 ] 2>/dev/null && [ -n "$max_resets_at" ]; then
    local eta_secs
    eta_secs=$(( ${max_resets_at%.*} - now ))
    eta_str=" · ${COLOUR_RED}resets $(format_eta_secs "$eta_secs")${COLOUR_RESET}"
  fi

  if [ "$max_pct" -ge 80 ] 2>/dev/null; then
    printf '%s%s%s%s%%%s%s' "$COLOUR_RED" "$window_label" "$trend_glyph" "$max_pct" "$COLOUR_RESET" "$eta_str"
  else
    printf '%s%s%s%s%%%s' "$COLOUR_FAINT" "$window_label" "$trend_glyph" "$max_pct" "$COLOUR_RESET"
  fi
}

build_workspace_line() {
  # Line 2: {glyph}{branch}{dirty?} │ {lines?} │ {dir} │ ...
  local branch dir agent git_cache dirty_cache cache_mtime now
  branch="${WORKTREE_BRANCH:-}"
  dir="${WORKSPACE_DIR:-}"
  agent="${AGENT_NAME:-}"

  dir="${dir##*/}"
  [ -z "$dir" ] && dir="."

  now="$(date +%s)"

  # Live git branch (cached 5s)
  if [ -z "$branch" ] && [ "${CLAUDE_STATUSLINE_NO_GIT:-0}" != "1" ] && \
     [ -n "${SESSION_ID:-}" ]; then
    git_cache="/tmp/claude-statusline-git-${SESSION_ID}"
    cache_mtime="$(stat -f %m "$git_cache" 2>/dev/null || \
                   stat -c %Y "$git_cache" 2>/dev/null || echo 0)"
    if [ "$((now - cache_mtime))" -gt 5 ]; then
      git branch --show-current 2>/dev/null > "$git_cache" || printf '' > "$git_cache"
    fi
    branch="$(cat "$git_cache" 2>/dev/null || true)"
  fi

  [ -z "$branch" ] && branch="(no-branch)"

  # Branch prefix glyph
  local branch_glyph
  if [ "${TERM_ASCII:-0}" = "1" ]; then
    branch_glyph="/"
  else
    branch_glyph="⌿"
  fi

  # Dirty indicator (cached 5s)
  local dirty=""
  if [ "${CLAUDE_STATUSLINE_NO_GIT:-0}" != "1" ] && [ -n "${SESSION_ID:-}" ]; then
    dirty_cache="/tmp/claude-statusline-dirty-${SESSION_ID}"
    cache_mtime="$(stat -f %m "$dirty_cache" 2>/dev/null || \
                   stat -c %Y "$dirty_cache" 2>/dev/null || echo 0)"
    if [ "$((now - cache_mtime))" -gt 5 ]; then
      if git status --porcelain 2>/dev/null | grep -q .; then
        printf '*' > "$dirty_cache" 2>/dev/null || true
      else
        printf '' > "$dirty_cache" 2>/dev/null || true
      fi
    fi
    dirty="$(cat "$dirty_cache" 2>/dev/null || true)"
  fi

  # Lines added/removed from session cost data
  local lines_str=""
  local added="${COST_LINES_ADDED:-0}"
  local removed="${COST_LINES_REMOVED:-0}"
  if [ "$added" -gt 0 ] 2>/dev/null || [ "$removed" -gt 0 ] 2>/dev/null; then
    lines_str="${COLOUR_GREEN}+${added}${COLOUR_RESET}/${COLOUR_RED}-${removed}${COLOUR_RESET}"
  fi

  local mcp_health multi_inst
  mcp_health="$(safe_section build_mcp_health)"
  multi_inst="$(safe_section build_multi_instance)"

  local sep="  ${COLOUR_FAINT}${SYMBOL_BAR_SEPARATOR}${COLOUR_RESET}  "
  local line="${branch_glyph}${branch}${dirty}${sep}"
  [ -n "$lines_str" ] && line="${line}${lines_str}${sep}"
  line="${line}${dir}"
  [ -n "${SESSION_NAME:-}" ] && line="${line}${sep}${COLOUR_FAINT}${SESSION_NAME}${COLOUR_RESET}"
  [ -n "$mcp_health" ]  && line="${line}${sep}${mcp_health}"
  [ -n "$multi_inst" ]  && line="${line}${sep}${multi_inst}"
  [ -n "$agent" ]       && line="${line}${sep}${agent}"
  printf '%s' "$line"
}

build_mcp_health() {
  # Innovation 5: ⚡{healthy}/{total} — silently disabled when mcp_servers absent/empty.
  if [ -z "${MCP_SERVERS_JSON:-}" ] || [ "$MCP_SERVERS_JSON" = "[]" ] || \
     [ "$MCP_SERVERS_JSON" = "null" ]; then
    return 0
  fi

  local total healthy
  total=$(printf '%s' "$MCP_SERVERS_JSON" | jq 'length' 2>/dev/null) || return 0
  [ -z "${total:-}" ] && return 0
  [ "$total" -eq 0 ] 2>/dev/null && return 0

  healthy=$(printf '%s' "$MCP_SERVERS_JSON" | \
    jq '[.[] | select(.status == "connected")] | length' 2>/dev/null) || healthy=0

  if [ "${healthy:-0}" -lt "${total:-1}" ] 2>/dev/null; then
    printf '⚡%s%d/%d%s' "$COLOUR_RED" "$healthy" "$total" "$COLOUR_RESET"
  else
    printf '%s⚡%d/%d%s' "$COLOUR_FAINT" "$healthy" "$total" "$COLOUR_RESET"
  fi
}

build_multi_instance() {
  # Innovation 9: ⊞{N} when multiple Claude instances are active.
  # Counts session files modified <5min. Cached 10s. Hidden when N≤1.
  local sessions_dir="${CLAUDE_STATUSLINE_SESSIONS_DIR:-$HOME/.claude/sessions}"
  [ ! -d "$sessions_dir" ] && return 0

  local cache_file="/tmp/claude-statusline-instances-cache"
  local now
  now=$(date +%s)
  local cache_mtime
  cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || \
                stat -c %Y "$cache_file" 2>/dev/null || echo 0)

  local total
  if [ "$((now - cache_mtime))" -le 10 ]; then
    total=$(cat "$cache_file" 2>/dev/null || echo 0)
  else
    total=0
    local f mtime age
    while IFS= read -r f; do
      mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
      age=$((now - mtime))
      [ "$age" -le 300 ] && total=$((total + 1))
    done < <(find "$sessions_dir" -maxdepth 1 -type f -name "*.json" 2>/dev/null)
    printf '%d' "$total" > "$cache_file" 2>/dev/null || true
  fi

  [ "${total:-0}" -le 1 ] 2>/dev/null && return 0

  local colour=""
  [ "$total" -ge 3 ] 2>/dev/null && colour="$COLOUR_YELLOW"

  if [ "$TERM_ASCII" -eq 1 ]; then
    local others=$((total - 1))
    printf '%s[+%d]%s' "$colour" "$others" "${colour:+$COLOUR_RESET}"
  else
    printf '%s⊞%d%s' "$colour" "$total" "${colour:+$COLOUR_RESET}"
  fi
}

build_trace_line() {
  # Innovation 6: ↳ tool1 · tool2 · tool3 from /tmp/claude-statusline-tools-${SESSION_ID}
  # Tool log populated by a PostToolUse hook (one tool name per line).
  if [ "${CLAUDE_STATUSLINE_TRACE:-0}" != "1" ]; then
    return 0
  fi

  [ -z "${SESSION_ID:-}" ] && return 0

  local tool_log="/tmp/claude-statusline-tools-${SESSION_ID}"
  [ ! -s "$tool_log" ] && return 0

  # Last 5 entries, dedup-collapse consecutive repeats (view·view·bash → view·bash)
  local tools
  tools=$(tail -5 "$tool_log" 2>/dev/null | awk '
    NR == 1 { prev = $0; next }
    $0 != prev { print prev }
    { prev = $0 }
    END { if (prev != "") print prev }
  ') || return 0
  [ -z "$tools" ] && return 0

  local prefix="-> "
  if [ "$TERM_ASCII" -ne 1 ]; then
    prefix="↳ "
  fi

  # Older entries faint; most recent (rightmost) in default colour.
  local result
  result=$(printf '%s' "$tools" | awk \
    -v faint="$COLOUR_FAINT" -v reset="$COLOUR_RESET" -v prefix="$prefix" '
    { lines[NR] = $0 }
    END {
      n = NR
      printf "%s", prefix
      for (i = 1; i <= n; i++) {
        if (i > 1) printf " \xc2\xb7 "
        if (i < n) printf "%s%s%s", faint, lines[i], reset
        else        printf "%s", lines[i]
      }
    }
  ')

  # Truncate at 80 printable columns
  local plain
  plain=$(printf '%s' "$result" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')
  if [ "${#plain}" -gt 80 ]; then
    result=$(printf '%s' "$plain" | cut -c1-80)
  fi

  printf '%s' "$result"
}

###############################################################################
# Main
###############################################################################

main() {
  local start_ms end_ms
  start_ms="$(time_ms)"

  detect_terminal_capabilities
  load_theme_library
  apply_theme_preset
  apply_explicit_overrides

  parse_input_json

  source_history_lib
  source_forecast_lib
  append_history_row
  compute_burn_rate_and_velocity

  # Line 1 pieces
  local line1_bar line1_state line1_cost line1_tokens line1_dur line1_rate
  line1_bar="$(safe_section build_bar_section)"
  line1_state="$(safe_section build_state_glyph)"
  line1_cost="$(safe_section build_cost_and_burn)"
  line1_tokens="$(safe_section build_session_tokens)"
  line1_dur="$(safe_section build_duration)"
  line1_rate="$(safe_section build_rate_limits)"

  # Faint separators let data pop; 2 spaces each side for breathing room
  local sep="  ${COLOUR_FAINT}${SYMBOL_BAR_SEPARATOR}${COLOUR_RESET}  "

  # Colour model name by tier; synthesise "Claude " prefix if API omits it.
  local _mname="${MODEL_DISPLAY_NAME:-}"
  [[ "$_mname" != Claude* ]] && _mname="Claude $_mname"
  local model_coloured="$_mname"
  case "${MODEL_ID:-}" in
    *haiku*)  model_coloured="${COLOUR_FAINT}${_mname}${COLOUR_RESET}" ;;
    *sonnet*) model_coloured="${COLOUR_ACCENT}${_mname}${COLOUR_RESET}" ;;
    *opus*)   model_coloured="${COLOUR_BRAND}${_mname}${COLOUR_RESET}" ;;
  esac

  local fast_badge=""
  [ "${FAST_MODE:-0}" = "1" ] && fast_badge=" ${COLOUR_ACCENT}fast${COLOUR_RESET}"

  local line1
  line1="${line1_state} ${model_coloured}${fast_badge}${sep}${line1_bar}${sep}${line1_cost}"
  [ -n "$line1_tokens" ] && line1="${line1}${sep}${line1_tokens}"
  line1="${line1}${sep}${line1_dur}"
  [ -n "$line1_rate" ] && line1="${line1}${sep}${line1_rate}"

  # Line 2
  local line2
  line2="$(safe_section build_workspace_line)"

  # Line 3 (optional trace)
  local line3=""
  if [ "${CLAUDE_STATUSLINE_TRACE:-0}" = "1" ]; then
    line3="$(safe_section build_trace_line)"
  fi

  # Output: single newline between lines — Claude Code's renderer swallows blank lines.
  if [ -n "$line3" ]; then
    printf '%b\n%b\n%b' "$line1" "$line2" "$line3"
  else
    printf '%b\n%b' "$line1" "$line2"
  fi

  end_ms="$(time_ms)"
  debug_log "total_ms=$((end_ms - start_ms))"
}

main "$@"