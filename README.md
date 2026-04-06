# ai-ring.wezterm

A WezTerm plugin that shows a dot indicator (●) on tabs when AI coding agents (Claude Code, OpenCode, etc.) are running or need your attention.

Like tmux's activity monitoring, but designed for AI agent workflows -- you can work in other tabs and instantly see which agents are busy or finished.

## Features

- **Running indicator** -- blue ● while the agent is processing
- **Done indicator** -- green ● when the agent finishes or needs input
- **Per-pane tracking** -- works with split panes; each pane tracked independently
- **Workspace-level indicator** -- aggregated status per workspace, shown next to workspace names in tabline
- **Auto-dismiss** -- dot clears when you focus the pane
- **No text scanning** -- uses WezTerm user variables (OSC 1337), not terminal output parsing
- **Works with mux** -- compatible with `wezterm connect` / `unix_domains`

## How it works

```
Claude Code hooks / Shell hooks  -->  WezTerm Plugin (Lua)
  AI_RING=running (start/prompt)        user-var-changed -> pane_states
  AI_RING=done    (stop/notification)   update-status    -> scan + dismiss
                                        tabline component -> ● on tab
                                        workspace component -> ● on workspace
```

### Status flow

| Event | Status | Tab indicator |
|---|---|---|
| Agent starts / user sends prompt | `running` | Blue ● |
| Agent finishes / needs input | `done` | Green ● |
| User focuses the pane | dismissed | Hidden |

## Installation

### Step 1: Set up the WezTerm plugin

**Option A: Standalone (no tabline plugin)**

```lua
local wezterm = require 'wezterm'
local ai_ring = wezterm.plugin.require 'https://github.com/AniP-gt/ai-ring.wezterm'

local config = wezterm.config_builder()
ai_ring.apply_to_config(config)
return config
```

> Note: This registers a `format-tab-title` handler. Only one handler can be active -- if you use another tab plugin, see Option B.

