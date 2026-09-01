"""Score the labelled corpus and print the scorecard.

    python evals/run.py --data evals/data/variants.json
    python evals/run.py --tune --iters 400        # search for better weights
    python evals/run.py --weights data/weights.json --compare data/weights.candidate.json
"""

from __future__ import annotations

import argparse
import copy
import json
import statistics
import sys
from dataclasses import asdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "tool" / "src"))
sys.path.insert(0, str(HERE))

from metrics import Scorecard, auc, bootstrap_ci, sign_test, spearman  # noqa: E402
from plainlang.lexicon import Lexicon  # noqa: E402
from plainlang.model import Scorer, Weights  # noqa: E402


def print_config(scorer, weights, label=""):
    """Say which glossary is in effect, before reporting any number.

    Every number in this file depends on the working directory. `_discover_glossary`
    walks up from it looking for `.plainlang/glossary.txt`, so the same corpus and
    the same weights give different figures depending on where you invoke the
    script. On 2026-09-01 that produced two contradictory-looking readings of the
    same measurement one command apart: run from the monorepo, M3 was 3.4% and
    CLEAR 0.628; run from the skill directory, 8.0% and 0.637. Neither is wrong.
    An eval number that moves with the working directory and does not say so is
    unreviewable.
    """
    from pathlib import Path as _P
    from plainlang.model import _discover_glossary
    project = _discover_glossary()
    print(f"cwd {_P.cwd()}")
    print(f"glossary: {len(scorer.glossary)} terms total, "
          f"{len(project)} from a project .plainlang/glossary.txt")
    print(f"weights: min_score {weights.min_score}, max_errors {weights.max_errors}"
          + (f"  [{label}]" if label else ""))
    print()

REGISTERS = ("plain", "wild", "slop")


def load_variants(path: Path) -> list[dict]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    return raw["variants"] if isinstance(raw, dict) and "variants" in raw else raw


def judge_composite(entry: dict) -> dict[str, float]:
    """Map each register to the judges' quality score: clarity minus AI smell."""
    out: dict[str, list[float]] = {r: [] for r in REGISTERS}
    for panel in ("judgeA", "judgeB"):
        for item in entry.get(panel, []):
            for v in item.get("variants", []):
                reg = v.get("register")
                if reg in out:
                    out[reg].append(v["clarity"] - v["ai_smell"])
    return {r: statistics.mean(v) for r, v in out.items() if v}


def attach_judgements(variants: list[dict], judged: dict) -> None:
    """Turn blind tag letters back into register names."""
    tags = judged.get("tags", ["X", "Y", "Z"])
    by_id = {v["id"]: v for v in variants}
    for panel in ("judgeA", "judgeB"):
        for item in judged.get(panel, []):
            v = by_id.get(item["id"])
            if not v:
                continue
            order = v["order"]
            mapping = {tags[i]: order[i] for i in range(len(order))}
            for scored in item.get("variants", []):
                scored["register"] = mapping.get(scored.get("tag"))
            v.setdefault(panel, []).append(item)


def score_all(scorer: Scorer, variants: list[dict], human: list[dict]) -> dict:
    scores: dict[str, dict[str, float]] = {r: {} for r in REGISTERS}
    errors: dict[str, dict[str, int]] = {r: {} for r in REGISTERS}
    FLOOR = 40  # the hook's own minimum; shorter text is never gated
    for v in variants:
        for r in REGISTERS:
            text = v.get(r) or ""
            if not text.strip():
                continue
            rep = scorer.score(text)
            if rep.words < FLOOR:
                continue
            scores[r][v["id"]] = rep.score
            errors[r][v["id"]] = int(rep.stats["errors"])
    human_scores = []
    human_flags = []
    for h in human:
        rep = scorer.score(h["text"])
        if rep.words < FLOOR:
            continue
        human_scores.append(rep.score)
        human_flags.append(bool(rep.stats["errors"]))
    import re as _re
    em = sum(1 for h in human if _re.search(r"[\u2014\u2013]", h["text"])) / max(1, len(human))
    return {"scores": scores, "errors": errors, "human_scores": human_scores,
            "human_flags": human_flags, "human_errors": sum(human_flags),
            "chat_em_dash": em}


