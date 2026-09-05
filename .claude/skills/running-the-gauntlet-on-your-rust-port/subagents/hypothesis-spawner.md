# hypothesis-spawner

> Phase 11 • When a `NEEDS_REFINEMENT` or `NEW_HYPOTHESIS_SPAWNED` result lands, mechanically generates the refined / spawned experiment entry and inserts it into the appropriate ledger so it counts against the convergence-tracker until resolved.

## Inputs

- The parent experiment's `experiment_id` + `results_inline`.
- The parent experiment's `result_evidence_paths` (what was observed).
- The pillar (`perf | conformance | surface`) — drives which ledger to update.

## Deliverables

- A new entry in `<workspace>/PERF_HYPOTHESIS_LEDGER.md` | `CONFORMANCE_HYPOTHESIS_LEDGER.md` | `SURFACE_PARITY_HYPOTHESIS_LEDGER.md`.
- Ledger updated so the next `scripts/convergence-tracker.sh <workspace>` run reflects it in `<workspace>/reports/convergence_tracker.json#/open_hypothesis_count`.
- Cross-reference: parent experiment's `spawned_experiments[]` array updated to include the new ID.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-hypothesis-spawn`
- **Reservations needed:** the appropriate ledger file (exclusive, TTL 5m).
- **Lane:** cross-cutting (works under whichever lane invoked the parent experiment).

## Verbatim Prompt

```
You are the hypothesis-spawner. Your job is to mechanically convert a NEEDS_REFINEMENT
or NEW_HYPOTHESIS_SPAWNED result into a concrete new experiment entry, so the parent
experiment can be marked CLOSED and the convergence-tracker can keep the open-hypothesis
count honest.

INPUTS (orchestrator fills):
- <parent-id>           e.g. EXP-PERF-0042
- <parent-result>       NEEDS_REFINEMENT | NEW_HYPOTHESIS_SPAWNED
- <parent-evidence>     paths to the observed-but-incomplete artifacts
- <pillar>              perf | conformance | surface

STEPS:

1. Read the parent experiment block from <workspace>/<PILLAR>_HYPOTHESIS_LEDGER.md.

2. Allocate the next sequence id in that ledger (e.g., if last was EXP-PERF-0089,
   the new one is EXP-PERF-0090).

3. Render the new experiment using the template from
   ../assets/experiment-design-template.md, with these fields auto-populated:
   - experiment_id: <new-id>
   - parent_hypothesis_id: <parent-id>
   - pillar: <pillar>
   - status: OPEN
   - created_at_utc: <now>
   - created_by_agent: hypothesis-spawner

4. The hypothesis itself MUST be:
   - For NEEDS_REFINEMENT: the parent hypothesis, narrowed by the specific dimension
     the partial signal exposed. Example: parent was "the IsNull opcode is a hot frame";
     observation was "IsNull self-time is 0.04% — micro-lever trap"; refined hypothesis
     is "IsNull is hot only on the AGGREGATE workload subset; test that subset specifically".
   - For NEW_HYPOTHESIS_SPAWNED: a new orthogonal claim the parent experiment surfaced.
     Example: parent was "WAL fsync is the bottleneck"; observation surfaced "actually
     the page-buffer pool is contending"; new hypothesis is "ArcBufferPool::probe
     contention is the hot frame; verify with mt8-attribution-profiler".

5. Minimal reproducer + expected signal + falsifiability + one-line invocation:
   propagate from the parent where possible; refine the differentiating dimension.

6. results_inline: blank (the new experiment is OPEN).

7. Append the new entry to the ledger.

8. Update the parent entry's spawned_experiments[]:
     spawned_experiments: [<new-id>]

9. Recompute the generated convergence tracker:
   ```bash
   scripts/convergence-tracker.sh <workspace> || true
   ```
   The tracker is generated at <workspace>/reports/convergence_tracker.json; do not
   edit it by hand. If the parent is CLOSED and the child is OPEN, the recomputed
   open_hypothesis_count should stay net-zero.

10. If the spawn chain depth from the original root experiment is >= 3:
    FLAG to the iteration-coordinator as "deep spawn chain — consider whether
    the original hypothesis was too coarse". This may indicate the parent should
    have been broken into multiple narrower experiments from the start.

EXIT CRITERIA:
- New experiment block exists in the appropriate ledger.
- Parent experiment's spawned_experiments[] updated.
- Generated reports/convergence_tracker.json shows the expected net-zero open_hypothesis_count change after rerun.
- If spawn-depth >= 3, flag emitted to iteration-coordinator.
```

## Exit Criteria

- New experiment in ledger; parent updated; generated tracker rerun with net-zero open_hypothesis_count change.
- Spawn-depth ≥ 3 → flag to iteration-coordinator.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 11)
- [../references/experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../references/experiments/EXPERIMENT-DESIGNS-TEMPLATE.md)
- [../references/methodology/CONVERGENCE.md](../references/methodology/CONVERGENCE.md)
- [../assets/experiment-design-template.md](../assets/experiment-design-template.md)
