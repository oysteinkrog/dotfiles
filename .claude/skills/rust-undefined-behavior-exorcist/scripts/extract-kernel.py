#!/usr/bin/env python3
"""extract-kernel — extract + validate the triangulated kernel.

The kernel (corpus/specs/triangulated_kernel.md) holds the consensus invariants
across multi-model distillations.  Disagreements live OUTSIDE the
<!-- KERNEL-START --> / <!-- KERNEL-END --> markers in DISPUTED / UNIQUE
sections; only consensus is kept between markers.

This script:

  1. Extracts text between the two kernel markers.
  2. Validates each `## IN.` invariant has an **Anchors:** line (the form of
     the anchor — Q-NNN, E-NN, or an external skill reference — is not
     enforced; presence of *some* anchor line is).
  3. Warns about gaps in invariant numbering.
  4. Writes the kernel to stdout (default) or to a file (--output).

Usage:
    ./extract-kernel.py <skill-or-workspace-dir> [--output <path>]

Exit codes:
    0 — extraction completed; every invariant has an **Anchors:** line
    1 — extracted but ≥1 invariant has no **Anchors:** line
    2 — usage error / triangulated_kernel.md missing / markers absent
"""
import argparse
import re
import sys
from pathlib import Path


def extract(root: Path, output: Path | None) -> int:
    k_path = root / "corpus" / "specs" / "triangulated_kernel.md"
    if not k_path.is_file():
        print(f"[ERR] triangulated_kernel.md not found: {k_path}", file=sys.stderr)
        return 2

    text = k_path.read_text()
    m = re.search(r"<!-- KERNEL-START -->\s*\n(.*?)\n<!-- KERNEL-END -->", text, flags=re.S)
    if not m:
        print(f"[ERR] {k_path}: missing KERNEL-START / KERNEL-END markers", file=sys.stderr)
        # Helpful: count partial markers so the user sees which side is gone.
        starts = text.count("<!-- KERNEL-START -->")
        ends = text.count("<!-- KERNEL-END -->")
        print(f"  (found {starts} start marker(s) and {ends} end marker(s))", file=sys.stderr)
        return 2
    kernel = m.group(1)

    # Optional: emit to stdout or write to a file.
    if output is not None:
        output.write_text(kernel + "\n")
        print(f"Wrote {len(kernel)} chars to {output}", file=sys.stderr)
    else:
        # Stdout output is the kernel content — diagnostics go to stderr.
        print(kernel)

    # --- Validate invariants ---------------------------------------------------
    issues = 0
    # Split at `## IN.` boundaries.  Invariants are sequentially numbered.
    invariant_re = re.compile(r"^## I(\d+)\.\s+(.+?)$", re.M)
    spans: list[tuple[int, int, int, str]] = []   # (idx, span_start, span_end, title)
    for m_ in invariant_re.finditer(kernel):
        idx = int(m_.group(1))
        title = m_.group(2).strip()
        spans.append((idx, m_.start(), -1, title))
    if not spans:
        print(f"[WARN] {k_path}: kernel has no `## IN.` invariants", file=sys.stderr)
    # Compute end offsets (next invariant start or end of kernel)
    for i, (idx, s, _, title) in enumerate(spans):
        end = spans[i + 1][1] if i + 1 < len(spans) else len(kernel)
        spans[i] = (idx, s, end, title)

    # Each invariant must contain an **Anchors:** line.  Q-/E- refs are
    # cross-checked when possible, but non-Q/E anchors (e.g., "the rch skill's
    # PHASES.md") are accepted as legitimate external evidence.
    seen_idxs: set[int] = set()
    for idx, s, e, title in spans:
        if idx in seen_idxs:
            print(f"[ERR] {k_path}: duplicate invariant I{idx}", file=sys.stderr)
            issues += 1
        seen_idxs.add(idx)
        section = kernel[s:e]
        if "**Anchors:**" not in section:
            print(f"[ERR] {k_path}: I{idx} ({title}) missing **Anchors:** line", file=sys.stderr)
            issues += 1

    # Sequential numbering check (I1, I2, ... contiguous).
    if seen_idxs:
        expected = set(range(1, max(seen_idxs) + 1))
        missing = sorted(expected - seen_idxs)
        if missing:
            print(f"[WARN] {k_path}: gaps in invariant numbering: missing {missing}", file=sys.stderr)

    if issues == 0:
        print(f"[OK] kernel extracted: {len(spans)} invariant(s), all with **Anchors:**.", file=sys.stderr)
        return 0
    print(f"[FAIL] {issues} invariant(s) violate the required shape.", file=sys.stderr)
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="extract-kernel.py",
        description="Extract + validate the triangulated kernel.",
    )
    ap.add_argument("root", type=Path, help="skill or workspace directory containing corpus/specs/triangulated_kernel.md")
    ap.add_argument("--output", type=Path, default=None, help="write kernel to this file instead of stdout")
    args = ap.parse_args()
    if not args.root.is_dir():
        print(f"Not a directory: {args.root}", file=sys.stderr)
        return 2
    return extract(args.root, args.output)


if __name__ == "__main__":
    sys.exit(main())
