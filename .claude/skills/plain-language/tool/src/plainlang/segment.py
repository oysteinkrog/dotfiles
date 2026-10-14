"""Split text into scoreable spans, skipping anything a person does not read as prose.

Markdown code fences, inline code, URLs, file paths, YAML front matter and
link targets are removed before scoring. They are machine text, and the skill
puts them out of scope. Positions are kept so findings can report line/column
in the original document.
"""

from __future__ import annotations

import bisect
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
    block_kind: str = (
        "paragraph"  # paragraph | heading | list_item | table | quote | title
    )


@dataclass
class Document:
    source: str
    prose: str  # source with non-prose regions blanked out (same length)
    sentences: list[Sentence] = field(default_factory=list)
    headings: list[Span] = field(default_factory=list)
    masked_regions: list[tuple[int, int, str]] = field(default_factory=list)

    def line_col(self, offset: int) -> tuple[int, int]:
        # Slicing and counting from the start on every call made scoring quadratic:
        # a 1 MB document took 490 seconds. The newline offsets are found once.
        nl = self.__dict__.get("_newlines")
        if nl is None:
            nl = self.__dict__["_newlines"] = [
                m.start() for m in re.finditer("\n", self.source)
            ]
        i = bisect.bisect_left(nl, offset)
        return i + 1, offset - (nl[i - 1] + 1 if i else 0) + 1


# Regions that are not prose. Order matters: fenced code first.
# CommonMark allows a fence of three or more markers, and a longer fence is how
# you quote a block that itself contains ```. Matching only exactly three let the
# inner code leak into the prose and be scored as writing. The closer must be at
# least as long as the opener, which is also CommonMark. Either fence line may be
# indented, because a code block inside a list item is indented to the item's
# text. Anchoring at column 0 left that code scored as prose, so a `--` in a
# shell command was charged as an em dash.
#
# An unclosed fence runs to the end of the file, as in CommonMark. A fence line
# indented four or more spaces counts only inside a list item, where code is
# indented to the item's text. Outside a list such a line is indented code, and
# treating it as a fence hid prose from the scorer: unclosed, it masked the rest
# of the document; closed by a later unrelated fence, it masked the paragraphs
# in between. A regex cannot see list context, and the one that tried
# backtracked quadratically on long blank lines, so this is a line scanner.
_FENCE_OPEN = re.compile(r"(?P<indent>[ \t]*)(?P<fence>`{3,}|~{3,})")
_LIST_ITEM = re.compile(r"[ \t]*(?:[-*+]|\d+[.)])[ \t]+")
# Lines that end a paragraph, so they are never its lazy continuation.
_THEMATIC = re.compile(r" {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$")
_ORDERED_NOT_ONE = re.compile(r"[ \t]*(?!1[.)])\d+[.)]")
# A setext underline turns the paragraph above it into a heading.
_SETEXT_UNDER = re.compile(r" {0,3}(?:=+|-+)[ \t]*$")
_INTERRUPTS = re.compile(r" {0,3}(?:#{1,6}(?:[ \t]|$)|>|(?:[-*_][ \t]*){3,}$)")


class _Span:
    __slots__ = ("_span",)

    def __init__(self, start: int, end: int):
        self._span = (start, end)

    def span(self) -> tuple[int, int]:
        return self._span


def _item_text(line: str, item: re.Match[str], start: int = 0) -> tuple[int, int]:
    """Return (text column, index where the text starts) for a list marker.

    CommonMark counts one to four spaces after the marker as padding. With five
    or more, or nothing after the marker, the padding is one space and the rest
    belongs to the item's content.
    """
    marker_end = item.start() + len(item.group(0).rstrip(" \t"))
    rest = line[item.end() :]
    padding = _indent_width(line[: item.end()]) - _indent_width(line[:marker_end])
    if padding >= 5 or not rest.strip():
        return _indent_width(line[:marker_end]) + 1, min(marker_end + 1, len(line))
    return _indent_width(line[: item.end()]), item.end()


def _indent_width(indent: str) -> int:
    width = 0
    for ch in indent:
        width = width + 4 - width % 4 if ch == "\t" else width + 1
    return width


