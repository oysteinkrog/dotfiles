#!/usr/bin/env python3
"""compare-to-expected.py — Diff an audit's REPORT.md against a fixture's EXPECTED.md.

Used by scripts/regression-test.sh to verify the audit produces the right
verdicts on known fixture cases. Comparison is structural, not byte-exact:
we extract a small set of headline assertions from EXPECTED.md and check the
actual REPORT.md satisfies each.

EXPECTED.md is a plain markdown file with a `## Assertions` section listing
expected facts in this format (one per bullet):

    ## Assertions
    - total_beads: 3
    - false_closed_count: 1
    - false_closed_includes: bd-stub-impl
    - false_closed_excludes: bd-real-impl
    - score_min_for: bd-real-impl >= 850
    - score_max_for: bd-stub-impl <= 250
    - verdict_band_for: bd-real-impl == "Verified"
    - convergence_is: false   (first pass)

Supported assertion verbs:
    total_beads: N                        — exact count
    closed_count: N                       — exact count
    false_closed_count: N                 — exact count
    false_closed_includes: <bead-id>      — must appear in false-closed list
    false_closed_excludes: <bead-id>      — must NOT appear
    score_min_for: <bead-id> >= N         — bead's score is at least N
    score_max_for: <bead-id> <= N         — bead's score is at most N
    verdict_band_for: <bead-id> == "..."  — verdict band string match
    contains_text: "..."                  — REPORT.md contains this literal

Usage:
    compare-to-expected.py <actual-report.md> <expected.md>
                            [--threshold 700]

Exit codes:
    0  every assertion satisfied
    1  one or more assertions failed (details on stderr)
    2  invalid arguments / parse error
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


# Current `master-report.py` ranked scoreboard row:
#   | `<id>` | <status> | <score> | <band> | <title> |
# Older reports also exposed scores in the false-closed table:
#   | `<id>` | P<n> | <type> | <score> | <title> | <scorecard-link> |
# Capture the first backticked cell literally; bead IDs are data, not a regex
# grammar, and may be scoped/domain-prefixed.
RANKED_SCORE_ROW_RE = re.compile(
    r"^\|\s*`([^`]+)`\s*\|\s*[^|]*\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|",
    re.M,
)
LEGACY_FALSE_CLOSED_SCORE_ROW_RE = re.compile(
    r"^\|\s*`([^`]+)`\s*\|\s*P\d+\s*\|\s*[^|]*\|\s*(\d+)\s*\|",
    re.M,
)
FALSE_CLOSED_ID_RE = re.compile(r"^\|\s*`([^`]+)`")


def _band_for_score(score: int) -> str:
    """Default verdict-band labels (matches assets/rubric-template.md)."""
    if score >= 950:
        return "Verified"
    if score >= 850:
        return "Substantially complete"
    if score >= 700:
        return "Partial"
    if score >= 500:
        return "False-closed (mild)"
    if score >= 250:
        return "False-closed (severe)"
    return "Theater"


def parse_report(report_path: Path) -> dict:
    """Best-effort extraction of facts from the master REPORT.md.

    Patterns match what `scripts/master-report.py` actually emits, namely:
      Header: "Beads audited: 1  |  Threshold: 700"
      Exec:   "**1** total beads audited; **1** false-closed (status=closed,
              score<700) — **100%** of all closed beads (of 1 total closed)."
    """
    txt = report_path.read_text()

    totals = {}
    # "**N** total beads audited" (exec-summary line, bold)
    m = re.search(r"\*\*(\d+)\*\*\s+total beads audited", txt, re.I)
    if m:
        totals["total_beads"] = int(m.group(1))
    else:
        # Fallback: the header line "Beads audited: N"
        m = re.search(r"Beads audited:\s*(\d+)", txt, re.I)
        if m:
            totals["total_beads"] = int(m.group(1))

    # "**N** false-closed"
    m = re.search(r"\*\*(\d+)\*\*\s+false[- ]closed", txt, re.I)
    if m:
        totals["false_closed_count"] = int(m.group(1))

    # "(of N total closed)" inside the exec-summary parenthetical
    m = re.search(r"of\s+(\d+)\s+total closed", txt, re.I)
    if m:
        totals["closed_count"] = int(m.group(1))

    # Per-bead rows from the scoreboard table: id, score, verdict-band string.
    per_bead = {}
    false_closed_ids = set()
    in_fc_section = False
    for line in txt.splitlines():
        if line.startswith("## False-closed list"):
            in_fc_section = True
            continue
        if in_fc_section and line.startswith("## "):
            in_fc_section = False
        if in_fc_section:
            m = FALSE_CLOSED_ID_RE.match(line)
            if m:
                false_closed_ids.add(m.group(1))
        m = RANKED_SCORE_ROW_RE.match(line)
        if m:
            bid, score, band = m.group(1), int(m.group(2)), m.group(3).strip()
            per_bead[bid] = {"score": score, "band": band}
            continue
        m = LEGACY_FALSE_CLOSED_SCORE_ROW_RE.match(line)
        if m:
            bid, score = m.group(1), int(m.group(2))
            per_bead.setdefault(bid, {"score": score, "band": _band_for_score(score)})

    return {
        "totals": totals,
        "per_bead": per_bead,
        "false_closed_ids": false_closed_ids,
        "raw_text": txt,
    }


def parse_assertions(expected_path: Path) -> list[tuple[str, str]]:
    """Extract assertion bullets from EXPECTED.md's `## Assertions` section.

    Returns a list of (verb, payload) tuples in declaration order.
    """
    txt = expected_path.read_text()
    in_section = False
    out: list[tuple[str, str]] = []
    for line in txt.splitlines():
        if re.match(r"^##+\s+Assertions\b", line, re.I):
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            m = re.match(r"^\s*[-*]\s+([a-z_]+):\s+(.+?)\s*$", line)
            if m:
                out.append((m.group(1), m.group(2)))
    return out


def check_assertion(verb: str, payload: str, report: dict) -> tuple[bool, str]:
    """Return (passed, message) for one assertion."""
    if verb in ("total_beads", "closed_count", "false_closed_count"):
        try:
            expected = int(payload)
        except ValueError:
            return False, f"{verb}: payload '{payload}' is not an integer"
        actual = report["totals"].get(verb)
        if actual is None:
            return False, f"{verb}: not found in REPORT.md (could not parse)"
        if actual != expected:
            return False, f"{verb}: expected {expected}, actual {actual}"
        return True, f"{verb} = {actual}"

    if verb == "false_closed_includes":
        bid = payload.strip("`")
        if bid not in report["false_closed_ids"]:
            return False, f"false_closed_includes: bead `{bid}` NOT in false-closed list (saw {sorted(report['false_closed_ids'])})"
        return True, f"`{bid}` is in false-closed list"

    if verb == "false_closed_excludes":
        bid = payload.strip("`")
        if bid in report["false_closed_ids"]:
            return False, f"false_closed_excludes: bead `{bid}` UNEXPECTEDLY in false-closed list"
        return True, f"`{bid}` correctly absent from false-closed list"

    if verb in ("score_min_for", "score_max_for"):
        m = re.match(r"`([^`]+)`\s*(>=|<=)\s*(\d+)\s*$", payload)
        if m:
            bid, op, val = m.group(1), m.group(2), int(m.group(3))
        else:
            m = re.match(r"(\S+)\s*(>=|<=)\s*(\d+)\s*$", payload)
            if m:
                bid, op, val = m.group(1), m.group(2), int(m.group(3))
        if not m:
            return False, f"{verb}: cannot parse '{payload}' (expected: bead-id >= N or <= N)"
        observed = report["per_bead"].get(bid, {}).get("score")
        if observed is None:
            return False, f"{verb}: bead `{bid}` not in scoreboard (per_bead keys: {sorted(report['per_bead'])[:5]}...)"
        if op == ">=" and observed < val:
            return False, f"{verb}: `{bid}` score {observed} < required {val}"
        if op == "<=" and observed > val:
            return False, f"{verb}: `{bid}` score {observed} > allowed {val}"
        return True, f"`{bid}` score {observed} {op} {val}"

    if verb == "verdict_band_for":
        m = re.match(r"`([^`]+)`\s*==\s*\"?(.+?)\"?\s*$", payload)
        if m:
            bid, expected_band = m.group(1), m.group(2).strip().strip('"')
        else:
            m = re.match(r"(\S+)\s*==\s*\"?(.+?)\"?\s*$", payload)
            if m:
                bid, expected_band = m.group(1), m.group(2).strip().strip('"')
        if not m:
            return False, f"verdict_band_for: cannot parse '{payload}'"
        observed = report["per_bead"].get(bid, {}).get("band")
        if observed is None:
            return False, f"verdict_band_for: bead `{bid}` not in scoreboard"
        if expected_band.lower() not in observed.lower():
            return False, f"verdict_band_for: `{bid}` band='{observed}', expected to contain '{expected_band}'"
        return True, f"`{bid}` band='{observed}' contains '{expected_band}'"

    if verb == "contains_text":
        needle = payload.strip().strip("\"'")
        if needle in report["raw_text"]:
            return True, f"REPORT.md contains '{needle}'"
        return False, f"contains_text: '{needle}' not found in REPORT.md"

    return False, f"unknown assertion verb: {verb}"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("actual_report")
    p.add_argument("expected_md")
    p.add_argument("--threshold", type=int, default=700,
                   help="(reserved for future per-threshold variants)")
    args = p.parse_args()

    actual = Path(args.actual_report)
    expected = Path(args.expected_md)
    if not actual.exists():
        print(f"ERROR: actual report not found: {actual}", file=sys.stderr)
        return 2
    if not expected.exists():
        print(f"ERROR: expected file not found: {expected}", file=sys.stderr)
        return 2

    report = parse_report(actual)
    assertions = parse_assertions(expected)
    if not assertions:
        print(f"ERROR: no assertions found in {expected} (need a `## Assertions` section)", file=sys.stderr)
        return 2

    passed = 0
    failed = 0
    failures: list[str] = []
    for verb, payload in assertions:
        ok, msg = check_assertion(verb, payload, report)
        if ok:
            passed += 1
        else:
            failed += 1
            failures.append(msg)

    print(f"compare-to-expected: {passed} passed, {failed} failed")
    if failures:
        print("FAILURES:", file=sys.stderr)
        for f in failures:
            print(f"  ✗ {f}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
