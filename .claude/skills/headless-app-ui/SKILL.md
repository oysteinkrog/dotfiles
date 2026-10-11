---
name: headless-app-ui
description: >-
  Run MotionCatalyst (Swing Catalyst) or any other GUI app on this Linux desktop
  without touching Oystein's screen: a private display per instance, its own D-Bus
  session and Wine prefix, works while the screen is locked, several instances at
  once, screenshots from inside. Use before starting MC, its UI broker, a Wine GUI,
  a GUI test or any app window from an agent shell, and when the user says
  "headless", "virtual display", "nested kwin", "Xvfb", "run MC in the background",
  "screen is locked" or "several MC instances".
---

# Headless App UI Runbook

**DRAFT (2026-10-11).** The kpp session is building an `xvfb-run` harness for
MotionCatalyst in lane impl-licmock. It will prove screenshots and drop-down picks
while the screen is locked, with 2 instances at once. When it lands, its scripts
replace the hand recipes below. Until then, treat the recipes as tested only where
this file says so.

Agent shells here have `DISPLAY=:0`, and libwayland falls back to `wayland-0` when
`WAYLAND_DISPLAY` is unset. Both are Oystein's real screen. Any window you start
without changing them opens on his desktop, takes keyboard focus, and can catch
what he types. That happened on 2026-10-07. So every app window an agent starts
goes on a private display.

A private display also matters when the screen is locked. On 2026-10-11 the kpp
lanes ran MC on `:0` while the screen was locked. KWin hid MC's window, WPF stopped
rendering, and every capture route came back blank. Drop-down picks had no effect.
Do not use `loginctl ... LockedHint` to check for a lock: it said `no` while the
screen was locked.

## Hard rules

- Never open an app window on `:0` or `wayland-0`. Before you start anything with a
  window, set `DISPLAY` to your private display and set `WAYLAND_DISPLAY` to your
  nested socket, or to a name that does not exist (`no-such-wl`) when you use Xvfb.
  Unsetting it is not enough, because of the `wayland-0` fallback.
- One instance gets one private display, one D-Bus session (`dbus-run-session`),
  one `WINEPREFIX`, one MC hive (`MC_HIVE_DIR`) and one broker port. Never share a
  Wine prefix between instances: one prefix means one wineserver, and MC's named
  mutexes and Wine services are shared through it.
- Stop only what you started: your compositor or Xvfb, and `wineserver -k` with
  your own `WINEPREFIX` set. Never `pkill wine`, `pkill kwin_wayland` or
  `pkill Xvfb`. The real desktop runs `kwin_wayland --socket wayland-0`, and other
  lanes run their own.
- Do not take screenshots of the real desktop to show Oystein something. He can
  see it. Screenshots from your private display are fine.

## Pick a display

| | Nested KWin (`kwin_wayland --virtual`) | Xvfb |
|---|---|---|
| What you get | A full KWin with Xwayland, a window manager, KWin scripting, `kscreen-doctor`, spectacle | A bare X server, no window manager |
| Works while locked | Reported yes by a QA lane on 2026-10-04, not re-tested | Expected yes, since it never talks to the desktop session. Not yet shown with MC; the kpp harness will test it |
| GPU | Not checked | No. Vulkan and GL are llvmpipe (software), checked 2026-10-11 |
| Status on 2026-10-11 | **Broken** until `kwin-local` is rebuilt, see Known limits | Works, tested with 3 parallel Wine instances |

**Xvfb is the main path for Wine and other X11 apps.** Use nested KWin once the
`kwin-local` rebuild has landed, and only when the app needs a window manager
(focus, title bars, window placement, fractional scale) or KWin scripting. Do not
try to fix KWin yourself; another session owns that rebuild.

## Recipe: Xvfb

Let the server pick a free display number with `-displayfd`. Do not use
`xvfb-run -a`: two runs started at the same moment both took `:99` on 2026-10-11
and one failed.

```bash
run=/var/tmp/claude/<task>              # on disk, never /tmp
mkdir -p "$run"
Xvfb -displayfd 4 -screen 0 1920x1200x24 -nolisten tcp 4>"$run/display" 2>"$run/xvfb.log" &
echo $! > "$run/xvfb.pid"
until [ -s "$run/display" ]; do sleep 0.1; done
export DISPLAY=:$(cat "$run/display") WAYLAND_DISPLAY=no-such-wl XAUTHORITY=/dev/null
dbus-run-session -- <your launcher>      # for example a script that runs run-mc.sh
```

