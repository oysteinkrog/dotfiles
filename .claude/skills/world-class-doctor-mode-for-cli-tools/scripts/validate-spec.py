#!/usr/bin/env python3
"""validate-spec.py — assert a repair_specs/<id>.md file is well-formed.

Required sections: Detector, Fixer, Preconditions, Invariants preserved,
Backup spec, Inverse, Idempotence proof sketch, Fixture spec.

Asserts:
- Detector pseudocode does NOT call mutate()
- Fixer pseudocode DOES call mutate()

Usage: validate-spec.py <path>
Exit 0 if valid, 2 with violations on stderr if not.
"""

import re
import sys
from pathlib import Path

REQUIRED_SECTIONS = [
    "## Detector",
    "## Fixer",
    "## Preconditions",
    "## Invariants preserved",
    "## Backup spec",
    "## Inverse",
    "## Idempotence proof sketch",
    "## Fixture spec",
]


def main():
    if len(sys.argv) != 2:
        print("usage: validate-spec.py <path>", file=sys.stderr)
        sys.exit(64)
    path = Path(sys.argv[1])
    if not path.exists():
        print(f"error: {path} does not exist", file=sys.stderr)
        sys.exit(2)
    text = path.read_text()

    violations = 0
    for sec in REQUIRED_SECTIONS:
        if sec not in text:
            print(f"VIOLATION: {path}: missing section '{sec}'", file=sys.stderr)
            violations += 1

    # Extract detector and fixer pseudocode blocks (best-effort).
    def block_after(heading):
        m = re.search(rf"{re.escape(heading)}.*?(?=\n## |\Z)", text, re.DOTALL)
        return m.group(0) if m else ""

    detector_block = block_after("## Detector")
    fixer_block = block_after("## Fixer")

    # Detector must be pure. Match `mutate(` and `Mutate(` (Go) and `mutate (`
    # case-insensitively. Allow comment exceptions in any language style.
    EXCEPTION_MARKERS = ("// allowed:", "# allowed:", "// pure:", "# pure:")
    has_exception = any(m in detector_block for m in EXCEPTION_MARKERS)
    if re.search(r"\bmutate\s*\(", detector_block, re.IGNORECASE) and not has_exception:
        print(f"VIOLATION: {path}: detector references mutate() — detectors must be PURE",
              file=sys.stderr)
        violations += 1

    if not re.search(r"\bmutate\s*\(", fixer_block, re.IGNORECASE):
        print(f"VIOLATION: {path}: fixer does not call mutate()", file=sys.stderr)
        violations += 1

    if violations:
        sys.exit(2)
    print(f"validate-spec: {path} OK", file=sys.stderr)


if __name__ == "__main__":
    main()
