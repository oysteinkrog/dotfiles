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


# --- regressions from the 2026-09-01 audit ----------------------------------
# Each of these pins one defect that shipped and was found by running the tool
# against text nobody had written for it. Both directions are asserted wherever
# a fix could go too far: the case that used to be wrong, and the case the rule
# still has to catch.

_SLOP = (
    "In todays fast-paced world, our journey to remote capture is not just a "
    "feature, it is a testament to the evolving landscape of mobile motion "
    "analysis. It is worth noting that experts agree this marks a pivotal "
    "moment for the whole team and the product overall."
)
_CJK = (
    "用户手册说明了如何在移动设备上使用远程捕获功能。请参阅第三章了解详细的配置步骤和注意事项。"
    "系统要求包括最新版本的操作系统和至少四百兆的可用存储空间。如果连接失败请检查网络设置。"
)
_NORWEGIAN = (
    "Telefonen eier sine egne innstillinger og skrivebordet viser dem. Naar du "
    "endrer en verdi sender skrivebordet den tilbake over den eksisterende "
    "protokollen, og telefonen bruker den og rapporterer resultatet tilbake."
)


def test_terse_english_is_not_mistaken_for_another_language(scorer):
    """Bullets carry no function words, which used to read as not English.

    A changelog of eight `- Fixed ...` lines scored 0.000 on the function-word
    share, exactly like Norwegian prose, so it was declared not English and
    scored not at all. Real repo prose was bypassing the gate.
    """
    changelog = "\n".join(["- Fixed force plate reconnect crash after USB unplug"] * 8)
    rep = scorer.score(changelog)
    assert rep.language == "en"
    assert rep.stats["known_share"] > 0.85


def test_latin_script_other_languages_are_still_skipped(scorer):
    """The other direction: the fix must not start scoring Norwegian as English."""
    rep = scorer.score(_NORWEGIAN)
    assert rep.language == "not-english"
    assert rep.stats["known_share"] < 0.85


def test_a_quoted_non_latin_paragraph_does_not_exempt_the_document(scorer):
    """One paragraph of Chinese used to take the whole file out of scope.

    The not-English test measured the share of Latin characters over the whole
    document, so appending a Chinese quotation to an inflated English passage
    took it from a failed gate to a score of 100 with no findings.
    """
    rep = scorer.score(_SLOP + "\n\n" + _CJK)
    assert rep.language == "en"
    assert rep.score < 34.5
    assert rep.findings


def test_a_document_entirely_in_another_script_is_still_skipped(scorer):
    rep = scorer.score(_CJK + "\n\n" + _CJK)
    assert rep.language == "not-english"


def test_a_single_non_latin_symbol_stays_prose(scorer):
    """A micro sign in a tolerance is prose, not a foreign-language quotation."""
    spec = (
        "The plate reads 812 N at 1000 Hz and the tolerance is 5 μm across the "
        "whole range, which is inside what the datasheet promises for this "
        "amplifier at normal room temperature."
    )
    rep = scorer.score(spec)
    assert rep.language == "en"
    assert rep.stats["latin_share"] > 0.9
    assert rep.score > 34.5


def test_a_markdown_blockquote_is_quoted_material(scorer):
    """Quoting someone else's hype must not be charged to the person quoting it."""
    hype = (
        "> Our seamless and robust platform delivers a comprehensive, "
        "best-in-class experience that empowers teams to unlock their full "
        "potential and drive transformative outcomes.\n"
    )
    report = (
        "The vendor replied on 2026-08-20. Their answer is below, unedited. I "
        "have not changed a word of it.\n\n" + hype +
        "\nI do not think it answers the question we asked about frame timing."
    )
    from_quote = {"robust-hype", "promo-adjectives", "ai-vocab", "heavy-sentence"}
    fired = {f.rule for f in scorer.score(report).findings}
    assert not (fired & from_quote), f"charged for the quotation: {fired & from_quote}"


def test_writing_the_same_hype_yourself_still_fails(scorer):
    """The other direction: the exemption is for the `>` block, not the words."""
    own = (
        "The vendor replied on 2026-08-20. Our seamless and robust platform "
        "delivers a comprehensive, best-in-class experience that empowers teams "
        "to unlock their full potential and drive transformative outcomes."
    )
    assert scorer.score(own).findings


def test_a_bullet_list_is_not_flat_writing(scorer):
    """Bullets are parallel by design, so their length variance proves nothing.

    A ten-item release note of two-word bullets was charged for uniform rhythm.
    """
    items = ["Import take", "Trim clip", "Export overlay", "Sync cameras",
             "Rebuild index", "Clear cache", "Reset plate offsets",
             "Recalibrate pads", "Reload profile", "Verify sync"]
    rep = scorer.score("\n".join(f"- {i}" for i in items))
    assert not [f for f in rep.findings if f.rule == "uniform-rhythm"]


def test_prose_that_really_is_flat_still_fires(scorer):
    """The other direction: paragraphs of one length are still charged."""
    flat = " ".join(["The plate reads a value now."] * 8)
    assert [f for f in scorer.score(flat).findings if f.rule == "uniform-rhythm"]


def test_short_text_is_not_scored(scorer):
    """The rate is cost per 100 words, so a score on 21 words is not evidence.

    The hook has always applied this floor. It lives in the scorer now so that
    `pl check` agrees with the hook instead of failing what the hook allows.
    """
    rep = scorer.score("- Import take\n- Trim clip\n- Export overlay\n- Sync cameras")
    assert not rep.scorable
    assert scorer.score(_SLOP).scorable


