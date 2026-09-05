#!/usr/bin/env python3
"""
scorecard.py — language-agnostic scorecard generator for the doctor skill.

Reads .doctor/runs/<id>/scorecard.json (per-run) plus the workspace's
failure_mode_scores.jsonl (per-FM × per-dimension) and emits aggregate
artifacts: scorecard.md, heatmap.svg, scorecard_history.jsonl line.

Subcommands:

    scorecard.py render <workspace>
        Render scorecard.md + heatmap.svg from failure_mode_scores.jsonl.

    scorecard.py compare-against-baseline <new.json> <baseline.json> \
            --max-regression-points=50
        Compare two scorecards. Exit 0 if no regression > N points.
        Used by CI.

    scorecard.py append-history <run-dir> <history-jsonl>
        Append a one-line summary of a run to scorecard_history.jsonl.

    scorecard.py validate <workspace>
        Reject scorecards with >= 700 scores lacking evidence; reject
        unacknowledged regression blocks emitted by diff-scorecards.py.

stdin/stdout discipline: stdout is data only; diagnostic output goes to
stderr. Exit codes: 0 success, 1 regression detected (compare-against-baseline),
2 validation failure (validate), 64 usage error, 74 I/O or bad run artifact
(append-history).
"""

import argparse
import json
import math
import os
import statistics
import sys
from pathlib import Path
from collections import defaultdict
from html import escape


DIMENSIONS = [
    "agent_intuitiveness",
    "agent_ergonomics",
    "automation_degree",
    "data_safety",
    "idempotence",
    "reversibility",
    "diagnostic_specificity",
    "blast_radius_containment",
    "observability",
    "test_coverage_of_repair",
]

DIMENSION_ALIASES = {
    # Historical agent-ergonomics names. Normalize them so older score rows and
    # prompts still feed the ten canonical dimensions instead of disappearing
    # from the rendered table / heatmap.
    "output_parseability": "agent_ergonomics",
    "self_documentation": "diagnostic_specificity",
    "error_pedagogy": "diagnostic_specificity",
    "agent_ease_of_use": "agent_ergonomics",
    "intent_inference": "agent_intuitiveness",
    "safety_with_recovery": "blast_radius_containment",
    "determinism_and_reproducibility": "idempotence",
    "composability": "automation_degree",
    "regression_resistance": "test_coverage_of_repair",
}

FREQUENCY_LABELS = {
    "rare": 0.5,
    "occasional": 1.0,
    "often": 2.0,
}

BLAST_RADIUS_LABELS = {
    "cosmetic": 0.25,
    "nuisance": 0.5,
    "degrades_correctness": 1.0,
    "corrupts_state": 2.0,
    "loses_data": 4.0,
}
# NOTE: per IO-CONTRACTS.md and scorecard-generator's prompt, BOTH frequency
# AND blast_radius are clamped to [0.5, 2.0] before weighting. This is
# intentional: the rubric weights ALL bad outcomes roughly equally for the
# aggregate, so a single P0 catastrophe doesn't dominate. Consequence:
# `cosmetic` (0.25) clamps up to 0.5 (same as `nuisance`) and `loses_data`
# (4.0) clamps down to 2.0 (same as `corrupts_state`). The labels are still
# expressive INPUTS for documentation, but their post-clamp weight is
# identical at the extremes. If you want differentiated extreme labels in
# the aggregate, widen the clamp bounds in clamp() AND update the contract
# in IO-CONTRACTS.md + scorecard-generator.md in lock-step. (Audit #2.)


def clamp(value, lo=0.5, hi=2.0):
    return max(lo, min(hi, value))


def normalize_dimension(dimension):
    return DIMENSION_ALIASES.get(dimension, dimension)


def coerce_factor(value, labels, default=1.0):
    if value is None:
        return default
    if isinstance(value, str):
        text = value.strip()
        if text in labels:
            return labels[text]
        try:
            return float(text)
        except ValueError:
            return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def aggregate_score(fm_medians, weights_by_fm):
    if not fm_medians:
        return 0, 0, {}

    normalized_weights = {}
    weighted_total = 0.0
    weight_total = 0.0
    for fm_id, median in fm_medians.items():
        weights = weights_by_fm.get(fm_id, {})
        frequency = clamp(coerce_factor(weights.get("frequency"), FREQUENCY_LABELS))
        blast_radius = clamp(coerce_factor(weights.get("blast_radius"), BLAST_RADIUS_LABELS))
        weight = frequency * blast_radius
        normalized_weights[fm_id] = {
            "frequency": frequency,
            "blast_radius": blast_radius,
            "weight": weight,
        }
        weighted_total += median * weight
        weight_total += weight

    aggregate = int(round(weighted_total / weight_total)) if weight_total else 0
    # Use round() not int() — int() truncates, so a median of 749.5 becomes
    # 749 and drops below the "≥700 needs evidence" gate when re-aggregated
    # (and agg/median are off-by-one vs each other). Audit finding #5.
    median_per_fm = int(round(statistics.median(fm_medians.values())))
    return aggregate, median_per_fm, normalized_weights


