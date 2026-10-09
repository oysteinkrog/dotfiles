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

-- Panes that rang the bell, most recent last. The Claude hooks ring it when
-- Claude finishes or asks a question; Alt+M jumps to the latest one.
local bell_panes = {}
wezterm.on('bell', function(window, pane)
  local id = pane:pane_id()
  for i = #bell_panes, 1, -1 do
    if bell_panes[i] == id then table.remove(bell_panes, i) end
  end
  table.insert(bell_panes, id)
end)

-- Skips panes that are gone or in the tab you are already on, so pressing it
-- again goes to the one before
local function jump_to_last_bell(window, pane)
  local active_tab = pane:tab() and pane:tab():tab_id()
  while #bell_panes > 0 do
    local ok, p = pcall(mux.get_pane, table.remove(bell_panes))
    local tab = ok and p and p:tab()
    if tab and tab:tab_id() ~= active_tab then
      tab:activate()
      p:activate()
      return
    end
  end
end

-- Alt+K: fuzzy search this window's tabs by number, title, folder and Claude
-- state. Typing filters the list live, Up/Down picks, Enter switches.
local home_pattern = '^' .. wezterm.home_dir:gsub('%p', '%%%0')
local function tab_search(window, pane)
  local choices = {}
  for i, tab in ipairs(window:mux_window():tabs()) do
    local p = tab:active_pane()
    local title = tab:get_title()
    if title == '' then title = p:get_title() end
    local label = string.format('%2d  %s', i, title)
    local ok, cwd = pcall(function() return p:get_current_working_dir() end)
    if ok and cwd then
      local dir = tostring(cwd):gsub('^file://[^/]*', ''):gsub(home_pattern, '~')
      label = label .. '   ' .. dir
    end
    local state = p:get_user_vars().claude_state
    if state then label = label .. '   [' .. state .. ']' end
    table.insert(choices, { id = tostring(tab:tab_id()), label = label })
  end
  window:perform_action(wezterm.action.InputSelector({
    title = 'Switch to tab',
    choices = choices,
    fuzzy = true,
    fuzzy_description = 'Tab: ',
    action = wezterm.action_callback(function(_, _, id)
      local tab = id and mux.get_tab(tonumber(id))
      if tab then tab:activate() end
    end),
  }), pane)
end

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
    local login_path
    local p = io.popen("fish -lc 'string join : $PATH' 2>/dev/null")
    if p then
      login_path = p:read('*l')
      p:close()
      if login_path == '' then login_path = nil end
    end
    local plan = io.popen('bash ' .. wezterm.home_dir .. '/.claude/hooks/claude-persist.sh plan')
    if plan then
      for line in plan:lines() do
        local cwd, title, cmd = line:match('^([^\t]*)\t([^\t]*)\t(.*)$')
        if cwd then
          -- run claude, then keep a shell open in the tab when it exits
          local spec = {
            cwd = cwd,
            args = { 'bash', '-c', cmd .. '; exec fish -l' },
            -- the server runs under systemd with a minimal PATH; give the
            -- resumed session the PATH a login shell would have
            set_environment_variables = login_path and { PATH = login_path } or nil,
          }
          -- One failed spawn (e.g. out of file descriptors) must not abort the
          -- loop: an error here used to leave plan blocked on a full pipe.
          local ok, err = pcall(function()
            local tab
            if window then
              tab = window:spawn_tab(spec)
            else
              tab, _, window = mux.spawn_window(spec)
            end
            tab:set_title(title)
          end)
          if not ok then
            wezterm.log_error('claude-persist: could not reopen ' .. cwd .. ': ' .. tostring(err))
          end
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
  { key = 'm', mods = 'ALT', action = wezterm.action_callback(jump_to_last_bell) },
  -- back to the tab you were on before (after Alt+M, or any tab switch)
  { key = 'm', mods = 'ALT|SHIFT', action = wezterm.action.ActivateLastTab },
  { key = 'k', mods = 'ALT', action = wezterm.action_callback(tab_search) },
  { key = 'b', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateCommandPalette },
  -- new tabs start in the home directory, not the active tab's directory
  { key = 't', mods = 'CTRL|SHIFT', action = wezterm.action.SpawnCommandInNewTab({ cwd = wezterm.home_dir }) },
  { key = 'a', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(window, pane)
      local id = pane:tab():tab_id()
      local cur = tab_priorities[id] or 0
      tab_priorities[id] = (cur + 1) % 3
      window:invalidate()
    end),
  },
}

config.window_close_confirmation = 'NeverPrompt'

-- The bell only marks the tab orange (Claude hooks ring it); no sound
config.audible_bell = 'Disabled'

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
-- Tab text colors come from the active color scheme, so the tab bar follows
-- the theme: the scheme's cyan marks the active tab, its yellow a tab that
-- rang the bell, and other tabs use a blend of its foreground and background.
local function hex_rgb(color)
  local r, g, b = color:match('^#(%x%x)(%x%x)(%x%x)')
  if r then return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) end
