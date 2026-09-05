#!/usr/bin/env python3
"""drift-check.py — Detect quality drift in the audit's own behavior over time.

Symptom of drift: the audit reports "everything is fine" not because the project
is healthy but because the rubric has softened, the scorer has become generous,
or differential auditing is serving stale cached PASSes. We catch this by
trending several signals across the last N passes and flagging any that move
in the "audit getting easier" direction.

Usage:
    drift-check.py <audit-dir> [--window N] [--out drift_check.json]

Signals computed (for each, "DRIFTING" if trend > threshold):
    score_median_trend         per-pass change in median score (▲)
    false_closed_rate_trend    per-pass change in false-closed count (▼)
    theater_blocking_density   theater BLOCKING findings per evidence-cited file (▼)
    convergence_delta          score-delta between consecutive passes (→ 0 too fast?)
    rubric_sha_constancy       did rubric.md hash change? (changes invalidate trend)

A signal "drifts" if its slope across the window crosses the threshold AND the
rubric.md sha256 stayed constant across that window (otherwise the trend is
just rubric tightening, not drift).

Output (stdout JSON, also written to <audit-dir>/<--out> if specified):
    {"window_passes": 8, "rubric_changes_in_window": 0,
     "drift_signals": [
        {"name":"score_median_trend","value":"+22 pts/pass","threshold":"±5","verdict":"DRIFTING"},
        ...
     ],
     "verdict": "DRIFT_DETECTED" | "STABLE" | "INSUFFICIENT_DATA"}

Exit codes:
    0 STABLE or INSUFFICIENT_DATA
    1 DRIFT_DETECTED
    2 usage error / audit-dir not found
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from statistics import median as _stat_median

SCORE_RE = re.compile(r"\*\*Score:\s+(\d+)\s*/\s*1000\*\*", re.M)
STATUS_RE = re.compile(r"\*\*Status \(claimed\):\*\*\s+(\S+)", re.M)


def _load_pass_metrics(pass_dir: Path, threshold: int) -> dict | None:
    """Compute per-pass metrics from the pass's scorecards + theater files."""
    beads_dir = pass_dir / "beads"
    if not beads_dir.is_dir():
        return None

    scores: list[int] = []
    closed_count = 0
    false_closed = 0
    theater_blocking = 0
    theater_files = 0

    for bd in beads_dir.iterdir():
        if not bd.is_dir():
            continue
        sc = bd / "scorecard.md"
        if sc.exists():
            txt = sc.read_text()
            sm = SCORE_RE.search(txt)
            stm = STATUS_RE.search(txt)
            if sm:
                score = int(sm.group(1))
                scores.append(score)
                status = stm.group(1) if stm else "unknown"
                if status == "closed":
                    closed_count += 1
                    if score < threshold:
                        false_closed += 1
        th = bd / "theater.json"
        if th.exists():
            try:
                t = json.loads(th.read_text())
                findings = t.get("findings") or []
                blocking = sum(1 for f in findings if f.get("severity") == "BLOCKING")
                theater_blocking += blocking
                # count distinct evidence files cited (denominator)
                ev = bd / "evidence.json"
                if ev.exists():
                    e = json.loads(ev.read_text())
                    paths = set()
                    for ck in (e.get("checks") or []):
                        for c in (ck.get("citations") or []):
                            p = c.get("path")
                            if p:
                                paths.add(p)
                    theater_files += len(paths)
            except Exception:
                pass

    if not scores:
        return None

    # Score median. Use stdlib `statistics.median` rather than
    # `s_sorted[len(s_sorted)//2]` — the latter only gives the correct
    # median for ODD-length lists; for even-length it returns the upper-
    # middle element (e.g. [1,2,3,4] → 3 instead of 2.5), biasing every
    # even-length pass's recorded `score_median` upward by ~0.5 vs the
    # mathematical median. The `per_pass_metrics` field is consumed by
    # other tools (dashboards, regression tests, manual inspection), so
    # preserve .5 values instead of truncating the precision away.
    s_sorted = sorted(scores)
    median = _stat_median(s_sorted)

    convergence = None
    cf = pass_dir / "convergence.json"
    if cf.exists():
        try:
            c = json.loads(cf.read_text())
            convergence = c.get("criteria", {}).get("max_score_delta_observed")
        except Exception:
            pass

    rubric_sha = None
    mf = pass_dir / "manifest.json"
    if mf.exists():
        try:
            rubric_sha = json.loads(mf.read_text()).get("rubric_sha256")
        except Exception:
            pass

    return {
        "pass": pass_dir.name,
        "score_median": median,
        "score_p10": s_sorted[len(s_sorted) // 10] if len(s_sorted) >= 10 else s_sorted[0],
        "n_beads": len(scores),
        "closed_count": closed_count,
        "false_closed": false_closed,
        "false_closed_rate": (false_closed / closed_count) if closed_count else 0.0,
        "theater_blocking": theater_blocking,
        "theater_files": theater_files,
        "theater_blocking_density": (theater_blocking / theater_files) if theater_files else 0.0,
        "convergence_delta": convergence,
        "rubric_sha": rubric_sha,
    }


def _slope(values: list[float]) -> float:
    """Least-squares slope of `values` against index 0..n-1. Pure stdlib."""
    n = len(values)
    if n < 2:
        return 0.0
    xs = list(range(n))
    mean_x = sum(xs) / n
    mean_y = sum(values) / n
    num = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, values))
    den = sum((x - mean_x) ** 2 for x in xs) or 1
    return num / den


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("audit_dir")
    p.add_argument("--window", type=int, default=8,
                   help="number of most-recent passes to evaluate (default 8)")
    p.add_argument("--threshold", type=int, default=700,
                   help="false-closed score threshold (default 700)")
    p.add_argument("--out", default=None,
                   help="also write drift report to this path inside audit-dir")
    p.add_argument("--score-trend-threshold", type=float, default=5.0,
                   help="score-median trend > this (pts/pass) → DRIFTING (default 5)")
    p.add_argument("--theater-trend-threshold", type=float, default=0.05,
                   help="theater-blocking density drop > this/pass → DRIFTING (default 0.05)")
    args = p.parse_args()

    root = Path(args.audit_dir).resolve()
    if not (root / "passes").is_dir():
        print(f"ERROR: {root} has no passes/ subdirectory", file=sys.stderr)
        return 2

    pass_dirs = sorted(d for d in (root / "passes").iterdir() if d.is_dir())
    if len(pass_dirs) < 2:
        out = {
            "audit_dir": str(root),
            "window_passes": len(pass_dirs),
            "verdict": "INSUFFICIENT_DATA",
            "reason": f"need ≥ 2 passes for trend; found {len(pass_dirs)}",
        }
        print(json.dumps(out, indent=2))
        return 0

    window = pass_dirs[-args.window:]
    metrics = [m for m in (_load_pass_metrics(pd, args.threshold) for pd in window) if m]
    if len(metrics) < 2:
        print(json.dumps({"verdict": "INSUFFICIENT_DATA", "reason": "no pass had parseable scorecards"}, indent=2))
        return 0

    # Rubric constancy gates trend interpretation. If the rubric hash changed
    # within the window, score trends might just reflect the rubric change.
    rubric_shas = {m["rubric_sha"] for m in metrics if m["rubric_sha"]}
    rubric_changes = max(0, len(rubric_shas) - 1)

    score_slope = _slope([m["score_median"] for m in metrics])
    fc_slope = _slope([m["false_closed"] for m in metrics])
    fc_rate_slope = _slope([m["false_closed_rate"] for m in metrics])
    theater_slope = _slope([m["theater_blocking_density"] for m in metrics])

    drift_signals: list[dict] = []

    # Score median climbing without rubric change → drift (audit getting easier)
    drift_signals.append({
        "name": "score_median_trend",
        "value": f"{score_slope:+.1f} pts/pass",
        "threshold": f"+{args.score_trend_threshold}",
        "verdict": "DRIFTING" if (score_slope > args.score_trend_threshold and rubric_changes == 0) else "STABLE",
        "rubric_constant_in_window": rubric_changes == 0,
    })

    # False-closed rate trending DOWN without remediation → drift
    drift_signals.append({
        "name": "false_closed_rate_trend",
        "value": f"{fc_rate_slope:+.4f} /pass",
        "threshold": "≤ -0.02",
        "verdict": "DRIFTING" if (fc_rate_slope < -0.02 and rubric_changes == 0) else "STABLE",
    })

    # Theater BLOCKING density trending DOWN sharply → catalog rotting
    drift_signals.append({
        "name": "theater_blocking_density",
        "value": f"{theater_slope:+.4f} /file/pass",
        "threshold": f"≤ -{args.theater_trend_threshold}",
        "verdict": "DRIFTING" if (theater_slope < -args.theater_trend_threshold and rubric_changes == 0) else "STABLE",
    })

    # Convergence delta should plateau, not keep shrinking — shrinking forever
    # suggests we're converging on a moving target.
    conv_values = [m["convergence_delta"] for m in metrics if isinstance(m["convergence_delta"], (int, float))]
    if len(conv_values) >= 3:
        conv_slope = _slope(conv_values)
        drift_signals.append({
            "name": "convergence_delta_trend",
            "value": f"{conv_slope:+.2f} pts/pass",
            "threshold": "stable",
            "verdict": "DRIFTING" if (conv_slope < -1.0 and rubric_changes == 0) else "STABLE",
        })

    drifting = [s for s in drift_signals if s["verdict"] == "DRIFTING"]
    verdict = "DRIFT_DETECTED" if drifting else "STABLE"

    out = {
        "audit_dir": str(root),
        "window_passes": len(metrics),
        "first_pass": metrics[0]["pass"],
        "last_pass": metrics[-1]["pass"],
        "rubric_changes_in_window": rubric_changes,
        "per_pass_metrics": metrics,
        "drift_signals": drift_signals,
        "verdict": verdict,
        "recommended_action": (
            "run subagents/red-team-adversary.md; consider tightening rubric; "
            "re-baseline with subagents/cass-pattern-miner.md"
            if verdict == "DRIFT_DETECTED" else
            "no action needed; audit appears stable"
        ),
    }

    if args.out:
        out_path = Path(args.audit_dir) / args.out
        out_path.write_text(json.dumps(out, indent=2) + "\n")
        print(f"Wrote {out_path}", file=sys.stderr)
    print(json.dumps(out, indent=2))

    return 1 if verdict == "DRIFT_DETECTED" else 0


if __name__ == "__main__":
    sys.exit(main())
