---
name: headless-app-ui
description: >-
  Run MotionCatalyst (Swing Catalyst) or any other GUI app on this Linux desktop
  without touching Oystein's screen: a private display per instance, its own D-Bus
  session and Wine prefix, works while the screen is locked, several instances at
  once, screenshots from inside. Use before starting MC, its UI broker, a Wine GUI,
  a GUI test or any app window from an agent shell, and when the user says
  "headless", "virtual display", "nested kwin", "Xvfb", "headless-mc", "run MC in
  the background", "screen is locked" or "several MC instances".
---

# Headless App UI Runbook

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
- One instance gets one private display, one D-Bus session, one `WINEPREFIX`, one
  MC hive and one broker port. Never run two displays in one Wine prefix: one
  prefix has one wineserver, and Wine's desktop window lives on the display of
  whichever process started first. MC on the other display then dies with
  `BadWindow`.
- Stop only what you started: your own Xvfb or compositor, broker and wineserver,
  by the PID you recorded. Never `pkill wine`, `pkill kwin_wayland` or
  `pkill Xvfb`. The real desktop runs `kwin_wayland --socket wayland-0`, and other
  lanes run their own.
- Do not take screenshots of the real desktop to show Oystein something. He can
  see it. Screenshots from your private display are fine.

## MotionCatalyst: use `headless-mc.sh`

`tools/wine/headless-mc.sh` in the monorepo starts MC on its own Xvfb display,
driven through its own UI broker. Its docs are in `tools/wine/README.md`, section
"Headless MC on its own display".

**It is only on branch `kpp` for now** (commit `ae63e372e91f`, worktree
`~/work/desktop/kpp`), not on master. From another lane, run it by its path in the
kpp worktree and pass your own build and hive to `mc_connect`, or wait until it is
merged. Do not cherry-pick it into other branches. The kpp copy starts kpp's broker
build unless you export `MC_BROKER_DIR` first.

```bash
K=~/work/desktop/kpp/tools/wine
$K/headless-mc.sh start one                 # Xvfb, D-Bus, broker; prints display and port
eval "$($K/headless-mc.sh env one)"         # MC_UI_URL and XDG_RUNTIME_DIR for mcpc.py
$K/mcpc.py call mc_connect '{"buildDir":"<your BUILD/x64_Debug>","hiveDir":"/var/tmp/claude/<hive>","waitForIdle":true,"idleTimeoutMs":300000}'
# maximize once, see Limits
$K/headless-mc.sh shot one /var/tmp/claude/<task>/one.png
$K/mcpc.py call mc_disconnect '{"closeTarget":true}'
$K/headless-mc.sh stop one
```

Each instance gets:

- the next free X display from `:90` (Xvfb with `-br`, 1920x1080 by default,
  `--size` to change it);
- its own D-Bus session bus, and an `XDG_RUNTIME_DIR` under
  `/var/tmp/headless-mc-$USER/<name>/`;
- a free broker port (`--port` to pick one);
- its own Wine prefix, `~/.local/share/wineprefixes/motioncatalyst-headless-<name>`.
  This is a reflink copy of the shared prefix, made on the first start and kept for
  the next. `--fresh-prefix` copies it again.

There is no KWin and no window manager. DXVK runs on Mesa's software Vulkan
(llvmpipe), so MC draws and screenshots show it, but slowly.

`stop` ends the broker, the prefix's wineserver, the D-Bus bus and Xvfb, each by the
PID that `start` recorded. Close MC with `mc_disconnect` before `stop`.

**Proven on 2026-10-11** by the kpp lane impl-licmock: 2 instances at once on `:90`
and `:91`, and screenshots with ImageMagick `import` while the screen was locked.
Lane report: `/var/tmp/claude/impl-licmock-report.md`.

### Hive and licence

- Use a fresh hive: `tools/qa/hive/setup-hive.sh <dir> --profile minimal`. Never
  copy a whole hive folder, and do not use a `.dev-hive` copied from another
  checkout. `AppRegistry.json` holds absolute paths to the hive it came from, so MC
  reads and writes the original instead.
- A fresh hive stops at the licence dialog. A Debug MC can take its licence from
  the Linux licence mock. See "A licence from the mock" in `tools/wine/README.md`:
  `mock-license.sh --hive <dir> --profile <name>` serves on 127.0.0.1:8797, and
  you pass `"extraArgsJson":"[\"--license-server\",\"http://127.0.0.1:8797\"]"` to
  `mc_connect`. Profiles are in `tools/qa/hive/license-profiles/` (`profiler`,
  `all-features`). Release and ReleaseInternal cannot use the mock. Stop it with
  `mock-license.sh --down`.
- Each MC opens the hardware its hive enables, and a USB camera or serial port
  serves one process. In a second hive, turn off what the first one owns in
  `GeneralSettings.xml` (`UseAxioForce`, `UseBertecSDK`, the camera flags), while
  that MC is closed.

### Limits

- `wpf_click` and `wpf_select_item` cannot pick an item in the databox drop-down
  (an Xceed list). Open it with `wpf_set_property IsChecked True` on
  `PART_DropDownButton`, then click the row with `wpf_click_point` at the position
  the screenshot shows.
- With no window manager, MC can restore a window position that is off the Xvfb
  screen. Maximize once after `mc_connect`: `wpf_set_property` on the main window,
  `WindowState`, `Maximized`.
- `mcpc.py` keeps its MCP session in `$XDG_RUNTIME_DIR/mc-ui-wine/mcp-session`. A
  new broker does not know an old session and answers HTTP 404. `start` clears the
  file; if you start a broker any other way, run `mcpc.py reset`.
