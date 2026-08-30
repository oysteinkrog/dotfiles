"""Goal metrics for the plain-language scorer.

Every number here is computed from a labelled dataset, so a weight change can
be accepted or rejected on evidence rather than taste.

M1  separation        Can the score tell a plain rewrite from a slop rewrite?
                      Reported as AUC over all plain/slop pairs. 0.5 is chance.
M2  judge agreement   Does the score track what a blind human-style judge
                      thinks? Spearman rho between score and the judge's
                      composite quality (clarity minus AI smell).
M3  false alarm       How often does real, approved human writing trip a hard
                      rule or fall below the gate? Lower is better.
M4  pair accuracy     Share of passages where the plain variant outscores the
                      slop variant. Easier to read than AUC, same idea.
M5  wild placement    Where does untouched human writing land? It should sit
                      between plain and slop, not at the bottom.
M6  hard-rule
    precision         Of the hard-rule hits, how many does a judge call real.
                      Measured separately, from the audit set.
"""

from __future__ import annotations

import math
from dataclasses import dataclass


def rank(xs: list[float]) -> list[float]:
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    ranks = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        avg = (i + j) / 2 + 1
        for k in range(i, j + 1):
            ranks[order[k]] = avg
        i = j + 1
    return ranks


def spearman(a: list[float], b: list[float]) -> float:
    if len(a) < 3:
        return float("nan")
    ra, rb = rank(a), rank(b)
    n = len(a)
    ma, mb = sum(ra) / n, sum(rb) / n
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    da = math.sqrt(sum((x - ma) ** 2 for x in ra))
    db = math.sqrt(sum((y - mb) ** 2 for y in rb))
    return num / (da * db) if da and db else float("nan")


def auc(pos: list[float], neg: list[float]) -> float:
    """Probability a random positive scores above a random negative."""
    if not pos or not neg:
        return float("nan")
    allv = pos + neg
    ranks = rank(allv)
    rpos = sum(ranks[: len(pos)])
    n1, n0 = len(pos), len(neg)
    return (rpos - n1 * (n1 + 1) / 2) / (n1 * n0)


def wilson(successes: int, n: int, z: float = 1.96) -> tuple[float, float]:
    """Binomial confidence interval that behaves at the extremes."""
    if n == 0:
        return (0.0, 1.0)
    p = successes / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def sign_test(wins: int, losses: int) -> float:
    """Two-sided p value for a paired win/loss count, ties excluded."""
    n = wins + losses
    if n == 0:
        return 1.0
    k = min(wins, losses)
    total = 0.0
    for i in range(k + 1):
        total += math.comb(n, i)
    p = 2 * total / (2 ** n)
    return min(1.0, p)


def bootstrap_ci(values: list[float], stat, n_boot: int = 2000, seed: int = 12345) -> tuple[float, float]:
    """Percentile interval using a small deterministic generator."""
    if not values:
        return (float("nan"), float("nan"))
    state = seed
    n = len(values)
    stats = []
    for _ in range(n_boot):
        sample = []
        for _ in range(n):
            state = (1103515245 * state + 12345) & 0x7FFFFFFF
            sample.append(values[state % n])
        stats.append(stat(sample))
    stats.sort()
    return (stats[int(0.025 * n_boot)], stats[int(0.975 * n_boot) - 1])


@dataclass
class Scorecard:
    m1_auc_plain_vs_slop: float
    m2_spearman_judge: float
    m3_false_alarm_rate: float       # on real repo prose (the wild register)
    m4_pair_accuracy: float
    m5_wild_median: float
    plain_median: float
    slop_median: float
    n_pairs: int
    n_human: int
    pair_p_value: float
    auc_ci: tuple[float, float]
    chat_false_alarm_rate: float = float("nan")   # on the user's own chat prose
    chat_median: float = float("nan")
    chat_em_dash_rate: float = float("nan")
    slop_catch_rate: float = float("nan")         # share of slop the gate stops

    def table(self) -> str:
        lo, hi = self.auc_ci
        rows = [
            ("M1 separation (AUC plain vs slop)", f"{self.m1_auc_plain_vs_slop:.3f}", f"95% CI {lo:.3f}-{hi:.3f}"),
            ("M2 judge agreement (Spearman)", f"{self.m2_spearman_judge:.3f}", "score vs blind judges"),
            ("M3 false alarm on repo prose", f"{self.m3_false_alarm_rate:.1%}", f"n={self.n_pairs} untouched passages"),
            ("M4 pair accuracy", f"{self.m4_pair_accuracy:.1%}", f"n={self.n_pairs}, sign test p={self.pair_p_value:.2g}"),
            ("M6 slop caught by the gate", f"{self.slop_catch_rate:.1%}", ""),
            ("median score, plain", f"{self.plain_median:.1f}", ""),
            ("median score, repo prose", f"{self.m5_wild_median:.1f}", ""),
            ("median score, slop", f"{self.slop_median:.1f}", ""),
            ("diagnostic: user chat prose", f"{self.chat_median:.1f}", f"gate would stop {self.chat_false_alarm_rate:.0%}, "
                                                                       f"{self.chat_em_dash_rate:.0%} contain an em dash (n={self.n_human})"),
        ]
        width = max(len(r[0]) for r in rows)
        return "\n".join(f"{a:<{width}}  {b:>8}  {c}" for a, b, c in rows)
