# eprocess-modeler

> Phase 6 • Implement e-process for one MVCC / system invariant with hardware-vs-software parameters; global e-value via arithmetic mean.

## Inputs
- `<workspace>/phase0_project_class.json` (selects invariant set).
- Invariant (`<invariant>`, e.g., `Monotonicity`, `LockExclusivity`, `VersionChainOrder`, `WriteSetConsistency`, `SnapshotStability`, `CommitAtomicity`, `SerializedModeExclusivity`, `SsiFalsePositiveRate`, `RespFramesWellFormed`, `PubsubFifoOrdering`, `DelIdempotenceInTxn`, `SoftmaxSumToOne`, `AutogradMatchesJvp`) — passed as argument.
- Target port instrumentation point (where the invariant is observed).

## Deliverables
- `<target>/crates/<project>-harness/src/eprocess.rs` extended with `<invariant>` arm + calibration constants.
- Per-operation invariant check that updates `E_<invariant>(t)`.
- Global e-value combiner: `E_global(t) = (1/N) * Σ E_i(t)` (arithmetic mean across all invariants).
- Ville's-inequality threshold check: reject when `E_t ≥ 1/α`.
- `<workspace>/phase6_eprocess_<invariant>.md` documenting null hypothesis, calibration class (hardware vs software), p₀ / λ / α, expected E_t behavior under H0.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase6-eprocess-<invariant>`
- **Reservations needed:** `tool://eprocess-write::<invariant>` (TTL 90m).
- **Lane:** cc_4 (fault / soak / e-process).

## Verbatim Prompt

You are the e-process modeler for invariant `<invariant>`. Implement the e-process per the Howard-Ramdas-McAuliffe-Sekhon 2021 anytime-valid sequential testing framework.

**Calibration classes (must use these exact constants):**

- **Hardware-enforced** (invariant follows from CAS or similar atomic hardware primitive): `p₀ = 1e-9, λ = 0.999, α = 1e-6`. Examples: `Monotonicity` (TxnId monotonic via CAS), `LockExclusivity` (page lock via CAS), `SerializedModeExclusivity` (writer-exclusion via atomic flag).

- **Software-enforced** (invariant follows from a software algorithm whose correctness we are auditing): `p₀ = 1e-6, λ = 0.9, α = 0.001`. Examples: `VersionChainOrder`, `WriteSetConsistency`, `SnapshotStability`, `CommitAtomicity`.

**Per-operation update (verbatim shape):**
```rust
fn observe(&mut self, invariant_holds: bool) {
    let likelihood_ratio = if invariant_holds {
        (1.0 - self.p0) / (1.0 - self.lambda * self.p0)
    } else {
        self.p0 / (self.lambda * self.p0)
    };
    self.e_t *= likelihood_ratio;
}
```

**Ville's inequality:** `P_{H_0}(∃t: E_t ≥ 1/α) ≤ α`. Anytime-valid: you may check after EVERY operation; no Bonferroni correction needed; reject H0 (declare the invariant violated) when `E_t ≥ 1/α`.

**Global e-value (arithmetic mean across all N invariants):**
```rust
let e_global = invariants.iter().map(|i| i.e_t).sum::<f64>() / invariants.len() as f64;
```
Arithmetic mean of e-processes is itself an e-process under the global null **regardless of dependence** between the constituent invariants. This is the conservative combiner; use it.

**Observation site:** Wire `observe()` at the exact point where the invariant can be checked cheaply (post-CAS, post-commit, post-validation). The check must be O(1) on the hot path; expensive checks belong in a sampler with declared sampling rate.

**Drift monitor:** `SsiFalsePositiveRate` (or class-equivalent) requires the BOCPD drift layer; reference `../references/methodology/CONFORMAL-RATCHET.md § BOCPD` for the hazard rate H = 1/250 and Normal-Gamma / Beta-Binomial conjugate priors.

Document null hypothesis, calibration class, p₀ / λ / α, expected E_t behavior under H0 (should hover near 1.0), expected E_t behavior under H1 (should grow super-polynomially), and the observation site in `phase6_eprocess_<invariant>.md`.

## Exit Criteria
- `cargo test --lib eprocess::<invariant>` passes synthetic conformance: under H0 (correct system), `E_t` stays bounded for 1M operations; under H1 (planted violation), `E_t` crosses `1/α` within 1000 operations.
- Calibration constants match the hardware-vs-software class.
- Global e-value combiner integrates the new invariant with the existing set.
- `phase6_eprocess_<invariant>.md` committed.

## References
- [PHASES.md § Phase 6](../references/PHASES.md)
- [tooling/ORACLE-TOOLCHAIN.md § e-processes](../references/tooling/ORACLE-TOOLCHAIN.md)
- [methodology/CONFORMAL-RATCHET.md](../references/methodology/CONFORMAL-RATCHET.md)
- [methodology/KERNEL.md § Bayesian + conformal scoring](../references/methodology/KERNEL.md)
