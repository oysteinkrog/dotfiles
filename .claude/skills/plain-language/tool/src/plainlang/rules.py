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
        _r("\\b(?:(?:is|are|was|were)\\s*n[o'’]t|['’](?:s|re)\\s+not)\\s+(?:just\\s+|really\\s+|simply\\s+)?(?:an?|the|this|that|these|those|its|their|our|your|his|her|my|one|another)\\s+[^.,;:!?]{1,45},\\s*(?:it|that|they)['’](?:s|re)\\b"),
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
        _r("\\b(?:(?:is|are|was|were)\\s*n[o'’]t|['’](?:s|re)\\s+not)\\s+about\\s+(?!\\d)[^.!?;]{0,60}(?:[.!?]\\s+)?\\s*(?:it['’]s|that['’]s|they['’]re|they\\s+are|it\\s+is)\\s+about\\s+(?!\\d)"),
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
        _r("\\bin\\s+(?:(?:today['’]s|the\\s+modern|this\\s+modern|our\\s+modern|the\\s+present[- ]day)\\s+(?:[a-z][a-z-]*\\s+){0,3}(?:world|landscape|market|marketplace|era|age|climate|environment|industry|ecosystem|economy|culture|society)|today['’]s\\s+(?:fast|ever|rapidly|quickly|hyper|increasingly|highly)-[a-z]+|an?\\s+increasingly\\s+[a-z][a-z-]*|an?\\s+(?:age|era)\\b|the\\s+(?:age|era)\\s+of)\\b[^.,;:!?]{0,40},"),
        "Scene-setting opener.",
        "Delete it.",
        cost=4.0,
    ),
    Rule(
        "whether-youre", "warn",
        _r("(?:\\A|[.!?]\\s+|\\n[ \\t]*\\n\\s*)whether\\s+you(?:['’]re|\\s+are)\\b(?:[^.!?]|\\.(?=\\d)){1,60}\\bor\\b(?:[^.,!?]|\\.(?=\\d)){1,30},"),
        "\"Whether you're X or Y\" audience framing.",
        "Address the reader once, directly.",
        cost=2.5,
    ),
    Rule(
        "vague-attribution", "warn",
        _r('\\b(?:(?:many|some|most)\\s+(?:developers?|engineers?|programmers?|people|coaches|practitioners|scientists?|academics?|teams|users?|experts?|researchers?)|experts?|researchers?|studies|analysts?|critics?|observers?|commentators?|pundits?|industry\\s+(?:leaders|watchers|experts))\\s+(?:agrees?|says?|argues?|believes?|suggests?|notes?|claims?|maintains?|contends?|points?\\s+out|shows?|have\\s+(?:noted|argued|shown|found|said))\\b|\\b(?:many|some)\\s+(?:agree|say|argue|believe|suggest|contend|maintain|insist)\\b|\\bresearch\\s+(?:suggests?|shows?|indicates?|says?)\\b|\\bit\\s+(?:is|was)\\s+(?:widely|generally|commonly|broadly|often|well)\\s+(?:believed|accepted|assumed|understood|held|thought|agreed|regarded|considered)\\b'),
        "Vague attribution with no source.",
        "Name the source and the date.",
        cost=3.0,
    ),
    Rule(
        "worth-noting", "warn",
        _r("\\b(?<!\\bwhether\\s)(?<!\\bif\\s)(?:it'?s|it is)\\s+(?:worth|important|essential|crucial|useful|worthwhile|helpful)\\s+(?:noting|mentioning|highlighting|remembering|emphasi[sz]ing|pointing out|to note|to remember|to mention|to understand|to highlight|to point out|to emphasi[sz]e)\\s+that\\b|\\bit bears (?:noting|mentioning|repeating|highlighting)\\s+that\\b|\\b(?:one thing|another thing|something) worth (?:noting|mentioning|highlighting|pointing out|remembering)\\b|(?:^|[.!?]\\s+|\\n)\\s*notably,"),
        "Hedge before the point.",
        "Make the point.",
        cost=3.0,
    ),
    Rule(
        "at-its-core", "warn",
        _r('\\bat (?:its|their) (?:core|essence|heart|simplest|most basic level|most fundamental level)\\s*,|\\bat a fundamental level\\b|\\b(?:in essence|at the end of the day|when all is said and done|the bottom line is|fundamentally speaking|in the final analysis)\\b|(?:^|[.!?]\\s+|\\n)\\s*fundamentally,'),
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
        _r('\\b(?:plays?|played|playing|serves?|served|serving|has|have|had)\\s+an?\\s+(?:vital|significant|crucial|pivotal|key|central|critical|important|essential|instrumental|integral|major|indispensable)\\s+role\\b'),
        "Significance inflation.",
        "Say what it actually does.",
        cost=3.0,
    ),
    Rule(
        "broader-landscape", "warn",
        _r('\\b(?:broader|wider|larger|evolving|shifting|changing|ever-changing|global|overall)\\s+(?:\\w+\\s+)?(?:landscape|ecosystem|tapestry|fabric|paradigm|arena|milieu)[ \\t]*(?:[,.;:\\n]|of\\b|for\\b|$)|\\bagainst the backdrop of\\b|\\bin the grand scheme of things\\b'),
        "Abstract scene-setting.",
        "Name the thing that changed.",
        cost=4.0,
    ),
    Rule(
        "journey-framing", "warn",
        _r('\\b(?:a|an|the|our|my|this|your|their)\\s+(?:(?!user\\b|customer\\b|coach(?:es)?\\b)\\w+\\s+)?journey\\s+(?:through|towards?|of|for|so far|we|has|had|begins?|began|started|continues|ends)\\b|\\bembark(?:ed|s|ing)?\\s+on\\s+(?:a|an|the|our|this|their)\\s+(?:\\w+\\s+)?journey\\b|\\balong (?:this|that|our|my) journey\\b'),
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
        _r('\\bin order (?:to|for\\b[^.!?;,\\n]{0,40}?\\bto)\\s+(?:avoid|allow|enable|ensure|prevent|stop|keep|make|get|give|take|put|set|let|do|be|have|use|reuse|run|test|verify|check|confirm|validate|fix|repair|reproduce|release|build|rebuild|compile|deploy|ship|land|merge|rebase|commit|push|pull|sync|flush|clean|clear|reset|restart|start|launch|open|close|load|save|read|write|send|receive|handle|catch|throw|log|track|trace|measure|compute|calculate|generate|emit|render|draw|display|show|hide|report|expose|hook|wire|bind|register|resolve|inject|mock|stub|seed|arm|disarm|capture|record|stream|decode|encode|scrub|seek|index|import|export|convert|migrate|upgrade|bump|pin|apply|remove|delete|add|create|update|edit|rename|move|copy|split|reduce|improve|optimi[sz]e|match|align|adjust|tune|calibrate|normali[sz]e|filter|sort|group|compare|diff|find|search|locate|identify|detect|isolate|debug|diagnose|investigate|understand|know|see|tell|explain|document|describe|name|label|mark|flag|gate|block|unblock|guard|support|cover|satisfy|meet|reach|achieve|maintain|preserve|drop|skip|ignore|suppress|force|trigger|fire|invoke|call|dispatch|schedule|throttle|debounce|retry|wait|poll|watch|monitor|observe|subscribe|dispose|free|allocate|cache|store|persist|serialize|deserialize|parse|format|escape|strip|trim|wrap|work|help|focus|separate|share|limit|cap|extend|simplify|clarify|pick|choose|select|decide|plan|design|refactor|rewrite|port|replace|swap|switch|toggle|turn|bring|leave|surface|silence|widen|narrow|speed|serve|point|read)\\b'),
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
        _r('(?m)(?:(?:^[ \\t]*(?:>[ \\t]*)?|(?<=[.!?]\\s)(?<![0-9]\\.\\s)|(?<=[.!?]["\')]\\s))(?:Moreover|Furthermore|Additionally|In addition|Notably|Importantly|Ultimately|Overall|In conclusion|To summari[sz]e|In summary)\\b[ \\t]*[,:]|^[ \\t]*(?:>[ \\t]*)?(?:[-*+][ \\t]+|\\d+[.)][ \\t]+)(?:Moreover|Furthermore|Additionally|In addition|Notably|Importantly|Ultimately|Overall|In conclusion|To summari[sz]e|In summary)\\b[ \\t]*,)'),
        "Conjunctive opener stacked at the start of a sentence.",
        "Join the sentences, or just state the next fact.",
        cost=1.5,
    ),
    Rule(
        "robust-hype", "warn",
        _r('\\b(?:best[- ]in[- ]class|world-class|cutting[- ]edge|enterprise[- ]grade|industry[- ]leading|future[- ]proof|turnkey|unparalleled|groundbreaking|revolutionary|game[- ]?chang(?:er|ers|ing)|blazing(?:ly)?[- ]fast|best[- ]in[- ]breed)\\b|\\bstate-of-the-art\\b|(?<!the )\\bstate of the art\\b|\\bunmatched[ \\t]+(?:accuracy|precision|performance|reliability|quality|speed|power|value|experience|coverage|control|clarity|detail|results?|flexibility)\\b|\\b(?:robust|comprehensive|powerful|seamless|elegant|effortless|scalable|innovative|holistic)\\b[ \\t]*(?:,[ \\t]*|[ \\t]+(?:and|yet|but)[ \\t]+)(?:\\w+ly[ \\t]+)?(?:robust|comprehensive|powerful|seamless|elegant|effortless|scalable|innovative|holistic|intuitive|flexible|reliable|performant|extensible|rock[- ]solid|state-of-the-art|best[- ]in[- ]class|world-class|cutting[- ]edge|enterprise[- ]grade|industry[- ]leading|future[- ]proof)\\b|\\b(?:intuitive|reliable|performant|extensible|rock[- ]solid|lightning[- ]fast)\\b[ \\t]*(?:,[ \\t]*|[ \\t]+(?:and|yet|but)[ \\t]+)(?:\\w+ly[ \\t]+)?(?:robust|comprehensive|powerful|seamless|elegant|effortless|scalable|innovative|holistic)\\b'),
        "Hype register.",
        "Say what it does and give the number.",
        cost=3.0,
    ),
    Rule(
        "promo-adjectives", "info",
        _r('\\b(?:innovative|industry[- ]leading|revolutionar(?:y|ily)|game[- ]?chang(?:er|ers|ing)|unparalleled|groundbreaking|world-class|best[- ]in[- ]class|cutting[- ]edge|state-of-the-art|stunning|breathtaking|sleek|effortless(?:ly)?|beautifully crafted|vibrant|rich tapestry|must-have|must-visit|renowned|nestled|boasts|in the heart of)\\b|\\bunmatched[ \\t]+(?:accuracy|precision|performance|reliability|quality|speed|power|value|experience|coverage|control|clarity|detail|results?|flexibility)\\b'),
        "Promotional adjective.",
        "Cut it or replace with a fact.",
        cost=2.0,
    ),
    Rule(
        "ai-vocab", "info",
        _r('\\bleverag(?:es|ed|ing)(?![-\\w])|\\b(?:to|can|could|should|would|will|shall|must|may|might|we|you|they|it|and|then|please|simply)[ \\t]+leverage[ \\t]+(?:the|our|your|their|its|this|that|these|those|existing|a|an)\\b|\\butili[sz](?:e|es|ed|ing)(?![-\\w])|\\b(?:in|into|within|across|throughout) the realm of\\b|(?<!the )\\bunderscor(?:es|ed|ing)[ \\t]+(?:the|this|that|a|an|how|why|just|our|its|their)\\b|\\bshowcas(?:e|es|ed|ing)(?![-\\w])|\\bfacilitat(?:e|es|ed|ing)\\b|\\b(?:plethora|myriad|multifaceted|intricacies|treasure trove|ever[- ]evolving|commendable|meticulous(?:ly)?|paradigm shift|rich tapestry)\\b|\\b(?:deep dive|dive deep)\\b|\\bunlock(?:s|ing)?[ \\t]+the[ \\t]+(?:power|potential|full[ \\t]+(?:power|potential|value))\\b|\\bnavigat(?:e|es|ing) the (?:complexit\\w+|landscape|nuances?|challenges?)\\b'),
        "Word that appears far more often in AI prose than in human prose.",
        "Use the plain word.",
        cost=1.5,
    ),
    Rule(
        "significance-tail", "warn",
        _r("\\b(?:cannot|can ?not|can't|could not)[ \\t]+be[ \\t]+over(?:stated|emphasi[sz]ed)\\b|\\b(?:hard|difficult|impossible)[ \\t]+to[ \\t]+over(?:state|emphasi[sz]e)\\b|\\bis[ \\t]+(?:a[ \\t]+)?(?:really[ \\t]+|truly[ \\t]+)?big[ \\t]+deal\\b|\\b(?:marks|represents|signals)[ \\t]+(?:a|an)[ \\t]+(?:(?:major|real|significant|important|new|genuine|fundamental|huge|profound)[ \\t]+)?(?:milestone|turning point|watershed|inflection point|sea change|paradigm shift)\\b|\\b(?:marks|represents|signals)[ \\t]+(?:a|an)[ \\t]+(?:major|real|significant|important|new|genuine|fundamental|huge|profound)[ \\t]+(?:step (?:forward|change)|shift|leap|change|advance)\\b|\\bserves?[ \\t]+as[ \\t]+(?:a|the)[ \\t]+(?:foundation|cornerstone|springboard|launching pad|stepping stone)\\b|\\bmatters?[ \\t]+more[ \\t]+than[ \\t]+(?:almost[ \\t]+|nearly[ \\t]+|just about[ \\t]+)?(?:anything|everything)\\b|\\b(?:this|that|it)[ \\t]+(?:\\w+[ \\t]+)?is[ \\t]+(?:hugely[ \\t]+|deeply[ \\t]+|truly[ \\t]+)?significant[ \\t]+for\\b|\\bspeaks[ \\t]+to[ \\t]+(?:the[ \\t]+)?(?:importance|value|power|strength)\\b|\\bis[ \\t]+a[ \\t]+reflection[ \\t]+of\\b|\\bsets[ \\t]+the[ \\t]+stage[ \\t]+for\\b|\\bpaves[ \\t]+the[ \\t]+way[ \\t]+for\\b|\\bopens[ \\t]+the[ \\t]+door[ \\t]+to\\b"),
        "Sentence exists to assert importance.",
        "Delete it, or replace with what happens next.",
        cost=3.5,
    ),
    Rule(
        "rhetorical-question", "info",
        _r('(?m)\\bever wondered\\b|\\bwhat could possibly go wrong\\b|\\bwhy (?:does|do|is) (?:this|that|it) matter\\b(?:[^.?!\\n]|\\.(?=\\d)){0,40}\\?|(?<=[a-z] )what (?:does|do|is) (?:this|that|it) mean\\b(?:[^.?!\\n]|\\.(?=\\d)){0,40}\\?|^[#>*\\s-]*(?:But|So|And)\\s+(?:which|what|why|how|who|where)\\b(?:[^.?!\\n]|\\.(?=\\d)){0,70}\\?|(?<=[.!?] )But\\s+(?:which|what|why|how|who|where)\\b(?:[^.?!\\n]|\\.(?=\\d)){0,70}\\?|(?:^[#>*\\s-]*|(?<=[.!?] ))Is (?:that|this) really\\b(?:[^.?!\\n]|\\.(?=\\d)){0,70}\\?|^#{1,6}\\s*(?:Ready|Want|Curious|Wondering|Looking)\\s+to\\b[^\\n?]{0,70}\\?\\s*$'),
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
        _r('(?:\\*\\*(?!(?:bug|reported by|fix version|fixed|changed|added|removed|deprecated|security|known issues?|environment|severity|priority|assignee|reporter|component)\\s*:)[^*\\n]{1,40}(?::\\*\\*|\\*\\*\\s*:)(?:[^*]{0,200})){2}\\*\\*(?!(?:bug|reported by|fix version|fixed|changed|added|removed|deprecated|security|known issues?|environment|severity|priority|assignee|reporter|component)\\s*:)[^*\\n]{1,40}(?::\\*\\*|\\*\\*\\s*:)'),
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
        _r('(?<![`\'"‘’“”])\\b(?:cite)?turn\\d+(?:search|view|news|forum|image|video|file)\\d+\\b(?![\'"’”])|(?<![`\'"‘’“”])\\b(?:oaicite|oai_citation|contentReference|attributableIndex|grok_card|grok_render_citation_card_json|ppl-ai-file-upload)\\b|【\\d+†[^】\\n]{0,40}】|(?<![\'"‘’“”])\\[cite:\\s*\\d+\\](?![\'"’”])|\\[span_\\d+\\]\\(start_span\\)'),
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
        _r("(?m)^\\s*(?:Certainly\\s*[!,]|Sure thing[!,]|Absolutely[!,]|(?:Great|Good|Excellent) question\\b)|\\bas an AI language model\\b|\\bas of my (?:last|knowledge) (?:update|cutoff)\\b|\\bI don'?t have real-time access\\b|\\bI(?:'ve| have) gone ahead and\\b|\\b(?:I hope|hope) (?:this|that) helps\\b|\\blet me know if you'?d like\\b|\\bfeel free to (?:reach out|ask|let me know)\\b"),
        "Chat assistant boilerplate.",
        "Delete it.",
        cost=6.0,
    ),
    Rule(
        "unfilled-placeholder", "error",
        _r('(?m)(?:\\[(?:your\\s+name|company(?:\\s+name)?|insert[^\\]\\n]{0,30}|name\\s+here|date\\s+here|x{3,}|todo|tbd|author|email|placeholder)\\](?!\\()|\\b(?:by|on)\\s+\\[(?:name|date)\\](?!\\()|<[a-z0-9_]{0,24}_here>|(?<!`)\\b(?:fixes|closes|resolves|refs|ref)\\s*:\\s*[a-z]{2,}-x{3,}\\b|\\b\\w+\\s*:\\s*(?:tbd|todo)\\b(?=\\s*(?:[.\\n]|$))|\\blorem\\s+ipsum\\b|\\binsert\\s+(?!(?:the|a|an|this|that|these|those|each|both|one|it)\\b)(?:\\w+\\s+){0,3}here\\b|<!--\\s*(?:add|insert|todo|fixme)[^>]*-->)(?![^`\\n]*`)'),
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
        _r("\\?\\s+(?:because\\b|\\d)|\\bso what\\b(?:[^.?!\\n]|\\.(?=\\d)){0,40}\\?|\\bwas th(?:at|is) enough\\?|\\bwhat(?:'s| is| was) going on(?: here)?\\?|\\bwhy should (?:you|we|i) (?:care|worry)\\?|\\bwh(?:y|at) does (?:that|this|it) matter\\?|\\bwhat does (?:that|this|it) mean(?: (?:for|in) [^.?!\\n]{0,30})?\\?|\\b(?:who cares|what gives|why bother|sound familiar)\\?|\\?\\s+(?:it|they|that|this) (?:do(?:es)?|is|are|was|were|can|will|has|have)\\b|\\?\\s+(?:the (?:short|honest) answer|the answer is)\\b"),
        "Rhetorical question answered immediately.",
        "Write the answer as a statement.",
        cost=2.5,
    ),
    Rule(
        "despite-thrives", "warn",
        _r('\\b(?:despite|in\\s+spite\\s+of|although|even\\s+though|even\\s+so|even\\s+with|nevertheless|nonetheless|notwithstanding|regardless\\s+of|while)\\b(?:[^.!?]|\\.\\d){0,80}?(?:\\bthriv(?:e|es|ing)\\b|\\bflourish(?:es|ing)?\\b|\\bgo(?:es)?\\s+from\\s+strength\\s+to\\s+strength\\b|\\b(?:continue|continues|keep|keeps)\\s+(?:to\\s+)?(?:shine|shining|thrive|thriving|impress|impressing|excel|excelling)\\b|\\b(?:continue|continues|keep|keeps)\\s+(?:to\\s+)?(?:deliver|delivering|grow|growing|perform|performing|improve|improving)\\s+(?:\\w+\\s+){0,2}(?:strongly|beautifully|admirably|remarkably|impressively|handsomely|nicely)\\b|\\b(?:deliver|delivering|delivers)\\s+a\\s+steady\\s+stream\\s+of\\s+(?:green|glowing|positive|healthy|strong|successful|happy|clean)\\b|\\bheld\\s+up\\s+(?:beautifully|admirably|remarkably|nicely)\\b|\\b(?:remain|remains|stay|stays)\\s+(?:(?:remarkably|impressively|surprisingly|exceptionally|admirably|notably|refreshingly)\\s+)?(?:resilient|confident|optimistic|unshaken|buoyant|upbeat)\\b|\\b(?:remain|remains|stay|stays)\\s+(?:remarkably|impressively|surprisingly|exceptionally|admirably|notably)\\s+(?:robust|strong|healthy|solid)\\b|\\b(?:remain|remains|stay|stays)\\s+in\\s+(?:excellent|great|good|robust|rude)\\s+(?:health|shape|form|standing)\\b)'),
        "Acknowledge-then-dismiss template.",
        "State the problem and what is being done about it.",
        cost=3.0,
    ),
    Rule(
        "hedge-stack", "info",
        _r('(?:\\b(?:possibly|potentially|perhaps|maybe|probably|conceivably|arguably|presumably|seemingly|seems?\\s+likely|appears?\\s+likely)\\b(?:(?!\\b(?:but|though|although|however|whereas|yet|while|and|or|nor|so|because|since)\\b)(?:[^.!?;:]|\\.\\d)){0,40}?\\b(?:could|may|might|possibly|potentially|perhaps|maybe|probably|conceivably|arguably|presumably|seemingly|seems?\\s+likely|appears?\\s+likely)\\b|\\b(?:could|may|might)\\b(?:(?!\\b(?:but|though|although|however|whereas|yet|while|and|or|nor|so|because|since)\\b)(?:[^.!?;:]|\\.\\d)){0,40}?\\b(?:possibly|potentially|perhaps|maybe|probably|conceivably|arguably|presumably|seemingly)\\b)'),
        "Two hedges stacked.",
        "Pick one, or state the condition.",
        cost=1.5,
    ),
    Rule(
        "negation-chain", "warn",
        _r('(?:^|(?<=\\n)|(?<=[.!?][ \\t]))no\\s+(?:\\w+[\\s-]+){0,2}\\w+,\\s+no\\s+(?:\\w+[\\s-]+){0,2}\\w+,\\s+(?:just|only|simply|merely|purely)\\s+(?!as\\b|like\\b|then\\b|when\\b|before\\b|after\\b|because\\b|if\\b|so\\b|about\\b|over\\b|under\\b|\\d)'),
        "\"No X, no Y, just Z\" drumroll.",
        "Say what it is.",
        cost=3.0,
    ),
    Rule(
        "copula-avoidance", "info",
        _r("\\b(?:serves?|serving)\\s+as\\s+(?:an?|the|its|their|our|your|this|that|these|those)\\b|\\bconstitut(?:es|ed|ing)\\s+(?:an?|the)\\b|\\b(?:thought|regarded|viewed|construed|conceived)\\s+of\\s+as\\s+(?:an?|the)\\b|\\brepresents?\\s+(?:an?|the)\\b|(?:^|(?<=\\n)|(?<=[.!?][ \\t]))(?:(?!\\b(?:treat|treats|treated|regard|regards|regarded|consider|considers|considered|use|uses|used|see|sees|seen|view|views|viewed|describe|describes|described|rename|renames|plot|plots|list|lists|count|counts|show|shows|know|known|define|defines|classify|classifies|mark|marks|report|reports|leave|leaves|keep|keeps|take|takes)\\b)(?:[^.!?\\n]|\\.(?=\\S))){0,120}?\\b(?:exists?|existing|stands?|acts?|functions?|functioning)\\s+as\\s+(?:an?|the|its|their|our|your|this|that)\\s+(?:[\\w'’-]+\\s+){0,2}[\\w'’-]+\\s+(?:of|in|for|with|between|to|across|behind|under)\\b"),
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
        _r("\\b(?<!not )(?<!n't )(?<!hard to )(?<!ficult to )(?:imagine|picture|envision|visuali[sz]e)\\s+(?:a|an)\\s+(?:\\w+\\s+){0,2}(?:where|in which|without|with no)\\b|\\bpicture this\\s*(?=[:;.!?,]|$)|\\b(?:imagine|picture|envision|consider)\\s+for a moment\\b|\\b(?:imagine|envision)\\s+if\\b|\\bwhat if I told you\\b"),
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