**Option B: With [tabline.wez](https://github.com/michaelbrusegard/tabline.wez) (recommended)**

Create a wrapper module (e.g. `~/.config/wezterm/plugins/ai-ring.lua`):

```lua
local wezterm = require("wezterm")

local M = {}
local ai_ring_module

function M.setup(config)
  if not ai_ring_module then
    ai_ring_module = wezterm.plugin.require(
      "https://github.com/AniP-gt/ai-ring.wezterm"
    )
  end

  ai_ring_module.apply_to_config(config, {
    indicator = "●",
    color_done = "#A6E22E",
    color_running = "#66D9EF",
  })
end

function M.agent_status_component(tab)
  if not ai_ring_module then return "" end

  local status = ai_ring_module.get_tab_status(tab.tab_id)
  if not status then return "" end

  return wezterm.format({
    { Foreground = { Color = status.color } },
    { Text = status.icon },
  })
end

function M.get_workspace_indicator(workspace_name)
  if not ai_ring_module then return "" end

  local status = ai_ring_module.get_workspace_status(workspace_name)
  if not status then return "" end

  return wezterm.format({
    { Foreground = { Color = status.color } },
    { Text = status.icon },
  })
end

return M
```

Then use `agent_status_component` and `get_workspace_indicator` in your tabline config:

```lua
local ai_ring = require("plugins.ai-ring")

-- Custom workspace component with AI status indicators
local function all_workspaces(window)
  local active = window:active_workspace()
  local names = wezterm.mux.get_workspace_names()
  local parts = {}
  for _, name in ipairs(names) do
    if name ~= "default" then
      local indicator = ai_ring.get_workspace_indicator(name)
      local label = name == active and ("[" .. name .. "]") or name
      if indicator ~= "" then
        label = indicator .. " " .. label
      end
      table.insert(parts, label)
    end
  end
  return table.concat(parts, " | ")
end

tabline.setup({
  sections = {
    tabline_b = { all_workspaces },
    tab_active = {
      ai_ring.agent_status_component,
      "index",
      { "process", padding = { left = 0, right = 1 } },
    },
    tab_inactive = {
      ai_ring.agent_status_component,
      "index",
      { "cwd", padding = { left = 0, right = 1 } },
    },
    -- ...
  },
})
```

### Step 2: Set up signal sources

You need at least one signal source to tell the plugin when agents start and stop. You can use Claude Code hooks, the shell hook, or both.

#### Claude Code hooks (recommended)

First, copy the hook script to `~/.claude/hooks/`:

```bash
mkdir -p ~/.claude/hooks
cp shell/ai-ring-hook.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/ai-ring-hook.sh
```

Then add the following to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/ai-ring-hook.sh running"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/ai-ring-hook.sh running"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/ai-ring-hook.sh done"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/ai-ring-hook.sh done"
          }
        ]
      }
    ]
  }
}
```

**What each hook does:**

| Hook | Triggers when | Signal |
|---|---|---|
| `SessionStart` | Claude Code session begins | `running` (blue ●) |
| `UserPromptSubmit` | You send a message | `running` (blue ●) |
| `Stop` | Claude finishes a response | `done` (green ●) |
| `Notification` | Claude needs permission or input | `done` (green ●) |

#### Shell hook (for OpenCode, Aider, etc.)

For agents that don't support hooks, use the zsh shell hook. Add to your `.zshrc`:

```zsh
source ~/.config/ai-ring.wezterm/shell/ai-ring.zsh
```

This uses `preexec`/`precmd` to detect when a watched command starts and stops.

By default, `claude` and `opencode` are watched. Customize before sourcing:

```zsh
AI_RING_AGENTS=(claude opencode aider gemini)
source ~/.config/ai-ring.wezterm/shell/ai-ring.zsh
```

#### Using both together

Claude Code hooks and the shell hook can coexist. The hooks provide more granular status (running vs waiting), while the shell hook covers agents without hook support.

## Configuration

```lua
ai_ring.apply_to_config(config, {
  indicator = '●',           -- dot character (default: '●')
  color_done = '#A6E22E',    -- color when agent finished (default: '#A6E22E')
  color_running = '#66D9EF', -- color while agent is running (default: '#66D9EF')
  position = 'left',         -- 'left' or 'right' of tab title (default: 'left')
})
```

## API

### `apply_to_config(config, opts)`

Initializes the plugin with the given options. Call this in your `wezterm.lua`.

### `get_tab_status(tab_id)`

Returns the status for a tab, for use in custom tab components (e.g. tabline.wez).

Returns `nil` if no active indicators, or a table:

```lua
{
  icon = '●',           -- the indicator character
  color = '#A6E22E',    -- the color to use
  has_done = true,      -- at least one pane is "done"
  has_running = false,  -- at least one pane is "running"
}
```

`done` takes priority over `running` for the color.

### `get_workspace_status(workspace_name)`

Returns the aggregated status for all panes in a workspace. Same return format as `get_tab_status`.

Scans all mux windows across all workspaces, so you can see the status of agents in workspaces you're not currently viewing.

## How dismissal works

1. An agent finishes -- green ● appears on the tab
2. You switch to that tab and the pane gets focus
3. The ● disappears for that pane
4. If the tab has multiple split panes with agents, each pane must be focused individually to dismiss its indicator

## Limitations

- **zsh only** for the shell hook. Bash/fish support can be added.
- **Local panes only** for user variables. SSH or mux remote sessions need the hook on the remote side.
- **`format-tab-title` conflict** (standalone mode only). If another plugin uses `format-tab-title`, use the tabline.wez integration instead.

## Comparison with wezterm-agent-deck

[wezterm-agent-deck](https://github.com/Eric162/wezterm-agent-deck) is a similar plugin that detects agent status by scanning terminal output. ai-ring.wezterm takes a different approach:

| | ai-ring.wezterm | wezterm-agent-deck |
|---|---|---|
| Detection method | Explicit signals (hooks / OSC) | Terminal text scanning |
| False positives | None | Possible (pattern matching) |
| CPU overhead | Minimal | Scans all panes every interval |
| Setup | Requires hooks config | Zero config |
| Agent support | Any (with hooks/shell hook) | Built-in patterns for known agents |

Choose ai-ring.wezterm if you want reliable, low-overhead notifications. Choose wezterm-agent-deck if you prefer zero-config setup.

## License

MIT
