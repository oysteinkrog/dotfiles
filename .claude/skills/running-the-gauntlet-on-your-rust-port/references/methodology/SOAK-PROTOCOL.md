# SOAK-PROTOCOL — The Phase 15 Soak Playbook

This file is the operational playbook for Phase 15 (Soak / Deep-Validation). Soak is the gauntlet's defense against the class of bugs that hide in tail distributions: rare interleavings, regime shifts in long streams, edge-case schedules, adversarial input distributions. It is intentionally expensive — durations measured in days, not minutes — and intentionally `rch`-offloaded because the dev host cannot afford to sit idle while a multi-day fuzz runs. See [../../SKILL.md § Phase 15](../../SKILL.md) for the phase summary and [OPERATORS.md § ⊞ Soak](OPERATORS.md) for the operator that triggers it.

---

## (a) Soak durations by harness

Each soak harness has a minimum duration below which the soak is presumed insufficient. The dispatcher (`scripts/run-soak-campaign.sh`) refuses to declare a harness "soaked" until the minimum is met.

| Harness | Minimum duration | Iteration floor | Workload | Verdict criterion |
|---|---|---|---|---|
| **Differential fuzz** | 24 hours wall-clock | N/A (continuous) | Subject vs oracle on `derive_entry_seed`-driven corpus | Zero new `TrueDivergence` `MismatchSignature`s in the last 6 hours |
| **Miri** | Multi-day (≥48h) | One full pass over harness-internals test set | Harness-internal types (the engine itself is too slow under Miri; soak the harness) | Zero UB, zero unsoundness reports |
| **Loom + Shuttle** | Multi-thousand iterations | ≥10,000 per critical interleaving target | Each `loom::model` and `shuttle::check` configured target | Zero panics, zero assertion failures, BPOR/DPOR coverage report attached |
| **Crash-boundary** | Multi-thousand iterations | ≥5,000 fault-injection sequences | Every named boundary × every fault profile (combinatorial) | Recovery state satisfies the consistency predicate for every (boundary, fault) pair |
| **BOCPD on parity-score stream** | Multi-day rolling window | ≥1,000 windows | The continuous stream of parity-score samples from the differential fuzz harness | `Regime::Stable` for ≥3 consecutive windows; no `Regime::ShiftDetected` in trailing 24h |
| **Adversarial-search** | One full pass per gate | N/A (exhaustive per gate) | Perturbation of every gate's input + threshold + decision rule | No counterexample (a perturbation accepted by the gate but rejected by the ground-truth oracle) found |

The "minimum" is the floor for declaring done; the loop *may* continue longer if the verdict criterion isn't met. A 24h fuzz that finds a new divergence in hour 23 resets the 6-hour quiescence requirement, extending the run.

---

## (b) Why this isn't covered by per-round tests

Per-round tests (Phases 5–10) run on a budget — minutes to a couple of hours per round. They surface the failures that are reproducible at modest cost. Soak surfaces the class of failures that aren't:

### Surfacing rare bugs
The per-round fuzz target runs ~10^6 inputs and surfaces ~10^4 unique divergences. The 24-hour fuzz runs ~10^9 inputs and surfaces the long tail: the 10^-7 frequency divergences that don't appear in the per-round budget. The FrankenSQLite history has multiple examples of bugs first found in hour 14+ of a soak (recovery edge cases, MVCC visibility windows of width <1ms).

### Anytime-valid sequential testing
Per-round tests stop after a fixed budget; if they're going to find the bug, they find it then. The e-process layer (MINING-2 §10) gives anytime-validity: `P_{H_0}(∃t: E_t ≥ 1/α) ≤ α`. Watch every operation forever; reject the null the moment the e-value crosses `1/α`. The per-round test cannot give this guarantee — it stops too soon. The soak run *is* the anytime-valid test, instantiated against the project's monitored invariants:

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

The same machinery applied to RESP-class: "RESP frames well-formed", "PUBSUB ordering FIFO per subscriber", "DEL idempotent within transaction". To Tensor-class: "softmax outputs sum to 1.0 within ε", "autograd gradient matches forward-mode JVP within ε".

The e-process under soak is what catches the 1-in-10^9 invariant violation that per-round can't.

---

## (c) Dispatching to `rch` workers

Soak is `rch`-offloaded. The dev host cannot afford to sit idle for days. The cost discipline:

> **Anything >5 minutes wall time → rch.** A 30-minute local bench is acceptable. A 24-hour local fuzz is not — it blocks every other agent's bench, perf-skews under your interactive workload, and risks getting killed by the OOM killer or the daily reboot.