end

-- t of `to` mixed into `from`; both are #RRGGBB
local function mix(from, to, t)
  local r1, g1, b1 = hex_rgb(from)
  local r2, g2, b2 = hex_rgb(to)
  if not (r1 and r2) then return from end
  local function ch(a, b) return math.floor(a + (b - a) * t + 0.5) end
  return string.format('#%02x%02x%02x', ch(r1, r2), ch(g1, g2), ch(b1, b2))
end

local function tab_colors(palette)
  local ansi = palette and palette.ansi or {}
  local fg = palette and palette.foreground or '#D8DEE9'
  local bg = palette and palette.background or '#2E3440'
  return {
    accent = ansi[7] or '#88C0D0',
    bell = ansi[4] or '#EBCB8B',
    title = mix(fg, bg, 0.2),
    muted = mix(fg, bg, 0.45),
    active_title = fg,
  }
end

wezterm.on('format-tab-title', function(tab, tabs, panes, config)
  local c = tab_colors(config.resolved_palette)
  local idx = string.format('%2d', tab.tab_index + 1)
  local title = tab.tab_title
  local pane_title = tab.active_pane.title
  -- While Claude Code runs, its own title ("✳ name", or a spinner while it
  -- works) wins over the fixed title restored tabs get, so /rename shows up.
  -- Claude's titles start with a non-ASCII symbol and a space.
  local claude_title = tab.active_pane.user_vars.claude_state
    and pane_title:match('^[\xC2-\xF4][\x80-\xBF]+ ')
  if claude_title or not title or #title == 0 then
    title = pane_title
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
  -- A colored bar on the left edge marks the tab to look at: the accent for
  -- the active tab, yellow (with a yellow title) for a tab that rang the bell
  local edge, edge_color, idx_color, title_color = ' ', nil, c.muted, c.title
  if tab.is_active then
    edge, edge_color, idx_color, title_color = '▌', c.accent, c.accent, c.active_title
  elseif tab.has_bell then
    edge, edge_color, idx_color, title_color = '▌', c.bell, c.bell, c.bell
  end
  local strong = tab.is_active or tab.has_bell
  return {
    { Foreground = { Color = edge_color or idx_color } },
    { Text = edge },
    { Attribute = { Intensity = strong and 'Bold' or 'Normal' } },
    { Foreground = { Color = idx_color } },
    { Text = idx .. ' ' },
    { Foreground = { Color = dot_color } },
    { Text = '●' },
    { Foreground = { Color = title_color } },
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
  config.font = wezterm.font('DejaVu Sans Mono') -- same as Windows Terminal (DejaVu Sans Mono for Powerline, 11)
  -- 11.5: between the old 11 and 12 (12 felt too big at scale 1.0)
  config.font_size = 11.5
  -- The terminal ignores fontconfig, so match KDE here: slight hinting, RGB subpixel.
  -- All three Dell U2412M panels are landscape with a horizontal RGB stripe.
  config.freetype_load_target = 'Light'
  config.freetype_render_target = 'HorizontalLcd'
  -- Blend glyph edges in linear light, so light text on a dark background is not
  -- drawn too thin. Only builds with the text_gamma option know the key, and
  -- config_builder raises on an unknown key, so older builds skip it.
  pcall(function() config.text_gamma = 1.45 end)
  -- Faint text (SGR 2). DejaVu Sans Mono has no Light weight, and its "Book"
  -- file stops the terminal from drawing a dimmed copy, so faint text came out
  -- at full brightness. Give it a dim grey instead. Faint italic is dimmed already.
  config.font_rules = {
    { intensity = 'Half', italic = false, font = wezterm.font('DejaVu Sans Mono', { foreground = '#7B8394' }) },
  }
  config.default_cursor_style = 'SteadyUnderline'
  config.window_background_opacity = 1.0 -- no transparency
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
      active_tab = { bg_color = '#4C566A', fg_color = '#ECEFF4', intensity = 'Bold' },
      inactive_tab = { bg_color = '#2E3440', fg_color = '#8A93A5' },
      inactive_tab_hover = { bg_color = '#3B4252', fg_color = '#D8DEE9', italic = true },
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
  -- same as a plain inactive tab: the yellow edge and title mark the bell instead
  bell_bg, bell_hover_bg = '#2E3440', '#3B4252'
end

-- Bell tab colors: fork-only, like the vertical tab options above
pcall(function()
  local colors = config.colors
  colors.tab_bar.inactive_tab_bell = {
    bg_color = bell_bg,
    fg_color = '#FFFFFF',
  }
  colors.tab_bar.inactive_tab_bell_hover = {
    bg_color = bell_hover_bg,
    fg_color = '#FFFFFF',
    italic = true,
  }
  config.colors = colors
end)

-- the tab bar + button: open the new tab in the home directory too
wezterm.on('new-tab-button-click', function(window, pane, button, default_action)
  if button == 'Left' then
    window:perform_action(wezterm.action.SpawnCommandInNewTab({ cwd = wezterm.home_dir }), pane)
    return false
  end
end)

-- Theme browser. Alt+Shift+K picks a built-in color scheme by fuzzy search;
-- Alt+PageDown / Alt+PageUp step to the next or previous one. The choice is
-- saved in ~/.local/state/frankenterm-theme so it survives restarts; an empty
-- or missing file means the Nord colors above. The tab bar takes its colors
-- from the scheme: FrankenTerm fills in tab bar colors a scheme leaves unset.
local theme_file = wezterm.home_dir .. '/.local/state/frankenterm-theme'
local scheme_lists = dofile(wezterm.home_dir .. '/.config/wezterm/color_schemes.lua')
local all_schemes = {}
for _, name in ipairs(scheme_lists.dark) do table.insert(all_schemes, name) end
for _, name in ipairs(scheme_lists.light) do table.insert(all_schemes, name) end

local function read_theme()
  local f = io.open(theme_file, 'r')
  if not f then return nil end
  local name = f:read('*l')
  f:close()
  if name and #name > 0 then return name end
end

-- Tab bar colors built from a scheme's background and foreground, in the same
-- pattern as the Nord ones: inactive and bell tabs on the terminal background,
-- the bar behind them a shade darker, the active tab a faint step toward the text color.
local function scheme_tab_bar(s)
  local bar = mix(s.bg, '#000000', 0.15)
  local muted = mix(s.fg, s.bg, 0.45)
  local hover = mix(s.bg, s.fg, 0.02)
  return {
    background = bar,
    -- A faint lift only: the colored edge mark and bold title already show the active tab
    active_tab = { bg_color = mix(s.bg, s.fg, 0.03), fg_color = s.fg, intensity = 'Bold' },
    inactive_tab = { bg_color = s.bg, fg_color = muted },
    inactive_tab_hover = { bg_color = hover, fg_color = s.fg, italic = true },
    new_tab = { bg_color = bar, fg_color = muted },
    new_tab_hover = { bg_color = hover, fg_color = s.fg },
    -- Same as a plain inactive tab: the yellow edge and title mark the bell instead
    inactive_tab_bell = { bg_color = s.bg, fg_color = s.fg },
    inactive_tab_bell_hover = { bg_color = hover, fg_color = s.fg, italic = true },
  }
end

local current_theme = read_theme()
if current_theme then
  config.color_scheme = current_theme
  -- Drop the Nord palette, which would paint over the scheme, and build the
  -- tab bar from the scheme's colors unless the scheme sets its own.
  config.colors = nil
  local s = scheme_lists.colors and scheme_lists.colors[current_theme]
  if s and not s.tab_bar then
    config.colors = { tab_bar = scheme_tab_bar(s) }
  end
end

local function set_theme(window, name)
  local f = io.open(theme_file, 'w')
  if not f then return end
  f:write(name or '')
  f:close()
  window:toast_notification('Theme', name or 'Nord (default)', nil, 2000)
  wezterm.reload_configuration()
end

local function step_theme(delta)
  return wezterm.action_callback(function(window)
    local idx = 0
    for i, name in ipairs(all_schemes) do
      if name == current_theme then idx = i break end
    end
    if idx == 0 then
      idx = delta > 0 and 1 or #all_schemes
    else
      idx = (idx + delta - 1) % #all_schemes + 1
    end
    set_theme(window, all_schemes[idx])
  end)
end

local function theme_picker(window, pane)
  local choices = { { id = '', label = 'Nord (default)' } }
  for _, name in ipairs(scheme_lists.dark) do
    table.insert(choices, { id = name, label = name })
  end
  for _, name in ipairs(scheme_lists.light) do
    table.insert(choices, { id = name, label = name .. '   (light)' })
  end
  window:perform_action(wezterm.action.InputSelector({
    title = 'Color scheme' .. (current_theme and (' (now: ' .. current_theme .. ')') or ''),
    choices = choices,
    fuzzy = true,
    fuzzy_description = 'Theme: ',
    action = wezterm.action_callback(function(win, _, id)
      if id then set_theme(win, id ~= '' and id or nil) end
    end),
  }), pane)
end

table.insert(config.keys, { key = 'k', mods = 'ALT|SHIFT', action = wezterm.action_callback(theme_picker) })
table.insert(config.keys, { key = 'PageDown', mods = 'ALT', action = step_theme(1) })
table.insert(config.keys, { key = 'PageUp', mods = 'ALT', action = step_theme(-1) })

return config