def read_jsonl(path):
    with open(path, encoding="utf-8") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as exc:
                print(f"error: {path}:{lineno}: invalid JSON — {exc}", file=sys.stderr)
                sys.exit(2)


def render(workspace: Path):
    scores_path = workspace / "failure_mode_scores.jsonl"
    if not scores_path.exists():
        print(f"error: {scores_path} not found", file=sys.stderr)
        sys.exit(2)

    scores_by_fm = defaultdict(dict)  # fm_id -> {dimension -> score}
    evidence_by_fm = defaultdict(dict)
    weights_by_fm = defaultdict(dict)
    for row in read_jsonl(scores_path):
        fm_id = row["fm_id"]
        dimension = normalize_dimension(row["dimension"])
        if dimension not in DIMENSIONS:
            print(f"error: unknown scorecard dimension {row['dimension']!r}", file=sys.stderr)
            sys.exit(2)
        scores_by_fm[fm_id][dimension] = row["score"]
        evidence_by_fm[fm_id][dimension] = (
            row.get("evidence_path"),
            row.get("evidence_line_or_test"),
        )
        if "frequency" in row:
            weights_by_fm[fm_id]["frequency"] = row["frequency"]
        if "blast_radius" in row:
            weights_by_fm[fm_id]["blast_radius"] = row["blast_radius"]

    fm_medians = {
        fm_id: int(round(statistics.median(dim_scores.values())))
        for fm_id, dim_scores in scores_by_fm.items()
    }
    aggregate, median_per_fm, normalized_weights = aggregate_score(
        fm_medians, weights_by_fm
    )

    out = workspace / "scorecard.md"
    with open(out, "w", encoding="utf-8") as f:
        f.write("# Doctor Scorecard\n\n")
        f.write(
            f"**Aggregate score (frequency x blast-radius weighted):** "
            f"`{aggregate}`\n\n"
        )
        f.write(f"**Median per-FM score:** `{median_per_fm}`\n\n")
        f.write("**Per-FM medians (sorted descending):**\n\n")
        f.write("| FM | Median | Weight | " + " | ".join(DIMENSIONS) + " |\n")
        f.write("|" + "---|" * (3 + len(DIMENSIONS)) + "\n")
        for fm_id in sorted(fm_medians, key=lambda k: -fm_medians[k]):
            weight = normalized_weights.get(fm_id, {}).get("weight", 1.0)
            row = [fm_id, str(fm_medians[fm_id]), f"{weight:.2f}"]
            for d in DIMENSIONS:
                row.append(str(scores_by_fm[fm_id].get(d, "-")))
            f.write("| " + " | ".join(row) + " |\n")

    pass_n = guess_pass_number(workspace)
    pass_path = workspace / f"scorecard_pass_{pass_n}.md"
    pass_path.write_text(out.read_text(encoding="utf-8"), encoding="utf-8")

    render_heatmap_svg(workspace, scores_by_fm, fm_medians)

    print(f"wrote {out}", file=sys.stderr)
    print(f"wrote {pass_path}", file=sys.stderr)
    print(f"aggregate: {aggregate}", file=sys.stderr)

    print(json.dumps({
        "schema_version": "1.0",
        "aggregate_score": aggregate,
        "aggregate": {
            "score": aggregate,
            "median_per_fm": median_per_fm,
            "weight_method": "frequency_x_blast_radius",
        },
        "per_fm_medians": fm_medians,
        "per_fm_weights": normalized_weights,
        "fm_count": len(fm_medians),
        "scorecard_md_path": str(out),
        "heatmap_svg_path": str(workspace / "heatmap.svg"),
    }, indent=2))


