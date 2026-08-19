# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "torch==2.6.0+cpu",
#   "torchaudio==2.6.0+cpu",
#   "faster-whisper>=1.0",
#   "speechbrain>=1.0",
#   "scikit-learn",
#   "numpy",
# ]
# ///
"""CPU fallback: faster-whisper ASR + ECAPA-TDNN speaker-embedding clustering.

No gated models, no HF token. Clusters are anonymous voice IDs; map them to
names from the meeting video (see SKILL.md step 4). Run with:
  UV_EXTRA_INDEX_URL=https://download.pytorch.org/whl/cpu \
  UV_INDEX_STRATEGY=unsafe-best-match uv run transcribe_cpu.py in.wav out.json [small|medium|large-v3-turbo]

Expects 16 kHz mono 16-bit PCM WAV (ffmpeg -ac 1 -ar 16000).
"""
import json
import sys
import time
import wave

import numpy as np
import torch
from faster_whisper import WhisperModel
from sklearn.cluster import AgglomerativeClustering
from sklearn.metrics import silhouette_score
from speechbrain.inference.speaker import EncoderClassifier

wav_path, out_path = sys.argv[1], sys.argv[2]
model_name = sys.argv[3] if len(sys.argv) > 3 else "small"

t0 = time.time()
model = WhisperModel(model_name, device="cpu", compute_type="int8")
seg_iter, info = model.transcribe(wav_path, vad_filter=True, beam_size=5)
print(f"language={info.language} prob={info.language_probability:.2f} duration={info.duration:.0f}s", flush=True)
segs = [{"start": s.start, "end": s.end, "text": s.text.strip()} for s in seg_iter]
print(f"ASR done: {len(segs)} segments in {time.time()-t0:.0f}s", flush=True)

with wave.open(wav_path, "rb") as w:
    sr = w.getframerate()
    assert sr == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2
    audio = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0

enc = EncoderClassifier.from_hparams(source="speechbrain/spkrec-ecapa-voxceleb", savedir="ecapa-model")
embs = []
for s in segs:
    chunk = audio[int(s["start"] * sr) : int(s["end"] * sr)]
    if len(chunk) < sr // 2:
        chunk = np.pad(chunk, (0, sr // 2 - len(chunk)))
    with torch.no_grad():
        e = enc.encode_batch(torch.from_numpy(chunk).unsqueeze(0)).squeeze().numpy()
    embs.append(e / np.linalg.norm(e))
X = np.array(embs)
print(f"embedded {len(X)} segments", flush=True)

# Cluster long segments only (short ones carry too little voice), assign the
# rest to the nearest centroid. Pick k by silhouette but print the sweep so the
# agent can override: same-language colleagues on similar mics often merge.
dur = np.array([s["end"] - s["start"] for s in segs])
long_idx = np.where(dur >= 3)[0]
if len(long_idx) < 10:
    long_idx = np.arange(len(segs))
best = None
for k in range(2, min(9, len(long_idx))):
    labels_long = AgglomerativeClustering(n_clusters=k, metric="cosine", linkage="average").fit_predict(X[long_idx])
    score = silhouette_score(X[long_idx], labels_long, metric="cosine")
    print(f"k={k} silhouette={score:.3f} sizes={np.bincount(labels_long).tolist()}", flush=True)
    if best is None or score > best[0]:
        best = (score, k, labels_long)
_, k, labels_long = best
cents = np.array([X[long_idx][labels_long == c].mean(axis=0) for c in range(k)])
cents /= np.linalg.norm(cents, axis=1, keepdims=True)
labels = np.argmax(X @ cents.T, axis=1)
print(f"chosen k={k}", flush=True)

for s, l in zip(segs, labels):
    s["cluster"] = int(l)
json.dump({"language": info.language, "model": model_name, "segments": segs}, open(out_path, "w"), indent=0)
print(f"wrote {out_path} in {time.time()-t0:.0f}s total", flush=True)
