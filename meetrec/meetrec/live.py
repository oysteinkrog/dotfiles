"""Live transcript while a call records, so you can see that audio is coming through.

Runs next to the recorder for one session folder. Every 2 s it reads the new audio
in each track file, transcribes speech that has finished (a pause of 0.6 s after it)
with Whisper large-v3-turbo, and appends lines to live.jsonl. Speakers on the call
track are not told apart here; the full transcript after the call names them.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path

import numpy as np

from . import config
from .process import HALLUCINATIONS, NORWEGIANISH, RATE, to_rate

log = logging.getLogger("meetrec.live")

TICK_S = 2.0
PAUSE_S = 0.6  # speech counts as finished after this much silence
MAX_CHUNK_S = 25.0  # cut long monologues so the window does not lag behind


def transcribe(model, audio: np.ndarray, prompt: str) -> tuple[str, str]:
    _, _, probs = model.detect_language(audio)
    p = dict(probs)
    no = sum(p.get(c, 0.0) for c in NORWEGIANISH)
    lang = "no" if no >= p.get("en", 0.0) else "en"
    segs, _ = model.transcribe(
        audio,
        language=lang,
        beam_size=1,
        vad_filter=False,
        condition_on_previous_text=False,
        initial_prompt=prompt or None,
    )
    texts = [
        s.text.strip()
        for s in segs
        if s.text.strip()
        and not HALLUCINATIONS.match(s.text.strip())
        and not (s.no_speech_prob > 0.6 and s.avg_logprob < -1.0)
    ]
    return lang, " ".join(texts)


def run(d: Path) -> None:
    import torch  # noqa: F401  (loads the CUDA libraries CTranslate2 needs)
    from faster_whisper import WhisperModel
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    cfg = config.load()
    who = {"me": cfg["my_name"], "others": "Call"}
    prompt = ", ".join([cfg["my_name"], *cfg["vocabulary"]]) + "."
    model = WhisperModel("large-v3-turbo", device="cuda", compute_type="float16")
    vad = VadOptions(min_silence_duration_ms=int(PAUSE_S * 1000), speech_pad_ms=100)
    pos: dict[Path, int] = {}  # samples already handled, per track file
    out = d / "live.jsonl"
    log.info("live transcript for %s", d.name)

    while d.exists():
        for meta_path in sorted(d.glob("*-*-*.json")):
            pcm = meta_path.with_suffix(".pcm")
            if not pcm.exists():
                continue
            meta = json.loads(meta_path.read_text())
            # Positions below are in 16 kHz samples; the file may be at 48 kHz.
            step = meta.get("rate", RATE) // RATE
            start = pos.get(pcm, 0)
            raw = np.fromfile(pcm, dtype="<i2", offset=start * step * 2)
            audio = to_rate(raw.astype(np.float32) / 32768.0, meta.get("rate", RATE))
            if len(audio) < RATE:
                continue
            speech = get_speech_timestamps(audio, vad)
            if not speech:
                # Keep the last second: a word may be starting.
                pos[pcm] = start + max(0, len(audio) - RATE)
                continue
            done_before = len(audio) - int(PAUSE_S * RATE)
            finished = [s for s in speech if s["end"] <= done_before]
            if not finished and (len(audio) - speech[0]["start"]) > MAX_CHUNK_S * RATE:
                finished = speech  # long monologue: transcribe what we have
            if not finished:
                pos[pcm] = start + speech[0]["start"]
                continue
            a, b = finished[0]["start"], finished[-1]["end"]
            lang, text = transcribe(model, audio[a:b], prompt)
            pos[pcm] = start + b
            if not text:
                continue
            line = {
                "t": meta["offset_s"] + (start + a) / RATE,
                "who": who.get(meta["role"], meta["role"]),
                "lang": lang,
                "text": text,
            }
            if d.exists():
                with open(out, "a") as f:
                    f.write(json.dumps(line, ensure_ascii=False) + "\n")
        time.sleep(TICK_S)
    log.info("session folder gone, live transcript stops")
