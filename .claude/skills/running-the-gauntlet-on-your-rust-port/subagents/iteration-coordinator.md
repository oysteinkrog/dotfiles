# iteration-coordinator

> Phase 11 • Drive the convergence loop. Per round: dispatch Phases 5–10 workers; aggregate findings; run `scripts/convergence-tracker.sh`; exit when convergence is reached.

## Inputs
- Phase 0–10 outputs (workspace bootstrapped through first idea-wizard round).
- `scripts/convergence-tracker.sh` (computes per-round new-finding counts).
- All three negative-evidence ledgers + every per-bucket findings file.

## Deliverables
- `<workspace>/round_<N>/` directory per round with: dispatch log, per-worker outputs, aggregated findings, and synthesis.
- `<workspace>/phase11_convergence.md` summarizing: rounds executed, per-round new-finding counts, final convergence verdict.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase11-coordinator`
- **Reservations needed:** `tool://orchestrator` (TTL 480m+; long-lived).
- **Lane:** orchestrator.

## Verbatim Prompt

You are the iteration coordinator for the convergence loop. Drive Phases 5→10 until convergence is reached. The minimum is 10 full rounds; convergence is computed by `scripts/convergence-tracker.sh`.

**Per-round procedure:**

1. Create `<workspace>/round_<N>/` (where `<N>` starts at 1 and increments).

2. **Dispatch parallel workers:**
   - `bench-author.md` per workload family (if a family needs re-running per the prior round's findings).
   - `oracle-test-author.md` per behavior class with open NEEDS_REFINEMENT hypotheses.
   - `metamorphic-author.md` per family with open hypotheses.
   - `fault-injector-author.md` per category with open hypotheses.
   - `crash-boundary-wirer.md` per boundary with open hypotheses.
   - `fuzz-author.md` per target with open hypotheses.
   - `eprocess-modeler.md` per invariant with open hypotheses.
   - `baseline-runner-perf.md`, `baseline-runner-conformance.md`, `baseline-runner-surface.md` to re-baseline.
   - `idea-wizard-orchestrator.md` + `advanced-methods-miner.md` to surface new candidates.

   Workers run in their cc_N lanes; use MCP Agent Mail reservations to prevent collisions.

3. **Aggregate findings** — `synthesizer.md` reads all per-bucket outputs and writes `<workspace>/round_<N>/synthesis.md` with: new-divergence count by classification, new-hotspot count by frame, new-feature-gap count by category, new-experiment-design count by source.

4. **Run convergence-tracker:**
   ```bash
   scripts/convergence-tracker.sh <workspace>
   ```
   The script writes `<workspace>/reports/convergence_tracker.json` and computes
   `round_count`, `round_findings`, `last_two_findings`, `clean_last_two`,
   `open_hypothesis_count`, and the aggregate `converged` boolean.

5. **Decision:**
   - If `converged == true` AND `N >= 10` → proceed to Phase 12 (write `phase11_convergence.md` and exit).
   - Else → increment `N`, return to step 1.

**Convergence rule (non-negotiable; encoded in the script):**
1. **Minimum rounds:** `N >= 10`.
2. **Two consecutive clean rounds:** each producing fewer than 3 *new genuine* findings.
3. **Every open hypothesis resolved:** every entry in `GAUNTLET_EXPERIMENT_DESIGNS.md`, `PERF_HYPOTHESIS_LEDGER.md`, `CONFORMANCE_HYPOTHESIS_LEDGER.md`, `SURFACE_PARITY_HYPOTHESIS_LEDGER.md` has status `CONFIRMED_GAP | NO_EVIDENCE | NEEDS_REFINEMENT | NEW_HYPOTHESIS_SPAWNED`. (NEEDS_REFINEMENT and NEW_HYPOTHESIS_SPAWNED keep the loop going.)

**Anti-bias check:** if the loop converges quickly (3-4 rounds), do NOT trust it — the convergence may reflect an under-aggressive idea-wizard, not actual convergence. Manually run one more advanced-methods mining + frontier-math compilation round and re-check. The 10-round minimum exists to defend against this failure mode.

Document final convergence verdict in `phase11_convergence.md`.

## Exit Criteria
- `convergence-tracker.sh` exits zero (converged).
- `N >= 10`.
- Two consecutive rounds had <3 new genuine findings.
- Every open hypothesis has a resolved status.
- `phase11_convergence.md` committed.

## References
- [PHASES.md § Phase 11](../references/PHASES.md)
- [methodology/CONVERGENCE.md](../references/methodology/CONVERGENCE.md)
- [orchestration/ORCHESTRATION.md](../references/orchestration/ORCHESTRATION.md)
