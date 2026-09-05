# PROJECT-CLASSES.md — Per-Class Instantiations

The gauntlet routes through the same Subject/Oracle/Comparator kernel regardless of class, but the **wiring** changes per class. This file is the routing heart: pick the matching class, then read the section straight through. Every section covers oracle wiring strategy, NormalizedValue type, retry predicate, headline matrix axes, keep-gate score weights, hot-path counters, negative-ledger failure terms, crash boundaries, bit-exact vs ULP boundary, seed contract, behavior-preserving verifier, concurrency-honesty rule, and certification-bundle shape.

Cross-references: [`../THREE-PILLARS.md`](../THREE-PILLARS.md), [`FEATURE-UNIVERSE.md`](FEATURE-UNIVERSE.md), [`INVARIANT-CATALOG.md`](INVARIANT-CATALOG.md), [`../tooling/ORACLE-TOOLCHAIN.md`](../tooling/ORACLE-TOOLCHAIN.md), [`../tooling/BENCH-TOOLCHAIN.md`](../tooling/BENCH-TOOLCHAIN.md), [`../methodology/KEEP-GATE-RULES.md`](../methodology/KEEP-GATE-RULES.md).

Six classes cover every gauntlet target shipped today — the five port-shaped FrankenSuite classes plus Greenfield-Rust-class for novel non-port projects (added Round 4; see § Greenfield-Rust-class at the bottom of this file for the full row):

| Class | Members | Reference type |
|---|---|---|
| SQL-class | `frankensqlite`, `sqlmodel_rust` | upstream SQLite + rusqlite oracle |
| RESP-class | `frankenredis` | vendored `redis-server` over UNIX socket |
| Numerical-Python-class | `franken_numpy`, `frankenpandas`, `frankenscipy`, `franken_networkx` | PyO3 in-process bridge to upstream Python lib |
| ML-System-class | `frankentorch`, `frankenjax`, `franken_whisper` | PyO3 in-process bridge to upstream Python lib + deterministic-mode pin |
| HTTP-Protocol-class | `fastapi_rust`, `fastmcp_rust` | upstream Python framework over compliance fixture corpus + OpenAPI schema diff |
| Greenfield-Rust-class | `eidetic_engine_cli` (canonical example) + any novel non-port Rust project | NO upstream reference — Oracle constructed from 5 modes: Spec / Property / Self / Round-trip / External-tool. See [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md). |

---

## SQL-Class

**Members:** `frankensqlite`, `sqlmodel_rust`.

### Oracle Wiring Strategy
In-process `rusqlite` via `libsqlite3-sys` pinned to contract version (`docs/contracts/csqlite_version_contract.toml`, e.g., `sqlite-3.52.0`).

The 30-line `scenario()` template (verbatim from `crates/fsqlite-e2e/tests/null_semantics_oracle_e2e.rs`):
```rust
fn scenario(stmts: &[&str], queries: &[&str], label: &str) {
    let f = fsqlite::Connection::open(":memory:").expect("open frank");
    let r = rusqlite::Connection::open_in_memory().expect("open rusqlite");

    // 1. Setup: panic if engines DISAGREE on success
    for s in stmts {
        let fe = f.execute(s);
        let re = r.execute_batch(s);
        match (&fe, &re) {
            (Ok(_), Ok(())) | (Err(_), Err(_)) => {},
            (Ok(_), Err(e)) => panic!("frank OK, csql ERROR({e})"),
            (Err(e), Ok(())) => panic!("frank ERROR({e}), csql OK"),
        }
    }
    // 2. Queries: classify each
    let mut mismatches = Vec::new();
    for q in queries {
        match (frank_rows(&f, q), sqlite_rows(&r, q)) {
            (Ok(a), Ok(b)) if a == b   => { /* PASS */ },
            (Ok(a), Ok(b))             => mismatches.push(format!("MISMATCH: {q}\n  frank: {a:?}\n  csql:  {b:?}")),
            (Err(e), Ok(b))            => mismatches.push(format!("FRANK_ERR: {q}\n  frank: ERROR({e})\n  csql:  {b:?}")),
            (Ok(a), Err(e))            => mismatches.push(format!("CSQL_ERR: {q}\n  frank: {a:?}\n  csql: ERROR({e})")),
            (Err(_), Err(_))           => { /* both ERROR — agreement */ },
        }
    }
    assert!(mismatches.is_empty(), "{label}: {} mismatch(es)\n{}", mismatches.len(), mismatches.join("\n"));
}
```

`EngineIdentity` (`SUBJECT_IDENTITY_LABEL = "frankensqlite"`, `REFERENCE_IDENTITY_LABEL = "csqlite-oracle"`) asserted at every comparator entry; preflight doctor refuses to certify if identities collide.

### NormalizedValue Type
`{Null, Integer, Real, Text, Blob}` — render-to-canonical-string comparator. From `oracle.rs` 284–310:
```rust
pub fn normalize_value(value: &str) -> String {
    let trimmed = value.trim();
    if let Ok(f) = trimmed.parse::<f64>() {
        if f.is_nan() { return "NaN".to_string(); }
        if f.is_infinite() {
            return if f.is_sign_positive() { "Inf".to_string() } else { "-Inf".to_string() };
        }
        return format!("{f:.15}");
    }
    if trimmed.is_empty() || trimmed.eq_ignore_ascii_case("null") {
        return "NULL".to_string();
    }
    trimmed.to_string()
}
```
Rendering uniform: `Vec<Vec<String>>` with NULL capitalized, integers base-10, floats via `Display`, text in single quotes, blob as `X'<hex>'`.

