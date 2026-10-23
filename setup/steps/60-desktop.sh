# KDE Plasma settings. Writes single keys with kwriteconfig6 instead of linking
# the rc files: KDE rewrites those files, and they hold machine-generated IDs.
# Most changes apply at the next login.

step "desktop: KDE"
if ! have kwriteconfig6; then
  warn "kwriteconfig6 missing, not a KDE session; skipped"
  return 0
fi
# --notify tells a running session about the change. Without it, plasmashell keeps the
# values it read at login (notification popups stayed next to the panel).
kw() { kwriteconfig6 --notify "$@"; }

# Look and feel: Breeze Dark, faster animations
current_laf="$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)"
if [ "$current_laf" != org.kde.breezedark.desktop ] && have plasma-apply-lookandfeel; then
  plasma-apply-lookandfeel -a org.kde.breezedark.desktop >/dev/null 2>&1 || true
fi
kw --file kdeglobals --group KDE --key AnimationDurationFactor 0.25

# Keyboard: US, AltGr dead keys (the system step sets the same for the login screen).
# A running session only picks this up after a re-login or a change in System Settings.
kw --file kxkbrc --group Layout --key Use true
kw --file kxkbrc --group Layout --key LayoutList us
kw --file kxkbrc --group Layout --key VariantList altgr-intl
kw --file kxkbrc --group Layout --key Model pc105

# Delete without asking, no Baloo file indexing, no USB automount popups
kw --file kiorc --group Confirmations --key ConfirmDelete false
kw --file baloofilerc --group "Basic Settings" --key Indexing-Enabled false
kw --file kded5rc --group Module-device_automounter --key autoload false
kw --file kded5rc --group Module-browserintegrationreminder --key autoload false

# Notification popups top right, gone after 3 s
kw --file plasmanotifyrc --group Notifications --key PopupPosition TopRight
kw --file plasmanotifyrc --group Notifications --key PopupTimeout 3000

# Monitor scale for X11 apps, per host
if [ -n "$HOST_KDE_SCALE" ]; then
  kw --file kwinrc --group Xwayland --key Scale "$HOST_KDE_SCALE"
fi

# Session restore: the autostart entry opens FrankenTerm (and starts its mux), so Plasma
# must not reopen it as well, or the login shows two FrankenTerm windows.
kw --file ksmserverrc --group General --key excludeApps com.dicklesworthstone.frankenterm.desktop

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

# Built-in RDP server: start with the session, log in with the system account
kw --file krdpserverrc --group General --key Autostart true
kw --file krdpserverrc --group General --key SystemUserEnabled true

ok "Breeze Dark, us altgr-intl, no indexing, KRDP on"

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
kw --file kdeglobals --group General --key BrowserApplication chrome-work.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/http chrome-work.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/https chrome-work.desktop
kw --file mimeapps.list --group "Default Applications" --key text/html chrome-work.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/claude com.anthropic.Claude.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/claude-cli claude-code-url-handler.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/slack slack.desktop
ok "browser Chrome (work profile); claude://, claude-cli://, slack:// handlers"

step "desktop: music shortcuts"
# Global keys for the launchers in .local/share/applications/foobar2000-*.desktop.
# They run ~/.local/bin/music-control, which drives fooyin if it is open and
# foobar2000 otherwise. New keys work after the next login.
kw --file kglobalshortcutsrc --group services --group foobar2000-playpause.desktop --key _launch "Alt+C"
kw --file kglobalshortcutsrc --group services --group foobar2000-next.desktop --key _launch $'Alt+A\tAlt+V'
kw --file kglobalshortcutsrc --group services --group foobar2000-random.desktop --key _launch "Alt+X"
kw --file kglobalshortcutsrc --group services --group foobar2000-back.desktop --key _launch "Alt+S"
ok "Alt+C play/pause, Alt+A or Alt+V next, Alt+X random, Alt+S back"

step "desktop: taskbar pins"
launchers="applications:foobar2000.desktop,applications:systemsettings.desktop,preferred://filemanager,applications:chrome-personal.desktop,applications:chrome-work.desktop,applications:org.remmina.Remmina.desktop,applications:com.anthropic.Claude.desktop"
if have qdbus6 && qdbus6 org.kde.plasmashell >/dev/null 2>&1; then
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    panels().forEach(function (p) {
      p.widgets('org.kde.plasma.icontasks').forEach(function (w) {
        w.currentConfigGroup = ['General'];
        w.writeConfig('launchers', '$launchers'.split(','));
      });
    });" >/dev/null && ok "taskbar: foobar2000, settings, files, Chrome personal and work, Remmina, Claude"
else
  warn "plasmashell not running; taskbar pins skipped"
fi

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
