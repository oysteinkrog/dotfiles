# bench-author

> Phase 5 • Build `comprehensive_bench.rs` skeleton (or class-equivalent) + focused narrow benches; one instance per workload family.

## Inputs
- `<workspace>/phase0_project_class.json` (selects axis enumeration).
- Workload family (`<family>`, e.g., `oltp`, `bulk_dml`, `aggregation`, `set_ops`, `pubsub`, `matmul`, `autograd`, `request_routing`) — passed as argument.
- Existing crate path for the bench bin (typically `crates/<project>-e2e/src/bin/comprehensive_bench.rs` + `benches/`).

## Deliverables
- `<target>/crates/<project>-e2e/src/bin/comprehensive_bench.rs` (or class-equivalent) with the six verbatim timing constants + `measure()` + `measure_with_teardown()` + the three orthogonal axes + the identical-PRAGMAs/config block + the six weighted scenario categories.
- Focused narrow benches (one per workload family) under `crates/<project>-e2e/benches/<family>.rs`.
- `<target>/.bench-history/<family>.latest.json` initial baseline.
- `<workspace>/phase5_bench_<family>.md` documenting workload definition, scenarios covered, hot-path counters wired, expected ratio range.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase5-bench-<family>`
- **Reservations needed:** `tool://comprehensive-bench::<family>` (TTL 180m), `resource://bench-host` (TTL 90m).
- **Lane:** cc_2 (performance).

## Verbatim Prompt

You are the bench author for workload family `<family>`. Wire the comprehensive-bench skeleton + the focused per-workload bench for this family.

**Six verbatim timing constants** (must appear exactly):

```rust
const WARMUP_ITERS: usize = 2;
const MIN_ITERS:    usize = 3;
const MAX_ITERS:    usize = 10;
const TARGET_DURATION: Duration = Duration::from_secs(5);
```

`measure()` body (verbatim shape):

```rust
fn measure<F>(label: &str, f: F) -> Measurement where F: Fn() -> () {
    for _ in 0..WARMUP_ITERS { f(); }              // discarded
    let start_total = Instant::now();
    let mut times = vec![];
    for iter in 0..MAX_ITERS {
        let start = Instant::now();
        f();
        let elapsed = start.elapsed();
        times.push(elapsed);
        if iter >= MIN_ITERS && start_total.elapsed() >= TARGET_DURATION { break; }
    }
    Measurement::from_samples(label, times)  // median, mean, p95, p99, stddev, cv_pct, rows/sec, us/row
}
```

`measure_with_teardown()` — **CRITICAL:** `start.elapsed()` is captured BEFORE `teardown()` runs. The teardown call is OUTSIDE the timed window.

**Three orthogonal axes:**
1. Workload size: `[100, 1_000, 10_000, 100_000]` (quick drops 100K).
2. Value shape: Tiny (1 col) / Small (3 cols ≈30B) / Medium (6 cols ≈180B) / Large (10 cols ≈600B with overflow). For non-SQL classes, adapt per `../references/taxonomy/PROJECT-CLASSES.md`.
3. Concurrency: `[2, 4, 8]` in comprehensive; `[1, 2, 4, 8, 16]` in mt-mvcc-equivalent.

**Identical configuration block:** Both engines get byte-identical configuration. For SQL-class this is the 30-line PRAGMA block at `comprehensive_bench.rs:502–541`. For RESP-class: identical client config (RESP version, pipeline depth, timeouts). For ML-class: identical dtype + device + RNG seed. Write the block; do NOT rely on verbal convention.

**Six weighted scenario categories** (default weights; per-class may override):
```
ReadSingle         0.35
ReadAggregate      0.15
WriteSingle        0.30
WriteBulk          0.10
ConcurrentWriters  0.05
MixedOltp          0.05
```
CI regression gate keys off `per_category_weighted.score`.

**`release-perf` profile** (mandatory; never `--release`):
```toml
[profile.release-perf]
inherits = "release"
opt-level = 3
lto = "thin"
codegen-units = 1
debug = "line-tables-only"
strip = false
```
With `RUSTFLAGS = "-C force-frame-pointers=yes"`.

Drop `concurrent_mode_default_guard.txt` (or class-equivalent: `RESP_VERSION=3`, `CUDA_DEVICE_COUNT=N`, `DETERMINISTIC_ALGS=true`) into every artifact lane. Emit the JSON v3 self-describing report (`detected_environment`, `summary`, `ci_regression_gate`, `sections[]`). Commit the first run to `.bench-history/<family>.latest.json`.

Document the workload definition, scenarios, hot-path counters wired, and expected ratio range in `phase5_bench_<family>.md`.

## Exit Criteria
- `cargo build --profile release-perf --bin comprehensive_bench` succeeds.
- A 5-minute smoke run produces JSON v3 with `summary.total_scenarios > 0` and `per_category_weighted.score` populated.
- `.bench-history/<family>.latest.json` committed.
- `cv_pct` populated for every measurement; any scenario with `cv_pct > 5` flagged in `phase5_bench_<family>.md` as noise-prone.
- The `concurrent_mode_default_guard.txt` (or equivalent) proof file appears in the artifact lane.

## References
- [PHASES.md § Phase 5](../references/PHASES.md)
- [tooling/BENCH-TOOLCHAIN.md](../references/tooling/BENCH-TOOLCHAIN.md)
- [methodology/KEEP-GATE-RULES.md](../references/methodology/KEEP-GATE-RULES.md)
- [taxonomy/PROJECT-CLASSES.md](../references/taxonomy/PROJECT-CLASSES.md)
