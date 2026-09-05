#!/usr/bin/env python3
"""validate-operators — deep-validate corpus/specs/operator_library.md.

Distinct from validate-corpus.py (which only checks that marker counts match);
this script enforces operator-card structural invariants:

  1. Every <!-- OPERATOR-START id=X --> is matched by <!-- OPERATOR-END id=X -->
     in the right order (no nesting, no interleaving).  Markers inside fenced
     ``` code blocks are skipped — those are examples, not real cards.
  2. Each operator card has the canonical sections: heading line, Trigger,
     Prompt module (with fenced code block), Exit criterion, Failure modes,
     Anchors.  "Composes with" is optional.
  3. Operator ids and symbols are each unique across the library.
  4. Anchors that cite Q-NNN / E-NN ids are cross-checked against
     corpus/quote_bank/quote_bank.md.  Non-Q/E anchors (e.g., "the rch skill's
     PHASES.md") are accepted as legitimate external evidence.

Usage:
    ./validate-operators.py <skill-or-workspace-dir>

Exit codes:
    0 — every invariant passed
    1 — at least one invariant failed (specific lines reported)
    2 — usage error / operator_library.md missing
"""
import re
import sys
from pathlib import Path


REQUIRED_SECTIONS = [
    "**Trigger:**",
    "**Prompt module:**",
    "**Exit criterion:**",
    "**Failure modes:**",
    "**Anchors:**",
]

MARKER_RE = re.compile(
    r"<!-- OPERATOR-(START|END) id=([A-Za-z0-9._-]+)(?: symbol=([^\s>-]+))? -->"
)


def find_markers(raw_text: str) -> list[tuple[str, str, str | None, int, int]]:
    """Walk the file line by line, tracking ``` fence state.

    Returns a list of (kind, id, symbol, line_no, char_offset) for every marker
    found OUTSIDE a code fence.  Line numbers are 1-based, matching what an
    editor would show.
    """
    markers: list[tuple[str, str, str | None, int, int]] = []
    in_fence = False
    line_no = 0
    offset = 0
    for line in raw_text.splitlines(keepends=True):
        line_no += 1
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            offset += len(line)
            continue
        if not in_fence:
            for m in MARKER_RE.finditer(line):
                markers.append(
                    (m.group(1), m.group(2), m.group(3), line_no, offset + m.start())
                )
        offset += len(line)
    return markers


def find_quote_ids(quote_bank_text: str) -> set[str]:
    """Extract every Q-NNN / E-NN id declared in the quote bank.

    The corpus convention is `<!-- Q id=Q-001 -->` — the `Q-`/`E-` prefix is
    INSIDE the id value, not added on top of the `Q id=` keyword.  So we
    capture the value as-is.
    """
    ids: set[str] = set()
    for m in re.finditer(r"<!-- [QE] id=([A-Za-z0-9._-]+)", quote_bank_text):
        ids.add(m.group(1))
    return ids


