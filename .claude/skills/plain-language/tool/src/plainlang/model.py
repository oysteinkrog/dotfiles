"""The cost model.

Nothing is banned. Every word and every sentence spends from a budget, and a
word that is rare, late-learned or abstract spends more. Precision is free:
a domain term, a proper noun, an acronym, a number or anything inside code
costs nothing, because the skill says to keep the precise word and simplify
the sentence around it.

What costs extra is unearned difficulty: a hard word that has a plain synonym
carrying the same meaning. That is the only place the model is opinionated
about specific words, and it is a multiplier, not a ban.
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path

from .lexicon import Lexicon, latinate_suffix, syllables
from .rules import ALL_RULES, Rule

DATA_DIR = Path(__file__).resolve().parents[3] / "data"
if not DATA_DIR.exists():
    DATA_DIR = Path(__file__).resolve().parents[2] / "data"


@dataclass
class Weights:
    # Lexical cost
    free_zipf: float = 4.15        # at or above this frequency a word is free
    rarity_gate: float = 0.6       # rarity needed before lateness/abstractness count
    zipf_cap: float = 3.0          # most a single word can cost on frequency
    w_zipf: float = 1.00
    free_aoa: float = 10.0         # years; later-learned words start to cost
    aoa_scale: float = 4.0
    aoa_cap: float = 1.5
    w_aoa: float = 0.55
    free_conc: float = 2.6         # concreteness 1..5; below this is abstract
    conc_scale: float = 1.6
    conc_cap: float = 1.0
    w_conc: float = 0.30
    # Prevalence: the share of people who report knowing the word (Brysbaert et
    # al. 2019). Normed on native speakers, so it saturates near 1.0 for almost
    # all ordinary vocabulary and only separates the genuinely obscure.
    free_prev: float = 0.97
    prev_scale: float = 0.30
    prev_cap: float = 1.5
    w_prev: float = 0.0
    # A word in the learner core vocabulary costs nothing. Membership only ever
    # removes cost, so it cannot make the model stricter.
    w_core_free: bool = False
    w_oov: float = 0.45            # per syllable above 3 for unknown words
    oov_cap: float = 2.0
    # Extra charge for an unknown word carrying a Latinate suffix. Tunable
    # because no standard written for second-language readers carries an
    # Anglo-Saxon preference, and for a Romance first language the Latinate word
    # is often the cognate and so the easier one.
    w_latinate: float = 0.40
    unearned_mult: float = 2.2     # hard word with a plain synonym
    unearned_floor: float = 1.2    # and at least this much

    # Sentence cost
    free_sentence_len: float = 20.0
    len_exponent: float = 1.45
    w_len: float = 0.055
    w_clause: float = 0.55         # per subordinate clause above two
    free_clauses: float = 2.0
    w_passive: float = 1.1
    w_uniformity: float = 6.0      # flat, when length variation collapses
    uniformity_cv: float = 0.28
    uniformity_min_sentences: int = 5

    # Structure
    w_heading_clause: float = 4.0  # heading that is a sentence, not a name
    w_heading_question: float = 3.0
    w_heading_long: float = 1.0    # per word above six in a heading
    w_acronym_undefined: float = 1.0
    w_tricolon: float = 1.2        # per three-item list above the free rate
    free_tricolon_rate: float = 1.2  # per 100 words
    w_heading_gerund: float = 2.5

    # Rule costs, keyed by rule id; falls back to the rule's own cost.
    rule_costs: dict[str, float] = field(default_factory=dict)

    # Score curve: score = 100 / (1 + (rate/r50) ** curve)
    r50: float = 22.0
    curve: float = 1.6

    min_english_share: float = 0.13   # below this the text is not English

    # Gate
    max_errors: int = 0
    min_score: float = 70.0

    @classmethod
    def load(cls, path: Path | None = None) -> "Weights":
        p = path or (DATA_DIR / "weights.json")
        if p and p.exists():
            raw = json.loads(p.read_text(encoding="utf-8"))
            known = {f for f in cls.__dataclass_fields__}
            return cls(**{k: v for k, v in raw.items() if k in known})
        return cls()

    def save(self, path: Path) -> None:
        path.write_text(json.dumps(asdict(self), indent=2, sort_keys=True) + "\n", encoding="utf-8")


@dataclass
class Finding:
    rule: str
    severity: str
    line: int
    col: int
    excerpt: str
    message: str
    suggest: str = ""
    cost: float = 0.0


@dataclass
class Report:
    score: float
    grade: str
    words: int
    sentences: int
    rate: float
    spend: dict[str, float]
    findings: list[Finding]
    stats: dict[str, float]
    top_costs: list[tuple[str, float]]
    language: str = "en"

    def to_json(self) -> str:
        d = asdict(self)
        d["findings"] = [asdict(f) if not isinstance(f, dict) else f for f in self.findings]
        return json.dumps(d, indent=2)


def _load_wordset(name: str) -> set[str]:
    p = DATA_DIR / name
    if not p.exists():
        return set()
    out = set()
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip().lower()
        if line:
            out.add(line)
    return out


def _discover_glossary() -> set[str]:
    """Pick up a per-project term list: .plainlang/glossary.txt, walking up."""
    import os as _os

    out: set[str] = set()
    seen = 0
    here = Path(_os.environ.get("PLAINLANG_PROJECT", _os.getcwd())).resolve()
    for parent in [here, *here.parents]:
        cand = parent / ".plainlang" / "glossary.txt"
        if cand.exists():
            for line in cand.read_text(encoding="utf-8", errors="replace").splitlines():
                line = line.split("#", 1)[0].strip().lower()
                if line:
                    out.add(line)
            break
        seen += 1
        if seen > 12:
            break
    return out


def _load_simpler(name: str = "simpler.tsv") -> dict[str, str]:
    p = DATA_DIR / name
    if not p.exists():
        return {}
    out: dict[str, str] = {}
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line or "\t" not in line:
            continue
        hard, plain = line.split("\t", 1)
        out[hard.strip().lower()] = plain.strip()
    return out


# Finite verb forms common enough to appear in a slogan-shaped heading.
FINITE_VERBS = set("""
is are was were be been being am has have had does do did will would can could
should shall may might must stays stay stayed keeps keep kept gets get got goes
go went comes come came makes make made takes take took gives give gave runs run
ran works work worked wins win won loses lose lost breaks break broke needs need
needed wants want wanted means mean meant knows know knew sees see saw finds find
found holds hold held moves move moved builds build built ships ship shipped
matters matter mattered counts count counted lives live lived dies die died
starts start started ends end ended begins begin began fails fail failed
happens happen happened belongs belong belonged owns own owned rules rule ruled
""".split())

DETERMINERS = set("""
the a an this that these those our your my its his her their we you it they i
every each no all some any both either neither one two three
""".split())

STOPWORDS = set("""
a an the and or but if then than that this these those of to in on at by for with
from as is are was were be been being am it its it's we you they he she i our your
their his her them us me my not no nor so such very can could should would will
shall may might must do does did done have has had here there when where while
what which who whom whose how why all any each few more most other some only own
same too s t just don now up down out off over under again further once about
into through during before after above below between both against per via
""".split())


# The 30 commonest English function words. Ordinary English prose is 25 to 50
# per cent of these. Swedish, Dutch and Finnish documentation is near zero, and
# scoring it as English charges every word as rare and unknown.
_EN_MARKERS = frozenset("""
the of and to a in that it is was for on as with be at by this from or an are
have has had not but they you we he she which will can all would there their
""".split())


def english_share(tokens: list[str]) -> float:
    if not tokens:
        return 1.0
    return sum(1 for t in tokens if t.lower() in _EN_MARKERS) / len(tokens)


class Scorer:
    def __init__(self, weights: Weights | None = None, lexicon: Lexicon | None = None) -> None:
        self.w = weights or Weights.load()
        self.lex = lexicon or Lexicon()
        self.glossary = _load_wordset("glossary.txt") | _discover_glossary()
        self.core_vocab: set[str] = set()
        if self.w.w_core_free:
            self.core_vocab = _load_wordset("wordlists/ngsl.txt")
        self.simpler = _load_simpler()
        self.rules: list[Rule] = list(ALL_RULES)

    # -- word level ---------------------------------------------------------

    def word_cost(self, word: str, *, mid_sentence_cap: bool = False) -> tuple[float, str]:
        """Cost of one word, and why."""
        raw = word
        w = word.lower().strip("'’-")
        if not w or w in STOPWORDS:
            return 0.0, "free"
        if w in self.glossary:
            return 0.0, "glossary"
        if raw.isupper() and len(raw) > 1:
            return 0.0, "acronym"
        if self.core_vocab and w in self.core_vocab:
            return 0.0, "core vocabulary"
        if mid_sentence_cap and raw[:1].isupper():
            return 0.0, "proper-noun"

        n = self.lex.lookup(w)
        cost = 0.0
        why: list[str] = []
        # Rarity is the gate. A word nobody meets often is the one that costs,
        # and how late it is learned or how abstract it is only matters for
        # those words. "enough" is abstract and easy; "paradigm" is abstract
        # and hard, and the difference is that one is common.
        if n.zipf is not None and n.zipf > 0:
            rarity = min(max(0.0, self.w.free_zipf - n.zipf), self.w.zipf_cap)
            if rarity:
                cost += self.w.w_zipf * rarity
                why.append(f"rare(zipf {n.zipf:.1f})")
        else:
            rarity = self.w.zipf_cap
            extra = max(0, syllables(w) - 3)
            c = min(self.w.w_oov * extra, self.w.oov_cap)
            if self.w.w_latinate and latinate_suffix(w):
                c += self.w.w_latinate
            if c:
                cost += c
                why.append("unknown word")
        gate = min(1.0, rarity / max(0.25, self.w.rarity_gate))
        if gate > 0:
            if n.aoa is not None:
                c = min(max(0.0, (n.aoa - self.w.free_aoa) / self.w.aoa_scale), self.w.aoa_cap)
                if c:
                    cost += self.w.w_aoa * c * gate
                    why.append(f"late(aoa {n.aoa:.0f})")
            if n.conc is not None:
                c = min(max(0.0, (self.w.free_conc - n.conc) / self.w.conc_scale), self.w.conc_cap)
                if c:
                    cost += self.w.w_conc * c * gate
                    why.append(f"abstract(conc {n.conc:.1f})")
        if self.w.w_prev and n.prev is not None:
            c = min(max(0.0, (self.w.free_prev - n.prev) / self.w.prev_scale), self.w.prev_cap)
            if c:
                cost += self.w.w_prev * c
                why.append(f"not widely known(prev {n.prev:.2f})")

        if w in self.simpler and cost > 0:
            cost = max(cost * self.w.unearned_mult, self.w.unearned_floor)
            why.append(f"plain synonym: {self.simpler[w]}")

        return cost, ", ".join(why) or "free"

    # -- sentence level -----------------------------------------------------

    @staticmethod
    def count_clauses(text: str) -> int:
        markers = re.findall(
            r"\b(?:which|who|whom|whose|that|because|although|though|while|whereas|"
            r"unless|until|since|if|when|where|after|before|so that|such that|"
            r"in order that|given that|provided that)\b",
            text, re.I,
        )
        return len(markers) + text.count(";") + text.count(":")

    # Only agentless passives are charged. The comprehension penalty documented
    # in the literature is for passives with no actor ("the frame rate is
    # clamped"); a passive that names its actor with "by" is not reliably
    # harder to read, so a following "by" clears the charge.
    PASSIVE = re.compile(
        r"\b(?:is|are|was|were|be|been|being|gets?|got)\s+(?:\w+ly\s+)?"
        r"(?:[a-z]+(?:ed|en)|done|made|shown|given|taken|seen|known|held|built|"
        r"found|kept|left|sent|set|put|told|brought|caught|bought|thought)\b"
        r"(?!\s+by\b)",
        re.I,
    )

    def sentence_cost(self, text: str, n_words: int) -> tuple[float, dict[str, float]]:
        parts: dict[str, float] = {}
        over = max(0.0, n_words - self.w.free_sentence_len)
        if over:
            parts["length"] = self.w.w_len * (over ** self.w.len_exponent)
        clauses = self.count_clauses(text)
        if clauses > self.w.free_clauses:
            parts["clauses"] = self.w.w_clause * (clauses - self.w.free_clauses)
        n_pass = len(self.PASSIVE.findall(text))
        if n_pass:
            parts["passive"] = self.w.w_passive * n_pass
        return sum(parts.values()), parts

    # -- structure ----------------------------------------------------------

    # A heading is a tease when it asks a question or promises significance,
    # not merely because it starts with "how" or "where". "How the score works"
    # names its section; "Why This Matters" does not.
    QUESTION_HEAD = re.compile(
        r"^(?:why|what|whether)\b[^\n]{0,40}\b(?:matters?|means?|is important|you (?:need|should))\b"
        r"|^(?:should|can|is|are|do|does|will|would)\b[^\n]{0,60}$",
        re.I,
    )
    # A heading that opens on a participle is pitching rather than naming:
    # "Reimagining capture" versus "Capture changes in 26.2". Restricted to
    # headings because -ing words are ordinary nouns in body text (testing,
    # logging, streaming) and flagging those would be noise.
    GERUND_HEAD = re.compile(r"^(?!(?:building|testing|logging|tracking|recording|streaming|encoding|"
                             r"decoding|debugging|profiling|caching|routing|sampling|timing|scaling|"
                             r"getting started|working with|using|running|installing|writing|reading|"
                             r"understanding|troubleshooting|migrating|upgrading)\b)"
                             r"[A-Za-z]+ing\b", re.I)
    # "A, B, and C" or "A, B and C" as a rhetorical flourish. One is normal
    # prose; a high rate across a passage is the tell.
    TRICOLON = re.compile(r"\b[\w'-]+,\s+[\w'-]+(?:,)?\s+and\s+[\w'-]+\b")
    # First and second person in a heading is pitching. Third person is not:
    # "When it runs" names a section, "Why you need this" sells one.
    PRONOUN_HEAD = re.compile(r"\b(?:we|you|our|your|us|my|mine|yours)\b", re.I)

    def heading_cost(self, text: str) -> tuple[float, list[str]]:
        toks = re.findall(r"[A-Za-z][A-Za-z'’-]*", text)
        if not toks:
            return 0.0, []
        reasons: list[str] = []
        cost = 0.0
        lowered = [t.lower() for t in toks]
        # A heading that is a sentence rather than a name. Nearly every common
        # English verb is also a common noun ("rule group", "force plate"), so
        # a bare verb list is not enough: require a determiner or pronoun
        # subject in front of it. "The Phone Stays Mounted" fires; "Value of
        # each rule group" does not.
        if len(toks) >= 3 and lowered[0] in DETERMINERS:
            for i, tok in enumerate(lowered[1:4], start=1):
                if tok in FINITE_VERBS and i < len(lowered) - 1:
                    cost += self.w.w_heading_clause
                    reasons.append("reads as a sentence, not a name")
                    break
        if self.GERUND_HEAD.match(text.strip()):
            cost += self.w.w_heading_gerund
            reasons.append("opens on a participle")
        if text.rstrip().endswith("?") or self.QUESTION_HEAD.match(text.strip()):
            cost += self.w.w_heading_question
            reasons.append("question or tease")
        if self.PRONOUN_HEAD.search(text):
            cost += self.w.w_heading_clause * 0.5
            reasons.append("addresses the reader instead of naming the section")
        over = max(0, len(toks) - 6)
        if over:
            cost += self.w.w_heading_long * over
            reasons.append(f"{len(toks)} words")
        return cost, reasons

    # -- document ----------------------------------------------------------

    def score(self, source: str, *, kind: str = "document") -> Report:
        from .segment import fence_spans, in_spans, parse, quote_spans, words as tokenize

        doc = parse(source)
        quoted = quote_spans(source)
        fenced = fence_spans(source)
        self.lex.prime({t.lower().strip("'\u2019-") for s in doc.sentences for t, _ in tokenize(s.text)})
        spend: dict[str, float] = {"lexical": 0.0, "sentence": 0.0, "tells": 0.0, "structure": 0.0}
        findings: list[Finding] = []
        word_costs: dict[str, float] = {}
        n_words = 0
        lengths: list[int] = []

        for sent in doc.sentences:
            toks = tokenize(sent.text)
            if not toks:
                continue
            content = [t for t, _ in toks]
            if sent.block_kind not in {"heading", "table"}:
                lengths.append(len(content))
            n_words += len(content)
            for idx, (tok, off) in enumerate(toks):
                cost, why = self.word_cost(tok, mid_sentence_cap=(idx > 0 and sent.block_kind != "heading"))
                if cost > 0:
                    spend["lexical"] += cost
                    key = tok.lower()
                    word_costs[key] = word_costs.get(key, 0.0) + cost
                    if cost >= 1.5:
                        line, col = doc.line_col(sent.start + off)
                        findings.append(Finding(
                            "hard-word", "info", line, col, tok,
                            f"Hard word: {why}.",
                            self.simpler.get(key, ""), round(cost, 2),
                        ))
            if sent.block_kind == "heading":
                hc, reasons = self.heading_cost(sent.text)
                if hc:
                    spend["structure"] += hc
                    line, col = doc.line_col(sent.start)
                    findings.append(Finding(
                        "heading-shape", "warn" if hc >= self.w.w_heading_clause else "info",
                        line, col, sent.text[:80],
                        "Heading: " + "; ".join(reasons) + ".",
                        "Name what the section covers.", round(hc, 2),
                    ))
            elif sent.block_kind != "table":
                sc, parts = self.sentence_cost(sent.text, len(content))
                if sc:
                    spend["sentence"] += sc
                    if parts.get("length", 0) >= 1.0 or sc >= 2.0:
                        line, col = doc.line_col(sent.start)
                        detail = ", ".join(f"{k} {v:.1f}" for k, v in parts.items())
                        findings.append(Finding(
                            "heavy-sentence", "warn" if sc >= 3.0 else "info",
                            line, col, sent.text[:90],
                            f"{len(content)} words ({detail}).",
                            "Split it, or cut a clause.", round(sc, 2),
                        ))

        # Sentence-length variation: prose that never changes gear reads as a list.
        if len(lengths) >= self.w.uniformity_min_sentences:
            mean = sum(lengths) / len(lengths)
            var = sum((x - mean) ** 2 for x in lengths) / len(lengths)
            cv = math.sqrt(var) / mean if mean else 0.0
            if cv < self.w.uniformity_cv:
                spend["structure"] += self.w.w_uniformity
                findings.append(Finding(
                    "uniform-rhythm", "info", 1, 1, f"cv={cv:.2f}",
                    f"Every sentence is about {mean:.0f} words.",
                    "Vary the length.", round(self.w.w_uniformity, 2),
                ))
        else:
            cv = 0.0

        # Three-item lists: one is ordinary, a steady beat of them is a habit.
        tricolons = len(self.TRICOLON.findall(doc.prose))
        rate_tri = tricolons / max(1, n_words) * 100
        if rate_tri > self.w.free_tricolon_rate and tricolons >= 2:
            over = (rate_tri - self.w.free_tricolon_rate) / 100 * n_words
            cost_tri = self.w.w_tricolon * over
            spend["structure"] += cost_tri
            findings.append(Finding(
                "tricolon-rate", "info", 1, 1, f"{tricolons} three-item lists in {n_words} words",
                "Three-item lists used as a rhythm rather than a count.",
                "Keep the ones that really have three items.", round(cost_tri, 2),
            ))

        # Pattern rules run over the prose text, which has code and links blanked.
        for rule in self.rules:
            cost = self.w.rule_costs.get(rule.id, rule.cost)
            if cost <= 0:
                continue
            haystack = source if rule.surface == "raw" else doc.prose
            for m in rule.pattern.finditer(haystack):
                if rule.surface == "raw":
                    # A fenced block in prose is quoted evidence, which the skill
                    # puts out of scope even for the machine-residue rules: a bug
                    # report about a leaked citation marker has to show one.
                    if in_spans(m.start(), fenced):
                        continue
                elif in_spans(m.start(), quoted):
                    continue
                excerpt = doc.source[m.start():m.end()][:90]
                line, col = doc.line_col(m.start())
                spend["tells"] += cost
                findings.append(Finding(
                    rule.id, rule.severity, line, col, excerpt,
                    rule.message, rule.suggest, round(cost, 2),
                ))

        share = english_share([tok for sent in doc.sentences for tok, _ in tokenize(sent.text)])
        # A non-Latin script gives almost no [A-Za-z] tokens, so the function-word
        # share cannot see it. Measure the script directly as well.
        letters = [c for c in doc.prose if c.isalpha()]
        latin_share = (sum(1 for c in letters if ord(c) < 0x250) / len(letters)) if letters else 1.0
        language = "en"
        if latin_share < 0.85:
            language = "not-english"
        elif n_words >= 30 and share < self.w.min_english_share:
            language = "not-english"
        if language != "en":
            # Not English. Report it and score nothing, rather than charging every
            # word as rare and unknown.
            return Report(
                score=100.0, grade="A", words=n_words, sentences=len(lengths), rate=0.0,
                spend={k: 0.0 for k in spend}, findings=[],
                stats={"mean_sentence_words": 0.0, "max_sentence_words": 0.0,
                       "length_cv": 0.0, "errors": 0.0, "warnings": 0.0,
                       "english_share": round(share, 3), "latin_share": round(latin_share, 3)},
                top_costs=[], language=language,
            )

        total = sum(spend.values())
        rate = (total / n_words * 100) if n_words else 0.0
        score = 100.0 / (1.0 + (rate / self.w.r50) ** self.w.curve) if rate > 0 else 100.0
        findings.sort(key=lambda f: (-f.cost, f.line))

        return Report(
            score=round(score, 1),
            grade=grade_of(score),
            words=n_words,
            sentences=len(lengths),
            rate=round(rate, 2),
            spend={k: round(v, 2) for k, v in spend.items()},
            findings=findings,
            stats={
                "mean_sentence_words": round(sum(lengths) / len(lengths), 1) if lengths else 0.0,
                "max_sentence_words": float(max(lengths)) if lengths else 0.0,
                "length_cv": round(cv, 3),
                "errors": float(sum(1 for f in findings if f.severity == "error")),
                "warnings": float(sum(1 for f in findings if f.severity == "warn")),
                "english_share": round(share, 3),
            },
            top_costs=sorted(word_costs.items(), key=lambda kv: -kv[1])[:12],
            language=language,
        )


def grade_of(score: float) -> str:
    if score >= 90:
        return "A"
    if score >= 80:
        return "B"
    if score >= 70:
        return "C"
    if score >= 55:
        return "D"
    return "F"
