# KDE Plasma settings. Writes single keys with kwriteconfig6 instead of linking
# the rc files: KDE rewrites those files, and they hold machine-generated IDs.
# Most changes apply at the next login.

step "desktop: KDE"
if ! have kwriteconfig6; then
  warn "kwriteconfig6 missing, not a KDE session; skipped"
  return 0
fi
kw() { kwriteconfig6 "$@"; }

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

# Monitor scale for X11 apps, per host
if [ -n "$HOST_KDE_SCALE" ]; then
  kw --file kwinrc --group Xwayland --key Scale "$HOST_KDE_SCALE"
fi

# Built-in RDP server: start with the session, log in with the system account
kw --file krdpserverrc --group General --key Autostart true
kw --file krdpserverrc --group General --key SystemUserEnabled true

ok "Breeze Dark, us altgr-intl, no indexing, KRDP on"

step "desktop: default apps"
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/http google-chrome.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/https google-chrome.desktop
kw --file mimeapps.list --group "Default Applications" --key text/html google-chrome.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/claude com.anthropic.Claude.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/claude-cli claude-code-url-handler.desktop
kw --file mimeapps.list --group "Default Applications" --key x-scheme-handler/slack slack.desktop
ok "browser Chrome; claude://, claude-cli://, slack:// handlers"

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
launchers="applications:foobar2000.desktop,applications:systemsettings.desktop,preferred://filemanager,preferred://browser,applications:org.remmina.Remmina.desktop,applications:com.anthropic.Claude.desktop"
if have qdbus6 && qdbus6 org.kde.plasmashell >/dev/null 2>&1; then
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
    panels().forEach(function (p) {
      p.widgets('org.kde.plasma.icontasks').forEach(function (w) {
        w.currentConfigGroup = ['General'];
        w.writeConfig('launchers', '$launchers'.split(','));
      });
    });" >/dev/null && ok "taskbar: foobar2000, settings, files, browser, Remmina, Claude"
else
  warn "plasmashell not running; taskbar pins skipped"
fi
