#!/usr/bin/env python3
"""validate-operators.py — verify OPERATORS.md cards have all required sections.

Per /operationalizing-expertise: each operator card must include trigger, failure
modes, prompt module, and fix section. Run as part of CI for the skill itself.

Exit non-zero if any operator is missing a required section.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parent.parent
OPS = SKILL_ROOT / "references/methodology/OPERATORS.md"

REQUIRED_FIELDS = ("Trigger.", "Question.", "Failure modes.", "Prompt module.", "Fix section.")

def main() -> int:
    if not OPS.exists():
        print(f"OPERATORS.md not found at {OPS}", file=sys.stderr)
        return 2

    text = OPS.read_text()

    # Operator cards are second-level headers starting with a glyph
    headers = re.findall(r"^## (.+)$", text, re.MULTILINE)
    # Drop the meta-sections
    cards = [h for h in headers if not h.lower().startswith(("composition", "operator"))]

    if not cards:
        print("no operator cards detected", file=sys.stderr)
        return 1

    failures: list[str] = []
    sections = re.split(r"^## ", text, flags=re.MULTILINE)
    section_map = {s.split("\n", 1)[0].strip(): s for s in sections if s.strip()}

    for card in cards:
        body = section_map.get(card, "")
        missing = [f for f in REQUIRED_FIELDS if f"**{f}**" not in body]
        if missing:
            failures.append(f"{card!r}: missing {missing}")

    if not failures:
        print(f"validate-operators.py: OK ({len(cards)} cards verified)")
        return 0

    print(f"validate-operators.py: FAILED ({len(failures)} card(s) missing required sections)")
    for f in failures:
        print(f"  - {f}")
    return 1

if __name__ == "__main__":
    sys.exit(main())
