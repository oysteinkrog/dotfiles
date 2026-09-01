"""Split text into scoreable spans, skipping anything a person does not read as prose.

Markdown code fences, inline code, URLs, file paths, YAML front matter and
link targets are removed before scoring. They are machine text, and the skill
puts them out of scope. Positions are kept so findings can report line/column
in the original document.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass
class Span:
    """A run of characters in the source, with its offset."""

    text: str
    start: int

    @property
    def end(self) -> int:
        return self.start + len(self.text)


@dataclass
class Sentence:
    text: str
    start: int
    block_kind: str = "paragraph"  # paragraph | heading | list_item | table | quote | title


@dataclass
class Document:
    source: str
    prose: str  # source with non-prose regions blanked out (same length)
    sentences: list[Sentence] = field(default_factory=list)
    headings: list[Span] = field(default_factory=list)
    masked_regions: list[tuple[int, int, str]] = field(default_factory=list)

    def line_col(self, offset: int) -> tuple[int, int]:
        before = self.source[:offset]
        line = before.count("\n") + 1
        col = offset - (before.rfind("\n") + 1) + 1
        return line, col


# Regions that are not prose. Order matters: fenced code first.
# CommonMark allows a fence of three or more markers, and a longer fence is how
# you quote a block that itself contains ```. Matching only exactly three let the
# inner code leak into the prose and be scored as writing. The closer must be at
# least as long as the opener, which is also CommonMark.
_FENCE = re.compile(
    r"(?m)^(?P<fence>`{3,}|~{3,})[^\n]*\n"
    r"(?:.*?(?m:^)(?P=fence)`*~*[ \t]*$|.*\Z)", re.S)
_FRONTMATTER = re.compile(r"\A---\n.*?\n---[ \t]*$", re.S | re.M)
# An indented line is code only when it is not a continuation of a list. Nested
# bullets and list continuation paragraphs are indented by four spaces in normal
# CommonMark, and masking them meant a whole nested list was never scored: writing
# slop as a sub-bullet made it invisible. The lookbehind requires the line above
# to be blank or itself indented code, which is what CommonMark requires for an
# indented code block anyway.
_INDENTED_CODE = re.compile(
    r"(?m)^(?: {4,}|\t)(?![-*+][ \t]|\d+[.)][ \t])\S[^\n]*$")
_INLINE_CODE = re.compile(r"`[^`\n]+`")
_URL = re.compile(r"https?://\S+|\bwww\.\S+")
_MD_LINK_TARGET = re.compile(r"\]\([^)\s]+(?:\s+\"[^\"]*\")?\)")
_HTML_TAG = re.compile(r"</?[a-zA-Z][^>\n]*>")
_PATH = re.compile(r"(?<![\w.])(?:[A-Za-z]:)?[~./][\w./~-]*/[\w./~-]+")
_MENTION = re.compile(r"(?<![\w])[@#][\w./-]+")
_MATH = re.compile(r"\$\$.*?\$\$|\$[^$\n]+\$", re.S)
_BADGE = re.compile(r"!\[[^\]]*\]\([^)]*\)")

_MASKS: list[tuple[str, re.Pattern[str]]] = [
    ("frontmatter", _FRONTMATTER),
    ("fence", _FENCE),
    ("math", _MATH),
    ("badge", _BADGE),
    ("indented_code", _INDENTED_CODE),
    ("inline_code", _INLINE_CODE),
    ("link_target", _MD_LINK_TARGET),
    ("html", _HTML_TAG),
    ("url", _URL),
    ("path", _PATH),
    ("mention", _MENTION),
]


# A run of text in a script other than Latin. Masking it does two separate jobs.
# It stops a quoted paragraph of Chinese or Russian being charged as rare English,
# and it stops that same paragraph exempting the whole document: the not-English
# test measures the share of Latin characters, so one non-Latin paragraph pushed a
# document under the threshold, and a document called not-English is scored not at
# all. Measured 2026-09-01: one paragraph of Chinese appended to an inflated
# English passage took it from 4.4 and a failed gate to 100 and no findings.
#
# The floor of 12 characters keeps single symbols ordinary. A micro sign in a
# tolerance, an ohm in a spec, a Greek letter in a formula and a name with a
# diacritic are all prose, not a foreign-language quotation.
_NON_LATIN_MIN = 12
_NON_LATIN_LETTER = re.compile(r"[^\W\d_]", re.UNICODE)
_NON_LATIN_RUN = re.compile(
    r"[\u0370-\u1cff\u1f00-\u1fff\u2c00-\u2dff\u3040-\u9fff"
    r"\ua000-\uabff\uac00-\ud7af\uf900-\ufaff]"
    r"[\s\u3000-\u303f\uff00-\uffef\w\d.,;:!?()\[\]'\"/-]*"
    r"[\u0370-\u1cff\u1f00-\u1fff\u2c00-\u2dff\u3040-\u9fff"
    r"\ua000-\uabff\uac00-\ud7af\uf900-\ufaff]"
)


def _is_non_latin(ch: str) -> bool:
    return ch.isalpha() and ord(ch) >= 0x250


def mask_non_prose(source: str) -> tuple[str, list[tuple[int, int, str]]]:
    """Blank out non-prose regions, preserving offsets and line breaks."""
    chars = list(source)
    regions: list[tuple[int, int, str]] = []
    for m in _NON_LATIN_RUN.finditer(source):
        s, e = m.span()
        if sum(1 for i in range(s, e) if _is_non_latin(source[i])) < _NON_LATIN_MIN:
            continue
        regions.append((s, e, "non_latin"))
        for i in range(s, e):
            if chars[i] != "\n":
                chars[i] = " "
    for kind, pattern in _MASKS:
        for m in pattern.finditer("".join(chars)):
            s, e = m.span()
            if all(chars[i] == " " or chars[i] == "\n" for i in range(s, e)):
                continue
            regions.append((s, e, kind))
            for i in range(s, e):
                if chars[i] != "\n":
                    chars[i] = " "
    return "".join(chars), regions


_HEADING = re.compile(r"(?m)^[ \t]{0,3}(#{1,6})[ \t]+(?P<text>[^\n]+?)[ \t]*#*[ \t]*$")
_SETEXT = re.compile(r"(?m)^(?P<text>[^\n#>\-*][^\n]*)\n[ \t]{0,3}(?:=+|-{2,})[ \t]*$")
_LIST_MARK = re.compile(r"(?m)^[ \t]*(?:[-*+]|\d+[.)])[ \t]+")
_QUOTE_MARK = re.compile(r"(?m)^[ \t]*>[ \t]?")
_TABLE_ROW = re.compile(r"(?m)^[ \t]*\|.*\|[ \t]*$")
_TABLE_SEP = re.compile(r"(?m)^[ \t]*\|?[ \t]*:?-{2,}:?[ \t]*(\|[ \t]*:?-{2,}:?[ \t]*)*\|?[ \t]*$")

# Abbreviations that end in a period but do not end a sentence.
_ABBREV = {
    "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e",
    "fig", "no", "vol", "approx", "al", "inc", "ltd", "co", "dept", "est",
    "min", "max", "sec", "cf", "ca", "ver", "rev", "ref", "eq", "ch",
}

_SENT_END = re.compile(r"[.!?]['\")\]]*(?=\s|$)")


def split_sentences(text: str, base: int = 0) -> list[tuple[str, int]]:
    """Split a prose block into sentences. Offsets are absolute."""
    out: list[tuple[str, int]] = []
    start = 0
    for m in _SENT_END.finditer(text):
        end = m.end()
        head = text[start:end]
        stripped = head.rstrip()
        # Do not split on an abbreviation or a decimal point.
        last = re.search(r"([A-Za-z.]+)\.$", stripped)
        if last and last.group(1).lower().strip(".") in _ABBREV:
            continue
        if re.search(r"\d\.$", stripped) and end < len(text) and text[end:end + 2].strip()[:1].isdigit():
            continue
        # A single capital letter before the period is an initial.
        if re.search(r"(?:^|\s)[A-Z]\.$", stripped):
            continue
        if stripped:
            out.append((stripped, base + start + (len(head) - len(head.lstrip()))))
        start = end
    tail = text[start:].strip()
    if tail:
        lead = len(text[start:]) - len(text[start:].lstrip())
        out.append((tail, base + start + lead))
    return out


def parse(source: str) -> Document:
    prose, regions = mask_non_prose(source)
    doc = Document(source=source, prose=prose, masked_regions=regions)

    consumed = [False] * len(prose)

    def take(s: int, e: int) -> None:
        for i in range(s, e):
            consumed[i] = True

    for m in _HEADING.finditer(prose):
        span = Span(m.group("text").strip(), m.start("text"))
        if span.text:
            doc.headings.append(span)
            doc.sentences.append(Sentence(span.text, span.start, "heading"))
        take(*m.span())
    for m in _SETEXT.finditer(prose):
        if any(consumed[m.start():m.end()]):
            continue
        span = Span(m.group("text").strip(), m.start("text"))
        if span.text:
            doc.headings.append(span)
            doc.sentences.append(Sentence(span.text, span.start, "heading"))
        take(*m.span())
    for m in _TABLE_SEP.finditer(prose):
        take(*m.span())

    # Everything else: walk line blocks.
    line_start = 0
    for raw_line in prose.split("\n"):
        s = line_start
        line_start += len(raw_line) + 1
        if not raw_line.strip() or all(consumed[i] for i in range(s, s + len(raw_line)) if raw_line):
            continue
        if any(consumed[i] for i in range(s, s + len(raw_line))):
            continue
        kind = "paragraph"
        body = raw_line
        off = s
        qm = _QUOTE_MARK.match(raw_line)
        if qm:
            kind = "quote"
            off += qm.end()
            body = raw_line[qm.end():]
        lm = _LIST_MARK.match(body)
        if lm:
            kind = "list_item"
            off += lm.end()
            body = body[lm.end():]
        if _TABLE_ROW.match(raw_line):
            kind = "table"
            for cell in body.strip().strip("|").split("|"):
                idx = body.find(cell, 0)
                cell_text = cell.strip()
                if cell_text:
                    doc.sentences.append(Sentence(cell_text, off + max(idx, 0), "table"))
            continue
        for text, offset in split_sentences(body, off):
            doc.sentences.append(Sentence(text, offset, kind))

    doc.sentences.sort(key=lambda x: x.start)
    return doc


_WORD = re.compile(r"[A-Za-z][A-Za-z'’-]*")


def words(text: str) -> list[tuple[str, int]]:
    """Word tokens with offsets, relative to `text`."""
    return [(m.group(0), m.start()) for m in _WORD.finditer(text)]


_QUOTED = re.compile(r"[\"\u201c]([^\"\u201c\u201d\n]{12,400})[\"\u201d]")


def quote_spans(text: str) -> list[tuple[int, int]]:
    """Ranges holding someone else's words.

    The skill puts quoted text out of scope, so a rule must not fire on a
    sentence the writer is reporting rather than writing. Only runs of at
    least three words count, so a quoted identifier or a single quoted term
    still gets scored normally.
    """
    spans: list[tuple[int, int]] = []
    for m in _QUOTED.finditer(text):
        if len(m.group(1).split()) >= 3:
            spans.append(m.span())
    return spans


def in_spans(pos: int, spans: list[tuple[int, int]]) -> bool:
    return any(s <= pos < e for s, e in spans)


def fence_spans(text: str) -> list[tuple[int, int]]:
    """Ranges a raw-surface rule must not look inside.

    Fenced blocks and inline code spans. A machine-residue rule runs on the raw
    source so it can see inside URLs, which means it also sees the examples in a
    document that documents it. A marker in backticks is being quoted; a real
    leak appears bare.
    """
    return [m.span() for m in _FENCE.finditer(text)] + \
           [m.span() for m in _INLINE_CODE.finditer(text)]
