#!/usr/bin/env python3
"""master-report.py — Phase 8: aggregate per-bead scorecards into REPORT.md.

Usage:
    master-report.py <pass-dir> [--threshold 700] [--prior-pass-dir <path>]

Reads every <pass-dir>/beads/<id>/scorecard.md, extracts the score line, and
produces <pass-dir>/REPORT.md with the executive summary, distribution,
ranked scoreboard, false-closed list, and (if prior-pass-dir given) trends.

Also overwrites <audit-dir>/REPORT.md with the same content and appends one row
per bead per pass to <audit-dir>/trends.md.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from statistics import median


SCORE_RE = re.compile(r"\*\*Score:\s+(\d+)\s*/\s*1000\*\*", re.M)
VERDICT_RE = re.compile(r"\*\*Verdict:\s+(.+?)\*\*", re.M)
STATUS_RE = re.compile(r"\*\*Status \(claimed\):\*\*\s+(\S+)", re.M)
TITLE_RE = re.compile(r"\*\*Title:\*\*\s+(.+)", re.M)
TYPE_RE = re.compile(r"\*\*Type:\*\*\s+(\S+)", re.M)
PRIORITY_RE = re.compile(r"\*\*Priority:\*\*\s+P(\d+)", re.M)


def parse_scorecard(path: Path) -> dict:
    txt = path.read_text()
    bead_id = path.parent.name
    score_m = SCORE_RE.search(txt)
    verdict_m = VERDICT_RE.search(txt)
    status_m = STATUS_RE.search(txt)
    title_m = TITLE_RE.search(txt)
    type_m = TYPE_RE.search(txt)
    pri_m = PRIORITY_RE.search(txt)
    return {
        "bead_id": bead_id,
        "score": int(score_m.group(1)) if score_m else 0,
        "verdict": verdict_m.group(1).strip() if verdict_m else "unknown",
        "status": status_m.group(1) if status_m else "unknown",
        "title": title_m.group(1).strip() if title_m else "",
        "type": type_m.group(1) if type_m else "task",
        "priority": int(pri_m.group(1)) if pri_m else 2,
        "scorecard_path": str(path),
    }


def parse_prior(prior_pass_dir: Path) -> dict[str, int]:
    """Map prior-pass bead_id → score, only for scorecards we actually parsed.

    parse_scorecard() returns `score: 0` when SCORE_RE doesn't match — which
    is indistinguishable from a genuine 0/1000 (Theater band) score. If we
    blindly include those, the Trends table renders confusing `prior: 0 →
    now: N` rows for beads whose prior scorecard was unparseable rather than
    actually scored 0. Re-check the regex on the file content and skip any
    bead whose score couldn't be derived.
    """
    out: dict[str, int] = {}
    if not prior_pass_dir or not prior_pass_dir.exists():
        return out
    for sc in (prior_pass_dir / "beads").glob("*/scorecard.md"):
        if not SCORE_RE.search(sc.read_text()):
            continue  # unparseable; omit rather than report misleading 0
        d = parse_scorecard(sc)
        out[d["bead_id"]] = d["score"]
    return out


# Canonical band ordering (best → worst). MUST stay in sync with
# `score-bead.py::VERDICT_BANDS` — those labels are emitted into each
# scorecard.md via `**Verdict: <label>**` and parsed back here via
# `VERDICT_RE`. If a band label drifts there but not here, the renderer
# below will still surface the drifted band (under "Other / unrecognized")
# instead of silently dropping it from the Distribution table.
CANONICAL_BANDS = [
    "🟢 Verified",
    "🟢 Substantially complete",
    "🟡 Partial",
    "🟠 False-closed (mild)",
    "🔴 False-closed (severe)",
    "🚨 Theater",
]


def _esc_md_cell(s: str) -> str:
    """Escape characters that would break a markdown table row.

    A literal `|` in a cell splits the row into more columns than the header
    declared, shifting every subsequent column right and visually corrupting
    the table for human readers AND breaking downstream regex parsers (e.g.
    remediate.sh that grep-extracts bead IDs from REPORT.md). Bead titles
    routinely contain `|` (e.g. `refactor: split foo | bar`).
    """
    return s.replace("|", "\\|")


def _fmt_number(value) -> str:
    return f"{value:g}"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("pass_dir")
    p.add_argument("--threshold", type=int, default=700)
    p.add_argument("--prior-pass-dir", default=None)
    args = p.parse_args()

    pass_dir = Path(args.pass_dir)
    audit_dir = pass_dir.parent.parent
    scorecards = sorted((pass_dir / "beads").glob("*/scorecard.md"))
    if not scorecards:
        print("ERROR: no scorecards found", file=sys.stderr)
        return 2

    rows = [parse_scorecard(sc) for sc in scorecards]
    prior = parse_prior(Path(args.prior_pass_dir)) if args.prior_pass_dir else {}

    rows.sort(key=lambda r: r["score"])
    scores = [r["score"] for r in rows]
    false_closed = [r for r in rows if r["status"] == "closed" and r["score"] < args.threshold]
    false_closed.sort(key=lambda r: (r["priority"], r["score"]))

    band_counts: dict[str, int] = {}
    for r in rows:
        band_counts[r["verdict"]] = band_counts.get(r["verdict"], 0) + 1

    # Detect deterministic-only mode by scanning Phase 4 / Phase 6 packs for
    # the stub signals that score-bead.py also recognizes. If the majority of
    # beads were scored against stub Phase-4/6 packs, the resulting "false-
    # closed" rate is misleading — surface that prominently at the top of the
    # report so first-time users don't act on a coverage-gap report as if
    # it were a real implementation verdict.
    #
    # Stub signals (must stay in sync with score-bead.py::is_stub_pack):
    #   1. executor / auditor name in STUB_EXECUTORS
    #   2. `stub_reason` field present
    #   3. pack file missing entirely
    stub_compliance_count = 0
    stub_test_depth_count = 0
    real_compliance_count = 0
    real_test_depth_count = 0
    stub_executors = {"stub-wrapper", "single-bead-stub"}

    def _looks_like_stub(pack: dict) -> bool:
        if not isinstance(pack, dict):
            return False
        if str(pack.get("executor") or pack.get("auditor") or "") in stub_executors:
            return True
        if pack.get("stub_reason"):
            return True
        if not pack:  # empty dict — pack effectively missing
            return True
        return False

    for sc in scorecards:
        bead_dir = sc.parent
        co_path = bead_dir / "compliance.json"
        td_path = bead_dir / "test_depth.json"
        # Missing-file is itself a stub signal — count it on the stub side.
        if not co_path.exists():
            stub_compliance_count += 1
        else:
            try:
                co = json.loads(co_path.read_text())
                if _looks_like_stub(co):
                    stub_compliance_count += 1
                else:
                    real_compliance_count += 1
            except Exception:
                # Malformed JSON: count as "real" so we don't hide a parse error
                # behind the deterministic-only banner. (validate-evidence.py
                # surfaces malformed packs separately.)
                real_compliance_count += 1
        if not td_path.exists():
            stub_test_depth_count += 1
        else:
            try:
                td = json.loads(td_path.read_text())
                if _looks_like_stub(td):
                    stub_test_depth_count += 1
                else:
                    real_test_depth_count += 1
            except Exception:
                real_test_depth_count += 1
    deterministic_only = (
        stub_compliance_count + stub_test_depth_count
    ) > (real_compliance_count + real_test_depth_count)

    md: list[str] = []
    md.append(f"# Beads Compliance Audit — Master Report\n")
    md.append(f"Pass: `{pass_dir.name}`  |  Beads audited: {len(rows)}  |  Threshold: {args.threshold}\n")
    if deterministic_only:
        md.append(
            "> ⚠ **DETERMINISTIC-ONLY PASS — read carefully before acting on this report.**\n"
            f"> Phase 4 (Required tests) ran in stub mode for {stub_compliance_count} of "
            f"{stub_compliance_count + real_compliance_count} beads, and Phase 6 (Test depth) "
            f"ran in stub mode for {stub_test_depth_count} of "
            f"{stub_test_depth_count + real_test_depth_count} beads. The scorer awards FULL "
            "credit (WAIVED) for stub-mode dimensions, so the scores below are an **UPPER BOUND** "
            "on real completion — false-closed verdicts here may be artifacts of incomplete "
            "Phase 3 evidence extraction rather than implementation theater. **Do NOT reopen "
            "beads or create completion-debt based on this report alone.** Re-run with the real "
            "compliance-verifier and test-depth-auditor subagents wired in for definitive "
            "verdicts (see `references/PHASES.md`).\n"
        )

    # Executive summary
    md.append("## Executive summary (paste-ready)\n")
    closed_count = sum(1 for r in rows if r["status"] == "closed")
    fc_pct = (len(false_closed) * 100 // closed_count) if closed_count else 0
    # v1.2 calibration framing. Across prior real-world runs, the deterministic-
    # only headline overstated true false-closed by ~10–20× (15/15 of the
    # lowest-scoring beads in one cohort were SCORE false positives). The fix
    # has two parts: (1) keep the canonical "X total / Y false-closed" line
    # exactly as before — fixtures, validate-evidence.py, and the SELF-TEST
    # smoke test all match against it verbatim — and (2) add a SEPARATE
    # calibration bullet for deterministic-only passes with ≥ 5 flags that
    # tells the reader to plan for ~10–25% of the flag count, not all of it.
    # The two-line shape is intentional: the canonical line keeps tooling
    # happy; the calibration bullet keeps humans calibrated.
    md.append(
        f"- **{len(rows)}** total beads audited; **{len(false_closed)}** false-closed "
        f"(status=closed, score<{args.threshold}) — **{fc_pct}%** of all closed beads "
        f"(of {closed_count} total closed)."
    )
    # Calibration prior — only meaningful when the flag count is large enough
    # for "85–95% are pipeline artifacts" to be a useful frame. Below ~5 flags
    # the prior collapses to noise (e.g. "plan for 1 of 1" reads as nonsense).
    if deterministic_only and len(false_closed) >= 5:
        low = max(1, len(false_closed) // 10)   # ~10% of flags
        high = max(low + 1, len(false_closed) // 4)  # ~25% of flags
        md.append(
            f"- **Calibration framing (deterministic-only).** Across prior real-world "
            f"runs of this skill, ~85–95% of deterministic-baseline flags were SCORE "
            f"false positives — real code, real tests, real fixes shipped, but the "
            f"deterministic extractor / theater scanner couldn't see them without a "
            f"Phase-4 LLM in the loop. **Plan for ~{low}–{high} true false-closed "
            f"beads, NOT all {len(false_closed)}.** Run "
            f"`scripts/calibrate-bottom-n.sh` to confirm before recommending reopens."
        )
    if false_closed:
        worst = false_closed[0]
        md.append(f"- Worst offender: **{worst['bead_id']}** (score {worst['score']}/1000) — {worst['title']}")
    if scores:
        best = max(rows, key=lambda r: r["score"])
        md.append(f"- Best in class: **{best['bead_id']}** (score {best['score']}/1000) — {best['title']}")
        md.append(f"- Score median: **{_fmt_number(median(scores))}**, mean: **{int(sum(scores)/len(scores))}**.")
    # Always-on calibration recommendation. The original report only printed
    # this advice in the deterministic-only branch, which meant the full-
    # pipeline report dove straight into "reopen the N false-closed beads"
    # without any spot-check guidance. Spot-checking the bottom-N before
    # acting is the SINGLE most effective practice for catching pipeline
    # artifacts before they land in remediation. Recommend it always.
    if false_closed:
        sample_n = max(5, min(10, len(false_closed)))
        md.append(
            f"- **Calibration check (before acting):** spot-verify the {sample_n} "
            f"lowest-scoring beads against the real codebase. Run "
            f"`scripts/calibrate-bottom-n.sh <project> <pass-dir> --n {sample_n}` "
            f"or have an LLM gatherer ground-truth them. Prior runs found ≥80% "
            f"of low-score beads were FALSE positives — burn 5 minutes calibrating "
            f"before recommending reopens/completion-debt. The `Missing items` "
            f"section in each scorecard.md is your spot-check checklist."
        )
    if deterministic_only:
        md.append(
            f"- Recommendation: **DO NOT** reopen the {len(false_closed)} flagged beads yet — "
            "this pass is deterministic-only (Phase 4/6 stub). Re-run with the real "
            "compliance-verifier + test-depth-auditor subagents to get a definitive verdict. "
            "If you've already run the full pipeline and still see this banner, check that "
            "compliance.json / test_depth.json have a non-stub `executor` / `auditor` field.\n"
        )
    else:
        md.append(f"- Recommendation: after the calibration spot-check above, reopen / create completion-debt for the confirmed false-closed beads; run /multi-pass-bug-hunting on the bottom decile. Phase 9.5 polish loop is mandatory whenever Phase 9 wrote beads.\n")

    # Distribution. Iterate CANONICAL_BANDS first (so empty bands still show
    # zero rows in the expected order), then any unrecognized bands that
    # actually appeared in this pass — those signal that score-bead.py emitted
    # a label master-report.py didn't know about, which would otherwise be
    # silently dropped from the table.
    md.append("## Distribution\n")
    md.append("| Band | Count |")
    md.append("|------|------:|")
    for band in CANONICAL_BANDS:
        md.append(f"| {band} | {band_counts.get(band, 0)} |")
    extra = [b for b in band_counts if b not in CANONICAL_BANDS]
    for band in sorted(extra):
        md.append(f"| {_esc_md_cell(band)} (unrecognized — score-bead.py drift?) | {band_counts[band]} |")
    md.append("")

    # False-closed list (the headline)
    md.append(f"## False-closed list (status=closed AND score<{args.threshold})\n")
    if not false_closed:
        md.append("(none — every closed bead scored ≥ threshold) ✓\n")
    else:
        md.append("| Bead | P | Type | Score | Title | Scorecard |")
        md.append("|------|--:|------|------:|-------|-----------|")
        for r in false_closed:
            md.append(f"| `{r['bead_id']}` | P{r['priority']} | {r['type']} | {r['score']} | {_esc_md_cell(r['title'][:60])} | [link]({r['scorecard_path']}) |")
        md.append("")

    # Ranked scoreboard
    md.append("## Ranked scoreboard (lowest first)\n")
    md.append("| Bead | Status | Score | Band | Title |")
    md.append("|------|--------|------:|------|-------|")
    for r in rows:
        md.append(f"| `{r['bead_id']}` | {r['status']} | {r['score']} | {r['verdict']} | {_esc_md_cell(r['title'][:50])} |")
    md.append("")

    # Trends
    if prior:
        md.append("## Trends vs prior pass\n")
        md.append("| Bead | Prior | Now | Δ |")
        md.append("|------|------:|----:|--:|")
        deltas = []
        for r in rows:
            if r["bead_id"] in prior:
                d = r["score"] - prior[r["bead_id"]]
                deltas.append(d)
                sign = "+" if d >= 0 else ""
                md.append(f"| `{r['bead_id']}` | {prior[r['bead_id']]} | {r['score']} | {sign}{d} |")
        if deltas:
            md.append(f"\n**Max |Δ|:** {max(abs(d) for d in deltas)}; **Mean Δ:** {sum(deltas)/len(deltas):+.1f}\n")

    out = "\n".join(md) + "\n"
    (pass_dir / "REPORT.md").write_text(out)
    (audit_dir / "REPORT.md").write_text(out)

    # Append to trends.md
    trends_path = audit_dir / "trends.md"
    if not trends_path.exists():
        trends_path.write_text("# Trends — score per bead per pass\n\n| Pass | Bead | Score |\n|------|------|------:|\n")
    with trends_path.open("a") as fp:
        for r in rows:
            fp.write(f"| {pass_dir.name} | `{r['bead_id']}` | {r['score']} |\n")

    print(f"Wrote {pass_dir / 'REPORT.md'} ({len(rows)} beads, {len(false_closed)} false-closed)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
