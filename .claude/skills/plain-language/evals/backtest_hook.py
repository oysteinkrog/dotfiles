"""Replay real historical tool calls through the gate, and see what it would have done.

The rule tests say each pattern is precise on cases written for it. This says what
the hook does to a real day's work: how often it fires, on what, and how much time
it costs. Nothing here is synthetic.

    python evals/backtest_hook.py --calls <toolcalls.json> --replies <replies.json>
    python evals/backtest_hook.py --calls ... --dump-blocked 40   # read what it stopped

Input files come from a session-log extractor; see README.md. They are not
committed, because they contain the contents of real commits, documents and
messages.
"""

from __future__ import annotations

import argparse
import collections
import importlib.util
import json
import os
import statistics
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "tool" / "src"))

from plainlang.lexicon import Lexicon  # noqa: E402
from plainlang.model import Scorer, Weights  # noqa: E402


def load_guard(path: Path):
    spec = importlib.util.spec_from_file_location("plguard", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--calls", type=Path, required=True)
    ap.add_argument("--replies", type=Path, default=None)
    # The detector, for its text-extraction half only. This script does its own
    # scoring in process, because shelling out 84,000 times would measure process
    # startup rather than the gate.
    ap.add_argument("--guard", type=Path,
                    default=Path(os.environ.get("PLAINLANG_GUARD",
                                                ROOT / "hooks" / "plain-language-detect.py")))
    ap.add_argument("--weights", type=Path, default=None)
    ap.add_argument("--dump-blocked", type=int, default=0)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    guard = load_guard(args.guard)
    weights = Weights.load(args.weights)
    scorer = Scorer(weights, Lexicon(mode="full"))

    # Say which glossary is in effect, every run. The scorer finds a project
    # glossary by walking up from the working directory, so the same corpus and
    # the same weights give a different refusal rate depending on where you
    # invoke this. That is not a bug in the scorer, it is how per-repo domain
    # terms are meant to work, but an eval number that moves with the working
    # directory and does not say so is unreviewable. Measured on 2026-09-01: run
    # from the monorepo, 6,938 project terms, 451 refusals; run from the skill
    # directory, 0 project terms, 876 refusals.
    from plainlang.model import _discover_glossary  # noqa: PLC0415
    project_terms = _discover_glossary()
    print(f"cwd {Path.cwd()}")
    print(f"glossary: {len(scorer.glossary)} terms total, "
          f"{len(project_terms)} from a project .plainlang/glossary.txt")
    print(f"weights: {args.weights or 'data/weights.json'}, "
          f"min_score {weights.min_score}, max_errors {weights.max_errors}")
    print(f"detector: {args.guard}\n")

    # Score in process. The hook shells out to `pl`; doing that 84,000 times would
    # measure process startup, not the gate.
    def gate(text: str) -> dict:
        rep = scorer.score(text)
        errors = int(rep.stats["errors"])
        failed = errors > weights.max_errors or rep.score < weights.min_score
        return {"score": rep.score, "errors": errors, "failed": failed,
                "language": rep.language,
                "rules": [f.rule for f in rep.findings if f.severity in ("error", "warn")]}

    calls = json.loads(args.calls.read_text(encoding="utf-8"))
    if args.limit:
        calls = calls[: args.limit]

    per_tool = collections.Counter()
    considered = collections.Counter()
    blocked = collections.Counter()
    short_blocked = collections.Counter()
    rule_hits = collections.Counter()
    skipped_lang = 0
    blocked_examples = []
    t0 = time.time()

    for c in calls:
        tool = c["tool"]
        per_tool[tool] += 1
        got = guard.from_tool(tool, c["input"])
        if not got:
            continue
        text, label = got
        if not text or guard.SKIP_MARKER.search(text):
            continue
        short = guard.word_count(text) < guard.MIN_WORDS
        if short and not guard.HARD_HINT.search(text):
            continue
        considered[tool] += 1
        rep = gate(text)
        if rep["language"] != "en":
            skipped_lang += 1
            continue
        if short:
            if not rep["errors"]:
                continue
            blocked[tool] += 1
            short_blocked[tool] += 1
            for r in rep["rules"]:
                rule_hits[r] += 1
        elif rep["failed"]:
            blocked[tool] += 1
            for r in rep["rules"]:
                rule_hits[r] += 1
        else:
            continue
        if len(blocked_examples) < max(args.dump_blocked, 200):
            blocked_examples.append({"tool": tool, "label": label, "score": rep["score"],
                                     "errors": rep["errors"], "rules": rep["rules"][:4],
                                     "text": text[:400], "ts": c.get("ts", "")})

    elapsed = time.time() - t0

    print(f"{len(calls)} historical tool calls replayed in {elapsed:.0f}s\n")
    print(f"{'tool':<26}{'calls':>8}{'text found':>12}{'blocked':>9}{'block rate':>12}")
    for tool, n in per_tool.most_common():
        cons, bl = considered[tool], blocked[tool]
        if not cons and not bl:
            continue
        rate = bl / cons if cons else 0.0
        print(f"{tool.split('__')[-1]:<26}{n:>8}{cons:>12}{bl:>9}{rate:>11.1%}")
    tot_calls, tot_cons, tot_bl = len(calls), sum(considered.values()), sum(blocked.values())
    print(f"\n{'TOTAL':<26}{tot_calls:>8}{tot_cons:>12}{tot_bl:>9}"
          f"{(tot_bl / tot_cons if tot_cons else 0):>11.1%}")
    print(f"\n{tot_cons} of {tot_calls} calls carried text the gate looks at "
          f"({tot_cons / max(1, tot_calls):.1%}).")
    print(f"{tot_bl} would have been refused, which is "
          f"{tot_bl / max(1, tot_calls):.2%} of all tool calls.")
    print(f"{sum(short_blocked.values())} of those were short text caught on a hard rule alone.")
    print(f"{skipped_lang} were skipped as not English.")

    print("\nwhat the refusals were for:")
    for rule, n in rule_hits.most_common(12):
        print(f"  {rule:<24}{n:>6}")

    if args.replies and args.replies.exists():
        replies = json.loads(args.replies.read_text(encoding="utf-8"))
        n_bl = n_con = 0
        scores = []
        for r in replies:
            if guard.word_count(r["text"]) < guard.STOP_MIN_WORDS:
                continue
            n_con += 1
            rep = gate(r["text"])
            if rep["language"] != "en":
                continue
            scores.append(rep["score"])
            if rep["failed"]:
                n_bl += 1
        print(f"\nStop path: {n_con} of {len(replies)} historical replies are long enough to score.")
        print(f"  {n_bl} would have been sent back ({n_bl / max(1, n_con):.1%}); "
              f"median score {statistics.median(scores) if scores else float('nan'):.0f}")

    if args.dump_blocked:
        print(f"\n--- {min(args.dump_blocked, len(blocked_examples))} refusals, read them ---")
        for e in blocked_examples[: args.dump_blocked]:
            print(f"\n[{e['ts']}] {e['label']}  score {e['score']:.0f}  "
                  f"hard {e['errors']}  {e['rules']}")
            print("   " + e["text"].replace("\n", "\n   ")[:340])

    out = HERE / "data" / "backtest_blocked.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(blocked_examples, indent=1), encoding="utf-8")
    print(f"\nrefusal sample written to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
