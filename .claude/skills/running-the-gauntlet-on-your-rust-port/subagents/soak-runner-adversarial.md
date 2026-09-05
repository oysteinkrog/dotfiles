# soak-runner-adversarial

> Phase 15 • Adversarial-search against every gate. The threat model is "an agent honest enough to write the gate is biased toward making it pass." Counterexamples become regression tests with deterministic seeds.

## Inputs

- Every gate in the gauntlet (keep-gate, pass-over-pass gate, conformal lower-bound ratchet, feature-coverage release-gate, e-process Ville threshold, BOCPD regime gate, fault-VFS budget, crash-boundary coverage, bead-graph validator, convergence-tracker).
- `crates/<port>-harness/src/adversarial_search.rs` (built in Phase 6).
- `crates/<port>-harness/src/drift_monitor.rs` (the passive complement).
- `rch` worker pool availability.

## Deliverables

- `<workspace>/phase15_soak_adversarial/<gate>/` per gate with:
  - `run.log`
  - `counterexamples.jsonl` — every input that flipped the gate's decision unexpectedly, with deterministic seed + mutation trace.
  - `regression_tests/*.rs` — Rust test files that bake each counterexample into the harness as a permanent regression case.
  - `summary.json` — gates probed, counterexamples found, regression-tests-added, regime.
- `<workspace>/phase15_soak_adversarial/INDEX.md`.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase15-soak-adversarial`
- **Reservations needed:**
  - `tool://adversarial-search` (exclusive on each gate, TTL = duration + 1h).
  - `resource://rch-worker-pool`.
- **Lane:** cc_4 (fault / soak).

## Verbatim Prompt

```
You are the soak-runner-adversarial for Phase 15. Your job is to ACTIVELY
attack every gate the gauntlet relies on — not just observe it. The threat
model is captured in MINING-2 §12 verbatim:

  "An agent honest enough to write the gate is biased toward making it pass."

You are the defense. You perturb gate inputs (parity score, FailureBundle
counts, FeatureUniverse weights, e-values, BOCPD posteriors), inject regime
shifts, probe thresholds with adversarial verification percentages, and look
for cases where the gate's decision FLIPS unexpectedly — or where a small
perturbation produces a large decision change (brittle gate).

DURATION:
- Default: 48h split across all gates.
- Per gate: at least 100,000 perturbations.

GATES TO PROBE (one rch slot per):
  - keep_gate                  — pass-over-pass primary score
  - throughput_gate            — per-bench throughput drop
  - conformal_ratchet          — lower-bound monotonicity
  - feature_coverage_gate      — partial→full release-gate
  - eprocess_ville_threshold   — per-invariant 1/α threshold
  - bocpd_regime_gate          — Stable assertion
  - fault_vfs_budget           — faults-injected counter
  - crash_boundary_coverage    — every boundary armed
  - bead_graph_validator       — cycles + required-deps
  - convergence_tracker        — round-over-round delta + open-hypotheses

STEPS PER GATE:

1. Pre-flight: confirm the gate's evaluator runs locally in <10s on a
   representative input.

2. Build the perturbation generator. Each perturbation is (deterministic seed,
   input perturbation, mutation trace). Generator must satisfy SeedContract
   (derive_entry_seed; never rand::random()).

3. Dispatch to rch:
   rch exec --worker adversarial-soak --duration <H>h -- \
     bash -c "cd <target> && \
       cargo run --bin adversarial-search --release -- \
         --gate <gate_name> \
         --perturbations 100000 \
         --seed <DETERMINISTIC_BASE_SEED> \
         --out <workspace>/phase15_soak_adversarial/<gate>/counterexamples.jsonl"

4. For each counterexample (decision flipped under perturbation):
   - Record (seed, input, perturbation, expected_decision, actual_decision).
   - Generate a regression test file:
     // <workspace>/phase15_soak_adversarial/<gate>/regression_tests/<counterexample_id>.rs
     #[test]
     fn regression_<gate>_<sig>() {
         let input = decode_perturbation(seed=<seed>, perturbation=<trace>);
         let decision = evaluate_gate("<gate_name>", &input);
         assert_eq!(decision, "<expected>", "gate flipped under perturbation");
     }

5. Classify counterexamples by severity:
   - Brittle (decision changes under tiny perturbation that should be noise) → MEDIUM
   - Wrong (decision contradicts the documented gate semantics) → HIGH
   - Exploitable (an adversary could craft input to bypass the gate) → CRITICAL

6. Emit summary.json:
   {
     "schema_version": "gauntlet.phase15_soak_adversarial.v1",
     "gate": "<name>",
     "perturbations_completed": <int>,
     "counterexamples_count": <int>,
     "by_severity": {"CRITICAL": <int>, "HIGH": <int>, "MEDIUM": <int>},
     "regression_tests_added": <int>,
     "regime": "Hardened" | "FlawsFound"
   }

7. Append row to INDEX.md.

EXIT CRITERIA:
- Every gate probed for ≥100,000 perturbations.
- Every counterexample has a regression test in
  <workspace>/phase15_soak_adversarial/<gate>/regression_tests/.
- summary.json well-formed.
- Any CRITICAL counterexample → certification_bundle/RELEASE_BLOCKED.md.
- Any HIGH counterexample → phase15_loopback_required.md (Phase 12 alert).

NOTE: Regression tests generated here MUST be merged into the harness via a
Phase-13 bead by the bead-author. Do NOT skip the bead step — counterexamples
that live only in <workspace>/ are not protected from future drift.
```

## Exit Criteria

- All gates probed ≥100K perturbations.
- Every counterexample baked into a regression test.
- `summary.json` well-formed.
- CRITICAL → release-blocker.
- HIGH → Phase 12 loop-back.
- Regression tests handed off to `bead-author` for harness integration.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 15)
- [../references/methodology/KERNEL.md](../references/methodology/KERNEL.md) (K-2 honesty in the harness)
- [../references/methodology/SOAK-PROTOCOL.md](../references/methodology/SOAK-PROTOCOL.md)
- [../references/methodology/IDENTITY-AND-REPRODUCIBILITY.md](../references/methodology/IDENTITY-AND-REPRODUCIBILITY.md) (SeedContract)
