"""Pattern rules for the tells the plain-language skill bans.

Every rule carries a cost, not a ban. `severity` decides what the cost means:

    error  a hard rule from the skill. Any hit fails the gate.
    warn   a strong tell. Costs budget; enough of them fail the gate.
    info   a weak signal. Costs a little, and is there to be tuned or dropped.

Costs live in weights.json so the tuner can change them without touching code.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Rule:
    id: str
    severity: str
    pattern: re.Pattern[str]
    message: str
    suggest: str = ""
    cost: float = 1.0
    scope: str = "any"  # any | heading | body | first_last
    surface: str = "prose"  # prose = code, links and paths blanked; raw = the whole file


def _r(pat: str, flags: int = re.I) -> re.Pattern[str]:
    return re.compile(pat, flags)


# --- Hard rules -------------------------------------------------------------

HARD: list[Rule] = [
    Rule(
        "em-dash", "error",
        _r(r"(?<![0-9\s])[—–](?![0-9])|(?<=\s)[—–](?![0-9])|(?<=\w) -- (?=\w)"),
        "Em dash or en dash used as punctuation.",
        "Use a period, comma, colon, or parentheses.",
        cost=6.0,
    ),
]

# --- Banned shapes from the skill's table -----------------------------------

SHAPES: list[Rule] = [
    Rule(
        "not-x-its-y", "error",
        _r(r"\b(?:it'?s|this is|that'?s|they'?re|we'?re)\s+not\s+(?:just\s+)?(?:a|an|the)?[^.,;:!?]{1,40},\s*(?:it'?s|this is|that'?s|they'?re|we'?re|but)\b"),
        "\"Not X, it's Y\" contrast formula.",
        "State what it is.",
        cost=5.0,
    ),
    Rule(
        "not-only-but-also", "error",
        _r(r"\bnot only\b[^.!?]{1,120}?\bbut (?:also|it also|they also)\b"),
        "\"Not only X, but also Y\" negative parallelism.",
        "Split into two sentences.",
        cost=5.0,
    ),
    Rule(
        "not-merely", "warn",
        _r(r"\b(?:is|was|are|were|does|do)\s+n[o']t\s+(?:merely|simply|just)\b[^.!?]{0,80}?\bbut\b"),
        "\"Not merely X but Y\" negative parallelism.",
        "Say what it does.",
        cost=3.0,
    ),
    Rule(
        "isnt-about", "warn",
        _r(r"\b(?:this|it|that)\s+is\s*n[o']t\s+about\b[^.!?]{1,60}\bit'?s about\b"),
        "\"It isn't about X, it's about Y\" formula.",
        "State the point directly.",
        cost=4.0,
    ),
    Rule(
        "heres-why", "warn",
        _r(r"\bhere'?s (?:why|how|what|the thing|the kicker|where)\b"),
        "\"Here's why\" tease.",
        "Give the reason.",
        cost=3.0,
    ),
    Rule(
        "why-it-matters", "warn",
        _r(r"\b(?:why (?:this|it|that) matters|what (?:this|it) means for you|the (?:real )?(?:kicker|catch|twist))\b"),
        "Significance tease.",
        "Say the consequence.",
        cost=3.0,
    ),
    Rule(
        "lets-dive", "warn",
        _r(r"\blet'?s (?:dive|jump|get started|explore|unpack|take a look|break (?:it|this) down)\b"),
        "Forced enthusiasm opener.",
        "Start with the content.",
        cost=3.0,
    ),
    Rule(
        "in-todays", "warn",
        _r(r"\bin (?:today'?s|the modern|an? increasingly)\b[^.!?]{0,40}\b(?:world|landscape|era|environment|age)\b"),
        "Scene-setting opener.",
        "Delete it.",
        cost=4.0,
    ),
    Rule(
        "whether-youre", "warn",
        _r(r"\bwhether you'?(?:re|are)\b[^.!?]{1,60}\bor\b"),
        "\"Whether you're X or Y\" audience framing.",
        "Address the reader once, directly.",
        cost=2.5,
    ),
    Rule(
        "vague-attribution", "warn",
        _r(r"\b(?:experts?|researchers?|studies|many|some|analysts?|critics?|observers?|industry (?:leaders|watchers))\s+(?:agree|say|argue|believe|suggest|note|have (?:noted|argued|shown)|show)\b"),
        "Vague attribution with no source.",
        "Name the source and the date.",
        cost=3.0,
    ),
    Rule(
        "worth-noting", "warn",
        _r(r"\b(?:it'?s|it is)\s+(?:worth|important|essential|crucial)\s+(?:noting|to note|to remember|to mention|to understand)\b"),
        "Hedge before the point.",
        "Make the point.",
        cost=3.0,
    ),
    Rule(
        "at-its-core", "warn",
        _r(r"\b(?:at its core|at the end of the day|in essence|fundamentally speaking|when all is said and done|the bottom line is)\b"),
        "Pseudo-profound opener.",
        "Delete it.",
        cost=3.0,
    ),
    Rule(
        "gerund-tail", "warn",
        _r(r",\s+(?:highlighting|underscoring|emphasi[sz]ing|showcasing|reflecting|symboli[sz]ing|demonstrating|illustrating|cementing|solidifying|marking|signaling|signalling|ensuring|cultivating|fostering|paving the way|contributing to|reinforcing|affirming)\b"),
        "Participial tail that adds significance rather than fact.",
        "Cut it, or make it a sentence with a fact in it.",
        cost=3.5,
    ),
    Rule(
        "testament", "warn",
        _r(r"\b(?:stands? as|serves? as|is) a (?:testament|reminder|symbol|hallmark|cornerstone|beacon|linchpin)\b"),
        "Significance inflation.",
        "State what it does.",
        cost=4.0,
    ),
    Rule(
        "pivotal-role", "warn",
        _r(r"\b(?:plays?|played|playing) an? (?:vital|significant|crucial|pivotal|key|central|critical|important) role\b"),
        "Significance inflation.",
        "Say what it actually does.",
        cost=3.0,
    ),
    Rule(
        "broader-landscape", "warn",
        _r(r"\b(?:evolving|shifting|changing|broader|wider|ever-changing) (?:landscape|ecosystem|tapestry|fabric|paradigm)\b"),
        "Abstract scene-setting.",
        "Name the thing that changed.",
        cost=4.0,
    ),
    Rule(
        "journey-framing", "warn",
        _r(r"\b(?:our|the|my) (?:journey|path|road|quest|adventure) (?:to|toward|towards|through)\b"),
        "Journey framing.",
        "Name the phases or the goal.",
        cost=3.0,
    ),
    Rule(
        "delve", "warn",
        _r(r"\b(?:delve|delves|delving) into\b"),
        "\"Delve into\" is the strongest single-word tell of AI prose.",
        "Use: look at, cover, examine.",
        cost=4.0,
    ),
    Rule(
        "in-order-to", "info",
        _r(r"\bin order to\b"),
        "Padding.",
        "Use \"to\".",
        cost=1.0,
    ),
    Rule(
        "the-fact-that", "info",
        _r(r"\bthe fact that\b"),
        "Padding.",
        "Rewrite without it.",
        cost=1.0,
    ),
    Rule(
        "needless-to-say", "info",
        _r(r"\b(?:needless to say|as we all know|as you (?:may|might) know|of course,)\b"),
        "Padding.",
        "Delete it.",
        cost=1.5,
    ),
    Rule(
        "moreover", "info",
        _r(r"(?m)^\s*(?:>|[-*+]\s+|\d+[.)]\s+)?(?:Moreover|Furthermore|Additionally|Notably|Importantly|Ultimately|Overall|In conclusion|To summari[sz]e|In summary)\b[,:]"),
        "Conjunctive opener stacked at the start of a sentence.",
        "Join the sentences, or just state the next fact.",
        cost=1.5,
    ),
    Rule(
        "robust-hype", "warn",
        _r(r"\b(?:seamless(?:ly)?|robust|comprehensive|powerful|cutting[- ]edge|state[- ]of[- ]the[- ]art|game[- ]?changer|game[- ]changing|best[- ]in[- ]class|world[- ]class|unparalleled|unmatched|revolutionary|groundbreaking|innovative|elegant(?:ly)?|effortless(?:ly)?|blazing(?:ly)? fast|turnkey|holistic|synergy|synerg\w+)\b"),
        "Hype register.",
        "Say what it does and give the number.",
        cost=3.0,
    ),
    Rule(
        "promo-adjectives", "info",
        _r(r"\b(?:vibrant|rich tapestry|breathtaking|stunning|must[- ]have|must[- ]visit|renowned|nestled|boasts?|in the heart of|meticulous(?:ly)?|profound(?:ly)?)\b"),
        "Promotional adjective.",
        "Cut it or replace with a fact.",
        cost=2.0,
    ),
    Rule(
        "ai-vocab", "info",
        _r(r"\b(?:leverage[sd]?|leveraging|utili[sz]e[sd]?|utili[sz]ing|utili[sz]ation|facilitate[sd]?|myriad|plethora|intricate|intricacies|nuanced|realm|paradigm|underscore[sd]?|underscores|showcase[sd]?|navigate the|foster(?:ing|s)?|streamline[sd]?|bolster(?:ing|s)?|garner(?:ing|ed|s)?|pivotal|crucial|vital|noteworthy|commendable|multifaceted|ever[- ]evolving|treasure trove|deep dive|dive deep|unlock(?:ing|s)? the)\b"),
        "Word that appears far more often in AI prose than in human prose.",
        "Use the plain word.",
        cost=1.5,
    ),
    Rule(
        "significance-tail", "warn",
        _r(r"(?:\bthis\b[^.!?]{0,40})?\b(?:speaks to|is a reflection of|represents a (?:shift|turning point|milestone)|marks a (?:new|turning|significant)|sets the stage for|paves the way for|opens the door to)\b"),
        "Sentence exists to assert importance.",
        "Delete it, or replace with what happens next.",
        cost=3.5,
    ),
    Rule(
        "rhetorical-question", "info",
        _r(r"(?m)^\s*(?:So )?(?:What|Why|How|Where)\b[^.!?\n]{0,60}\?\s*$"),
        "Rhetorical question as a heading or standalone line.",
        "Replace with the answer.",
        cost=2.0,
    ),
    Rule(
        "emoji-heading", "warn",
        _r(r"(?m)^#{1,6}\s*[\U0001F300-\U0001FAFF←-➿⬀-⯿]"),
        "Emoji in a heading.",
        "Name the section in words.",
        cost=3.0,
    ),
    Rule(
        "bold-lead-in", "info",
        _r(r"(?m)^\s*(?:[-*+]|\d+[.)])\s+\*\*[^*\n]{2,60}\*\*\s*[:—-]\s+\S"),
        "\"**Bold lead-in:** explanation\" list format.",
        "Fine in moderation. Too many in a row reads as generated.",
        cost=0.5,
    ),
]


# --- Machine residue -------------------------------------------------------
# Literal software leakage. These are bugs rather than style, so they are the
# most durable signals available and carry almost no false-positive risk.
# Sources: Wikipedia:Signs of AI writing (WP:AICATCH), 2026-08-30.

ARTIFACTS: list[Rule] = [
    Rule(
        "tool-artifact", "error",
        _r(r"(?:oaicite|oai_citation|contentReference|turn\d+search\d+|attributableIndex|"
           r"grok_card|grok_render_citation_card_json|ppl-ai-file-upload|\[cite:\s*\d+\]|"
           r"\[span_\d+\]\(start_span\))"),
        "Chatbot citation markup left in the text.",
        "Delete it and cite the source properly.",
        cost=8.0, surface="raw",
    ),
    Rule(
        "tracking-url", "error",
        _r(r"utm_source=(?:chatgpt\.com|claude\.ai|perplexity\.ai|gemini\.google\.com)"),
        "Chatbot tracking parameter left in a URL.",
        "Strip the query string.",
        cost=8.0, surface="raw",
    ),
    Rule(
        "assistant-residue", "error",
        _r(r"\b(?:as an AI language model|as of my (?:last|knowledge) (?:update|cutoff)|"
           r"I hope this helps|I'?m sorry, but I|certainly!|great question|"
           r"I don'?t have real-time access|based on (?:the )?available information)\b"),
        "Chat assistant boilerplate.",
        "Delete it.",
        cost=6.0,
    ),
    Rule(
        "unfilled-placeholder", "error",
        _r(r"\[(?:your name|insert[^\]]{0,30}|name here|company name|date here|x{3,}|todo)\]"
           r"|<!--\s*(?:add|insert|todo)[^>]*-->"),
        "Placeholder that was never filled in.",
        "Fill it in or cut it.",
        cost=6.0, surface="raw",
    ),
]

# --- Second-tier shapes ----------------------------------------------------
# Lower confidence than the table in the skill, kept separate so they can be
# switched off as a group if they cost more in false alarms than they earn.

EXTRA: list[Rule] = [
    Rule(
        "bold-label-period", "info",
        _r(r"(?m)^\s*(?:[-*+]|\d+[.)])\s+\*\*[^*\n]{2,50}\.\*\*\s+[A-Z]"),
        "List item with a bolded label ending in a period.",
        "Use a colon, or write it as a sentence.",
        cost=1.5,
    ),
    Rule(
        "question-then-answer", "warn",
        _r(r"(?<![?.!])\b(?:the (?:result|catch|problem|kicker|upshot|twist|reason)|so what|"
           r"the answer)\?\s+[A-Z]"),
        "Rhetorical question answered immediately.",
        "Write the answer as a statement.",
        cost=2.5,
    ),
    Rule(
        "despite-thrives", "warn",
        _r(r"\bdespite (?:these |the |its |ongoing )?(?:challenges|limitations|setbacks|concerns|criticism)\b"
           r"[^.!?]{0,60}\b(?:continues?|remains?|thrives?|persists?|is (?:still|poised))\b"),
        "Acknowledge-then-dismiss template.",
        "State the problem and what is being done about it.",
        cost=3.0,
    ),
    Rule(
        "hedge-stack", "info",
        _r(r"\b(?:could|may|might|can|would)\s+(?:potentially|possibly|eventually|ultimately|"
           r"conceivably|perhaps|arguably)\b"),
        "Two hedges stacked.",
        "Pick one, or state the condition.",
        cost=1.5,
    ),
    Rule(
        "negation-chain", "warn",
        _r(r"\bno\s+\w+,\s+no\s+\w+(?:,\s+(?:no\s+\w+|just\s+\w+))"),
        "\"No X, no Y, just Z\" drumroll.",
        "Say what it is.",
        cost=3.0,
    ),
    Rule(
        "copula-avoidance", "info",
        _r(r"\b(?:serves? as|stands? as|functions? as|acts? as an?)\b"),
        "Substitute for a plain \"is\".",
        "Use \"is\".",
        cost=1.0,
    ),
    Rule(
        "title-case-heading", "info",
        _r(r"(?m)^#{1,6}\s+(?:[A-Z][a-z]+\s+){2,}(?:[A-Z][a-z]+)\s*$"),
        "Heading in Title Case.",
        "Sentence case reads as written by a person.",
        cost=0.5,
    ),
    Rule(
        "imagine-a-world", "warn",
        _r(r"\b(?:imagine (?:a|an|if)|picture (?:a|this)|consider for a moment|"
           r"what if I told you)\b"),
        "Speculative opener.",
        "Start with the fact.",
        cost=3.0,
    ),
    Rule(
        "emoji-bullet", "info",
        _r(r"(?m)^\s*(?:[-*+]\s+)?[\U0001F300-\U0001FAFF\u2190-\u27BF\u2B00-\u2BFF]\s+\S"),
        "Emoji as a bullet or decoration.",
        "Use a plain bullet.",
        cost=1.0,
    ),
]


# --- Corroborated by other rule packs --------------------------------------
# Adapted from the MIT-licensed tbhb/vale-ai-tells and JMill/deslop, written
# from the described behaviour rather than copied, and narrowed for technical
# writing. Each was kept only after measuring it on the eval corpus.

MINED: list[Rule] = [
    Rule(
        "participial-opener", "warn",
        _r(r"(?m)(?:^|[.!?]\s+)(?:Having|Analy[sz]ing|Considering|Examining|Reflecting on|"
           r"Recogni[sz]ing|Acknowledging|Building on|Drawing on|Taking into account|"
           r"Looking at|Understanding|Leveraging|Harnessing)\s+[^,\n]{3,90},\s+"),
        "Sentence opens on a participial clause.",
        "Start with the subject and the verb.",
        cost=2.5,
    ),
    Rule(
        "anthropomorphic-credit", "warn",
        _r(r"\b(?:does?\s+(?:the\s+)?(?:heavy\s+lifting|real\s+work)|pulls?\s+its\s+weight|"
           r"pays?\s+for\s+itself|speaks?\s+for\s+itself|earns?\s+its\s+keep)\b"),
        "Credit handed to a piece of software as if it were a colleague.",
        "Say what the code does.",
        cost=2.5,
    ),
    Rule(
        "calibration-theatre", "info",
        _r(r"\bepistemic\s+status\b"
           r"|\b(?:my|the)\s+confidence\s+(?:here|in\s+this|in\s+that)\s+is\s+(?:low|medium|moderate|high)\b"
           r"|\bI\s*['’]?m\s+(?:fairly|reasonably|moderately)\s+(?:confident|uncertain)\b"
           r"|\bI\s*['’]?m\s+(?:about\s+|roughly\s+|around\s+)?\d{1,3}\s*%\s+(?:confident|sure)\b"
           r"|\bI\s+(?:hold|am\s+holding)\s+(?:this|that)\s+loosely\b"),
        "Confidence performed rather than used.",
        "State what you checked and what you did not.",
        cost=1.5,
    ),
    Rule(
        "incomplete-comparison", "warn",
        _r(r"\b(?:significantly|substantially|dramatically|considerably|markedly|vastly)\s+"
           r"(?:faster|slower|better|worse|higher|lower|cheaper|larger|smaller|more|less)\b"
           r"(?!\s+(?:than|compared|versus|vs\.?|relative|in\b))"),
        "Comparison with no baseline.",
        "Give the second term, or the two numbers.",
        cost=2.5,
    ),
    Rule(
        "universal-overclaim", "info",
        _r(r"\b(?:handles?|covers?|addresses?|eliminates?|resolves?|guarantees?)\s+"
           r"(?:all|every)\s+(?:known\s+|possible\s+|remaining\s+)?"
           r"(?:edge\s+cases?|scenarios?|concerns?|cases?|ambiguity|requirements?|issues?)\b"),
        "Clean-sweep claim.",
        "Say which cases, and which are still open.",
        cost=1.5,
    ),
]

ALL_RULES: list[Rule] = HARD + SHAPES + ARTIFACTS + EXTRA + MINED
GROUPS = {"hard": HARD, "shapes": SHAPES, "artifacts": ARTIFACTS, "extra": EXTRA, "mined": MINED}
BY_ID = {r.id: r for r in ALL_RULES}
