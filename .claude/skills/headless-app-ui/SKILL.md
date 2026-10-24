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
driven through its own UI broker, with its own licence mock. Its docs are in
`tools/wine/README.md`, section "Headless MC on its own display".

It is on master: `start`, `env`, `shot`, `stop` and `reap`. Run it from your own
worktree. Only the `run` verb is still on branch `kpp` alone (worktree
`~/work/desktop/kpp`). Check what master has with
`git show if/master:tools/wine/headless-mc.sh | sed -n 2,12p`.

```bash
K=<your worktree>/tools
$K/qa/hive/setup-hive.sh /var/tmp/claude/<hive> --profile minimal
$K/wine/headless-mc.sh start one --hive /var/tmp/claude/<hive> --licence all-features \
    --build-dir <your src/motioncatalyst/BUILD/x64_Debug>
eval "$($K/wine/headless-mc.sh env one)"    # broker, prefix, display and D-Bus for this shell
$K/wine/mcpc.py call mc_navigate_to '{"screenName":"UserSelection"}'
$K/wine/headless-mc.sh shot one --refresh /var/tmp/claude/<task>/one.png
$K/wine/headless-mc.sh stop --rm one   # --rm also deletes the prefix and runtime folder
```

`start` brings up Xvfb, a D-Bus session bus and the broker. With `--hive` it also
starts MC through the broker and maximizes its window. `--licence <profile>` first
starts a licence mock for this instance on a free port, installs a test key into the
hive and passes `--license-server` to MC. That needs a Debug build with
`MotionCatalyst-cli.exe` in it (see "A licence from the mock" in the README).
Profiles are in `tools/qa/hive/license-profiles/` (for example `all-features` and `minimal`; there is no `profiler` profile).
Without `--hive`, start MC yourself with `mc_connect`, then maximize it (see Limits).
`stop` closes MC through the broker, then ends the mock, the broker, the prefix's
wineserver, the D-Bus bus and Xvfb, each by the PID that `start` recorded.

Each instance gets:

- a display that Xvfb picks itself (`-displayfd`), run with `-br`, 1920x1080 by
  default (`--size` to change it);
- its own D-Bus session bus, and an `XDG_RUNTIME_DIR` under
  `/var/tmp/headless-mc-$USER/<name>/`;
- a free broker port (`--port` to pick one) and a free licence mock port;
- `WAYLAND_DISPLAY` set to a name that does not exist;
- its own Wine prefix, `~/.local/share/wineprefixes/motioncatalyst-ui-<name>`. This
  is a reflink copy of the shared prefix, made on the first start and kept for the
  next. `--fresh-prefix` copies it again.

There is no KWin and no window manager. DXVK runs on Mesa's software Vulkan
(llvmpipe), so MC draws and screenshots show it, but slowly.

**Proven on 2026-10-11** by the kpp lane impl-licmock: MC renders under Xvfb on DXVK
with llvmpipe, two licensed instances ran at once (on `:1` and `:2`), and screenshots
worked while the screen was locked. Lane report: `/var/tmp/claude/impl-licmock-report.md`.

### Hive, licence and CLI calls

- Use a fresh hive from `setup-hive.sh --profile minimal`. Never copy a whole hive
  folder, and do not use a `.dev-hive` copied from another checkout.
  `AppRegistry.json` holds absolute paths to the hive it came from, so MC reads and
  writes the original instead. For the same reason, never rename a hive folder.
- Two takes with the same take id need separate hives.
- `start --hive` writes `DataSharing/Consented=false` into the hive's
  `ProgramData/settings/PrivacySettings.xml` before MC starts. Without it the
  data-sharing consent dialog blocks MC's UI thread, and neither `wpf_click_point`
  nor `WM_CLOSE` gets past it under Wine. If you start MC yourself with
  `mc_connect`, set it first. kpp saw no dialog after 90 s with the setting.
- For a CLI call or Wine command that goes through `heavy-build`, use `run`. It is on
  kpp only, so call it by its kpp path. The kpp copy starts kpp's broker build unless
  you export `MC_BROKER_DIR` first:

  ```bash
  ~/work/desktop/kpp/tools/wine/headless-mc.sh run one -- sh -c 'cd "$MC_BUILD_DIR" && wine MotionCatalyst-cli.exe import-takes --dir Z:/var/tmp/claude/takes --hiveDir Z:/var/tmp/claude/<hive>'
  ```

  `run` starts `heavy-build` with the real `XDG_RUNTIME_DIR=/run/user/$UID` and user
  bus, which heavy-build needs for its systemd scope. The command inside gets the
  instance's prefix, display, bus and private `XDG_RUNTIME_DIR`, plus `MC_BUILD_DIR`
  and `MC_BROKER_DIR`. The instance must be running. kpp checked that
  `import-takes` wrote into the instance prefix only.
- For a plain call without `heavy-build`, run `eval "$(headless-mc.sh env <name>)"` before any CLI or Wine call
  (`MotionCatalyst-cli.exe install-license`, `import-takes`, `wine reg add`). It
  exports `MC_UI_URL`, `XDG_RUNTIME_DIR`, `WINEPREFIX`, `DISPLAY`,
  `WAYLAND_DISPLAY=no-such-wl`, `XAUTHORITY=/dev/null` and the D-Bus address.
  Without it the call runs in the shared prefix. kpp checked this on 2026-10-11:
  after the `eval`, `wine reg add` and `install-license` wrote into
  `motioncatalyst-ui-<name>` (`/var/tmp/claude/impl-licmock/impl-licmock-envcheck.sh`).