- Screenshots show names from the committed test takes. Keep them out of
  anything published.
- Video decoding and real cameras are not tested headless.

### Disk and cleanup

Each prefix is a reflink copy, so it starts near 0 B but grows as MC writes to it.
Reuse one instance name per lane rather than inventing new ones. When the lane ends:

```bash
$K/headless-mc.sh stop <name>
rm -r ~/.local/share/wineprefixes/motioncatalyst-headless-<name>   # the script has no option for this
```

Check first that `stop` printed `stopped` and that `pgrep -af headless-<name>`
shows nothing, so no wineserver is still using the prefix.

## Other apps: plain Xvfb

For a Wine or X11 app that has no harness, do by hand what `headless-mc.sh` does.
Let the server pick a free display with `-displayfd`. Do not use `xvfb-run -a`: two
runs started at the same moment both took `:99` on 2026-10-11 and one failed.

```bash
run=/var/tmp/claude/<task>              # on disk, never /tmp
mkdir -p "$run"
Xvfb -displayfd 4 -screen 0 1920x1200x24 -nolisten tcp 4>"$run/display" 2>"$run/xvfb.log" &
echo $! > "$run/xvfb.pid"
until [ -s "$run/display" ]; do sleep 0.1; done
export DISPLAY=:$(cat "$run/display") WAYLAND_DISPLAY=no-such-wl XAUTHORITY=/dev/null
dbus-run-session -- <your launcher>
# when done
kill "$(cat "$run/xvfb.pid")"
```

For Wine, give each instance its own `WINEPREFIX` and stop it with
`WINEPREFIX=<yours> wineserver -k`. For MC-style prefixes, clone the shared prefix
(`cp -a --reflink=auto`) rather than making a new one with `wineboot`: the shared
prefix carries settings from `tools/wine/setup-prefix.sh` that a fresh one lacks.
Tested 2026-10-11: three Xvfb displays at once, each running Wine `notepad` in its
own prefix, each captured on its own.

Screenshot the whole display with
`ffmpeg -loglevel error -y -f x11grab -video_size 1920x1200 -i "$DISPLAY" -frames:v 1 out.png`
or `import -window root out.png`. Xvfb has no window manager, so
`_NET_CLIENT_LIST` does not exist and window lookups by title find nothing.

## Second path: nested KWin (waiting for a rebuild)

Use a nested KWin when an app needs a window manager (focus, title bars, window
placement, fractional scale), a Wayland client, or KWin scripting.

**It does not start on 2026-10-11.** `qt6-base` went from 6.11.2 to 6.12.0 that day,
and `kwin-local` 6.7.5 is a local build against Qt 6.11 private API, so a new
`kwin_wayland` exits with `symbol lookup error ... Qt_6_PRIVATE_API`. Another session
is rebuilding it. Do not try to fix KWin yourself. Check with
`kwin_wayland --version` before you rely on it.

```bash
dbus-run-session -- kwin_wayland --virtual --xwayland --no-lockscreen \
    --no-global-shortcuts --socket <tag>-wl --width 1920 --height 1200 \
    --exit-with-session <inner.sh> 2>"$run/kwin.log"
```

KWin exits when `inner.sh` ends. Inside it, `WAYLAND_DISPLAY`, `DISPLAY` (the nested
Xwayland) and `DBUS_SESSION_BUS_ADDRESS` point at the nested session. Give each
instance its own `--socket` name. For a long-lived session, make `inner.sh` write
those three variables to a file and then `exec sleep infinity`, as
`/var/tmp/claude/qa-capture-ui-rt/kwin-start.sh` does.

Inside the session:

- Fractional scale: `kscreen-doctor output.Virtual-0.scale.1.1`. The `--scale` flag
  on the virtual backend only enlarges the framebuffer. Two outputs:
  `--output-count 2`.
- KWin scripts and window helpers: `/var/tmp/claude/ft-text-gamma-scratch/nested/lib.sh`
  (`nkwin`, `nlaunch`, `ncapture`). Set
  `QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES=kwin_scripting.debug=true` so script
  `print()` lands in the KWin log.
- Screenshots: `spectacle -b -n -f -o out.png` inside the session. With mixed output
  scales it composes at 2x and resamples, so do A/B captures on one output. KWin's
  ScreenShot2 D-Bus call refuses callers without a matching desktop file. For X11
  windows, `ffmpeg -f x11grab -window_id <id>` with the id from
  `xprop -root _NET_CLIENT_LIST`.
- A QA lane reported on 2026-10-04 that a nested KWin kept working while the screen
  was locked. Not re-tested. Whether it gets the NVIDIA GPU is not checked.

## Builds and the Wine test runner

Build MC with `heavy-build`, as for any heavy build. `tools/wine/run-tests.sh` also
goes through `heavy-build`, and it gives each worktree and `AgentOutputSuffix` its
own prefix already. It sources `wine-env.sh`, which fills in `DISPLAY=:0` and
`WAYLAND_DISPLAY=wayland-0` when they are unset, so a test that opens a window lands
on the real screen. Whether any test project opens a window is not checked. Export a
private `DISPLAY` and `WAYLAND_DISPLAY` first anyway.

## Known limits

- The broker's `wpf_capture_screenshot` returns a blank image under Wine. Use
  `headless-mc.sh shot` or `import`.
- MC sometimes exits with the Wine X error `BadWindow ... X_UnmapWindow` right after
  "Application lost focus", on the real desktop and on a private display alike.
  This is separate from the two-displays-in-one-prefix crash above.
- Xvfb has no GPU, so GPU-only bugs will not show headless.
