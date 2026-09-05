# Pattern 70 — E-PROCESSES (Ville-bounded anytime-valid invariant monitoring)

## What

A composable layer of anytime-valid sequential hypothesis tests (Howard-Ramdas-McAuliffe-Sekhon 2021) over named system invariants. Each invariant emits an observation per operation; an e-process accumulates evidence into an e-value `E_t`; Ville's inequality guarantees `P_{H_0}(∃t: E_t ≥ 1/α) ≤ α`, so the system can **check after every operation and reject the null the moment `E_t ≥ 1/α` — no Bonferroni correction needed**. The global e-value is the arithmetic mean of per-invariant e-values, which is itself an e-process under the global null *regardless of dependence*. Calibration splits hardware-enforced invariants (tight `p₀ = 1e-9`) from software-enforced (loose `p₀ = 1e-6`). Operationalizes [K-6](../methodology/KERNEL.md#k-6).

## Why

> "Anytime-valid: check after every operation, reject when crosses `1/α`, **no Bonferroni correction needed**." — MINING-2 §10

Classical hypothesis tests have a fixed sample size and a single decision. Run them N times and the Type-1 error inflates to `1 - (1-α)^N`; correcting via Bonferroni costs power. E-processes are *anytime-valid*: you watch every operation forever and stop as soon as evidence crosses `1/α`. This is exactly what an MVCC invariant monitor needs — observe billions of commits, reject the null (the invariant holds) the moment a violation accumulates.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/eprocess.rs` (bead `bd-3go.3`, 70 KB) — the e-process implementation (MINING-2 §10)
- `crates/fsqlite-mvcc/src/invariants.rs` — the 8 monitored invariants
- `crates/fsqlite-harness/src/drift_monitor.rs` — runtime layer that feeds observations to e-processes

## Verbatim shape — the 8 monitored MVCC invariants

From MINING-2 §10, verbatim:

```rust
pub enum MvccInvariant {
    Monotonicity,              // INV-1: TxnId monotone (CAS)
    LockExclusivity,           // INV-2: at most one txn holds page lock (CAS)
    VersionChainOrder,         // INV-3: chains descending by commit_seq
    WriteSetConsistency,       // INV-4: write_set ⊆ page_lock_table
    SnapshotStability,         // INV-5: snapshot immutable after first read
    CommitAtomicity,           // INV-6: committed txns all-or-nothing visible
    SerializedModeExclusivity, // INV-7: at most one serialized writer
    SsiFalsePositiveRate,      // INV-SSI-FP: drift monitor
}
```

### Calibration (verbatim, MINING-2 §10)

> **Hardware-enforced (CAS guarantees):** `p₀ = 1e-9, λ = 0.999, α = 1e-6` (INV-1, INV-2, INV-7)
> **Software-enforced:** `p₀ = 1e-6, λ = 0.9, α = 0.001` (INV-3, INV-4, INV-5, INV-6)

### E-process update step (canonical)

For each observation `x_t ∈ {0, 1}` (0 = invariant held, 1 = violated):

```rust
pub struct EProcess {
    pub p0: f64,        // null hypothesis violation probability
    pub lambda: f64,    // mixture weight
    pub alpha: f64,     // significance level
    pub e_value: f64,   // current accumulated e-value
}

