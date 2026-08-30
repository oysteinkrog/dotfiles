"""Try a candidate regex for one rule against its cases, without editing rules.py.

    python evals/try_pattern.py em-dash '[—–](?![0-9])'
    python evals/try_pattern.py em-dash --file /tmp/candidate.txt      # pattern in a file
    python evals/try_pattern.py em-dash --pattern-from-rules          # what is in rules.py now

Prints recall, false alarms, precision, and every case that went wrong.
Add --raw to match against the source as written; the default blanks code
fences, inline code, URLs, paths and link targets first, which is what the
scorer does for a prose rule.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "tool" / "src"))

from plainlang.rules import BY_ID  # noqa: E402
from plainlang.segment import in_spans, mask_non_prose, quote_spans  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rule")
    ap.add_argument("pattern", nargs="?")
    ap.add_argument("--file", type=Path, help="read the pattern from this file")
    ap.add_argument("--pattern-from-rules", action="store_true")
    ap.add_argument("--raw", action="store_true")
    ap.add_argument("--cases", type=Path, default=HERE / "data" / "rule_cases.json")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    if args.pattern_from_rules:
        rule = BY_ID.get(args.rule)
        if not rule:
            print(f"no rule {args.rule}", file=sys.stderr)
            return 2
        rx = rule.pattern
        raw = rule.surface == "raw"
    else:
        pat = args.file.read_text(encoding="utf-8").strip() if args.file else args.pattern
        if not pat:
            print("give a pattern, --file, or --pattern-from-rules", file=sys.stderr)
            return 2
        try:
            rx = re.compile(pat, re.I)
        except re.error as exc:
            print(f"bad regex: {exc}", file=sys.stderr)
            return 2
        raw = args.raw

    data = json.loads(args.cases.read_text(encoding="utf-8"))
    entry = next((e for e in data["rules"] if e["id"] == args.rule), None)
    if not entry:
        print(f"no cases for {args.rule}", file=sys.stderr)
        return 2

    def hit(text: str) -> bool:
        if raw:
            return bool(rx.search(text))
        quoted = quote_spans(text)
        return any(not in_spans(m.start(), quoted) for m in rx.finditer(mask_non_prose(text)[0]))

    pos = entry.get("positives", [])
    neg = entry.get("negatives", []) + entry.get("attacks", [])
    tp = [t for t in pos if hit(t)]
    missed = [t for t in pos if not hit(t)]
    fp = [t for t in neg if hit(t)]

    recall = len(tp) / len(pos) if pos else float("nan")
    precision = len(tp) / (len(tp) + len(fp)) if (tp or fp) else float("nan")
    print(f"{args.rule}: recall {len(tp)}/{len(pos)} = {recall:.2f}   "
          f"false alarms {len(fp)}/{len(neg)}   precision {precision:.2f}   surface={'raw' if raw else 'prose'}")
    if not args.quiet:
        for t in missed:
            print(f"  MISSED  {t[:150]}")
        for t in fp:
            print(f"  FALSE+  {t[:150]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
