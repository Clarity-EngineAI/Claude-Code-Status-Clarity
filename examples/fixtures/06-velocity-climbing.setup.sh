#!/usr/bin/env bash
# Seed history for the velocity-climbing fixture.
# Five rows over 3 minutes give a history older than 60s so the tick fires.
# Row at (now-30) has ctx=74; current ctx=75 -> velocity=+1 -> tick at pos 14.
# Recent cost delta is tiny so no spike fires.
# Append in statusline adds a 6th row (tokens=750000 > 190000 = turn 5).
# ETA: in_tok+out_tok=200000, turns=5, avg=40000, remain=200000 -> eta=5.
HISTORY_FILE="/tmp/claude-statusline-history-${SESSION_ID}"
NOW=$(date +%s)
{
  printf '%s|2.70|69|10000|\n'   "$((NOW - 180))"
  printf '%s|2.80|71|50000|\n'   "$((NOW - 120))"
  printf '%s|2.90|73|100000|\n'  "$((NOW -  90))"
  printf '%s|2.995|74|150000|\n' "$((NOW -  30))"
  printf '%s|2.999|74|190000|\n' "$((NOW -   5))"
} > "$HISTORY_FILE"
