# Worked Example: E-Process (Howard-Ramdas-McAuliffe-Sekhon 2021)

End-to-end worked example showing how the e-process layer in `crates/fsqlite-harness/src/eprocess.rs` decides — at each of 1000 observations — whether to reject the null hypothesis that an invariant holds. Demonstrates Ville-bounded anytime-valid rejection, hardware-enforced vs software-enforced calibration, and why arithmetic mean of e-values is conservative under dependence.

**The invariant under test:** `INV-SoftmaxSumsToOne` — "softmax outputs sum to 1.0 within ε" — applies to ML-System-class ports (frankentorch, frankenjax, franken_whisper) at every model forward call.

---

## 1. Setup

We monitor the invariant `|sum(softmax(logits)) - 1.0| ≤ ε` where `ε = 1e-7`. Under the null hypothesis `H_0` ("the implementation is correct"), violations occur with probability at most `p₀`. Each violation is an "alarm"; an alarm under `H_0` carries information against `H_0`.

**Two calibration regimes:**

| Regime | When | `p₀` (null violation rate) | `λ` (mixing weight) | `α` (Type-I error budget) | Threshold `1/α` |
|---|---|---:|---:|---:|---:|
| Hardware-enforced | invariant guaranteed by CAS / atomics | `1e-9` | `0.999` | `1e-6` | `1,000,000` |
| Software-enforced | invariant guaranteed by code path | `1e-6` | `0.9` | `0.001` | `1,000` |

For `INV-SoftmaxSumsToOne`, classification is **hardware-enforced** because IEEE-754 fp arithmetic is deterministic under fixed kernel + fixed inputs + fixed dtype; the only way the invariant fails is via a logic bug, which is rare.

---

## 2. The E-Value Update Rule

At observation `t`, we observe outcome `Y_t ∈ {0, 1}` where `Y_t = 1` iff `|sum(softmax(logits_t)) - 1.0| > ε` (alarm), `0` otherwise.

Under `H_0`, `P(Y_t = 1) ≤ p₀`. The e-value at step `t` is:

```
E_t = E_{t-1} · ((1 - λ) + λ · Y_t / p₀)        starting from E_0 = 1
```

This is a non-negative supermartingale under `H_0` because:
```
E[(1 - λ) + λ · Y_t / p₀ | F_{t-1}] = (1 - λ) + λ · E[Y_t]/p₀ ≤ (1 - λ) + λ · 1 = 1
```

so `E[E_t | F_{t-1}] ≤ E_{t-1}` — e-values shrink in expectation under `H_0`.

**Ville's inequality** then gives anytime-valid coverage:

```
P_{H_0}(∃t : E_t ≥ 1/α) ≤ α
```

— no matter how many times we look, the false-rejection rate is at most `α`. **No Bonferroni correction needed.**

---

## 3. Worked Sequence — Hardware-enforced calibration (`p₀ = 1e-9, λ = 0.999, α = 1e-6`, threshold `1/α = 1e6`)

Observations: 1000 forward passes against a `frankentorch` softmax kernel. Suppose all of them satisfy the invariant for `t = 1..999`, then `Y_1000 = 1` (the kernel-fusion change at commit `XYZ` broke numerical stability for one input shape, surfaced at obs 1000).

### Step-by-step e-value

**At each `Y_t = 0`:**
```
E_t = E_{t-1} · ((1 - 0.999) + 0.999 · 0 / 1e-9)
    = E_{t-1} · 0.001
```

So under all-zeros, `E_t = (0.001)^t`. After 999 zeros: `E_999 = 0.001^999 ≈ 0` (effectively floor at `f64::MIN_POSITIVE`).

**At `Y_1000 = 1`:**
```
E_1000 = E_999 · ((1 - 0.999) + 0.999 · 1 / 1e-9)
       = E_999 · (0.001 + 9.99e8)
       ≈ E_999 · 9.99e8
```

Even if `E_999` had decayed to `1e-50`, `E_1000 ≈ 9.99e8 · 1e-50 = 9.99e-42` — well below the rejection threshold `1e6`.

This is correct behavior: **a single alarm shouldn't cause rejection** under hardware-enforced calibration where `p₀ = 1e-9` is the assumed null violation rate. The null says "violations are extremely rare"; one violation in 1000 obs is fully consistent.

### What does cause rejection?

Suppose between obs 1000 and 1010, 8 of 10 observations alarm (sudden burst of violations from a new bug). Resetting `E_999 = 1` for the burst calculation:

