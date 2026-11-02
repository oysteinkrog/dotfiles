---
name: motioncatalyst-obs-recording
description: >-
  Record Swing Catalyst (MotionCatalyst under Wine) in OBS at a clean 1920x1080, including its
  dialogs, menus and popups, without cropping. Uses the mc-record launcher (Wine virtual desktop)
  and an OBS Window Capture. Use when setting up OBS for a Swing Catalyst screen recording, a demo,
  a walkthrough or a CTO's Corner video, when subwindows are missing from a capture, or when a
  recording of MC is blurry or the wrong size.
---

# Recording Swing Catalyst in OBS at full HD

Run MC with `mc-record`. It starts the installed Swing Catalyst inside a Wine virtual desktop: one
host window of a fixed size, with MC and every subwindow (dialogs, menus, popups, tooltips) drawn
inside it. OBS captures that one window. Nothing needs cropping, and the layout is the same every
time.

Why not the other ways:

| Method | Problem |
|---|---|
| OBS Window Capture of MC itself | Misses dialogs, menus and popups. Each is its own top-level window. |
| Screen Capture plus crop | Works, but the crop must match the window exactly and breaks when the window moves. |
| obs-vkcapture (Game Capture) | Installed and works for the main window (DXVK turns MC's D3D9Ex and D3D11 into Vulkan). It captures one swapchain at a time, so subwindows are expected to be missing. |

## 1. Window size and scaling

Measured on the office desktop on 2026-11-02: the monitors (DP-1, DP-2, DP-3) are Dell 1920x1200
panels at 110% scale, and XWayland still reports each monitor as 1920x1200 (`xrandr
--listmonitors`). So X11 apps such as Wine draw at physical pixels, and a 1920x1080 MC desktop is
1920x1080 real pixels. No scaling change is needed.

Two traps, both handled by `mc-record`:

- **Garbage strip under MC.** Wine marks the desktop window fullscreen when it is as wide as the
  monitor. KWin then stretches the window to the whole 1920x1200 monitor. Wine draws only the top
  1920x1080, and the 120 pixels below show leftover image data. `mc-record` takes the window out of
  fullscreen and sizes it to 1920x1080 for the first 30 seconds after it appears.
- **KWin rule sizes are logical, not X pixels.** A KWin rule that forces the size to 1920x1080
  gives a 2112x1188 window at 110% scale. The rule `mcrecord-fullhd` in `~/.config/kwinrulesrc`
  therefore sets no size. It only removes the frame and blocks maximize and fullscreen. Size the
  window in X pixels with `wmctrl -e`, as `mc-record` does.

If the strip comes back mid-session, run:

```
wmctrl -r "MCRecord - Wine Desktop" -b remove,fullscreen,maximized_vert,maximized_horz
wmctrl -r "MCRecord - Wine Desktop" -e 0,-1,-1,1920,1080
```

## 2. Start MC in the recording desktop

```
mc-record              # 1920x1080, the default
mc-record 1600x900     # smaller size
mc-record 1920x1080 --hiveDir 'Z:\\home\\oystein\\.local\\share\\motioncatalyst-hives\\run262'
```

Arguments after the size go to MotionCatalyst.exe.

`mc-record` (`~/.dotfiles/bin/mc-record`) uses the same prefix (`~/.wine`), Wine build
(`~/.local/share/motioncatalyst-wine/current`) and `dxvk.conf` as the normal Swing Catalyst menu
entry. The only difference is `explorer /desktop=MCRecord,<size>`.

Once MC is up, maximize it inside the MCRecord window, so it fills the 1920x1080 area exactly.

Agents must not run `mc-record` on Oystein's screen (`:0`, `wayland-0`). It opens a window. Hand
him the command.

## 3. Set up OBS once

Settings > Video:

- Base (canvas) resolution: **1920x1080**
- Output (scaled) resolution: **1920x1080**. If base and output differ, OBS rescales and the text
  goes soft.
- FPS: 25 or 30. The CTO's Corner takes used 25.

Settings > Output > Recording:

- Format: Hybrid MP4 or MKV. Remux MKV to MP4 afterwards.
- Encoder: NVENC (the RTX 5070 Ti), rate control CQP around 18 to 20.

Scene:

1. Add **Window Capture (PipeWire)** and pick the window titled **MCRecord**. The KDE picker
   remembers the choice, so later sessions need one click.
2. Right-click the source > Transform > Fit to screen. At 1:1 this is a no-op.

## 4. Check the size before every real take

Right-click the source > Resize output (source size). OBS shows the source size. It must be
**1920x1080**:

- 1920x1200: the window went fullscreen again. Run the two `wmctrl` lines in step 1.
- 2112x1188: something sized the window in logical units, such as a KWin size rule. Remove that
  rule and run the `wmctrl` lines.
- 1920x1080 but MC does not fill it: maximize MC inside the MCRecord window.

Also record 5 seconds, open a dialog and a dropdown, and check that both appear in the file.

## 5. Before you record

- Check MC's own title bar. A dev build shows an internal build name (for example `run262@4cd354a`).
  Use a release build for anything customers or ambassadors see.
- Check that no real player names show in the take list or session lists. Use demo data.
- The teleprompter and other apps are not captured: the PipeWire window capture records only the
  MCRecord window. This is not true for a Screen Capture, which records everything on the monitor.

## Related

- `~/.dotfiles/bin/mc-record`: the launcher.
- `redacting-sensitive-parts-of-screencast-videos`: blur something after the fact.
- `video-obs-youtube-music`: remux and add music.