## Recipe: nested KWin

```bash
dbus-run-session -- kwin_wayland --virtual --xwayland --no-lockscreen \
    --no-global-shortcuts --socket <tag>-wl --width 1920 --height 1200 \
    --exit-with-session <inner.sh> 2>"$run/kwin.log"
```

KWin exits when `inner.sh` ends. Inside it, `WAYLAND_DISPLAY`, `DISPLAY` (the
nested Xwayland, for example `:2`) and `DBUS_SESSION_BUS_ADDRESS` already point at
the nested session. Give each instance its own `--socket` name. For a long-lived
session, make `inner.sh` write those three variables to a file and then
`exec sleep infinity`, as `/var/tmp/claude/qa-capture-ui-rt/kwin-start.sh` does.

Inside the session:

- Fractional scale: `kscreen-doctor output.Virtual-0.scale.1.1`. The `--scale`
  flag on the virtual backend only enlarges the framebuffer.
- Two outputs: `--output-count 2`.
- KWin scripts and window helpers: `/var/tmp/claude/ft-text-gamma-scratch/nested/lib.sh`
  (`nkwin`, `nlaunch`, `ncapture`). Set
  `QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES=kwin_scripting.debug=true` so
  script `print()` lands in the KWin log.

## MotionCatalyst under Wine

The scripts live in the monorepo at `tools/wine/` (read `tools/wine/README.md`).
Use the kpp branch's copy until its changes reach master.
`run-mc.sh` starts MC, `run-broker.sh [PORT]` starts the UI broker, `mcpc.py`
talks to the broker, `mcshot.sh` screenshots MC's window. All of them source
`wine-env.sh`, which fills in `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0` and the
shared prefix `~/.local/share/wineprefixes/motioncatalyst` only when those are
unset. So export your own values first, every time:

```bash
export DISPLAY=:N WAYLAND_DISPLAY=<nested socket or no-such-wl>
export WINEPREFIX=~/.local/share/wineprefixes/motioncatalyst-ui-<tag>
export MC_HIVE_DIR=~/.local/share/motioncatalyst-hives/<tag>
# first use only: reflink copy of the shared prefix, the way run-tests.sh does it
[ -d "$WINEPREFIX" ] || cp -a --reflink=auto ~/.local/share/wineprefixes/motioncatalyst "$WINEPREFIX"
tools/wine/run-broker.sh <free port> &      # not 8767 if another lane uses it
MC_UI_URL=http://127.0.0.1:<port>/ python3 tools/wine/mcpc.py list
```

Always clone the shared prefix as above. Never make a new one with `wineboot`: the
shared prefix carries settings from `tools/wine/setup-prefix.sh` (for example the
`windows.storage.applicationdata` DLL override that SQLite tests need), and a fresh
prefix lacks them.

`mcpc.py` keeps its MCP session in `$XDG_RUNTIME_DIR/mc-ui-wine`, so give each
instance its own `XDG_RUNTIME_DIR` for the client (the qa lanes used
`/var/tmp/claude/<lane>-rt`).

Use a fresh hive: `tools/qa/hive/setup-hive.sh <dir> --profile minimal`. Do not
use a worktree's `.dev-hive` that was copied from another checkout. Its
`AppRegistry.json` can point `DataPath` at `C:\WORK\desktop\master\.dev-hive`,
so under Wine every such worktree reads and writes the same folder inside the prefix.
MC's single-instance lock is per hive, so separate hives let instances coexist.

**Licence.** A fresh hive stops at the licence dialog. A Debug MC can get its
licence from the Linux licence mock instead. See "A licence from the mock" in
`tools/wine/README.md`: `tools/wine/mock-license.sh --hive <dir> --profile <name>`
starts `tools/qa/hive/license_mock_server.py` on 127.0.0.1:8797 and installs a test
key. Then start MC with `--license-server http://127.0.0.1:8797` (through the broker:
`"extraArgsJson":"[\"--license-server\",\"http://127.0.0.1:8797\"]"` on
`mc_connect`). Profiles live in `tools/qa/hive/license-profiles/` (`profiler`,
`all-features`). Release and ReleaseInternal builds cannot use the mock. Give a second
mock its own `--port`, and stop yours with `mock-license.sh --down`. The worked
example, with its own broker port 8792 and its own `XDG_RUNTIME_DIR`, is
`/var/tmp/claude/impl-licmock-report.md`.