### Retry Predicate (Default Form)
"Retry only if a profiler attributes a clearly-above-noise share to `<specific counter>` on `<wider workload shape>`." (Example: "Retry only if MT8 attribution shows `commit_finalize_seq_time_ns` ≥0.1% self-time on the 8-writer shared-table workload.")

Other forms documented in [`../methodology/RETRY-CONDITION-VOCABULARY.md`](../methodology/RETRY-CONDITION-VOCABULARY.md):
- "Reconsider only inside the broader DML mutation operator redesign"
- "Worth reconsidering when MT16 shared-table ratio crosses 5x"
- "Not worth retrying as a standalone patch"
- "Do not retry from a cold read; use comprehensive-bench attribution instead"

### Headline Matrix Axes
1. **Workload size:** `[100, 1_000, 10_000, 100_000]` (quick mode drops 100K)
2. **Value shape:** Tiny (1 col), Small (3 cols ≈30B), Medium (6 cols ≈180B), Large (10 cols ≈600B w/ overflow)
3. **Concurrency:** `[2, 4, 8]` in comprehensive; `[1, 2, 4, 8, 16]` in mt-mvcc

### Keep-Gate Score Weights
```
ReadSingle        0.35
ReadAggregate     0.15
WriteSingle       0.30
WriteBulk         0.10
ConcurrentWriters 0.05
MixedOltp         0.05
```
CI regression gate keys off `per_category_weighted.score`, not raw average.

### Hot-Path Counters (Verbatim from MINING-3 §23.6)
> **FrankenSQL** | `prepared_lookup_time_ns`, `begin_setup_time_ns`, `execute_body_time_ns`, `commit_finalize_seq_time_ns`, concurrent_commit_plan_{successes, errors, busy_snapshot_errors, uncontended_fast_paths, full_validations}, prepared_direct_{insert,update,delete}_executions, B-tree seek/insert/delete/page_splits/swizzle_{in,out}_total, arena_alloc_bytes, page_buffer_pool_{hits,misses}

Connection lifecycle: `background_status_time_ns, prepared_lookup_time_ns, prepared_schema_refresh_time_ns, cached_read_snapshot_reuses, cached_read_snapshot_parks`.

Transaction phases: `begin_setup_time_ns, execute_body_time_ns, commit_pre_txn_time_ns, commit_txn_roundtrip_time_ns, commit_finalize_seq_time_ns`.

Parser & VDBE: `parser: ParserHotPathProfileSnapshot, window_func_partitions_total`.

### Negative-Ledger Failure Terms (Project-Specific)
General terms: `rejected, reverted, abandoned, slower, regressed, didn't help, within noise, no improvement, failed to improve, rolled back, backed out, not a keep, keep gate`.

SQL-specific: `correctness-abandoned, focused improved broad worsened, no bounded micro-lever, reconsider only inside broader DML mutation operator redesign, MT8 attribution missing, cold-start outlier, pulled the pin, fused-design target, selections= counts byte-identical`.

### Crash Boundaries (8 Verbatim from MINING-2 §9)
```rust
pub enum CrashBoundary {
    BeforeWalHeaderWrite,             // before header is laid down
    BeforeWalFrameAppend,             // before next frame's bytes appended
    AfterWalFrameAppendBeforeFsync,   // bytes on disk, not yet durable
    AfterFsyncBeforePublish,          // fsync done, CommitIndex/SHM not yet visible
    BetweenPageTableRebuildSteps,     // mid-recovery rebuild
    AfterPublishBeforeCheckpoint,     // commit visible, checkpoint not started
    MidCheckpoint,                    // some pages back to DB, not all
    AfterCheckpoint,                  // checkpoint done
}
```
Per-boundary verification: `arm_crash_boundary(boundary)` → crash at that exact point → recovery → assert consistent state ("**not 'right state' but 'committed-or-not-committed-no-partial'**").

### Bit-Exact vs ULP Boundary
**Bit-exact:** integers, blobs, text, NULL handling, plan output for explainable queries. Required.
**Per `normalize_value`:** floats rendered `{f:.15}` so the byte-level compare tolerates final-LSB differences only within the 15-decimal envelope. NaN canonicalized to `"NaN"`, Inf to `"Inf"`/`"-Inf"`.
**Strict:** no ULP-tolerance table for SQL. Floats in SQL are double-precision IEEE-754 with deterministic ordering; any divergence is `TrueDivergence` or `FloatingPointDifference` (the latter only if explicitly documented in a metamorphic equivalence-expectation).

### Seed Contract
```rust
fn derive_entry_seed(corpus_entry_id: &str) -> u64 { /* deterministic */ }
```
**Never `rand::random()`.** Same input → same seed → same SQL → same bugs found.

Fault-VFS seed: `const DEFAULT_FAULT_SEED: u64 = 0xD1A6_A3F4_9B17_0C5E;` — "Torn-write at WAL offset 8192 with valid_bytes=17 produces exactly 17 bytes every run."

Cross-process swarm seed: `DEFAULT_SEED = 0x4653_514C_5357_4152` ("FSQLSWAR" in ASCII hex).

### Behavior-Preserving Verifier
`selections=` counts byte-identical. The bench harness exposes per-scenario selection counters; a change that preserves selection counts to the byte is verified non-behavior-affecting. From CC.md §37: "A specific form of behavior-preservation proof: the bench harness exposes per-scenario selection counters; a change that preserves selection counts to the byte is verified non-behavior-affecting."

Plus: oracle test suite green; insta snapshots of bytecode unchanged or accompanied by `cargo insta review` diff explained in the bead.

### Concurrency-Honesty Rule
- `concurrent_mode_default_guard.txt` dropped into every artifact lane:
  ```
  CONCURRENT_MODE_DEFAULT=true
  GIT_SHA=<sha>
  TIMESTAMP=<ISO-8601>
  ```
