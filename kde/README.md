# KDE Plasma settings

This folder holds the KDE settings both desktops share. Each file is named after an rc file
in `~/.config` and uses KDE's own format, but holds only the keys we chose. `bin/kde-config`
writes them one by one with `kwriteconfig6 --notify`, so a running session picks most of them
up at once.

The rc files are not symlinked. KDE replaces a file when it saves it, which turns a symlink
into a plain copy and stops the sync without telling you. The files also hold IDs that differ
per machine (panels, monitors, activities, virtual desktops).

## Shared first, host overrides second

- `~/.dotfiles/kde/<rcfile>` is the default for every machine.
- `~/projects/life/setup/machines/<hostname>/kde/<rcfile>` overrides single keys on one machine.
  Put a key there only when that machine should differ, with a comment saying why. The
  profiles live in the private Life repo because this repo is public.

Example: the shared `kwinrc` sets `[Xwayland] Scale=1`, and the home desktop's
`kde/kwinrc` sets `Scale=1.25` because its main monitor runs at 125 %.

## Colour theme

The colour theme comes from `os-theme` (`bin/os-theme`, themes in `.config/os-theme/themes.json`).
Its hooks set the Plasma colour scheme, the Plasma style, fooyin, the panels and the wallpaper
shader. `kde/_os-theme.txt` holds the theme name both machines use, and a host file of the same
name overrides it. `kde-config apply` switches to it, `diff` reports a different theme as drift,
and `kde-config capture os-theme` saves the current one. So the colour scheme and Plasma style
keys are not in `kdeglobals` or `plasmarc` here.

## Commands

```sh
kde-config diff                  # this machine against the repo
kde-config diff --ssh office     # another machine against the repo
kde-config capture kwinrc        # copy changed or new kwinrc keys into the shared file
kde-config capture --host kwinrc '[Xwayland]' Scale   # into this machine's override file
kde-config capture --ssh office katerc                # take the office machine's values
kde-config apply --dry-run       # list what apply would write
kde-config apply                 # write it (the desktop step of the bootstrap runs this)
```

`diff` prints two kinds of line:

- `drift`: a key in the repo whose live value is different. Run `apply` to put the repo value
  back, or `capture` to keep the new one.
- `untracked`: a key in a watched rc file that the repo does not have yet. Capture it, or add
  it to `_ignore.txt` if it is state rather than a choice.

## Workflow for a new setting

1. Change it in System Settings.
2. Run `kde-config diff` to see which keys KDE wrote.
3. Run `kde-config capture <rcfile>` (add `--host` if only this machine should have it).
4. Add a comment above the key in the repo file if the reason is not obvious, then commit.

## Other files here

- `_watch.txt`: the rc files `diff` scans for untracked keys. Files with repo keys are always
  scanned.
- `_ignore.txt`: `file:[group]:key` patterns that `diff` never reports. Only `*` is a wildcard.
- In `kglobalshortcutsrc`, `diff` only reports shortcuts that differ from their default.

## What stays in `setup/steps/60-desktop.sh`

Settings that need logic or another tool: the global theme (through
`plasma-apply-lookandfeel`), panel and system tray layout
(plasmashell scripting, because panel IDs differ per machine), wallpapers,
default apps in `mimeapps.list`, and the pin-to-monitor window layout from `HOST_WINDOW_LAYOUT`
in `host.sh`.

Taskbar pins are not synced. Each machine keeps the pins you set by hand.
