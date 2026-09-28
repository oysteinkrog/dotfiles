# /// script
# dependencies = ["numpy", "soundfile"]
# ///
"""Bake the old Equalizer APO chain into four stereo-to-binaural FIR filters.

Windows chain (config.txt on the old C: drive), all linear:
  1. AutoEq FIR for the KZ ZSX (minimum phase), per channel
  2. Preamp +8.5 dB
  3. HeSuVi: stereo is upmixed to 7.1 with matrix.txt, then each virtual
     speaker is convolved with the dht- HRIR (14-channel HeSuVi layout)
     and summed per ear.

For stereo input the whole chain collapses to a 2x2 FIR matrix, which is
what this writes: ir-<rate>.wav with channels
  0 = in L -> ear L, 1 = in L -> ear R, 2 = in R -> ear L, 3 = in R -> ear R

Run: uv run build.py
"""

from pathlib import Path

import numpy as np
import soundfile as sf

HERE = Path(__file__).parent
SRC = HERE / "source"
PREAMP_DB = 8.5

# HeSuVi matrix.txt: virtual speaker = a*L + b*R
UPMIX = {
    "FL": (0.5, 0.0),
    "FR": (0.0, 0.5),
    "FC": (0.2, 0.2),
    "RL": (0.3, -0.2),
    "RR": (-0.2, 0.3),
    "SL": (0.45, -0.25),
    "SR": (-0.25, 0.45),
}

# HeSuVi 14-channel HRIR order: (speaker, ear) per channel index
HRIR_LAYOUT = [
    ("FL", "L"), ("FL", "R"), ("SL", "L"), ("SL", "R"), ("RL", "L"), ("RL", "R"),
    ("FC", "L"), ("FR", "R"), ("FR", "L"), ("SR", "R"), ("SR", "L"), ("RR", "R"),
    ("RR", "L"), ("FC", "R"),
]


def build(rate: int) -> None:
    hrir, r1 = sf.read(SRC / f"hesuvi-dht-{rate}.wav", dtype="float64", always_2d=True)
    autoeq, r2 = sf.read(SRC / f"KZ ZSX minimum phase {rate}Hz.wav", dtype="float64", always_2d=True)
    assert r1 == r2 == rate and hrir.shape[1] == 14, (r1, r2, hrir.shape)

    gain = 10 ** (PREAMP_DB / 20)
    out = []
    for in_idx in (0, 1):  # input L, input R
        for ear in ("L", "R"):
            ear_ir = np.zeros(hrir.shape[0])
            for ch, (spk, e) in enumerate(HRIR_LAYOUT):
                if e == ear:
                    ear_ir += UPMIX[spk][in_idx] * hrir[:, ch]
            out.append(gain * np.convolve(autoeq[:, in_idx], ear_ir))
    ir = np.stack(out, axis=1)
    sf.write(HERE / f"ir-{rate}.wav", ir.astype(np.float32), rate, subtype="FLOAT")

    # Worst-case gain: full-scale mono sine hitting one ear (both direct paths add)
    n = 1 << 16
    spec = np.abs(np.fft.rfft(ir, n, axis=0))
    worst = max(np.max(np.abs(np.fft.rfft(ir[:, 0] + ir[:, 2], n))),
                np.max(np.abs(np.fft.rfft(ir[:, 1] + ir[:, 3], n))))
    print(f"{rate} Hz: {ir.shape[0]} taps, peak per-path gain "
          f"{20*np.log10(spec.max()):+.1f} dB, peak mono gain {20*np.log10(worst):+.1f} dB")


if __name__ == "__main__":
    for rate in (48000, 44100):
        build(rate)
