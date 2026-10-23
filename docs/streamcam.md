# StreamCam Mic Setup and Recovery on Linux

How the dotfiles run the Logitech StreamCam (USB ID `046d:0893`, firmware 0.17) mic in
stereo on Linux, how they recover it when it breaks, what the camera's control
selectors do, and how to set it up on a new machine. Last updated 2026-10-23.

## Setup on a new machine

`setup/bootstrap.sh` does all of it. The pieces, in case you need to check one:

| Piece | Where | Installed by |
|---|---|---|
| `streamcam-mic-enable` (the script) | `.local/bin/` | `install.sh` link |
| `streamcam-mic-resume-watch` | `.local/bin/` | `install.sh` link |
| `streamcam-mic.service` (oneshot, runs the script) | `.config/systemd/user/` | `install.sh` link |
| `streamcam-mic-resume.service` (runs the script at login and after wake) | `.config/systemd/user/` | link, enabled by `setup/steps/70-services.sh` |
| udev rule: start `streamcam-mic.service` when the camera connects | `setup/system/99-streamcam-mic.rules` to `/etc/udev/rules.d/` | `setup/steps/20-system.sh` |
| sudoers rule: let the script rebind `snd-usb-audio` | `/etc/sudoers.d/92-streamcam-audio` | `setup/steps/20-system.sh` |

To run only these steps: `setup/bootstrap.sh system links services`. The udev rule
matches only `046d:0893`, so it does nothing on a machine without the camera.

The PipeWire mic filter (`effect_input.mic_streamcam`) is per machine and lives in the
machine profile, not here. The script works without it.

## The problem

Sometimes the camera's mic sends only zero samples: every sample is exactly 0, which
reads as -91 dB. The camera still shows up as a normal USB audio device. First seen on
2026-09-29. In that state:

- PipeWire, Slack and `arecord` straight from the ALSA device all record zeros, at
  16 kHz and 48 kHz, with the ALSA mixer at any setting.
- Unplugging the cable, `usbreset 046d:0893` and a warm reboot did not fix it.
- `snd-usb-audio` quirk flags (`set_iface_first`, `iface_delay`, `ctl_msg_delay_1m`,
  `always_set_rate`) did not fix it.
- Changing the audio mode block (selector 15, below) did not fix it.
- The kernel logs `current rate 16000 is different from the runtime rate 48000` on every
  open. Pinning the PipeWire source to 16 kHz changed nothing.
- Writing 1 to selector 17 fixed it at once.

We do not know for sure what puts the camera in this state. It has been seen after a
boot and after a wake from sleep. It survives a power cut, so the bad state is stored in
the camera. The best lead: while the mic was silent, selector 15 read
`000001001200000000000000000000000000`, with the DSP parameter bytes (4 to 17) almost all
zero. On 2026-10-23, writing zeroed DSP parameters broke a working mic (it then sent loud
white noise instead of sound), and writing the factory parameters back fixed it at once.
So bad DSP parameters in selector 15 are a likely cause. This is inferred, not proven: we
have not reproduced the all-zero state itself. Logitech Capture on Windows writes
selector 15, so it may be what set them.

## What the script does

`streamcam-mic-enable` runs when the camera connects, at login and after each wake:

1. It writes the factory audio block with stereo mode to selector 15:
   `00000100faff01000a00f7fff7fff0fff0ff`. This sets stereo and repairs any bad DSP
   parameters. It does not reboot the camera, so it runs every time.
2. It records 1.5 s from the camera's PipeWire source. If any sample is not zero, the mic
   works and the script goes to step 4.
3. If every sample is zero, it writes 1 to selector 17 (below). The camera restores its
   default settings and reboots, and reconnects about 2 s later. The reset puts the
   camera back in mono, so the script waits for the camera and repeats step 1.
4. It checks that PipeWire has the camera's mic source. If not, it rebinds
   `snd-usb-audio` on the camera's audio interfaces so WirePlumber probes the card
   again. This handles the case where WirePlumber probed the card while the camera was
   rebooting and was left with only the `off` and `pro-audio` profiles.

Options: `--mono` skips step 1 and leaves the camera's mode alone. `--force` sends the
reset even when the mic works. `--reprobe` only rebinds the sound card. `--no-relink`
skips step 4.

After a write that times out, the script skips automatic runs for 2 minutes (stamp file
`$XDG_RUNTIME_DIR/streamcam-mic-timeout`). Without this, the reboot caused a reconnect,
the reconnect ran the script again, and the camera reconnected 365 times in 40 minutes
on 2026-10-23. Earlier versions sent the reset on every connect, even with a working mic.

## Camera controls

The camera exposes Logitech's "peripheral" UVC extension unit, GUID
`ffe52d21-8030-4e2c-82d9-f587d00540bd`. On this camera it is unit 11. The script reads
the unit ID from the USB descriptors, so it does not depend on the number. It talks to
the unit with the `UVCIOC_CTRL_QUERY` ioctl on `/dev/videoN`, which needs no root.

Only two selectors answer on this unit:

