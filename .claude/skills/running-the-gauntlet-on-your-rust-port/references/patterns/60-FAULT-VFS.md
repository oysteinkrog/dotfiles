# Pattern 60 — FAULT VFS (declarative `FaultSpec` with stable seeds, F-1..F-8 adoption checklist)

## What

A `FaultInjectingVfs` layer wrapping the real VFS, driven by declarative `FaultSpec` rules: file glob, `FaultKind` (TornWrite / PartialWrite / PowerCut / IoError / ReadFailure / WriteFailure / Latency / DiskFull), trigger position (`at_offset` / `after_nth_sync` / `after_count`), and `max_triggers`. Faults fire deterministically from a `DEFAULT_FAULT_SEED` so the same `FaultSpec` produces byte-identical fault behavior every run. The F-1..F-8 checklist is the adoption gate: enum + spec + wiring + named profiles + invariants + metric + record + dashboard.

## Why

Crash testing without determinism is theatre — the bug reproduces once, then never again. The `DEFAULT_FAULT_SEED` constant means *the same torn-write at WAL offset 8192 with `valid_bytes=17` produces exactly 17 bytes every run*. That turns a flaky "we saw it once" into a regression test you can put in CI.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/fault_vfs.rs` (bead `bd-3go.2`, 57 KB) — the VFS + `FaultKind` + `FaultSpec` (MINING-2 §8)
- `DEFAULT_FAULT_SEED = 0xD1A6_A3F4_9B17_0C5E`
- Named profiles in `crates/fsqlite-harness/src/fault_profiles/` (e.g., `torn-wal-frame`, `partial-checkpoint`)

## Verbatim shape — the types

### `FaultKind`

From MINING-2 §8, verbatim:

```rust
pub enum FaultKind {
    TornWrite     { valid_bytes: usize },
    PartialWrite  { valid_bytes: usize },
    PowerCut,
    IoError,
    ReadFailure,
    WriteFailure,
    Latency       { base_millis: u64, jitter_millis: u64 },
    DiskFull,
}
```

### `FaultSpec`

```rust
pub struct FaultSpec {
    pub file_glob: String,
    pub kind: FaultKind,
    pub at_offset: Option<u64>,
    pub after_nth_sync: Option<u32>,
    after_count: Option<u64>,
    max_triggers: u32,
    trigger_count: u32,
    match_count: u64,
}
```

### Usage idiom

```rust
let mut vfs = FaultInjectingVfs::new(MemoryVfs::new());
vfs.inject_fault(FaultSpec::torn_write("*.wal").at_offset_bytes(8192).valid_bytes(17));
vfs.inject_fault(FaultSpec::power_cut("*.wal").after_nth_sync(2));
```

### Determinism

```rust
const DEFAULT_FAULT_SEED: u64 = 0xD1A6_A3F4_9B17_0C5E;
// Torn-write at WAL offset 8192 with valid_bytes=17 produces exactly 17 bytes every run.
```

### F-1..F-8 adoption checklist (verbatim, MINING-2 §8)

| ID | Requirement |
|---|---|
| **F-1** | Define `FaultKind` enum. |
| **F-2** | Define `FaultSpec` with declarative rules + stable seeds. |
| **F-3** | Wire `FaultInjectingVfs` around real VFS layer. |
| **F-4** | Define named profiles (e.g., `torn-wal-frame`, `partial-checkpoint`). |
| **F-5** | Each profile has `expected_behavior.invariants_preserved`. |
| **F-6** | Metric counter `fsqlite_test_vfs_faults_injected_total`. |
| **F-7** | Each fault becomes `FaultTriggerRecord` in run report. |
| **F-8** | CI dashboard answers "how many partial writes did we exercise this week". |

### `FaultTriggerRecord` (canonical)

```rust
pub struct FaultTriggerRecord {
    pub spec_id: String,
    pub file_path: PathBuf,
    pub offset: u64,
    pub kind: FaultKind,
    pub at: SystemTime,
    pub stack_trace_summary: String,    // truncated to top 6 frames
}
```

## Per-class instantiation

### SQL-class (FrankenSQLite)

- **Wrapper type**: `FaultInjectingVfs<MemoryVfs>` or `FaultInjectingVfs<UnixVfs>`
- **File globs**: `*.db`, `*.db-wal`, `*.db-shm`, `*.db-journal`
- **Named profiles**: `torn-wal-frame`, `partial-checkpoint`, `power-cut-mid-commit`, `disk-full-on-vacuum`, `fsync-storm`, `read-error-on-page-load`, `write-error-on-overflow`
- **F-6 metric name**: `fsqlite_test_vfs_faults_injected_total`

### RESP-class (FrankenRedis) — `RdbFaultVfs`

> "FrankenRedis: `RdbFaultVfs` — partial AOF rewrites, mid-rdb torn writes, fsync-then-power-cut, `EAGAIN` storms on replication socket." — MINING-2 §8

- **Wrapper type**: `RdbFaultVfs` (file faults) + `ReplicationFaultMiddleware` (socket faults)
- **File globs**: `*.rdb`, `*.rdb.tmp`, `*.aof`, `*.aof.manifest`
- **Named profiles**: `partial-aof-rewrite`, `mid-rdb-torn-write`, `fsync-then-power-cut`, `eagain-storm-replication`
- **Socket faults**: `EAGAIN`, `ECONNRESET`, `EPIPE` injected via `ReplicationFaultMiddleware`
- **F-6 metric name**: `frankenredis_test_vfs_faults_injected_total`

### ML-class (FrankenTorch) — `CheckpointFaultVfs`

> "FrankenTorch: `CheckpointFaultVfs` — partial `torch.save`, mid-shard NCCL drops, `CUDA_ERROR_LAUNCH_FAILED` mid-collective." — MINING-2 §8

- **Wrapper type**: `CheckpointFaultVfs` (file faults) + `NcclFaultMiddleware` (collective faults)
- **File globs**: `*.pt`, `*.safetensors`, `*.ckpt`, shard files `*-rank-*-of-*.pt`
- **Named profiles**: `partial-torch-save`, `mid-shard-nccl-drop`, `cuda-launch-failed-mid-collective`, `disk-full-on-checkpoint`
- **F-6 metric name**: `frankentorch_test_vfs_faults_injected_total`

### HTTP-class (fastapi_rust) — `RequestFaultMiddleware`

> "FastAPI Rust: `RequestFaultMiddleware` — connection drops mid-body, slow-loris, partial multipart." — MINING-2 §8

- **Wrapper type**: `RequestFaultMiddleware` (HTTP-stream faults) + `TimeoutFaultLayer`
- **File globs**: N/A (network-only)
- **Named profiles**: `connection-drop-mid-body`, `slow-loris`, `partial-multipart-boundary`, `timeout-just-before-200`, `keepalive-eagain-storm`
- **F-6 metric name**: `fastapi_rust_test_request_faults_injected_total`

## Composition

- [pattern:65-CRASH-BOUNDARIES](65-CRASH-BOUNDARIES.md) — crash boundaries (`BeforeWalHeaderWrite`, etc.) use this VFS to inject the crash at the named point.
- [pattern:25-FIXTURE-ROOT-CONTRACT](25-FIXTURE-ROOT-CONTRACT.md) — fault profiles + their `expected_behavior.invariants_preserved` live in the fixture corpus.
- [pattern:70-E-PROCESSES](70-E-PROCESSES.md) — fault campaigns feed e-process invariant observations.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — `FaultTriggerRecord` is embedded in failure bundles for reproducible repros.

## Pitfalls

- **Non-deterministic faults.** Using `rand::random()` instead of the `DEFAULT_FAULT_SEED`-derived PRNG. The same `FaultSpec` must produce byte-identical fault behavior every run; without that, "we saw a bug under torn-write" is unreproducible.
- **Faults injected before `FaultInjectingVfs` is wrapped around the real VFS.** Common in test-setup ordering bugs: the VFS is constructed AFTER the connection opens, and `inject_fault` calls before the open are silently dropped.
- **`max_triggers` set too high.** "Inject 1000 torn writes" means the test runs forever; the first torn write usually exposes the bug. `max_triggers: 1` is the default; raise only with intent.
- **F-5 invariants not enumerated.** A profile without `expected_behavior.invariants_preserved` is a profile that "tests crash recovery" without naming what recovery should preserve. Without it, the assertion is "didn't panic", which catches almost nothing.
- **Skipping F-6 metric.** Without the counter, the CI dashboard cannot answer "how many partial writes did we exercise this week" (F-8). Counter is one line of code; skipping it means losing fault-coverage visibility.
- **F-7 records not persisted.** `FaultTriggerRecord`s emitted to stderr only are lost on test pass. Persist to `<workspace>/fault_records.jsonl` for the dashboard.
- **Reusing the same `FaultSpec` across tests.** `trigger_count` is mutable per-spec; sharing a spec means the second test's first injection is actually the (N+1)-th. Build a fresh `FaultSpec` per test or `Clone` and reset `trigger_count`.
- **Fault VFS used in production builds.** The whole file should be `#[cfg(test)]` or behind a `test-vfs` feature flag. A production binary with `FaultInjectingVfs` linked in is a security hazard.
- **Forgetting `Latency` as a fault.** Slow-but-not-failing storage exercises timeout paths that other faults don't. `Latency { base_millis: 500, jitter_millis: 100 }` finds timeouts that "ReadFailure" never will.
- **Faults too specific to the current implementation.** A spec that says "fault at offset 8192" assumes 4KB pages. If the page size doubles, the spec misses. Prefer named anchors (`at_wal_header_end`, `after_first_frame`) that the harness resolves to offsets at runtime.
