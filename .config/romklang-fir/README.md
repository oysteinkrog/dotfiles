# Headphone FIR filters for romklang

[romklang](https://github.com/oysteinkrog/romklang) lists each folder here as a headphone EQ
called "NAME (FIR)". `install.sh` links this folder to `~/.config/romklang/fir`. Each folder
holds `48000.wav` and `44100.wav`, mono or stereo (left ear, right ear). A missing rate is
resampled from the other one.

- `KZ ZSX (AutoEq)`: the AutoEq minimum phase FIR for the KZ ZSX IEMs, from the old
  Equalizer APO setup on Windows.
- `windows-reference/`: that old Equalizer APO config, the HeSuVi matrix and the AutoEq
  parametric EQ, kept for reference.

The HeSuVi HRIRs and the AutoEq GraphicEQ list are not in this repo. `romklang import DIR`
copies them from a HeSuVi install into `~/.local/share/romklang`.