| Selector | Size | What it does | Evidence |
|---|---|---|---|
| 15 | 18 bytes | Audio settings block. Bytes 0 and 1 are ByPass and bytes 2 and 3 are Stereo, both little-endian: 0 is mono (left and right identical), 1 is stereo. Bytes 4 to 17 are DSP parameters. | Logi Options+ reads and writes it as "audio mode" (below). Measured: byte 2 switches mono and stereo, and zeroed bytes 4 to 17 turn the mic into a noise source. |
| 17 | 1 byte, range 0 to 1 | Writing 1 restores the defaults and reboots the camera. Writing 0 does nothing. Always reads 0. | Tested 2026-10-23, below. |

Selector 15 right after a factory reset reads `00000000faff01000a00f7fff7fff0fff0ff`
(mono). The script writes the same block with byte 2 set to 1 (stereo). In both modes
every sample's low byte is `0x00` or `0xFF`, so the camera's DSP output has about 8 bits
of real resolution. That is how the firmware works, not a fault.

Selector 15 cannot be read back reliably. `GET_CUR`, `GET_DEF`, `GET_MIN` and `GET_MAX`
all return the same buffer, and after some writes that buffer does not match what the
camera does. So the script writes the block every time instead of comparing first.

Blocks with zeroed DSP parameters, such as `000001001200000000000000000000000000` or
`000001000000000000000000000000000000`, make the mic send near full-scale white noise:
RMS about 18,900 whatever the room sound, spectral flatness 0.3 to 0.5, energy spread
evenly up to 24 kHz. Real sound measures flatness under 0.01 with most energy below
1 kHz. The noise uses all 16 bits of each sample, so it looks like better audio until you
look at the spectrum.

**Never write to the unit with GUID `1f5d4ca9-de11-4487-840d-50933c8ec8d1`** (unit 9
here). It is Logitech's test and debug unit, and Logitech Capture uses it for EEPROM
writes and firmware upload (`TXU_EEPROM_ACCESS`, `AITXU_SET_FW_DATA`).

### Tests behind the selector 17 row

All on 2026-10-23, with the mic working:

| Test | Result |
|---|---|
| Write 1 while the mic works | The request times out, the camera drops off USB and reconnects. |
| Write 0 | Accepted at once. No reconnect. Mic unchanged. |
| Write a non-default block to selector 15, then write 1 to selector 17 | Camera reboots, and selector 15 reads the default block again. |
| Write a non-default block to selector 15, then `usbreset` | The read-back keeps the stereo flag but other bytes change. A USB reset is not the same as selector 17. |
| Write zeroed DSP parameters to selector 15, then the factory stereo block | Noise while zeroed, real sound at once after the factory block. No reboot. |

Older kernels or controllers report the failed write as `EPROTO` (-71) and return at
once. On 2026-10-23 it returned `ETIMEDOUT` (-110) after the 5 s USB timeout. Both mean
the camera rebooted.

## What Logi Options+ does

Read from `logioptionsplus_agent.exe` on the Windows disk (disassembled with capstone,
2026-10-23). This corrects an earlier note that Options+ turns the StreamCam mic on.

- The peripheral unit code is `logi::uvc::PeripheralUnitImpl` in
  `peripheral_unit_impl_win.cpp`. Each feature has a control ID: 0 audio mode, 1
  microphone enabled, 2 audio library mode, 3 auto framing.
- A static table maps control IDs to selectors per USB product ID. For `0893` it has one
  entry: control 0 (audio mode) on selector 15. Brio-family cameras map control 1 (mic
  enabled) to selector 16. The StreamCam has no mic-enable control.
- Options+ never sends selector 17 to any camera model.
- The regex `(c920|c922|reach|streamcam)` in the binary belongs to settings migrations
  (`xmigration_020_uvc_global_settings`, `xmigration_021_webcam_microphone_settings`),
  not to a mic switch.
- The device database (`data/devices/devices_initial.json`) lists for the StreamCam
  `microphone.audioMode` with values `MONO` and `STEREO`, default `STEREO`, and no
  `hasMicrophoneDisableSupport`.
- Logitech Capture's service log on Windows shows `STEREO: 1`, so Windows runs the
  camera in stereo.

## Checks

```sh
# Is the mic stuck? Prints the peak sample; 0 means stuck.
src=$(pactl list short sources | awk '/alsa_input.*StreamCam/{print $2; exit}')
timeout 1.5 pw-record --target "$src" --rate 16000 --channels 1 --format s16 - |
  python3 -c 'import sys,array; a=array.array("h",sys.stdin.buffer.read()[3200:]); print(max(map(abs,a)))'

# What did the script do?
journalctl --user -u streamcam-mic.service -n 20

# Reconnect loop? Count USB disconnects (all devices) since boot.
journalctl -k -b | grep -c 'USB disconnect'

# Recover by hand
streamcam-mic-enable --force
```

## Open questions

- Whether bad selector 15 parameters fully explain the all-zero state. If the mic goes
  silent again, the script's step 1 may fix it without a reset. In
  `journalctl --user -u streamcam-mic.service`, "no reset needed" after a silent mic
  means step 1 was enough. A "sent reset" line means it was not.
- The checks in the script only catch the all-zero state. A noise state (zeroed DSP
  parameters) passes the "any non-zero sample" check, but step 1 repairs it first.
