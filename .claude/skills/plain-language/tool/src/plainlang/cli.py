"""Command line: `pl`.

    pl check FILE...        findings, human readable, exit 1 if the gate fails
    pl score FILE...        one line per file
    pl explain FILE         where every point of cost went
    pl json FILE            full report as JSON
    pl gate                 read stdin, exit non-zero if it fails

Text can come from stdin with `-`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from .model import Report, Scorer, Weights

# A file may declare itself out of scope. Used by specifications that have to
# quote the banned constructions, and by quoted or prescribed material.
SKIP_MARKER = re.compile(r"(?mi)^\s*(?:<!--\s*)?plainlang:\s*skip")

RESET = "\033[0m"
COLORS = {"error": "\033[31m", "warn": "\033[33m", "info": "\033[90m"}


def _read(target: str) -> str:
    if target == "-":
        return sys.stdin.read()
    return Path(target).read_text(encoding="utf-8", errors="replace")


def _color(enabled: bool, sev: str, text: str) -> str:
    if not enabled:
        return text
    return f"{COLORS.get(sev, '')}{text}{RESET}"


def print_findings(name: str, rep: Report, *, color: bool, limit: int, min_sev: str) -> None:
    order = {"info": 0, "warn": 1, "error": 2}
    floor = order[min_sev]
    shown = [f for f in rep.findings if order[f.severity] >= floor]
    head = f"{name}: {rep.score:.0f}/100 ({rep.grade})  {rep.words} words, cost {rep.rate:.1f}/100w"
    print(head)
    if rep.stats.get("errors"):
        print(f"  {int(rep.stats['errors'])} hard-rule violation(s)")
    for f in shown[:limit]:
        loc = f"{f.line}:{f.col}"
        line = f"  {loc:>8}  {f.severity:<5} {f.rule:<18} {f.message}"
        print(_color(color, f.severity, line))
        if f.excerpt.strip():
            print(f"            > {f.excerpt.strip()[:100]}")
        if f.suggest:
            print(f"            fix: {f.suggest}")
    if len(shown) > limit:
        print(f"  ... {len(shown) - limit} more")


def gate_fails(rep: Report, w: Weights) -> tuple[bool, str]:
    if rep.stats.get("errors", 0) > w.max_errors:
        return True, f"{int(rep.stats['errors'])} hard-rule violation(s)"
    if rep.score < w.min_score:
        return True, f"score {rep.score:.0f} is below {w.min_score:.0f}"
    return False, ""


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="pl", description="Score prose against the plain-language rules.")
    ap.add_argument("command", choices=["check", "score", "explain", "json", "gate"])
    ap.add_argument("files", nargs="*", default=["-"])
    ap.add_argument("--weights", type=Path, default=None)
    ap.add_argument("--glossary", type=Path, default=None, help="extra domain terms, one per line")
    ap.add_argument("--min-score", type=float, default=None)
    ap.add_argument("--limit", type=int, default=25)
    ap.add_argument("--severity", choices=["info", "warn", "error"], default="info")
    ap.add_argument("--no-color", action="store_true")
    ap.add_argument("--quiet", action="store_true", help="print nothing; use the exit code")
    args = ap.parse_args(argv)

    weights = Weights.load(args.weights)
    if args.min_score is not None:
        weights.min_score = args.min_score
    scorer = Scorer(weights)
    if args.glossary and args.glossary.exists():
        for line in args.glossary.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip().lower()
            if line:
                scorer.glossary.add(line)

    color = sys.stdout.isatty() and not args.no_color
    files = args.files or ["-"]
    failed = False

    for target in files:
        try:
            text = _read(target)
        except OSError as exc:
            print(f"{target}: {exc}", file=sys.stderr)
            failed = True
            continue
        rep = scorer.score(text)
        if rep.language != "en":
            if args.command == "json":
                print(rep.to_json())
            elif not args.quiet and args.command in {"check", "gate", "score", "explain"}:
                print(f"{target}: not English "
                      f"({rep.stats.get('english_share', 0):.0%} English function words), not gated")
            continue
        if SKIP_MARKER.search(text):
            bad, why = False, ""
            if not args.quiet and args.command in {"check", "gate", "score"}:
                print(f"{target}: {rep.score:.0f}/100, not gated (declares plainlang: skip)")
                continue
        else:
            bad, why = gate_fails(rep, weights)
        failed = failed or bad

        if args.quiet:
            continue
        if args.command == "json":
            print(rep.to_json())
        elif args.command == "score":
            print(f"{rep.score:6.1f}  {rep.grade}  {rep.words:5d}w  rate={rep.rate:6.2f}  {target}")
        elif args.command in {"check", "gate"}:
            print_findings(target, rep, color=color, limit=args.limit, min_sev=args.severity)
            if bad:
                print(_color(color, "error", f"  FAIL: {why}"))
            elif args.command == "gate":
                print("  pass")
        elif args.command == "explain":
            print(json.dumps({
                "score": rep.score, "rate": rep.rate, "words": rep.words,
                "spend": rep.spend, "stats": rep.stats,
                "most_expensive_words": rep.top_costs,
            }, indent=2))

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
