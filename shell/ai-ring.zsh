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

__ai_ring_set_user_var() {
  local encoded
  encoded="$(printf '%s' "$2" | base64)"
  if [[ -n "${TMUX:-}" ]]; then
    printf '\033Ptmux;\033\033]1337;SetUserVar=%s=%s\007\033\\' "$1" "$encoded"
  else
    printf '\033]1337;SetUserVar=%s=%s\007' "$1" "$encoded"
  fi
}

__ai_ring_preexec() {
  local cmd="${1%% *}"
  cmd="${cmd##*/}"
  for agent in "${AI_RING_AGENTS[@]}"; do
    if [[ "$cmd" == "$agent" ]]; then
      _ai_ring_active=1
      __ai_ring_set_user_var "AI_RING" "running"
      return
    fi
  done
}

__ai_ring_precmd() {
  if [[ -n "$_ai_ring_active" ]]; then
    _ai_ring_active=""
    __ai_ring_set_user_var "AI_RING" "done"
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec __ai_ring_preexec
add-zsh-hook precmd __ai_ring_precmd
