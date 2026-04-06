local wezterm = require 'wezterm'

local M = {}

local pane_states = {}
local opts = nil
local last_focused_pane_id = nil

local default_opts = {
  indicator = '●',
  color_done = '#A6E22E',
  color_running = '#66D9EF',
  position = 'left',
}

local function merge_opts(defaults, overrides)
  local result = {}
  for k, v in pairs(defaults) do
    result[k] = v
  end
  if overrides then
    for k, v in pairs(overrides) do
      result[k] = v
    end
  end
  return result
end

-- Scan all panes for AI_RING user variable across all workspaces
local function scan_panes(window)
  if not opts then return end

  local pane_tab_map = {}

  -- Scan all mux windows (all workspaces)
  for _, mux_win in ipairs(wezterm.mux.all_windows()) do
    local workspace = mux_win:get_workspace()
    for _, tab in ipairs(mux_win:tabs()) do
      local tab_id = tab:tab_id()
      for _, pane_info in ipairs(tab:panes_with_info()) do
        local pane = pane_info.pane
        local pane_id = pane:pane_id()
        pane_tab_map[pane_id] = true

        local ok, vars = pcall(function() return pane:get_user_vars() end)
        if ok and vars then
          local signal = vars['AI_RING']
          if signal == 'running' or signal == 'done' then
            local existing = pane_states[pane_id]
            -- Don't overwrite dismissed state with same status from scan
            if existing and existing.dismissed and existing.status == signal then
              -- already dismissed, skip
            elseif not existing or existing.status ~= signal then
              pane_states[pane_id] = { tab_id = tab_id, workspace = workspace, status = signal, dismissed = false }
            end
          end
        end
      end
    end
  end

  -- GC: remove states for closed panes
  for pid, _ in pairs(pane_states) do
    if not pane_tab_map[pid] then
      pane_states[pid] = nil
    end
  end
end

wezterm.on('update-status', function(window, pane)
  if not opts then return end

  scan_panes(window)

  -- Dismissal: when user focuses a "done" pane, mark it dismissed
  local pane_id = pane:pane_id()
  if pane_id ~= last_focused_pane_id then
    last_focused_pane_id = pane_id
    local state = pane_states[pane_id]
    if state and state.status == 'done' and not state.dismissed then
      state.dismissed = true
    end
  end
end)

-- Immediate response via user-var-changed
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'AI_RING' then return end
  if not opts then return end

  local pane_id = pane:pane_id()
  local tab = pane:tab()
  if not tab then return end
  local tab_id = tab:tab_id()

  -- Resolve workspace name for this pane
  local workspace = ''
  local ok_ws, mux_win = pcall(function() return tab:window() end)
  if ok_ws and mux_win then
    workspace = mux_win:get_workspace() or ''
  end

  if value == 'running' then
    pane_states[pane_id] = { tab_id = tab_id, workspace = workspace, status = 'running', dismissed = false }
  elseif value == 'done' then
    pane_states[pane_id] = { tab_id = tab_id, workspace = workspace, status = 'done', dismissed = false }
  elseif value == '' then
    pane_states[pane_id] = nil
  end
end)

local function compute_tab_status(tab_id)
  if not opts then return nil end

  local has_done = false
  local has_running = false

  for _, state in pairs(pane_states) do
    if state.tab_id == tab_id and not state.dismissed then
      if state.status == 'done' then
        has_done = true
      elseif state.status == 'running' then
        has_running = true
      end
    end
  end

  if not has_done and not has_running then
    return nil
  end

  local color = has_done and opts.color_done or opts.color_running
  return { icon = opts.indicator, color = color, has_done = has_done, has_running = has_running }
end

function M.get_tab_status(tab_id)
  return compute_tab_status(tab_id)
end

local function compute_workspace_status(workspace_name)
  if not opts then return nil end

  local has_done = false
  local has_running = false

  for _, state in pairs(pane_states) do
    if state.workspace == workspace_name and not state.dismissed then
      if state.status == 'done' then
        has_done = true
      elseif state.status == 'running' then
        has_running = true
      end
    end
  end

  if not has_done and not has_running then
    return nil
  end

  local color = has_done and opts.color_done or opts.color_running
  return { icon = opts.indicator, color = color, has_done = has_done, has_running = has_running }
end

function M.get_workspace_status(workspace_name)
  return compute_workspace_status(workspace_name)
end

function M.apply_to_config(config, user_opts)
  opts = merge_opts(default_opts, user_opts)
end

return M
