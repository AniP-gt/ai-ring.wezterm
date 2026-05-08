# ai-ring.zsh - Shell hooks for ai-ring.wezterm
#
# Source this file in your .zshrc:
#   source /path/to/ai-ring.wezterm/shell/ai-ring.zsh
#
# Override the agent list before sourcing if needed:
#   AI_RING_AGENTS=(claude opencode aider)

# Configurable agent list (user can override before sourcing)
(( ${#AI_RING_AGENTS[@]} )) || AI_RING_AGENTS=(claude opencode)

# Internal state
typeset -g _ai_ring_active=""
typeset -g _ai_ring_active_agent=""
typeset -g _ai_ring_script_dir="${${(%):-%N}:A:h}"

__ai_ring_set_user_var() {
  local encoded
  encoded="$(printf '%s' "$2" | base64)"
  if [[ -n "${TMUX:-}" ]]; then
    printf '\033Ptmux;\033\033]1337;SetUserVar=%s=%s\007\033\\' "$1" "$encoded"
  else
    printf '\033]1337;SetUserVar=%s=%s\007' "$1" "$encoded"
  fi
}

__ai_ring_set_state() {
  local status="$1"
  local agent="${2:-agent}"
  local state_hook="$_ai_ring_script_dir/cc-glow-state.sh"

  if [[ -x "$state_hook" && -n "${WEZTERM_PANE:-}" ]]; then
    "$state_hook" "$status" "$agent"
  else
    __ai_ring_set_user_var "AI_RING" "$status"
  fi
}

__ai_ring_preexec() {
  local cmd="${1%% *}"
  cmd="${cmd##*/}"
  for agent in "${AI_RING_AGENTS[@]}"; do
    if [[ "$cmd" == "$agent" ]]; then
      _ai_ring_active=1
      _ai_ring_active_agent="$agent"
      __ai_ring_set_state "running" "$agent"
      return
    fi
  done
}

__ai_ring_precmd() {
  if [[ -n "$_ai_ring_active" ]]; then
    _ai_ring_active=""
    __ai_ring_set_state "done" "${_ai_ring_active_agent:-agent}"
    _ai_ring_active_agent=""
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec __ai_ring_preexec
add-zsh-hook precmd __ai_ring_precmd
