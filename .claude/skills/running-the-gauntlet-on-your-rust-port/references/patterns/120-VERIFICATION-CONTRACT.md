# Pattern 120 — Verification Contract

## What

A bead may not close on a "test passes" signal alone. Closure requires *both* the base gate (CI green, focused + broad benches in same window, lints clean) *and* a verification contract that the bead's claimed evidence (`pass | fail-missing-evidence | fail-invalid-references | fail-mixed`) is actually present and resolves. The product is a 4×4 matrix of close-decisions; only the `(pass, allowed)` cell closes the bead. Every other cell maps to a specific blocker reason so the agent knows what to do next.

## Why

> "A bead cannot close with weak evidence (`pass | fail-missing-evidence | fail-invalid-references | fail-mixed` × `allowed | blocked-by-base-gate | blocked-by-contract | blocked-by-both`)." — Polish Bar row, SKILL.md

Failure mode prevented: the well-known "the tests pass, I'm done" close where the bead claimed to add `OracleDifferential` proof for a Feature but never actually wrote the artifact, or wrote it but didn't update the `ArtifactRef` hash, or updated the hash but the artifact's schema_version is stale. A bead that closes with weak evidence rots the InvariantCatalog: future runs see "Met" status backed by missing files.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/verification_contract.rs` — the matrix evaluator + the bead-close gate.
- `crates/fsqlite-harness/src/parity_invariant_catalog.rs::validate()` — produces the contract status (`pass | fail-...`).
- `.github/workflows/verification-gates.yml` — CI wiring; the gate is mechanical, not editorial.
- Bead-close webhook (in `bv`/`br`) consults this contract and refuses to flip the bead's status if the matrix returns anything but `(pass, allowed)`.

## Verbatim shape

### Contract status (column dimension)

| Status | Meaning |
|---|---|
| `pass` | All `ProofObligation`s for this bead's claimed features have `status = Met`, all `ArtifactRef`s resolve and hash-match, all `schema_version`s current. |
| `fail-missing-evidence` | One or more `ProofObligation`s are declared but the artifact at `path` does not exist. |
| `fail-invalid-references` | Artifact exists but hash mismatch OR schema_version mismatch OR per-ProofKind acceptance predicate fails. |
| `fail-mixed` | Both `fail-missing-evidence` and `fail-invalid-references` populate for different obligations under the same bead. |

### Base gate status (row dimension)

| Status | Meaning |
|---|---|
| `allowed` | CI is green; focused + broad benches landed in same run window (K-4); `.bench-history` updated; lints + tests + miri (where applicable) clean. |
| `blocked-by-base-gate` | CI red, or pass-over-pass gate failed, or `cv_pct > 5`, or required perf snapshot missing. |
| `blocked-by-contract` | Base gate green but verification contract returned non-pass. |
| `blocked-by-both` | Both red. |

### The matrix

| status \ gate | allowed | blocked-by-base-gate | blocked-by-contract | blocked-by-both |
|---|---|---|---|---|
| `pass` | **CLOSE** | block: base-gate | (impossible: gate column inconsistent with row) | block: base-gate |
| `fail-missing-evidence` | block: contract (missing evidence; list paths) | block: both | block: contract (list paths) | block: both |
| `fail-invalid-references` | block: contract (list hash/schema mismatches) | block: both | block: contract | block: both |
| `fail-mixed` | block: contract (list both classes) | block: both | block: contract | block: both |

Only the top-left cell closes. Every other cell carries a *specific* reason string so the agent's next step is obvious.

## Per-class instantiation

| Class | What "claimed evidence" usually consists of |
|---|---|
| SQL | One or more of: oracle E2E test artifact, Differential V2 envelope, metamorphic suite output, fault-VFS recovery proof, e-process trace summary, fuzz no-panic certificate, insta snapshot. |
| RESP | Oracle E2E vs vendored `redis-server`, RESP-parser closure-wave evaluation, RDB/AOF round-trip golden, replication-offset e-process summary. |
| Numerical-Python | NumPy oracle parity packet, RNG bit-exact stream certificate, ULP-tolerance table compliance summary. |
| ML-System | PyTorch / JAX oracle packet, gradcheck `max_rel_error` snapshot, NCCL collective parity record, deterministic-algorithms compliance certificate. |
| HTTP-Protocol | Reference-framework parity transcript, OpenAPI schema diff (must be empty modulo declared exclusions), validation-error schema golden. |

Per-class adapters live in `crates/{c}-harness/src/verification_contract_adapter.rs` and translate per-ProofKind acceptance predicates to the class's evidence shapes.

## Composition

- [pattern:105-FEATURE-UNIVERSE](105-FEATURE-UNIVERSE.md) — the bead's claimed features must exist in the universe; closing a bead that claims a feature not yet enrolled is `fail-invalid-references` (the FeatureId resolves to nothing).
- [pattern:110-INVARIANT-CATALOG](110-INVARIANT-CATALOG.md) — `validate()` from the catalog is the engine that returns the contract status column.
- [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — the base-gate row consults the pass-over-pass file gate (K-4); a perf bead with `cv_pct > 5` is `blocked-by-base-gate` regardless of evidence.
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — for perf beads, the base gate also requires `.bench-history/<bench>.latest.json` updated in the same commit.
- [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) — a `fail-*` close cannot be "fixed" by writing a ledger entry; ledger entries are for *rejected* candidates, not for *deferred* evidence. Deferred evidence reopens the bead.
- See [methodology/KERNEL.md § K-2](../methodology/KERNEL.md) (honesty in the harness) and [methodology/KERNEL.md § K-12](../methodology/KERNEL.md) (convergence is a CI gate).

## Pitfalls

- **"It's a documentation bead; verification doesn't apply"** — documentation beads still must declare which Feature(s) they document and which artifact (the doc itself) is the evidence. The contract applies; the `ProofKind` may be `InstaSnapshot` over the rendered markdown.
- **Manually flipping a bead from "Open" to "Closed" in `br`** — bypasses the gate; future audits catch it via the bead-graph validator. The webhook is the only path.
- **Mutating an artifact in-place to make a hash match** — `fail-invalid-references` resolved by editing the *catalog* to point at the new hash, not by editing the artifact to match the old. The catalog tracks truth; the artifact is the evidence.
- **Letting a stale `schema_version` slide** — schema bumps are deliberate; an artifact written under v2 that the validator reads under v3 must be re-emitted under v3, not the validator relaxed.
- **Closing as "pass" with `Excluded` features in the claimed-improved set** — `Excluded` features have no obligations; claiming improvement on them is `fail-invalid-references`.
- **Treating `blocked-by-contract` as a recommendation** — the gate is mechanical; CI refuses the close. Override requires a documented `Waiver` in the ratchet (see [pattern:170-ROBUST-REGRESSION-DETECTOR](170-ROBUST-REGRESSION-DETECTOR.md)) with severity bounds and an expiry date.
- **Re-using one bead for many features so the contract has to validate dozens of obligations** — design bead granularity so each bead touches a small obligation set. If the validator's output is too noisy to act on, the bead is too big.
