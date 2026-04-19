#!/bin/bash
# wezterm-bg.sh - Change WezTerm pane background color via OSC 11
#
# Usage:
#   wezterm-bg.sh done    # green tint (agent finished)
#   wezterm-bg.sh reset   # restore default background
#
# Designed to be called from Claude Code hooks (Stop / PreToolUse / UserPromptSubmit).
# Output is written to /dev/tty because hooks capture stdout.
#
# Colors can be customized in wezterm-bg.conf in the same directory:
#   COLOR_DONE=<hex>   (default: #0d2b0d)
#
# Install:
#   cp shell/wezterm-bg.sh ~/.claude/hooks/
#   cp shell/wezterm-bg.conf ~/.claude/hooks/   # optional, to customize colors
#   chmod +x ~/.claude/hooks/wezterm-bg.sh

ACTION="${1:-}"

# Load color config (defaults)
COLOR_DONE="#0d2b0d"
CONF="$(dirname "$0")/wezterm-bg.conf"
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

case "$ACTION" in
  done)  OSC=$(printf '\033]11;%s\033\\' "$COLOR_DONE") ;;
  reset) OSC=$(printf '\033]111\033\\') ;;
  *)     exit 0 ;;
esac

if [ -w /dev/tty ]; then
  printf '%s' "$OSC" >/dev/tty
elif [ -t 1 ]; then
  printf '%s' "$OSC"
fi