- Rationale (verbatim): "Feb 2026 an agent silently disabled concurrent mode; project didn't notice until pass-over-pass gate flipped. This proof file, part of artifact contract, prevents silent regression."
- MT8 attribution mandatory for kept perf wins; cite a specific frame ≥0.1% self-time.

### Certification-Bundle Shape
- `certification_bundle/confidence_gate.json` — Beta posterior + conformal lower bound per category
- `certification_bundle/verification_contract.json` — `pass | fail-missing-evidence | fail-invalid-references | fail-mixed` matrix
- `certification_bundle/release_certificate.json` — strict-conformant-release.v1; embeds `csqlite_version_contract.toml` hash
- `certification_bundle/ci_artifact_manifest.json` — every per-Phase artifact path + SHA-256
- `certification_bundle/benchmark_summary.json` — `.bench-history/<bench>.latest.json` for every focused bench
- `certification_bundle/scorecards.json` — per-feature Pass/Partial/Missing/Excluded status
- `certification_bundle/critical_path_report.json` — bead-graph critical path
- `certification_bundle/ratchet_state.json` — current lower bound for the conformal ratchet

---

## RESP-Class

**Members:** `frankenredis`.

### Oracle Wiring Strategy
Vendored `redis-server` binary at pinned version (`redis-7.2.5`), UNIX domain socket, deterministic command trace. Subprocess bridge (not in-process) because Redis is a server with its own event loop.

`EngineIdentity::Subject = "frankenredis"`, `EngineIdentity::Oracle = "redis-7.2.5-oracle"`. Preflight doctor verifies the binary exists at the contract path, version string matches `INFO server` output, and protocol mode (`RESP_VERSION=3`) is the default.

### NormalizedValue Type
`RespValue` with 14 RESP3 variants + collection-semantics comparator. Adapted from MINING-1 §6 + MINING-2 §1 generalization paragraph:
```rust
pub enum RespValue {
    SimpleString(String),
    Error { code: String, message: String },   // category-compared, not text-compared
    Integer(i64),
    BulkString(Option<Vec<u8>>),
    Array(Option<Vec<RespValue>>),
    // RESP3 additions:
    Null,
    Boolean(bool),
    Double(f64),
    BigNumber(num_bigint::BigInt),
    BulkError { code: String, message: String },
    VerbatimString { format: String, data: Vec<u8> },
    Map(Vec<(RespValue, RespValue)>),
    Set(Vec<RespValue>),
    Attribute { attrs: Vec<(RespValue, RespValue)>, value: Box<RespValue> },
    Push(Vec<RespValue>),
}
```
Collection-semantics comparator: `Set` compared as unordered multiset; `Hash` compared as unordered map of key→value; `List` and `Sorted Set` ordered.

### Retry Predicate (Default Form)
"Retry only if `--latency` p99 attribution shows `<command>::<phase>` ≥0.1% self-time on the 64-client `PIPELINE`-mode workload, AND the negative ledger does not already contain a related rejection."

### Headline Matrix Axes
1. **Command family:** GET / SET / MGET / MSET, hashes, lists, sets, sorted sets, streams, pubsub
2. **Clients:** `[1, 2, 4, 8, 16, 64, 256]`
3. **Pipeline depth:** `[1, 16, 128]`
4. **Value size:** Tiny (8B) / Small (64B) / Medium (1KB) / Large (16KB)

Primary score: "RPS p99 latency" — quoted from FrankenRedis next-action list (§97 MINING-1).

### Keep-Gate Score Weights (Suggested per FrankenRedis next-action list)
```
StringOps         0.30
HashOps           0.15
ListOps           0.10
SetOps            0.10
SortedSetOps      0.10
StreamOps         0.05
PubSub            0.05
Pipeline          0.10
Cluster           0.05
```
(To be ratified in `parity_score_contract.toml` at Phase 2.)

### Hot-Path Counters (Verbatim from MINING-3 §23.6)
> **Redis** | `resp_parse_time_ns`, `dict_probe_count`, `aof_flush_time_ns`, `rdb_serialize_time_ns`, `command_dispatch_time_ns`, `pubsub_deliver_time_ns`, `cluster_slot_resolve_time_ns`, `expiration_sweep_time_ns`, `replication_backlog_appends`, `client_io_eagain_count`

### Negative-Ledger Failure Terms
General terms + RESP-specific: `RESP frame malformed, AOF rewrite race, RDB byte-drift, PUBSUB ordering violation, replication offset desync, EAGAIN storm, slot resolution miss, expiration sweep regression`.

### Crash Boundaries (6+ Verbatim from MINING-2 §9)
- `BeforeAofRewriteRename`
- `DuringRdbWrite`
- `BeforeReplicationOffsetUpdate`
- `MidPsync`
- `AfterReplOffsetBeforeAck`
- `DuringFsync`

Plus `RdbFaultVfs` profiles per MINING-2 §8: partial AOF rewrites, mid-rdb torn writes, fsync-then-power-cut, `EAGAIN` storms on replication socket.

### Bit-Exact vs ULP Boundary
**Bit-exact:** RESP serialization byte-equal; RDB byte-equal; AOF byte-equal modulo timestamp lines. Integer commands integer-exact.
**Floating point:** `INCRBYFLOAT`, `ZADD` scores, `OBJECT FREQ`. Documented per-command tolerance (typically 1 ULP). Sorted-set scores compared with 1-ULP tolerance.

