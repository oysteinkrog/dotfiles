"""Rebuild the local eval corpora.

The corpora are not committed. This repository is public, and the passages come
from a private monorepo's commit messages and documentation and from local
agent session logs. Run this inside the repo you want to calibrate against.

    python evals/build_corpus.py --repo /path/to/repo          # passages.json
    python evals/build_corpus.py --repo . --sessions           # + human_writing.json
    python evals/build_corpus.py --repo . --glossary           # + .plainlang/glossary.txt

`variants.json` and `rule_cases.json` are produced by two agent workflows, not
by this script. Their prompts are recorded in README.md; rerun them against a
fresh `passages.json` to rebuild.
"""

from __future__ import annotations

import argparse
import json
import random
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

COMMON = re.compile(r"\b(the|and|is|to|of|a|in|that|it|for)\b", re.I)


def words(text: str) -> int:
    return len(re.findall(r"[A-Za-z']+", text))


def is_english(text: str) -> bool:
    letters = sum(c.isalpha() for c in text)
    if not letters:
        return False
    ascii_letters = sum(c.isalpha() and ord(c) < 128 for c in text)
    return ascii_letters / letters > 0.95 and len(COMMON.findall(text)) >= 8


def from_commits(repo: Path, limit: int = 4000) -> list[dict]:
    out = []
    proc = subprocess.run(
        ["git", "-C", str(repo), "log", "--all", f"-{limit}", "--pretty=format:%H\x01%ai\x01%B\x02"],
        capture_output=True, text=True, errors="replace",
    )
    for record in proc.stdout.split("\x02"):
        parts = record.strip().split("\x01")
        if len(parts) < 3:
            continue
        sha, _date, body = parts[0], parts[1], parts[2]
        lines = body.strip().split("\n")
        subject = lines[0] if lines else ""
        rest = "\n".join(
            line for line in lines[1:]
            if not re.match(r"^(Co-Authored-By|Fixes|Signed-off-by|Refs|Closes|Generated with)", line.strip())
        ).strip()
        if 350 < len(rest) < 1200:
            out.append({"src": f"commit:{sha[:8]}", "text": f"{subject}\n\n{rest}"})
    return out


def from_docs(repo: Path) -> list[dict]:
    out = []
    for path in list((repo / "docs").rglob("*.md")) + list(repo.glob("*.md")):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        text = re.sub(r"```.*?```", "", text, flags=re.S)
        for block in re.split(r"\n\s*\n", text):
            b = block.strip()
            if 400 < len(b) < 1400 and b.count("\n") < 14 and not b.startswith(("|", "#", "-", "*", ">")):
                out.append({"src": f"docs:{path.relative_to(repo)}", "text": b})
    return out


