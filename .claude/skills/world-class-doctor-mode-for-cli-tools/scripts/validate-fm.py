#!/usr/bin/env python3
"""validate-fm.py — assert a failure_modes/<subsystem>.md file is well-formed.

Usage: validate-fm.py <path>
Exit 0 if valid, 2 with violations on stderr if not.
"""

import re
import sys
from pathlib import Path

REQUIRED_FIELDS = [
    "id:", "title:", "severity:", "subsystem:",
    "symptoms:", "root_cause:", "observable_signals:",
    "currently_auto_detected:", "currently_auto_fixed:",
]


def main():
    if len(sys.argv) != 2:
        print("usage: validate-fm.py <path>", file=sys.stderr)
        sys.exit(64)
    path = Path(sys.argv[1])
    if not path.exists():
        print(f"error: {path} does not exist", file=sys.stderr)
        sys.exit(2)
    text = path.read_text()

    violations = 0
    if "## n/a" in text and len(text.strip().splitlines()) < 30:
        # Explicit n/a block; OK.
        print(f"validate-fm: {path} explicit n/a (acceptable)", file=sys.stderr)
        return

    fm_blocks = re.split(r"^# FM-", text, flags=re.MULTILINE)[1:]
    if len(fm_blocks) < 3:
        print(f"VIOLATION: {path} has {len(fm_blocks)} FMs; expected >= 3", file=sys.stderr)
        violations += 1

    for i, block in enumerate(fm_blocks):
        block_id = block.splitlines()[0].strip() if block else f"#{i}"
        for field in REQUIRED_FIELDS:
            if field not in block:
                print(f"VIOLATION: FM-{block_id}: missing field '{field}'", file=sys.stderr)
                violations += 1
        # Severity must be P0/P1/P2/P3.
        sev_m = re.search(r"severity:\s*(P[0-3])", block)
        if not sev_m:
            print(f"VIOLATION: FM-{block_id}: severity not P0..P3", file=sys.stderr)
            violations += 1

    if violations:
        sys.exit(2)
    print(f"validate-fm: {path} OK ({len(fm_blocks)} FMs)", file=sys.stderr)


if __name__ == "__main__":
    main()
