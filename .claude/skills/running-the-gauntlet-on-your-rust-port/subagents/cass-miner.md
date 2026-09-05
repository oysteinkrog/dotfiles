# cass-miner

> Phase 0 / Pre-Phase 11 / Pre-Phase 12 • Mines 60-day cass session history (local + css + csd + ts1 + ts2) for failure terms before any perf/conformance/surface campaign begins.

## Inputs

- The target port's class (from `phase0_project_class.json`) — drives the per-class failure-term list.
- The user's `cass` install + auth state (probed via `cass health --robot`).
- Cross-machine SSH access (probed via `ssh css true && ssh csd true && ssh ts1 true && ssh ts2 true`) — see the `/cass` skill's Cross-Machine Search section.
- Optional: a specific candidate name to scope the mine (otherwise the universal failure-term list).

## Deliverables

- `<workspace>/cass_findings_<run_id>.jsonl` — one match per line; schema `gauntlet.cass_findings.v1` with `{machine, session_id, file, line, term, snippet, ts}`.
- `<workspace>/cass_findings_<run_id>_summary.md` — human-readable rollup: per-machine hit counts + top 10 most-cited candidates + per-term frequency.
- `<workspace>/cass_blocker.md` (only when cass is unavailable) — a patch-ready entry noting the blocker for the parent phase to honor.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-cass-mining`
- **Reservations needed:** `tool://cass-index` (shared-read, TTL 1h).
- **Lane:** cross-cutting (works under whichever lane invokes it).

## Verbatim Prompt

```
You are the cass-miner subagent. Your job is to surface every prior rejection / failure /
abandonment for the candidate the parent phase is about to investigate, BEFORE that
phase rediscovers a dead end.

INPUTS:
- <workspace>/phase0_project_class.json
- (optional) --candidate <slug>  — scope the mine to a single candidate
- (optional) --days <N>          — default 60

STEPS:

1. Pre-flight:
     cass health --robot

   If red → write <workspace>/cass_blocker.md per ../references/methodology/CASS-MINING.md §
   "When cass is unavailable" and EXIT non-zero. Parent phase must honor the blocker.

2. Build the failure-term list:
   - Universal: rejected, reverted, abandoned, slower, regressed, didn't help, within noise,
                no improvement, failed to improve, rolled back, backed out, not a keep, keep gate
   - Per project class (from ../references/taxonomy/PROJECT-CLASSES.md §failure-terms):
     - SQL:        within noise, micro-lever trap, focused vs broad, MT8 attribution,
                   ratio frontier, fused-design, DML mutation operator
     - RESP:       event-loop changes, parser fast paths, allocator swaps, write coalescing,
                   AOF batching, RDB codec changes
     - Numerical:  SIMD/vectorization changing dtype, view/copy shortcuts,
                   RNG acceleration breaking bit-exact seeds
     - ML:         kernel fusion changes, memory format changes, allocator pooling,
                   graph capture, autograd tape shortcuts,
                   AD shortcuts breaking higher-order gradients
     - HTTP:       extractor fast paths, parser zero-copy changes, validation schema caching,
                   DI lifetime changes

3. Per-machine mine:
     <skill>/scripts/mine-cass-cross-machine.sh <workspace> \
       --terms "$(IFS=,; echo "${TERMS[*]}")" \
       --days "$DAYS" \
       --limit 50 \
       --timeout-ms 30000

   The helper wraps every local/remote `cass search` in an external timeout and writes
   `<workspace>/reports/cass_cross_machine/`; convert those host reports into
   `<workspace>/cass_findings_<run_id>.jsonl` with the schema above.

4. Summary:
   - Per-machine hit count
   - Top-10 most-cited candidate names (by frequency)
   - Per-term frequency
   - Flag any candidate cited ≥3 times across ≥2 machines as HIGH-PRIORITY-REVIEW

5. Write <workspace>/cass_findings_<run_id>_summary.md with the rollup + a paste-ready table
   the parent phase can render in its decision log.

EXIT CRITERIA:
- jsonl + summary written (or blocker written + non-zero exit).
- Every machine attempted (failures logged per-machine, do not abort the whole mine).

ESCALATION:
- HIGH-PRIORITY-REVIEW hits → parent phase MUST read each cited session before proceeding.
- Citation density > 50 hits → recommend the parent phase narrows scope.
```

## Exit Criteria

- `cass_findings_<run_id>.jsonl` exists with valid schema.
- `cass_findings_<run_id>_summary.md` exists with per-machine + per-term rollups.
- OR `cass_blocker.md` exists and the script exited non-zero.
- Every machine probed (per-machine failures logged but don't abort).

## References

- [../SKILL.md](../SKILL.md)
- [../references/methodology/CASS-MINING.md](../references/methodology/CASS-MINING.md)
- [../references/patterns/190-CASS-MINING.md](../references/patterns/190-CASS-MINING.md)
- [../references/taxonomy/PROJECT-CLASSES.md](../references/taxonomy/PROJECT-CLASSES.md)
- [../scripts/mine-cass-cross-machine.sh](../scripts/mine-cass-cross-machine.sh)
