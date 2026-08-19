# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["whisperx>=3.8.6"]
# ///
"""SOTA single-pass path: WhisperX ASR + alignment + pyannote community-1.

Usage: with-secrets HF_TOKEN -- uv run transcribe_whisperx.py <wav> <out.json> [model]
(or put the token in ~/.hf_token on a remote box). The token must be allowed
to read gated repos: fine-grained tokens need the global "read gated repos"
permission, and the account must have accepted the terms at
hf.co/pyannote/speaker-diarization-community-1 — a plain 'read' token with no
acceptance fails with GatedRepoError 403.

CUDA when available, else CPU int8. Emits {"segments": [{start, end,
speaker, text}]} with anonymous SPEAKER_NN labels.
"""
import json
import os
import sys
import time

import torch
import whisperx

wav_path, out_path = sys.argv[1], sys.argv[2]
model_name = sys.argv[3] if len(sys.argv) > 3 else "large-v3-turbo"
tok = os.environ.get("HF_TOKEN") or open(os.path.expanduser("~/.hf_token")).read().strip()

device = "cuda" if torch.cuda.is_available() else "cpu"
compute = "float16" if device == "cuda" else "int8"
t0 = time.time()
audio = whisperx.load_audio(wav_path)
model = whisperx.load_model(model_name, device, compute_type=compute)
result = model.transcribe(audio, batch_size=16 if device == "cuda" else 4)
print(f"asr done {time.time()-t0:.0f}s lang={result['language']}", flush=True)

t1 = time.time()
diarize = whisperx.diarize.DiarizationPipeline(token=tok, device=device)
ds = diarize(audio)
print(f"diar done {time.time()-t1:.0f}s", flush=True)

result = whisperx.assign_word_speakers(ds, result)
segs = [
    {"start": s["start"], "end": s["end"], "speaker": s.get("speaker", "NA"), "text": s["text"].strip()}
    for s in result["segments"]
]
json.dump({"segments": segs}, open(out_path, "w"))
print(f"total {time.time()-t0:.0f}s, {len(segs)} segments", flush=True)
