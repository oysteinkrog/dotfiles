#!/usr/bin/env python3
"""validate-quote-bank.py — Lint references/QUOTE-BANK.md.

The quote bank anchors generic failure-mode patterns to verbatim session
quotes. A pattern without a quote is a vibe; a quote without a stable anchor
can't be cross-referenced. We enforce both.

Adapted from /operationalizing-expertise's quote-bank contract.

Each quote MUST have:
  - A stable anchor (e.g., `[Q-NN]` or `<a id="q-NN">`)
  - A source attribution line (file/session/date)
  - At least one tag (`#tag-name`) for retrieval
  - A verbatim quote block (markdown blockquote `>` or fenced)

Optional but recommended:
  - Linked failure-mode pattern (`See: FAILURE-MODES.md#pattern-name`)

Usage:
    validate-quote-bank.py [path/to/QUOTE-BANK.md] [--strict]
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

ANCHOR_RE = re.compile(r"\[Q-(\d+)\]|<a\s+id=[\"']q-(\d+)[\"']", re.I)
# `Pattern N` heading itself acts as a stable anchor in markdown auto-id'd
# headings (`#pattern-n`), so allow that as an implicit anchor form for
# QUOTE-BANK.md sections that follow the documented Pattern-N heading
# convention. Without this, validate-quote-bank rejects every pattern even
# though the docs cross-reference them by their heading anchor everywhere.
PATTERN_HEADING_ANCHOR_RE = re.compile(r"^Pattern\s+(\d+)", re.I)
TAG_RE = re.compile(r"#[a-z][a-z0-9-]+")
QUOTE_BLOCK_RE = re.compile(r"^>", re.M)
# Accept BOTH plain `Source: ...` and the markdown-blockquote+bold form
# `> **Source**: ...` actually used throughout QUOTE-BANK.md. The previous
# regex only matched the plain form, falsely flagging every shipped
# pattern as missing source attribution.
SOURCE_RE = re.compile(r"^\s*(?:>\s*)?\**Source\**\s*[:*]\s*", re.M | re.I)
LINKED_PATTERN_RE = re.compile(r"FAILURE-MODES\.md#", re.I)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("path", nargs="?", default=None)
    p.add_argument("--strict", action="store_true")
    args = p.parse_args()

    path = Path(args.path) if args.path else (
        Path(__file__).resolve().parent.parent / "references" / "QUOTE-BANK.md"
    )
    if not path.exists():
        print(f"ERROR: {path} not found", file=sys.stderr)
        return 2
    text = path.read_text()

    errors: list[str] = []
    warnings: list[str] = []

    sections = re.split(r"^##+\s+", text, flags=re.M)[1:]
    if not sections:
        warnings.append("no quote sections (## headings) detected — quote bank may be empty")

    # Only enforce the quote-card contract on sections that actually claim to
    # be a pattern-anchored quote: heading starts with "Pattern N", "Q-N", or
    # contains an explicit [Q-N] anchor. Other sections (e.g. "How to use",
    # "Quote provenance tracking", "Mining methodology") are meta-docs and
    # should not be linted for source/blockquote/tag presence.
    PATTERN_SECTION_RE = re.compile(
        r"^(?:Pattern\s+\d+|Q-\d+|\[Q-\d+\])\b", re.I
    )

    seen_anchors: list[str] = []
    quote_sections = 0
    for i, sec in enumerate(sections):
        head = sec.split("\n", 1)[0].strip()
        is_quote_card = bool(PATTERN_SECTION_RE.match(head)) or bool(ANCHOR_RE.search(sec))
        if not is_quote_card:
            continue  # meta section — skip strict linting
        quote_sections += 1
        anchors = ANCHOR_RE.findall(sec)
        anchor_ids = [a[0] or a[1] for a in anchors]
        # Implicit `Pattern N` heading also counts as a stable anchor —
        # markdown renderers auto-generate `#pattern-n` ids from headings.
        if not anchor_ids:
            heading_match = PATTERN_HEADING_ANCHOR_RE.match(head)
            if heading_match:
                anchor_ids = [f"heading-pattern-{heading_match.group(1)}"]
        if not anchor_ids:
            warnings.append(f"section '{head[:60]}': no [Q-NN] / <a id='q-NN'> / Pattern-N heading anchor")
        else:
            for aid in anchor_ids:
                seen_anchors.append(aid)
        tags = TAG_RE.findall(sec)
        if not tags:
            warnings.append(f"section '{head[:60]}': no #tag for retrieval")
        if not QUOTE_BLOCK_RE.search(sec):
            errors.append(f"section '{head[:60]}': no markdown blockquote (lines starting with '>')")
        if not SOURCE_RE.search(sec):
            warnings.append(f"section '{head[:60]}': no 'Source:' attribution line")
        if not LINKED_PATTERN_RE.search(sec):
            warnings.append(f"section '{head[:60]}': no link to FAILURE-MODES.md pattern (orphan quote?)")

    dup = [a for a, c in Counter(seen_anchors).items() if c > 1]
    if dup:
        errors.append(f"duplicate anchor ids: {dup}")

    if args.strict:
        errors.extend(warnings)
        warnings = []
    for w in warnings:
        print(f"WARN:  {w}")
    for e in errors:
        print(f"ERROR: {e}")
    print(f"\nValidation: {quote_sections} quote-card section(s) (of {len(sections)} total), "
          f"{len(seen_anchors)} anchor(s), {len(errors)} error(s), {len(warnings)} warning(s)",
          file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
