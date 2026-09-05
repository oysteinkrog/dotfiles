<!-- KERNEL_START v1.0 -->

# KERNEL — Universal Axioms of the Gauntlet

This file is the load-bearing list of axioms every other reference file presupposes. If a phase, operator, gate, or ledger entry contradicts one of these axioms, the axiom wins. Each axiom is anchored with a verbatim quote from the FrankenSQLite mining extracts and a one-paragraph operational gloss. Number the axioms K-1..K-12; downstream references cross-link by number (e.g., "by K-2"). See [../../SKILL.md](../../SKILL.md) for the One Rule that compresses the entire kernel into a single sentence.

---

## K-1 — Subject vs Oracle vs Comparator IS the engine

> "Subject/Oracle/Comparator Across 8 Quality Concerns" — MINING-2 §Summary

| Pillar | Subject | Oracle | Comparator |
|---|---|---|---|
| Behavioral oracle | `fsqlite::Connection` | `rusqlite::Connection` | string render of rows |
| Differential V2 | `FsqliteExecutor` | `CsqliteExecutor` | `NormalizedValue` after canonicalization |
| Metamorphic | Subject's answer to rewritten Q | Subject's answer to original Q | equivalence-expectation comparator |
| Insta snapshots | Current build's bytecode/plan | Last-committed `.snap` | text equality |
| Crash-boundary | Recovered state after crash at boundary B | "Some consistent prefix of committed txns" | consistency predicate |
| MVCC invariant | Live system | Mathematical invariant (INV-1..7) | e-process Ville threshold |
| Perf gate | Current build | Previous build (`.bench-history`) | ratio drop ≥ threshold |
| Conformance ratchet | Current parity score | Persisted high-water mark | lower-bound monotonicity |

Every artifact in the gauntlet decomposes into a *Subject, an Oracle, and a Comparator*. If you cannot name all three on demand for a given gate, the gate is not a gate. The Oracle is never the Subject — see K-9 (Engine-Identity guard). The Comparator is never "looks right by eye" — see K-7 (deterministic rendering).

---

## K-2 — Honesty is encoded in the harness, not in the reviewer

> "An agent honest enough to write the gate is biased toward making it pass." — MINING-2 §12 (Adversarial search threat model)

A reviewer cannot read 6,040 lines of `comprehensive_bench.rs` plus three negative ledgers plus the `.bench-history/` deltas every PR. The harness must refuse to lie: pass-over-pass gate is a *committed file*; `concurrent_mode_default_guard.txt` is a *file dropped into every artifact lane*; `truncate_score` is a *function called at the boundary*. If the discipline is "the reviewer remembers to check," the discipline is dead. See [KEEP-GATE-RULES.md](KEEP-GATE-RULES.md) and [ANTI-PATTERNS.md](ANTI-PATTERNS.md).

---

## K-3 — Negative evidence is a first-class output

> "This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass, and add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction." — CC.md lines 479–482 (verbatim, MINING-1 §3)

A rejected optimization is not a non-event; it is data that costs hours and must be banked. The three durable ledgers (`docs/progress/perf-negative-results.md`, `conformance-negative-results.md`, `surface-deferrals.md`) are committed to git, mandatorily mined before any campaign (60 days of cass + recent commits + perf artifacts), and every entry carries a load-bearing retry-condition predicate. See [RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md) for the eight verbatim predicate forms.

---

## K-4 — Both gates must move in the same run window

> "Both gates must move in the same run window" — MINING-1 §1 (verbatim)
> "Same run = same git state, same `target/`, same machine, same minute." — MINING-1 §1

The focused gate (e.g., 10K DELETE keep gate) and the broad gate (`comprehensive_bench` primary score) must both pass *from the same compile, on the same host, within the same wall-clock minute*. Improving focused while broad worsens is a rejection by [ANTI-PATTERNS.md § Focused improved, broad worsened](ANTI-PATTERNS.md). The pass-over-pass gate is a file (`.bench-history/<bench>.latest.json`) precisely so that "I forgot to commit the broad result" cannot happen silently. See [KEEP-GATE-RULES.md § same run window](KEEP-GATE-RULES.md).

---