### Seed Contract
- Client-side: deterministic command trace from corpus (`corpus_entry_id → command_sequence`)
- Server-side: `--hz 10` and pinned `--maxmemory-policy noeviction` for determinism
- RDB tests: pinned random-seed initial state via `DEBUG SLEEP` + scripted preload

### Behavior-Preserving Verifier
- `INFO commandstats` byte-identical for the workload
- RDB file SHA-256 byte-identical (Tier-1) or canonical (Tier-2 after canonicalization)
- AOF replay produces byte-identical DB state
- `MONITOR` trace identical command-sequence per client

### Concurrency-Honesty Rule
- `resp_protocol_default_guard.txt` (analogue of `concurrent_mode_default_guard.txt`):
  ```
  RESP_VERSION=3
  CLUSTER_MODE=off
  GIT_SHA=<sha>
  TIMESTAMP=<ISO-8601>
  ```
- Pipelining tests must report `pipeline_depth_effective` (actual, not requested)
- Replication tests must report replica lag at end-of-run

### Certification-Bundle Shape
Same as SQL-class with:
- `certification_bundle/resp_protocol_compliance.json` — per-RESP3-variant pass rate
- `certification_bundle/rdb_aof_roundtrip.json` — Tier-1/Tier-2/Tier-3 per fixture

---

## Numerical-Python-Class

**Members:** `franken_numpy`, `frankenpandas`, `frankenscipy`, `franken_networkx`.

### Oracle Wiring Strategy
PyO3 in-process Python interpreter with the reference library pinned in `docs/contracts/<numpy|pandas|scipy|networkx>_version_contract.toml`. Reference invoked via `numpy.testing` formatters / pandas `assert_frame_equal` / scipy tolerance policy / networkx behavioral protocol.

**Bit-exact PCG64DXSM RNG parity** is mandatory. The Rust port must seed `PCG64DXSM` with the same key and produce byte-identical stream as `numpy.random.default_rng(seed)`.

`EngineIdentity::Subject` = port basename; `EngineIdentity::Oracle` = `<reference>-oracle`. Preflight doctor verifies PyO3 interpreter starts, reference version matches contract, SIMD flags + BLAS thread count match the contract.

### NormalizedValue Type
`TensorSpec { shape, dtype, device, requires_grad, data_hash }` for NumPy/SciPy arrays.
For pandas: `DataFrameSpec { columns: Vec<(String, Dtype)>, index_dtype, shape, value_hash, null_mask_hash }`.
For NetworkX: `GraphSpec { node_set_hash, edge_set_hash, edge_data_hash, is_directed, is_multigraph, iteration_order_hash }`.

Per-op ULP tolerance table (mandatory at Phase 2; lives in `docs/contracts/ulp_tolerance_v1.toml`).

### Retry Predicate (Default Form)
"Retry only if profiler attributes `<ufunc_or_method>::<phase>` ≥0.1% self-time on the `<dtype>×<shape>` workload, AND the change does not weaken the ULP tolerance table."

### Headline Matrix Axes
1. **Dtype:** `[f32, f64, i32, i64, complex64, complex128, bool]`
2. **Array shape:** small (16), medium (1024), large (1M); 1D / 2D / 3D / 4D
3. **Operation family:** elementwise, reduction, linalg, FFT, RNG, broadcasting
4. **Layout:** C-contiguous, F-contiguous, strided view, slice

For pandas additionally: row count, column count, dtype mix, NaN density, groupby cardinality.

### Keep-Gate Score Weights (Suggested per FrankenNumPy §99)
```
Ufuncs            0.30
Reductions        0.15
ShapeTransforms   0.10
LinAlg            0.15
RNG               0.10
Broadcasting      0.10
IO                0.05
ArrayProtocol     0.05
```

### Hot-Path Counters (Verbatim from MINING-3 §23.6)
> **NumPy** | `ufunc_dispatch_time_ns`, `array_alloc_bytes`, `iter_setup_time_ns`, `blas_call_count`, `lapack_call_count`, `random_pcg64dxsm_advance_count`, `array_view_creates`, `copy_on_write_breaks`

For pandas/scipy/networkx: same instrumentation philosophy with library-specific names; document in `crates/<port>-core/src/hot_path_profile_snapshot.rs`.

### Negative-Ledger Failure Terms
General terms + Numerical-Python-specific: `SIMD broke dtype, view became copy, RNG stream diverged at element N, NaN propagated where reference returned scalar, BLAS thread count drifted, ufunc loop selection changed`.

### Crash Boundaries (5 Checkpoint-Save Verbatim from MINING-2 §9, ML-class analogue applies here too)
- `BeforeSerialize`
- `MidShardWrite`
- `AfterShardBeforeMetadata`
- `MidMetadataUpdate`
- `AfterRenameBeforeFsync`

For NumPy IO specifically: `BeforeNpyHeaderWrite`, `MidNpyArrayWrite`, `AfterNpyArrayBeforeFsync`, `MidNpzShardWrite` (pickle-protocol mid-write).

### Bit-Exact vs ULP Boundary
**Bit-exact required:**
- Integer ops
- Boolean ops
- Bit-twiddling
- RNG stream (PCG64DXSM byte-exact with reference seed)
- Shape, stride, dtype metadata
- View vs copy semantics

**ULP-tolerant (per `ulp_tolerance_v1.toml`):**
- f32: 1 ULP for elementwise; 4 ULP for matmul; 8 ULP for FFT
- f64: 1 ULP for elementwise; 2 ULP for matmul; 4 ULP for FFT
- Transcendental (sin/cos/exp/log): library-specific (numpy uses Cephes / SLEEF; document the source)
- LAPACK routines: condition-number-dependent; document policy

ULP tolerance changes go through the `🎚 Raise-ULP-Tolerance` operator: justified, scoped to the operator, accompanied by `gradcheck_max_rel_error` snapshot for ML class (where applicable).