| t | Y_t | factor | E_t |
|---:|:---:|---:|---:|
| 1 | 1 | `0.001 + 0.999·1e9 = 9.99e8` | `9.99e8` |
| 2 | 1 | `9.99e8` | `9.98e17` |
| 3 | 1 | `9.99e8` | `9.97e26` |
| 4 | 1 | `9.99e8` | `9.96e35` |

By `t = 4`, `E_t ≈ 1e36`, which is `≫ 1e6 = 1/α`. **Reject `H_0` at obs `t = 4` of the burst.**

This is the right behavior: a 4-in-4 alarm under "violations are 1e-9 probability" is overwhelming evidence against `H_0`.

---

## 4. Worked Sequence — Software-enforced calibration (`p₀ = 1e-6, λ = 0.9, α = 0.001`, threshold `1/α = 1000`)

Software-enforced invariants (e.g., `INV-MVCC-VersionChainOrder` — "version chains descending by commit_seq") tolerate more frequent alarms; `p₀ = 1e-6` says violations are rare but plausible under benign causes.

**At each `Y_t = 0`:**
```
E_t = E_{t-1} · ((1 - 0.9) + 0.9 · 0 / 1e-6)
    = E_{t-1} · 0.1
```

**At each `Y_t = 1`:**
```
E_t = E_{t-1} · (0.1 + 0.9 / 1e-6)
    = E_{t-1} · (0.1 + 9e5)
    ≈ E_{t-1} · 9e5
```

After 5 consecutive alarms:
```
E_5 = 1 · (9e5)^5 = 5.9e29
```

Way above threshold `1000` — rejected at `t = 2` (since `(9e5)^2 = 8.1e11 ≫ 1000`).

After 2 alarms in 20 observations (interleaved with 18 zeros):
```
After 2 alarms × 18 zeros: E = (9e5)^2 · (0.1)^18 = 8.1e11 · 1e-18 = 8.1e-7
```

Below threshold — **not rejected.** The decay rate `λ = 0.9` correctly forgives benign sporadic alarms while concentrating on bursts.

---

## 5. Global E-Value Across Multiple Invariants (Arithmetic Mean)

The harness monitors `N = 7` invariants (INV-1..INV-7 per [PROJECT-CLASSES.md § SQL-Class](../taxonomy/PROJECT-CLASSES.md) + extensions). The global e-value:

```
E_global(t) = (1/N) · Σ_i E_i(t)
```

This is **conservative under arbitrary dependence between invariants** — even if INV-1 and INV-2 are perfectly correlated (always alarm together), `E_global` still satisfies Ville's inequality at the global level with the same `α`.

Why arithmetic mean and not max or product?
- **Product** is not a supermartingale unless invariants are independent — too anti-conservative.
- **Max** is an e-value but loses information from non-max invariants.
- **Arithmetic mean** is a supermartingale under arbitrary dependence (sum of supermartingales is a supermartingale; division by constant preserves this) — strictly conservative.

**Numerical example.** At observation `t = 500`:

| Invariant | E_i(500) |
|---|---:|
| INV-1 (Monotonicity) | `1.2` |
| INV-2 (LockExclusivity) | `0.8` |
| INV-3 (VersionChainOrder) | `1e6` (rejected on its own) |
| INV-4 (WriteSetConsistency) | `0.3` |
| INV-5 (SnapshotStability) | `2.1` |
| INV-6 (CommitAtomicity) | `0.5` |
| INV-7 (SerializedModeExclusivity) | `1.1` |

```
E_global(500) = (1.2 + 0.8 + 1e6 + 0.3 + 2.1 + 0.5 + 1.1) / 7
              ≈ 142,858
```

Hardware-enforced threshold `1/α = 1e6`. Global E ≈ 142,858 < 1e6 — global null **not rejected** even though INV-3 individually crossed.

This is correct: with multiple invariants, the per-invariant threshold may be crossed by chance (`α` per invariant × 7 invariants ≈ 7α global Type-I if uncorrected). The global e-process gives the *family-wise* anytime-valid guarantee.

In practice the orchestrator looks at BOTH `E_global` AND individual `E_i`:
- `E_global ≥ 1/α` → strong global evidence; immediate rejection.
- Individual `E_i ≥ 1/α` AND `E_global < 1/α` → flag for triage; one invariant misbehaving may be a real bug at lower confidence.

---

## 6. Rust Snippet — E-Value Updater