class _FenceScanner:
    """Finds fenced code blocks, with the same finditer/span surface as a regex.

    Follows CommonMark for the cases that decide what is prose: a fence may be
    indented at most three columns past its container, which inside a list is
    the column where the item's text starts; a fence may start on the list
    marker's own line; a backtick fence's info string has no backticks (else the
    line is inline code); a closer sits at most three columns past the container;
    and an unclosed fence ends with its container, which for the document is the
    end of the file. A line that directly continues a paragraph (no blank line
    between) stays in the paragraph's list item, which is CommonMark's lazy
    continuation. Block quotes are not modelled.
    """

    def finditer(self, text: str):
        raw_lines = text.split("\n")
        offsets = []
        pos = 0
        for line in raw_lines:
            offsets.append(pos)
            pos += len(line) + 1
        # CRLF text: drop the \r for the analysis, keep the offsets of the source.
        lines = [line[:-1] if line.endswith("\r") else line for line in raw_lines]
        # Text columns of the open list items, innermost last.
        stack: list[int] = []
        # True while the previous line was paragraph text, so this line may be a
        # lazy continuation of it.
        in_para = False
        i = 0
        while i < len(lines):
            line = lines[i]
            body = line.lstrip(" \t")
            if not body:
                in_para = False
                i += 1
                continue
            lead = _indent_width(line[: len(line) - len(body)])
            item = _LIST_ITEM.match(line)
            if item and _THEMATIC.match(body):
                item = None  # "* * *" is a thematic break, not a list item
            if item and in_para and _ORDERED_NOT_ONE.match(line):
                item = None  # only "1." may interrupt a paragraph
            if item and in_para and lead - (stack[-1] if stack else 0) >= 4:
                item = None  # too deep to start an item: paragraph text
            if in_para and not item and _SETEXT_UNDER.match(line):
                in_para = False  # the paragraph above became a heading
                i += 1
                continue
            if (
                in_para
                and not item
                and not _FENCE_OPEN.match(body)
                and not _INTERRUPTS.match(line)
            ):
                i += 1  # lazy continuation: the list items stay open
                continue
            while stack and lead < stack[-1]:
                stack.pop()
            if item:
                col, end = _item_text(line, item)
                while stack and stack[-1] >= col:
                    stack.pop()
                stack.append(col)
                # "- - ~~~sh" opens two items on one line; read every marker.
                while (more := _LIST_ITEM.match(line, end)) and more.start() == end:
                    if _THEMATIC.match(line[end:]):
                        break
                    col, nxt = _item_text(line, more)
                    if nxt <= end:
                        break  # no progress: stop rather than loop forever
                    end = nxt
                    stack.append(col)
                candidate, base, rel = line[end:], col, 0
            else:
                base = stack[-1] if stack else 0
                candidate, rel = body, lead - base
            m = _FENCE_OPEN.match(candidate) if 0 <= rel <= 3 else None
            if m and m.group("indent"):
                m = None  # the candidate already starts at its text
            if m and m.group("fence")[0] == "`" and "`" in candidate[m.end() :]:
                m = None  # backticks in the info string: inline code, not a fence
            if not m:
                # A heading or a thematic break is not paragraph text.
                # On a marker line the item's own text decides: "- # Title"
                # is a heading and "-" alone is an empty item.
                body = candidate if item else line
                in_para = bool(body.strip()) and not _INTERRUPTS.match(body)
                i += 1
                continue
            in_para = False
            fence = m.group("fence")
            contained = base > 0
            closer = None
            stop = len(lines)
            for j in range(i + 1, len(lines)):
                raw = lines[j]
                rest = raw.lstrip(" \t")
                if not rest:
                    continue
                jlead = _indent_width(raw[: len(raw) - len(rest)])
                if contained and jlead < base:
                    stop = j
                    break
                rest = rest.rstrip()
                if (
                    jlead - base <= 3
                    and rest.startswith(fence)
                    and rest.rstrip(fence[0]) == ""
                    and len(rest) >= len(fence)
                ):
                    closer = j
                    break
            if closer is not None:
                yield _Span(offsets[i], offsets[closer] + len(raw_lines[closer]))
                i = closer + 1
                continue
            yield _Span(
                offsets[i], len(text) if stop == len(lines) else offsets[stop] - 1
            )
            if stop == len(lines):
                return
            i = stop


