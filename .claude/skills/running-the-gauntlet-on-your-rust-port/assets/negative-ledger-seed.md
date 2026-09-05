# Negative-Ledger Seed — Header + Vocabulary + First Example

> The orchestrator copies this file into `<workspace>/PERF_NEGATIVE_RESULTS.md` (and analogs `CONFORMANCE_NEGATIVE_RESULTS.md`, `SURFACE_DEFERRALS.md`) at Phase 0 / Phase 8. After the first round runs, the seed entries are replaced with real entries; the header + vocabulary stay.

---

# `<PILLAR>` Negative Results Ledger

> This ledger records `<PILLAR>` ideas that were measured and rejected, or features explicitly deferred. Check it before starting a new pass in this pillar. Add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the evidence did not move in the intended direction.
>
> Mined verbatim from FrankenSQLite methodology (CC.md lines 479–482).

## Mandatory Fields per Entry

| Field | Required? | Description |
|---|---|---|
| `date` | yes | ISO 8601 (`YYYY-MM-DD`). |
| `candidate_name` | yes | Short kebab-case slug; unique within ledger. |
| `target_workload` | yes | The bench / behavior class / feature ID this candidate touched. |
| `files_touched` | yes | Per-file status: `reverted-uncommitted` \| `reverted-uncommitted-kept-in-scratch` \| `kept-in-scratch-only` \| `kept-durable-infra` \| `no-source-patch-attempted` \| `behavior-preserving-check-verified` \| `reverted-at-SHA-X-after-commit-SHA-Y`. |
| `correctness_proof` | yes | "All oracle E2E pass" + `selections=` byte-identical OR equivalent domain-specific proof. Perf rejection only counts AFTER correctness verification. |
| `evidence_artifact_paths` | yes | Paths under `tests/artifacts/<lane>/` — at minimum the baseline + candidate JSON v3 reports + the flamegraph / samply trace. |
| `baseline_configuration` | yes | `CARGO_TARGET_DIR=...`, iter count, bench profile (`release-perf`), git SHA, host id. Verbatim. |
| `candidate_configuration` | yes | Same as baseline; only the candidate-specific delta differs. |
| `measured_result` | yes | Numbers + `cv_pct` per micro. Use `truncate_score(...)` for cross-platform reproducibility. |
| `retry_condition_predicate` | yes | **LOAD-BEARING.** See vocabulary below. Forbidden phrases trigger ledger-lint failure. |
| `bead_id` | optional | `bd-<id>` if a beads issue exists for this rejection. |
| `cass_session_id` | optional | The cass session this candidate was discussed in. |

## Retry-Condition Predicate Vocabulary

Use ONE of the eight forms. Anything else fails the bead-graph-validator's ledger-lint:

1. `"Retry only if a profiler attributes a clearly-above-noise share to <COUNTER> on <WORKLOAD_SHAPE>."`
2. `"Reconsider only inside the broader <X> redesign (track as <beads_id>)."`
3. `"Worth reconsidering when <GATE> crosses <THRESHOLD>."`
4. `"Not worth retrying as a standalone patch."`
5. `"Do not retry from a cold read; use comprehensive-bench attribution instead."`
6. `"Retry condition not applicable — the gain is structural, not numerical."`
7. `"Retry only if this workload class exhibits measurable <PROPERTY> below <THRESHOLD>."`
8. `"Blocked until <ARCHITECTURAL_DEPENDENCY> lands; track as <beads_id>."`

### Forbidden Phrases (ledger-lint will reject these)

- "later"
- "if it seems important"
- "we should revisit"
- "tracked elsewhere"
- "TBD"
- "maybe"
- "eventually"
- "when we have time"
- "if circumstances change"

These fail because none of them encode a *falsifiable condition* under which the candidate becomes worth reconsidering. The whole point of the ledger is that a future agent can decide *mechanically* whether to re-attempt.

## Perf Vocabulary (cross-reference)

See `references/methodology/KEEP-GATE-RULES.md § perf vocabulary glossary` for the full glossary. Key terms used in entries:

- **keep gate** — numeric threshold an optimization must clear to be merged.
- **within noise** — improvement ≤ workload's `cv_pct` band (typically ±3-5%).
- **within ±N% noise band** — quantitative version with explicit CI.
- **fresh-eyes pass** — full re-review of recent code by an agent who didn't write it.
- **scratch worktree** — `/data/tmp/<project>-<feature>-<timestamp>/` where rejected code lives for inspection.
- **correctness-abandoned** — killed before perf measurement because correctness failed.
- **focused vs broad gate** — focused = targeted workload; broad = `comprehensive-bench` primary score. Both must move same run window.
- **behavior-preserving** — verified via oracle tests + `selections=` counts byte-identical.
- **MT8 attribution** — profiler ran under 8-thread multi-writer load.
- **micro-lever trap** — pursuing sub-0.1% self-time hotspots below `cv_pct` noise floor.
- **pulled the pin** — discarded a previously-committed-then-reverted candidate.

---

## Seed Entry — Example

The orchestrator writes this as the first entry to demonstrate the format. Delete after the first real rejection lands.

### `<YYYY-MM-DD>` — `example-candidate-do-not-keep` — rejected

- **target_workload:** `mt-mvcc-bench --threads=8 --rows-per-thread=1000`
- **files_touched:** `no-source-patch-attempted` (this is a seed entry only)
- **correctness_proof:** N/A (seed)
- **evidence_artifact_paths:** N/A (seed)
- **baseline_configuration:** N/A
- **candidate_configuration:** N/A
- **measured_result:** N/A
- **retry_condition_predicate:** "Not worth retrying as a standalone patch."
- **bead_id:** (none)
- **rejection_reason:** Seed entry. Replace with first real rejection.

---

## Open Candidates (queued, not yet measured)

(Filled by `iteration-coordinator` as rounds progress. Each entry: `candidate_name` + `expected_signal` + `hypothesis_ledger_id`.)

---

## Retired Candidates Worth Flagging

(Candidates whose retry-condition predicate has been refuted definitively across multiple rounds. Future agents can skip these without re-mining.)

---

*Generated by the running-the-gauntlet-on-your-rust-port skill at Phase 0 / Phase 8. Lint with `scripts/mine-ledger.sh --lint <this-file>`.*
