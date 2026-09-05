#!/usr/bin/env python3
"""convergence-check.py — Phase 10: compare current pass to prior pass.

Usage:
    convergence-check.py <pass-dir> [--prior <pass-dir>]
    convergence-check.py --current <pass-dir> [--prior <pass-dir>]
                         [--threshold 10] [--score-threshold 700]

Both invocations accept the current pass dir as either a positional arg or
the explicit --current flag. Positional form matches the SKILL.md
cheat-sheet examples; --current is preserved for callers (e.g. run-pass.sh)
that built against the original interface.

Emits convergence.json conforming to references/EVIDENCE-SCHEMAS.md and prints
a one-line summary to stderr.

Convergence criteria (all must be true):
  1. max_score_delta_within_threshold
  2. no_new_false_closed
  3. no_new_synthesis_findings (best-effort: counts findings in synthesis.md)
  4. rubric_consistency_pass (must be filled in by the fresh-eyes agent)
  5. all_remediation_beads_exist (best-effort: checks inventory.jsonl)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCORE_RE = re.compile(r"\*\*Score:\s+(\d+)\s*/\s*1000\*\*", re.M)
STATUS_RE = re.compile(r"\*\*Status \(claimed\):\*\*\s+(\S+)", re.M)
UNSAFE_BEAD_ID_RE = re.compile(r"[\x00-\x1f`|]")


def collect_scores(pass_dir: Path) -> dict[str, tuple[int, str]]:
    out: dict[str, tuple[int, str]] = {}
    for sc in (pass_dir / "beads").glob("*/scorecard.md"):
        txt = sc.read_text()
        sm = SCORE_RE.search(txt)
        st = STATUS_RE.search(txt)
        if sm:
            out[sc.parent.name] = (int(sm.group(1)), st.group(1) if st else "unknown")
    return out


def count_synthesis_findings(pass_dir: Path) -> int:
    """Count bead-citing rows in synthesis tables.

    A finding row always cites at least one backticked bead id, so we look for
    `| ` followed by a backtick — header / separator / placeholder rows don't
    have backticks at the row start.
    """
    p = pass_dir / "synthesis.md"
    if not p.exists():
        return 0
    txt = p.read_text()
    return sum(1 for ln in txt.splitlines() if re.match(r"^\|\s+`", ln))


def rubric_sha(audit_dir: Path) -> str:
    p = audit_dir / "rubric.md"
    if not p.exists():
        return ""
    return hashlib.sha256(p.read_bytes()).hexdigest()


def _truthy_review_value(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"pass", "passed", "true", "yes", "ok"}
    return False


def load_fresh_eyes_review(pass_dir: Path) -> dict[str, object]:
    """Load Phase-10 fresh-eyes verdict written before this formal check.

    The skill's convergence contract requires an independent rubric consistency
    spot-check. Without this artifact the deterministic script must fail closed;
    otherwise CI could declare convergence before the audit-of-the-audit ran.
    """
    for name in ("fresh_eyes_review.json", "convergence_review.json"):
        path = pass_dir / name
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text())
        except Exception as exc:
            return {
                "pass": False,
                "path": str(path),
                "reason": f"{name} could not be parsed: {exc}",
                "data": {},
            }
        verdict = data.get("rubric_consistency_pass", data.get("verdict"))
        passed = _truthy_review_value(verdict)
        generosity_flags = data.get("generosity_flags", [])
        category_miss_flags = data.get("category_miss_flags", [])
        if generosity_flags or category_miss_flags:
            passed = False
        return {
            "pass": passed,
            "path": str(path),
            "reason": data.get("reason") or data.get("summary") or None,
            # `wrapper_stub: true` signals the review was emitted by
            # `run-pass.sh` as a deterministic stub rather than by the
            # fresh-eyes subagent. Convergence is still computed, but the
            # rubric-consistency dimension is unverified; surface the flag
            # to convergence.json so consumers (CI, dashboards, the next
            # pass's reviewer) can warn or treat it as "convergence pending
            # real review".
            "wrapper_stub": bool(data.get("wrapper_stub")),
            "data": data,
        }
    return {
        "pass": False,
        "path": None,
        "reason": "missing fresh_eyes_review.json from Phase 10",
        "wrapper_stub": False,
        "data": {},
    }


def main() -> int:
    p = argparse.ArgumentParser()
    # Accept either a positional <pass-dir> OR the explicit `--current` flag.
    # SKILL.md's cheat-sheet uses the positional form; run-pass.sh uses the
    # flag. argparse rejects the dual definition if we mark `--current`
    # required, so both are optional and we validate manually below.
    p.add_argument("pass_dir", nargs="?", default=None,
                   help="The current pass dir to score for convergence "
                        "(positional, equivalent to --current).")
    p.add_argument("--current", default=None,
                   help="The current pass dir (alternative to positional "
                        "<pass-dir>). Provided for callers that built against "
                        "the legacy flag form.")
    p.add_argument("--prior", required=False,
                   help="Optional prior pass dir to diff against. If omitted, "
                        "convergence is reported as undefined (single-pass).")
    p.add_argument("--threshold", type=int, default=10)
    p.add_argument("--score-threshold", type=int, default=700)
    args = p.parse_args()

    current_arg = args.current or args.pass_dir
    if not current_arg:
        p.error("a pass dir is required: pass it positionally OR via --current")
    if args.current and args.pass_dir and args.current != args.pass_dir:
        p.error(
            "specify the current pass dir EITHER positionally OR via --current, "
            f"not both with conflicting values ({args.pass_dir!r} vs {args.current!r})"
        )

    cur = Path(current_arg)
    audit_dir = cur.parent.parent
    cur_scores = collect_scores(cur)

    if not args.prior:
        out: dict[str, Any] = {
            "computed_at": datetime.now(timezone.utc).isoformat(),
            "current_pass": cur.name,
            "prior_pass": None,
            "is_converged": False,
            "criteria": {"reason": "no prior pass — convergence requires two passes"},
        }
        (cur / "convergence.json").write_text(json.dumps(out, indent=2))
        print("First pass — convergence undefined", file=sys.stderr)
        return 0

    prior = Path(args.prior)
    prior_scores = collect_scores(prior)

    # Criterion 1: max score delta within threshold
    common = set(cur_scores) & set(prior_scores)
    deltas = [(b, cur_scores[b][0] - prior_scores[b][0]) for b in common]
    max_delta = max((abs(d) for _, d in deltas), default=0)
    max_delta_bead = max(deltas, key=lambda x: abs(x[1]))[0] if deltas else None

    # Criterion 2: no new false-closed
    cur_fc = {b for b, (s, st) in cur_scores.items() if st == "closed" and s < args.score_threshold}
    prior_fc = {b for b, (s, st) in prior_scores.items() if st == "closed" and s < args.score_threshold}
    new_fc = sorted(cur_fc - prior_fc)

    # Criterion 3: synthesis-finding count
    cur_synth = count_synthesis_findings(cur)
    prior_synth = count_synthesis_findings(prior)
    new_synth = max(0, cur_synth - prior_synth)

    # Criterion 4: fresh-eyes rubric consistency. Fail closed if the independent
    # Phase 10 reviewer has not written a verdict artifact yet.
    fresh_eyes = load_fresh_eyes_review(cur)
    rubric_consistency_pass = bool(fresh_eyes["pass"])
    fresh_eyes_is_wrapper_stub = bool(fresh_eyes.get("wrapper_stub", False))

    # Criterion 5: remediation beads exist. Malformed inventory evidence fails
    # closed because otherwise a corrupt Phase 1 artifact can hide the bead
    # graph state that convergence is supposed to verify.
    inv_path = cur / "inventory.jsonl"
    inv_ids: set[str] = set()
    inventory_parse_errors: list[str] = []
    if inv_path.exists():
        for line_no, ln in enumerate(inv_path.read_text().splitlines(), start=1):
            if not ln.strip():
                continue
            try:
                item = json.loads(ln)
            except json.JSONDecodeError as exc:
                inventory_parse_errors.append(f"line {line_no}: {exc.msg}")
                continue
            if not isinstance(item, dict):
                inventory_parse_errors.append(f"line {line_no}: expected JSON object")
                continue
            bead_id = item.get("id")
            if not isinstance(bead_id, str) or not bead_id:
                inventory_parse_errors.append(f"line {line_no}: missing string id")
                continue
            inv_ids.add(bead_id)
    rem_path = prior / "remediation.md"
    expected_remediation_ids: list[str] = []
    if rem_path.exists():
        seen_remediation_ids: set[str] = set()
        for line in rem_path.read_text().splitlines():
            if not line.startswith("|"):
                continue
            for bead_id in re.findall(r"`([^`]+)`", line):
                if not bead_id or UNSAFE_BEAD_ID_RE.search(bead_id):
                    continue
                if bead_id not in seen_remediation_ids:
                    seen_remediation_ids.add(bead_id)
                    expected_remediation_ids.append(bead_id)
    missing_remediation = [i for i in expected_remediation_ids if i not in inv_ids]

    # Rubric change check
    cur_rubric = rubric_sha(audit_dir)
    rubric_changed = False
    rubric_changed_reason = None
    prior_manifest = prior / "manifest.json"
    if prior_manifest.exists():
        # Tolerate a corrupt prior manifest. Without this guard, an aborted
        # prior pass that left a half-written manifest.json would raise
        # JSONDecodeError here and crash convergence-check before
        # `convergence.json` is written — hiding the entire verdict from the
        # user. Mirrors the line-by-line try/except used for inventory.jsonl
        # above; same fail-soft posture.
        try:
            prior_data = json.loads(prior_manifest.read_text())
        except Exception as exc:
            prior_data = {}
            rubric_changed = True
            rubric_changed_reason = (
                f"prior pass manifest.json could not be parsed ({exc}); "
                "treating as rubric drift to fail convergence safely"
            )
        prior_rubric_hash = prior_data.get("rubric_sha256")
        if prior_rubric_hash and prior_rubric_hash != cur_rubric:
            rubric_changed = True
            rubric_changed_reason = "rubric.md changed; score deltas not directly comparable"

    is_converged = (
        max_delta <= args.threshold
        and not new_fc
        and new_synth == 0
        and rubric_consistency_pass
        and not fresh_eyes_is_wrapper_stub
        and not inventory_parse_errors
        and not missing_remediation
        and not rubric_changed
    )

    # Heterogeneous mix (str / int / bool / list / nested dict). The type
    # annotation lives on the first-pass branch above (line ~136); mypy
    # [no-redef] flags a second annotated binding as a redefinition, so
    # this branch reuses the same `out` name without re-annotating.
    out = {
        "computed_at": datetime.now(timezone.utc).isoformat(),
        "current_pass": cur.name,
        "prior_pass": prior.name,
        "is_converged": is_converged,
        "criteria": {
            "max_score_delta_within_threshold": max_delta <= args.threshold,
            "max_score_delta_observed": max_delta,
            "max_score_delta_bead": max_delta_bead,
            "no_new_false_closed": not new_fc,
            "new_false_closed_beads": new_fc,
            "no_new_synthesis_findings": new_synth == 0,
            "new_synthesis_finding_count": new_synth,
            "rubric_consistency_pass": rubric_consistency_pass,
            "fresh_eyes_review_path": fresh_eyes["path"],
            "fresh_eyes_review_reason": fresh_eyes["reason"],
            # When `true`, the rubric_consistency_pass verdict came from a
            # deterministic stub (run-pass.sh has no fresh-eyes subagent in
            # the loop), NOT from a real independent reviewer. Convergence
            # is technically computed but the rubric-consistency dimension
            # is unverified; gate "real" convergence on this being false.
            "fresh_eyes_review_is_wrapper_stub": fresh_eyes_is_wrapper_stub,
            "inventory_jsonl_parse_error_count": len(inventory_parse_errors),
            "inventory_jsonl_parse_errors": inventory_parse_errors,
            "all_remediation_beads_exist": not missing_remediation,
            "missing_remediation_beads": missing_remediation,
        },
        "rubric_changed_since_prior_pass": rubric_changed,
        "rubric_changed_reason": rubric_changed_reason,
        "next_pass_tasks": [],
    }

    if not is_converged:
        tasks = []
        if max_delta > args.threshold:
            tasks.append(f"Investigate why bead {max_delta_bead} score moved by {max_delta} points")
        for b in new_fc:
            tasks.append(f"Spec-extract {b} (newly false-closed) — was it missed in prior pass?")
        if missing_remediation:
            tasks.append(f"Verify {len(missing_remediation)} prior-pass remediation beads exist: {missing_remediation}")
        if inventory_parse_errors:
            tasks.append(f"Repair current pass inventory.jsonl parse errors: {len(inventory_parse_errors)} malformed rows")
        if new_synth > 0:
            tasks.append(f"Resolve {new_synth} new synthesis findings")
        if not rubric_consistency_pass:
            tasks.append(f"Run Phase 10 fresh-eyes rubric review and write fresh_eyes_review.json ({fresh_eyes['reason']})")
        elif fresh_eyes_is_wrapper_stub:
            tasks.append("Replace wrapper-stub fresh_eyes_review.json with a real Phase 10 fresh-eyes rubric review")
        if rubric_changed:
            tasks.append("Rubric changed; rerun with consistent rubric to assess true convergence")
        out["next_pass_tasks"] = tasks

    (cur / "convergence.json").write_text(json.dumps(out, indent=2))
    verdict = "CONVERGED ✓" if is_converged else "NOT CONVERGED"
    print(f"{verdict} (max_delta={max_delta}, new_false_closed={len(new_fc)}, new_synth={new_synth})", file=sys.stderr)
    return 0 if is_converged else 1


if __name__ == "__main__":
    sys.exit(main())
