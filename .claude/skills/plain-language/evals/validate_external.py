"""Check the reading-cost model against outside data that has nothing to do with us.

Two datasets, both public:

  CLEAR corpus     4,724 excerpts with a continuous human difficulty rating
                   (BT_easiness) and every classic readability formula already
                   computed on the same text. This answers: does our cost model
                   track human judgement, and does it beat Flesch-Kincaid?

  OneStopEnglish   189 news articles, each rewritten by editors at three
                   levels. This answers: does the score put Elementary above
                   Intermediate above Advanced?

Only the reading-cost half of the model is used here (word cost plus sentence
cost). The AI-tell rules measure a different thing and would be noise on 19th
century fiction.

    python evals/validate_external.py
"""

from __future__ import annotations

import argparse
import csv
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "tool" / "src"))
sys.path.insert(0, str(HERE))

from metrics import bootstrap_ci, sign_test, spearman  # noqa: E402
from plainlang.lexicon import Lexicon  # noqa: E402
from plainlang.model import Scorer, Weights  # noqa: E402

FORMULAS = [
    "Flesch-Reading-Ease",
    "Flesch-Kincaid-Grade-Level",
    "Automated Readability Index",
    "SMOG Readability",
    "New Dale-Chall Readability Formula",
    "CAREC",
]


def cost_rate(scorer: Scorer, text: str) -> float:
    rep = scorer.score(text)
    if not rep.words:
        return 0.0
    return (rep.spend["lexical"] + rep.spend["sentence"]) / rep.words * 100


def run_clear(scorer: Scorer, path: Path, limit: int | None) -> None:
    with path.open(newline="", encoding="utf-8-sig", errors="replace") as fh:
        rows = list(csv.DictReader(fh))
    if limit:
        rows = rows[:limit]
    ease, ours = [], []
    others: dict[str, list[float]] = {f: [] for f in FORMULAS}
    for r in rows:
        text = r.get("Excerpt") or ""
        try:
            bt = float(r["BT_easiness"])
        except (KeyError, TypeError, ValueError):
            continue
        if len(text) < 200:
            continue
        ease.append(bt)
        ours.append(-cost_rate(scorer, text))  # negate: higher = easier, like BT
        for f in FORMULAS:
            try:
                others[f].append(float(r[f]))
            except (KeyError, TypeError, ValueError):
                others[f].append(float("nan"))

    print(f"CLEAR corpus: {len(ease)} excerpts, correlation with the human easiness rating")
    print(f"  {'measure':<38}{'Spearman':>10}   {'95% CI':>16}")

    def report(name: str, xs: list[float]) -> float:
        pairs = [(a, b) for a, b in zip(xs, ease) if a == a]
        if len(pairs) < 30:
            print(f"  {name:<38}{'n/a':>10}")
            return float("nan")
        rho = spearman([p[0] for p in pairs], [p[1] for p in pairs])
        lo, hi = bootstrap_ci(
            list(range(len(pairs))),
            lambda idx: spearman([pairs[i][0] for i in idx], [pairs[i][1] for i in idx]),
            n_boot=300,
        )
        print(f"  {name:<38}{rho:>10.3f}   {lo:>7.3f}-{hi:.3f}")
        return rho

    mine = report("plainlang reading cost (ours)", ours)
    # Some formulas score difficulty and some score ease, so compare magnitudes.
    scored = [(f, report(f, others[f])) for f in FORMULAS]
    named, best = max(((f, abs(r)) for f, r in scored if r == r), key=lambda kv: kv[1], default=("none", float("nan")))
    verdict = "ahead of" if abs(mine) > best else "behind"
    print(f"\n  ours |{abs(mine):.3f}| vs best classic formula {named} |{best:.3f}| "
          f"-> {verdict} it by {abs(abs(mine) - best):.3f}")


def run_onestop(scorer: Scorer, path: Path) -> None:
    by_article: dict[str, dict[str, float]] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        text = d.get("text") or ""
        if len(text) < 200:
            continue
        by_article.setdefault(d["article"], {})[d["level"]] = cost_rate(scorer, text)

    full = {a: lv for a, lv in by_article.items() if {"ele", "int", "adv"} <= set(lv)}
    ele_int = sum(1 for lv in full.values() if lv["ele"] < lv["int"])
    int_adv = sum(1 for lv in full.values() if lv["int"] < lv["adv"])
    ordered = sum(1 for lv in full.values() if lv["ele"] < lv["int"] < lv["adv"])
    n = len(full)
    print(f"\nOneStopEnglish: {n} articles rewritten at three levels (lower cost should mean easier)")
    for label, hits, tot in (
        ("elementary cheaper than intermediate", ele_int, n),
        ("intermediate cheaper than advanced", int_adv, n),
        ("all three in the right order", ordered, n),
    ):
        print(f"  {label:<40}{hits:>4}/{tot}  {hits/tot:>6.1%}  sign test p={sign_test(hits, tot - hits):.2g}")
    for lvl in ("ele", "int", "adv"):
        vals = [lv[lvl] for lv in full.values()]
        print(f"  median cost/100w, {lvl:<4}{statistics.median(vals):>8.2f}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", type=Path, default=None)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--data", type=Path, default=HERE / "data" / "external")
    args = ap.parse_args()

    scorer = Scorer(Weights.load(args.weights), Lexicon(mode="full"))
    clear = args.data / "clear.csv"
    onestop = args.data / "onestop.jsonl"
    if clear.exists():
        run_clear(scorer, clear, args.limit)
    else:
        print(f"missing {clear}")
    if onestop.exists():
        run_onestop(scorer, onestop)
    else:
        print(f"missing {onestop}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