### Seed Contract
- RNG seed pinned at corpus-entry level; PCG64DXSM stream byte-identical for the same seed
- `numpy.testing.assert_array_equal` for bit-exact; `assert_allclose(atol, rtol)` for ULP-tolerant per the table
- `numpy.show_config()` SIMD flags + BLAS thread count embedded in the run's `ExecutionEnvelope`

### Behavior-Preserving Verifier
- `numpy.testing.assert_array_equal` over output arrays
- View-vs-copy invariants: `np.shares_memory(a, b)` agrees with reference
- Stride pattern matches reference (modulo equivalent layouts)
- For pandas: `pd.testing.assert_frame_equal(check_exact=True, check_like=False, check_dtype=True, check_index_type=True)`

### Concurrency-Honesty Rule
- `blas_thread_count_default_guard.txt`:
  ```
  OPENBLAS_NUM_THREADS=1
  MKL_NUM_THREADS=1
  OMP_NUM_THREADS=1
  GIT_SHA=<sha>
  TIMESTAMP=<ISO-8601>
  ```
- Multi-threaded ops report thread-count actually used (not requested)
- Parallel ops document tie-breaking (deterministic vs reduction-order-dependent)

### Certification-Bundle Shape
Same as SQL-class with:
- `certification_bundle/ulp_tolerance_compliance.json` — per-op observed ULP vs tolerated
- `certification_bundle/rng_stream_proof.json` — PCG64DXSM byte-identity proof for N seeds × M stream lengths
- `certification_bundle/view_copy_invariants.json` — per-op `shares_memory` agreement

---

## ML-System-Class

**Members:** `frankentorch`, `frankenjax`, `franken_whisper`.

### Oracle Wiring Strategy
PyO3 in-process with `torch.use_deterministic_algorithms(True)` (or JAX equivalent: `jax.config.update("jax_enable_x64", True)` + `XLA_FLAGS=--xla_gpu_deterministic_ops=true`) pinned; seeded RNG captured per-call.

Reference pinning: `torch-2.X.Y`, `jax-0.4.Y`, model corpus hashes for `franken_whisper`.

Preflight doctor verifies PyTorch version + CUDA/cuDNN/driver versions + determinism flags + dtype policy + RNG seed policy + model corpus hashes match contract.

### NormalizedValue Type
`TensorSpec { shape, dtype, device, requires_grad, data_hash }` plus per-op ULP tolerance table:
- 4 ULP f32 matmul
- 2 ULP elementwise default
- Per-op overrides in `docs/contracts/ulp_tolerance_v1.toml`

Gradient comparisons: `gradcheck_max_rel_error` per op.

### Retry Predicate (Default Form)
"Retry only if a profiler attributes `<aten_op>::<kernel_variant>` ≥0.1% self-time on the `<dtype>×<shape>×<device>` workload, AND `gradcheck_max_rel_error` stays within the ULP tolerance budget."

### Headline Matrix Axes
1. **Op family:** elementwise, reduction, matmul, conv, attention, normalization, optimizer step, autograd backward
2. **Tensor shape:** common shapes (1D, 2D, 3D, 4D); batch sizes (1, 32, 128, 1024)
3. **Dtype:** `[f16, bf16, f32, f64, i32, i64]`
4. **Device:** CPU, CUDA, (Metal, ROCm if applicable)
5. **Determinism mode:** `use_deterministic_algorithms(True)` only

For `franken_whisper`: model size (tiny/base/small/medium/large), audio length, sample rate.

### Keep-Gate Score Weights (Suggested per FrankenTorch §98)
```
Elementwise       0.15
Reductions        0.10
MatMul            0.20
Conv              0.10
Attention         0.10
Normalization     0.05
Optimizer         0.10
Autograd          0.10
DataPipeline      0.05
nn_Modules        0.05
```

### Hot-Path Counters (Verbatim from MINING-3 §23.6)
> **Torch** | `aten_dispatch_time_ns`, `autograd_tape_append_time_ns`, `kernel_launch_time_ns`, `memcpy_h2d_bytes`, `memcpy_d2h_bytes`, `jit_cache_{hits,misses}`, `nccl_collective_time_ns`, `cuda_stream_sync_time_ns`, `gradcheck_max_rel_error`, `nondeterministic_op_count`
>
> **JAX** | `tracer_construct_time_ns`, `primitive_dispatch_count`, `transform_stack_depth`, `xla_compile_time_ns`, `hlo_pass_time_ns`, `pjit_partition_time_ns`, `vmap_unroll_count`, `grad_jvp_vjp_calls`

### Negative-Ledger Failure Terms
General terms + ML-specific: `kernel-fusion broke gradient, memory-format change altered ULP, allocator-pool churn, autograd-tape shortcut broke higher-order, NCCL collective non-deterministic, JIT cache key collision, transform-cache miss, AD JVP/VJP shortcut numerically wrong, XLA rewrite rule algebraically valid but numerically wrong`.

### Crash Boundaries (5 Checkpoint-Save + 2 Distributed-Collective Verbatim from MINING-2 §9)
Checkpoint-save:
- `BeforeSerialize`
- `MidShardWrite`
- `AfterShardBeforeMetadata`
- `MidMetadataUpdate`
- `AfterRenameBeforeFsync`

Distributed-collective:
- `MidAllReduce`
- `BeforeRendezvousAck`

Plus `CheckpointFaultVfs` profiles per MINING-2 §8: partial `torch.save`, mid-shard NCCL drops, `CUDA_ERROR_LAUNCH_FAILED` mid-collective.

