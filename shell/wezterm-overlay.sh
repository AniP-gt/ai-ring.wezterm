#!/bin/bash
# wezterm-overlay.sh - Show a status overlay in the WezTerm pane
#
# Usage:
#   wezterm-overlay.sh waiting    # ❓ WAITING
#
# Designed to be called from Claude Code Notification hooks.
# Works reliably because Claude Code's TUI halts while waiting for user input.
# Output is written to /dev/tty because hooks capture stdout.
#
# Position is controlled by wezterm-overlay.conf in the same directory:
#   OVERLAY_ROW=top|bottom        (default: bottom)
#   OVERLAY_COL=right|left        (default: left)
#   OVERLAY_ROW_OFFSET=<number>   (default: 3, lines from edge)
#
# Install:
#   cp shell/wezterm-overlay.sh ~/.claude/hooks/
#   cp shell/wezterm-overlay.conf ~/.claude/hooks/   # optional, to customize position
#   chmod +x ~/.claude/hooks/wezterm-overlay.sh

ACTION="${1:-}"

case "$ACTION" in
  waiting)     MSG="❓ WAITING    " ;;
  in_progress) MSG="🚀 IN PROGRESS" ;;
  *)           exit 0 ;;
esac

[ -w /dev/tty ] || exit 0

export TERM=xterm-256color

# Load position config (defaults: bottom-left)
OVERLAY_ROW="bottom"
OVERLAY_COL="left"
OVERLAY_ROW_OFFSET=3
CONF="$(dirname "$0")/wezterm-overlay.conf"
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

MSG_LEN="${#MSG}"
COLS=$(tput cols </dev/tty)
ROWS=$(tput lines </dev/tty)

case "$OVERLAY_ROW" in
  bottom) ROW=$(( ROWS - OVERLAY_ROW_OFFSET )) ;;
  *)      ROW=$(( OVERLAY_ROW_OFFSET - 1 )) ;;
esac

case "$OVERLAY_COL" in
  left)  COL=0 ;;
  *)     COL=$(( COLS - MSG_LEN )) ;;
esac

{
  tput sc
  tput cup "$ROW" "$COL"
  printf '%s' "$MSG"
  tput rc
} >/dev/tty