def build_passages(repo: Path, out_path: Path, n: int = 96, seed: int = 7) -> None:
    random.seed(seed)
    docs = [p for p in from_docs(repo) if is_english(p["text"])]
    commits = [p for p in from_commits(repo) if is_english(p["text"])]
    random.shuffle(docs)
    random.shuffle(commits)
    sample = docs[: n // 2] + commits[: n // 2]
    random.shuffle(sample)
    sample = [p for p in sample if 40 <= words(p["text"]) <= 260][:n]
    for i, p in enumerate(sample):
        p["id"] = f"P{i:03d}"
        p["words"] = words(p["text"])
    out_path.write_text(json.dumps(sample, indent=1), encoding="utf-8")
    print(f"{len(sample)} passages -> {out_path}")


INJECTED = re.compile(
    r"(Another Claude session|Stop hook feedback|<teammate-message|<system-reminder|<local-command|"
    r"\[Request interrupted|<command-name>|tool_use_id|Caveat:|A session-scoped Stop hook|task-notification)", re.I)
AGENTY = re.compile(
    r"(?:^|\n)\s*(?:You are|You have|Your task|FIRST |Read the|TASK:|DELIVERABLE|Return |Deliverable|"
    r"Rules:|Constraints:|Adversarially|Independently verify|Verify |Audit |Review the|For every|"
    r"Report:|Goal:|Scope:|Context:|Do NOT|IMPORTANT:)", re.M)
INFORMAL = re.compile(
    r"\b(?:dont|doesnt|cant|wont|isnt|didnt|couldnt|shouldnt|lets|im|ive|thats|whats|pls|tbh|imo|"
    r"afaik|prob|btw|okay|yeah|yep|nope|hmm)\b|\bi \b", re.I)


def build_human(sessions: Path, out_path: Path, n: int = 150, seed: int = 23) -> None:
    """Messages the user typed, as a false-alarm diagnostic."""
    random.seed(seed)
    kept: list[dict] = []
    files = sorted(sessions.rglob("*.jsonl"))
    random.shuffle(files)
    for f in files[:4000]:
        try:
            with f.open(encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if '"user"' not in line:
                        continue
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    if d.get("type") != "user" or not isinstance(d.get("message"), dict):
                        continue
                    c = d["message"].get("content")
                    if isinstance(c, list):
                        c = " ".join(p.get("text", "") for p in c
                                     if isinstance(p, dict) and p.get("type") == "text")
                    if not isinstance(c, str):
                        continue
                    c = c.strip()
                    if not (40 <= words(c) <= 400) or "```" in c:
                        continue
                    if AGENTY.search(c) or INJECTED.search(c) or re.match(r"\s*[\{\[<#]", c):
                        continue
                    if not is_english(c):
                        continue
                    if not (INFORMAL.search(c) or c.lstrip()[:1].islower()):
                        continue
                    kept.append({"text": c, "src": "user-message"})
        except Exception:
            continue
        if len(kept) > 3000:
            break
    random.shuffle(kept)
    rows = [{"id": f"H{i:03d}", **k} for i, k in enumerate(kept[:n])]
    out_path.write_text(json.dumps(rows, indent=1), encoding="utf-8")
    print(f"{len(rows)} human passages -> {out_path}")


def build_glossary(repo: Path, out_path: Path, min_count: int = 60, max_zipf: float = 3.3) -> None:
    """Domain terms: frequent in this repo's own docs, rare in general English."""
    import gzip

    lex: dict[str, float] = {}
    lex_path = ROOT / "data" / "lexicon.tsv.gz"
    with gzip.open(lex_path, "rt", encoding="utf-8") as fh:
        next(fh)
        for line in fh:
            parts = line.split("\t")
            if len(parts) >= 2 and parts[1]:
                try:
                    lex[parts[0]] = float(parts[1])
                except ValueError:
                    pass

    simpler = set()
    sp = ROOT / "data" / "simpler.tsv"
    if sp.exists():
        for line in sp.read_text(encoding="utf-8").splitlines():
            if line.strip() and not line.startswith("#") and "\t" in line:
                simpler.add(line.split("\t")[0].strip().lower())

    counts: Counter[str] = Counter()
    folders = ["docs", "foundation", "knowledge-base", "src"]
    for folder in folders:
        for path in (repo / folder).rglob("*.md") if (repo / folder).exists() else []:
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            text = re.sub(r"```.*?```", "", text, flags=re.S)
            text = re.sub(r"`[^`\n]+`", " ", text)
            text = re.sub(r"https?://\S+", " ", text)
            for w in re.findall(r"(?<![\w./-])[A-Za-z]{3,}(?![\w/-])", text):
                counts[w.lower()] += 1

    keep = sorted(
        w for w, c in counts.items()
        if c >= min_count and w not in simpler and (lex.get(w) is None or lex[w] < max_zipf)
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        "# Domain terms for this repo. Words that appear at least "
        f"{min_count} times in its docs and have a Zipf frequency below {max_zipf}.\n"
        "# Regenerate with: python evals/build_corpus.py --repo . --glossary\n"
        + "\n".join(keep) + "\n",
        encoding="utf-8",
    )
    print(f"{len(keep)} domain terms -> {out_path}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", type=Path, required=True)
    ap.add_argument("--sessions", nargs="?", const=Path.home() / ".claude/projects", type=Path, default=None)
    ap.add_argument("--glossary", action="store_true")
    ap.add_argument("--out", type=Path, default=HERE / "data")
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    build_passages(args.repo, args.out / "passages.json")
    if args.sessions:
        build_human(args.sessions, args.out / "human_writing.json")
    if args.glossary:
        build_glossary(args.repo, args.repo / ".plainlang" / "glossary.txt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
