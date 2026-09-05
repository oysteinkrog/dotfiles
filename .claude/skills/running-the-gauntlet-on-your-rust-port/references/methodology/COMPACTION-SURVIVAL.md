# Compaction Survival Contract

The gauntlet runs for days-to-weeks of wall-clock time. Context compactions, machine reboots, agent crashes, fresh-cold-start sessions are routine. The skill is designed so an agent dropped into the middle of a run can resume **without losing a single decision**.

This document specifies the contract: what state must be durable + how it's organized + how to detect mid-flight you've been compacted vs starting fresh.

## The 5 durable-state layers

### Layer 1 — `<workspace>/MEMORY.md` (the index)

Per [`methodology/MEMORY-MD-CONVENTION.md`](MEMORY-MD-CONVENTION.md). One line per session; ≤200 lines total; rotates if it grows beyond. The agent's first action on cold start is to `Read` this file.

### Layer 2 — `<workspace>/sessions/session_<NNN>_<topic>.md` (the detail)

The full per-session record. Frontmatter-typed (YAML) so it's machine-parseable. The agent reads only the sessions relevant to "what was the last thing I was doing"; doesn't have to swallow the whole history.

### Layer 3 — `<workspace>/phase<N>_*.md` (per-phase decision records)

Output files of the 16-phase loop. These freeze the decision at the time of authoring; they're read-only after the phase commits. The agent re-reads them when re-entering a phase.

### Layer 4 — `<workspace>/round_<N>/` (per-round artifacts)

Per-iteration directories. Each round contains its baseline JSON, profile artifacts, FailureBundles, conformance findings, surface dashboard, idea-wizard yield. The round directory is the unit of resumability for Phase 11.

### Layer 5 — `<workspace>/reports/convergence_tracker.json` (generated Phase 11 convergence summary)

The generated source of truth for Phase 11 convergence math. It is written by `scripts/convergence-tracker.sh`; agents do not edit it by hand. Fields:

```jsonc
{
  "schema_version": "gauntlet.convergence_tracker.v1",
  "generated_at": "<ISO>",
  "workspace": "<path>",
  "round_count": <int>,
  "min_rounds_required": 10,
  "clean_threshold": 3,
  "required_consecutive_clean": 2,
  "open_hypothesis_count": <int>,
  "round_findings": [{"round": "round_1", "new_findings": <int>}],
  "last_two_findings": [<int>, <int>],
  "clean_last_two": <bool>,
  "converged": <bool>
}
```

## Cold-start protocol

When an agent invokes this skill and `<workspace>/` already exists:

```
1. Read SKILL.md                                           # restore the skill itself
2. Read <workspace>/MEMORY.md                              # 200-line index of sessions
3. Read the most recent <workspace>/sessions/session_*.md  # most recent session detail
4. If <workspace>/reports/convergence_tracker.json exists:
     Read it for Phase 11 convergence state
5. Read the latest completed phase record and latest round_<N>/synthesis.md if present
6. Decide the next action from MEMORY.md + phase records + tracker; resume.
```

The agent MUST NOT re-derive prior decisions; the workspace is authoritative.

## Resumability tests

Before any phase that could be compaction-interrupted (Phases 5-11, 15), the agent runs a self-test:

```bash
test -f <workspace>/MEMORY.md
test -d <workspace>/sessions
if test -f <workspace>/reports/convergence_tracker.json; then
  jq -r '.round_count // empty' <workspace>/reports/convergence_tracker.json
fi
```

If MEMORY.md or sessions/ is missing, the agent BLOCKS and writes a `<workspace>/RESUMABILITY_BROKEN.md` entry explaining what's missing rather than silently proceeding. A missing convergence tracker is only blocking after Phase 11 has started.

## Idempotency of every script

Every script in `scripts/` MUST be idempotent: running it twice in a row produces the same state on the second run as the first. Concrete instances:

- `init-workspace.sh` — re-init detects existing workspace; prompts to resume vs reset.
- `compute-parity-score.sh` — given the same inputs, produces bytewise identical JSON.
- `update-ratchet-state.sh` — applying the same score twice is a no-op the second time.
- `convergence-tracker.sh` — re-running yields the same convergence verdict given the same ledger state.

A non-idempotent script is a compaction-survival bug.

## Anti-patterns

- ❌ Storing live state in shell variables that don't survive a process restart.
- ❌ Writing files in `/tmp/` (cleared on reboot). Use `<workspace>/`.
- ❌ Computing derived state on the fly instead of writing it back. (Future-you can't compute it.)
- ❌ Editing past `phase<N>_*.md` files after the phase has committed. (Append a new file or session.)
- ❌ Skipping `session_<NNN>_*.md` because "this work was small". (Future-you doesn't know what was small.)

## Cross-references

- [`methodology/MEMORY-MD-CONVENTION.md`](MEMORY-MD-CONVENTION.md)
- [`methodology/CONVERGENCE.md`](CONVERGENCE.md)
- [`subagents/iteration-coordinator.md`](../../subagents/iteration-coordinator.md)
- [`subagents/synthesizer.md`](../../subagents/synthesizer.md)
