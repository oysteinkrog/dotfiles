"""Check the fence scanner in segment.py against a CommonMark parser.

The scanner decides which lines are code and which are prose, so a mistake
either hides prose from scoring or scores code as prose. Five rounds of review
each found a new CommonMark case by hand. This compares the scanner with
markdown-it-py on random documents built from lists, nested lists, fences
(indented, unclosed, on the marker line, with odd info strings) and indented
code, and optionally on real files.

markdown-it-py is not a dependency of the tool, so run it with:

    uv run --with markdown-it-py evals/fence_fuzz.py [N] [files...]

Blank lines are ignored, since they hold no prose. Block quotes are not
generated, because the scanner does not model them. On 2026-10-14, with
headings, thematic breaks, lazy continuation and CRLF in the mix, the scanner
hid prose in 12 of 20,000 random documents and the regex it replaced in 3,075.
The 12 need deeper CommonMark container rules. Real files: none of 8,018.
"""

from __future__ import annotations

import random
import sys
from pathlib import Path

from markdown_it import MarkdownIt

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tool" / "src"))
from plainlang.segment import _FENCE  # noqa: E402

_MD = MarkdownIt("commonmark")
FENCES = ["```", "````", "~~~"]
INFOS = ["", "sh", "bash", "python title", "x`y"]


def reference_lines(text: str) -> set[int]:
    out: set[int] = set()
    for tok in _MD.parse(text):
        if tok.type == "fence" and tok.map:
            out.update(range(tok.map[0], tok.map[1]))
    return out


def scanner_lines(text: str) -> set[int]:
    out: set[int] = set()
    for m in _FENCE.finditer(text):
        s, e = m.span()
        first = text.count("\n", 0, s)
        last = text.count("\n", 0, max(s, e - 1)) if e > s else first
        out.update(range(first, last + 1))
    return out


def compare(text: str) -> tuple[set[int], set[int]]:
    """Return (code we score as prose, prose we hide), non-blank lines only."""
    nonblank = {i for i, line in enumerate(text.split("\n")) if line.strip()}
    ref, ours = reference_lines(text), scanner_lines(text)
    return (ref - ours) & nonblank, (ours - ref) & nonblank


def block(rng: random.Random, indent: str) -> list[str]:
    kind = rng.choice(
        [
            "para",
            "para",
            "fence",
            "fence",
            "unclosed",
            "indented",
            "list",
            "marker_fence",
            "heading",
            "rule",
        ]
    )
    if kind == "heading":
        return [indent + rng.choice(["# Title", "## Section", "### Sub"])]
    if kind == "rule":
        return [indent + rng.choice(["---", "***", "* * *"])]
    if kind == "para":
        return [
            indent
            + rng.choice(
                ["Plain words here.", "Another sentence.", "Signed, [your name]"]
            )
        ]
    if kind in ("fence", "unclosed"):
        f = rng.choice(FENCES)
        info = rng.choice(INFOS) if f[0] == "`" else rng.choice(INFOS[:4])
        pad = " " * rng.choice([0, 0, 1, 2, 3, 4])
        lines = [
            indent + pad + f + info,
            indent
            + " " * rng.choice([0, 2, 4])
            + rng.choice(["ls -la", "```", "    ```", "x = 1"]),
        ]
        if kind == "fence":
            lines.append(
                indent
                + " " * rng.choice([0, 0, 1, 3, 4])
                + f
                + rng.choice(["", "`"]) * (f[0] == "`")
            )
        return lines
    if kind == "indented":
        return [
            "",
            indent + "    " + rng.choice(["```not a fence", "code line", "~~~"]),
        ]
    if kind == "marker_fence":
        f = rng.choice(FENCES)
        return [indent + "- " + f + "sh", indent + "  echo hi", indent + "  " + f]
    marker = rng.choice(["- ", "* ", "1. ", "10. "])
    lines = [indent + marker + "Item text."]
    child = indent + " " * len(marker)
    for _ in range(rng.randint(0, 2)):
        if rng.random() < 0.7:  # else no blank line: exercises lazy continuation
            lines.append("")
        lines.extend(block(rng, child) if len(child) < 12 else [child + "Deep prose."])
    return lines


def make(rng: random.Random) -> str:
    out: list[str] = []
    for _ in range(rng.randint(1, 6)):
        out.extend(block(rng, ""))
        if rng.random() < 0.8:
            out.append("")
    newline = "\r\n" if rng.random() < 0.2 else "\n"
    return newline.join(out) + newline


def main() -> int:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 5000
    rng = random.Random(1234)
    hid = scored = shown = 0
    for k in range(n):
        doc = make(rng)
        code_scored, prose_hidden = compare(doc)
        hid += bool(prose_hidden)
        scored += bool(code_scored)
        if (prose_hidden or code_scored) and shown < 3:
            shown += 1
            print(
                f"--- doc {k}: prose hidden {sorted(prose_hidden)}, "
                f"code scored {sorted(code_scored)}"
            )
            for i, line in enumerate(doc.split("\n")):
                print(f"{i:3} |{line}")
    print(f"random: prose hidden in {hid}, code scored in {scored}, of {n} documents")

    files = sys.argv[2:]
    real = 0
    for f in files:
        try:
            text = Path(f).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        _, prose_hidden = compare(text)
        if prose_hidden:
            real += 1
            print(
                f"real: {f}: lines hidden that CommonMark does not treat as a fence: "
                f"{sorted(prose_hidden)[:5]} (check: an HTML block is not prose either)"
            )
    if files:
        print(f"real: {real} of {len(files)} files differ")
    return 1 if hid else 0


if __name__ == "__main__":
    raise SystemExit(main())
