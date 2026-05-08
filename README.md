# cc-glow.wezterm

A WezTerm plugin that shows a dot indicator (●) on tabs when AI coding agents (Claude Code, OpenCode, etc.) are running or need your attention.

Like tmux's activity monitoring, but designed for AI agent workflows -- you can work in other tabs and instantly see which agents are busy or finished.

## Features

- **Running indicator** -- blue ● while the agent is processing
- **Done indicator** -- green ● when the agent finishes
- **Waiting indicator** -- blue ● when the agent needs input
- **Per-pane tracking** -- works with split panes; each pane tracked independently
- **Workspace-level indicator** -- aggregated status per workspace, shown next to workspace names in tabline
- **Persistent state** -- records workspace/pane state in `~/.local/state/cc-glow/state.json`
- **Auto-dismiss** -- dot clears when you focus the pane
- **No text scanning** -- uses WezTerm user variables (OSC 1337), not terminal output parsing
- **Works with mux** -- compatible with `wezterm connect` / `unix_domains`

## How it works

```
Claude Code hooks / Shell hooks  -->  WezTerm Plugin (Lua)
  AI_RING=running (start/prompt)        user-var-changed -> pane_states
  AI_RING=done    (stop)                update-status    -> scan + dismiss
  AI_RING=waiting (notification)        state.json       -> reload after config changes
                                        tabline component -> ● on tab
                                        workspace component -> ● on workspace
```

### Status flow

| Event | Status | Tab indicator |
|---|---|---|
| Agent starts / user sends prompt | `running` | Blue ● |
| Agent finishes | `done` | Green ● |
| Agent needs permission/input | `waiting` | Blue ● |
| User focuses the pane | dismissed | Hidden |

## AI-assisted setup

You can ask Claude Code to set this up for you. Clone the repo first, then paste this prompt:

```
Please set up cc-glow.wezterm for me by following the AI Setup Instructions in the README.
The repo is cloned at: <path to cloned repo>
```

Claude will ask you a few questions and configure everything automatically.

---

<!-- AI SETUP INSTRUCTIONS — Claude reads this section when asked to set up cc-glow.wezterm -->
<details>
<summary>AI Setup Instructions (for Claude)</summary>

You are setting up cc-glow.wezterm for the user. Follow these steps exactly.

### Step 1 — Ask the user which features they want

Ask these questions one at a time and wait for answers:

1. **Tab indicator (required)**: "Do you use tabline.wez, or standalone WezTerm with no tab plugin?"
   - tabline.wez → use Option B setup
   - standalone → use Option A setup

2. **Signal source**: "Do you use Claude Code, another agent (OpenCode, Aider, etc.), or both?"
   - Claude Code only → set up Claude Code hooks
   - Other agents → set up shell hook
   - Both → set up both

3. **Background color** (only ask if Claude Code): "Do you want the pane background to turn green when Claude finishes? (yes / no)"

4. **Pane overlay** (only ask if Claude Code): "Do you want an in-pane colored dot while Claude is working, done, or waiting for input? (yes / no)"
   - If yes, ask: "Where should the dot appear? (top-left / top-right / bottom-left / bottom-right, default: bottom-left)"
   - If yes, ask: "How many lines from the edge? (default: 3)"

### Step 2 — Check existing state

Before making any changes:
- Read `~/.claude/settings.json` if it exists — never overwrite existing hooks, only append
- Check `~/.claude/hooks/` for existing scripts
- Check `~/.config/wezterm/wezterm.lua` or similar for existing WezTerm config

### Step 3 — Install based on answers

**WezTerm plugin (always required):**
- Option A (standalone): add `ai_ring.apply_to_config(config)` to wezterm.lua
- Option B (tabline.wez): create `~/.config/wezterm/plugins/ai-ring.lua` using the wrapper shown in the Installation section, then wire into tabline config

**Claude Code hooks (if chosen):**
```bash
mkdir -p ~/.claude/hooks
cp <repo>/shell/ai-ring-hook.sh ~/.claude/hooks/
cp <repo>/shell/cc-glow-state.py ~/.claude/hooks/
cp <repo>/shell/cc-glow-state.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/ai-ring-hook.sh ~/.claude/hooks/cc-glow-state.sh ~/.claude/hooks/cc-glow-state.py
```
Add to `~/.claude/settings.json` (merge with existing hooks, do not replace):
- Always add: `SessionStart`, `UserPromptSubmit` → `ai-ring-hook.sh running`
- Add: `Stop` → `ai-ring-hook.sh done`
- Add: `Notification` → `ai-ring-hook.sh waiting`