### `rch exec` invocation patterns

```bash
# 24h differential fuzz
rch exec --label "soak-fuzz-$(date -u +%Y%m%dT%H%M%SZ)" \
         --time-limit 25h \
         --artifact-dir round_${ROUND}/soak/fuzz \
         -- cargo fuzz run differential_v2 -- \
            -max_total_time=86400 \
            -timeout=30 \
            -workers=$(nproc)

# Multi-day miri
rch exec --label "soak-miri" \
         --time-limit 72h \
         --artifact-dir round_${ROUND}/soak/miri \
         -- cargo +nightly miri test -p fsqlite-harness --release --

# Multi-thousand-iter loom
rch exec --label "soak-loom" \
         --time-limit 48h \
         --artifact-dir round_${ROUND}/soak/loom \
         -- env LOOM_MAX_PREEMPTIONS=4 LOOM_LOG=1 cargo test --release \
            -p fsqlite-mvcc --test loom_models -- --nocapture

# Multi-day BOCPD against the live parity-score stream
rch exec --label "soak-bocpd" \
         --time-limit 96h \
         --artifact-dir round_${ROUND}/soak/bocpd \
         -- cargo run -p fsqlite-harness --bin drift_monitor -- \
            --stream artifacts/scorecards/parity-score.jsonl \
            --hazard 0.004 \
            --window 256 \
            --emit-regimes round_${ROUND}/soak/bocpd/regimes.jsonl
```

### `rch`-offload rules
1. Always `--label` with a soak-class prefix + ISO-8601 timestamp.
2. Always `--time-limit` ≥ 1h above the minimum to give the worker slack.
3. Always `--artifact-dir` to a `round_N/soak/<class>/` path (not a workspace-temp).
4. Always commit a `soak_dispatch_<class>.json` next to the dispatch with the full rch command and the expected outputs.
5. Never run two soak harnesses targeting the same workspace concurrently on the same worker (they share the build cache and will compete).
6. On worker pool exhaustion, queue the dispatch via `rch queue` rather than blocking; the convergence-tracker has slack for staggered soak completion.

---

## (d) Soak-failure handling

A soak failure is **always** a loop-back to Phase 12 (Remediation). It is never "we'll address it next release" — soak findings are exactly the bugs that don't surface until production, and the gauntlet's promise is that they surface here.

### Concrete loop-back protocol
1. `run-soak-campaign.sh` writes `soak_findings_<class>.jsonl`, one finding per line, with full `FailureBundle v1.0.0` (per [IDENTITY-AND-REPRODUCIBILITY.md § FailureBundle](IDENTITY-AND-REPRODUCIBILITY.md)).
2. Each finding is dedup'd by `MismatchSignature` against the existing hypothesis ledgers.
3. New genuine findings are filed as `bd-soak-<class>.<seq>` beads with `priority=critical` and the FailureBundle attached.
4. Phase 12 architects pick up the new beads; the convergence loop reopens; Phase 14 (fresh-eyes) must re-pass two consecutive clean rounds before Phase 15 reruns.
5. The fixed soak finding becomes a permanent regression test: the failure's repro command (from the FailureBundle's `replay_command`) is added to the per-round test suite, so future rounds catch the regression within minutes.

### Specific failure-class handling

| Soak finding | Phase 12 response |
|---|---|
| Differential fuzz `TrueDivergence` | New hypothesis in `CONFORMANCE_HYPOTHESIS_LEDGER.md`; minimize via [OPERATORS.md § ⌘ Reduce](OPERATORS.md); fix via [OPERATORS.md § ⊕ Isomorphic-Rewrite](OPERATORS.md). |
| Miri UB | Source change required; treat as a `correctness-abandoned` blocker; no perf work on the affected path until UB is removed. |
| Loom/Shuttle assertion failure | DPOR coverage shows the interleaving; the failure is the minimum repro; fix via lock-discipline correction or invariant tightening. |
| Crash-boundary inconsistency | Recovery code is wrong; the FailureBundle's `wal_state_at_failure` is the artifact to study; fix is a recovery-state machine change. |
| BOCPD `Regime::ShiftDetected` | The distributional assumption underlying the conformal band has broken. Halt; investigate the change-point; see (e) below. |
| Adversarial-search counterexample | A gate is biased. The counterexample is the regression test. Fix the gate; rerun adversarial-search until exhaustion completes cleanly. |

---

## (e) BOCPD on the parity-score stream

