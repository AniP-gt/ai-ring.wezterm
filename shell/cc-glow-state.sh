#!/bin/bash
# cc-glow-state.sh - persist cc-glow pane state and notify WezTerm.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANE_ID="${WEZTERM_PANE:-}"

if [ -z "$PANE_ID" ]; then
  exit 0
fi

INNER="$(python3 "$SCRIPT_DIR/cc-glow-state.py" "$@")"

if [ -n "${TMUX:-}" ]; then
  OSC=$(printf '\033Ptmux;\033%s\033\\' "$INNER")
else
  OSC="$INNER"
fi

if [ -t 1 ]; then
  printf '%s' "$OSC"
elif [ -e /dev/tty ] && (printf '%s' "$OSC" > /dev/tty) 2>/dev/null; then
  exit 0
elif command -v wezterm >/dev/null 2>&1 && printf '%s' "$INNER" | wezterm cli send-text --pane-id "$PANE_ID" --no-paste 2>/dev/null; then
  exit 0
else
  printf '%s' "$INNER"
fi
