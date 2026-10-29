"""Settings in ~/meetings/config.json, created with defaults on first use."""

from __future__ import annotations

import json
import os
from pathlib import Path

DEFAULTS = {
    "my_name": "Øystein",
    "notify": True,
    "summary": True,
    "summary_model": "sonnet",
    # Words Whisper should spell right: product names, colleagues, jargon.
    "vocabulary": ["Swing Catalyst", "Motion Catalyst", "Initial Force"],
    # Cosine similarity a cluster needs against a stored voiceprint to get that name.
    "voice_threshold": 0.6,
    "voice_margin": 0.08,
    # Name speakers from the Meet extension's speaking hints (and learn their voices).
    # Off until the hints are checked against real calls.
    "trust_meet_speaking": False,
    # Transcribe while the call runs, for the tray's live window.
    "live_transcript": True,
}


def root() -> Path:
    return Path(os.environ.get("MEETREC_ROOT", Path.home() / "meetings"))


def load() -> dict:
    p = root() / "config.json"
    if not p.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(DEFAULTS, indent=2, ensure_ascii=False) + "\n")
    cfg = dict(DEFAULTS)
    cfg.update(json.loads(p.read_text()))
    return cfg
