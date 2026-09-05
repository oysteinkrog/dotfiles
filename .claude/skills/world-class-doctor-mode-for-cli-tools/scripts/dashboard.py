#!/usr/bin/env python3
"""dashboard.py — one-screen ASCII dashboard for an in-flight doctor pass.

Reads a workspace and prints a single-screen summary: phase progress, FM
counts, scorecard delta vs prior pass, ETA. Useful for operators applying
the skill manually who want visibility into where the pass currently is.

Usage:
    dashboard.py <workspace> [--no-color] [--watch SEC]

Args:
    <workspace>   workspace directory
    --no-color    disable ANSI; auto-disabled when stdout is not a TTY
    --watch SEC   refresh every SEC seconds (Ctrl-C to exit). Default: print once.

Reads:
    <workspace>/manifest.json                    — pass number, mode, target
    <workspace>/phase0_cli.json                  — language, binaries
    <workspace>/preflight.json                   — required tools status
    <workspace>/phases_timing.jsonl              — per-phase start/finish (round-55 idea #13)
    <workspace>/scorecard.json                   — current aggregate
    <workspace>/scorecard_pass_<N-1>.md          — prior pass aggregate (parsed loosely)
    <workspace>/safety_harness.jsonl             — Phase 5 results
    <workspace>/analysis/failure_modes/*.md      — Phase 1 FM count (line count proxy)
    <workspace>/recommendations.jsonl            — Phase 3 / audit-only deliverable
    <workspace>/HANDOFF.md                       — Phase 10 marker

All inputs are optional; missing inputs render as "—" or "(pending)".

Exit codes: 0 success, 64 usage, 66 workspace not found.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path


class _UsageExitParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:  # noqa: ANN001
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(64)


# ANSI palette (auto-disabled when stdout is not a TTY).
class C:
    RESET = "\x1b[0m"
    BOLD = "\x1b[1m"
    DIM = "\x1b[2m"
    GREEN = "\x1b[32m"
    YELLOW = "\x1b[33m"
    RED = "\x1b[31m"
    BLUE = "\x1b[34m"
    CYAN = "\x1b[36m"


def disable_color() -> None:
    for attr in ("RESET", "BOLD", "DIM", "GREEN", "YELLOW", "RED", "BLUE", "CYAN"):
        setattr(C, attr, "")


def safe_read_json(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def safe_read_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    out: list[dict] = []
    try:
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    except OSError:
        pass
    return out


PHASE_NAMES = [
    "0: Bootstrap",
    "1: Archaeology",
    "2: Repair specs",
    "3: Synthesis",
    "4: Implementation",
    "5: Safety harness",
    "6: Agent-ergo + scorecard",
    "7: Fresh eyes",
    "8: Integration",
    "9: Fixture suite",
    "10: Final UX + handoff",
]


def render_dashboard(workspace: Path) -> str:
    """Build the dashboard string."""
    lines: list[str] = []

    manifest = safe_read_json(workspace / "manifest.json") or {}
    cli = safe_read_json(workspace / "phase0_cli.json") or {}
    preflight = safe_read_json(workspace / "preflight.json") or {}
    timing = safe_read_jsonl(workspace / "phases_timing.jsonl")
    scorecard = safe_read_json(workspace / "scorecard.json") or {}
    safety = safe_read_jsonl(workspace / "safety_harness.jsonl")
    fm_dir = workspace / "analysis" / "failure_modes"
    fm_count = len(list(fm_dir.glob("*.md"))) if fm_dir.is_dir() else 0
    recs = safe_read_jsonl(workspace / "recommendations.jsonl")
    handoff_present = (workspace / "HANDOFF.md").is_file()

    pass_n = manifest.get("pass", "?")
    mode = manifest.get("mode", "?")
    target = manifest.get("target", cli.get("target", "?"))
    language = cli.get("language", "?")
    binaries = cli.get("binaries", [])
    tool = manifest.get("tool", binaries[0] if binaries else "?")

    # Header.
    lines.append(f"{C.BOLD}{C.BLUE}╔══ doctor pass dashboard ═══════════════════════════════════════╗{C.RESET}")
    lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  workspace: {C.CYAN}{workspace}{C.RESET}")
    lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  target:    {C.CYAN}{target}{C.RESET}")
    lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  mode:      {C.CYAN}{mode}{C.RESET}    pass: {C.CYAN}{pass_n}{C.RESET}    tool: {C.CYAN}{tool}{C.RESET} ({language})")
    lines.append(f"{C.BOLD}{C.BLUE}╠════════════════════════════════════════════════════════════════╣{C.RESET}")

    # Preflight.
    if preflight:
        all_ok = preflight.get("all_required_present", False)
        preflight_color = C.GREEN if all_ok else C.RED
        preflight_icon = "✓" if all_ok else "✗"
        lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  preflight: {preflight_color}{preflight_icon} {'all required tools' if all_ok else 'MISSING required tools'}{C.RESET}")
    else:
        lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  preflight: {C.DIM}(not run){C.RESET}")

    # Phase progress.
    lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  {C.BOLD}phase progress:{C.RESET}")
    phases_seen = set()
    phases_done = set()
    for rec in timing:
        phase = rec.get("phase")
        if phase is None:
            continue
        phases_seen.add(phase)
        if rec.get("finished_at"):
            phases_done.add(phase)
    for i, name in enumerate(PHASE_NAMES):
        if i in phases_done:
            mark = f"{C.GREEN}✓{C.RESET}"
        elif i in phases_seen:
            mark = f"{C.YELLOW}…{C.RESET}"
        else:
            mark = f"{C.DIM}·{C.RESET}"
        lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}    {mark} Phase {name}")

    # FM counts + scorecard.
    lines.append(f"{C.BOLD}{C.BLUE}╠════════════════════════════════════════════════════════════════╣{C.RESET}")
    fm_str = f"{fm_count}" if fm_count else f"{C.DIM}(pending){C.RESET}"
    lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  failure modes:           {C.CYAN}{fm_str}{C.RESET}")
    safety_pass = sum(1 for r in safety if r.get("exit_code") == 0)
    safety_fail = sum(1 for r in safety if r.get("exit_code") not in (0, None))
    if safety:
        sc = C.GREEN if safety_fail == 0 else C.RED
        lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  safety harness results:  {sc}{safety_pass} pass / {safety_fail} fail{C.RESET}")
    else:
        lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  safety harness:          {C.DIM}(pending){C.RESET}")

    # Scorecard. Both shapes are seen in practice:
    #   {"aggregate": {"score": 927, ...}}     ← OUTPUT-SCHEMA.md form
    #   {"aggregate_score": 927}               ← scorecard_history.jsonl form
    # Older or hand-written shapes may put a bare number under "aggregate".
    # Guard against all three (dict, number, missing).
    aggregate_obj = scorecard.get("aggregate")
    if isinstance(aggregate_obj, dict):
        aggregate_raw = aggregate_obj.get("score")
    elif isinstance(aggregate_obj, (int, float)):
        aggregate_raw = aggregate_obj
    else:
        aggregate_raw = scorecard.get("aggregate_score")
    # Coerce to float for arithmetic; preserve original for display. If
    # coercion fails (e.g., the value is a non-numeric string), display the
    # raw value but skip the delta calculation.
    aggregate_num: float | None
    if aggregate_raw is None:
        aggregate_num = None
    else:
        try:
            aggregate_num = float(aggregate_raw)
        except (TypeError, ValueError):
            aggregate_num = None
    if aggregate_raw is not None:
        prior = _find_prior_aggregate(workspace, pass_n)
        delta_str = ""
        if (aggregate_num is not None and prior is not None
                and isinstance(prior, (int, float))):
            delta = aggregate_num - prior
            delta_color = C.GREEN if delta >= 0 else C.RED
            sign = "+" if delta >= 0 else ""
            delta_str = f"  ({delta_color}{sign}{delta:.0f}{C.RESET} vs pass-{int(pass_n) - 1 if isinstance(pass_n, int) else '?'})"
        lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  scorecard aggregate:     {C.CYAN}{aggregate_raw}{C.RESET}{delta_str}")
    else:
        lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  scorecard aggregate:     {C.DIM}(pending){C.RESET}")

    # Recommendations.
    rec_str = f"{len(recs)}" if recs else f"{C.DIM}(pending){C.RESET}"
    lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  recommendations.jsonl:   {C.CYAN}{rec_str}{C.RESET}")

    # Handoff.
    handoff_str = f"{C.GREEN}✓{C.RESET}" if handoff_present else f"{C.DIM}(pending){C.RESET}"
    lines.append(f"{C.BOLD}{C.BLUE}║{C.RESET}  HANDOFF.md:              {handoff_str}")

    lines.append(f"{C.BOLD}{C.BLUE}╚════════════════════════════════════════════════════════════════╝{C.RESET}")

    # Latest timing event.
    if timing:
        last = timing[-1]
        evt = "finished" if last.get("finished_at") else "started"
        lines.append(f"{C.DIM}last event: {evt} phase {last.get('phase')} subagent {last.get('subagent_name', '?')} at {last.get(evt + '_at', '?')}{C.RESET}")

    return "\n".join(lines)


def _find_prior_aggregate(workspace: Path, pass_n) -> float | None:
    """Best-effort parse of scorecard_pass_<N-1>.md for the aggregate.

    render() writes the header as
        **Aggregate score (frequency x blast-radius weighted):** `927`
    (note the parenthetical), so the regex must accept any non-`:` content
    between "score" and the closing `:**`. The earlier form `Aggregate
    score:**` never matched the current writer and silently produced no
    delta — bug found during fresh-eyes pass.
    """
    if not isinstance(pass_n, int) or pass_n < 2:
        return None
    candidate = workspace / f"scorecard_pass_{pass_n - 1}.md"
    if not candidate.is_file():
        return None
    text = candidate.read_text(encoding="utf-8", errors="replace")
    # Exclude `\n` from the bridge class — without it, `[^:*]*` can span
    # newlines and grab the wrong number when an earlier paragraph happens
    # to start with `**Aggregate score`. render() always writes the header
    # on one line, so the constraint is safe.
    m = re.search(r"\*\*Aggregate score[^:*\n]*:\*\*\s*`?(\d+)`?", text)
    if m:
        return float(m.group(1))
    return None


def main() -> int:
    parser = _UsageExitParser(description=__doc__.splitlines()[0])
    parser.add_argument("workspace")
    parser.add_argument("--no-color", action="store_true")
    parser.add_argument("--watch", type=int, default=0,
                        help="refresh every SEC seconds")
    args = parser.parse_args()

    workspace = Path(args.workspace)
    if not workspace.is_dir():
        print(f"dashboard: {workspace} is not a directory", file=sys.stderr)
        return 66

    # Auto-disable color on non-TTY.
    if args.no_color or not sys.stdout.isatty():
        disable_color()

    if args.watch > 0:
        try:
            while True:
                # Clear screen + home cursor.
                if sys.stdout.isatty():
                    sys.stdout.write("\x1b[2J\x1b[H")
                sys.stdout.write(render_dashboard(workspace))
                sys.stdout.write("\n")
                sys.stdout.flush()
                time.sleep(args.watch)
        except KeyboardInterrupt:
            return 0
    else:
        print(render_dashboard(workspace))

    return 0


if __name__ == "__main__":
    sys.exit(main())
