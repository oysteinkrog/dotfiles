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

-- Quake-style: top of screen, full width, 40% height, no title bar (Windows).
-- On Linux/Wayland wezterm draws its own (odd-looking) frame for any
-- non-default value; only the default asks KDE to draw the native one.
if wezterm.target_triple:find('windows') then
  config.window_decorations = 'RESIZE'
end

local function reposition_window(win)
  -- Frankenterm has no wezterm.gui.screens; leave the window where it is there
  if not (wezterm.gui and wezterm.gui.screens) then return end
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

local is_windows = wezterm.target_triple:find('windows') ~= nil

if is_windows then
  -- Default program: Ubuntu WSL
  config.default_prog = { 'wsl.exe', '-d', 'Ubuntu' }
else
  -- Linux: sessions live in wezterm-mux-server (systemd user unit wezterm-mux.service),
  -- so they survive closing the window. The GUI attaches to it on start.
  config.unix_domains = { { name = 'unix' } }
  config.default_gui_startup_args = { 'connect', 'unix' }

  -- When the mux server starts (at boot), reopen the Claude Code sessions that
  -- were still open at shutdown. claude-persist.sh plan prints one line per
  -- session: <cwd> TAB <tab title> TAB <shell command>.
  wezterm.on('mux-startup', function()
    local window
    local plan = io.popen('bash ' .. wezterm.home_dir .. '/.claude/hooks/claude-persist.sh plan')
    if plan then
      for line in plan:lines() do
        local cwd, title, cmd = line:match('^([^\t]*)\t([^\t]*)\t(.*)$')
        if cwd then
          -- run claude, then keep a shell open in the tab when it exits
          local spec = { cwd = cwd, args = { 'bash', '-c', cmd .. '; exec fish -l' } }
          local tab
          if window then
            tab = window:spawn_tab(spec)
          else
            tab, _, window = mux.spawn_window(spec)
          end
          tab:set_title(title)
        end
      end
      plan:close()
    end
    -- always leave at least one window with a plain shell
    if not window then mux.spawn_window({}) end
  end)

  -- 'connect' skips gui-startup, so size the window when it attaches instead
  wezterm.on('gui-attached', function(domain)
    for _, w in ipairs(mux.all_windows()) do
      -- the gui window may not exist yet when this fires; skip it then
      local ok, gw = pcall(function() return w:gui_window() end)
      if ok and gw then reposition_window(gw) end
    end
  end)
end

-- Font (matching Windows Terminal)
-- Linux has plain DejaVu Sans Mono; wezterm draws the powerline glyphs itself
config.font = wezterm.font(is_windows and 'DejaVu Sans Mono for Powerline' or 'DejaVu Sans Mono')
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

-- Vertical tab bar (Left or Right). Only the oysteinkrog/wezterm fork has these
-- options; stock wezterm rejects them, so skip them there instead of failing.
pcall(function()
  config.tab_bar_position = 'Left'
  config.vertical_tab_width = 25
  config.vertical_tab_cell_height = 1
end)

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

local bell_bg, bell_hover_bg = '#8B4513', '#A0522D' -- dark orange/brown

-- Linux: Nord, matching ~/.config/alacritty/alacritty.toml
if not is_windows then
  config.font = wezterm.font('Noto Sans Mono') -- what alacritty's "monospace" resolves to
  config.font_size = 12
  config.default_cursor_style = 'SteadyUnderline'
  config.window_background_opacity = 0.97
  config.bold_brightens_ansi_colors = 'BrightAndBold'

  config.colors = {
    foreground = '#D8DEE9',
    background = '#2E3440',
    cursor_bg = '#D8DEE9',
    cursor_fg = '#2E3440',
    cursor_border = '#D8DEE9',
    selection_bg = '#4C566A',
    selection_fg = '#ECEFF4',
    tab_bar = {
      background = '#272C36', -- a shade darker than the terminal
      active_tab = { bg_color = '#3B4252', fg_color = '#ECEFF4', intensity = 'Bold' },
      inactive_tab = { bg_color = '#2E3440', fg_color = '#8A93A5' },
      inactive_tab_hover = { bg_color = '#434C5E', fg_color = '#D8DEE9', italic = true },
      new_tab = { bg_color = '#272C36', fg_color = '#8A93A5' },
      new_tab_hover = { bg_color = '#434C5E', fg_color = '#D8DEE9' },
    },
    ansi = {
      '#3B4252', '#BF616A', '#A3BE8C', '#EBCB8B',
      '#81A1C1', '#B48EAD', '#88C0D0', '#E5E9F0',
    },
    brights = {
      '#4C566A', '#BF616A', '#A3BE8C', '#EBCB8B',
      '#81A1C1', '#B48EAD', '#8FBCBB', '#ECEFF4',
    },
  }
  bell_bg, bell_hover_bg = '#D08770', '#E0A08A' -- Nord orange
end

-- Bell tab colors: fork-only, like the vertical tab options above
pcall(function()
  local colors = config.colors
  colors.tab_bar.inactive_tab_bell = {
    bg_color = bell_bg,
    fg_color = is_windows and '#FFFFFF' or '#2E3440',
  }
  colors.tab_bar.inactive_tab_bell_hover = {
    bg_color = bell_hover_bg,
    fg_color = is_windows and '#FFFFFF' or '#2E3440',
    italic = true,
  }
  config.colors = colors
end)

return config
