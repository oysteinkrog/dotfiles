# Convergence — Criteria, Measurement, jq Queries

The audit ends when it converges. This file says what "converged" means and how to measure it.

---

## Convergence Definition

A run has converged when **all** of the following hold simultaneously, across two consecutive rounds:

1. Every entry in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` has a verdict ≠ `OPEN`.
2. The round's *new-findings count* (the number of new rows added to `phase4_unified_findings.md` since the previous round) is <3.
3. The round's *newly-`NEEDS_REFINEMENT`-count* is 0.
4. The total round count is **≥ the archetype-aware floor** (see below).

Both rounds must satisfy criteria 1–3. The floor is independent of those: even if Round 3 is quiet, the loop runs until the floor.

### Archetype-aware round floor

The 10-round floor was originally calibrated for unsafe-heavy crates. A field trial against a `#![forbid(unsafe_code)]` pure-safe project (no FFI, no manual `unsafe impl Send/Sync`, no aliasing-bucket sites) reached substantive completion in 7 rounds — rounds 8-10 would have produced near-zero findings because 19 of the 25 UB-taxonomy buckets are structurally inapplicable under forbid-unsafe. The 10-round floor was theatre for this archetype.

Use this table:

| Archetype (declared in `phase0_run.json`) | Run mode | Round floor |
|-------------------------------------------|----------|-------------|
| Has any `unsafe` in crate code, OR FFI, OR `unsafe impl Send/Sync`, OR `#[repr(packed)]` field-take, OR custom allocator, OR lock-free DS | Standard | **10** (non-negotiable) |
| Has any `unsafe` in crate code (etc.) | Exhaustive | **10** (non-negotiable) |
| `#![forbid(unsafe_code)]` AND no FFI AND no manual unsafe-impls (i.e., archetype P15 in [PROJECT-TYPES.md](PROJECT-TYPES.md#p15-pure-safe-forbid-unsafe-projects)) | Standard | **3** (with mandatory confirm-clean idea-wizard pass) |
| `#![forbid(unsafe_code)]` (etc.) | Exhaustive | **5** (idea-wizard runs 3 rounds in Exhaustive — each is substantively different) |
| Quick mode (any archetype) | — | (phase 7 not run) |

The archetype is **declared** in `phase0_run.json` at the START of the run by the orchestrator, with rationale. If during Phase 1 a `unsafe` block is discovered in code that was claimed to be forbid-unsafe (e.g., a feature-gated module, a macro-expanded site), the archetype upgrades to "has unsafe" and the floor reverts to 10. Document the upgrade in `phase0_run.json` revision history.

**Why "3 rounds" is enough for pure-safe:**
- Round 1: Phase 1 RECON + Phase 2 bucket sweeps + Phase 3 Miri-on-pure-logic + Phase 4 synthesis + Phase 5 execution.
- Round 2: Phase 6 multi-round idea-wizard (2 lenses for Standard) + Phase 5 execution of new EXPs.
- Round 3: Phase 6 re-mining for any remaining gaps + Phase 5 + confirm-clean Phase 4.

Each round still has all the same gates; the round COUNT shrinks because there are fewer UB shapes to find. The gates do not relax.

---

## Measurement: `scripts/convergence-tracker.sh`

The script runs at the end of every Phase-7 round:

```bash
./scripts/convergence-tracker.sh "$WORKSPACE"
```

It:
1. Reads `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` and counts entries by verdict.
2. Reads `phase4_unified_findings.md` and counts new rows since the previous round's snapshot (stored as `phase7_findings_snapshot_round_<N-1>.txt`).
3. Writes `phase7_convergence_round_<N>.json`:

   ```json
   {
     "round": 7,
     "verdicts": {
       "OPEN": 0,
       "CONFIRMED_UB": 12,
       "NO_EVIDENCE": 18,
       "NEEDS_REFINEMENT": 1,
       "DEFERRED": 2
     },
     "new_findings": 2,
     "new_needs_refinement": 1,
     "quiet": false
   }
   ```

4. Exits **0** if the round is `quiet: true` AND there is at least one prior `quiet: true` round; exits **>0** otherwise.

The orchestrator runs `convergence-tracker.sh` after each Phase-7 round; the loop ends only on exit code 0.

---

## jq Queries

```bash
# Verdict distribution from EXPERIMENT-DESIGNS:
grep -oE '\*\*Verdict:\*\* (OPEN|CONFIRMED_UB|NO_EVIDENCE|NEEDS_REFINEMENT|DEFERRED)' \
  UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md \
  | awk '{print $2}' | sort | uniq -c

# Are we done?
jq -e '.quiet and .verdicts.OPEN == 0 and .verdicts.NEEDS_REFINEMENT == 0' \
  phase7_convergence_round_*.json | tail -2

# Plot of new-findings over rounds (CSV for a graph):
for f in phase7_convergence_round_*.json; do
  jq -r '[.round, .new_findings, .new_needs_refinement, .quiet] | @csv' "$f"
done > convergence.csv
```

---

## Quiet Round Edge Cases

- **Round 1 is never quiet.** Even if static + dynamic sweep finds nothing, the loop must run at least 10 rounds because the *idea-wizard* in Phase 6 hasn't fired yet at Round 1.
- **A round with only DEFERRED additions** doesn't count as quiet. DEFERRED is a punt, not a resolution.
- **A round where `NEEDS_REFINEMENT` increases** is never quiet, regardless of `new_findings` count.

---

## When To Manually Override Convergence

If after 15+ rounds the loop is producing new findings only because of test churn (e.g., new fuzz seeds keep finding the same shape of UB), the orchestrator may:

1. Group the recurring findings into a single Phase-8 remediation.
2. Mark all entries pointing at that shape as `CONFIRMED_UB` with a shared root-cause ID.
3. Update `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` to consolidate the duplicates.

This is a *judgment call*. Document it in `phase7_manual_override.md` with rationale.

---

## Soak (Phase 11) Convergence

Phase 11 has its own convergence criteria:

- 24h fuzz: zero crashes
- Multi-day Miri: zero `Undefined Behavior` errors across the matrix
- Loom 10⁴+: zero assertion failures
- Shuttle 10⁵+ random schedules: zero failures

Any campaign that exits before its time budget without meeting its criterion is a *failure of the remediation*, not a convergence event. Loop back to Phase 8.

---

## End State

When the loop ends:
1. `phase7_convergence_summary.md` is written with the round-by-round counts.
2. The convergence-evidence appendix in `FINAL_UB_REPORT.md` is generated from `phase7_convergence_round_*.json`.
3. The orchestrator posts a summary to the user: total rounds, total findings (by verdict), DEFERRED rationale.
