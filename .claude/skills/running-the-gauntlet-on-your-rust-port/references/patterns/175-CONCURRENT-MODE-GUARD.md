# Pattern 175 — Concurrent-Mode Guard

## What

Every artifact lane (every bench run, every profile capture, every conformance suite invocation) drops a small text guard file alongside its primary output that records the project's feature-defining mode-default state at the moment of capture. For FrankenSQLite the file is `concurrent_mode_default_guard.txt` containing `CONCURRENT_MODE_DEFAULT=true`; for Redis it's `resp_version_guard.txt`; for Torch it's `cuda_device_guard.txt`. The guard prevents the "silently disabled" failure mode where a feature flag the bench depends on is toggled off in some build, the bench numbers look unfamiliar, and nobody notices for weeks because the bench's primary output looks the same shape.

## Why

Feb 2026 an agent silently disabled concurrent mode on FrankenSQLite; the project didn't notice until pass-over-pass gate flipped (no concurrent mode = different bench semantics). The proof file, part of the artifact contract, prevents this silent regression.

Failure mode prevented: a flag toggled in a CI config (or in a developer's local `~/.cargo/config.toml`) silently changes what the bench is measuring; the *number* still looks plausible (just different), the ratchet absorbs the drift, and weeks later the project notices it's been measuring serial-mode performance while claiming concurrent-mode wins.

## Where in FrankenSQLite

- `concurrent_mode_default_guard.txt` dropped into every `artifacts/{bead_id}/...` lane.
- Required-output declaration in `crates/fsqlite-e2e/src/bin/comprehensive_bench.rs`; bench refuses to exit cleanly if guard write fails.
- Verified by `scripts/run-bench-matrix.sh` post-run and by `scripts/apply-ratchet.sh` pre-comparison.

## Verbatim shape

```
CONCURRENT_MODE_DEFAULT=true
GIT_SHA=<sha>
TIMESTAMP=<ISO-8601>
```

### The Feb 2026 incident

A code change shifted the default of `BEGIN CONCURRENT` mode from `on` to `off` for one bench binary; the JSON output looked normal (no schema version bump, scenario rows identical shape); the per-category scores looked slightly different but within the 5% pass-over-pass band; three weeks of perf work was based on serial-mode measurements before someone wondered why MT8 looked weirdly flat. The guard file is the artifact that would have caught it on day one: a single grep across the artifact lane reveals `CONCURRENT_MODE_DEFAULT=false` and the gate rejects.

### Why text, not embedded JSON

The guard is a *separate file* (not just an embedded field) for three reasons:
1. **Independent existence as evidence** — a missing guard file is a different signal than a JSON with a missing field. `ls artifacts/{bead_id}/*.txt` is a one-line audit.
2. **Shell-greppable** — `grep -r CONCURRENT_MODE_DEFAULT=true artifacts/` works without `jq`; CI shell steps can verify trivially.
3. **Per-lane locality** — the file lives *with* the artifact it guards; copying or moving an artifact lane copies the guard.

### Fields beyond the mode default

The minimal three fields (`CONCURRENT_MODE_DEFAULT`, `GIT_SHA`, `TIMESTAMP`) are required; per-class extensions are encouraged:
- `CARGO_PROFILE=release-perf` (audit trail for [pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md)).
- `RUSTFLAGS=-C force-frame-pointers=yes` (frame-pointer audit).
- `HOST_ID=<cpu-model>__<kernel>__<mem-mb>` (for cross-host detection).
- `FEATURE_FLAGS=<list>` (for cargo-features drift).

## Per-class instantiation

| Class | Guard file | Required key | Typical extensions |
|---|---|---|---|
| SQL | `concurrent_mode_default_guard.txt` | `CONCURRENT_MODE_DEFAULT=true` | `WAL_DEFAULT=on`, `MVCC_DEFAULT=on`, `CACHE_SIZE_PAGES=-2000` |
| RESP | `resp_version_guard.txt` | `RESP_VERSION=3` | `AOF_DEFAULT=on`, `RDB_DEFAULT=on`, `MAXMEMORY_BYTES=…` |
| Numerical-Python | `numpy_simd_guard.txt` | `NUMPY_SIMD_FLAGS=avx2,avx512f` | `BLAS_THREAD_COUNT=8`, `PYTHONHASHSEED=0` |
| ML-System (Torch) | `cuda_device_guard.txt` | `CUDA_DEVICE_COUNT=8` | `CUDNN_VERSION=…`, `DETERMINISTIC_ALGORITHMS=true`, `CUDA_LAUNCH_BLOCKING=0` |
| ML-System (JAX) | `xla_device_guard.txt` | `JAX_PLATFORMS=cuda` | `JAX_ENABLE_X64=true`, `JAX_DEVICE_COUNT=8` |
| HTTP-Protocol | `runtime_flavor_guard.txt` | `TOKIO_FLAVOR=multi_thread` | `TOKIO_WORKER_THREADS=8`, `TLS_ENABLED=false`, `KEEPALIVE_SECS=60` |

Each class has *one* canonical guard file name; secondary guards may be added (e.g., a SQL project might drop both `concurrent_mode_default_guard.txt` and `wal_default_guard.txt` for paranoid coverage).

### Audit hook

`scripts/apply-ratchet.sh` runs a pre-comparison audit:

```bash
for lane in artifacts/{bead_id}/*; do
    grep -q "CONCURRENT_MODE_DEFAULT=true" "$lane"/concurrent_mode_default_guard.txt || \
        { echo "GUARD FAILURE: $lane"; exit 2; }
done
```

A missing or wrong-valued guard exits non-zero; the regression detector never runs on tainted artifacts.

## Composition

- [pattern:125-COMPREHENSIVE-BENCH](125-COMPREHENSIVE-BENCH.md) — comprehensive-bench produces the guard alongside its JSON.
- [pattern:130-FOCUSED-BENCHES](130-FOCUSED-BENCHES.md) — every focused bench produces its own guard in its own lane.
- [pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md) — `CARGO_PROFILE=release-perf` is one of the guard fields; mismatched profile is a guard failure.
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — the ratchet refuses to compare across runs whose guards disagree.
- [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — same-window enforcement uses guard timestamps as one of the four coordinates.
- [pattern:170-ROBUST-REGRESSION-DETECTOR](170-ROBUST-REGRESSION-DETECTOR.md) — detector skips samples whose guards differ from baseline guards.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — `blocked-by-base-gate` includes "guard file mismatch or missing."

## Pitfalls

- **Embedding mode default only in the JSON `detected_environment`** — JSON drift hides it; the standalone file is the explicit gate. Both is fine; standalone file is non-optional.
- **Hardcoding the guard contents at bench-binary compile time** — defeats the purpose if a *runtime* flag flips the mode after build. The bench must *read the actual runtime state* and write that, not a baked constant.
- **Guard file format that varies per-class arbitrarily** — adopt the `KEY=VALUE` line format universally; cross-class tooling can parse with one regex.
- **One guard file across many lanes** — copy means audit can't tell if one specific lane drifted. Each lane has its own.
- **Guard file written at process exit (`atexit` style)** — a crashed run produces a missing guard but the JSON might have been flushed mid-run; the gate sees JSON-without-guard and is confused. Write the guard *first*, before the timed work; the timed work can't proceed without confirmed guard.
- **CI runner with a different default than dev workstations** — bench results from the two are silently comparing apples to oranges. The guard makes this visible; without it the discrepancy goes unnoticed.
- **Guard file in `.gitignore` because "it's a generated artifact"** — fine, but it must be a *committed CI artifact* (uploaded as workflow artifact); otherwise reviewers can't audit.
- **No guard for "non-perf" runs (conformance, fuzz)** — they also depend on mode defaults; a fuzz run under serial mode finds different bugs than under concurrent. Guard *all* artifact lanes.
- **Guard contents include a Unix timestamp instead of ISO-8601** — humans can't read it without conversion; tooling can. Use ISO-8601 (`2026-05-22T14:02:13Z`) for both.
- **Mode default true vs false isn't checked, only logged** — the gate must *reject* on wrong default, not just record. Audit script: `grep -q EXPECTED_VALUE || exit 2`.
