"""Tests for the scorer. Run with: uv run pytest -q"""

from __future__ import annotations

import pytest

from plainlang.model import Scorer, Weights
from plainlang.segment import mask_non_prose, parse, split_sentences


# --- segmentation -----------------------------------------------------------

def test_code_fence_is_not_prose():
    src = "Text before.\n\n```python\nx = 'delve into the realm'\n```\n\nText after."
    doc = parse(src)
    joined = " ".join(s.text for s in doc.sentences)
    assert "delve" not in joined
    assert "Text before." in joined and "Text after." in joined


def test_inline_code_and_paths_are_masked():
    prose, _ = mask_non_prose("Run `utilize --leverage` on /usr/local/bin/paradigm now.")
    assert "utilize" not in prose
    assert "paradigm" not in prose
    assert "Run" in prose and "now" in prose


def test_urls_are_masked():
    prose, _ = mask_non_prose("See https://example.com/delve/into/the/realm for detail.")
    assert "delve" not in prose
    assert "for detail" in prose


def test_offsets_survive_masking():
    src = "Hello `code` world."
    prose, _ = mask_non_prose(src)
    assert len(prose) == len(src)
    assert prose.index("world") == src.index("world")


def test_frontmatter_is_masked():
    src = "---\nname: leverage\n---\n\nThe phone reports its own state."
    doc = parse(src)
    joined = " ".join(s.text for s in doc.sentences)
    assert "leverage" not in joined


@pytest.mark.parametrize("text,count", [
    ("One. Two. Three.", 3),
    ("Dr. Smith went home. He slept.", 2),
    ("Version 1.5 shipped. It worked.", 2),
    ("Is it done? Yes. Good!", 3),
])
def test_sentence_splitting(text, count):
    assert len(split_sentences(text)) == count


def test_headings_are_found():
    doc = parse("# Phonecam Settings Brief\n\nBody text here.\n\n## Risks\n\nMore text.")
    assert [h.text for h in doc.headings] == ["Phonecam Settings Brief", "Risks"]


# --- word cost --------------------------------------------------------------

@pytest.fixture(scope="module")
def scorer():
    return Scorer(Weights())


def test_common_words_are_free(scorer):
    for w in ["the", "use", "phone", "start", "before", "enough", "wrong"]:
        cost, _ = scorer.word_cost(w)
        assert cost == 0.0, f"{w} should be free, cost {cost}"


def test_rare_abstract_words_cost_more_than_plain_ones(scorer):
    assert scorer.word_cost("utilize")[0] > scorer.word_cost("use")[0]
    assert scorer.word_cost("commence")[0] > scorer.word_cost("start")[0]
    assert scorer.word_cost("paradigm")[0] > scorer.word_cost("model")[0]


def test_acronyms_and_proper_nouns_are_free(scorer):
    assert scorer.word_cost("HTTP")[0] == 0.0
    assert scorer.word_cost("Bertec", mid_sentence_cap=True)[0] == 0.0


def test_glossary_terms_are_free():
    s = Scorer(Weights())
    s.glossary.add("quantization")
    assert s.word_cost("quantization")[0] == 0.0


def test_nothing_is_banned_outright(scorer):
    """A hard word is expensive, never impossible."""
    cost, _ = scorer.word_cost("ubiquitous")
    assert 0 < cost < 100


# --- rules ------------------------------------------------------------------

def test_em_dash_is_priced_but_does_not_gate(scorer):
    """An em dash is a tell, not a comprehension problem.

    It still costs budget and still shows as a finding. It no longer stops a
    write: the goal is that a person understands the text, and an em dash does
    not stand in the way of that.
    """
    rep = scorer.score("The phone reports its state — and the desktop shows it.")
    hit = next(f for f in rep.findings if f.rule == "em-dash")
    assert hit.severity == "warn"
    assert hit.cost > 0
    assert rep.stats["errors"] == 0


def test_only_defects_gate(scorer):
    """A hard rule means something objectively wrong, not something inelegant."""
    for text in ("The rebuild is scheduled for 26.2 citeturn0search3 and the drift held.",
                 "Reviewed by [NAME] on [DATE]. The plate matched within 0.5 N."):
        assert scorer.score(text).stats["errors"] > 0, text
    for text in ("The phone reports its state — and the desktop shows it.",
                 "It is not a flake, it's a real deadlock in the capture pipeline."):
        assert scorer.score(text).stats["errors"] == 0, text


def test_hyphen_is_not_an_em_dash(scorer):
    rep = scorer.score("Use the well-known force-plate path for cross-platform work.")
    assert not any(f.rule == "em-dash" for f in rep.findings)


def test_em_dash_inside_code_is_ignored(scorer):
    rep = scorer.score("Run `git log --format=%h — %s` to see it.")
    assert not any(f.rule == "em-dash" for f in rep.findings)