### Bit-Exact vs ULP Boundary
**Bit-exact required:**
- Integer ops
- Tensor metadata (shape, dtype, device, layout, requires_grad)
- Autograd graph topology
- Optimizer state dict keys
- Model state dict keys

**ULP-tolerant (`ulp_tolerance_v1.toml`):**
- f32 elementwise: 2 ULP default
- f32 matmul: 4 ULP (per kernel)
- f32 conv: 4 ULP (per kernel)
- f32 attention: 8 ULP (composition of matmul + softmax)
- bf16/f16: per-op (typically larger; document)
- Backward pass: per-op (typically 2× forward tolerance)

`gradcheck_max_rel_error` snapshot required for every kept perf win that touches autograd; ULP-tolerance changes must justify with `gradcheck_max_rel_error` delta ≤ 0.

### Seed Contract
- `torch.manual_seed(seed)`, `torch.cuda.manual_seed_all(seed)`, `numpy.random.seed(seed)`, `random.seed(seed)`
- `torch.use_deterministic_algorithms(True)` + `CUBLAS_WORKSPACE_CONFIG=:4096:8` (CUDA determinism)
- For JAX: `jax.random.PRNGKey(seed)` byte-identical
- Per-call seed derivation from `corpus_entry_id` (never `rand::random()`)

### Behavior-Preserving Verifier
- Tensor input/output bundles SHA-256-identical (Tier-1) or ULP-tolerant (Tier-3)
- Gradient bundles SHA-256-identical or `gradcheck_max_rel_error` within budget
- State-dict fixtures SHA-256-identical
- Deterministic autograd ledger (per-op replay produces same gradient)

### Concurrency-Honesty Rule
- `determinism_default_guard.txt`:
  ```
  TORCH_USE_DETERMINISTIC_ALGORITHMS=true
  CUBLAS_WORKSPACE_CONFIG=:4096:8
  CUDA_DEVICE_COUNT=<n>
  CUDNN_DETERMINISTIC=1
  GIT_SHA=<sha>
  TIMESTAMP=<ISO-8601>
  ```
- DataLoader `num_workers` documented; `worker_init_fn` seeds per worker
- NCCL collectives must use deterministic algorithms; `nccl_collective_time_ns` reported
- `nondeterministic_op_count` must be 0 for kept perf wins

### Certification-Bundle Shape
Same as Numerical-Python-class with:
- `certification_bundle/gradcheck_compliance.json` — per-op `gradcheck_max_rel_error`
- `certification_bundle/checkpoint_roundtrip.json` — save/load byte-identity proof
- `certification_bundle/distributed_collective_proof.json` — for `franken_whisper` distributed inference

---

## HTTP-Protocol-Class

**Members:** `fastapi_rust`, `fastmcp_rust`.

### Oracle Wiring Strategy
Compliance fixture corpus (HTTP transcripts, OpenAPI specs, MCP JSON-RPC traces) + reference framework (Python FastAPI / Python FastMCP) with deterministic clock + RNG. Subprocess bridge to reference; in-process Rust subject.

`EngineIdentity::Subject = "fastapi_rust"` / `"fastmcp_rust"`; `EngineIdentity::Oracle = "fastapi-0.X.Y-oracle"` / `"fastmcp-0.X.Y-oracle"`.

### NormalizedValue Type
Normalized HTTP response: `(status_code, normalized_headers, normalized_body)`.
- Status code: exact integer
- Headers: case-insensitive name comparison; order-insensitive; specific multi-value headers (`Set-Cookie`, `Vary`) compared as ordered list
- Body: MIME-aware (`application/json` → canonical-JSON; `application/xml` → canonical-XML; `text/plain` → text-equality; binary → SHA-256)

Plus OpenAPI schema diff (for fastapi_rust) and MCP tool/resource schema snapshot (for fastmcp_rust).

### Retry Predicate (Default Form)
"Retry only if `--latency` p99 attribution shows `<route>::<phase>` ≥0.1% self-time on the `<concurrency>` workload, AND the OpenAPI schema diff is empty."

### Headline Matrix Axes
1. **HTTP method:** GET / POST / PUT / DELETE / PATCH
2. **Body size:** Tiny (empty) / Small (256B) / Medium (16KB) / Large (1MB) / Streaming
3. **Concurrency:** `[1, 8, 64, 512, 4096]`
4. **Middleware stack depth:** 0 / 5 / 20
5. **Body type:** JSON / form / multipart / binary / streaming

For fastmcp_rust: per-MCP-method (tools/list, tools/call, resources/list, resources/read, prompts/list, prompts/get) + cancellation budgets + four-valued outcome (Success/Error/Cancelled/Timeout).

### Keep-Gate Score Weights (Suggested)
```
Routing           0.20
Validation        0.15
SerDe             0.20
Middleware        0.10
OpenAPI           0.10
DI                0.05
Streaming         0.10
ErrorMapping      0.10
```

### Hot-Path Counters (Verbatim from MINING-3 §23.6)
> **HTTP (FastAPI Rust)** | `route_match_time_ns`, `handler_dispatch_time_ns`, `middleware_traversal_time_ns`

Plus for fastmcp_rust: `jsonrpc_parse_time_ns`, `tool_dispatch_time_ns`, `resource_read_time_ns`, `cancellation_check_time_ns`, `budget_enforcement_time_ns`.

### Negative-Ledger Failure Terms
General terms + HTTP-specific: `header case mismatch, body MIME mis-canonicalized, OpenAPI schema drift, route precedence wrong, DI scope leaked across requests, middleware order changed observable behavior, extractor fast-path skipped validation, streaming chunk boundary changed, error mapping lost detail`.