def build_scorecard(scored: dict, variants: list[dict], min_score: float) -> Scorecard:
    s = scored["scores"]
    # Only ids the floor kept in every register can be compared.
    ids = [i for i in s["plain"] if i in s["slop"] and i in s["wild"]]
    plain = [s["plain"][i] for i in ids]
    slop = [s["slop"][i] for i in ids]
    wild = [s["wild"][i] for i in ids if i in s["wild"]]
    wins = sum(1 for a, b in zip(plain, slop) if a > b)
    losses = sum(1 for a, b in zip(plain, slop) if a < b)

    judge_x: list[float] = []
    tool_y: list[float] = []
    for v in variants:
        comp = judge_composite(v)
        for r, q in comp.items():
            if v["id"] in s[r]:
                judge_x.append(q)
                tool_y.append(s[r][v["id"]])

    # M3 measures the failure the user cares about: does the gate stop writing
    # that was already acceptable? The honest sample for that is the untouched
    # repo prose, which nobody has complained about.
    wild_err = scored["errors"]["wild"]
    wild_fail = sum(1 for i in ids if s["wild"][i] < min_score or wild_err.get(i, 0))
    fa_rate = wild_fail / max(1, len(ids))

    hs = scored["human_scores"]
    flags = scored["human_flags"]
    chat_fa = sum(1 for x, err in zip(hs, flags) if x < min_score or err) / max(1, len(hs))
    slop_err = scored["errors"]["slop"]
    slop_caught = sum(1 for i in ids if s["slop"][i] < min_score or slop_err.get(i, 0)) / max(1, len(ids))

    pairs = list(zip(plain, slop))
    return Scorecard(
        m1_auc_plain_vs_slop=auc(plain, slop),
        m2_spearman_judge=spearman(judge_x, tool_y) if len(judge_x) > 3 else float("nan"),
        m3_false_alarm_rate=fa_rate,
        m4_pair_accuracy=wins / max(1, wins + losses),
        m5_wild_median=statistics.median(wild) if wild else float("nan"),
        plain_median=statistics.median(plain) if plain else float("nan"),
        slop_median=statistics.median(slop) if slop else float("nan"),
        n_pairs=len(ids),
        n_human=len(hs),
        pair_p_value=sign_test(wins, losses),
        chat_false_alarm_rate=chat_fa,
        chat_median=statistics.median(hs) if hs else float("nan"),
        chat_em_dash_rate=scored.get("chat_em_dash", float("nan")),
        slop_catch_rate=slop_caught,
        auc_ci=bootstrap_ci(
            [1.0 if a > b else (0.5 if a == b else 0.0) for a, b in pairs],
            lambda xs: sum(xs) / len(xs),
        ),
    )


def objective(card: Scorecard) -> float:
    """One number to search on.

    Separation and judge agreement are threshold-free, so they carry most of
    the weight: they say whether the score ranks writing correctly at all. The
    gate threshold is chosen afterwards from the ROC, not searched here. The
    median terms keep the score on a scale a person can read, and stop the
    search from winning by pushing everything to one end.
    """

    def ok(x: float, default: float = 0.0) -> float:
        return default if x != x else x

    plain_target = 1.0 - abs(ok(card.plain_median, 0) - 88.0) / 100.0
    slop_target = 1.0 - abs(ok(card.slop_median, 0) - 30.0) / 100.0
    wild_target = 1.0 - abs(ok(card.m5_wild_median, 0) - 80.0) / 100.0
    spread = (ok(card.plain_median, 0) - ok(card.slop_median, 0)) / 100.0
    return (
        6.0 * ok(card.m1_auc_plain_vs_slop, 0.5)
        + 3.0 * max(0.0, ok(card.m2_spearman_judge, 0.0))
        + 1.5 * ok(card.m4_pair_accuracy, 0.5)
        + 1.0 * spread
        + 0.8 * plain_target
        + 0.5 * wild_target
        + 0.5 * slop_target
    )


TUNABLE = [
    ("free_zipf", 3.4, 5.4), ("rarity_gate", 0.2, 2.0), ("zipf_cap", 1.5, 4.0), ("w_zipf", 0.2, 1.4),
    ("free_aoa", 8.0, 14.0), ("aoa_scale", 2.0, 8.0), ("w_aoa", 0.0, 1.0),
    ("free_conc", 1.8, 3.4), ("conc_scale", 1.0, 3.0), ("w_conc", 0.0, 0.8),
    ("w_oov", 0.1, 1.0), ("unearned_mult", 1.0, 4.0), ("unearned_floor", 0.4, 2.5),
    ("free_sentence_len", 14.0, 30.0), ("len_exponent", 1.0, 2.0), ("w_len", 0.01, 0.16),
    ("w_clause", 0.0, 1.6), ("w_passive", 0.0, 0.9), ("w_uniformity", 0.0, 8.0),
    ("w_heading_clause", 0.0, 8.0), ("w_heading_question", 0.0, 6.0),
    ("w_heading_gerund", 0.0, 6.0), ("w_tricolon", 0.0, 3.0), ("free_tricolon_rate", 0.4, 3.0),
    ("r50", 10.0, 70.0), ("curve", 0.8, 3.0),
]


