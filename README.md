# ai-ring.wezterm

A WezTerm plugin that shows a dot indicator (●) on tabs when AI agents (Claude Code, OpenCode, etc.) finish their work. Like tmux's activity monitoring, but for AI coding agents.

- No polling, no text scanning -- uses WezTerm user variables via OSC 1337
- Per-pane tracking -- works with split panes
- Dot clears when you focus the pane

## How it works

```
Shell (preexec/precmd)  --OSC 1337-->  WezTerm Plugin (Lua)
  AI_RING=running                       user-var-changed -> state update
  AI_RING=done                          format-tab-title -> ● on tab
                                        update-status -> clear on focus
```

1. You run `claude` or `opencode` in a terminal pane
2. The shell hook sets a WezTerm user variable to `running` (yellow ●)
3. When the agent exits, the variable is set to `done` (green ●)
4. When you focus that pane, the dot clears
5. With split panes, each pane is tracked independently -- the tab dot remains until all done panes are acknowledged

## Installation

### 1. Add the plugin to your `wezterm.lua`

```lua
local wezterm = require 'wezterm'
local ai_ring = wezterm.plugin.require 'https://github.com/AniP-gt/ai-ring.wezterm'

local config = wezterm.config_builder()

ai_ring.apply_to_config(config)

return config
```

### 2. Source the shell hook in your `.zshrc`

```zsh
source /path/to/ai-ring.wezterm/shell/ai-ring.zsh
```

Or if installed via `wezterm.plugin.require`, the plugin is cached at:

```zsh
# macOS
source "$HOME/Library/Application Support/wezterm/plugins/*/ai-ring.wezterm/shell/ai-ring.zsh"
```

## Configuration

```lua
ai_ring.apply_to_config(config, {
  indicator = '●',         -- dot character (default: '●')
  color_done = 'green',    -- color when agent finished (default: 'green')
  color_running = 'yellow', -- color while agent is running (default: 'yellow')
  position = 'left',       -- 'left' or 'right' of tab title (default: 'left')
})
```

### Custom agent list

By default, `claude` and `opencode` are watched. Override before sourcing:

```zsh
AI_RING_AGENTS=(claude opencode aider gemini)
source /path/to/ai-ring.wezterm/shell/ai-ring.zsh
```

## Limitations

- **`format-tab-title` is exclusive**: WezTerm only runs the first registered `format-tab-title` handler. If another plugin or your config also uses this event, they will conflict. In that case, you can call `ai-ring`'s logic manually from your own handler.
- **Local panes only**: Process detection via user variables requires the shell hook to be sourced in each pane's shell. SSH or mux remote sessions need the hook sourced on the remote side.
- **zsh only**: The shell hook uses `add-zsh-hook`. Bash/fish support can be added in the future.

## License

MIT