A hive seeded from the QA profile can turn `UseAxioForce` on and open the real
force plate (seen 2026-10-04). Check the hive before you start MC when real
hardware is plugged in.

## Several instances

Repeat the recipe with a new tag. Each instance needs its own display (Xvfb picks
one; KWin needs a distinct `--socket`), `WINEPREFIX`, `MC_HIVE_DIR`, broker port
and client `XDG_RUNTIME_DIR`. Tested 2026-10-11: three Xvfb displays (`:1` to `:3`)
each running Wine `notepad` in its own prefix, all started at the same moment,
each captured on its own.

## Screenshots

- Xvfb or nested Xwayland, whole display:
  `ffmpeg -loglevel error -y -f x11grab -video_size 1920x1200 -i "$DISPLAY" -frames:v 1 out.png`
- One window under nested KWin: `ffmpeg -f x11grab -window_id <id> -i "$DISPLAY" ...`
  with the id from `xprop -root _NET_CLIENT_LIST`, or `tools/wine/mcshot.sh` with
  your `DISPLAY` exported. `mcshot.sh` matches the window title, which shows the
  worktree name rather than the hive, so it can grab another lane's MC. Match
  `_NET_WM_PID` against your own MC's PID instead. Under Xvfb there is no window manager, so
  `_NET_CLIENT_LIST` does not exist and `mcshot.sh` finds nothing. Grab the whole
  display instead.
- Wayland windows under nested KWin: `spectacle -b -n -f -o out.png` inside the
  session. With mixed output scales it composes at 2x and resamples, so do A/B
  captures on one output. KWin's ScreenShot2 D-Bus call refuses callers without a
  matching desktop file, so use spectacle.
- The broker's `wpf_capture_screenshot` returns a blank image under Wine. Do not
  rely on it.

## Builds and the Wine test runner

Build MC with `heavy-build`, as for any heavy build. `tools/wine/run-tests.sh` also
goes through `heavy-build`. It gives each worktree and `AgentOutputSuffix` its own
prefix already. It sources `wine-env.sh` too, so a test that opens a window lands on
`:0` unless you export a private `DISPLAY` and `WAYLAND_DISPLAY` first. Whether any
test project opens a window is not checked; export them anyway.

## Cleanup

```bash
WINEPREFIX=<your prefix> wineserver -k
kill "$(cat "$run/xvfb.pid")"            # Xvfb
# nested KWin: let inner.sh end, or kill the dbus-run-session PID you started
```

Then check nothing of yours is left: `pgrep -af "<your prefix or tag>"`.
`tools/wine/prune-test-prefixes.sh` removes unused test prefixes. Remove a
`motioncatalyst-ui-<tag>` prefix yourself when the task is done.

## Known limits

- **Nested KWin is broken right now (2026-10-11).** `qt6-base` went from 6.11.2 to
  6.12.0 at 18:22 that day. `kwin-local` 6.7.5 is a local build against Qt 6.11
  private API, so a new `kwin_wayland` exits with
  `symbol lookup error ... Qt_6_PRIVATE_API`. It needs `localbuild build kwin`.
  Test with `kwin_wayland --version` before you rely on it.
- Xvfb has no GPU. DXVK and the video views run on llvmpipe. Slow, and GPU-only
  bugs will not show. Whether MC's full UI renders correctly under Xvfb is not
  verified; only Wine `notepad` was tested.
- Under Xvfb there is no window manager, so focus and window decoration behave
  differently from a real desktop.
- MC sometimes exits with the Wine X error `BadWindow ... X_UnmapWindow` right after
  "Application lost focus". It happened on the real desktop and on a
  private display alike.
- Whether nested KWin gets the NVIDIA GPU is not checked.
- The kpp harness is not landed yet (see the DRAFT note at the top). The MC-specific
  parts of this file come from kpp's lane notes and are not re-run by the author.