BOCPD (Bayesian Online Change-Point Detection, Adams-MacKay 2007) watches the continuous stream of parity-score samples emitted by the differential fuzz harness. The detector's output:

```rust
pub enum Regime {
    Stable,           // no statistical change
    Improving,        // better than baseline
    Regressing,       // worse than baseline
    ShiftDetected,    // BOCPD detected regime shift mid-run
}

pub struct ReplayHarnessResult {
    pub regime: Regime,
    pub throughput_posterior: BetaParams,        // Normal-Gamma
    pub abort_rate_posterior: BetaParams,        // Beta-Binomial
    pub window_regimes: Vec<Regime>,
}
```

### What `Regime::Stable` evidence proves
- The parity-score stream's posterior parameters are not changing within the configured hazard rate (`H = 1/250` default, per MINING-2 §7).
- The Beta posterior used by the ratchet (see [CONFORMAL-RATCHET.md](CONFORMAL-RATCHET.md)) is being fit against a distribution whose first two moments are stable.
- The release decision's lower-bound is calibrated against an honest stream — no late-breaking regime change is contaminating the bound.
- Required: `Regime::Stable` for ≥3 consecutive windows AND no `ShiftDetected` in trailing 24h before release certification can claim soak-coverage.

### What `Regime::ShiftDetected` means for release-readiness
- The detector found a change-point with run-length posterior probability above its threshold.
- Something changed in the parity-score distribution mid-soak: it could be a code-state issue (a flaky test reproducing more often), a workload issue (the fuzz corpus exhausted easy cases and started finding harder ones), or a real regression that the per-round tests missed.
- **Release certification is blocked** until the change-point is investigated and either:
  (a) Attributed to a known cause (fuzz corpus shape change is expected; document and continue), OR
  (b) A genuine regression is found and fixed (loop back to Phase 12), OR
  (c) The detector's calibration is shown to be incorrect (rare; requires recalibration evidence per [CONFORMAL-RATCHET.md § calibration](CONFORMAL-RATCHET.md)).
- Even if (a) holds, the release certificate cites the change-point and the cause; the reader knows the soak surfaced a regime shift and it was understood.

### How to inspect window regimes
```bash
jq -r '.window_regimes | to_entries[] | "\(.key)\t\(.value)"' \
   round_${ROUND}/soak/bocpd/result.json
# 0    Stable
# 1    Stable
# 2    Improving
# 3    ShiftDetected     ← change-point at window 3
# 4    Stable
# 5    Stable
```

The shift point's window index plus the per-window timestamps in `regimes.jsonl` give a precise temporal localization. The differential fuzz harness's events around that window are the evidence; grep them by `run_id` time-range.

### Calibration parameters
| Parameter | Default | Meaning |
|---|---|---|
| `hazard_rate` (H) | `1/250` | Prior probability of regime change per sample. Lower H = more sensitive; higher H = more tolerant. |
| `window_size` | 256 samples | Each emitted regime label is computed over a sliding window of this many samples. |
| `predictive_model` | Normal-Gamma (throughput), Beta-Binomial (rates) | Conjugate priors per stream type per MINING-2 §7. |
| `min_run_length` | 64 | Minimum samples in a regime before BOCPD will emit `ShiftDetected` (avoids edge-of-data noise). |

The defaults are FrankenSQLite-tuned; bumping `hazard_rate` to `1/100` gives faster detection at the cost of more false positives. Tune per-project after at least one full soak cycle.

---

## Cross-links

- This file implements [OPERATORS.md § ⊞ Soak](OPERATORS.md).
- BOCPD is one of the three statistical layers per [KERNEL.md § K-6](KERNEL.md); the other two are documented in [CONFORMAL-RATCHET.md](CONFORMAL-RATCHET.md).
- Soak findings get `FailureBundle`s per [IDENTITY-AND-REPRODUCIBILITY.md § FailureBundle](IDENTITY-AND-REPRODUCIBILITY.md).
- The loop-back to Phase 12 on soak failure is the documented loop edge in [../../SKILL.md § Phase 15](../../SKILL.md).
- Adversarial-search machinery is in [../tooling/ORACLE-TOOLCHAIN.md § adversarial_search](../tooling/ORACLE-TOOLCHAIN.md) and the e-process layer in MINING-2 §10.
- Convergence cannot complete with `ShiftDetected` open; see [CONVERGENCE.md § (f) stalled convergence](CONVERGENCE.md).
- The `rch`-offload heuristic ("anything >5 minutes → rch") is the central thread of [../orchestration/ORCHESTRATION.md § rch](../orchestration/ORCHESTRATION.md).
