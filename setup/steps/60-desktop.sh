# KDE Plasma settings. Writes single keys with kwriteconfig6 (through kde-config) instead
# of linking the rc files: KDE replaces those files when it saves, and they hold
# machine-generated IDs. Most changes apply at once, some at the next login.

step "desktop: KDE"
if ! have kwriteconfig6; then
  warn "kwriteconfig6 missing, not a KDE session; skipped"
  return 0
fi
# --notify tells a running session about the change. Without it, plasmashell keeps the
# values it read at login (notification popups stayed next to the panel).
kw() { kwriteconfig6 --notify "$@"; }

# Global theme and colour scheme from ~/.dotfiles/kde/kdeglobals. They go through the
# plasma-apply tools, which also write the derived colours that kde-config leaves alone.
want() { kreadconfig6 --file "$DOTFILES/kde/kdeglobals" --group "$1" --key "$2"; }
laf="$(want KDE LookAndFeelPackage)"
if [ -n "$laf" ] && [ "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" != "$laf" ] &&
  have plasma-apply-lookandfeel; then
  plasma-apply-lookandfeel -a "$laf" >/dev/null 2>&1 || warn "global theme $laf not installed"
fi
scheme="$(want General ColorScheme)"
if [ -n "$scheme" ] && [ "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)" != "$scheme" ] &&
  have plasma-apply-colorscheme; then
  plasma-apply-colorscheme "$scheme" >/dev/null 2>&1 || warn "colour scheme $scheme not installed"
fi

# Plain settings: the rc keys in ~/.dotfiles/kde, with host overrides from the machine
# profile's kde/ folder. See ~/.dotfiles/kde/README.md.
"$DOTFILES/bin/kde-config" apply >/dev/null

# System tray: pin a few icons, hide the ones that never have news (Cachy-Update and
# Remmina report Active all the time). The rest sit in the popup and show on the panel
# only while they have something to report. The panel and tray ids differ per machine,
# so this goes through plasmashell's scripting interface; it needs a running session.
if qdbus6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1; then
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
    panels().forEach(function (p) {
      p.floating = false;  // flush with the screen edge, no gap
      p.widgets("org.kde.plasma.systemtray").forEach(function (w) {
        w.currentConfigGroup = ["General"];
        w.writeConfig("shownItems", ["org.kde.plasma.volume", "org.kde.plasma.networkmanagement",
          "org.kde.plasma.notifications", "Slack_status_icon_1", "Claude_status_icon_1"]);
        w.writeConfig("hiddenItems", ["remmina-icon", "Cachy-Update",
          "org.kde.plasma.clipboard", "org.kde.plasma.brightness"]);
        w.writeConfig("showAllItems", false);
      });
    });' >/dev/null
else
  warn "plasmashell not running, system tray entries not set"
fi

# Window layout per host: which app goes on which monitor (the pin-to-monitor KWin script).
# Empty turns the script off.
if [ -n "$HOST_WINDOW_LAYOUT" ]; then
  kw --file kwinrc --group Script-pin-to-monitor --key Layout "$(printf '%s' "$HOST_WINDOW_LAYOUT" | tr -d '\n')"
  kw --file kwinrc --group Plugins --key pin-to-monitorEnabled true
else
  kw --file kwinrc --group Plugins --key pin-to-monitorEnabled false
fi

ok "theme $laf, colours $scheme, settings from ~/.dotfiles/kde"

step "desktop: default apps"
# Two Chromes, personal and work (work/life docs/computers/linux-setup.md, "Chrome"). Work is the default browser.
# The stock entry is hidden with a user copy, so menus show only the two launchers.
mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons"
if [ -f /usr/share/applications/google-chrome.desktop ]; then
  sed '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nNoDisplay=true/' /usr/share/applications/google-chrome.desktop \
    >"$HOME/.local/share/applications/google-chrome.desktop"
fi
# The icons carry the account avatars, so they live in the private Life repo.
# chrome-profile-icon then redraws each one on the icon theme's Chrome logo, with the
# local avatar if that profile is signed in, else with the badge from the repo copy.
for ic in chrome-personal chrome-work; do
  [ -f "$HOME/work/life/setup/chrome/$ic.png" ] && cp "$HOME/work/life/setup/chrome/$ic.png" "$HOME/.local/share/icons/$ic.png"
done
if have magick && [ -f "$HOME/.local/share/icons/chrome-work.png" ]; then
  "$HOME/.local/bin/chrome-profile-icon" "$HOME/.config/google-chrome-personal" "Profile 1" "$HOME/.local/share/icons/chrome-personal.png"
  "$HOME/.local/bin/chrome-profile-icon" "$HOME/.config/google-chrome" Default "$HOME/.local/share/icons/chrome-work.png"
  ok "Chrome icons drawn on the icon theme's Chrome logo"
fi
# Empty profile folders. Never copy the office ones: their logins are tied to its keyring.
mkdir -p "$HOME/.config/google-chrome-personal/Profile 1" "$HOME/.config/google-chrome/Default"
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/http chrome-work.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/https chrome-work.desktop
kw --file mimeapps.list --group "Default Applications" --key text/html chrome-work.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/claude com.anthropic.Claude.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/claude-cli claude-code-url-handler.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/slack slack.desktop
ok "browser Chrome (work profile); claude://, claude-cli://, slack:// handlers"

step "desktop: Star Nest shader wallpaper"
# Desktops and lock screen use the themed Star Nest shader written by
# ~/bin/shader-wallpaper-theme-sync (tools step). Needs plasma-wallpaper-shader-local.
shader_plugin=online.knowmad.shaderwallpaper
shader_url="file://$HOME/.local/share/shader-wallpaper/Star_Nest_Themed.frag"
if [ -d /usr/share/plasma/wallpapers/$shader_plugin ]; then
  lock() { kw --file kscreenlockerrc --group Greeter --group Wallpaper --group $shader_plugin --group General --key "$1" -- "$2"; }
  kw --file kscreenlockerrc --group Greeter --key WallpaperPlugin $shader_plugin
  lock selectedShaderPath "$shader_url"
  lock shaderSpeed 0.035
  lock targetFps 30
  lock resolutionScale 1.0
  if have qdbus6 && qdbus6 org.kde.plasmashell >/dev/null 2>&1; then
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
      desktops().forEach(function (d) {
        d.wallpaperPlugin = '$shader_plugin';
        d.currentConfigGroup = ['Wallpaper', '$shader_plugin', 'General'];
        d.writeConfig('selectedShaderCode', '');
        d.writeConfig('selectedShaderPath', '$shader_url');
        d.writeConfig('shaderSpeed', 0.035);
        d.writeConfig('targetFps', 30);
        d.writeConfig('resolutionScale', 1.0);
        d.writeConfig('pauseMode', 1);
        d.writeConfig('watchSourceFile', true);
        d.writeConfig('enableShaderTweaks', true);
        d.reloadConfig();
      });" >/dev/null && ok "desktops and lock screen: themed Star Nest"
  else
    ok "lock screen: themed Star Nest"; warn "plasmashell not running; desktop wallpapers skipped"
  fi
  # Login screen (Plasma Login Manager): needs a copy outside the home folder; uses sudo.
  if systemctl is-enabled -q plasmalogin.service 2>/dev/null; then
    "$HOME/bin/shader-wallpaper-greeter-setup" && ok "login screen: themed Star Nest"
  fi
else
  warn "$shader_plugin not installed; wallpaper skipped (tools step)"
fi
