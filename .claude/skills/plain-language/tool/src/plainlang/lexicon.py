"""Word-level norms: Zipf frequency, age of acquisition, concreteness, prevalence.

The table is baked by `plainlang.bake` and shipped gzipped, so scoring needs no
third-party package. Two load modes:

    lazy  scan the table once for the words a document actually uses (~40 ms).
          This is what a hook wants.
    full  parse every row (~210 ms). This is what the tuner wants, because it
          scores thousands of documents against one loaded table.
"""

from __future__ import annotations

import gzip
import os
import re
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PATHS = [
    Path(__file__).resolve().parents[3] / "data" / "lexicon.tsv.gz",
    Path(__file__).resolve().parents[2] / "data" / "lexicon.tsv.gz",
]

_Row = tuple


@dataclass(frozen=True)
class Norms:
    zipf: float | None = None
    aoa: float | None = None
    conc: float | None = None
    prev: float | None = None


_EMPTY = Norms()


class Lexicon:
    def __init__(self, path: Path | None = None, mode: str = "lazy") -> None:
        self.path = path or self._find()
        self.mode = mode
        self._rows: dict[str, _Row] = {}
        self._cache: dict[str, Norms] = {}
        self._blob: bytes | None = None
        self._asked: set[str] = set()
        if self.mode == "full":
            self._load_full()

    @staticmethod
    def _find() -> Path | None:
        env = os.environ.get("PLAINLANG_LEXICON")
        if env:
            return Path(env)
        for p in DEFAULT_PATHS:
            if p.exists():
                return p
        return None

    def _read_blob(self) -> bytes:
        if self._blob is None:
            if not self.path or not self.path.exists():
                self._blob = b""
            else:
                opener = gzip.open if self.path.suffix == ".gz" else open
                with opener(self.path, "rb") as fh:  # type: ignore[operator]
                    self._blob = fh.read()
        return self._blob

    @staticmethod
    def _parse(rest: bytes) -> _Row:
        vals: list[float | None] = []
        for field in rest.split(b"\t")[:4]:
            vals.append(float(field) if field else None)
        while len(vals) < 4:
            vals.append(None)
        return tuple(vals)

    def _load_full(self) -> None:
        blob = self._read_blob()
        for line in blob.split(b"\n")[1:]:
            i = line.find(b"\t")
            if i > 0:
                self._rows[line[:i].decode()] = self._parse(line[i + 1:])

    def prime(self, words: set[str]) -> None:
        """Load only the rows a document needs, plus their morphological stems."""
        if self.mode == "full":
            return
        fresh = {w for w in words if w not in self._asked}
        if not fresh:
            return
        self._asked |= fresh
        wanted: set[bytes] = set()
        for w in fresh:
            if w in self._rows:
                continue
            wanted.add(w.encode())
            for v in _variants(w):
                wanted.add(v.encode())
        wanted -= {k.encode() for k in self._rows}
        if not wanted:
            return
        blob = self._read_blob()
        for line in blob.split(b"\n")[1:]:  # first line is the header
            i = line.find(b"\t")
            if i > 0 and line[:i] in wanted:
                self._rows[line[:i].decode()] = self._parse(line[i + 1:])

    @property
    def loaded(self) -> bool:
        return bool(self._rows) or bool(self._read_blob())

    def __len__(self) -> int:
        if self.mode == "full":
            return len(self._rows)
        blob = self._read_blob()
        return max(0, blob.count(b"\n") - 1)

    def lookup(self, word: str) -> Norms:
        w = word.lower().strip("'’-")
        hit = self._cache.get(w)
        if hit is not None:
            return hit
        if w not in self._rows:
            self.prime({w})
        row = self._rows.get(w)
        if row is not None:
            out = Norms(*row)
        else:
            out = _EMPTY
            for cand in _variants(w):
                row = self._rows.get(cand)
                if row is not None:
                    # An inflected form is at least as rare as its lemma, so do
                    # not inherit frequency. Acquisition age and concreteness are
                    # lexical-semantic and do carry over.
                    out = Norms(zipf=None, aoa=row[1], conc=row[2], prev=row[3])
                    break
        self._cache[w] = out
        return out


def _variants(w: str) -> list[str]:
    out: list[str] = []
    if len(w) < 4:
        return out
    rules = [
        ("ies", "y"), ("ied", "y"), ("ier", "y"), ("iest", "y"),
        ("sses", "ss"), ("shes", "sh"), ("ches", "ch"), ("xes", "x"),
        ("ing", ""), ("ed", ""), ("es", ""), ("s", ""),
        ("ly", ""), ("er", ""), ("est", ""),
    ]
    for suf, rep in rules:
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            stem = w[: -len(suf)] + rep
            out.append(stem)
            if suf in {"ing", "ed"}:
                out.append(stem + "e")
                if len(stem) > 2 and stem[-1] == stem[-2]:
                    out.append(stem[:-1])
    return out


_VOWELS = "aeiouy"


def syllables(word: str) -> int:
    """Cheap syllable estimate, used only as an out-of-vocabulary fallback."""
    w = re.sub(r"[^a-z]", "", word.lower())
    if not w:
        return 0
    count = 0
    prev_vowel = False
    for ch in w:
        is_vowel = ch in _VOWELS
        if is_vowel and not prev_vowel:
            count += 1
        prev_vowel = is_vowel
    if w.endswith("e") and count > 1 and not w.endswith(("le", "ee", "ye")):
        count -= 1
    if w.endswith(("ism", "sm")):
        count += 1
    return max(1, count)


_LATINATE = re.compile(
    r"(?:isation|ization|ationally|ational|ations?|ities|ity|ments?|ances?|ences?"
    r"|isms?|ists?|ologies|ology|iveness|fulness|lessness|abilit|ibilit)$"
)


def latinate_suffix(word: str) -> bool:
    return bool(_LATINATE.search(word.lower()))
