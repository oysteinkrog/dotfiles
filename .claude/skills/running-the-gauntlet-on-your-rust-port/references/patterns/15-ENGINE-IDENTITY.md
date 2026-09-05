# Pattern 15 — ENGINE IDENTITY (`Subject::<port>` vs `Oracle::<reference>` discriminator)

## What

Two `const` strings — `SUBJECT_IDENTITY_LABEL` and `REFERENCE_IDENTITY_LABEL` — embedded in every artifact, every executor, every report, and asserted distinct at the comparator. The discriminator is the operationalization of [K-9](../methodology/KERNEL.md#k-9): *never compare an oracle against itself*. A pre-flight assertion at oracle harness entry refuses to run if either label is missing or if they match each other.

## Why

> "Defense against the failure mode 'you accidentally wired the oracle's executor to both sides and got 100% pass' is enforced *in the harness*, not in the reviewer." — [methodology/KERNEL.md § K-9](../methodology/KERNEL.md#k-9)

The failure mode is real and embarrassing. A refactor renames `rusqlite::Connection` and the test author's IDE auto-completes to `fsqlite::Connection` on both sides; tests now pass at 100% because the engine is compared against itself. Without the K-9 guard, the agent ships a release citing "100% parity" that means nothing.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/differential_v2.rs` — `EngineVersions` struct with `subject_identity: String` and `reference_identity: String` fields (MINING-2 §2).
- `crates/fsqlite-harness/src/oracle_preflight_doctor.rs` — asserts both labels present and distinct before any test runs (MINING-2 §13).
- All harness binaries declare the two consts at module top.

## Verbatim shape

From MINING-2 §3, verbatim:

```rust
const SUBJECT_IDENTITY_LABEL: &str = "frankensqlite";
const REFERENCE_IDENTITY_LABEL: &str = "csqlite-oracle";
```

The matching field block in `ExecutionEnvelope.engines: EngineVersions`:

```rust
pub struct EngineVersions {
    pub fsqlite: String,
    pub csqlite: String,
    pub subject_identity: String,    // must be "frankensqlite" in parity mode
    pub reference_identity: String,  // must be "csqlite-oracle" in parity mode
}
```

The pre-flight assertion (canonical form):

```rust
fn assert_engine_identity(env: &ExecutionEnvelope) -> Result<()> {
    let s = &env.engines.subject_identity;
    let r = &env.engines.reference_identity;
    if s.is_empty() || r.is_empty() {
        bail!("EngineIdentity unset: subject={s:?} reference={r:?}");
    }
    if s == r {
        bail!("EngineIdentity collision: oracle being compared against itself ({s})");
    }
    if s != SUBJECT_IDENTITY_LABEL {
        bail!("Subject identity {s:?} != expected {SUBJECT_IDENTITY_LABEL:?}");
    }
    if r != REFERENCE_IDENTITY_LABEL {
        bail!("Reference identity {r:?} != expected {REFERENCE_IDENTITY_LABEL:?}");
    }
    Ok(())
}
```

## Per-class instantiation

| Class | `SUBJECT_IDENTITY_LABEL` | `REFERENCE_IDENTITY_LABEL` |
|---|---|---|
| SQL (FrankenSQLite) | `"frankensqlite"` | `"csqlite-oracle"` |
| SQL (sqlmodel_rust) | `"sqlmodel_rust"` | `"sqlmodel-python-oracle"` |
| RESP (FrankenRedis) | `"frankenredis"` | `"redis-server-oracle"` |
| Numerical (franken_numpy) | `"franken_numpy"` | `"numpy-pyo3-oracle"` |
| Numerical (frankenpandas) | `"frankenpandas"` | `"pandas-pyo3-oracle"` |
| Numerical (frankenscipy) | `"frankenscipy"` | `"scipy-pyo3-oracle"` |
| Numerical (franken_networkx) | `"franken_networkx"` | `"networkx-pyo3-oracle"` |
| ML (frankentorch) | `"frankentorch"` | `"torch-pyo3-oracle"` |
| ML (frankenjax) | `"frankenjax"` | `"jax-pyo3-oracle"` |
| HTTP (fastapi_rust) | `"fastapi_rust"` | `"fastapi-python-oracle"` |
| HTTP (fastmcp_rust) | `"fastmcp_rust"` | `"fastmcp-python-oracle"` |

The labels are sourced from `[engine_identity]` in [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md):

```toml
[engine_identity]
subject_identity_label = "frankensqlite"
reference_identity_label = "csqlite-oracle"
```

## Composition

- [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md) — the discriminator is what proves Subject ≠ Oracle in K-1's triple.
- [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) — `[engine_identity]` table sources the two const values.
- [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) — wraps the pre-flight assertion and emits green/yellow/red.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — `EngineVersions` is embedded in every envelope and hashed into the artifact id.
- [pattern:40-METAMORPHIC-TRANSFORMS](40-METAMORPHIC-TRANSFORMS.md) — *Subject = Oracle by design* in metamorphic; the K-9 guard is per-pillar, not universal. Metamorphic uses a separate `MetamorphicEnvelope` that doesn't carry the discriminator.

## Pitfalls

- **Labels not asserted, only declared.** Two consts at the top of a file are decorative. The pre-flight assertion must be called from every test binary's `main` (or `#[test]` setup hook). If it isn't called, the discriminator does nothing.
- **Labels mutated at runtime.** A test that helpfully sets `env.engines.subject_identity = ""` to "skip the check in CI" defeats the discriminator. The labels are `const`; the envelope's fields are populated from `const` references only.
- **One label, two engines.** A common mistake: both subject and reference labeled `"sqlite"` because "they're both SQLite". The K-9 violation is silent. The reference label must be distinct (`"sqlite-oracle"`, `"csqlite-oracle"`, etc.).
- **Identity check disabled "for the metamorphic suite".** Don't disable it — emit a different envelope type. Metamorphic comparisons are Subject-vs-Subject by design; they use `MetamorphicEnvelope` which has no `reference_identity` field. The presence/absence of the field carries the type-level distinction.
- **Reference label drift across test files.** Different tests using `"csqlite-oracle"` vs `"csqlite_oracle"` vs `"CSQLite-Oracle"`. The pre-flight assertion compares against `REFERENCE_IDENTITY_LABEL` exactly; a typo in one test file produces a different artifact_id and breaks the ratchet by K-11.
- **Identity assertion only in release mode.** `#[cfg(not(test))]` on the assertion means tests run without it. That's exactly the wrong direction — the assertion is most needed in tests.
