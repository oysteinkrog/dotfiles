# Pattern 05 — SUBJECT / ORACLE / COMPARATOR

## What

The atomic decomposition of every gate in the gauntlet into a *Subject* (the thing being tested), an *Oracle* (the thing it's compared against), and a *Comparator* (the function that decides equal/not-equal). 8 quality concerns instantiate the triple — behavioral oracle, differential V2, metamorphic, insta snapshots, crash-boundary, MVCC invariant, perf gate, conformance ratchet — all from the same template. This is the operationalization of [K-1](../methodology/KERNEL.md#k-1).

## Why

> "An agent honest enough to write the gate is biased toward making it pass." — MINING-2 §12

A gate with no Comparator is a gate that returns true whenever the author wants it to. A gate with no Oracle is a gate that compares the Subject to itself (the K-9 anti-pattern). The triple forces the author to *name* the three components separately, which is enough friction to surface most of the silent-pass failure modes catalogued in [pattern:00-KERNEL-AXIOMS](00-KERNEL-AXIOMS.md).

## Where in FrankenSQLite

- `crates/fsqlite-e2e/tests/null_semantics_oracle_e2e.rs` (the 30-line `scenario()` template, MINING-2 §1)
- `crates/fsqlite-harness/src/differential_v2.rs` (the `ExecutionEnvelope` with `EngineVersions { subject_identity, reference_identity }`, MINING-2 §2)
- `crates/fsqlite-harness/src/metamorphic.rs` (TransformFamily + EquivalenceExpectation, MINING-2 §4)
- `crates/fsqlite-harness/src/eprocess.rs` (live system vs INV-1..7 invariants, MINING-2 §10)
- `.bench-history/mt-mvcc-bench.latest.json` (current build vs persisted baseline, MINING-3 §4)

## Verbatim shape — the 8-pillar table

From MINING-2 §Summary, verbatim:

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

The triple is *the* engine. Every other pattern in the library is an elaboration of one row.

## Per-class instantiation

### SQL-class (FrankenSQLite, sqlmodel_rust)

| Pillar | Subject | Oracle | Comparator |
|---|---|---|---|
| Behavioral | `fsqlite::Connection` | `rusqlite::Connection` (libsqlite3-sys pinned) | `Vec<Vec<String>>` via [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md) |
| Differential V2 | `FsqliteExecutor` | `CsqliteExecutor` | `artifact_id` SHA-256 of canonical JSON, see [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) |
| Metamorphic | Rewritten Q result | Original Q result | `EquivalenceExpectation::{ExactRowMatch, MultisetEquivalence, SetEquivalence, TypeCoercionEquivalent}` |
| Crash-boundary | Recovered DB after crash at one of 8 WAL boundaries | "consistent prefix of committed txns" | recovery consistency predicate, see [pattern:65-CRASH-BOUNDARIES](65-CRASH-BOUNDARIES.md) |
| MVCC invariant | Live `fsqlite::Connection` under MT8 load | INV-1..INV-7 (Monotonicity, LockExclusivity, …) | e-process Ville threshold `E_t ≥ 1/α`, see [pattern:70-E-PROCESSES](70-E-PROCESSES.md) |

### RESP-class (FrankenRedis)

| Pillar | Subject | Oracle | Comparator |
|---|---|---|---|
| Behavioral | `frankenredis::Connection` | vendored `redis-server` 7.2.5 via UNIX socket | `RespValue` over 14 RESP3 types |
| Crash-boundary | Recovered RDB+AOF after one of 6+ persistence boundaries | "consistent prefix of acknowledged commands" | persistence-recovery predicate |
| MVCC invariant | Live cluster under client storm | "RESP frames well-formed", "PUBSUB ordering FIFO per subscriber", "DEL idempotent within transaction" | e-process |

### Numerical-class (franken_numpy, frankenpandas, frankenscipy)

| Pillar | Subject | Oracle | Comparator |
|---|---|---|---|
| Behavioral | `franken_numpy::ndarray` | PyO3 in-process NumPy 1.26 | `TensorSpec { shape, dtype, device, requires_grad, data_hash }` |
| Differential V2 | Subject's RNG-seeded operation | NumPy's PCG64DXSM-bit-exact same call | per-op ULP tolerance + dtype-cast policy |

### ML-class (frankentorch, frankenjax)

| Pillar | Subject | Oracle | Comparator |
|---|---|---|---|
| Behavioral | `frankentorch::Tensor` | PyO3 PyTorch with `torch.use_deterministic_algorithms(True)` | TensorSpec + per-op ULP table (4 ULP f32 matmul, 2 ULP elementwise default) |
| MVCC invariant analogue | Live autograd graph | "softmax outputs sum to 1.0 within ε", "autograd gradient matches forward-mode JVP within ε" | e-process |

### HTTP-Protocol-class (fastapi_rust, fastmcp_rust)

| Pillar | Subject | Oracle | Comparator |
|---|---|---|---|
| Behavioral | Subject's HTTP handler | reference FastAPI/MCP server with deterministic clock + RNG | normalized HTTP response (status + headers case-insensitive + body MIME-aware) + OpenAPI schema diff |
| Crash-boundary | Recovered request lifecycle after one of 5 phases (open/header/body-start/body-end/close + cancellation) | "no partial write to downstream resource" | request-lifecycle consistency predicate |

## Composition

- [pattern:15-ENGINE-IDENTITY](15-ENGINE-IDENTITY.md) — the discriminator that proves Subject ≠ Oracle.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — Subject/Oracle/Comparator wrapped in a content-addressed envelope.
- [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md) — the Comparator's canonical-string rendering.
- [pattern:40-METAMORPHIC-TRANSFORMS](40-METAMORPHIC-TRANSFORMS.md) — Subject's-answer-to-rewritten-Q vs Subject's-answer-to-original-Q (Subject = Subject!).
- [pattern:50-THREE-TIER-EQUIVALENCE](50-THREE-TIER-EQUIVALENCE.md) — three Comparator strictnesses (raw byte / canonical / logical).
- [pattern:70-E-PROCESSES](70-E-PROCESSES.md) — the MVCC-invariant Comparator (Ville threshold).
- [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) — the conformance-ratchet Comparator (lower-bound monotonicity).
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — the perf-gate Oracle (persisted `.bench-history/`).

## Pitfalls

- **"The comparator is just `==`."** That's fine for primitives but lies for everything else. Float equality, set equality without sort, error-message text equality, hash-map iteration-order equality — every one a silent-pass machine. Use the canonical string rendering from [pattern:35-NORMALIZED-VALUE](35-NORMALIZED-VALUE.md).
- **Subject and Oracle share state.** Common when both are `Connection`s opened over the same `:memory:` URL or the same temp directory. They must be byte-isolated; see [pattern:15-ENGINE-IDENTITY](15-ENGINE-IDENTITY.md) for the discriminator that catches this.
- **Forgetting that metamorphic Subject == Oracle.** In the metamorphic row, both Subject and Oracle are the *same engine*, evaluating two related queries. The Comparator is the equivalence expectation between Q and T(Q). This is by design; see [pattern:40-METAMORPHIC-TRANSFORMS](40-METAMORPHIC-TRANSFORMS.md).
- **Perf-gate Oracle = "what I remember it being last week".** No. The Oracle is the committed file `.bench-history/<bench>.latest.json`. If it's not in `git log -p .bench-history/`, it doesn't exist.
- **Conformance-ratchet Comparator is "score >= last score".** Almost. It's `truncate_score(lower_bound) >= truncate_score(previous_lower_bound)` per [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md). The lower bound is the conformal band's lower edge, not the point estimate.
- **Writing a "comparator" that prints a diff and returns `true`.** This is the most common subtle failure. The comparator must *return* the result; printing is for the human. If a CI script reads stdout to decide pass/fail, that's a fragile gate by K-2.