def render_heatmap_svg(workspace, scores_by_fm, fm_medians):
    fm_ids = sorted(fm_medians, key=lambda k: -fm_medians[k])
    n_fm = len(fm_ids)
    n_dim = len(DIMENSIONS)
    cell_w, cell_h = 70, 28
    label_w = 280
    label_h = 110
    width = label_w + n_dim * cell_w + 20
    height = label_h + n_fm * cell_h + 20

    out = []
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" '
               f'width="{width}" height="{height}" '
               f'font-family="monospace" font-size="11">')
    out.append(f'<rect width="{width}" height="{height}" fill="#ffffff"/>')

    for j, dim in enumerate(DIMENSIONS):
        x = label_w + j * cell_w + cell_w / 2
        y = label_h - 6
        out.append(f'<text x="{x}" y="{y}" text-anchor="end" '
                   f'transform="rotate(-50 {x} {y})">{escape(str(dim))}</text>')

    for i, fm in enumerate(fm_ids):
        y = label_h + i * cell_h
        out.append(f'<text x="{label_w - 8}" y="{y + cell_h / 2 + 4}" '
                   f'text-anchor="end">{escape(str(fm))}</text>')
        for j, dim in enumerate(DIMENSIONS):
            x = label_w + j * cell_w
            score = scores_by_fm[fm].get(dim, 0)
            color = score_to_color(score)
            out.append(f'<rect x="{x}" y="{y}" width="{cell_w - 1}" '
                       f'height="{cell_h - 1}" fill="{color}"/>')
            out.append(f'<text x="{x + cell_w / 2}" y="{y + cell_h / 2 + 4}" '
                       f'text-anchor="middle" fill="#222">{score}</text>')

    out.append('</svg>')
    (workspace / "heatmap.svg").write_text("\n".join(out))


def score_to_color(score):
    # 0 = red, 500 = yellow, 1000 = green
    if score is None:
        return "#cccccc"
    pct = max(0, min(1000, score)) / 1000.0
    if pct < 0.5:
        # red -> yellow
        r, g, b = 220, int(60 + (220 - 60) * (pct * 2)), 60
    else:
        # yellow -> green
        r, g, b = int(220 - (220 - 60) * ((pct - 0.5) * 2)), 220, 60
    return f"#{r:02x}{g:02x}{b:02x}"


def guess_pass_number(workspace):
    manifest = workspace / "manifest.json"
    if manifest.exists():
        try:
            return json.loads(manifest.read_text(encoding="utf-8")).get("pass", 1)
        except (OSError, json.JSONDecodeError, TypeError):
            return 1
    return 1


def compare_against_baseline(new_path, baseline_path, max_regression_points):
    try:
        new = json.loads(Path(new_path).read_text(encoding="utf-8"))
        base = json.loads(Path(baseline_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"error: cannot read scorecard JSON for comparison: {exc}", file=sys.stderr)
        sys.exit(2)

    regressions = []
    new_per_fm = new.get("per_fm_medians", {})
    base_per_fm = base.get("per_fm_medians", {})

    for fm_id, base_score in base_per_fm.items():
        new_score = new_per_fm.get(fm_id, 0)
        delta = new_score - base_score
        if delta < -max_regression_points:
            regressions.append({
                "fm_id": fm_id,
                "baseline_score": base_score,
                "new_score": new_score,
                "delta": delta,
            })

    print(json.dumps({
        "schema_version": "1.0",
        "regressions": regressions,
        "max_regression_points": max_regression_points,
        "ok": len(regressions) == 0,
    }, indent=2))

    if regressions:
        print(f"REGRESSION: {len(regressions)} FM(s) dropped > {max_regression_points} pts",
              file=sys.stderr)
        sys.exit(1)


def append_history(run_dir, history_jsonl):
    run_dir = Path(run_dir)
    history_jsonl = Path(history_jsonl)

    report_path = run_dir / "report.json"
    scorecard_path = run_dir / "scorecard.json"
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
        scorecard = json.loads(scorecard_path.read_text(encoding="utf-8")) if scorecard_path.exists() else {}
    except (OSError, json.JSONDecodeError) as exc:
        print(f"error: cannot read run artifact for history append: {exc}", file=sys.stderr)
        sys.exit(74)
    summary = report.get("summary") or {}

    entry = {
        "run_id": report.get("run_id"),
        "started_at": report.get("started_at"),
        "tool_version": report.get("tool_version"),
        "doctor_version": report.get("doctor_version"),
        "ok": report.get("ok"),
        "total_findings": summary.get("total_findings", 0),
        "by_severity": summary.get("by_severity", {}),
        "aggregate_score": scorecard.get("aggregate", {}).get("score"),
        "actions_taken": report.get("actions_taken", summary.get("actions_taken", 0)),
        "duration_ms": report.get("duration_ms", summary.get("duration_ms")),
        "health_p95_ms": report.get("health_p95_ms", summary.get("health_p95_ms")),
        "panics_caught": report.get("panics_caught", summary.get("panics_caught", 0)),
    }

    try:
        with open(history_jsonl, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, separators=(",", ":")) + "\n")
            f.flush()
            os.fsync(f.fileno())
    except OSError as exc:
        print(f"error: cannot append history line to {history_jsonl}: {exc}", file=sys.stderr)
        sys.exit(74)

    print(f"appended history line to {history_jsonl}", file=sys.stderr)


