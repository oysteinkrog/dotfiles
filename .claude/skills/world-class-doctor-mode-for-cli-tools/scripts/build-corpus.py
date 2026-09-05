#!/usr/bin/env python3
"""build-corpus.py — aggregate per-project mine-changelog findings into a
deduplicated cross-project FM corpus.

Run once (and refreshed periodically) by the skill maintainer to produce
`references/corpus/known-fms.jsonl`. Phase 1 archaeology then queries the
corpus via `query-corpus.py --language <lang>` to get a seed list of FMs
likely to apply to a new project.

Input: a directory containing per-project JSONL files (output of
mine-changelog.py), filename `<project-name>.jsonl`. The corpus generator
also expects a sibling JSON file `<project-name>.meta.json` if available
with `{"language": "..."}`. If absent, language is inferred from the
project name suffix (`*_rust`, `*_go`, `*-go`, `*-rs`) or set to "unknown".

Output: a single JSONL file at the requested path. One line per
deduplicated FM. Schema:
    {"fm_id": "fm-<subsystem>-<slug>",
     "subsystem": "...",
     "languages": ["rust", "go", ...],
     "frequency_across_projects": 3,
     "severity_hint": "P1",
     "example_messages": ["...", "..."],
     "source_projects": ["beads_rust", "xf"]}

Usage:
    build-corpus.py <input-dir> --out <output.jsonl>
                    [--min-frequency N]    keep entries seen in >= N projects (default 1)
                    [--max-examples N]     example messages per entry (default 3)
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path


class _UsageExitParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:  # noqa: ANN001
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(64)


# Heuristic language inference from project directory name when no .meta.json.
LANG_NAME_HINTS = [
    (re.compile(r"_rust$|-rust$|-rs$"), "rust"),
    (re.compile(r"_go$|-go$"), "go"),
    (re.compile(r"_py$|-py$|_python$"), "python"),
    (re.compile(r"_ts$|-ts$|_typescript$"), "typescript"),
    (re.compile(r"_bash$|-bash$|-sh$"), "bash"),
    (re.compile(r"_c$|-c$|_cpp$|-cpp$"), "cpp"),
]


def infer_language(project_name: str) -> str:
    for pattern, lang in LANG_NAME_HINTS:
        if pattern.search(project_name):
            return lang
    return "unknown"


def normalize_for_dedupe(message: str) -> str:
    """Collapse whitespace, lowercase, strip punctuation/links/SHA hashes
    so similar bug-fix messages from different projects map to the same key.
    """
    # Strip markdown links and bare URLs.
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", message)
    text = re.sub(r"https?://\S+", "", text)
    # Strip backticks (`)
    text = text.replace("`", "")
    # Strip git SHAs (8+ hex chars).
    text = re.sub(r"\b[0-9a-f]{7,40}\b", "", text)
    # Strip parenthesized refs (round-NN), (P0), etc.
    text = re.sub(r"\([^)]{0,40}\)", "", text)
    # Collapse whitespace, lowercase.
    text = re.sub(r"\s+", " ", text).lower().strip()
    # Strip trailing punctuation / leading words like "fix" "bug" etc.
    text = re.sub(r"^(fix|bug|patch|repair|recover|resolve|prevent|harden)(\s*:|s|ed|es)?\s+", "", text)
    return text.strip()


def severity_priority(severity: str) -> int:
    return {"P0": 0, "P1": 1, "P2": 2, "P3": 3}.get(severity, 4)


def merge_severity(existing: str, new: str) -> str:
    """Take the more-severe of two hints (P0 wins over P3)."""
    if severity_priority(new) < severity_priority(existing):
        return new
    return existing


def main() -> int:
    parser = _UsageExitParser(description=__doc__.splitlines()[0])
    parser.add_argument("input_dir", help="dir with per-project .jsonl files")
    parser.add_argument("--out", required=True, help="output path")
    parser.add_argument("--min-frequency", type=int, default=1,
                        help="keep entries seen in >= N projects")
    parser.add_argument("--max-examples", type=int, default=3,
                        help="example messages per entry")
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    if not input_dir.is_dir():
        print(f"build-corpus: {input_dir} not a directory", file=sys.stderr)
        return 66

    # Aggregate. Key = (subsystem, normalized-message-prefix).
    # Using a 60-char prefix of the normalized message lets near-identical
    # messages collapse without merging unrelated ones.
    aggregated: dict[tuple[str, str], dict] = {}

    for jsonl_path in sorted(input_dir.glob("*.jsonl")):
        project_name = jsonl_path.stem
        language = infer_language(project_name)
        meta_path = jsonl_path.with_suffix(".meta.json")
        if meta_path.is_file():
            try:
                meta = json.loads(meta_path.read_text())
                language = meta.get("language", language)
            except Exception:
                pass
        try:
            text = jsonl_path.read_text()
        except OSError:
            continue
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            subsystem = rec.get("classified_subsystem", "unknown")
            message = rec.get("message", "")
            severity = rec.get("severity_hint", "P2")
            normalized = normalize_for_dedupe(message)
            if not normalized or len(normalized) < 8:
                continue
            key = (subsystem, normalized[:60])
            entry = aggregated.setdefault(key, {
                "subsystem": subsystem,
                "languages": set(),
                "source_projects": set(),
                "example_messages": [],
                "severity_hint": severity,
                "candidate_fm_id_seed": rec.get("candidate_fm_id", ""),
            })
            entry["languages"].add(language)
            entry["source_projects"].add(project_name)
            if len(entry["example_messages"]) < args.max_examples:
                # Avoid near-duplicate examples from the same project.
                if message not in entry["example_messages"]:
                    entry["example_messages"].append(message)
            entry["severity_hint"] = merge_severity(entry["severity_hint"], severity)

    # Filter by min-frequency, sort by frequency desc.
    filtered = []
    for (subsystem, _), entry in aggregated.items():
        freq = len(entry["source_projects"])
        if freq < args.min_frequency:
            continue
        # Generate a stable fm_id from subsystem + normalized message stem.
        # Re-use the first example's slug-style fm_id when available.
        seed = entry.get("candidate_fm_id_seed") or f"fm-{subsystem}-unknown"
        filtered.append({
            "fm_id": seed,
            "subsystem": subsystem,
            "languages": sorted(entry["languages"]),
            "frequency_across_projects": freq,
            "severity_hint": entry["severity_hint"],
            "example_messages": entry["example_messages"],
            "source_projects": sorted(entry["source_projects"]),
        })

    filtered.sort(key=lambda x: (-x["frequency_across_projects"],
                                 severity_priority(x["severity_hint"]),
                                 x["fm_id"]))

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w") as f:
        for entry in filtered:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    print(f"build-corpus: wrote {len(filtered)} FMs to {out_path}", file=sys.stderr)
    # Also write a stats summary alongside.
    stats = collections.Counter(e["subsystem"] for e in filtered)
    print("build-corpus: by subsystem:", dict(stats), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
