"""Voiceprint library: CAM++ speaker embeddings (from senko) keyed by person name."""

from __future__ import annotations

import json

import numpy as np

from . import config

MAX_PER_PERSON = 30


def _path():
    return config.root() / "voices.json"


def load() -> dict[str, dict]:
    p = _path()
    return json.loads(p.read_text()) if p.exists() else {}


def save(lib: dict[str, dict]) -> None:
    p = _path()
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(lib, ensure_ascii=False))
    tmp.replace(p)


def _unit(v) -> np.ndarray:
    v = np.asarray(v, dtype=np.float32)
    return v / (np.linalg.norm(v) + 1e-9)


def enroll(name: str, embedding, session: str) -> None:
    lib = load()
    person = lib.setdefault(name, {"embeddings": [], "sessions": []})
    person["embeddings"].append([round(float(x), 5) for x in _unit(embedding)])
    person["sessions"].append(session)
    person["embeddings"] = person["embeddings"][-MAX_PER_PERSON:]
    person["sessions"] = person["sessions"][-MAX_PER_PERSON:]
    save(lib)


def match(
    embedding, exclude: set[str] = frozenset()
) -> tuple[str | None, float, float]:
    """Best name for an embedding: (name or None, score, margin over the runner-up)."""
    cfg = config.load()
    e = _unit(embedding)
    scores = []
    for name, person in load().items():
        if name in exclude or not person["embeddings"]:
            continue
        centroid = _unit(np.mean([_unit(x) for x in person["embeddings"]], axis=0))
        scores.append((float(e @ centroid), name))
    if not scores:
        return None, 0.0, 0.0
    scores.sort(reverse=True)
    best, name = scores[0]
    margin = best - (scores[1][0] if len(scores) > 1 else 0.0)
    if best >= cfg["voice_threshold"] and margin >= cfg["voice_margin"]:
        return name, best, margin
    return None, best, margin
