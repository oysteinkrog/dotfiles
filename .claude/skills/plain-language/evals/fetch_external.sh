#!/usr/bin/env bash
# Fetch the two outside readability corpora that validate_external.py uses.
# They are not committed: together they are about 8 MB, and both are public.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/data/external"
mkdir -p "$OUT"

# CLEAR corpus: 4,724 excerpts with continuous human difficulty ratings, plus
# every classic readability formula scored on the same text.
# Crossley et al. 2022, Behavior Research Methods. https://github.com/scrosseye/CLEAR-Corpus
if [ ! -f "$OUT/clear.csv" ]; then
  echo "fetching the CLEAR corpus"
  for NAME in \
    "CLEAR%20Corpus%206.01%20-%20CLEAR%20Corpus%206.01.csv" \
    "CLEAR.csv" \
    "CLEAR_corpus_final.csv"; do
    if curl -fsSL -o "$OUT/clear.csv" \
        "https://raw.githubusercontent.com/scrosseye/CLEAR-Corpus/main/$NAME"; then
      break
    fi
  done
  [ -s "$OUT/clear.csv" ] || echo "CLEAR download failed; list the repo tree and fix the file name" >&2
fi

# OneStopEnglish: 189 news articles, each rewritten by editors at three levels.
# CC BY-SA 4.0. https://github.com/nishkalavallabhi/OneStopEnglishCorpus
if [ ! -f "$OUT/onestop.jsonl" ]; then
  echo "fetching OneStopEnglish"
  TMP="$(mktemp -d)"
  git clone --depth 1 -q https://github.com/nishkalavallabhi/OneStopEnglishCorpus "$TMP/one"
  python3 - "$TMP/one" "$OUT/onestop.jsonl" <<'PY'
import json, re, sys
from pathlib import Path

root, out = Path(sys.argv[1]), Path(sys.argv[2])
levels = {"Ele-Txt": "ele", "Int-Txt": "int", "Adv-Txt": "adv"}
rows = []
for folder, level in levels.items():
    for p in root.rglob(f"{folder}/*.txt"):
        article = re.sub(r"-(?:ele|int|adv)\.txt$", "", p.name, flags=re.I)
        rows.append({"article": article, "level": level,
                     "text": p.read_text(encoding="utf-8", errors="replace")})
out.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
print(f"{len(rows)} texts written to {out}")
PY
fi

ls -la "$OUT"