def load_clear(path: Path, n: int, seed: int = 4) -> list[tuple[str, float]]:
    """A deterministic sample of the CLEAR corpus, for the external-fit term."""
    import csv as _csv

    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8-sig", errors="replace") as fh:
        rows = list(_csv.DictReader(fh))
    picked: list[tuple[str, float]] = []
    state = seed
    step = max(1, len(rows) // max(1, n))
    for i in range(0, len(rows), step):
        r = rows[i]
        try:
            bt = float(r["BT_easiness"])
        except (KeyError, TypeError, ValueError):
            continue
        text = r.get("Excerpt") or ""
        if len(text) >= 200:
            picked.append((text, bt))
        if len(picked) >= n:
            break
    del state
    return picked


def clear_rho(scorer: Scorer, sample: list[tuple[str, float]]) -> float:
    if not sample:
        return float("nan")
    ours, human = [], []
    for text, bt in sample:
        rep = scorer.score(text)
        if not rep.words:
            continue
        ours.append(-(rep.spend["lexical"] + rep.spend["sentence"]) / rep.words * 100)
        human.append(bt)
    return spearman(ours, human)


def lcg(seed: int):
    state = seed
    while True:
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        yield state / 0x7FFFFFFF


def tune(variants: list[dict], human: list[dict], base: Weights, iters: int, seed: int = 99,
         clear: list[tuple[str, float]] | None = None) -> tuple[Weights, list]:
    rng = lcg(seed)
    lex = Lexicon(mode="full")
    clear = clear or []
    best = copy.deepcopy(base)
    scorer = Scorer(best, lex)
    card = build_scorecard(score_all(scorer, variants, human), variants, best.min_score)
    ext = clear_rho(scorer, clear)
    best_obj = objective(card) + (4.0 * ext if ext == ext else 0.0)
    history = [(0, best_obj, asdict(card))]
    print(f"start objective {best_obj:.4f}", file=sys.stderr)
    temp = 1.0
    for i in range(1, iters + 1):
        cand = copy.deepcopy(best)
        n_changes = 1 + int(next(rng) * 3)
        for _ in range(n_changes):
            name, lo, hi = TUNABLE[int(next(rng) * len(TUNABLE)) % len(TUNABLE)]
            cur = getattr(cand, name)
            step = (hi - lo) * 0.35 * temp
            val = cur + (next(rng) * 2 - 1) * step
            setattr(cand, name, max(lo, min(hi, val)))
        scorer = Scorer(cand, lex)
        c = build_scorecard(score_all(scorer, variants, human), variants, cand.min_score)
        ext = clear_rho(scorer, clear)
        obj = objective(c) + (4.0 * ext if ext == ext else 0.0)
        if obj > best_obj:
            best, best_obj, card = cand, obj, c
            history.append((i, obj, asdict(c)))
            print(f"  iter {i}: objective {obj:.4f} auc={c.m1_auc_plain_vs_slop:.3f} "
                  f"rho={c.m2_spearman_judge:.3f} clear={ext:.3f} fa={c.m3_false_alarm_rate:.1%} "
                  f"plain={c.plain_median:.0f} wild={c.m5_wild_median:.0f} slop={c.slop_median:.0f}",
                  file=sys.stderr)
        temp = max(0.15, temp * 0.995)
    return best, history


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=HERE / "data" / "variants.json")
    ap.add_argument("--human", type=Path, default=HERE / "data" / "human_writing.json")
    ap.add_argument("--weights", type=Path, default=None)
    ap.add_argument("--tune", action="store_true")
    ap.add_argument("--iters", type=int, default=300)
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--clear", type=int, default=0, help="fit against N CLEAR-corpus excerpts too")
    args = ap.parse_args()

    judged = json.loads(args.data.read_text(encoding="utf-8"))
    variants = load_variants(args.data)
    if isinstance(judged, dict):
        attach_judgements(variants, judged)
    human = json.loads(args.human.read_text(encoding="utf-8"))
    base = Weights.load(args.weights)

    if args.tune:
        sample = load_clear(HERE / "data" / "external" / "clear.csv", args.clear) if args.clear else []
        if args.clear:
            print(f"external fit: {len(sample)} CLEAR excerpts", file=sys.stderr)
        best, history = tune(variants, human, base, args.iters, clear=sample)
        out = args.out or (ROOT / "data" / "weights.candidate.json")
        best.save(out)
        print(f"\nwrote {out}", file=sys.stderr)
        base = best

    scorer = Scorer(base, Lexicon(mode="full"))
    print_config(scorer, base, "scorecard")
    card = build_scorecard(score_all(scorer, variants, human), variants, base.min_score)
    if args.json:
        print(json.dumps(asdict(card), indent=2))
    else:
        print(card.table())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
