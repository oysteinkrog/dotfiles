# Headphone FIR filters for hesuvi

Each folder is one headphone EQ that `hesuvi` lists as "NAME (FIR)". It holds
`48000.wav` and `44100.wav`, mono or stereo (left ear, right ear). A missing rate is
resampled from the other one. Folders in `~/.local/share/hesuvi/fir` are listed too.

- `KZ ZSX (AutoEq)`: the AutoEq minimum phase FIR for the KZ ZSX IEMs, from the old
  Equalizer APO setup on Windows.
- `windows-reference/`: that old Equalizer APO config, the HeSuVi matrix and the AutoEq
  parametric EQ, kept for reference.

The HeSuVi HRIRs and the AutoEq GraphicEQ list are not in this repo. `hesuvi import DIR`
copies them from a HeSuVi install into `~/.local/share/hesuvi`.
