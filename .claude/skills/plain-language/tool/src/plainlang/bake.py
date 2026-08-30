"""Build the shipped lexicon from source norms.

Run once when a norm dataset changes:

    uv run --with wordfreq --with openpyxl python -m plainlang.bake --norms <dir> --out ../data/lexicon.tsv.gz

The output is a gzipped TSV so the scorer needs no third-party package at run
time. Columns: word, zipf, aoa, conc, prev. Missing values are empty.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import sys
from pathlib import Path

VOCAB_LIMIT = 120_000


def read_norm(path: Path, key: str, value: str) -> dict[str, float]:
    """Read one norm file. The shipped copies are gzipped to keep the repo small."""
    gz = path.with_suffix(path.suffix + ".gz")
    if path.exists():
        opener = lambda: path.open(newline="", encoding="utf-8-sig", errors="replace")  # noqa: E731
    elif gz.exists():
        opener = lambda: gzip.open(gz, "rt", newline="", encoding="utf-8-sig", errors="replace")  # noqa: E731
    else:
        print(f"  missing: {path.name} (and {gz.name})", file=sys.stderr)
        return {}
    out: dict[str, float] = {}
    with opener() as fh:
        sample = fh.read(8192)
        fh.seek(0)
        delim = "\t" if sample.count("\t") > sample.count(",") else ","
        reader = csv.DictReader(fh, delimiter=delim)
        cols = {c.lower().strip(): c for c in (reader.fieldnames or [])}
        kc = cols.get(key)
        vc = cols.get(value)
        if not kc or not vc:
            print(f"  {path.name}: want columns {key}/{value}, have {list(cols)}", file=sys.stderr)
            return {}
        for row in reader:
            w = (row.get(kc) or "").strip().lower()
            raw = (row.get(vc) or "").strip()
            if not w or not raw or " " in w:
                continue
            try:
                out[w] = float(raw)
            except ValueError:
                continue
    print(f"  {path.name}: {len(out)} rows", file=sys.stderr)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--norms", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    from wordfreq import iter_wordlist, zipf_frequency  # type: ignore

    print("reading norms", file=sys.stderr)
    aoa = read_norm(args.norms / "aoa.csv", "word", "aoa_mean")
    conc = read_norm(args.norms / "concreteness.csv", "word", "conc_mean")
    prev = read_norm(args.norms / "prevalence.csv", "word", "prevalence")

    vocab: set[str] = set()
    for i, w in enumerate(iter_wordlist("en", "best")):
        if i >= VOCAB_LIMIT:
            break
        if w.isalpha():
            vocab.add(w)
    vocab |= {w for w in (aoa.keys() | conc.keys() | prev.keys()) if w.isalpha()}
    print(f"vocab: {len(vocab)}", file=sys.stderr)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(args.out, "wt", encoding="utf-8", newline="\n") as fh:
        fh.write("word\tzipf\taoa\tconc\tprev\n")
        for w in sorted(vocab):
            z = zipf_frequency(w, "en", wordlist="best")
            if z <= 0 and w not in aoa and w not in conc:
                continue
            fh.write(
                "{}\t{:.2f}\t{}\t{}\t{}\n".format(
                    w,
                    z,
                    f"{aoa[w]:.2f}" if w in aoa else "",
                    f"{conc[w]:.2f}" if w in conc else "",
                    f"{prev[w]:.2f}" if w in prev else "",
                )
            )
    size = args.out.stat().st_size
    print(f"wrote {args.out} ({size/1024:.0f} KiB)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
