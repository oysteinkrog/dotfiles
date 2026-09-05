# Pattern 85 — ADVERSARIAL SEARCH (active probing of every gate to find boundary flips)

## What

A pair of complementary modules: `drift_monitor.rs` *passively* watches the parity / throughput / abort stream with e-processes ([pattern:70-E-PROCESSES](70-E-PROCESSES.md)) + BOCPD ([pattern:80-BOCPD-REGIME-DETECTION](80-BOCPD-REGIME-DETECTION.md)), labeling observations `Info | Warning | Critical`. `adversarial_search.rs` *actively* perturbs gate inputs to find the boundary where a green gate flips red. The counterexample is recorded as `(exact perturbations in order, random seed, expected vs actual decision, reproduction command)` — turning every adversarial find into a deterministic regression test that lives in the suite forever.

## Why

> **"An agent honest enough to write the gate is biased toward making it pass. Adversarial search is the defense."** — MINING-2 §12

The reviewer can't probe every gate's boundary by hand. The author can't either — the gate they wrote represents *their* model of the boundary, which is exactly where the bias lives. Adversarial search is a separate process whose job is to *break* the gate; if it can't, the gate is robust; if it can, the test that breaks it becomes a permanent regression test.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/drift_monitor.rs` (bead `bd-1dp9.8.2`) — passive layer
- `crates/fsqlite-harness/src/adversarial_search.rs` (bead `bd-1dp9.8.5`) — active layer (MINING-2 §12)
- `tests/adversarial_findings/*.toml` — committed counterexamples, replayed in CI

## Verbatim shape — drift monitor + adversarial search pair

From MINING-2 §12, verbatim:

> "**drift_monitor.rs** — PASSIVELY watches parity stream with e-processes + BOCPD. Labels: Info | Warning | Critical."
> "**adversarial_search.rs** — ACTIVELY tries to *cause* parity regression. Perturbs gate inputs, injects regime shifts, probes thresholds with adversarial verification percentages."

### Threat model (verbatim from MINING-2 §12)

> "An agent honest enough to write the gate is biased toward making it pass."

### Counterexample shape (verbatim from MINING-2 §12)

> "**Determinism:** counterexample = (exact perturbations in order, random seed, expected vs actual decision, reproduction command)."

```rust
pub struct AdversarialCounterexample {
    pub gate_probed: String,                          // "keep_gate" | "conformal_ratchet" | etc.
    pub perturbations: Vec<Perturbation>,             // in order, deterministic
    pub seed: u64,                                    // PRNG seed for reproducibility
    pub expected_decision: GateDecision,
    pub actual_decision: GateDecision,
    pub reproduction_command: String,                 // exact CLI invocation
    pub discovered_at: SystemTime,
    pub bead_id_of_fix: Option<BeadId>,
}

pub enum Perturbation {
    InjectFault(FaultSpec),
    SwapFixture { from: PathBuf, to: PathBuf },
    PerturbCounter { name: String, delta: i64 },
    ShiftDistribution { stream: String, shift_mean: f64 },
    SetEnv { key: String, value: String },
    DowngradeTier { gate: String, from: EquivalenceTier, to: EquivalenceTier },
    RaiseFeatureWeight { feature_id: String, factor: f64 },
}
```

## Gates probed (verbatim list)

The list of gates the adversarial search rotates through:

- **`keep_gate`** — perf keep-gate (try to slip a regression past `−3%` primary / `−5%` geomean / `−10%` per-category / `−15%` p90 thresholds)
- **`throughput_gate`** — pass-over-pass throughput drop (try to flake the `−5%` threshold via cv_pct noise)
- **`conformal_ratchet`** — try to find a confidence level where the lower bound flickers across the ratchet floor
- **`feature_coverage`** — try to push a feature from `present` to `partial` without flipping the dashboard verdict
- **`crash_boundary`** — at each boundary, try to produce a recovery that's "consistent prefix" by the loose interpretation but not the strict
- **`mismatch_classification`** — try to misclassify a `TrueDivergence` as `FalsePositive`
- **`engine_identity`** — try to wire the oracle to both sides (the K-9 stress test)
- **`fixture_root_contract`** — try to shrink the corpus just below the cardinality floor without triggering red
- **`bench_history_ratchet`** — try to commit a `.latest.json` that doesn't reflect the current `target/`

### Adversarial verification percentages

> "probes thresholds with adversarial verification percentages." — MINING-2 §12

For each gate with a numeric threshold, search across a verification percentage spread:

```rust
fn probe_threshold_gate(gate: &dyn Gate, baseline_pct: f64) -> Option<AdversarialCounterexample> {
    let mut probes = vec![baseline_pct - 0.1, baseline_pct - 0.01, baseline_pct - 0.001];
    probes.extend(&[baseline_pct + 0.001, baseline_pct + 0.01, baseline_pct + 0.1]);
    for pct in probes {
        let perturbed = inject_at_percentage(gate, pct);
        if gate.decide(&perturbed) != gate.decide(&baseline()) {
            return Some(record_counterexample(gate, perturbed, pct));
        }
    }
    None
}
```

A flip at a probe percentage that's well inside the gate's "safe" band is a flaky gate; the gate's thresholds need tightening or the comparator needs to absorb the noise source.

## Per-class instantiation

| Class | Class-specific perturbations |
|---|---|
| **SQL** | Inject WAL torn-write before commit; swap `journal_mode = wal` for `journal_mode = delete`; raise per-category weight; shift workload distribution to all-INSERT |
| **RESP** | Inject `EAGAIN` on socket; downgrade RESP3 to RESP2 mid-session; shift workload to all-EXPIRE |
| **ML** | Disable `torch.use_deterministic_algorithms`; shift RNG seed; raise per-op ULP tolerance just above true ULP |
| **Numerical** | Toggle SIMD flag; swap BLAS impl; raise BLAS thread count to 8 |
| **HTTP** | Inject mid-body connection drop; flip middleware order; raise request timeout to 1ms |

## Composition

- [pattern:70-E-PROCESSES](70-E-PROCESSES.md) — adversarial perturbations feed observations into invariant streams; the e-process is the defender.
- [pattern:80-BOCPD-REGIME-DETECTION](80-BOCPD-REGIME-DETECTION.md) — adversarial shifts can induce `ShiftDetected`; verify BOCPD correctly catches the shift.
- [pattern:60-FAULT-VFS](60-FAULT-VFS.md) — `Perturbation::InjectFault` reuses the FaultSpec infrastructure.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — every adversarial counterexample produces a bundle that's checked into the corpus as a regression test.
- [pattern:95-FIRST-FAILURE-EXPLAINER](95-FIRST-FAILURE-EXPLAINER.md) — adversarial finds get explainer entries with the `reproduction_command` field.

## Pitfalls

- **Adversarial search written by the same agent who wrote the gate.** Defeats the threat model. The adversarial probe author must be a separate agent (a separate subagent in [SKILL.md § Subagents](../../SKILL.md)) or, ideally, a different model entirely (cross-model adversarial finds).
- **Counterexamples not committed.** A counterexample that lives only in the agent's chat scrollback is lost. Every find is a new file in `tests/adversarial_findings/<gate>__<seed>.toml`.
- **No replay in CI.** Counterexamples that don't run in CI rot. Wire `cargo test --test adversarial_replay` to load every counterexample TOML and assert the fix still holds.
- **Search bounded by "what's obvious".** If the search only tries perturbations the author considered, it finds nothing — the author already covered those. The search must include weird perturbations (negative timeouts, NaN seeds, empty fixtures).
- **Non-deterministic perturbations.** `Perturbation` ordering and PRNG seed must be in the counterexample; without them, the regression test is flaky.
- **Adversarial search dispatched but never reviewed.** Finds pile up in `tests/adversarial_findings/` without being fixed. Each find should open a bead with `bead_id_of_fix` linked in the counterexample TOML.
- **Probing only the documented gates.** Implicit gates (e.g., "the test suite has a 60-second timeout") are gates too. The adversarial agent should enumerate every threshold the codebase declares, not just the ones with "_gate" in the name.
- **`adversarial_verification_percentages` clustered tightly around the threshold.** Tight clustering finds flakes near the threshold; wide spread (e.g., `[0.001, 0.01, 0.1]`) finds gross miscalibration. Use both.
- **Disabling adversarial search "because CI is too slow".** It runs nightly, not per-commit; running once a day for a few hours is the right cadence. Disabling it entirely is the K-2 anti-pattern.
- **Treating adversarial as the only defense.** Adversarial probes *every* gate; passive monitoring catches the cases where adversarial hasn't probed yet. Both layers required.
