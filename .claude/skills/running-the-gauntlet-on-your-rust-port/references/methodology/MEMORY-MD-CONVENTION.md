# MEMORY.md Convention (per /flywheel skill)

The `/flywheel` skill establishes a `MEMORY.md` index + `session_*.md` detail-file convention for long-running projects. The gauntlet adopts this for the per-workspace `<workspace>/MEMORY.md` so a compaction-survival contract is enforceable: an agent re-entering mid-run can rehydrate from `MEMORY.md` alone.

## The convention

`<workspace>/MEMORY.md` is an INDEX. Each line is one entry pointing at a detail file under `<workspace>/sessions/session_<NNN>_<topic>.md`. Lines are ≤150 chars; the full file is parseable as context overflow protection (after line 200, lines are truncated per the auto-memory rule).

```text
- \[Session 001 — Phase 0 bootstrap\]\(sessions/session_001_phase0_bootstrap.md\) — toolchain + workspace init; green precondition verdict
- \[Session 002 — Phase 1 RECON\]\(sessions/session_002_phase1_recon.md\) — per-crate archaeology; 14 crates mapped
- \[Session 003 — Phase 2 scope decision\]\(sessions/session_003_phase2_scope.md\) — ref pinned 3.52.0; 487 features classified
- ...
```
(The example links above are illustrations of the format; the actual files at `sessions/session_NNN_*.md` are created at runtime in `<workspace>/sessions/`. Brackets are escaped so the link-checker doesn't try to resolve them.)

## Per-session detail file template

`<workspace>/sessions/session_<NNN>_<topic>.md`:

```markdown
---
session_id: 001
session_date_utc: 2026-05-22
phase: 0
operators_used: [★ PIN-REFERENCE-VERSION]
agents_dispatched: [workspace-bootstrapper]
artifacts_produced:
  - phase0_workspace_init.md
  - docs/contracts/sqlite_version_contract.toml
  - PERF_NEGATIVE_RESULTS.md (seed)
  - CONFORMANCE_NEGATIVE_RESULTS.md (seed)
  - SURFACE_DEFERRALS.md (seed)
verdict: green
---

# Session 001 — Phase 0 Bootstrap

## Decision
<what was decided + verbatim user input>

## Findings
<what was learned that future sessions need>

## Next session prerequisites
- [ ] <thing that must hold before session 002>

## Open questions for the human
<things the agent couldn't resolve autonomously>

## Cross-references
- See round_<N> artifacts: <paths>
- Related cookbook recipes: ...
```

## Update protocol

After every meaningful unit of work:

1. Author the session detail file in `<workspace>/sessions/session_<NNN>_<topic>.md`.
2. Append a one-line entry to `<workspace>/MEMORY.md`.
3. Do not edit the generated convergence tracker by hand. If the work changed round artifacts or hypothesis ledgers, rerun `scripts/convergence-tracker.sh <workspace>` so `<workspace>/reports/convergence_tracker.json` reflects the new state.

## What MEMORY.md is NOT

- NOT a transcript (use cass for that).
- NOT a TODO list (use beads for that).
- NOT a quick-update channel (use MCP Agent Mail).

MEMORY.md is the **durable mental model** future-you (after a context reset / compaction / a new agent fresh from cold start) needs to pick up where you left off.

## Anti-patterns

- ❌ One-line entries that say "did Phase 1" with no anchor — the future agent has no way to know what was actually decided.
- ❌ Inline content in MEMORY.md instead of pointers — bloats the index past the 200-line cap.
- ❌ Skipping the session file because "it was easy" — the discipline is the value.
- ❌ Editing past session files to "update them" — they're frozen at the time of authoring. Author a new session that supersedes.

## Cross-references

- `/flywheel` skill — the original MEMORY.md + session_*.md convention.
- [`methodology/CONVERGENCE.md`](CONVERGENCE.md) — uses session files to track round-over-round new findings.
- [`subagents/iteration-coordinator.md`](../../subagents/iteration-coordinator.md) — emits session files as it drives rounds.