```rust
/// E-process updater per Howard-Ramdas-McAuliffe-Sekhon 2021.
pub struct EProcess {
    pub p_null: f64,        // p₀: null violation probability
    pub lambda: f64,        // λ: mixing weight
    pub alpha: f64,         // α: Type-I error budget
    e: f64,                 // current e-value
    obs_count: u64,         // observations seen
    rejected_at: Option<u64>,
}

impl EProcess {
    pub fn hardware_enforced() -> Self {
        Self {
            p_null: 1e-9,
            lambda: 0.999,
            alpha: 1e-6,
            e: 1.0,
            obs_count: 0,
            rejected_at: None,
        }
    }

    pub fn software_enforced() -> Self {
        Self {
            p_null: 1e-6,
            lambda: 0.9,
            alpha: 0.001,
            e: 1.0,
            obs_count: 0,
            rejected_at: None,
        }
    }

    /// Update with one observation. `alarm` = true iff invariant violated.
    /// Returns `true` if Ville threshold crossed for the first time.
    pub fn observe(&mut self, alarm: bool) -> bool {
        self.obs_count += 1;
        let factor = if alarm {
            // (1 - λ) + λ · 1/p_null
            (1.0 - self.lambda) + self.lambda / self.p_null
        } else {
            // (1 - λ) + λ · 0/p_null = (1 - λ)
            1.0 - self.lambda
        };
        self.e *= factor;

        // Saturate to avoid f64 overflow/underflow noise.
        self.e = self.e.clamp(f64::MIN_POSITIVE, f64::MAX / 2.0);

        let threshold = 1.0 / self.alpha;
        if self.e >= threshold && self.rejected_at.is_none() {
            self.rejected_at = Some(self.obs_count);
            true
        } else {
            false
        }
    }

    pub fn e_value(&self) -> f64 { self.e }
    pub fn was_rejected(&self) -> Option<u64> { self.rejected_at }
}

/// Global e-value via arithmetic mean — supermartingale under arbitrary dependence.
pub fn global_e_value(processes: &[EProcess]) -> f64 {
    let n = processes.len() as f64;
    processes.iter().map(|p| p.e_value()).sum::<f64>() / n
}
```

---

## 7. Anytime-Valid Property Demonstrated

Consider running the e-process for 1 million observations under `H_0` (no bugs, no alarms). The probability of *ever* crossing `1/α = 1e6` is at most `α = 1e-6` per Ville. This means:

- We can check `E_t ≥ 1/α` after every single observation — no "peeking penalty".
- We can stop the soak at any time and report the verdict — no "stopping rule" worry.
- Multiple soaks can be concatenated — the e-value of the concatenation is the product (valid because supermartingale property composes).

Contrast with classic NHST p-values: peeking + early stopping inflates Type-I to `α · O(√n)` (multiple-comparisons effect). E-processes are designed precisely for the gauntlet's mode of operation: continuous monitoring, anytime stopping.

---

## 8. Failure Mode Catalog

Common ways the e-process layer fails in practice (mined from FrankenSQLite negative ledger):

1. **`p₀` set too low** — e-value never accumulates; never rejects even on real bugs. (Fix: re-calibrate against per-component baseline; per [methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) typical soak runs N=1e6 obs; verify e-value reaches `1/α` on planted bugs.)
2. **`λ` set too high** — single noise alarm crosses threshold; false rejection burst. (Fix: `λ` lower; `0.999` only for true hardware-enforced; `0.9` for software-enforced is empirically tested.)
3. **Counter rolled into wrong invariant** — e.g., `nondeterministic_op_count` alarms tied to `INV-AutogradTapeMonotone` when they should be `INV-DeterminismFlagHonored`. (Fix: explicit invariant-ID-to-counter mapping in `eprocess.rs`.)
4. **E-value not snapshotted to persistent storage** — restart resets to 1.0; gauntlet loses cumulative evidence. (Fix: snapshot to `<workspace>/eprocess_state.json` per round; resume on restart.)
5. **Arithmetic mean misimplemented as max** — anti-conservative; global Type-I inflated. (Fix: replace `max` with `sum/n`; document in `score_engine.rs`.)

---

## Cross-references

- `crates/fsqlite-harness/src/eprocess.rs` — production implementation
- [PROJECT-CLASSES.md § SQL-Class § Crash-Boundary Protocol](../taxonomy/PROJECT-CLASSES.md) — per-class invariant mapping
- [methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) — multi-day BOCPD + e-process composition
- [patterns/70-E-PROCESSES.md](../patterns/70-E-PROCESSES.md) — pattern reference
- [math/conformal-band-worked.md](conformal-band-worked.md) — companion: pass-rate scoring
- [math/bocpd-worked.md](bocpd-worked.md) — companion: regime detection composes with e-process
- Howard et al. 2021 — "Time-uniform, nonparametric, nonasymptotic confidence sequences"
- Ville 1939 — supermartingale inequality (original)
