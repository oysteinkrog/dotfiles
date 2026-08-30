"""Does each rule earn its place?

Two views:

    per-rule hits   how often a rule fires on slop, on the plain rewrite, on
                    untouched repo prose, and on the user's own chat prose.
                    A rule that fires as often on plain writing as on slop is
                    not measuring anything; one that fires only on chat prose
                    is a false-alarm generator.

    leave-one-out   recompute the scorecard with the rule switched off. If the
                    metrics do not move, the rule is not paying for itself.

    python evals/ablate.py                 # per-rule hits, ranked
    python evals/ablate.py --leave-one-out # slower, recomputes the scorecard
"""

from __future__ import annotations

import argparse
import collections
import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "tool" / "src"))
sys.path.insert(0, str(HERE))

from plainlang.lexicon import Lexicon  # noqa: E402
from plainlang.model import Scorer, Weights  # noqa: E402
from plainlang.rules import GROUPS  # noqa: E402
from run import attach_judgements, build_scorecard, load_variants, objective, score_all  # noqa: E402


def hits_by_register(scorer: Scorer, variants: list[dict], chat: list[dict]) -> dict:
    tally: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for v in variants:
        for reg in ("plain", "wild", "slop"):
            text = v.get(reg) or ""
            if not text:
                continue
            for f in scorer.score(text).findings:
                tally[f.rule][reg] += 1
    for c in chat:
        for f in scorer.score(c["text"]).findings:
            tally[f.rule]["chat"] += 1
    return tally


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=HERE / "data" / "variants.json")
    ap.add_argument("--human", type=Path, default=HERE / "data" / "human_writing.json")
    ap.add_argument("--weights", type=Path, default=None)
    ap.add_argument("--leave-one-out", action="store_true")
    ap.add_argument("--groups", action="store_true", help="ablate whole rule groups")
    args = ap.parse_args()

    judged = json.loads(args.data.read_text(encoding="utf-8"))
    variants = load_variants(args.data)
    attach_judgements(variants, judged)
    chat = json.loads(args.human.read_text(encoding="utf-8"))
    base_w = Weights.load(args.weights)
    lex = Lexicon(mode="full")
    scorer = Scorer(copy.deepcopy(base_w), lex)

    tally = hits_by_register(scorer, variants, chat)
    print(f"{'rule':<24}{'slop':>6}{'plain':>7}{'wild':>6}{'chat':>6}   {'precision':>9}  verdict")
    rows = []
    for rule, counts in tally.items():
        slop, plain, wild, ch = counts["slop"], counts["plain"], counts["wild"], counts["chat"]
        clean = plain + wild
        prec = slop / (slop + clean) if (slop + clean) else 0.0
        rows.append((rule, slop, plain, wild, ch, prec))
    rows.sort(key=lambda r: (-r[1], -r[5]))
    for rule, slop, plain, wild, ch, prec in rows:
        if slop == 0 and plain + wild + ch == 0:
            verdict = "never fires"
        elif slop == 0:
            verdict = "fires only on clean text"
        elif prec >= 0.9:
            verdict = "clean signal"
        elif prec >= 0.7:
            verdict = "usable"
        else:
            verdict = "noisy"
        print(f"{rule:<24}{slop:>6}{plain:>7}{wild:>6}{ch:>6}   {prec:>8.2f}   {verdict}")

    if not (args.leave_one_out or args.groups):
        return 0

    base_card = build_scorecard(score_all(scorer, variants, chat), variants, base_w.min_score)
    base_obj = objective(base_card)
    print(f"\nbaseline: objective {base_obj:.4f} auc {base_card.m1_auc_plain_vs_slop:.3f} "
          f"rho {base_card.m2_spearman_judge:.3f} fa {base_card.m3_false_alarm_rate:.1%}")

    targets: list[tuple[str, list[str]]] = []
    if args.groups:
        targets = [(name, [r.id for r in rules]) for name, rules in GROUPS.items()]
    else:
        targets = [(rid, [rid]) for rid, *_ in rows if rid in {r.id for g in GROUPS.values() for r in g}]

    print(f"\n{'switched off':<24}{'d.objective':>12}{'d.auc':>8}{'d.rho':>8}{'d.falsealarm':>13}")
    out = []
    for name, ids in targets:
        w = copy.deepcopy(base_w)
        for rid in ids:
            w.rule_costs[rid] = 0.0
        card = build_scorecard(score_all(Scorer(w, lex), variants, chat), variants, w.min_score)
        d_obj = objective(card) - base_obj
        out.append((name, d_obj, card))
        print(f"{name:<24}{d_obj:>+12.4f}{card.m1_auc_plain_vs_slop - base_card.m1_auc_plain_vs_slop:>+8.3f}"
              f"{card.m2_spearman_judge - base_card.m2_spearman_judge:>+8.3f}"
              f"{card.m3_false_alarm_rate - base_card.m3_false_alarm_rate:>+12.1%}")
    print("\nA positive d.objective means the tool is better WITHOUT that rule.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