### Crash Boundaries (5 Request-Lifecycle Verbatim from MINING-2 §9)
- `BeforeRequestParse` (open)
- `AfterHeaderParseBeforeBody` (header)
- `MidBodyRead` (body-start)
- `AfterBodyBeforeHandler` (body-end)
- `MidResponseWrite` (close)
- Plus `MidCancellation` (the +1)

Plus `RequestFaultMiddleware` profiles per MINING-2 §8: connection drops mid-body, slow-loris, partial multipart.

### Bit-Exact vs ULP Boundary
**Bit-exact required:**
- Status codes
- Header names (case-insensitive equality)
- Header values
- JSON bodies (canonical-JSON)
- Multipart body byte-equal modulo boundary string
- OpenAPI schema JSON (canonical)

**Not applicable:** ULP tolerance does not apply; HTTP is byte-exact end-to-end.

### Seed Contract
- Deterministic clock injected (replaces `time::now()` with `MockClock`)
- Deterministic RNG injected (replaces `rand::random()` with seeded `ChaCha20Rng`)
- Per-test-case seed derived from `corpus_entry_id`
- Cookie/CSRF token generation seeded

### Behavior-Preserving Verifier
- HTTP transcript fixtures byte-identical (Tier-1) or canonical (Tier-2)
- OpenAPI schema diff empty (golden file)
- Route macro compile-fail tests for malformed annotations
- Validation-error JSON identical (Pydantic-equivalent error shape)

### Concurrency-Honesty Rule
- `protocol_default_guard.txt`:
  ```
  HTTP_VERSION=1.1
  H2C_ENABLED=false
  KEEP_ALIVE=true
  GIT_SHA=<sha>
  TIMESTAMP=<ISO-8601>
  ```
- Concurrency tests must report `concurrent_requests_actual` (after rate-limit and queue effects)
- Cancellation tests must report `cancellation_observed_at_phase` (which boundary fired)

### Certification-Bundle Shape
Same as SQL-class with:
- `certification_bundle/openapi_schema_diff.json` — empty diff vs reference
- `certification_bundle/http_transcript_compliance.json` — per-transcript Tier-1/Tier-2 result
- `certification_bundle/cancellation_proof.json` — per-boundary cancellation observation

---

## Cross-Class Commonalities

Regardless of class, every port has:

1. **Subject/Oracle/Comparator kernel** — the 30-line `scenario()` template adapted per class
2. **`EngineIdentity` discriminator** — subject and oracle identity strings asserted distinct at every comparator entry; preflight doctor refuses to certify if they collide
3. **`differential_v2.rs` envelope** — `ExecutionEnvelope { format_version, run_id, scenario_id, seed, engines, pragmas|config, schema|stub, workload, canonicalization }` with `artifact_id = SHA-256 of canonical JSON excluding run_id`
4. **`oracle_preflight_doctor`** — green/yellow/red verdict per class adaptation; `certifying: true` ONLY for green
5. **`fault_vfs.rs` / class-equivalent** — F-1..F-8 adoption checklist; pinned `DEFAULT_FAULT_SEED`
6. **`failure_bundle.rs`** — `first_divergence_jsonptr = /failure/first_divergence`; "**A partial bundle with provenance is more valuable than no bundle.**"
7. **`eprocess.rs` / class-equivalent** — hardware-enforced `p₀=1e-9, λ=0.999, α=1e-6`; software-enforced `p₀=1e-6, λ=0.9, α=0.001`; arithmetic-mean global e-value
8. **`metamorphic.rs`** — four `TransformFamily` variants adapted per class
9. **`comprehensive_bench.rs`** — six timing constants verbatim (`WARMUP_ITERS=2, MIN_ITERS=3, MAX_ITERS=10, TARGET_DURATION=5s`); `measure()` + `measure_with_teardown()` with teardown OUTSIDE timed window
10. **`.bench-history/<bench>.latest.json` committed** — pass-over-pass gate is a file
11. **`HotPathProfileSnapshot`** — per-domain counters per §23.6 row
12. **`<feature>_default_guard.txt` per artifact lane** — concurrent mode default proof; `EngineIdentity` proof
13. **`docs/progress/{perf,conformance,surface}-negative-results.md`** — three ledgers seeded with the verbatim preamble + retry-condition vocabulary
14. **AGENTS.md mandate paragraph** — cass-mining 60-day grep; ledger-grep-before-perf-work
15. **`FeatureUniverse` + `InvariantCatalog`** — see [`FEATURE-UNIVERSE.md`](FEATURE-UNIVERSE.md) and [`INVARIANT-CATALOG.md`](INVARIANT-CATALOG.md)
16. **Verification-contract enforcement** — `pass | fail-missing-evidence | fail-invalid-references | fail-mixed` × `allowed | blocked-by-base-gate | blocked-by-contract | blocked-by-both`

The universal floor (MINING-3 §15) — what every sibling must have:
```
docs/
├── contracts/{reference}_version_contract.toml
├── canonical_parity_contract.md
└── progress/perf-negative-results.md

crates/{project}-harness/src/
├── oracle.rs
├── differential_v2.rs
├── ratchet_policy.rs
├── failure_bundle.rs
├── e2e_log_schema.rs
└── fault_vfs.rs (or equivalent)

crates/{project}-e2e/
├── tests/*_oracle_e2e.rs
├── src/bin/comprehensive_bench.rs
└── benches/

.bench-history/{primary_bench}.latest.json
.github/workflows/verification-gates.yml
AGENTS.md
```

---

## When to Escalate to a New Class

If a port doesn't fit any of the five classes, signs you need a new class:

