"""Turn a finished recording into a named, timestamped transcript.

Steps: rebuild the two aligned tracks, find my turns on the mic track, diarize
the others track with senko, name each cluster from Meet speaker events and the
voiceprint library, pick English or Norwegian per turn, transcribe, write files.
"""

from __future__ import annotations

import json
import logging
import re
import shutil
import subprocess
import time
from pathlib import Path

import numpy as np
import soundfile as sf

from . import config, voices

log = logging.getLogger("meetrec.process")

RATE = 16000
EN_MODEL = "large-v3-turbo"
NO_MODEL_REPO = "NbAiLab/nb-whisper-large"
NORWEGIANISH = {"no", "nn", "sv", "da"}
# Phrases Whisper invents on silence or noise, mostly from subtitle training data.
HALLUCINATIONS = re.compile(
    r"^(teksting av|undertekster av|takk for (at du så|meg|nå)|thanks? (you )?for watching|"
    r"subtitles by|\.+$|you$)",
    re.IGNORECASE,
)


# Tracks ---------------------------------------------------------------------------
def to_rate(audio: np.ndarray, rate: int) -> np.ndarray:
    """Resample to the 16 kHz the models use. Recordings are captured at 48 kHz."""
    if rate == RATE:
        return audio
    from math import gcd

    from scipy.signal import resample_poly

    g = gcd(RATE, rate)
    return resample_poly(audio, RATE // g, rate // g).astype(np.float32)


def archive_raw(d: Path, out: Path) -> None:
    """Keep everything the recorder wrote, so the pipeline can be rerun or improved later.

    Each stream's raw PCM becomes a lossless FLAC at its capture rate. The metadata,
    Meet events and live transcript are copied as they are.
    """
    raw = out / "raw"
    raw.mkdir(exist_ok=True)
    for f in d.iterdir():
        if f.suffix == ".pcm":
            meta = json.loads(f.with_suffix(".json").read_text())
            audio = np.fromfile(f, dtype="<i2")
            sf.write(raw / f"{f.stem}.flac", audio, meta.get("rate", RATE), "PCM_16")
        elif f.is_file():
            shutil.copy2(f, raw / f.name)


def pipeline_info(gain: float) -> dict:
    """What produced this transcript, so results from different versions can be compared."""
    src = Path(__file__).resolve().parent
    git = ["git", "-C", str(src)]
    commit = subprocess.run(
        [*git, "rev-parse", "--short", "HEAD"], capture_output=True, text=True
    ).stdout.strip()
    dirty = subprocess.run(
        [*git, "status", "--porcelain", "--", "."], capture_output=True, text=True
    ).stdout.strip()
    return {
        "processed": time.strftime("%Y-%m-%d %H:%M:%S"),
        "commit": commit + ("+dirty" if dirty else ""),
        "mic_gain": round(gain, 2),
        "asr": {"en": EN_MODEL, "no": NO_MODEL_REPO},
        "config": config.load(),
    }


def build_tracks(d: Path) -> tuple[np.ndarray, np.ndarray]:
    parts: dict[str, list[tuple[float, np.ndarray]]] = {"me": [], "others": []}
    for meta_path in sorted(d.glob("*-*-*.json")):
        m = json.loads(meta_path.read_text())
        pcm = meta_path.with_suffix(".pcm")
        if not pcm.exists():
            continue
        audio = np.fromfile(pcm, dtype="<i2").astype(np.float32) / 32768.0
        parts[m["role"]].append((m["offset_s"], to_rate(audio, m.get("rate", RATE))))
    length = max(
        [int(off * RATE) + len(a) for role in parts.values() for off, a in role] or [0]
    )
    tracks = {}
    for role, items in parts.items():
        t = np.zeros(length, dtype=np.float32)
        for off, a in items:
            s = int(off * RATE)
            t[s : s + len(a)] += a
        tracks[role] = np.clip(t, -1, 1)
    return tracks["me"], tracks["others"]


# Meet events ----------------------------------------------------------------------
def parse_events(d: Path, t0: float) -> dict:
    """Roster, per-name speaking intervals and my muted intervals from the extension."""
    p = d / "events.jsonl"
    out = {"roster": [], "self": None, "speaking": {}, "muted": [], "title": None}
    if not p.exists():
        return out
    evs = [json.loads(line) for line in p.read_text().splitlines() if line.strip()]
    evs.sort(key=lambda e: e.get("t", 0))
    roster: list[str] = []
    for i, e in enumerate(evs):
        t = e["t"] / 1000 - t0
        nxt = evs[i + 1]["t"] / 1000 - t0 if i + 1 < len(evs) else t + 1
        dt = min(max(nxt - t, 0), 1.5)
        out["self"] = e.get("self") or out["self"]
        out["title"] = e.get("title") or out["title"]
        for name in e.get("participants", []):
            if name not in roster:
                roster.append(name)
        for name in e.get("speaking", []):
            out["speaking"].setdefault(name, []).append((t, t + dt))
        if e.get("muted"):
            out["muted"].append((t, t + dt))
    out["roster"] = roster
    return out


def overlap(a: list[tuple[float, float]], b: list[tuple[float, float]]) -> float:
    total = 0.0
    for s1, e1 in a:
        for s2, e2 in b:
            total += max(0.0, min(e1, e2) - max(s1, s2))
    return total


# My turns -------------------------------------------------------------------------
def mic_gain(me: np.ndarray) -> float:
    """Gain that brings my loudest speech to about -12 dBFS.

    Slack levels the mic on its side, so a quiet mic still sounds fine in the call, but
    the raw track can sit near -50 dBFS and the VAD then misses whole sentences.
    """
    frame = RATE // 20
    n = len(me) // frame
    if n == 0:
        return 1.0
    rms = np.sqrt((me[: n * frame].reshape(n, frame) ** 2).mean(1))
    peak = float(np.percentile(rms, 99.5))
    return float(np.clip(0.25 / peak, 1.0, 40.0)) if peak > 0 else 1.0


def my_turns(
    me: np.ndarray, others: np.ndarray, muted: list, gain: float = 1.0
) -> list[dict]:
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    if not me.any():
        return []
    ts = get_speech_timestamps(
        np.clip(me * gain, -1, 1),
        VadOptions(
            min_silence_duration_ms=700, speech_pad_ms=200, min_speech_duration_ms=300
        ),
    )
    frame = RATE // 20  # 50 ms
    turns = []
    for seg in ts:
        s, e = seg["start"], seg["end"]
        n = (e - s) // frame
        if n == 0:
            continue
        m_rms = np.sqrt((me[s : s + n * frame].reshape(n, frame) ** 2).mean(1))
        o_rms = np.sqrt((others[s : s + n * frame].reshape(n, frame) ** 2).mean(1))
        # Speaker bleed: while the call is loud, the mic hears it at a fraction of its
        # level. Frames like that are not mine; pauses and my own speech are.
        bleed = (o_rms > 0.01) & (m_rms <= 0.5 * o_rms)
        # Smooth over 0.5 s so single frames do not split or join turns.
        bleed = np.convolve(bleed.astype(float), np.ones(10) / 10, mode="same") > 0.5
        for a, b in runs(~bleed):
            if b - a < 10 or m_rms[a:b].max() * gain < 0.02:
                continue
            start, end = (s + a * frame) / RATE, (s + b * frame) / RATE
            if any(overlap([(start, end)], [mu]) > 0.5 * (end - start) for mu in muted):
                continue
            turns.append({"start": start, "end": end, "track": "me"})
    return turns


def runs(mask: np.ndarray) -> list[tuple[int, int]]:
    """Start and end index of each run of True values."""
    padded = np.concatenate([[False], mask, [False]]).astype(int)
    edges = np.flatnonzero(np.diff(padded))
    return list(zip(edges[::2], edges[1::2]))


# Others -----------------------------------------------------------------------------
def diarize(others: np.ndarray, k: int) -> tuple[list[dict], dict]:
    import senko

    if not others.size or np.sqrt((others**2).mean()) < 1e-4:
        return [], {}
    d = senko.Diarizer(device="cuda", warmup=False, quiet=True)
    if k > 0:
        for c in (d.spectral_cluster, getattr(d.spectral_cluster, "cluster", None)):
            if c is not None and hasattr(c, "k"):
                c.k = k
        d.umap_hdbscan_cluster = d.spectral_cluster
    r = d.diarize_samples(others, sample_rate=RATE)
    if not r:
        return [], {}
    segs = [
        {
            "start": float(s["start"]),
            "end": float(s["end"]),
            "speaker": str(s["speaker"]),
        }
        for s in r["merged_segments"]
    ]
    return segs, {k: np.asarray(v) for k, v in r["speaker_centroids"].items()}


def name_clusters(
    segs: list[dict], centroids: dict, ev: dict, my_name: str
) -> dict[str, dict]:
    """Map senko cluster ids to {name, how}. Meet speaker events first, then voiceprints."""
    names: dict[str, dict] = {}
    me_aliases = {my_name, ev.get("self")}
    by_cluster: dict[str, list] = {}
    for s in segs:
        by_cluster.setdefault(s["speaker"], []).append((s["start"], s["end"]))
    # The extension's speaking hints are unverified on live calls; use them only when trusted.
    speaking = ev["speaking"] if config.load().get("trust_meet_speaking") else {}
    for cid, spans in by_cluster.items():
        scores = {
            n: overlap(spans, iv) for n, iv in speaking.items() if n not in me_aliases
        }
        total = sum(scores.values())
        if total:
            best = max(scores, key=lambda n: scores[n])
            if scores[best] >= 2.0 and scores[best] >= 0.5 * total:
                names[cid] = {
                    "name": best,
                    "how": f"meet ({scores[best]:.0f}s overlap)",
                }
    for cid in by_cluster:
        if cid in names or cid not in centroids:
            continue
        name, score, margin = voices.match(centroids[cid], exclude={my_name})
        if name:
            names[cid] = {
                "name": name,
                "how": f"voiceprint ({score:.2f}, margin {margin:.2f})",
            }
    n = 0
    for cid in sorted(by_cluster):
        if cid not in names:
            n += 1
            names[cid] = {"name": None, "how": "unknown", "label": f"S{n}"}
    return names


# ASR --------------------------------------------------------------------------------
class Asr:
    def __init__(self) -> None:
        import torch  # noqa: F401  (loads the CUDA libraries CTranslate2 needs)
        from faster_whisper import WhisperModel
        from huggingface_hub import snapshot_download

        self.en = WhisperModel(EN_MODEL, device="cuda", compute_type="float16")
        nb = Path(
            snapshot_download(
                NO_MODEL_REPO,
                allow_patterns=["ct2/*", "preprocessor_config.json", "tokenizer.json"],
            )
        )
        # The repo's ct2/ folder lacks the preprocessor config (128 mel bins) and the
        # tokenizer, so assemble a complete model folder from links.
        model_dir = Path.home() / ".local/share/meetrec/models/nb-whisper-large"
        model_dir.mkdir(parents=True, exist_ok=True)
        for src in [
            *(nb / "ct2").iterdir(),
            nb / "preprocessor_config.json",
            nb / "tokenizer.json",
        ]:
            link = model_dir / src.name
            if link.is_symlink() or link.exists():
                link.unlink()
            link.symlink_to(src.resolve())
        self.no = WhisperModel(str(model_dir), device="cuda", compute_type="float16")

    def language(self, audio: np.ndarray) -> tuple[str, float, float]:
        """("en" or "no", confidence between the two, share of all languages they hold)."""
        _, _, probs = self.en.detect_language(audio)
        p = dict(probs)
        no = sum(p.get(code, 0.0) for code in NORWEGIANISH)
        en = p.get("en", 0.0)
        both = no + en + 1e-9
        lang = "no" if no >= en else "en"
        return lang, max(no, en) / both, both

    def transcribe(self, audio: np.ndarray, lang: str, prompt: str) -> str:
        model = self.no if lang == "no" else self.en
        segs, _ = model.transcribe(
            audio,
            language=lang,
            beam_size=5,
            vad_filter=False,
            condition_on_previous_text=False,
            initial_prompt=prompt or None,
        )
        out = []
        for s in segs:
            text = s.text.strip()
            if not text or HALLUCINATIONS.match(text):
                continue
            if s.no_speech_prob > 0.6 and s.avg_logprob < -1.0:
                continue
            out.append(text)
        return " ".join(out)


def merge_turns(
    turns: list[dict], gap: float = 1.0, max_len: float = 60.0
) -> list[dict]:
    turns = sorted(turns, key=lambda t: (t["speaker"], t["start"]))
    merged: list[dict] = []
    for t in turns:
        p = merged[-1] if merged else None
        if (
            p
            and p["speaker"] == t["speaker"]
            and t["start"] - p["end"] <= gap
            and t["end"] - p["start"] <= max_len
        ):
            p["end"] = max(p["end"], t["end"])
        else:
            merged.append(dict(t))
    return sorted(merged, key=lambda t: t["start"])


def speech_pieces(audio: np.ndarray) -> list[list]:
    """Split a turn at pauses of 300 ms or more: [start_sample, end_sample, lang]."""
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    ts = get_speech_timestamps(
        audio, VadOptions(min_silence_duration_ms=300, speech_pad_ms=100)
    )
    return [[s["start"], s["end"], None] for s in ts]


def transcribe_turns(turns, me, others, asr: Asr, prompt: str) -> None:
    """Pick English or Norwegian per piece of speech, so a speaker can switch mid-turn."""

    def clip(t):
        src = me if t["track"] == "me" else others
        return src[int(t["start"] * RATE) : int(t["end"] * RATE)]

    votes: dict[str, dict[str, float]] = {}
    for t in turns:
        audio = clip(t)
        t["pieces"] = []
        for a, b, _ in speech_pieces(audio):
            secs = (b - a) / RATE
            lang, conf, share = asr.language(audio[a:b])
            # Short noise reads as some other language ("Продолжение следует..."): drop it.
            if share < 0.5 and secs < 2.0:
                continue
            piece = [a, b, lang if secs >= 1.0 else None]
            t["pieces"].append(piece)
            if piece[2]:
                v = votes.setdefault(t["speaker"], {})
                v[lang] = v.get(lang, 0) + secs * conf
    overall: dict[str, float] = {}
    for v in votes.values():
        for lang, w in v.items():
            overall[lang] = overall.get(lang, 0) + w
    default = max(overall, key=lambda k: overall[k]) if overall else "no"

    for t in turns:
        audio = clip(t)
        pieces = t.pop("pieces")
        v = votes.get(t["speaker"])
        fallback = max(v, key=lambda k: v[k]) if v else default
        # Pieces under 1 s take the language of the piece before them, or after them.
        for i, p in enumerate(pieces):
            if p[2] is None:
                near = [q[2] for q in pieces[i - 1 :: -1] if q[2]] if i else []
                near += [q[2] for q in pieces[i + 1 :] if q[2]]
                p[2] = near[0] if near else fallback
        # Transcribe each run of same-language pieces as one unit.
        runs_: list[list] = []
        for a, b, lang in pieces:
            if runs_ and runs_[-1][2] == lang:
                runs_[-1][1] = b
            else:
                runs_.append([a, b, lang])
        texts, secs_by_lang = [], {}
        for a, b, lang in runs_:
            text = asr.transcribe(audio[a:b], lang, prompt)
            if text:
                texts.append(text)
                secs_by_lang[lang] = secs_by_lang.get(lang, 0) + (b - a)
        t["text"] = " ".join(texts)
        t["lang"] = (
            max(secs_by_lang, key=lambda k: secs_by_lang[k])
            if secs_by_lang
            else fallback
        )
        t["langs"] = sorted(secs_by_lang)


# Output -----------------------------------------------------------------------------
def fmt_ts(sec: float) -> str:
    sec = int(sec)
    return (
        f"{sec // 3600}:{sec % 3600 // 60:02d}:{sec % 60:02d}"
        if sec >= 3600
        else f"{sec // 60:02d}:{sec % 60:02d}"
    )


def display_name(t: dict, clusters: dict) -> str:
    if t["track"] == "me":
        return config.load()["my_name"]
    c = clusters[t["speaker"]]
    return c["name"] or f"Unknown speaker {c['label']}"


def write_transcript(d: Path) -> None:
    info = json.loads((d / "session.json").read_text())
    clusters = info["clusters"]
    turns = info["turns"]
    lines = [f"# {info['heading']}", ""]
    lines.append(f"- Date: {info['date']}")
    lines.append(f"- Length: {fmt_ts(info['duration'])}")
    present = [config.load()["my_name"]] + sorted(
        {c["name"] for c in clusters.values() if c["name"]}
    )
    unknown = sorted(c["label"] for c in clusters.values() if not c["name"])
    lines.append(f"- Speakers: {', '.join(present)}")
    if unknown:
        lines.append(
            f'- Not yet named: {", ".join(unknown)}. Run `meetrec label "{d}" S1="Full Name"`.'
        )
    if info.get("roster"):
        lines.append(f"- Meet participants: {', '.join(info['roster'])}")
    how = "; ".join(
        f"{c['name'] or c.get('label')}: {c['how']}" for c in clusters.values()
    )
    lines.append(f"- Name source: {how or 'only my microphone track'}")
    lines.append(
        "- Method: my mic and the call audio recorded as separate tracks; senko diarization on the "
        "call track; Norwegian turns by NbAiLab nb-whisper-large, English turns by Whisper "
        "large-v3-turbo."
    )
    lines.append("")
    prev = None
    for t in turns:
        if not t.get("text"):
            continue
        name = display_name(t, clusters)
        if name == prev:
            lines[-2] += " " + t["text"]
            continue
        # Mark turns in the meeting's second language, e.g. [en] in a Norwegian meeting.
        langs = t.get("langs") or [t["lang"]]
        tag = f" [{'+'.join(langs)}]" if langs != [info["main_lang"]] else ""
        lines += [f"**[{fmt_ts(t['start'])}] {name}:**{tag} {t['text']}", ""]
        prev = name
    (d / "transcript.md").write_text("\n".join(lines).rstrip() + "\n")


def summarize(d: Path) -> None:
    cfg = config.load()
    if not cfg.get("summary") or not shutil.which("claude"):
        return
    prompt = (
        "Summarize this meeting transcript for the person who recorded it "
        f"({cfg['my_name']}). Write in the language most of the meeting was held in. "
        "Start with the outcome in two or three sentences. Then list decisions, then action "
        "items as a table with owner and item. Use the speaker names exactly as given. "
        "Plain language, no em dashes, no headings above level 2. Output Markdown only.\n\n"
    )
    transcript = (d / "transcript.md").read_text()
    try:
        r = subprocess.run(
            ["claude", "-p", "--model", cfg["summary_model"]],
            input=prompt + transcript,
            capture_output=True,
            text=True,
            timeout=600,
        )
        if r.returncode == 0 and r.stdout.strip():
            (d / "summary.md").write_text(r.stdout.strip() + "\n")
        else:
            log.warning("summary failed: %s", r.stderr[-500:])
    except subprocess.TimeoutExpired:
        log.warning("summary timed out")


def safe_name(s: str) -> str:
    return re.sub(r"[^\w .,&()+-]+", "", s).strip()[:80] or "call"


def process(d: Path) -> Path:
    cfg = config.load()
    meta = json.loads((d / "meta.json").read_text())
    t0 = meta["start"]
    me, others = build_tracks(d)
    ev = parse_events(d, t0)
    log.info("%s: %.0f s of audio, roster %s", d.name, len(me) / RATE, ev["roster"])

    gain = mic_gain(me)
    log.info("mic gain %.1fx", gain)
    mine = my_turns(me, others, ev["muted"], gain)
    roster_others = [n for n in ev["roster"] if n not in (ev["self"], cfg["my_name"])]
    # A roster scraped from the Meet page can be wrong; only trust a plausible size.
    k = len(roster_others) if 1 <= len(roster_others) <= 15 else 0
    segs, centroids = diarize(others, k)
    clusters = name_clusters(segs, centroids, ev, cfg["my_name"])

    turns = [dict(t, speaker="me") for t in mine]
    turns += [
        {
            "start": s["start"],
            "end": s["end"],
            "track": "others",
            "speaker": s["speaker"],
        }
        for s in segs
    ]
    turns = merge_turns(turns)

    names = (
        [cfg["my_name"]]
        + [c["name"] for c in clusters.values() if c["name"]]
        + roster_others
    )
    prompt = ", ".join(dict.fromkeys(names + cfg["vocabulary"])) + "."
    asr = Asr()
    transcribe_turns(turns, np.clip(me * gain, -1, 1), others, asr, prompt)
    del asr

    langs: dict[str, float] = {}
    for t in turns:
        langs[t["lang"]] = langs.get(t["lang"], 0) + t["end"] - t["start"]
    label = {"slack": "Slack huddle", "meet": "Google Meet"}[meta["app"]]
    title = meta.get("title") or ev["title"]
    if (
        title
        and meta["app"] == "meet"
        and not re.fullmatch(r"(Meet|Google Meet)( - [a-z-]+)?", title)
    ):
        label = f"{label} - {title.removeprefix('Meet - ')}"
    stamp = time.strftime("%Y-%m-%d %H%M", time.localtime(t0))
    out = config.root() / safe_name(f"{stamp} {label}")
    i = 2
    while out.exists():
        out = config.root() / safe_name(f"{stamp} {label} {i}")
        i += 1
    out.mkdir()

    sf.write(out / "me.flac", me, RATE)
    sf.write(out / "others.flac", others, RATE)
    if (d / "events.jsonl").exists():
        shutil.copy(d / "events.jsonl", out / "events.jsonl")
    for cid, c in clusters.items():
        if cid in centroids:
            c["centroid"] = [round(float(x), 5) for x in centroids[cid]]
    session = {
        "heading": f"{label}, {time.strftime('%Y-%m-%d %H:%M', time.localtime(t0))}",
        "date": time.strftime("%Y-%m-%d %H:%M", time.localtime(t0)),
        "app": meta["app"],
        "start": t0,
        "duration": len(me) / RATE,
        "roster": ev["roster"],
        "main_lang": max(langs, key=lambda k: langs[k]) if langs else "no",
        "clusters": clusters,
        "turns": turns,
        "pipeline": pipeline_info(gain),
    }
    (out / "session.json").write_text(json.dumps(session, indent=1, ensure_ascii=False))
    write_transcript(out)

    # Names bound by Meet's own speaker highlight are reliable enough to learn voices from.
    for cid, c in clusters.items():
        if c["how"].startswith("meet") and "centroid" in c:
            voices.enroll(c["name"], c["centroid"], out.name)

    summarize(out)
    archive_raw(d, out)
    shutil.rmtree(d)
    log.info("done: %s", out)
    return out


def redo(out: Path) -> Path:
    """Transcribe a finished call again from its saved audio, e.g. after a pipeline fix.

    Uses the raw streams in raw/ when the folder has them, else the two mixed tracks.
    The new folder takes the old name. The old results move to .history/, so runs of
    different pipeline versions can be compared.
    """
    session = json.loads((out / "session.json").read_text())
    start = session.get("start") or time.mktime(
        time.strptime(session["date"], "%Y-%m-%d %H:%M")
    )
    root = config.root()
    q = root / ".redo" / out.name
    q.mkdir(parents=True)
    raw = out / "raw"
    if raw.is_dir() and any(raw.glob("*.flac")):
        for f in raw.iterdir():
            if f.suffix == ".flac":
                audio, _ = sf.read(f, dtype="int16")
                (q / f"{f.stem}.pcm").write_bytes(audio.astype("<i2").tobytes())
            elif f.is_file():
                shutil.copy2(f, q / f.name)
    else:
        for role in ("me", "others"):
            audio, _ = sf.read(out / f"{role}.flac", dtype="int16")
            stem = f"{role}-0-000000000"
            (q / f"{stem}.pcm").write_bytes(audio.astype("<i2").tobytes())
            (q / f"{stem}.json").write_text(
                json.dumps({"role": role, "node": 0, "offset_s": 0.0, "rate": RATE})
            )
        if (out / "events.jsonl").exists():
            shutil.copy(out / "events.jsonl", q / "events.jsonl")
    if not (q / "meta.json").exists():
        (q / "meta.json").write_text(
            json.dumps({"app": session["app"], "start": start})
        )
    new = process(q)
    # Files added by hand (labels log, Slack's own transcript) carry over.
    for f in out.iterdir():
        if f.is_file() and not (new / f.name).exists():
            shutil.copy2(f, new / f.name)
    # The new folder holds the same raw streams, so the old copy is not needed twice.
    if raw.is_dir() and len(list((new / "raw").glob("*.flac"))) == len(
        list(raw.glob("*.flac"))
    ):
        shutil.rmtree(raw)
    history = root / ".history"
    history.mkdir(exist_ok=True)
    stamp = time.strftime("%Y-%m-%d %H%M%S")
    out.rename(history / f"{out.name} (replaced {stamp})")
    new.rename(out)
    return out


def relabel(
    out: Path, assignments: dict[str, str], unsure: frozenset[str] = frozenset()
) -> None:
    """Name unknown or wrong clusters by hand and teach the voiceprint library.

    Speakers listed in `unsure` get the name but do not train their voiceprint.
    """
    p = out / "session.json"
    session = json.loads(p.read_text())
    by_label = {
        c.get("label") or c["name"]: cid for cid, c in session["clusters"].items()
    }
    for key, name in assignments.items():
        cid = by_label.get(key) or (key if key in session["clusters"] else None)
        if not cid:
            raise SystemExit(
                f"no speaker {key!r} in {out}; known: {', '.join(by_label)}"
            )
        c = session["clusters"][cid]
        with open(out / "labels.jsonl", "a") as f:
            entry = {"t": time.time(), "cluster": cid, "was": c["name"], "name": name}
            f.write(json.dumps(entry | {"unsure": key in unsure}, ensure_ascii=False))
            f.write("\n")
        c["name"] = name
        if key in unsure:
            c["how"] = "labelled by hand, unsure, voice not saved"
            continue
        c["how"] = "labelled by hand"
        if "centroid" in c:
            voices.enroll(name, c["centroid"], out.name)
    p.write_text(json.dumps(session, indent=1, ensure_ascii=False))
    write_transcript(out)
    if (out / "summary.md").exists():
        summarize(out)


def notify_done(out: Path) -> None:
    # The processing service exits right away, so the notification waits in its own unit.
    script = (
        "a=$(notify-send --app-name=meetrec --icon=document-new --expire-time=60000 "
        '--action=open="Open transcript" "Transcript ready" "$(basename "$1")"); '
        '[ "$a" = open ] && xdg-open "$1/transcript.md"'
    )
    subprocess.run(
        [
            "systemd-run",
            "--user",
            "--collect",
            "--quiet",
            "sh",
            "-c",
            script,
            "sh",
            str(out),
        ],
        check=False,
    )


def process_queue() -> None:
    root = config.root()
    queue = root / ".queue"
    failed = root / ".failed"
    while True:
        items = sorted(queue.iterdir()) if queue.exists() else []
        if not items:
            return
        d = items[0]
        try:
            out = process(d)
            notify_done(out)
        except Exception:
            log.exception("processing %s failed", d)
            failed.mkdir(exist_ok=True)
            d.rename(failed / d.name)