_FENCE = _FenceScanner()
# Front matter opens with "---" and, after any YAML comments or blank lines, a
# "key:" line. Without the key check, a document that starts with a horizontal
# rule lost its first section.
_FRONTMATTER = re.compile(
    r"\A---\n(?=(?:[ \t]*(?:#[^\n]*)?\n)*[A-Za-z0-9_-]+:)(?:.*?\n)?---[ \t]*$",
    re.S | re.M,
)


class _IndentedCodeScanner:
    """Finds indented code lines, with the same finditer/span surface as a regex.

    A line is indented code when it sits four or more columns past its
    container (inside a list, the column where the item's text starts) and does
    not continue a paragraph: indented code cannot interrupt one, but it may
    follow a blank line, a heading, a horizontal rule or more code. A flat "four spaces" regex took a list item's second paragraph
    for code, and hid 201 lines of prose in 86 real files. Fences are already
    blanked when this runs, so their lines read as blank here.
    """

    def finditer(self, text: str):
        stack: list[int] = []
        in_para = False
        pos = 0
        for raw in text.split("\n"):
            start = pos
            pos += len(raw) + 1
            line = raw[:-1] if raw.endswith("\r") else raw
            body = line.lstrip(" \t")
            if not body:
                in_para = False
                continue
            lead = _indent_width(line[: len(line) - len(body)])
            item = _LIST_ITEM.match(line)
            if item and _THEMATIC.match(body):
                item = None
            if item and in_para and _ORDERED_NOT_ONE.match(line):
                item = None
            if item and in_para and lead - (stack[-1] if stack else 0) >= 4:
                item = None
            if item:
                col, end = _item_text(line, item)
                while stack and stack[-1] >= col:
                    stack.pop()
                stack.append(col)
                body = line[end:]
                in_para = bool(body.strip()) and not _INTERRUPTS.match(body)
            elif in_para and _SETEXT_UNDER.match(line):
                in_para = False  # the paragraph above became a heading
            elif in_para and not _INTERRUPTS.match(line):
                pass  # lazy continuation, or the next line of the paragraph
            else:
                while stack and lead < stack[-1]:
                    stack.pop()
                base = stack[-1] if stack else 0
                if lead - base >= 4 and not in_para:
                    yield _Span(start + len(line) - len(body), start + len(line))
                    in_para = False
                else:
                    in_para = not _INTERRUPTS.match(line)


_INDENTED_CODE = _IndentedCodeScanner()
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
# Possessive quantifiers (*+): with plain ones a long whitespace-only line made
# the overlapping [ \t]* runs backtrack, and 20,000 spaces took 3 seconds.
_TABLE_SEP = re.compile(
    r"(?m)^[ \t]*+\|?[ \t]*+:?-{2,}:?[ \t]*+(\|[ \t]*+:?-{2,}:?[ \t]*+)*+\|?[ \t]*+$"
)

# Abbreviations that end in a period but do not end a sentence.
_ABBREV = {
    "mr",
    "mrs",
    "ms",
    "dr",
    "prof",
    "sr",
    "jr",
    "st",
    "vs",
    "etc",
    "e.g",
    "i.e",
    "fig",
    "no",
    "vol",
    "approx",
    "al",
    "inc",
    "ltd",
    "co",
    "dept",
    "est",
    "min",
    "max",
    "sec",
    "cf",
    "ca",
    "ver",
    "rev",
    "ref",
    "eq",
    "ch",
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
        if (
            re.search(r"\d\.$", stripped)
            and end < len(text)
            and text[end : end + 2].strip()[:1].isdigit()
        ):
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
        if any(consumed[m.start() : m.end()]):
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
        if not raw_line.strip() or all(
            consumed[i] for i in range(s, s + len(raw_line)) if raw_line
        ):
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
            body = raw_line[qm.end() :]
        lm = _LIST_MARK.match(body)
        if lm:
            kind = "list_item"
            off += lm.end()
            body = body[lm.end() :]
        if _TABLE_ROW.match(raw_line):
            kind = "table"
            for cell in body.strip().strip("|").split("|"):
                idx = body.find(cell, 0)
                cell_text = cell.strip()
                if cell_text:
                    doc.sentences.append(
                        Sentence(cell_text, off + max(idx, 0), "table")
                    )
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
    return [m.span() for m in _FENCE.finditer(text)] + [
        m.span() for m in _INLINE_CODE.finditer(text)
    ]