def validate(workspace):
    workspace = Path(workspace)
    scores_path = workspace / "failure_mode_scores.jsonl"
    if not scores_path.exists():
        print(f"error: {scores_path} not found", file=sys.stderr)
        sys.exit(2)

    violations = []
    for row in read_jsonl(scores_path):
        dimension = normalize_dimension(row["dimension"])
        if dimension not in DIMENSIONS:
            violations.append(f"{row['fm_id']}::{row['dimension']} is not a known dimension")
        # Score must be in [0, 1000] per the rubric. Out-of-range scores
        # poison medians and the SVG color ramp, and produce nonsense
        # comparisons in compare-against-baseline. The IO-CONTRACTS row
        # format implies 0–1000 but prior validate only checked the
        # ≥700-needs-evidence rule. (Audit found scorecard.py #1.)
        score_val = row.get("score")
        if (
            isinstance(score_val, bool)
            or not isinstance(score_val, (int, float))
            or not math.isfinite(score_val)
        ):
            violations.append(
                f"{row['fm_id']}::{dimension} score must be a finite number, got {score_val!r}"
            )
        elif score_val < 0 or score_val > 1000:
            violations.append(
                f"{row['fm_id']}::{dimension}={score_val} is out of range [0, 1000]"
            )
        elif score_val >= 700:
            ev = row.get("evidence_path") or row.get("evidence_line_or_test")
            if not ev:
                violations.append(
                    f"{row['fm_id']}::{dimension}={score_val} lacks evidence"
                )

    regression_alerts = workspace / "regression_alerts.md"
    if regression_alerts.exists():
        # If a regression file is present, every "## REGRESSION: <fm>" block
        # must contain at least one non-placeholder ACK: line. Placeholder
        # literal: "<fill in reason or revert the change>".
        text = regression_alerts.read_text(encoding="utf-8")
        PLACEHOLDER = "<fill in reason or revert the change>"
        if "## REGRESSION: " in text:
            blocks = text.split("## REGRESSION: ")[1:]
            for blk in blocks:
                fm_id = blk.splitlines()[0].strip() if blk else "<unknown>"
                non_placeholder_acks = [
                    line for line in blk.splitlines()
                    if line.strip().startswith("ACK:") and PLACEHOLDER not in line
                ]
                if not non_placeholder_acks:
                    violations.append(
                        f"regression_alerts.md::{fm_id} has no non-placeholder ACK"
                    )

    if violations:
        for v in violations:
            print(f"VIOLATION: {v}", file=sys.stderr)
        sys.exit(2)

    print("validation passed", file=sys.stderr)


class _UsageExitParser(argparse.ArgumentParser):
    """ArgumentParser that exits with the IO-CONTRACTS-mandated code 64
    (usage_error) instead of argparse's default 2 (which the rest of the
    skill reserves for validation failure / regression detection)."""

    def error(self, message):
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(64)


def main():
    p = _UsageExitParser(prog="scorecard.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_r = sub.add_parser("render")
    p_r.add_argument("workspace", type=Path)

    p_c = sub.add_parser("compare-against-baseline")
    p_c.add_argument("new")
    p_c.add_argument("baseline")
    p_c.add_argument("--max-regression-points", type=int, default=50)

    p_a = sub.add_parser("append-history")
    p_a.add_argument("run_dir")
    p_a.add_argument("history_jsonl")

    p_v = sub.add_parser("validate")
    p_v.add_argument("workspace", type=Path)

    args = p.parse_args()
    if args.cmd == "render":
        render(args.workspace)
    elif args.cmd == "compare-against-baseline":
        compare_against_baseline(args.new, args.baseline, args.max_regression_points)
    elif args.cmd == "append-history":
        append_history(args.run_dir, args.history_jsonl)
    elif args.cmd == "validate":
        validate(args.workspace)
    else:
        sys.exit(64)


if __name__ == "__main__":
    main()