- **The reference is not a runnable comparator** — e.g., a paper-only spec with no reference implementation. (Resolution: ratify a reference implementation first; don't escalate.)
- **The output is not comparable as a value** — e.g., a stream-processing system where comparison is per-event over time. (Resolution: introduce a class with `TraceSpec { event_sequence_hash, timing_envelope, equivalence_predicate }`.)
- **The system is fundamentally non-deterministic** — e.g., an evolutionary search with no seed-reproducibility contract. (Resolution: introduce determinism contract first, or carve out a `metamorphic-only` class.)
- **The output is a binary artifact with no canonical normalization** — e.g., a video codec where bitstream parity is impossible. (Resolution: introduce a class with `BitstreamSpec { perceptual_metric, reference_decoder, tolerance_envelope }`.)
- **The system has no "reference" — it IS the reference** — e.g., a novel greenfield project (eidetic_engine_cli is the canonical example). (Resolution: this is the **Greenfield-Rust-class** — the skill DOES apply via 5-mode Oracle construction. See [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) and the Greenfield-Rust-class section below.)

The fingerprint of a new class is: a different oracle wiring strategy + a different NormalizedValue type + a different crash-boundary enumeration + a different ULP/bit-exact boundary policy. If all four of those match an existing class, you're in that class with new members; if 2+ differ, it's a new class.

To propose a new class:
1. Draft `docs/contracts/<class-name>_class_contract.md` with the seven sections (oracle wiring, NormalizedValue, retry predicate, headline matrix axes, hot-path counters, crash boundaries, certification-bundle shape)
2. Map at least 2 candidate members
3. Validate that the seven universal-floor components (oracle, differential_v2, eprocess, metamorphic, fault_vfs, comprehensive_bench, FeatureUniverse) can be instantiated for the class
4. Append to this file under a new top-level section between HTTP-Protocol-Class and Cross-Class Commonalities

---

## Greenfield-Rust-class

**Members:** novel non-port Rust projects (canonical example: `eidetic_engine_cli`); the skill applies via the 5-mode Oracle construction in [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md).

**Oracle wiring:** one or more of `{Spec-as-Oracle, Property-Oracle, Self-Oracle (prior-commit), Round-trip-Oracle, External-tool-Oracle}`. Most greenfield projects use 3-4 in combination. The composite oracle dispatches per-scenario via the `OracleMode` enum — see [`subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md).

**NormalizedValue:** project-specific; defined alongside the spec at Phase 2. For `eidetic_engine_cli`: `EidContextPack`, `EidEmbedding`, `EidAuditEvent`, etc. — one normalized type per emitted output kind.

**Retry predicate:** typically wraps storage-backend transient errors (e.g., SQLite `SQLITE_BUSY`) symmetrically across subject AND the prior-commit baseline. For non-storage greenfield projects, no retry shell needed.

**Headline matrix axes:** CLI subcommand × scale × concurrency. For library-only projects: function family × input size × concurrency.

**Keep-gate score:** per-CLI-subcommand weighted; weights from usage telemetry if available, else equal-weight over the canonical subcommand set.

**Hot-path counters:** project-specific. For `eidetic_engine_cli`: `remember_latency_ns, recall_latency_ns, pack_assembly_time_ns, embed_dedup_ratio, sqlite_busy_retries, index_rebuild_progress_pct, arena_alloc_bytes`.

**Negative-ledger failure terms:** project-specific. For `eidetic_engine_cli`: `embed-cache-stale, ulid-tiebreak-loss, ppr-divergent, pack-overspill, why-stale-evidence, asupersync-cancel-leak` (plus universal terms: `rejected, reverted, abandoned, slower, regressed, within noise, keep gate`).

**Crash boundaries:** project-specific. For `eidetic_engine_cli` (SQLite-backed storage):
- `BeforeBeginImmediate` — before the writer's BEGIN IMMEDIATE
- `BeforeCommit` — body executed, COMMIT not yet sent
- `BetweenCommitAndFsync` — COMMIT sent, OS not yet fsync'd
- `BeforeWalCheckpoint` — fsync done, WAL checkpoint pending
- `AfterCheckpoint` — checkpoint done

Plus 2 long-running-procedure boundaries:
- `MidIndexRebuild` — mid index-rebuild batch
- `MidContextStreamSpill` — mid context-stream spill-to-disk

**Bit-exact vs ULP boundary:** typically bit-exact (greenfield rarely needs ULP tolerance unless Numerical-class adjacent — e.g., projects with custom embedding kernels import ML-class ULP policy).

**Seed contract:** `derive_entry_seed(corpus_entry_id) -> u64`; never `rand::random()`; never `thread_rng()`. Per [pattern:40-METAMORPHIC-TRANSFORMS § SeedContract](../patterns/40-METAMORPHIC-TRANSFORMS.md).

**Behavior-preserving verifier:** insta-snapshot equality on every emitted format AND round-trip identity on every (encode, decode) pair. `selections=` byte-identical analog: per-output-format byte-identical hash.

**Concurrency-honesty rule:** project-specific. For `eidetic_engine_cli`: "every WriteApi call uses BEGIN IMMEDIATE on the writer connection; reader connections may not call BEGIN IMMEDIATE; the `concurrent_mode_default_guard.txt` analog is `single_writer_invariant_guard.txt` dropped into every artifact lane stating which (writer | reader) connection mode was in effect."

**Certification-bundle shape:** same as other classes per [`methodology/CERTIFICATION.md`](../methodology/CERTIFICATION.md). The bundle additionally embeds the spec SHA-256 + the property-suite version so an external auditor can reproduce the certification.

**Cross-references:**
- [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) — full meta-pattern.
- [`case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md) — concrete worked example.
- [`subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md) — Phase 3 greenfield variant.
