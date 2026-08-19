# /// script
# requires-python = ">=3.10"
# dependencies = ["faster-whisper>=1.0"]
# ///
"""ASR only (no diarization): faster-whisper, CPU int8.

Usage: uv run asr_fw.py <wav-16k-mono> <out.json> [model]
Models: small (quick triage) | medium | large-v3-turbo (default on a fast box).
Emits {"language", "model", "segments": [{"start", "end", "text"}]}.
"""
import json
import sys
import time

from faster_whisper import WhisperModel

wav_path, out_path = sys.argv[1], sys.argv[2]
model_name = sys.argv[3] if len(sys.argv) > 3 else "large-v3-turbo"

t0 = time.time()
model = WhisperModel(model_name, device="cpu", compute_type="int8")
seg_iter, info = model.transcribe(wav_path, vad_filter=True, beam_size=5)
segs = [{"start": s.start, "end": s.end, "text": s.text.strip()} for s in seg_iter]
json.dump({"language": info.language, "model": model_name, "segments": segs}, open(out_path, "w"))
print(f"lang={info.language} ({info.language_probability:.2f}) {len(segs)} segments in {time.time()-t0:.0f}s")
