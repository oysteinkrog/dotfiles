# Pattern 90 — FAILURE BUNDLE (`v1.0.0` with `/failure/first_divergence` jsonptr)

## What

A `FailureBundle v1.0.0` struct emitted on every E2E failure carrying everything needed to reproduce: seed, fixture id, schedule fingerprint, list of artifact SHA-256s, db page previews, WAL state at failure, expected-vs-actual string, the JSONPointer `/failure/first_divergence` that jumps to the byte-offset of disagreement (not "test X failed somewhere"), and full environment fingerprint (git SHA, toolchain version, platform, feature flags). The `FailureType` enum classifies into ten orthogonal categories. The cardinal rule: **a partial bundle with provenance is more valuable than no bundle. Never skip manifest writing on failure.**

## Why

> "Critical: 'A partial bundle with provenance is more valuable than no bundle. Never skip manifest writing on failure.'" — MINING-2 §15

A test that prints "FAILED" to stdout and exits is a test that loses the failure forever — the heap is gone, the WAL state is gone, the seed is gone, and the next attempt to reproduce on a different machine starts from scratch. The bundle is the failure's permanent record; the `/failure/first_divergence` pointer makes it actionable in the time it takes to open the bundle in a viewer.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/failure_bundle.rs` (bead `bd-mblr.4.4`) — the `FailureBundle` + `FailureType` (MINING-2 §15)
- Bundles persisted to `<workspace>/failures/<run_id>/<failure_id>.bundle.json` + sibling binary artifacts
- Schema version: `failure_bundle.v1.0.0` (per K-10)

## Verbatim shape — the struct + enum

From MINING-2 §15, verbatim:

```rust
pub enum FailureType {
    Assertion, Panic, Divergence, Timeout,
    SsiConflict, MvccInvariant, WalRecovery, FileFormat,
    Extension, Other,
}

pub struct FailureBundle {
    pub failure_type: FailureType,
    pub seed: u64,
    pub fixture_id: String,
    pub schedule_fingerprint: String,
    pub artifact_sha256: Vec<String>,
    pub db_page_previews: Vec<u8>,
    pub wal_state_at_failure: Option<String>,
    pub expected_vs_actual: String,
    pub first_divergence_jsonptr: String,   // /failure/first_divergence
    pub git_sha: String,
    pub toolchain_version: String,
    pub platform: String,
    pub feature_flags: Vec<String>,
}
```

### `/failure/first_divergence` JSONPointer discipline (verbatim MINING-2 §15)

> "**First-divergence rule:** The pointer at `/failure/first_divergence` jumps to byte-offset where engines first disagreed, not to 'test X failed somewhere'."

JSONPointer RFC 6901: the path within the bundle JSON that, when dereferenced, yields the exact disagreement. Examples:

- For a behavioral divergence: `/failure/first_divergence` → `{ "byte_offset": 4096, "subject_byte": "0x42", "oracle_byte": "0x43" }`
- For a row-count mismatch: `/failure/first_divergence` → `{ "row_index": 17, "subject_row": [...], "oracle_row": [...] }`
- For a WAL recovery failure: `/failure/first_divergence` → `{ "wal_frame_offset": 8192, "expected_next_frame_sequence": 17, "actual_next_frame_sequence": 15 }`

A bundle whose `first_divergence_jsonptr` is `""` or `/failure/test_failed` violates the rule — the consumer cannot programmatically jump to the disagreement.

### "Partial bundle with provenance" rule (verbatim)

> "A partial bundle with provenance is more valuable than no bundle. Never skip manifest writing on failure."

If the failure is so catastrophic that `db_page_previews` can't be captured (e.g., the DB file was unlinked), still write the bundle with `db_page_previews: Vec::new()` and `wal_state_at_failure: None`. The `seed + git_sha + toolchain_version + platform + feature_flags + fixture_id` alone is enough to reproduce on a clean checkout.

## `FailureType` per class

### SQL-class (FrankenSQLite) — verbatim 10 variants

| Variant | Meaning |
|---|---|
| `Assertion` | Rust `assert!` or `assert_eq!` failure |
| `Panic` | Panic during test (uncaught) |
| `Divergence` | Subject ≠ Oracle for the same input |
| `Timeout` | Test exceeded wall-clock budget |
| `SsiConflict` | Snapshot-isolation conflict (false positive or true) |
| `MvccInvariant` | One of INV-1..INV-7 violated |
| `WalRecovery` | Post-crash recovery to inconsistent state |
| `FileFormat` | Persisted file not parseable by oracle |
| `Extension` | SQLite extension boundary failure |
| `Other` | Catchall |

