#!/usr/bin/env python3
"""reproducibility-check.py — Verify the audit is deterministic.

Re-runs `score-bead.py` against an existing pass's evidence packs (twice) and
asserts that every per-bead score matches its prior recorded score within a
tight delta. Determinism is a non-negotiable invariant of this skill (Axiom:
"same evidence pack + same rubric → same score across two runs"). This script
proves the invariant on a real audit dir.

Usage:
    reproducibility-check.py <pass-dir> [--max-delta 0]
                              [--rubric <path>]
                              [--report-out <path>]

Exit:
    0 if every bead's re-score == prior (or within --max-delta)
    1 if drift detected
    2 on usage error

A drift indicates one of:
    - score-bead.py is using non-deterministic input (timestamp, random,
      subprocess that returns different output each run)
    - rubric.md was edited between writes (rubric_sha256 mismatch)
    - evidence pack changed since the pass was written

The output --report-out (default stdout) includes per-bead deltas and a
verdict line that can be grepped from CI.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCORE_RE = re.compile(r"\*\*Score:\s+(\d+)\s*/\s*1000\*\*", re.M)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("pass_dir")
    p.add_argument("--max-delta", type=int, default=0,
                   help="acceptable per-bead score delta (default 0 = strict)")
    p.add_argument("--rubric", default=None,
                   help="rubric.md (defaults to pass_dir/../../rubric.md)")
    p.add_argument("--report-out", default=None)
    args = p.parse_args()

    pass_dir = Path(args.pass_dir).resolve()
    if not pass_dir.exists():
        print(f"ERROR: {pass_dir} not found", file=sys.stderr)
        return 2

    rubric_path = Path(args.rubric) if args.rubric else (pass_dir.parent.parent / "rubric.md")
    if not rubric_path.exists():
        print(f"ERROR: rubric not found at {rubric_path}", file=sys.stderr)
        return 2

    skill_scripts = Path(__file__).resolve().parent
    score_bead = skill_scripts / "score-bead.py"
    if not score_bead.exists():
        print(f"ERROR: {score_bead} missing", file=sys.stderr)
        return 2

    beads_dirs = sorted([d for d in (pass_dir / "beads").iterdir() if d.is_dir()])
    if not beads_dirs:
        print(f"ERROR: no beads under {pass_dir}/beads/", file=sys.stderr)
        return 2

    # If the original pass scored against a prior pass (for trend tracking), we
    # must pass the same --prior-pass-dir on re-score; otherwise scores can
    # legitimately differ even when the algorithm is deterministic. Probe by
    # listing sibling pass dirs and picking the one that immediately precedes
    # this one (matches what run-pass.sh does).
    #
    # Guard for users who pass a non-canonical pass_dir (not under
    # <audit-dir>/passes/<UTC>): the parent.parent might not contain a passes/
    # dir, in which case skip the prior-pass detection silently.
    prior_pass_args: list[str] = []
    passes_root = pass_dir.parent.parent / "passes"
    if passes_root.is_dir():
        sibling_passes = sorted(
            d for d in passes_root.iterdir() if d.is_dir() and d.name < pass_dir.name
        )
        if sibling_passes:
            prior_pass_args = ["--prior-pass-dir", str(sibling_passes[-1])]

    drifts: list[dict] = []
    matches = 0

    for bd in beads_dirs:
        prior_card = bd / "scorecard.md"
        prior_score = None
        if prior_card.exists():
            m = SCORE_RE.search(prior_card.read_text())
            if m:
                prior_score = int(m.group(1))

        # Re-score into a temp dir so we don't trample the original artifacts.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_bd = Path(tmp) / bd.name
            shutil.copytree(bd, tmp_bd)
            # Drop the prior scorecard so the re-run computes from scratch.
            (tmp_bd / "scorecard.md").unlink(missing_ok=True)
            try:
                subprocess.run(
                    [sys.executable, str(score_bead), str(tmp_bd),
                     "--rubric", str(rubric_path),
                     "--synthesis", str(pass_dir / "synthesis.md"),
                     *prior_pass_args],
                    check=True, capture_output=True, timeout=60,
                )
            except subprocess.CalledProcessError as e:
                drifts.append({"bead": bd.name, "kind": "rerun_error",
                               "stderr": e.stderr.decode("utf-8", "ignore")[:300]})
                continue
            except subprocess.TimeoutExpired:
                drifts.append({"bead": bd.name, "kind": "timeout"})
                continue

            new_card = tmp_bd / "scorecard.md"
            new_score = None
            if new_card.exists():
                m = SCORE_RE.search(new_card.read_text())
                if m:
                    new_score = int(m.group(1))

        if prior_score is None and new_score is None:
            drifts.append({"bead": bd.name, "kind": "no_score_either_run"})
            continue
        if prior_score is None or new_score is None:
            drifts.append({"bead": bd.name, "kind": "asymmetric_score",
                           "prior": prior_score, "new": new_score})
            continue
        delta = abs(new_score - prior_score)
        if delta > args.max_delta:
            drifts.append({"bead": bd.name, "kind": "score_drift",
                           "prior": prior_score, "new": new_score, "delta": new_score - prior_score})
        else:
            matches += 1

    verdict = "DETERMINISTIC" if not drifts else "DRIFT_DETECTED"
    report = {
        "pass_dir": str(pass_dir),
        "rubric": str(rubric_path),
        "max_delta_allowed": args.max_delta,
        "beads_checked": len(beads_dirs),
        "matches": matches,
        "drifts": drifts,
        "verdict": verdict,
    }

    out = json.dumps(report, indent=2)
    if args.report_out:
        Path(args.report_out).write_text(out + "\n")
        print(f"Wrote {args.report_out}", file=sys.stderr)
    else:
        print(out)

    if drifts:
        print(f"\nVERDICT: {verdict} ({len(drifts)} bead(s) drifted, {matches} matched)", file=sys.stderr)
        return 1
    print(f"\nVERDICT: {verdict} ({matches}/{len(beads_dirs)} beads matched exactly)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
