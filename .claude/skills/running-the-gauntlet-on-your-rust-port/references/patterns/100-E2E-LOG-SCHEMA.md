# Pattern 100 — E2E Log Schema (Logs as API)

## What

Every event emitted by every harness module conforms to a single versioned schema with a fixed set of required fields and a fixed set of replayability keys. Logs are not free text for humans; they are machine-consumable trace records that future agents parse to compute coverage, dedupe failures, and bisect regressions. A log line missing any required field fails `log_schema_validator` and the run is aborted before any artifact is published.

## Why

> "If these keys present, future agent drops into exact failure point. If missing, log fails `log_schema_validator`. **Logs as API:** Not free text for humans; machine-consumable trace future agents parse to compute coverage and bisect regressions." — MINING-2 §16

Failure mode prevented: "ad-hoc `println!` traces" where humans read logs while debugging but no script can dedupe failures across runs, attribute regressions to a phase, or replay a divergence from a CI artifact alone. Without a versioned schema, every consumer rewrites the same fragile regex; with one, every consumer queries by field.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/e2e_log_schema.rs` (bd-1dp9.7.2)
- Consumed by: `failure_bundle.rs`, `first_failure_explainer.rs`, `replay_harness.rs`, `score_engine.rs`, every `*_oracle_e2e.rs` test under `crates/fsqlite-e2e/tests/`.

## Verbatim shape

```rust
pub const LOG_SCHEMA_VERSION: &str = "1.0.0";

pub const REQUIRED_EVENT_FIELDS: &[&str] = &[
    "run_id",      // {bead_id}-{timestamp}-{pid}
    "timestamp",   // ISO 8601 UTC
    "phase",       // setup | execute | validate | teardown
    "event_type",
];

pub const REPLAYABILITY_KEYS: &[&str] = &[
    "scenario_id",
    "seed",
    "phase",
    "context.invariant_ids",
    "context.artifact_paths",
];
```

`run_id` composition is itself a contract: `{bead_id}-{timestamp}-{pid}`. The bead_id makes every artifact attributable to a tracked piece of work; the timestamp lets the regression detector order them; the pid disambiguates within the same wall-clock second on parallel runners.

## Per-class instantiation

| Class | `event_type` enumeration |
|---|---|
| SQL | `oracle.scenario_start`, `oracle.scenario_end`, `oracle.mismatch`, `oracle.both_error_agreement`, `vfs.fault_armed`, `vfs.fault_triggered`, `wal.crash_boundary_hit`, `wal.recovery_complete`, `mvcc.invariant_check`, `mvcc.invariant_violation`, `bench.warmup_iter`, `bench.measured_iter`, `bench.teardown`, `surface.feature_evaluated`, `differential.envelope_emitted` |
| RESP | `oracle.command_dispatch`, `oracle.resp_frame_compared`, `oracle.pubsub_ordering_check`, `aof.fault_triggered`, `rdb.crash_boundary_hit`, `replication.offset_advanced`, `bench.client_pool_seeded`, `bench.measured_iter` |
| Numerical-Python | `oracle.ufunc_dispatch`, `oracle.ulp_compared`, `oracle.shape_mismatch`, `oracle.dtype_promotion_diverged`, `rng.seed_captured`, `bench.measured_iter` |
| ML-System | `oracle.aten_dispatch`, `oracle.autograd_grad_compared`, `oracle.gradcheck_max_rel_error`, `nccl.collective_armed`, `nccl.collective_triggered`, `checkpoint.crash_boundary_hit`, `bench.measured_iter` |
| HTTP-Protocol | `oracle.request_replayed`, `oracle.response_normalized`, `oracle.header_case_compared`, `oracle.openapi_schema_diff`, `middleware.fault_triggered`, `bench.measured_iter` |

Every class shares the same `REQUIRED_EVENT_FIELDS` and `REPLAYABILITY_KEYS`. The `event_type` set is per-class but the *envelope* is universal.

`phase` is the same four-valued enum everywhere: `setup | execute | validate | teardown`. The validator rejects any other value; a class adding a fifth phase must bump `LOG_SCHEMA_VERSION` and update the validator in lockstep.

## Composition

- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — every `FailureBundle` embeds the originating `run_id` + `scenario_id` + `seed` so the bundle is reconstructible from a log replay.
- [pattern:95-FIRST-FAILURE-EXPLAINER](95-FIRST-FAILURE-EXPLAINER.md) — consumes `context.artifact_paths` to dereference the `/failure/first_divergence` jsonptr.
- [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) — defines the full identity tuple `(run_id, trace_id, scenario_id, seed, commit_sha, ...)` that subsumes `REPLAYABILITY_KEYS`.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — `run_id` appears in the envelope but is excluded from the content-addressed `artifact_id` (K-11); the log schema's `run_id` is therefore provenance, not identity.
- [pattern:110-INVARIANT-CATALOG](110-INVARIANT-CATALOG.md) — `context.invariant_ids` cross-references the catalog so every event names which invariants its phase is gated on.

## Pitfalls

- **Logging "structured" with `serde_json::json!({...})` but never wiring `log_schema_validator`** — the schema becomes a hint, not a gate. CI must reject any artifact whose first event fails validation.
- **Re-using `run_id` across reruns** — defeats `{bead_id}-{timestamp}-{pid}`. Always rebuild from scratch; never read it from an environment variable.
- **Pushing `phase = "init"` or `phase = "shutdown"`** — only the four canonical values are legal. New phases require a schema-version bump.
- **Logging human-readable summaries in `event_type`** — `event_type` is an enum, not a sentence. `"finished test"` is wrong; `"oracle.scenario_end"` is right.
- **Dropping `seed` because "this scenario is deterministic"** — REPLAYABILITY_KEYS are unconditional. If a scenario is deterministic, log `seed = 0` explicitly; never omit.
- **Aggregating events at end-of-run instead of streaming** — a crashed run loses everything. Stream-flush per event so a SIGKILL leaves a partial-but-valid log.
- **Versioning the schema in the README instead of in source** — `LOG_SCHEMA_VERSION` must be a `pub const` so consumers can branch on it at compile time and the validator can refuse mismatched producers.
