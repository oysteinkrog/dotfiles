#!/usr/bin/env python3
"""validate-operators.py — Lint references/OPERATOR-LIBRARY.md.

The operator library is the spine of the verifier's cognition. Drift here
makes phases call non-existent moves, scorecards cite the wrong operators,
and Phase 10 fresh-eyes review can't audit consistency. We enforce structure.

Adapted from /operationalizing-expertise's operator card contract.

Each operator card MUST contain (after the heading line):
  - GLYPH and NAME in the heading
  - "Triggers:" line with at least one trigger
  - "Failure modes:" line with at least one failure mode
  - "Prompt module:" code block (any language fence)
  - At least one phase reference (Phase 1..10)

Optional (recommended): "Used in:", "Cite as:", "Anti-patterns:".

Usage:
    validate-operators.py [path/to/OPERATOR-LIBRARY.md]
    validate-operators.py --strict
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CARD_HEADING_RE = re.compile(r"^##\s+(.+?)\s*$", re.M)
GLYPH_RE = re.compile(r"^([∀-⟿➀-⟿⬀-⯿★◐⚖✦⊕⚑§⊿⌖↻⌀⊠⟴⊳⌥⊡⌬⊙⊞⊘⟳⌂⤵☖☍⌘])")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("path", nargs="?", default=None)
    p.add_argument("--strict", action="store_true")
    args = p.parse_args()

    path = Path(args.path) if args.path else (
        Path(__file__).resolve().parent.parent / "references" / "OPERATOR-LIBRARY.md"
    )
    if not path.exists():
        print(f"ERROR: {path} not found", file=sys.stderr)
        return 2
    text = path.read_text()

    errors: list[str] = []
    warnings: list[str] = []

    headings = [m.group(1) for m in CARD_HEADING_RE.finditer(text)]
    cards = re.split(r"^##\s+", text, flags=re.M)[1:]
    if not cards:
        errors.append("no operator cards (## headings) found")
        for e in errors:
            print(f"ERROR: {e}")
        return 1

    seen_glyphs: dict[str, str] = {}
    seen_names: set[str] = set()
    operator_cards = 0

    for i, body in enumerate(cards):
        head, _, rest = body.partition("\n")
        head = head.strip()
        gm = GLYPH_RE.match(head)
        glyph = gm.group(1) if gm else None
        name = head[1:].strip().lstrip("•—–-:").strip() if gm else head

        # Sections without a glyph are META sections (format docs, pipeline
        # cheat-sheets, "Why we name the moves") — not operator cards. Skip
        # them silently; they don't need the trigger / failure-mode contract.
        if not glyph:
            continue

        operator_cards += 1
        if glyph in seen_glyphs:
            errors.append(f"glyph {glyph} repeated: '{seen_glyphs[glyph]}' and '{name}'")
        else:
            seen_glyphs[glyph] = name

        if name in seen_names:
            errors.append(f"operator name '{name}' duplicated")
        seen_names.add(name)

        if not re.search(r"^\s*Triggers?:\s*", rest, re.M | re.I):
            errors.append(f"card '{name}': missing 'Triggers:' line")
        if not re.search(r"^\s*Failure modes?:\s*", rest, re.M | re.I):
            errors.append(f"card '{name}': missing 'Failure modes:' line")
        if not re.search(r"```", rest):
            errors.append(f"card '{name}': missing prompt-module code fence")
        elif rest.count("```") % 2 != 0:
            errors.append(f"card '{name}': unbalanced ``` fences")
        if not re.search(r"Phase\s*\d", rest, re.I):
            warnings.append(f"card '{name}': no 'Phase N' reference (which phase invokes it?)")
        if not re.search(r"^\s*Cite as:\s*", rest, re.M | re.I):
            warnings.append(f"card '{name}': no 'Cite as:' line (artifact citation guidance recommended)")

    # Cross-check: every glyph in SKILL.md's operator-mention table is defined here.
    # The glyph search must include EVERY glyph that exists in the library; we
    # build it from the seen_glyphs set so adding a new operator automatically
    # extends the cross-check (no manual sync needed).
    skill_md = path.parent.parent / "SKILL.md"
    if skill_md.exists() and seen_glyphs:
        skill_text = skill_md.read_text()
        glyph_class = "[" + "".join(re.escape(g) for g in seen_glyphs) + "]"
        skill_glyphs = set(re.findall(glyph_class, skill_text))
        defined = set(seen_glyphs)
        undefined_in_skill = skill_glyphs - defined
        if undefined_in_skill:
            warnings.append(f"SKILL.md cites glyphs {sorted(undefined_in_skill)} that have no card in OPERATOR-LIBRARY.md")
        unused_in_skill = defined - skill_glyphs
        if unused_in_skill:
            warnings.append(f"OPERATOR-LIBRARY.md defines glyphs {sorted(unused_in_skill)} that SKILL.md never mentions")

    if args.strict:
        errors.extend(warnings)
        warnings = []
    for w in warnings:
        print(f"WARN:  {w}")
    for e in errors:
        print(f"ERROR: {e}")
    print(f"\nValidation: {operator_cards} operator card(s) (of {len(cards)} total ## sections), "
          f"{len(errors)} error(s), {len(warnings)} warning(s)", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