### RESP-class adaptation

| Variant | Meaning |
|---|---|
| `Assertion` / `Panic` / `Other` | Same |
| `Divergence` | Same |
| `Timeout` | Same |
| `ProtocolViolation` | Subject emitted non-RESP3 bytes / oracle parser failed |
| `PersistenceFailure` | AOF/RDB roundtrip failure |
| `ReplicationDrift` | Replica diverged from primary |
| `ClusterSlotFailure` | Slot ownership inconsistency |
| `PubSubOrderViolation` | FIFO violation |

### ML-class adaptation

| Variant | Meaning |
|---|---|
| `Assertion` / `Panic` / `Other` | Same |
| `Divergence` | Same (tensor inequality beyond ULP) |
| `Timeout` | Same |
| `NumericalInstability` | NaN/Inf produced where reference produced finite |
| `GradientDivergence` | Reverse-mode ≠ forward-mode JVP beyond tolerance |
| `NondeterminismLeak` | `nondeterministic_op_count > 0` with deterministic flag set |
| `DistributedDeadlock` | All-reduce hangs |
| `CheckpointFailure` | Save/load round-trip mismatch |

## Composition

- [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) — preflight red emits a bundle.
- [pattern:45-MISMATCH-MINIMIZER](45-MISMATCH-MINIMIZER.md) — `expected_vs_actual` is the minimized form of the divergence.
- [pattern:60-FAULT-VFS](60-FAULT-VFS.md) — `wal_state_at_failure` + injected `FaultTriggerRecord`s are embedded for reproducibility.
- [pattern:65-CRASH-BOUNDARIES](65-CRASH-BOUNDARIES.md) — `FailureType::WalRecovery` carries the `CrashBoundary` discriminant in the bundle.
- [pattern:85-ADVERSARIAL-SEARCH](85-ADVERSARIAL-SEARCH.md) — every adversarial counterexample emits a bundle.
- [pattern:95-FIRST-FAILURE-EXPLAINER](95-FIRST-FAILURE-EXPLAINER.md) — consumes `first_divergence_jsonptr` to produce the CI summary's first line.
- [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) — `run_id` provenance keys the bundle into its run.

## Pitfalls

- **Bundle written on success too.** That's logging, not failure bundling. Only emit on failure; on success, the per-run summary suffices.
- **`first_divergence_jsonptr` set to `""` or `/`.** Equivalent to "the failure is somewhere in this bundle, good luck". The JSONPointer must dereference to the exact disagreement.
- **`expected_vs_actual` as a free-text string.** Better is a structured shape: `{ "expected": <canonical>, "actual": <canonical> }`. The pointer can then drill into either side.
- **`db_page_previews` storing the full DB.** That's an artifact, not a preview. Cap previews at e.g. 64KB; full artifacts go into `<workspace>/artifacts/` with SHAs referenced from `artifact_sha256`.
- **No `git_sha` because "the test is local".** Local tests fail too; reproducing them on a different machine the next day requires the git SHA.
- **Bundle written to /tmp.** Lost on next reboot. Persist to `<workspace>/failures/` which is `git init`-ed in the gauntlet workspace.
- **`schedule_fingerprint` left empty for single-threaded tests.** Even single-threaded tests have an event schedule (the order of statement execution); fill it. For loom/shuttle multi-threaded tests, `schedule_fingerprint` is the LabRuntime schedule hash.
- **Schema version not bumped on field addition.** Adding `failure_subtype: Option<String>` to v1.0.0 silently is a K-10 violation; bump to v1.1.0 and document migration.
- **Bundle JSON not validated against the schema.** A bundle that's missing a required field doesn't help the consumer. Validate at write-time, not read-time.
- **Treating "partial bundle" as a license to write nothing.** "Partial > none" is a license to write *more* even when capture is incomplete, not a license to write less when capture is complete.
- **No `bead_id` link.** A failure that doesn't link to its triage bead orphans the investigation. Add a `bead_id: Option<BeadId>` field (post-triage) and update the bundle in-place when triaged.
