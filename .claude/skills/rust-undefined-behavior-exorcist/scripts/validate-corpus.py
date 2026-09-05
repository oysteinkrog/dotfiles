#!/usr/bin/env python3
"""validate-corpus — checks the Track-A corpus invariants.

Usage:
    ./validate-corpus.py <skill-or-workspace-dir>
"""
import re
import sys
from pathlib import Path


def strip_code_blocks(text: str) -> str:
    """Remove fenced code blocks so example markers inside them aren't counted."""
    return re.sub(r"```.*?```", "", text, flags=re.S)


def validate(root: Path) -> int:
    issues = 0
    # 1. Quote bank: every Q-NNN has a source line
    qb = root / "corpus" / "quote_bank" / "quote_bank.md"
    if qb.exists():
        text = strip_code_blocks(qb.read_text())
        # IDs end at space, `-`, or `>` (so embedded `id=NNN -->` is captured cleanly)
        anchors = re.findall(r"<!-- Q id=([A-Za-z0-9._-]+)", text)
        closes = re.findall(r"<!-- /Q id=([A-Za-z0-9._-]+)", text)
        if sorted(anchors) != sorted(closes):
            print(f"[ERR] {qb}: marker start/end mismatch: {set(anchors) ^ set(closes)}")
            issues += 1
        for a in anchors:
            block = re.search(rf"<!-- Q id={re.escape(a)}.*?<!-- /Q id={re.escape(a)} -->", text, re.S)
            if block and "**Source:**" not in block.group() and "**Citation:**" not in block.group() and "source=" not in block.group():
                print(f"[WARN] Q-{a}: no Source/Citation field detected (info only)")
    else:
        print(f"[INFO] {qb} not found (corpus may be in workspace, not skill)")

    # 2. Kernel: every invariant cites anchors
    k = root / "corpus" / "specs" / "triangulated_kernel.md"
    if k.exists():
        text = k.read_text()
        if "<!-- KERNEL-START -->" not in text or "<!-- KERNEL-END -->" not in text:
            print(f"[ERR] {k}: missing KERNEL-START / KERNEL-END markers")
            issues += 1
        # Each ## Iₙ heading should have an **Anchors:** line
        kernel_section = re.search(r"<!-- KERNEL-START -->(.*)<!-- KERNEL-END -->", text, re.S)
        if kernel_section:
            for m in re.finditer(r"^## I\d+\..*?(?=^## |\Z)", kernel_section.group(1), re.M | re.S):
                section = m.group()
                if "**Anchors:**" not in section:
                    head = section.split("\n", 1)[0]
                    print(f"[WARN] {k}: invariant '{head}' missing **Anchors:** line")

    # 3. Operator library markers (strip code blocks so example invocations
    # inside ```bash fences aren't counted as real markers)
    op = root / "corpus" / "specs" / "operator_library.md"
    if op.exists():
        text = strip_code_blocks(op.read_text())
        starts = re.findall(r"<!-- OPERATOR-START id=([A-Za-z0-9._-]+)", text)
        ends = re.findall(r"<!-- OPERATOR-END id=([A-Za-z0-9._-]+)", text)
        if sorted(starts) != sorted(ends):
            print(f"[ERR] {op}: operator marker start/end mismatch: {set(starts) ^ set(ends)}")
            issues += 1

    if issues == 0:
        print("[OK] corpus validation passed (some [INFO]/[WARN] notes may exist)")
    return 1 if issues else 0


if __name__ == "__main__":
    # Handle --help explicitly; passing it as a positional would silently treat
    # "--help" as the workspace dir and emit a [INFO] line that looks like real
    # validation output.
    if len(sys.argv) >= 2 and sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        sys.exit(0)
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    sys.exit(validate(root))