- Release and ReleaseInternal builds cannot use the licence mock.
- Each MC opens the hardware its hive enables, and a USB camera or serial port
  serves one process. In a second hive, turn off what the first one owns in
  `GeneralSettings.xml` (`UseAxioForce`, `UseBertecSDK`, the camera flags), while
  that MC is closed.

### Limits

- MC does not repaint the area a closed dialog covered, even with `-br`, so the
  dialog stays in the picture. Toggling `WindowState` from `Normal` to `Maximized`
  repaints it. `shot --refresh` does this before the capture.
- MC restores the window position saved in the hive, which can be off the Xvfb
  screen. `start --hive` maximizes it. After your own `mc_connect`, use
  `wpf_set_property` on the main window, `WindowState`, `Maximized`.
- `wpf_click` and `wpf_select_item` cannot pick an item from MC's Xceed lists, such
  as the databox drop-down. Open it with `wpf_set_property IsChecked True` on
  `PART_DropDownButton`, then click the row with `wpf_click_point` at the position
  the screenshot shows. Click the scroll bar track to page the list.
- `mcpc.py` keeps its MCP session id in `$XDG_RUNTIME_DIR/mc-ui-wine/mcp-session`. A
  restarted broker answers HTTP 404 until that file is deleted. `start` clears it;
  after any other broker restart, run `mcpc.py reset`.
- Screenshots show names from the committed test takes. Keep them out of anything
  published.
- Video decoding and real cameras are not tested headless.

### Disk and cleanup

Each prefix is a reflink copy, so it starts near 0 B but grows as MC writes to it.
Reuse one instance name per lane rather than inventing new ones. When the lane ends,
run `headless-mc.sh stop --rm <name>`. It deletes the instance's prefix and runtime
folder, but only when each is at the script's own path, is a real directory, and
holds the `.headless-mc` marker that `start` writes. Do not delete them by hand.

## Other apps: plain Xvfb

For a Wine or X11 app that has no harness, do by hand what `headless-mc.sh` does.
In the monorepo, source `tools/wine/xvfb.sh` and call its start function, which picks a
free display at `:10` or above (PR #14207, DESKTOP-15945). Elsewhere, pick the number
yourself from `:10` up, as below.

Never let Xvfb choose with a bare `-displayfd`: it takes the lowest free number, and
when nothing held `:0` (right after a reboot, 2026-10-22) it took `:0`. Every agent
shell has `DISPLAY=:0`, so they all drew into that hidden display, and the real
Xwayland could not start. Do not use `xvfb-run -a` either: two runs started at the
same moment both took `:99` on 2026-10-11 and one failed.

```bash
run=/var/tmp/claude/<task>              # on disk, never /tmp
mkdir -p "$run"
n=10                                    # never below 10
while :; do
  while [ -e /tmp/.X$n-lock ] || [ -e /tmp/.X11-unix/X$n ]; do n=$((n+1)); done
  Xvfb :$n -displayfd 4 -screen 0 1920x1200x24 -nolisten tcp 4>"$run/display" 2>"$run/xvfb.log" &
  echo $! > "$run/xvfb.pid"
  until [ -s "$run/display" ] || ! kill -0 "$(cat "$run/xvfb.pid")" 2>/dev/null; do sleep 0.1; done
  [ -s "$run/display" ] && break
  n=$((n+1))                            # lost a race for :$n; try the next number
done
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
or `import -window root -display "$DISPLAY" out.png`. Against Xwayland `:0`, `import`
fails with the misleading "missing an image filename"; you must not capture `:0`
anyway. Xvfb has no window manager, so
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

## Builds, the Wine test runner and memory

Build MC with `heavy-build`, as for any heavy build. `tools/wine/run-tests.sh` also goes
through `heavy-build`. On master it starts its own Xvfb display for each run, so test
windows do not reach the real screen. For Wine prefixes, exit codes and the test loop,
load the `heavy-build` skill.

Each headless MC uses 5 to 9 GiB of memory. Start it through heavy-build as class
`app-run`, so it waits for admission:

```bash
heavy-build --class app-run --ready-file "$READY" --wait-timeout 600 -- headless-mc.sh start <name>
```

heavy-build writes `--ready-file` once the command is let in and started, and removes it
when heavy-build exits. `--wait-timeout` gives up with exit 77 if the run is not let in in
time. A command that names `headless-mc.sh` is `app-run` already. Run
`headless-mc.sh stop --rm <name>` as soon as you are done. `start` can also end with
heavy-build's exit 75 or 76.

## Known limits

- The broker's `wpf_capture_screenshot` returns a blank image under Wine. Use
  `headless-mc.sh shot` or `import`.
- MC sometimes exits with the Wine X error `BadWindow ... X_UnmapWindow` right after
  "Application lost focus", on the real desktop and on a private display alike.
  This is separate from the two-displays-in-one-prefix crash above.
- Xvfb has no GPU, so GPU-only bugs will not show headless.
