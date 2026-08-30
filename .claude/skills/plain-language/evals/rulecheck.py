"""Precision and recall for every pattern rule, on hand-built cases.

The A/B corpus only exercises the rules the slop generator happened to use.
This runs each rule against cases written for it: passages where it should
fire, near-miss passages where it must not, and adversarial passages written
to make it misfire on legitimate technical writing.

    python evals/rulecheck.py            # summary
    python evals/rulecheck.py --show em-dash   # every miss and false alarm
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "tool" / "src"))

from plainlang.lexicon import Lexicon  # noqa: E402
from plainlang.model import Scorer, Weights  # noqa: E402


def fires(scorer: Scorer, rule_id: str, text: str) -> bool:
    return any(f.rule == rule_id for f in scorer.score(text).findings)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=Path, default=HERE / "data" / "rule_cases.json")
    ap.add_argument("--weights", type=Path, default=None)
    ap.add_argument("--show", default=None, help="print every failing case for this rule id")
    ap.add_argument("--min-precision", type=float, default=0.90)
    ap.add_argument("--min-recall", type=float, default=0.60)
    args = ap.parse_args()

    data = json.loads(args.cases.read_text(encoding="utf-8"))
    scorer = Scorer(Weights.load(args.weights), Lexicon(mode="full"))

    print(f"{'rule':<22}{'recall':>9}{'clean':>8}{'attack':>8}{'precision':>11}  verdict")
    bad = []
    for entry in data["rules"]:
        rid = entry["id"]
        pos = entry.get("positives", [])
        neg = entry.get("negatives", [])
        atk = entry.get("attacks", [])
        tp = sum(1 for t in pos if fires(scorer, rid, t))
        fp_neg = sum(1 for t in neg if fires(scorer, rid, t))
        fp_atk = sum(1 for t in atk if fires(scorer, rid, t))
        recall = tp / len(pos) if pos else float("nan")
        fp = fp_neg + fp_atk
        precision = tp / (tp + fp) if (tp + fp) else float("nan")
        verdict = "ok"
        if precision == precision and precision < args.min_precision:
            verdict = "too many false alarms"
            bad.append(rid)
        elif recall == recall and recall < args.min_recall:
            verdict = "misses real cases"
            bad.append(rid)
        print(f"{rid:<22}{tp:>4}/{len(pos):<4}{fp_neg:>5}/{len(neg):<3}{fp_atk:>4}/{len(atk):<3}"
              f"{precision:>11.2f}  {verdict}")

        if args.show == rid:
            for t in pos:
                if not fires(scorer, rid, t):
                    print(f"   MISSED   {t[:110]}")
            for t in neg + atk:
                if fires(scorer, rid, t):
                    print(f"   FALSE +  {t[:110]}")

    print(f"\n{len(bad)} rule(s) below target: {', '.join(bad) if bad else 'none'}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