**Background color (if chosen):**
```bash
cp <repo>/shell/wezterm-bg.sh ~/.claude/hooks/
cp <repo>/shell/wezterm-bg.conf ~/.claude/hooks/
chmod +x ~/.claude/hooks/wezterm-bg.sh
```
Add to `~/.claude/settings.json`:
- `PreToolUse`, `UserPromptSubmit` → `wezterm-bg.sh reset`
- `Stop` → `wezterm-bg.sh done`
- `SessionEnd` → `wezterm-bg.sh reset`

**Pane overlay (if chosen):**
```bash
cp <repo>/shell/wezterm-overlay.sh ~/.claude/hooks/
cp <repo>/shell/wezterm-overlay.conf ~/.claude/hooks/
chmod +x ~/.claude/hooks/wezterm-overlay.sh
```
Edit `~/.claude/hooks/wezterm-overlay.conf` based on user's position preference.
Add to `~/.claude/settings.json`:
- `PreToolUse` → `wezterm-overlay.sh in_progress`
- `Stop` → `wezterm-overlay.sh done`
- `Notification` → `wezterm-overlay.sh waiting`

**Shell hook (if chosen):**
Add to `~/.zshrc`:
```zsh
AI_RING_AGENTS=(claude opencode aider gemini)  # adjust to user's agents
source <repo>/shell/ai-ring.zsh
```

### Step 4 — Verify

After making changes:
1. Confirm `~/.claude/settings.json` is valid JSON: `python3 -m json.tool ~/.claude/settings.json`
2. Confirm hook scripts are executable: `ls -la ~/.claude/hooks/`
3. Tell the user what was installed and how to test it (e.g. start Claude Code and check the tab indicator)

### Rules

- Never remove existing entries from `~/.claude/settings.json` hooks arrays — only append
- Never overwrite existing hook scripts without asking
- If the user's wezterm.lua already loads ai-ring, don't add it again
- Keep changes minimal — only install what the user asked for

</details>

---

## Installation

### Step 1: Set up the WezTerm plugin

**Option A: Standalone (no tabline plugin)**

