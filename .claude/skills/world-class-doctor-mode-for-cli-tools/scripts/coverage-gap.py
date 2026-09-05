#!/usr/bin/env python3
"""coverage-gap.py — cross-correlate the FM corpus against real-project scorecards.

After multiple projects have produced `scorecard_history.jsonl` files (round-55
emission), the maintainer wants to know:
  (a) Which corpus FMs has NO project actually detected? → suspect the FM is
      theoretical, the recipe-level detector is broken, or the corpus entry's
      detector_hint isn't actionable.
  (b) Which FMs do projects detect frequently that are NOT in the corpus? →
      candidates for corpus addition.

Usage:
    coverage-gap.py --corpus PATH --histories DIR [--out REPORT.md]

Args:
    --corpus PATH     path to known-fms.jsonl
    --histories DIR   directory containing per-project scorecard_history.jsonl
                      files (filename: <project>.scorecard_history.jsonl).
                      The script also accepts a directory of project subdirs;
                      for each subdir, looks for .doctor/scorecard_history.jsonl.
    --out PATH        markdown report (default: stdout)

Output:
    Markdown report with two sections:
      ## Corpus FMs with zero detections (N)
      ## Frequent FMs not in corpus (N)

Exit codes: 0 success, 64 usage, 66 missing input.
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path


class _UsageExitParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:  # noqa: ANN001
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(64)


def load_corpus(path: Path) -> dict[str, dict]:
    """Load corpus keyed by fm_id."""
    if not path.is_file():
        return {}
    out: dict[str, dict] = {}
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


def load_history_files(histories_dir: Path) -> list[tuple[str, list[dict]]]:
    """Return [(project_name, [history_records])] for each found history file.

    Looks for either:
      <histories_dir>/<project>.scorecard_history.jsonl   (flat layout), OR
      <histories_dir>/<project>/.doctor/scorecard_history.jsonl   (subdir layout)
    """
    results: list[tuple[str, list[dict]]] = []
    if not histories_dir.is_dir():
        return results
    # Flat layout: *.scorecard_history.jsonl files directly under histories_dir.
    for f in sorted(histories_dir.glob("*.scorecard_history.jsonl")):
        project_name = f.stem.replace(".scorecard_history", "")
        results.append((project_name, _read_jsonl(f)))
    # Subdir layout.
    for d in sorted(histories_dir.iterdir()):
        if not d.is_dir():
            continue
        sub = d / ".doctor" / "scorecard_history.jsonl"
        if sub.is_file():
            results.append((d.name, _read_jsonl(sub)))
    return results


def _read_jsonl(path: Path) -> list[dict]:
    out: list[dict] = []
    try:
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    except OSError:
        pass
    return out


def main() -> int:
    parser = _UsageExitParser(description=__doc__.splitlines()[0])
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--histories", required=True)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    corpus = load_corpus(Path(args.corpus))
    if not corpus:
        print(f"coverage-gap: corpus at {args.corpus} empty or unreadable",
              file=sys.stderr)
        return 66

    histories = load_history_files(Path(args.histories))
    if not histories:
        print(f"coverage-gap: no scorecard_history.jsonl found under "
              f"{args.histories} (looked for *.scorecard_history.jsonl and "
              f"<project>/.doctor/scorecard_history.jsonl)", file=sys.stderr)
        return 66

    # Build the cross-table:
    #   fm_id -> set of projects that ever detected it (had a finding for it).
    # `scorecard_history.jsonl` records aggregate scores per pass, not per-FM
    # findings directly; the FM mapping comes from the per-pass `findings`
    # field if present. Some projects record only aggregates; for those, we
    # can't tell which FMs were detected and they don't contribute to the
    # cross-table (we count them as "no FM detail available").
    detected_by: dict[str, set[str]] = collections.defaultdict(set)
    projects_with_per_fm_data: set[str] = set()
    projects_aggregate_only: set[str] = set()
    for project, records in histories:
        had_per_fm = False
        for rec in records:
            findings = rec.get("findings") or rec.get("fm_findings")
            if not findings:
                continue
            had_per_fm = True
            for finding in findings:
                fm_id = finding.get("id") or finding.get("fm_id")
                if fm_id:
                    detected_by[fm_id].add(project)
        if had_per_fm:
            projects_with_per_fm_data.add(project)
        else:
            projects_aggregate_only.add(project)

    # Section (a): corpus FMs with zero detections.
    zero_detection = []
    for fm_id, entry in corpus.items():
        if fm_id not in detected_by:
            zero_detection.append(entry)
    zero_detection.sort(key=lambda e: (
        {"P0": 0, "P1": 1, "P2": 2, "P3": 3}.get(e.get("severity_hint", "P3"), 4),
        e["fm_id"],
    ))

    # Section (b): FMs detected by ≥ 1 project but NOT in corpus.
    non_corpus = []
    for fm_id, projects in detected_by.items():
        if fm_id in corpus:
            continue
        non_corpus.append({
            "fm_id": fm_id,
            "detected_by_projects": sorted(projects),
            "frequency": len(projects),
        })
    non_corpus.sort(key=lambda e: (-e["frequency"], e["fm_id"]))

    # Build markdown report.
    lines: list[str] = []
    lines.append("# Detector-Coverage Gap Report")
    lines.append("")
    lines.append(f"- Corpus entries: **{len(corpus)}**")
    lines.append(f"- Histories scanned: **{len(histories)}** ({len(projects_with_per_fm_data)} with per-FM detail, {len(projects_aggregate_only)} aggregate-only)")
    lines.append(f"- Distinct FM IDs seen across histories: **{len(detected_by)}**")
    lines.append("")
    lines.append(f"## Section A — Corpus FMs with zero detections ({len(zero_detection)})")
    lines.append("")
    lines.append("These FMs are in the corpus but no scanned project has ever surfaced a finding for them. Possible causes: (i) the FM is theoretical / hasn't manifested yet; (ii) the recipe-level detector is missing or buggy; (iii) the corpus entry's detector_hint is too vague to be actionable.")
    lines.append("")
    if not zero_detection:
        lines.append("_(none — every corpus FM has been detected at least once)_")
    else:
        lines.append("| fm_id | severity | languages | source projects |")
        lines.append("|-------|----------|-----------|-----------------|")
        for e in zero_detection:
            langs = ",".join(e.get("languages", []))
            srcs = ",".join(e.get("source_projects", []))
            lines.append(f"| `{e['fm_id']}` | {e.get('severity_hint','?')} | {langs} | {srcs} |")
    lines.append("")
    lines.append(f"## Section B — Frequently-detected FMs not in corpus ({len(non_corpus)})")
    lines.append("")
    lines.append("These FMs have been detected by ≥ 1 project but are NOT in the corpus. Candidates for corpus addition (especially those detected by ≥ 2 projects).")
    lines.append("")
    if not non_corpus:
        lines.append("_(none — every detected FM is in the corpus)_")
    else:
        lines.append("| fm_id | frequency | detected by |")
        lines.append("|-------|----------:|-------------|")
        for e in non_corpus:
            lines.append(f"| `{e['fm_id']}` | {e['frequency']} | {','.join(e['detected_by_projects'])} |")

    report = "\n".join(lines) + "\n"
    if args.out:
        Path(args.out).write_text(report, encoding="utf-8")
        print(f"coverage-gap: wrote {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
