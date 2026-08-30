"""Choose the gate threshold from data, not from taste.

The gate has to stop bad writing without blocking work that was already fine.
That is an operating point on a curve, so pick it the way you would pick any
operating point: fix the false-alarm budget you can live with, then take the
threshold that catches the most slop inside it.

    python evals/threshold.py --budget 0.10
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "tool" / "src"))
sys.path.insert(0, str(HERE))

from plainlang.lexicon import Lexicon  # noqa: E402
from plainlang.model import Scorer, Weights  # noqa: E402
from run import attach_judgements, load_variants  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=HERE / "data" / "variants.json")
    ap.add_argument("--human", type=Path, default=HERE / "data" / "human_writing.json")
    ap.add_argument("--weights", type=Path, default=None)
    ap.add_argument("--budget", type=float, default=0.10,
                    help="share of untouched repo prose the gate may stop on score alone")
    ap.add_argument("--write", type=Path, default=None, help="save the chosen threshold into this weights file")
    args = ap.parse_args()

    judged = json.loads(args.data.read_text(encoding="utf-8"))
    variants = load_variants(args.data)
    attach_judgements(variants, judged)
    chat = json.loads(args.human.read_text(encoding="utf-8"))

    w = Weights.load(args.weights)
    scorer = Scorer(w, Lexicon(mode="full"))

    FLOOR = 40  # the hook's own minimum; shorter text is never gated
    sets: dict[str, list[tuple[float, bool]]] = {}
    for reg in ("plain", "wild", "slop"):
        sets[reg] = []
        for v in variants:
            text = v.get(reg) or ""
            if not text.strip():
                continue
            rep = scorer.score(text)
            if rep.words < FLOOR:
                continue
            sets[reg].append((rep.score, bool(rep.stats["errors"])))
    sets["chat"] = []
    for c in chat:
        rep = scorer.score(c["text"])
        if rep.words >= FLOOR:
            sets["chat"].append((rep.score, bool(rep.stats["errors"])))

    def rate(reg: str, t: float, *, with_errors: bool) -> float:
        rows = sets[reg]
        if not rows:
            return float("nan")
        return sum(1 for s, e in rows if s < t or (with_errors and e)) / len(rows)

    print("Threshold sweep. 'stopped' means the gate would refuse the text.\n")
    print(f"{'min score':>10}{'slop stopped':>14}{'plain stopped':>15}{'repo prose':>12}{'chat':>8}")
    best = None
    for t in [x / 2 for x in range(30, 180)]:
        slop = rate("slop", t, with_errors=True)
        plain = rate("plain", t, with_errors=False)
        wild = rate("wild", t, with_errors=False)
        if int(t * 2) % 10 == 0:
            print(f"{t:>10.0f}{slop:>13.1%}{plain:>15.1%}{wild:>12.1%}{rate('chat', t, with_errors=False):>8.1%}")
        # Hard rules already stop nearly all slop, so slop-stopped ties at 100%
        # across the range. Break the tie toward the highest threshold inside
        # the budget: same cost in false alarms, more signal.
        if wild <= args.budget and (best is None or (slop, t) >= (best[1], best[0])):
            best = (t, slop, plain, wild)

    print()
    if best is None:
        print(f"No threshold keeps repo-prose refusals under {args.budget:.0%} on score alone.")
        return 1
    t, slop, plain, wild = best
    print(f"Chosen: min_score = {t:.0f}")
    print(f"  stops {slop:.1%} of slop (score or hard rule)")
    print(f"  stops {plain:.1%} of the plain rewrites on score alone")
    print(f"  stops {wild:.1%} of untouched repo prose on score alone (budget {args.budget:.0%})")

    # Hard rules are separate from the score, so report their share on their own.
    for reg in ("slop", "plain", "wild", "chat"):
        errs = sum(1 for _, e in sets[reg] if e) / max(1, len(sets[reg]))
        print(f"  hard-rule hits in {reg:<6}{errs:>7.1%}")

    if args.write:
        w.min_score = t
        w.save(args.write)
        print(f"\nwrote min_score={t:.0f} to {args.write}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
