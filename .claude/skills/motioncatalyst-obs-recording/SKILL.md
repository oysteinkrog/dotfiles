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

## 1. Make X11 apps render 1:1 (the full HD part)

The office monitors (DP-1, DP-2, DP-3) are Dell 1920x1200 panels at **110% scale**, and KWin is set
to scale X11 apps itself (`~/.config/kwinrc`, `[Xwayland] Scale=1`, which System Settings calls
"Legacy applications (X11): Scaled by the system"). Wine is an X11 app. With these settings a
1920x1080 Wine window is stretched by 1.1 to about 2112x1188 physical pixels. It is blurry and
does not fit on a 1920-pixel-wide screen.

Pick one of these before recording:

- **Recommended:** set the monitor you record on to **100%** in System Settings > Display &
  Monitor. Everything on that screen is then 1:1. Set it back to 110% after recording.
- Or set System Settings > Display & Monitor > Legacy applications (X11) to **Apply scaling
  themselves**. X11 apps then draw at physical pixels and stay sharp. This changes every X11 app,
  not only MC.

With either setting, a 1920x1080 MC desktop plus its title bar fits on a 1920x1200 monitor.

I worked this out from the config and how KWin scales X11 apps, not from a test recording. Check it
with the size test in step 4.

## 2. Start MC in the recording desktop

```
mc-record              # 1920x1080, the default
mc-record 1600x900     # smaller, for a screen that cannot fit 1920x1080
```

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

- 2112x1188 or anything else that is not 1920x1080: step 1 was skipped. Fix the scaling and
  restart `mc-record`.
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
