#!/usr/bin/env bash
# Theme presets for Claude Code statusline (Clarity Engine)

# Public API:
#   theme_load_preset THEME_NAME TERM_TRUECOLOR TERM_ASCII TERM_NERDFONT
#   theme_force_ascii
#   theme_force_powerline
#   theme_force_nerdfont
#
# Must set global vars used by statusline.sh:
#   SYMBOL_BAR_SEPARATOR
#   SYMBOL_POWERLINE_LEFT
#   COLOUR_ACCENT
#   COLOUR_FAINT
#   COLOUR_RESET

# Base colours (24-bit when available, fall back to 8-colour)
_colour_24_or_basic() {
  # $1=r, $2=g, $3=b, $4=basic-fallback-code
  local r=$1 g=$2 b=$3 basic=$4
  if [ "${1+set}" = "set" ] && [ "${TERM_TRUECOLOR:-0}" = "1" ]; then
    printf '\033[38;2;%s;%s;%sm' "$r" "$g" "$b"
  else
    printf '\033[%sm' "$basic"
  fi
}

theme_set_common_defaults() {
  COLOUR_RESET=$'\033[0m'
  COLOUR_FAINT=$'\033[2m'
  COLOUR_GREEN=$'\033[32m'
  COLOUR_YELLOW=$'\033[33m'
  COLOUR_RED=$'\033[31m'
  # Anthropic brand purple (#7266EA) — always used for the ◆ glyph
  COLOUR_BRAND=$(_colour_24_or_basic 114 102 234 "35")
  SYMBOL_BAR_SEPARATOR="│"
  SYMBOL_POWERLINE_LEFT=""
}

theme_preset_warm() {
  theme_set_common_defaults
  # signal-amber: 226,150,76 truecolour; ANSI 33 (yellow) as 8-colour approximation
  COLOUR_ACCENT=$(_colour_24_or_basic 226 150 76 "33")
}

theme_preset_cool() {
  theme_set_common_defaults
  # Anthropic purple: 114,102,234 with basic fallback 35
  COLOUR_ACCENT=$(_colour_24_or_basic 114 102 234 "35")
}

theme_preset_mono() {
  theme_set_common_defaults
  COLOUR_ACCENT=$'\033[37m'  # white
}

theme_preset_terminal_classic() {
  theme_set_common_defaults
  SYMBOL_BAR_SEPARATOR="|"
  COLOUR_ACCENT=$'\033[32m'  # green
}

theme_preset_nerdfont_powerline() {
  theme_set_common_defaults
  # Powerline theme assumes Nerdfont is present
  SYMBOL_POWERLINE_LEFT=$'\ue0b0'  # typical powerline left triangle
  # signal-amber: same as warm — ANSI 33 fallback for 8-colour terminals
  COLOUR_ACCENT=$(_colour_24_or_basic 226 150 76 "33")
}

theme_load_preset() {
  local name="${1:-warm}"
  TERM_TRUECOLOR="${2:-0}"
  local _ascii="${3:-0}"
  local _nerdfont="${4:-0}"

  case "$name" in
    cool)               theme_preset_cool ;;
    mono)               theme_preset_mono ;;
    terminal-classic)   theme_preset_terminal_classic ;;
    nerdfont-powerline) theme_preset_nerdfont_powerline ;;
    warm|*)             theme_preset_warm ;;
  esac

  # Apply hint flags immediately (these can be refined by explicit overrides)
  if [ "$_ascii" = "1" ]; then
    theme_force_ascii
  fi
  if [ "$_nerdfont" = "1" ]; then
    theme_force_nerdfont
  fi
}

theme_force_ascii() {
  SYMBOL_BAR_SEPARATOR="|"
  SYMBOL_POWERLINE_LEFT=""
  # For ASCII mode, keep colours but avoid special glyphs elsewhere.
}

theme_force_powerline() {
  # Ensure a powerline separator even if theme didn’t set one
  if [ -z "${SYMBOL_POWERLINE_LEFT:-}" ]; then
    SYMBOL_POWERLINE_LEFT=$'\ue0b0'
  fi
}

theme_force_nerdfont() {
  # This hook exists mainly to let the main script choose Nerd Font symbols.
  :
}