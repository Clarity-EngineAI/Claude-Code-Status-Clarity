#!/usr/bin/env bash
# Seed history for the burn-spike fixture.
# Two rows: one outside the 60s window (no-spike anchor) and one inside
# that shows a large cost jump -> recent_rate >> session_rate -> spike fires.
# ctx_then (45) > ctx_now (42) so velocity is negative -> tick suppressed.
HISTORY_FILE="/tmp/claude-statusline-history-${SESSION_ID}"
NOW=$(date +%s)
{
  printf '%s|1.50|40|380000|\n' "$((NOW - 70))"
  printf '%s|1.90|45|400000|\n' "$((NOW - 10))"
} > "$HISTORY_FILE"