## K-5 — `truncate_score` to 6 decimal places — cross-platform determinism

> "x86 vs ARM vs WASM differ at LSB; truncation ensures bytewise identical scores regardless of CPU." — MINING-2 §11

```rust
pub fn truncate_score(x: f64) -> f64 { /* truncate to 6 decimal places */ }
```

Every score that crosses a release boundary (parity score, per-category score, ratchet state, scorecards.json) is `truncate_score`'d. The bytewise identity is what lets the ratchet diff cleanly across machines; without it, a Mac build and a Linux build that should "agree" disagree at the LSB and the ratchet flickers. See [CONFORMAL-RATCHET.md § truncate_score](CONFORMAL-RATCHET.md) and [taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md) for the loader-enforced `sum(weights) == 1.0` rule that pairs with it.

---

## K-6 — Anytime-valid sequential testing (Bayesian + Conformal + E-process)

> "Anytime-valid: check after every operation, reject when crosses `1/α`, **no Bonferroni correction needed**." — MINING-2 §10 (Ville's inequality)

The gauntlet's three statistical layers are not interchangeable — they compose:

1. **Beta posterior per category × pass rate** — `theta_c ~ Beta(α_prior + Σ weighted_successes, β_prior + Σ weighted_failures)`. Subjective prior + observed evidence.
2. **Distribution-free conformal band** (Vovk-Gammerman-Shafer 2005) — honest under heavy-tailed/bimodal/regime-shifting workload distributions. Cost: wider. Benefit: doesn't fail catastrophically when the workload distribution doesn't match the prior.
3. **E-process (Howard-Ramdas-McAuliffe-Sekhon 2021)** — `P_{H_0}(∃t: E_t ≥ 1/α) ≤ α`. Watch every operation forever; reject the null the moment the e-value crosses `1/α`. Stops without Bonferroni.

Release decisions use the conformal **lower bound** on the Beta posterior, not the point estimate. Hardware-enforced invariants get tight calibration (`p₀=1e-9, λ=0.999, α=1e-6`); software-enforced get loose (`p₀=1e-6, λ=0.9, α=0.001`). Global e-value = arithmetic mean of per-invariant e-processes (conservative under arbitrary dependence). See [CONFORMAL-RATCHET.md](CONFORMAL-RATCHET.md).

---

## K-7 — Deterministic rendering = canonical comparison

> "String rendering uniform: `Vec<Vec<String>>` with NULL capitalized, integers base-10, floats via `Display`, text in single quotes, blob as `X'<hex>'`." — MINING-2 §1

Two engines "agreeing" requires a comparator whose output is bytewise identical for semantically equal inputs. The 30-line `scenario()` template in MINING-2 §1 establishes the bar: `NormalizedValue::normalize_value` capitalizes NULL, formats floats as `{f:.15}`, normalizes NaN/Inf/-Inf, lowercases nothing, and never trusts whitespace. The metamorphic family stack (Predicate / Projection / Structural / Literal) layers on top, but the floor is the same: every comparator emits canonical JSON-or-better.

Per-class instantiations:
- **SQL:** `Vec<Vec<String>>` per the template above.
- **RESP:** `render_resp_value()` over 14 RESP3 types.
- **Tensor:** `render_tensor_spec()` over `(shape, dtype, device, requires_grad, data_hash)` with per-op ULP tolerance.

---

## K-8 — Both-error = agreement; one-error-one-OK = hard failure

> "Both-error = agreement (message text irrelevant). One-error-one-OK = hard failure." — MINING-2 §1

A divergence is a *behavior* divergence, not a *message* divergence. If both engines raise an error on `INSERT INTO t(x) VALUES (NULL)` because `x NOT NULL`, the test passes regardless of whether one says "constraint violation: NOT NULL" and the other says "column x cannot be null". If one accepts and the other rejects, the test fails. This forbids the [ANTI-PATTERNS.md § Agreement-by-error-message](ANTI-PATTERNS.md) failure mode where two engines failing for different reasons look "agreed."

---

## K-9 — Engine-Identity discriminator — never compare an oracle against itself

> ```rust
> const SUBJECT_IDENTITY_LABEL: &str = "frankensqlite";
> const REFERENCE_IDENTITY_LABEL: &str = "csqlite-oracle";
> ```
> — MINING-2 §3

Every artifact carries `Subject::<port>` and `Oracle::<reference>` strings; the comparator asserts distinct. The oracle preflight doctor verifies these strings before any test runs. The defense against the failure mode "you accidentally wired the oracle's executor to both sides and got 100% pass" is enforced *in the harness*, not in the reviewer. See [../tooling/ORACLE-TOOLCHAIN.md § EngineIdentity](../tooling/ORACLE-TOOLCHAIN.md).

---

## K-10 — BEAD_ID + SCHEMA_VERSION in every module + every artifact

> ```rust
> pub const LOG_SCHEMA_VERSION: &str = "1.0.0";
> pub const REQUIRED_EVENT_FIELDS: &[&str] = &[
>     "run_id",      // {bead_id}-{timestamp}-{pid}
>     "timestamp",   // ISO 8601 UTC
>     "phase",       // setup | execute | validate | teardown
>     "event_type",
> ];
> ```
> — MINING-2 §16

Every harness module declares the bead it serves (`bd-1dp9.1.2`, `bd-3go.3`, `bd-mblr.4.4`, etc.) and the schema version of its emitted artifact (`fsqlite-e2e.comprehensive-bench-report.v3`, `LOG_SCHEMA_VERSION = "1.0.0"`, `failure_bundle.v1.0.0`, `strict-conformant-release.v1`). When a schema changes, the version bumps; downstream readers either upgrade or fail loudly. The "logs as API" discipline (MINING-2 §16) generalizes: artifacts are machine inputs to future agents, not chat output for humans.

---

## K-11 — Content-addressed artifact identity — `run_id` is provenance, not identity

> "Invariant: `artifact_id = SHA-256 of canonical JSON excluding run_id`. Two runs with identical semantic inputs produce the same artifact ID even with different `run_id` (timestamp/PID)." — MINING-2 §2

The Differential V2 envelope's `artifact_id()` hashes the canonical JSON of the envelope *with `run_id` stripped*. This separates "what was the test?" (artifact id) from "when/where did we run it?" (run id). Two distinct runs that test the same thing produce the same artifact id; this is what makes the ledger queryable, the regression detector stable, and the ratchet bytewise reproducible. See [IDENTITY-AND-REPRODUCIBILITY.md § content-addressed artifact ID](IDENTITY-AND-REPRODUCIBILITY.md).

---

## K-12 — Convergence is a CI gate, not an editorial verdict

> "≥10 full iterations of Phases 5→10. Two consecutive clean rounds each producing <3 *new genuine* findings (computed by `scripts/convergence-tracker.sh` across the three ledgers + every per-bucket findings file). Every open hypothesis resolved." — [../../SKILL.md § Convergence Rule](../../SKILL.md)

Convergence is computed mechanically: round-over-round new-finding counts, deduplicated by MismatchSignature, exit-non-zero from `convergence-tracker.sh` until all three conditions hold. An agent does not "feel" converged; a script declares it. The script is the same script in CI and on the agent's workstation, so the answer is identical. See [CONVERGENCE.md](CONVERGENCE.md).

---

## Compositional Invariants (how the axioms chain)

- **K-1 + K-9** ⇒ A comparator that cannot name distinct Subject and Oracle identity strings is invalid.
- **K-2 + K-4** ⇒ The pass-over-pass gate must be a committed file checked by CI, not a manual rerun.
- **K-3 + K-12** ⇒ Convergence cannot be declared while open hypotheses or unretired ledger entries exist.
- **K-5 + K-6 + K-11** ⇒ Cross-machine ratchet diff = `truncate_score(conformal_lower_bound(...))` over canonical-JSON-hashed artifacts.
- **K-7 + K-8** ⇒ The 30-line `scenario()` template is the floor; canonical rendering + both-error-agreement is the API.
- **K-10 + K-11** ⇒ Every artifact is content-addressable AND version-stamped; a future agent can replay exactly.

When two axioms conflict in a specific case, defer to K-2 (honesty in the harness) and design a new gate.

<!-- KERNEL_END v1.0 -->
