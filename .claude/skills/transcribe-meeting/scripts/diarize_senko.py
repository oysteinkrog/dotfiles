# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["senko @ git+https://github.com/narcotic-sh/senko.git", "torch==2.8.0+cpu", "torchaudio==2.8.0+cpu"]
# ///
"""Speaker diarization with senko (CAM++ embeddings + spectral clustering).

Usage: uv run diarize_senko.py <wav-16k-mono> <out.json> [n_speakers]

Pass n_speakers whenever you know it (count the human tiles in the meeting-UI
frames; exclude bots). With the oracle count, spectral clustering replaces
senko's auto-count path, which under-counts low-airtime speakers (measured:
93.5% -> 97.2% on the 6-speaker benchmark; see ../EVALUATION.md). Omit or pass
0 to let senko estimate.

Run with the CPU torch index or a GPU-less box pulls CUDA wheels:
  UV_EXTRA_INDEX_URL=https://download.pytorch.org/whl/cpu UV_INDEX_STRATEGY=unsafe-best-match
Emits {"segments": [{"start", "end", "speaker": "SPEAKER_NN"}]}.
"""
import json
import sys
import time

import senko

n = int(sys.argv[3]) if len(sys.argv) > 3 else 0
t0 = time.time()
d = senko.Diarizer(device="cpu", warmup=False)
if n > 0:
    d.spectral_cluster.cluster.k = n
    d.umap_hdbscan_cluster = d.spectral_cluster  # senko routes >20 min audio to auto-count HDBSCAN; force spectral
result = d.diarize(sys.argv[1], generate_colors=False)
segs = [{"start": s["start"], "end": s["end"], "speaker": str(s["speaker"])} for s in result["merged_segments"]]
json.dump({"segments": segs}, open(sys.argv[2], "w"))
labels = sorted(set(s["speaker"] for s in segs))
print(f"done in {time.time()-t0:.0f}s, {len(segs)} segments, {len(labels)} speakers: {labels}")
