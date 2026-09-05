#!/usr/bin/env python3
"""lint-experiment-designs — validate every ## EXP-NNN block in
UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md.

Usage:
    ./lint-experiment-designs.py <workspace>/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md
"""
import re
import sys
from pathlib import Path

REQUIRED_FIELDS = [
    "Finding ref",
    "Bucket",
    "Severity",
    "Hypothesis",
    "Minimal reproducer",
    "Expected signal",
    "Falsifiability",
    "Invocation",
    "Verdict",
]
VALID_VERDICTS = {"OPEN", "CONFIRMED_UB", "NO_EVIDENCE", "NEEDS_REFINEMENT", "DEFERRED"}


def lint(path: Path) -> int:
    if not path.exists():
        print(f"[ERR] {path} not found", file=sys.stderr)
        return 64
    text = path.read_text()
    blocks = re.split(r"^## EXP-", text, flags=re.M)[1:]
    issues = 0
    for block in blocks:
        head = block.split("\n", 1)[0]
        exp_id = "EXP-" + head.split(":", 1)[0].strip()
        for field in REQUIRED_FIELDS:
            if f"**{field}:" not in block and f"**{field} (" not in block:
                print(f"[{exp_id}] missing field: {field}")
                issues += 1
        verdict_match = re.search(r"\*\*Verdict:\*\* +(\w+)", block)
        if verdict_match:
            v = verdict_match.group(1)
            if v not in VALID_VERDICTS:
                print(f"[{exp_id}] invalid verdict: {v!r} (expected one of {sorted(VALID_VERDICTS)})")
                issues += 1
        # Reproducer length check (≤30 lines inside a fenced code block)
        repro_match = re.search(
            r"\*\*Minimal reproducer:\*\*\s*```rust\n(.*?)\n```",
            block, flags=re.DOTALL
        )
        if repro_match:
            n = repro_match.group(1).count("\n") + 1
            if n > 30:
                print(f"[{exp_id}] reproducer is {n} lines (>30); minimize further")
                issues += 1
    if issues == 0:
        print(f"[OK] {path} — all blocks well-formed")
    return 1 if issues else 0


if __name__ == "__main__":
    # Handle --help explicitly so users don't get a cryptic
    # "[ERR] --help not found" when asking for usage.
    if len(sys.argv) >= 2 and sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        sys.exit(0)
    sys.exit(lint(Path(sys.argv[1]) if len(sys.argv) > 1 else Path("UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md")))