```lua
local wezterm = require 'wezterm'
local ai_ring = wezterm.plugin.require 'https://github.com/AniP-gt/cc-glow.wezterm'

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
      "https://github.com/AniP-gt/cc-glow.wezterm"
    )
  end

  ai_ring_module.apply_to_config(config, {
    indicator = "●",
    color_done = "#A6E22E",
    color_waiting = "#66D9EF",
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
cp shell/cc-glow-state.py ~/.claude/hooks/
cp shell/cc-glow-state.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/ai-ring-hook.sh ~/.claude/hooks/cc-glow-state.sh ~/.claude/hooks/cc-glow-state.py
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
            "command": "~/.claude/hooks/ai-ring-hook.sh waiting"
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
| `Notification` | Claude needs permission or input | `waiting` (blue ●) |

When `cc-glow-state.sh` is installed next to `ai-ring-hook.sh`, the hook also writes persistent state to `~/.local/state/cc-glow/state.json`. The plugin still reacts through `AI_RING` immediately, and `CC_GLOW_STATE_VERSION` tells it to reload the state file after each update.

State entries are keyed by `workspace:pane_id` when the hook knows the workspace. If no workspace variable is available, the writer uses `unknown` and the WezTerm plugin falls back to matching the live pane id.

#### tmux users

If you run Claude Code inside tmux, enable OSC passthrough so the signals reach WezTerm:

```bash
# Add to ~/.tmux.conf
set -g allow-passthrough on
```

Then reload tmux config:

```bash
tmux source ~/.tmux.conf
```

#### Background color + pane overlay (optional)

Two scripts work together to give in-pane visual feedback:

- **`wezterm-bg.sh`** — changes the pane background color via OSC 11. Survives TUI redraws because it operates at the terminal emulator level, not the character grid.
- **`wezterm-overlay.sh`** — renders a small colored `●` via tput. `done` is green; `waiting` is blue.

```
[Stop]         → background turns green + green ● appears
[Notification] → blue ● appears
[SessionEnd]   → background resets to default
```

**Install:**

```bash
mkdir -p ~/.claude/hooks
cp shell/wezterm-bg.sh ~/.claude/hooks/
cp shell/wezterm-overlay.sh ~/.claude/hooks/
cp shell/wezterm-bg.conf ~/.claude/hooks/       # optional — customize colors
cp shell/wezterm-overlay.conf ~/.claude/hooks/  # optional — customize position
chmod +x ~/.claude/hooks/wezterm-bg.sh ~/.claude/hooks/wezterm-overlay.sh
```

**Add to `~/.claude/settings.json`:**

```json
{
  "hooks": {
    "PreToolUse":       [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/wezterm-bg.sh reset" }] }],
    "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/wezterm-bg.sh reset" }] }],
    "Stop":             [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/wezterm-bg.sh done" }, { "type": "command", "command": "~/.claude/hooks/wezterm-overlay.sh done" }] }],
    "Notification":     [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/wezterm-overlay.sh waiting" }] }],
    "SessionEnd":       [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/wezterm-bg.sh reset" }] }]
  }
}
```

**Customize background color** in `~/.claude/hooks/wezterm-bg.conf`:

```bash
COLOR_DONE="#0d2b0d"   # background when agent finishes (default: dark green)
```

Any hex color works. Examples:

| Color | Value |
|---|---|
| Dark green (default) | `#0d2b0d` |
| Dark blue | `#0d1f2b` |
| Dark amber | `#2b1a00` |

**Customize overlay position and colors** in `~/.claude/hooks/wezterm-overlay.conf`:

```bash
OVERLAY_ROW="bottom"    # top | bottom  (default: bottom)
OVERLAY_COL="left"      # right | left  (default: left)
OVERLAY_ROW_OFFSET=3    # lines from the edge (default: 3)
COLOR_DONE="#A6E22E"        # done dot color
COLOR_WAITING="#66D9EF"     # waiting dot color
COLOR_IN_PROGRESS="#66D9EF" # in-progress dot color
```

#### Shell hook (for OpenCode, Aider, etc.)

For agents that don't support hooks, use the zsh shell hook. Add to your `.zshrc`:

```zsh
source ~/.config/cc-glow.wezterm/shell/ai-ring.zsh
```

This uses `preexec`/`precmd` to detect when a watched command starts and stops.

By default, `claude` and `opencode` are watched. Customize before sourcing:

```zsh
AI_RING_AGENTS=(claude opencode aider gemini)
source ~/.config/cc-glow.wezterm/shell/ai-ring.zsh
```

#### Using both together

Claude Code hooks and the shell hook can coexist. The hooks provide more granular status (running vs waiting), while the shell hook covers agents without hook support.

## Configuration

```lua
ai_ring.apply_to_config(config, {
  indicator = '●',           -- dot character (default: '●')
  color_done = '#A6E22E',    -- color when agent finished (default: '#A6E22E')
  color_waiting = '#66D9EF', -- color when agent needs attention (default: '#66D9EF')
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
  has_waiting = false,  -- at least one pane is "waiting"
  has_done = true,      -- at least one pane is "done"
  has_running = false,  -- at least one pane is "running"
}
```

`waiting` takes priority over `done`, and `done` takes priority over `running` for the color.

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

[wezterm-agent-deck](https://github.com/Eric162/wezterm-agent-deck) is a similar plugin that detects agent status by scanning terminal output. cc-glow.wezterm takes a different approach:

| | cc-glow.wezterm | wezterm-agent-deck |
|---|---|---|
| Detection method | Explicit signals (hooks / OSC) | Terminal text scanning |
| False positives | None | Possible (pattern matching) |
| CPU overhead | Minimal | Scans all panes every interval |
| Setup | Requires hooks config | Zero config |
| Agent support | Any (with hooks/shell hook) | Built-in patterns for known agents |

Choose cc-glow.wezterm if you want reliable, low-overhead notifications. Choose wezterm-agent-deck if you prefer zero-config setup.

## License

MIT
