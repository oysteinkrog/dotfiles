#!/usr/bin/env python3
"""query-corpus.py — filter the cross-project FM corpus by language/subsystem.

Phase 0 invokes this to seed Phase 1 archaeology with relevant FMs:
    query-corpus.py --language rust > known_fms_for_language.jsonl

Or scope further:
    query-corpus.py --language rust --subsystem state_files > seed.jsonl

Reads `references/corpus/known-fms.jsonl` (resolved relative to the script's
location, so it works regardless of the caller's cwd).

Args:
    --language <lang>      filter to FMs that include <lang> in their languages list
    --subsystem <name>     additionally filter to a specific subsystem
    --severity <P0|P1|P2|P3>  filter to severity at or above the given level (P0 most severe)
    --min-frequency <N>    filter to FMs seen in >= N projects
    --corpus <path>        override default corpus path

Output: NDJSON to stdout (one matching FM per line). Stderr gets a one-line
summary (`query-corpus: <N> FMs match`).

Exit codes: 0 success (even if zero matches), 64 usage, 66 corpus not found.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


SEVERITY_RANK = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}


class _UsageExitParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:  # noqa: ANN001
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(64)


def default_corpus_path() -> Path:
    """Locate references/corpus/known-fms.jsonl relative to this script."""
    return Path(__file__).resolve().parent.parent / "references" / "corpus" / "known-fms.jsonl"


def main() -> int:
    parser = _UsageExitParser(description=__doc__.splitlines()[0])
    parser.add_argument("--language", default=None)
    parser.add_argument("--subsystem", default=None)
    parser.add_argument("--severity", default=None,
                        choices=list(SEVERITY_RANK.keys()))
    parser.add_argument("--min-frequency", type=int, default=1)
    parser.add_argument("--corpus", default=None,
                        help="override default corpus path")
    args = parser.parse_args()

    corpus_path = Path(args.corpus) if args.corpus else default_corpus_path()
    if not corpus_path.is_file():
        print(f"query-corpus: corpus not found at {corpus_path}", file=sys.stderr)
        return 66

    max_severity_rank = SEVERITY_RANK[args.severity] if args.severity else None

    matched = 0
    with corpus_path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if args.language and args.language not in rec.get("languages", []):
                continue
            if args.subsystem and args.subsystem != rec.get("subsystem"):
                continue
            if max_severity_rank is not None:
                rec_rank = SEVERITY_RANK.get(rec.get("severity_hint", "P3"), 4)
                if rec_rank > max_severity_rank:
                    continue
            if rec.get("frequency_across_projects", 0) < args.min_frequency:
                continue
            sys.stdout.write(json.dumps(rec, ensure_ascii=False) + "\n")
            matched += 1
    sys.stdout.flush()
    print(f"query-corpus: {matched} FMs match", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