@pytest.mark.parametrize("text,rule", [
    ("In today's fast-paced world, teams ship faster.", "in-todays"),
    ("It is worth noting that the plate reports zero.", "worth-noting"),
    ("Experts agree the format is stable.", "vague-attribution"),
    ("This stands as a testament to the design.", "testament"),
    ("The change landed, underscoring the value of tests.", "gerund-tail"),
    ("Let's dive in and see how it works.", "lets-dive"),
    ("We delve into the parser next.", "delve"),
    ("The build is seamless and robust.", "robust-hype"),
    ("Not only does it parse, but it also validates.", "not-only-but-also"),
])
def test_shape_rules_fire(scorer, text, rule):
    rep = scorer.score(text)
    assert any(f.rule == rule for f in rep.findings), f"{rule} did not fire on: {text}"


@pytest.mark.parametrize("text", [
    "The plate reads 812 N at 1000 Hz.",
    "Set the timeout to 30 seconds and retry twice.",
    "Nils asked for a per-activity flag on 2026-08-26.",
    "The 26.1 protocol ignores unknown field types, so no backport is needed.",
])
def test_plain_technical_text_trips_no_rule(scorer, text):
    rep = scorer.score(text)
    assert not [f for f in rep.findings if f.severity in {"error", "warn"}], \
        [f.rule for f in rep.findings]


def test_heading_that_is_a_sentence_costs_more_than_a_name(scorer):
    slogan, _ = scorer.heading_cost("The Phone Stays Mounted")
    name, _ = scorer.heading_cost("Phonecam Settings Brief")
    assert slogan > name
    assert name == 0.0


def test_question_heading_costs(scorer):
    cost, _ = scorer.heading_cost("Why This Matters")
    assert cost > 0


# --- document scoring -------------------------------------------------------

SLOP = """# The Phone Stays Mounted

In today's fast-paced world, our journey to remote control is not just a feature—it is a
testament to the evolving landscape of mobile capture. It is worth noting that experts agree
this represents a pivotal moment, underscoring our commitment to excellence.
"""

PLAIN = """# Phonecam Settings Brief

The phone owns its settings. The desktop shows them and sends changes back.

Version 26.2 adds white balance control. The 26.1 protocol already ignores unknown field
types, so no backport is needed.
"""


def test_slop_scores_below_plain(scorer):
    assert scorer.score(SLOP).score < scorer.score(PLAIN).score


def test_empty_input_does_not_crash(scorer):
    rep = scorer.score("")
    assert rep.words == 0 and rep.score == 100.0


def test_score_is_bounded(scorer):
    for text in ["", "a", SLOP, PLAIN, "delve " * 200]:
        rep = scorer.score(text)
        assert 0.0 <= rep.score <= 100.0


def test_findings_carry_positions(scorer):
    rep = scorer.score("Line one is fine.\n\nIt is worth noting that line three is not.")
    hit = next(f for f in rep.findings if f.rule == "worth-noting")
    assert hit.line == 3


def test_header_row_is_not_a_word(scorer):
    """The lexicon file starts with a header; looking up "word" must not read it."""
    rep = scorer.score("The word count and the zipf value are both stored per word in the table.")
    assert 0.0 <= rep.score <= 100.0


def test_non_english_is_not_scored(scorer):
    """Translated documentation must not be charged for not being English."""
    swedish = (
        "Versionen visas i det nedre hogra hornet av programmet. Oppna menyn och "
        "valj installningar for att se vilken version du anvander just nu. Om du "
        "behover uppdatera programmet finns knappen langst ner i samma meny, och "
        "den visar ocksa vilken version som ar tillganglig."
    )
    rep = scorer.score(swedish)
    assert rep.language == "not-english"
    assert rep.stats["errors"] == 0


def test_english_is_still_scored(scorer):
    rep = scorer.score(
        "The plate reads 812 N at 1000 Hz. The desktop shows the value and writes it "
        "to the take. If the pad has not resolved, capture stays disabled until it does."
    )
    assert rep.language == "en"


def test_machine_residue_quoted_as_evidence_is_exempt(scorer):
    """A bug report about a leaked citation marker has to be able to show one."""
    report = (
        "# The linter leaves pasted citation markers in place\n\n"
        "The hook strips markers from a pasted body but misses the ones inside a\n"
        "fenced block. This is the body that got through:\n\n"
        "```\nThe rebuild is scheduled for 26.2 citeturn0search3.\n```\n\n"
        "The fix is to strip inside fences too."
    )
    assert not [f for f in scorer.score(report).findings if f.rule == "tool-artifact"]


def test_machine_residue_in_prose_still_fires(scorer):
    leaked = ("The rebuild is scheduled for 26.2 citeturn0search3 and the drift was "
              "confirmed by the vendor, so the change is ready for review.")
    assert [f for f in scorer.score(leaked).findings if f.rule == "tool-artifact"]


def test_report_serialises(scorer):
    import json
    json.loads(scorer.score(PLAIN).to_json())
