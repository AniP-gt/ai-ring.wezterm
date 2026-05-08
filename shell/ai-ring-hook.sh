#!/bin/bash
# ai-ring-hook.sh - Claude Code / OpenCode hook script for ai-ring.wezterm
#
# Sends OSC 1337 user variable to the WezTerm pane.
# If stdout is not a terminal (hook captures output), falls back to
# writing directly to the pane's tty via /dev/tty, or uses wezterm cli.
#
# Usage:
#   ai-ring-hook.sh done     # mark agent as done
#   ai-ring-hook.sh running  # mark agent as running

STATUS="${1:-done}"
AGENT="${2:-claude}"
PANE_ID="${WEZTERM_PANE:-}"

if [ -z "$PANE_ID" ]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_HOOK="$SCRIPT_DIR/cc-glow-state.sh"

if [ -x "$STATE_HOOK" ]; then
  exec "$STATE_HOOK" "$STATUS" "$AGENT"
fi

ENCODED=$(printf '%s' "$STATUS" | base64)
# Build inner OSC sequence
INNER=$(printf '\033]1337;SetUserVar=%s=%s\007' "AI_RING" "$ENCODED")
# Wrap with tmux DCS passthrough if running inside tmux
if [ -n "${TMUX:-}" ]; then
  OSC=$(printf '\033Ptmux;\033%s\033\\' "$INNER")
else
  OSC="$INNER"
fi

# Try multiple output methods
if [ -t 1 ]; then
  # stdout is a terminal
  printf '%s' "$OSC"
elif [ -e /dev/tty ] && (printf '%s' "$OSC" > /dev/tty) 2>/dev/null; then
  # Write directly to controlling terminal
  exit 0
elif command -v wezterm >/dev/null 2>&1 && printf '%s' "$INNER" | wezterm cli send-text --pane-id "$PANE_ID" --no-paste 2>/dev/null; then
  # Last resort: use wezterm cli send-text (IPC direct — no tmux wrapping needed)
  exit 0
else
  printf '%s' "$INNER"
fi
