#!/usr/bin/env python3
"""process-defense.py — Deterministic file-management for the closer-defense flow.

This script handles the structural/bookkeeping half of Phase 8.5. The
substantive judgment ("does this defense actually justify a higher score?")
is LLM-driven and lives in subagents/closer-defender.md — but the structure
(write defense.json, append a Defense round section to scorecard.md, mark
the bead as defense-pending so the next score-bead invocation includes it)
is deterministic and lives here.

Workflow:
    1. Closer submits via scripts/closer-respond.sh, which writes
       <bead-dir>/closer_response.md and appends to closer_responses.jsonl.
    2. The orchestrator runs THIS script, which writes a stub defense.json
       and appends a "## Defense round" section template to scorecard.md.
    3. The orchestrator invokes subagents/closer-defender.md with the bead-dir.
       The subagent reads closer_response.md, applies the acceptance criteria
       in its own doc, fills in defense.json fields (verdict, score_delta,
       rationale), and updates the appended scorecard section with the new
       per-dimension scores.
    4. Re-run scripts/score-bead.py against the bead-dir; if defense.json's
       `verdict: accepted` is set, score-bead.py reads it and applies the
       per-dimension overrides from defense.json#dimensions.

Usage:
    process-defense.py <bead-dir> [<closer-response-md>]
                                  [--actor <human-or-agent-id>]

If <closer-response-md> is omitted, the script looks for closer_response.md
inside <bead-dir>. If that's missing too, it exits 3 (nothing to process).

Exit codes:
    0  defense.json + scorecard.md hook written; subagent can take it from here
    2  invalid arguments / bead-dir not found
    3  no closer response found (nothing to process)
"""
from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _actor() -> str:
    return os.environ.get("USER") or os.environ.get("LOGNAME") or getpass.getuser() or "unknown"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("bead_dir")
    p.add_argument("response_path", nargs="?", default=None,
                   help="path to closer_response.md (default: <bead-dir>/closer_response.md)")
    p.add_argument("--actor", default=None,
                   help="who is processing this defense (default: $USER)")
    args = p.parse_args()

    bead_dir = Path(args.bead_dir).resolve()
    if not bead_dir.is_dir():
        print(f"ERROR: bead dir not found: {bead_dir}", file=sys.stderr)
        return 2

    response_path = Path(args.response_path) if args.response_path else (bead_dir / "closer_response.md")
    if not response_path.exists():
        print(f"ERROR: no closer response at {response_path}", file=sys.stderr)
        print("       Closer must submit via: scripts/closer-respond.sh <bead-id> <evidence-file>", file=sys.stderr)
        return 3

    response_text = response_path.read_text()
    response_sha = hashlib.sha256(response_text.encode("utf-8")).hexdigest()

    # Read prior scorecard to capture starting score AND check whether a
    # Defense round has already been scaffolded (idempotency guard).
    sc_path = bead_dir / "scorecard.md"
    prior_score = None
    sc_text = ""
    if sc_path.exists():
        sc_text = sc_path.read_text()
        m = re.search(r"\*\*Score:\s+(\d+)\s*/\s*1000\*\*", sc_text)
        if m:
            prior_score = int(m.group(1))

    # Idempotency: if a Defense round section already exists in the scorecard
    # AND defense.json already records a non-PENDING verdict, refuse —
    # processing again would clobber the subagent's prior judgment. The
    # exception is when defense.json is still PENDING (the subagent hasn't
    # filled it in yet); in that case re-running just refreshes the
    # response_sha256 and timestamp.
    defense_path = bead_dir / "defense.json"
    if "## Defense round" in sc_text and defense_path.exists():
        try:
            prior_defense = json.loads(defense_path.read_text())
            if prior_defense.get("verdict") not in (None, "", "PENDING"):
                print(f"ERROR: defense already processed for {bead_dir.name} "
                      f"(verdict={prior_defense.get('verdict')}). Refusing to clobber.",
                      file=sys.stderr)
                print("       To re-process, manually delete defense.json AND remove the",
                      file=sys.stderr)
                print("       '## Defense round' section from scorecard.md first.",
                      file=sys.stderr)
                return 4
        except Exception:
            pass  # malformed prior defense.json — proceed with overwrite

    # Read prior bead show.json for context (status, type, title).
    show_path = bead_dir / "show.json"
    bead_id = bead_dir.name
    bead_title = ""
    if show_path.exists():
        try:
            show = json.loads(show_path.read_text())
            bead_id = show.get("id", bead_dir.name)
            bead_title = show.get("title", "")
        except Exception:
            pass

    # Stub defense.json — subagent fills in verdict + scores.
    # Explicit type: heterogeneous values (str/int/None/dict/list).
    defense: dict[str, Any] = {
        "bead_id": bead_id,
        "submitted_at": _utc_now(),
        "actor": args.actor or _actor(),
        "response_path": str(response_path),
        "response_sha256": response_sha,
        "prior_score": prior_score,
        "verdict": "PENDING",  # subagent updates to ACCEPTED|REJECTED|PARTIAL
        "score_delta": None,    # subagent fills if accepted
        "new_score": None,
        "dimensions": {},       # subagent fills per-dimension overrides
        "rationale": "",        # subagent's reasoning
        "spot_checks": [],      # subagent records what it verified vs took on faith
    }
    defense_path.write_text(json.dumps(defense, indent=2) + "\n")

    # Append the scorecard hook the subagent will fill in. Only append if
    # there isn't already a Defense round section (re-running while PENDING
    # should refresh defense.json but not duplicate the scorecard section).
    if sc_path.exists() and "## Defense round" not in sc_text:
        appended = "\n\n## Defense round\n\n"
        appended += f"_Closer response submitted {defense['submitted_at']} by {defense['actor']} "
        appended += f"(sha256: {response_sha[:12]}…)._\n\n"
        appended += "_Defense pending: subagents/closer-defender.md will read closer_response.md, "
        appended += "apply the acceptance criteria, and either ACCEPT (re-derive score upward, "
        appended += "update the dimension scores below) or REJECT (Phase 9 proceeds against the "
        appended += "original score)._\n\n"
        appended += "**Verdict:** PENDING\n"
        appended += "**Score delta:** —\n"
        appended += "**New score:** —\n"
        with sc_path.open("a") as f:
            f.write(appended)

    print(f"✓ Defense scaffolded for {bead_id}")
    print(f"  defense.json:    {defense_path}")
    print(f"  scorecard hook:  {sc_path} (## Defense round appended)")
    print(f"  prior score:     {prior_score if prior_score is not None else 'unknown'}")
    print(f"  response sha256: {response_sha}")
    print()
    print("Next: invoke subagents/closer-defender.md with this bead-dir.")
    print("After it updates defense.json#verdict, re-run scripts/score-bead.py to integrate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
