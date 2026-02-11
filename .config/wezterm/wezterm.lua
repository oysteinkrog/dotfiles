local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = wezterm.config_builder()

-- Tab priority: 0=normal, 1=important, 2=urgent
local tab_priorities = {}
local priority_colors = { '#555555', '#F39C12', '#E74C3C' }

-- Claude state dot colors (set via user var from claude-sound hooks)
local claude_state_colors = {
  working  = '#3498DB', -- blue: Claude is working
  complete = '#2ECC71', -- green: task finished
  input    = '#F39C12', -- amber: needs your input
  error    = '#E74C3C', -- red: something failed
}

-- Close all tabs except the active one
wezterm.on("close_other_tabs", function(window, pane)
  local current_tab = pane:tab()
  local mux_win = window:mux_window()

  for _, tab in ipairs(mux_win:tabs()) do
    if tab:tab_id() ~= current_tab:tab_id() then
      for _, p in ipairs(tab:panes()) do
        p:kill()
      end
    end
  end
end)

-- Quake-style: top of screen, full width, 40% height, no title bar
config.window_decorations = 'RESIZE'

local function reposition_window(win)
  local screen = wezterm.gui.screens().main
  local width = screen.width * 0.9
  local height = screen.height * 0.8
  win:set_position(screen.x + 70, screen.y)
  win:set_inner_size(width, height)
end

wezterm.on('gui-startup', function(cmd)
  local screen = wezterm.gui.screens().main
  local tab, pane, window = mux.spawn_window(cmd or {
    position = {
      x = screen.x + 70,
      y = screen.y,
      origin = 'MainScreen',
    },
  })
  window:gui_window():set_inner_size(screen.width * 0.9, screen.height * 0.8)
end)

-- Default program: Ubuntu WSL
config.default_prog = { 'wsl.exe', '-d', 'Ubuntu' }

-- Font (matching Windows Terminal)
config.font = wezterm.font('DejaVu Sans Mono for Powerline')
config.font_size = 11

-- Cursor (matching Windows Terminal: filledBox, white)
config.default_cursor_style = 'SteadyBlock'

-- Keybindings matching Windows Terminal
config.keys = {
  { key = 'f', mods = 'CTRL|SHIFT', action = wezterm.action.Search({ CaseInSensitiveString = '' }) },
  { key = 'd', mods = 'ALT|SHIFT', action = wezterm.action.SplitHorizontal({ domain = 'CurrentPaneDomain' }) },
  { key = 'v', mods = 'CTRL', action = wezterm.action.PasteFrom('Clipboard') },
  { key = 'r', mods = 'CTRL|SHIFT', action = wezterm.action.PromptInputLine {
      description = 'Enter new tab name',
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          window:active_tab():set_title(line)
        end
      end),
    },
  },
  { key = 'DownArrow', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(1) },
  { key = 'UpArrow', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(-1) },
  { key = 'e', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(1) },
  { key = 'u', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(-1) },
  { key = 'p', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(window, pane)
      reposition_window(window)
    end),
  },
  { key = 'o', mods = 'CTRL|SHIFT', action = wezterm.action.EmitEvent("close_other_tabs") },
  { key = 'a', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(window, pane)
      local id = pane:tab():tab_id()
      local cur = tab_priorities[id] or 0
      tab_priorities[id] = (cur + 1) % 3
      window:invalidate()
    end),
  },
}

config.window_close_confirmation = 'NeverPrompt'

config.use_fancy_tab_bar = false
config.tab_max_width = 32

-- Vertical tab bar (Left or Right)
config.tab_bar_position = 'Left'
config.vertical_tab_width = 25
config.vertical_tab_cell_height = 1

-- Pad tab index to fixed width so titles align
-- Prefer explicitly set tab title (from `wezterm cli set-tab-title`)
-- Priority dot: Ctrl+Shift+I cycles normal(gray) → important(amber) → urgent(red)
wezterm.on('format-tab-title', function(tab)
  local idx = string.format('%2d', tab.tab_index + 1)
  local title = tab.tab_title
  if not title or #title == 0 then
    title = tab.active_pane.title
  end
  -- Claude state (from hooks) takes precedence over manual priority
  local claude_state = tab.active_pane.user_vars.claude_state
  local dot_color
  if claude_state and claude_state_colors[claude_state] then
    dot_color = claude_state_colors[claude_state]
  else
    local pri = tab_priorities[tab.tab_id] or 0
    dot_color = priority_colors[pri + 1]
  end
  local fg = tab.is_active and '#FFFFFF' or '#AAAAAA'
  return {
    { Foreground = { Color = fg } },
    { Text = ' ' .. idx .. ' ' },
    { Foreground = { Color = dot_color } },
    { Text = '●' },
    { Foreground = { Color = fg } },
    { Text = ' ' .. title .. ' ' },
  }
end)

-- Copy on select (send to clipboard instead of primary selection)
config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = wezterm.action.CompleteSelectionOrOpenLinkAtMouseCursor('Clipboard'),
  },
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = wezterm.action.PasteFrom('Clipboard'),
  },
}

-- flat-ui-v1 color scheme
config.colors = {
    foreground = '#ECF0F1',
    background = '#000000',
    cursor_bg = '#FFFFFF',
    cursor_fg = '#000000',
    selection_bg = '#FFFFFF',
    selection_fg = '#000000',
    -- Tab bar colors including bell notification color
    tab_bar = {
        background = '#111111', -- darker tab bar background
        active_tab = {
            bg_color = '#222222',
            fg_color = '#FFFFFF',
            intensity = 'Bold',
        },
        inactive_tab = {
            bg_color = '#1a1a1a',
            fg_color = '#AAAAAA',
        },
        inactive_tab_hover = {
            bg_color = '#444444',
            fg_color = '#AAAAAA',
            italic = true,
        },
        inactive_tab_bell = {
            bg_color = '#8B4513', -- dark orange/brown for bell
            fg_color = '#FFFFFF',
        },
        inactive_tab_bell_hover = {
            bg_color = '#A0522D', -- slightly lighter when hovering
            fg_color = '#FFFFFF',
            italic = true,
        },
    },
    ansi = {
        '#000000', -- black
        '#C0392B', -- red
        '#27AE60', -- green
        '#F39C12', -- yellow
        '#2980B9', -- blue
        '#8E44AD', -- purple
        '#16A085', -- cyan
        '#ECF0F1', -- white
    },
    brights = {
        '#7F8C8D', -- bright black
        '#E74C3C', -- bright red
        '#2ECC71', -- bright green
        '#F1C40F', -- bright yellow
        '#3498DB', -- bright blue
        '#9B59B6', -- bright purple
        '#1ABC9C', -- bright cyan
        '#ECF0F1', -- bright white
    },
}

return config