impl EProcess {
    pub fn update(&mut self, x: u8) {
        // Mixture of likelihoods: under null, P(x=1) = p0; under alternative, P(x=1) = lambda
        let likelihood_alt = if x == 1 { self.lambda } else { 1.0 - self.lambda };
        let likelihood_null = if x == 1 { self.p0 } else { 1.0 - self.p0 };
        let increment = likelihood_alt / likelihood_null;
        self.e_value *= increment;
    }
    pub fn rejected(&self) -> bool {
        self.e_value >= 1.0 / self.alpha
    }
}
```

### Global e-value (arithmetic mean — verbatim MINING-2 §10)

> "`E_global(t) = Σ wᵢ Eᵢ(t)` with equal `wᵢ = 1/7`. Arithmetic mean of e-processes is itself an e-process under the global null *regardless of dependence*."

```rust
pub fn global_e_value(per_invariant: &[EProcess]) -> f64 {
    let n = per_invariant.len() as f64;
    per_invariant.iter().map(|e| e.e_value).sum::<f64>() / n
}
```

### Ville's inequality (verbatim MINING-2 §10)

> "`P_{H_0}(∃t: E_t ≥ 1/α) ≤ α`. Anytime-valid: check after every operation, reject when crosses `1/α`, **no Bonferroni correction needed**."

Ville's inequality is the supermartingale upper-bound: if `E_t` is a non-negative supermartingale (which the e-value is, under the null), then the probability it ever exceeds `1/α` is at most `α`. This is what makes "check after every operation" sound — sequential testing without multiple-comparisons correction.

## Per-class invariant analogues

### SQL-class (FrankenSQLite) — verbatim above 8 MVCC invariants

### RESP-class (FrankenRedis)

> "FrankenRedis: 'RESP frames well-formed', 'PUBSUB ordering FIFO per subscriber', 'DEL idempotent within transaction'." — MINING-2 §10

| Invariant ID | Statement | Calibration |
|---|---|---|
| `RESP-1` RespFramesWellFormed | Every RESP frame parses round-trip (no torn frames mid-byte) | Hardware (parser checksum): `p₀=1e-9, λ=0.999, α=1e-6` |
| `RESP-2` PubsubFifoPerSubscriber | Per (channel, subscriber), messages delivered in publish order | Software: `p₀=1e-6, λ=0.9, α=0.001` |
| `RESP-3` DelIdempotent | DEL of same key within MULTI/EXEC is idempotent | Software: `p₀=1e-6, λ=0.9, α=0.001` |
| `RESP-4` AofReplayIdempotent | AOF replay produces same KV as the original command stream | Software: `p₀=1e-6, λ=0.9, α=0.001` |

### ML-class (FrankenTorch)

> "FrankenTorch: 'softmax outputs sum to 1.0 within ε', 'autograd gradient matches forward-mode JVP within ε'." — MINING-2 §10

| Invariant ID | Statement | Calibration |
|---|---|---|
| `TORCH-1` SoftmaxNormalized | `softmax(x).sum() ∈ [1.0 - ε, 1.0 + ε]` for ε = 4 ULP f32 | Software: `p₀=1e-6, λ=0.9, α=0.001` |
| `TORCH-2` AutogradVsJvp | Reverse-mode gradient matches forward-mode JVP within per-op ULP | Software: `p₀=1e-6, λ=0.9, α=0.001` |
| `TORCH-3` GradcheckMaxRelError | `gradcheck_max_rel_error` ≤ contract threshold per op | Software: `p₀=1e-6, λ=0.9, α=0.001` |
| `TORCH-4` NondeterministicOpCount | `nondeterministic_op_count == 0` when `use_deterministic_algorithms(True)` | Hardware (deterministic flag): `p₀=1e-9, λ=0.999, α=1e-6` |

### Numerical-class (franken_numpy)

| Invariant ID | Statement | Calibration |
|---|---|---|
| `NP-1` DtypePromotionRespected | `(a + b).dtype == promote_types(a.dtype, b.dtype)` | Hardware (table lookup): `p₀=1e-9, λ=0.999, α=1e-6` |
| `NP-2` ViewMutationsPropagated | Mutating a view mutates the parent's bytes | Software: `p₀=1e-6, λ=0.9, α=0.001` |
| `NP-3` RngStreamBitExact | PCG64DXSM stream byte-equal to reference per seed | Hardware (deterministic): `p₀=1e-9, λ=0.999, α=1e-6` |

### HTTP-class

| Invariant ID | Statement | Calibration |
|---|---|---|
| `HTTP-1` ContentLengthHonored | Body bytes received == `Content-Length` header | Software: `p₀=1e-6, λ=0.9, α=0.001` |
| `HTTP-2` IdempotencyKeyHonored | Same Idempotency-Key on retry produces same response | Software: `p₀=1e-6, λ=0.9, α=0.001` |
| `HTTP-3` MiddlewareOrderStable | Middleware execution order matches declared stack | Hardware: `p₀=1e-9, λ=0.999, α=1e-6` |

## Composition

- [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md) — e-processes are the MVCC-invariant row's Comparator (Ville threshold).
- [pattern:60-FAULT-VFS](60-FAULT-VFS.md) — fault campaigns generate observations; the invariants are checked under fault.
- [pattern:65-CRASH-BOUNDARIES](65-CRASH-BOUNDARIES.md) — post-recovery invariants (INV-6 CommitAtomicity) feed observations into the e-process.
- [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) — Beta posterior + conformal band are the *release-decision* layer; e-processes are the *runtime monitoring* layer. Both required.
- [pattern:80-BOCPD-REGIME-DETECTION](80-BOCPD-REGIME-DETECTION.md) — BOCPD detects when the *distribution* shifts (regime change), complementing e-process's threshold rejection.
- [pattern:85-ADVERSARIAL-SEARCH](85-ADVERSARIAL-SEARCH.md) — adversarial gate inputs feed invariant streams; the e-process is the defender.

## Pitfalls

- **Using a fixed-N classical test instead.** Running a chi-square at "the end" of the test suite is the wrong shape — there is no end. E-processes are designed for unbounded observation.
- **Calibrating hardware-enforced and software-enforced invariants identically.** A CAS-guaranteed monotonicity check that "violates" once is almost certainly a CPU bug, not an MVCC bug — `p₀ = 1e-9` reflects that prior. Treating it like a software invariant (`p₀ = 1e-6`) blunts the alarm by 1000x.
- **Geometric mean instead of arithmetic.** The "arithmetic mean of e-processes is itself an e-process regardless of dependence" property is what makes the global e-value sound under arbitrary correlation between invariants. Geometric mean requires independence assumptions.
- **Resetting `e_value` periodically to "avoid runaway".** Don't. The supermartingale property requires uninterrupted accumulation. If you reset, you've broken Ville's inequality.
- **Forgetting that `λ` is the alternative-hypothesis violation probability.** `λ = 0.999` means "if the invariant is violated, it's violated frequently"; `λ = 0.9` means "if violated, violated often but not always". Choose based on the expected violation regime.
- **Per-invariant `α` set looser than the global α**. Per-invariant `α = 0.001` and global `α = 1e-6` is fine (the union bound holds), but reverse it and the global level is meaningless.
- **No observation when invariant trivially holds.** If you only emit `x = 1` (violation) and never `x = 0` (held), the e-value never decreases when the system is healthy — it stays near its initial value, eventually crossing `1/α` from random walk noise. Emit observations on every operation.
- **Drift monitor not wired to all operations.** If e-processes only see "the slow path", you're sampling biased; the fast path's behavior never updates the e-value. The drift monitor must observe every CAS, every commit, every snapshot read.
- **Persisting e-values across process restarts incorrectly.** A restart that resets `e_value` to 1.0 loses accumulated evidence. Persist the e-value to disk; reload at startup. (Or accept fresh-process semantics and document.)
- **Skipping `INV-SSI-FP` because "it's a drift monitor not an invariant".** It's both — the false-positive *rate* is itself a probabilistic invariant. Treat it identically.
