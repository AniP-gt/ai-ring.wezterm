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
PANE_ID="${WEZTERM_PANE:-}"

if [ -z "$PANE_ID" ]; then
  exit 0
fi

ENCODED=$(printf '%s' "$STATUS" | base64)
OSC=$(printf '\033]1337;SetUserVar=%s=%s\007' "AI_RING" "$ENCODED")

# Try multiple output methods
if [ -t 1 ]; then
  # stdout is a terminal
  printf '%s' "$OSC"
elif [ -w /dev/tty ]; then
  # Write directly to controlling terminal
  printf '%s' "$OSC" > /dev/tty
else
  # Last resort: use wezterm cli send-text
  printf '%s' "$OSC" | wezterm cli send-text --pane-id "$PANE_ID" --no-paste
fi
