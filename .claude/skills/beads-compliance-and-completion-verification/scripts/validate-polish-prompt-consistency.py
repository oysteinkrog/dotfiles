#!/usr/bin/env python3
"""validate-polish-prompt-consistency.py — fail loudly if the Phase 9.5 polish
prompt has drifted between its three canonical homes:

  1. assets/polish-prompt.txt           (single source of truth)
  2. SKILL.md > Phase 9.5 polish prompt blockquote
  3. scripts/polish-remediation-beads.sh > POLISH_PROMPT bash variable

The user's standing instruction is that the prompt MUST be applied verbatim.
Even small drift (a smart-quote vs a straight-quote, an em-dash swapped for a
hyphen) breaks the verbatim-application guarantee. This validator is
deliberately strict: it compares with character-level equality and reports
the first diff. Run it pre-commit (or wire it into CI).

Usage:
    validate-polish-prompt-consistency.py [<skill-dir>]

Exit codes:
    0  all three sources match exactly
    1  drift detected; first diff printed to stderr
    2  one or more sources are missing
"""
from __future__ import annotations

import difflib
import re
import sys
from pathlib import Path


def _normalize(s: str) -> str:
    """Strip trailing whitespace and a single trailing newline, but preserve
    internal whitespace (including non-breaking spaces and em-dashes)."""
    return s.rstrip("\n").rstrip()


def _extract_skill_md_prompt(skill_md: Path) -> str | None:
    """Find the verbatim polish-prompt blockquote in SKILL.md.

    Layout:
        > **Polish prompt (verbatim — do not paraphrase, do not shorten):**
        >
        > Check over each bead super carefully — ...

    The third line of the blockquote is the prompt. We tolerate any number of
    leading blank `> ` lines between the header and the body so future edits
    that add metadata don't break the matcher.
    """
    text = skill_md.read_text(encoding="utf-8")
    # `[^\n]+?` (not `.+?`) guarantees the capture stays on a single line —
    # avoids accidentally folding multiple blockquote lines together if a
    # future edit makes the prompt multi-line. DOTALL is intentionally NOT
    # set: we want `.` to NOT match `\n` so the lazy capture can't span
    # lines either.
    pattern = re.compile(
        r"\>\s+\*\*Polish prompt \(verbatim[^*]*\):\*\*\s*\n"
        r"(?:\>\s*\n)+"
        r"\>\s*(?P<prompt>[^\n]+?)\n"
        r"(?:\n|$)"
    )
    m = pattern.search(text)
    if not m:
        return None
    return _normalize(m.group("prompt"))


def _extract_bash_prompt(bash_script: Path) -> str | None:
    """Pull the POLISH_PROMPT bash assignment.

    Expected form:
        POLISH_PROMPT='...prompt...'

    The script uses single-quote bash form (so backslash escapes inside don't
    apply), with `'\''` to embed apostrophes. We re-decode that escape.
    """
    text = bash_script.read_text(encoding="utf-8")
    # Same single-line discipline as the SKILL.md extractor: `[^\n]+?` keeps
    # the capture on one line. The prompt is a single-line bash assignment
    # by convention; if a future edit makes it multi-line, this pattern will
    # fail loudly (returning None → caller reports "missing or unparseable")
    # which is the correct behavior — the bash variable would no longer be
    # `POLISH_PROMPT='...'` but something more elaborate, and the validator
    # SHOULD fail until the extractor is updated to match.
    m = re.search(r"^POLISH_PROMPT=\'(?P<body>[^\n]+?)\'\s*$", text, re.MULTILINE)
    if not m:
        return None
    body = m.group("body")
    # Decode bash single-quote apostrophe escape: '\''  →  '
    body = body.replace("'\\''", "'")
    return _normalize(body)


def _extract_asset_prompt(asset_file: Path) -> str | None:
    if not asset_file.exists():
        return None
    return _normalize(asset_file.read_text(encoding="utf-8"))


def _print_diff(name_a: str, body_a: str, name_b: str, body_b: str) -> None:
    print(f"\n--- {name_a} (canonical)", file=sys.stderr)
    print(f"+++ {name_b} (drifted)", file=sys.stderr)
    diff = difflib.unified_diff(
        body_a.splitlines(keepends=False),
        body_b.splitlines(keepends=False),
        fromfile=name_a,
        tofile=name_b,
        n=1,
    )
    for line in diff:
        print(line, file=sys.stderr)


def main(argv: list[str]) -> int:
    skill_dir = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parent.parent
    asset = skill_dir / "assets" / "polish-prompt.txt"
    skill_md = skill_dir / "SKILL.md"
    bash_script = skill_dir / "scripts" / "polish-remediation-beads.sh"

    asset_prompt = _extract_asset_prompt(asset)
    skill_prompt = _extract_skill_md_prompt(skill_md) if skill_md.exists() else None
    bash_prompt = _extract_bash_prompt(bash_script) if bash_script.exists() else None

    missing: list[str] = []
    if asset_prompt is None:
        missing.append(f"assets/polish-prompt.txt ({asset})")
    if skill_prompt is None:
        missing.append(f"SKILL.md (couldn't find the verbatim blockquote)")
    if bash_prompt is None:
        missing.append(f"scripts/polish-remediation-beads.sh (couldn't find POLISH_PROMPT='...')")

    if missing:
        print("ERROR: polish prompt is missing or unparseable in:", file=sys.stderr)
        for m in missing:
            print(f"  - {m}", file=sys.stderr)
        return 2

    # All three present — verify they match.
    drift = False
    if asset_prompt != skill_prompt:
        _print_diff("assets/polish-prompt.txt", asset_prompt or "", "SKILL.md", skill_prompt or "")
        drift = True
    if asset_prompt != bash_prompt:
        _print_diff("assets/polish-prompt.txt", asset_prompt or "", "scripts/polish-remediation-beads.sh", bash_prompt or "")
        drift = True

    if drift:
        print("\nFAIL: polish prompt has drifted across its three homes.", file=sys.stderr)
        print("Fix: copy the canonical text from assets/polish-prompt.txt into the", file=sys.stderr)
        print("      SKILL.md blockquote and the POLISH_PROMPT='...' bash variable.", file=sys.stderr)
        return 1

    print("OK: polish prompt is identical across all three sources.", file=sys.stderr)
    print(f"     length: {len(asset_prompt or '')} chars", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
