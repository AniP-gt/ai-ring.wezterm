#!/bin/bash
# wezterm-overlay.sh - Show a status dot in the WezTerm pane
#
# Usage:
#   wezterm-overlay.sh done       # green ●
#   wezterm-overlay.sh waiting    # blue ●
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

[ -w /dev/tty ] || exit 0

export TERM=xterm-256color

# Load position config (defaults: bottom-left)
OVERLAY_ROW="bottom"
OVERLAY_COL="left"
OVERLAY_ROW_OFFSET=3
COLOR_DONE="#A6E22E"
COLOR_WAITING="#66D9EF"
COLOR_IN_PROGRESS="#66D9EF"
CONF="$(dirname "$0")/wezterm-overlay.conf"
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

case "$ACTION" in
  done)        COLOR="$COLOR_DONE" ;;
  waiting)     COLOR="$COLOR_WAITING" ;;
  in_progress) COLOR="$COLOR_IN_PROGRESS" ;;
  *)           exit 0 ;;
esac

hex_to_rgb() {
  local hex="${1#\#}"
  if [ "${#hex}" -ne 6 ]; then
    printf '255;255;255'
    return
  fi
  printf '%d;%d;%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

DOT="●"
CLEAR_WIDTH=4
COLS=$(tput cols </dev/tty)
ROWS=$(tput lines </dev/tty)

case "$OVERLAY_ROW" in
  bottom) ROW=$(( ROWS - OVERLAY_ROW_OFFSET )) ;;
  *)      ROW=$(( OVERLAY_ROW_OFFSET - 1 )) ;;
esac

case "$OVERLAY_COL" in
  left)  COL=0 ;;
  *)     COL=$(( COLS - CLEAR_WIDTH )) ;;
esac

{
  tput sc
  tput cup "$ROW" "$COL"
  printf '\033[38;2;%sm%s\033[0m   ' "$(hex_to_rgb "$COLOR")" "$DOT"
  tput rc
} >/dev/tty
