#!/usr/bin/env bash
# Seed 2 session files (current + 1 other) → total 2 → [+1] (default colour)
sessions_dir="/tmp/claude-statusline-sessions-test"
mkdir -p "$sessions_dir"
rm -f "$sessions_dir"/*.json
printf '{"sessionId":"%s"}' "$SESSION_ID" > "$sessions_dir/current.json"
printf '{"sessionId":"other-session-abc"}' > "$sessions_dir/other.json"
touch "$sessions_dir/current.json" "$sessions_dir/other.json"
rm -f /tmp/claude-statusline-instances-cache
