---
name: motioncatalyst-obs-recording
description: >-
  Record Swing Catalyst (MotionCatalyst under Wine) in OBS at a clean 1920x1080, including its
  dialogs, menus and popups, without cropping. Uses the mc-record launcher (Wine virtual desktop)
  and an OBS Window Capture. Use when setting up OBS for a Swing Catalyst screen recording, a demo,
  a walkthrough or a CTO's Corner video, when subwindows are missing from a capture, or when a
  recording of MC is blurry, cropped or the wrong size, when a garbage strip shows below MC, when
  the teleprompter hides behind MC, or when OBS audio is choppy or the recording lags.
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
  therefore sets no size. It only removes the frame and blocks maximize. Size the
  window in X pixels with `wmctrl -e`, as `mc-record` does.

- **Teleprompter hidden behind MC.** While the Wine window is fullscreen and has focus, KWin
  puts it above every "keep on top" window, so the teleprompter disappears behind it. Clearing
  fullscreen fixes this too. `wmctrl -b remove,fullscreen` does not work here (Wine or KWin puts
  it back); a KWin script setting `fullScreen = false` does, and that is what `mc-record` runs.
  Do not add a KWin rule that forces fullscreen off: with that rule in place, the script cannot
  change the state of a window that was already open.

If the strip or the hidden teleprompter comes back mid-session, run:

```
echo 'for (const w of workspace.windowList()) if (w.caption === "MCRecord - Wine Desktop") w.fullScreen = false;' > /var/tmp/unfull.js
qdbus6 org.kde.KWin /Scripting/Script$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /var/tmp/unfull.js unfull) org.kde.kwin.Script.run
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript unfull
wmctrl -r "MCRecord - Wine Desktop" -e 0,-1,-1,1920,1080
```

## 2. Start MC in the recording desktop

```
mc-record              # 1920x1080, the default
mc-record 1600x900     # smaller size
mc-record 1920x1080 --hiveDir 'Z:\home\oystein\.local\share\motioncatalyst-hives\run262'
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
- Encoder: NVENC (the RTX 5070 Ti), rate control CQP around 18 to 20. In Simple mode, set
  Recording Quality to "High Quality, Medium File Size". "Same as stream" uses the stream
  encoder, which was x264 on the CPU.

Scene:

1. Add **Window Capture (PipeWire)** and pick the window titled **MCRecord**. The KDE picker
   remembers the choice, so later sessions need one click.
2. Right-click the source > Transform > **Reset Transform** (Ctrl+R). This clears any old crop
   and scale on the scene item. If you switch an existing source (for example a Screen Capture
   that was cropped by hand) to the MCRecord window, OBS keeps the old crop and cuts part of MC
   off. On 2026-11-02 the item still had crop 140, 212, 119, 54 and scale 1.021 from an earlier
   setup.

Settings > Audio:

- Desktop Audio: **Disabled**, unless the video needs app sound. A muted Desktop Audio source
  still runs, and on 2026-11-02 it pushed OBS's audio buffer up by 448 ms. Once the buffer hits
  its 960 ms limit ("Max audio buffering reached!" in the log), OBS drops audio and the mic stays
  choppy until OBS restarts.
- Mic/Aux: the default source, `effect_output.mic_streamcam` (StreamCam through RNNoise).

Webcam (V4L2 source, Logitech StreamCam): turn off **Use Buffering** in its properties to cut
the delay. In the scene json it is `"buffering": false`.

## 4. Check the size before every real take

Right-click the source > Resize output (source size). OBS shows the source size. It must be
**1920x1080**:

- 1920x1200: the window went fullscreen again. Run the fix-it commands in step 1.
- 2112x1188: something sized the window in logical units, such as a KWin size rule. Remove that
  rule and run the fix-it commands in step 1.
- 1920x1080 but MC does not fill it: maximize MC inside the MCRecord window.
- 1920x1080 but OBS shows only part of MC: the scene item has an old crop. Reset Transform
  (step 3).

Also record 20 seconds, open a dialog and a dropdown, and check that both appear in the file.
With View > Docks > Stats open, "Frames missed due to rendering lag" must stay near 0. The log
(`~/.config/obs-studio/logs/`) prints "Number of lagged frames due to rendering lag/stalls" at
each Recording Stop. On 2026-11-02 a take had 62.6%, so the file was about 11 real fps. If it
climbs: keep the OBS window visible and not minimized (NVIDIA on Wayland can stall rendering
for a hidden window), check the machine load, and as a last step start OBS with
`QT_QPA_PLATFORM=xcb obs`. Listen back to the test before a real take.

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
