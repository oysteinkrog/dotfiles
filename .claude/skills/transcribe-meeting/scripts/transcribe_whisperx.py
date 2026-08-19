# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = [
#   "whisperx>=3.8.6",
# ]
# ///
"""SOTA path: WhisperX ASR + alignment + pyannote community-1 diarization.

Needs HF_TOKEN in the environment (gated pyannote models; accept terms at
https://hf.co/pyannote/speaker-diarization-community-1). Run:
  with-secrets HF_TOKEN -- uv run transcribe_whisperx.py in.wav out.json [large-v3|large-v3-turbo]

Uses CUDA when available, else CPU (int8). On CPU expect ~realtime or slower
for large-v3; prefer a tech-pool box over WSL1.
"""
import json
import os
import sys

import torch
import whisperx

wav_path, out_path = sys.argv[1], sys.argv[2]
model_name = sys.argv[3] if len(sys.argv) > 3 else "large-v3"
hf_token = os.environ["HF_TOKEN"]

device = "cuda" if torch.cuda.is_available() else "cpu"
compute = "float16" if device == "cuda" else "int8"
print(f"device={device} model={model_name}", flush=True)

audio = whisperx.load_audio(wav_path)
model = whisperx.load_model(model_name, device, compute_type=compute)
result = model.transcribe(audio, batch_size=16 if device == "cuda" else 4)
print(f"ASR done: language={result['language']}", flush=True)

align_model, meta = whisperx.load_align_model(language_code=result["language"], device=device)
result = whisperx.align(result["segments"], align_model, meta, audio, device)
print("alignment done", flush=True)

diarize = whisperx.diarize.DiarizationPipeline(use_auth_token=hf_token, device=device)
diar_segments = diarize(audio)
result = whisperx.assign_word_speakers(diar_segments, result)
print("diarization done", flush=True)

segs = [
    {
        "start": s["start"],
        "end": s["end"],
        "text": s["text"].strip(),
        "speaker": s.get("speaker", "UNKNOWN"),
    }
    for s in result["segments"]
]
json.dump({"language": result["language"], "model": model_name, "segments": segs}, open(out_path, "w"), indent=0)
print(f"wrote {out_path} ({len(segs)} segments)", flush=True)