def validate(root: Path) -> int:
    op_path = root / "corpus" / "specs" / "operator_library.md"
    qb_path = root / "corpus" / "quote_bank" / "quote_bank.md"
    cass_path = root / "corpus" / "primary_sources" / "cass_quotes.md"
    if not op_path.is_file():
        print(f"[ERR] operator_library.md not found: {op_path}", file=sys.stderr)
        return 2
    # Anchor cross-check sources: the curated quote_bank.md (stable Q-NNN /
    # E-NN anchors) AND the primary-source cass_quotes.md (raw user quotes
    # mined from cass sessions, also Q-NNN format).  Operator cards may cite
    # either; failing because a Q-id is "only" in cass_quotes.md (the primary
    # source) would be wrong.
    known_quote_ids: set[str] = set()
    sources_checked: list[Path] = []
    if qb_path.is_file():
        known_quote_ids |= find_quote_ids(qb_path.read_text())
        sources_checked.append(qb_path)
    if cass_path.is_file():
        # cass_quotes.md uses `## Q-NNN` headings rather than `<!-- Q id=NNN -->`
        # markers; collect both forms.
        cass_text = cass_path.read_text()
        known_quote_ids |= find_quote_ids(cass_text)
        for m in re.finditer(r"^##\s+([QE]-[A-Za-z0-9._-]+)\b", cass_text, re.M):
            known_quote_ids.add(m.group(1))
        sources_checked.append(cass_path)
    if not sources_checked:
        print(
            f"[INFO] neither {qb_path} nor {cass_path} found — anchor refs will not be cross-checked",
            file=sys.stderr,
        )

    raw_text = op_path.read_text()
    raw_lines = raw_text.splitlines()
    markers = find_markers(raw_text)

    issues = 0

    # --- 1. Balanced + non-nested markers + uniqueness ------------------------
    open_stack: list[tuple[str, int]] = []   # (id, line_no)
    seen_ids: set[str] = set()
    symbol_to_id: dict[str, str] = {}
    operators: list[dict] = []
    current_card: dict | None = None

    for kind, oid, sym, line_no, _ in markers:
        if kind == "START":
            if open_stack:
                pending = open_stack[-1][0]
                print(
                    f"[ERR] {op_path}:{line_no}: OPERATOR-START id={oid} inside open operator id={pending}",
                    file=sys.stderr,
                )
                issues += 1
            if oid in seen_ids:
                print(f"[ERR] {op_path}:{line_no}: duplicate operator id={oid}", file=sys.stderr)
                issues += 1
            seen_ids.add(oid)
            if sym is not None:
                if sym in symbol_to_id and symbol_to_id[sym] != oid:
                    print(
                        f"[ERR] {op_path}:{line_no}: symbol '{sym}' reused (operators {symbol_to_id[sym]} and {oid})",
                        file=sys.stderr,
                    )
                    issues += 1
                symbol_to_id[sym] = oid
            open_stack.append((oid, line_no))
            current_card = {
                "id": oid,
                "symbol": sym,
                "start_line": line_no,
                "end_line": None,
            }
            operators.append(current_card)
        else:   # END
            if not open_stack:
                print(
                    f"[ERR] {op_path}:{line_no}: OPERATOR-END id={oid} with no matching START",
                    file=sys.stderr,
                )
                issues += 1
                continue
            expected, _ = open_stack.pop()
            if expected != oid:
                print(
                    f"[ERR] {op_path}:{line_no}: OPERATOR-END id={oid} does not match open id={expected}",
                    file=sys.stderr,
                )
                issues += 1
            if current_card is not None and current_card["id"] == oid:
                current_card["end_line"] = line_no
                current_card = None

    for pending, ln in open_stack:
        print(f"[ERR] {op_path}:{ln}: operator id={pending} never closed", file=sys.stderr)
        issues += 1

    # --- 2. Per-card structural requirements ----------------------------------
    # raw_lines is 0-indexed; line numbers from find_markers are 1-based.
    # Body is everything BETWEEN the START and END markers (exclusive).
    for card in operators:
        if card["start_line"] is None or card["end_line"] is None:
            continue   # already reported above
        body = "\n".join(raw_lines[card["start_line"]:card["end_line"] - 1])

        # 2a. Heading line right after the START marker.
        # The canonical heading is `## <symbol> <ID> — <description>`.  The em
        # dash (U+2014) is required; some legacy cards use `--` or `-` instead,
        # so accept any of " — ", " -- ", " - " as separators.
        if not re.search(r"^## .+?\s+[—\-–]+\s+.+$", body, re.M):
            print(
                f"[ERR] {op_path}:{card['start_line']}: operator id={card['id']} missing canonical "
                f"`## <symbol> <ID> — <description>` heading",
                file=sys.stderr,
            )
            issues += 1

        # 2b. Required sections present.
        for required in REQUIRED_SECTIONS:
            if required not in body:
                print(
                    f"[ERR] {op_path}:{card['start_line']}: operator id={card['id']} missing section {required}",
                    file=sys.stderr,
                )
                issues += 1

        # 2c. Prompt module has a fenced code block.
        if "**Prompt module:**" in body:
            after = body.split("**Prompt module:**", 1)[1]
            # Look ahead within ~30 lines for an opening fence.
            window = "\n".join(after.splitlines()[:30])
            if "```" not in window:
                print(
                    f"[ERR] {op_path}:{card['start_line']}: operator id={card['id']} "
                    f"has Prompt module but no fenced code block follows",
                    file=sys.stderr,
                )
                issues += 1

        # 2d. Anchors cross-check (cite-able evidence is fine; we only flag
        # Q-/E- refs that DON'T resolve in quote_bank.md, never the absence of
        # Q-/E- refs — an invariant may legitimately cite "the rch skill's
        # PHASES.md" which has no Q-/E- identifier).
        if known_quote_ids:
            anchor_line = re.search(r"\*\*Anchors:\*\*\s*(.+)$", body, re.M)
            if anchor_line:
                # Capture refs but trim a trailing punctuation (period, comma,
                # close-paren) that wasn't part of the id.
                for ref in re.findall(r"\b([QE]-[A-Za-z0-9._-]+)", anchor_line.group(1)):
                    ref_clean = ref.rstrip(".,;:)]")
                    if ref_clean in known_quote_ids:
                        continue
                    # Range form like E-001..E-011: check both endpoints exist.
                    range_m = re.match(r"^([QE])-([A-Za-z0-9_-]+)\.\.([QE])-([A-Za-z0-9_-]+)$", ref_clean)
                    if range_m:
                        lo, hi = f"{range_m.group(1)}-{range_m.group(2)}", f"{range_m.group(3)}-{range_m.group(4)}"
                        if lo in known_quote_ids and hi in known_quote_ids:
                            continue
                    print(
                        f"[WARN] {op_path}:{card['start_line']}: operator id={card['id']} "
                        f"Anchors refers to id '{ref_clean}' not found in quote_bank.md or cass_quotes.md",
                        file=sys.stderr,
                    )

    # --- 3. Summary ----------------------------------------------------------
    if issues == 0:
        print(f"[OK] {len(operators)} operator card(s) validated; markers balanced; structure complete.")
        return 0
    print(f"[FAIL] {issues} structural issue(s) — see [ERR] lines above.", file=sys.stderr)
    return 1


def _print_usage(stream) -> None:
    print("Usage: validate-operators.py <skill-or-workspace-dir>", file=stream)
    print("  Validates corpus/specs/operator_library.md structural invariants.", file=stream)


def main() -> int:
    # --help is success; missing/extra args is a usage error.
    if len(sys.argv) >= 2 and sys.argv[1] in ("-h", "--help"):
        _print_usage(sys.stdout)
        return 0
    if len(sys.argv) != 2:
        _print_usage(sys.stderr)
        return 2
    root = Path(sys.argv[1])
    if not root.is_dir():
        print(f"Not a directory: {root}", file=sys.stderr)
        return 2
    return validate(root)


if __name__ == "__main__":
    sys.exit(main())