def test_slop_inside_a_nested_bullet_is_scored(scorer):
    """Four-space indentation is legal list nesting, not an indented code block.

    Masking it meant a whole nested list was invisible, so writing an inflated
    paragraph as a sub-bullet passed the gate.
    """
    doc = "Notes on the release.\n\n- Top level item\n    - " + _SLOP + "\n"
    rep = scorer.score(doc)
    assert rep.score < 34.5
    assert rep.findings


def test_real_indented_code_is_still_masked(scorer):
    """The other direction: an indented block that is not a list item is code."""
    doc = ("Run the loop below and watch the counter.\n\n"
           "    for i in range(10):\n        print(paradigm, synergy, leverage)\n")
    joined = " ".join(s.text for s in parse(doc).sentences)
    assert "paradigm" not in joined


def test_a_longer_fence_masks_its_contents(scorer):
    """Four backticks are how you quote a block that itself contains three.

    Matching exactly three let the inner code leak out and be scored as writing.
    """
    doc = ("The nested fence below is the markdown to paste into the issue.\n\n"
           "````\n```\nparadigm synergy leverage utilise commence\n```\n````\n")
    joined = " ".join(s.text for s in parse(doc).sentences)
    assert "paradigm" not in joined


def test_an_unclosed_fence_runs_to_the_end_of_the_file(scorer):
    """CommonMark says an unclosed fence closes at end of input."""
    doc = ("Run this to reproduce the crash.\n\n"
           "```\nparadigm synergy leverage utilise commence\nmore paradigm synergy\n")
    joined = " ".join(s.text for s in parse(doc).sentences)
    assert "paradigm" not in joined


def test_describing_a_commit_trailer_is_not_an_unfilled_placeholder(scorer):
    """This repository documents `Fixes: DESKTOP-XXXX` as the form to use.

    Unanchored, the rule hard-blocked every sentence that described it, and a
    hard rule blocks at any length and any score.
    """
    describing = (
        "Commit bodies use the form Fixes: DESKTOP-XXXX so Jira links the issue. "
        "That is the convention this repository documents in CLAUDE.md, and every "
        "commit that closes an issue carries it in the body, never in the title."
    )
    assert not [f for f in scorer.score(describing).findings
                if f.rule == "unfilled-placeholder"]


@pytest.mark.parametrize("body", [
    "Fixes: DESKTOP-XXXX",
    "- Fixes: DESKTOP-XXXX",
    "> Fixes: DESKTOP-XXXX",
])
def test_a_real_unfilled_trailer_still_gates(scorer, body):
    """The other direction: a trailer nobody filled in is still a defect."""
    msg = ("video: rebuild the frame index on import\n\nThe first scrub after an "
           "import was slow because the index was built lazily.\n\n" + body + "\n")
    assert [f for f in scorer.score(msg).findings if f.rule == "unfilled-placeholder"]


@pytest.mark.parametrize("heading,fires", [
    ("## Why The Capture Lifecycle Needs A Second Pass", True),
    ("### What Costs Real Money", True),
    ("## The Phone Stays Mounted", True),
    ("### What it costs on real history", False),
    ("### Defects reported and not yet fixed", False),
    ("## Rebuild the frame index on import", False),
    ("# API CLI SDK", False),
    ("## Force plate calibration", False),
])
def test_title_case_heading_reads_capitals_not_word_count(heading, fires):
    """The rule was compiled case-insensitively, so it matched any three words.

    `_r` defaults to `re.I`, which made `[A-Z][a-z]+` match lowercase too, so
    every ordinary sentence-case heading of three or more plain words was
    reported as Title Case. It is case-sensitive now, and `[a-z]*` lets a
    one-letter word sit inside the run without ending the match.
    """
    from plainlang.rules import ALL_RULES
    rule = next(r for r in ALL_RULES if r.id == "title-case-heading")
    assert bool(rule.pattern.search(heading)) is fires


@pytest.mark.parametrize("text,fires,why", [
    ("The seek path rebuilds the index — that is why it is slow.", True, "em dash as punctuation"),
    ("The seek path rebuilds the index – that is why it is slow.", True, "en dash as punctuation"),
    ("Deteksjon mislyktes – platesignal er i konflikt.", True, "Norwegian pause tankestrek"),
    ("Use pages 3 – 5 for the figures.", True, "spaced dash between digits"),
    ("The Oslo–Bergen route takes seven hours.", False, "paired name"),
    ("The window is 2024–2026 for this plan.", False, "date range"),
    ("The May–June window is when it lands.", False, "month range"),
    ("Growth was –5 % in the quarter.", False, "minus sign on a number"),
    ("kost–nytte-analyse viser det samme.", False, "Norwegian paired compound"),
])
def test_en_dash_is_charged_only_as_punctuation(text, fires, why):
    """The en dash has mechanical jobs a character-level ban would corrupt.

    A range, a paired name and a minus sign are values and compounds, not writing.
    The minus-sign case matters most: charging it pushes a rewrite toward changing
    a number, which contradicts the rule that every number survives as written.
    The em dash stays charged everywhere.
    """
    from plainlang.rules import ALL_RULES
    rule = next(r for r in ALL_RULES if r.id == "em-dash")
    assert bool(rule.pattern.search(text)) is fires, why
