#!/usr/bin/env python3
"""corpus-grow-suggest.py — propose additions to known-fms.jsonl from a real Phase-1 pass.

After Phase 1 archaeology produces failure_modes/*.md for a real project,
the maintainer wants to know:
  (a) Which Phase-1 FMs are NOT in the corpus? → corpus addition candidates.
  (b) Which corpus FMs were considered but REJECTED by Phase 1? → corpus
      demotion candidates (entries that didn't apply to this project).

This is the manual-curation companion to coverage-gap.py: that script reports
gaps from scorecard data; this one proposes diffs from a single project's
Phase-1 outputs.

Usage:
    corpus-grow-suggest.py --workspace WS --corpus PATH [--out DIFF.md]

Args:
    --workspace WS    workspace dir containing analysis/failure_modes/*.md
    --corpus PATH     path to known-fms.jsonl
    --out PATH        markdown diff (default: stdout)

Output: markdown report with proposed additions and demotions. Maintainer
reviews, picks the right entries, and commits to the corpus by hand.

Exit codes: 0 success, 64 usage, 66 missing input.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


class _UsageExitParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:  # noqa: ANN001
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(64)


def load_corpus(path: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    if not path.is_file():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "fm_id" in rec:
            out[rec["fm_id"]] = rec
    return out


FM_HEADER_RE = re.compile(r"^##\s+(fm-[\w_-]+)\b(.*)")
SEVERITY_RE = re.compile(r"^\*\*severity\*\*:?\s*(P[0-3])", re.IGNORECASE)
SUBSYSTEM_RE = re.compile(r"^\*\*subsystem\*\*:?\s*(\S+)", re.IGNORECASE)


def parse_failure_modes(workspace: Path) -> list[dict]:
    """Walk failure_modes/*.md; extract (fm_id, severity, subsystem, title)."""
    fm_dir = workspace / "analysis" / "failure_modes"
    if not fm_dir.is_dir():
        return []
    out: list[dict] = []
    for md in sorted(fm_dir.glob("*.md")):
        text = md.read_text(encoding="utf-8", errors="replace")
        current: dict | None = None
        for line in text.splitlines():
            m = FM_HEADER_RE.match(line)
            if m:
                if current and current.get("fm_id"):
                    out.append(current)
                title_remainder = m.group(2).strip().lstrip("—-–").strip()
                current = {
                    "fm_id": m.group(1),
                    "subsystem": md.stem,
                    "severity": "P2",
                    "title": title_remainder,
                    "source_file": str(md),
                }
                continue
            if not current:
                continue
            sev_m = SEVERITY_RE.match(line)
            if sev_m:
                current["severity"] = sev_m.group(1).upper()
                continue
            sub_m = SUBSYSTEM_RE.match(line)
            if sub_m:
                current["subsystem"] = sub_m.group(1)
        if current and current.get("fm_id"):
            out.append(current)
    return out


def main() -> int:
    parser = _UsageExitParser(description=__doc__.splitlines()[0])
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    workspace = Path(args.workspace)
    if not workspace.is_dir():
        print(f"corpus-grow-suggest: {workspace} not a directory", file=sys.stderr)
        return 66

    corpus = load_corpus(Path(args.corpus))
    if not corpus:
        print(f"corpus-grow-suggest: corpus at {args.corpus} empty/unreadable",
              file=sys.stderr)
        return 66

    project_fms = parse_failure_modes(workspace)
    if not project_fms:
        print(f"corpus-grow-suggest: no failure_modes/*.md found under {workspace}",
              file=sys.stderr)
        return 66

    # Section A: Phase-1 FMs not in corpus.
    project_fm_ids = {fm["fm_id"] for fm in project_fms}
    additions = [fm for fm in project_fms if fm["fm_id"] not in corpus]
    additions.sort(key=lambda f: ({"P0": 0, "P1": 1, "P2": 2, "P3": 3}.get(f["severity"], 4), f["fm_id"]))

    # Section B: Corpus FMs not in this project's Phase-1 — these MIGHT be
    # demotion candidates if the maintainer concludes the FM is irrelevant
    # for projects of this language. We CANNOT auto-demote: a single project
    # not having an FM doesn't mean the FM is irrelevant. Only flag for review.
    demotions_candidate = []
    project_languages = set()
    # Best-effort: try to derive the project's language from manifest.json.
    manifest_path = workspace / "manifest.json"
    if manifest_path.is_file():
        try:
            project_languages.add(json.loads(manifest_path.read_text()).get("language", "unknown"))
        except (OSError, json.JSONDecodeError):
            pass
    cli_path = workspace / "phase0_cli.json"
    if cli_path.is_file():
        try:
            project_languages.add(json.loads(cli_path.read_text()).get("language", "unknown"))
        except (OSError, json.JSONDecodeError):
            pass
    project_languages.discard("unknown")

    for fm_id, entry in corpus.items():
        if fm_id in project_fm_ids:
            continue
        # Only flag as demotion candidate if the corpus FM CLAIMS this language.
        entry_langs = set(entry.get("languages", []))
        if project_languages and not (entry_langs & project_languages):
            continue
        demotions_candidate.append(entry)

    # Build report.
    lines: list[str] = []
    lines.append("# Corpus Grow / Demote Suggestions")
    lines.append("")
    lines.append(f"- Workspace: `{workspace}`")
    lines.append(f"- Phase-1 FMs found: **{len(project_fms)}**")
    lines.append(f"- Corpus entries: **{len(corpus)}**")
    lines.append(f"- Project language(s) detected: **{', '.join(sorted(project_languages)) or 'unknown'}**")
    lines.append("")
    lines.append(f"## Section A — Project FMs not in corpus ({len(additions)})")
    lines.append("")
    lines.append("Candidates for corpus addition. Maintainer review: which of these are project-specific (skip) vs. likely-recurring (add)?")
    lines.append("")
    if not additions:
        lines.append("_(none — every Phase-1 FM in this project is already in the corpus)_")
    else:
        lines.append("Suggested JSONL entries (paste into `references/corpus/known-fms.jsonl` after review):")
        lines.append("")
        lines.append("```jsonl")
        for fm in additions:
            entry = {
                "fm_id": fm["fm_id"],
                "subsystem": fm["subsystem"],
                "languages": sorted(project_languages) if project_languages else ["unknown"],
                "frequency_across_projects": 1,
                "severity_hint": fm["severity"],
                "example_messages": [fm.get("title", "")],
                "source_projects": [workspace.name.replace(".doctor", "").rstrip("_doctor")],
                "detector_hint": "TODO: review project's repair_specs/<fm_id>.md and lift the detector pseudocode",
                "fixer_hint": "TODO: review project's repair_specs/<fm_id>.md and lift the fixer pseudocode",
            }
            lines.append(json.dumps(entry, ensure_ascii=False))
        lines.append("```")
    lines.append("")
    lines.append(f"## Section B — Corpus FMs not in this project ({len(demotions_candidate)})")
    lines.append("")
    lines.append("Maintainer judgment: was this FM TRULY not applicable, or did Phase-1 archaeology miss it? If 3+ projects across the same language(s) all skip this FM, consider demoting (remove from corpus or narrow `languages`).")
    lines.append("")
    if not demotions_candidate:
        lines.append("_(none — every applicable corpus FM was found in this project)_")
    else:
        lines.append("| fm_id | corpus severity | claimed languages |")
        lines.append("|-------|-----------------|-------------------|")
        for entry in demotions_candidate:
            lines.append(f"| `{entry['fm_id']}` | {entry.get('severity_hint', '?')} | {', '.join(entry.get('languages', []))} |")
    lines.append("")
    lines.append(f"## Verdict")
    lines.append("")
    if additions:
        lines.append(f"- **{len(additions)} candidate addition{'s' if len(additions) != 1 else ''}** — review + curate.")
    if demotions_candidate:
        lines.append(f"- **{len(demotions_candidate)} candidate demotion{'s' if len(demotions_candidate) != 1 else ''}** — review only after seeing this FM skipped in 3+ same-language projects.")
    if not additions and not demotions_candidate:
        lines.append(f"- Corpus is consistent with this project; no action needed.")

    report = "\n".join(lines) + "\n"
    if args.out:
        Path(args.out).write_text(report, encoding="utf-8")
        print(f"corpus-grow-suggest: wrote {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
