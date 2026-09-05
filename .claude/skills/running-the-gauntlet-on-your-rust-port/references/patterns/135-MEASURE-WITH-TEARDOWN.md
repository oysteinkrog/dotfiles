# Pattern 135 — Measure With Teardown

## What

For scenarios where each iteration mutates state that must be reset before the next iteration (DELETE benches, table-truncate benches, cache-warm benches), the timing function takes *two* closures — the measured `f()` and an *unmeasured* `teardown()`. The crucial rule is that `start.elapsed()` is captured **before** `teardown()` runs. Population, cleanup, table-drop, and connection-reset never live inside the timed window. Violating this rule produces "free wins" that vanish under realistic load because the speedup measured was teardown cost, not work cost.

## Why

> "The teardown call is *outside* the timed window — `start.elapsed()` is captured *before* `teardown()` runs." — CC.md line 74 (verbatim, MINING-3 §1.3)

Failure mode prevented: a "DELETE optimization" whose 30% win came from the table-recreate being cheaper after the change, not the DELETE itself. The measured value rolls up into the broad bench geomean; the keep gate passes; production sees no improvement because production doesn't recreate the table on every DELETE.

## Where in FrankenSQLite

- `crates/fsqlite-e2e/src/bin/comprehensive_bench.rs` — the shared `measure_with_teardown()` function.
- `crates/fsqlite-e2e/src/bin/perf_update_delete.rs` — primary consumer; UPDATE/DELETE rows + reset table between iters.
- Any bench whose scenario mutates DB state should consume this variant, not the plain `measure()`.

## Verbatim shape

```rust
fn measure_with_teardown<F, T>(label: &str, f: F, teardown: T) -> Measurement
where F: Fn() -> (), T: Fn() -> () {
    for w in 0..WARMUP_ITERS { f(); teardown(); }
    let start_total = Instant::now();
    let mut times = vec![];
    for iter in 0..MAX_ITERS {
        let start = Instant::now();
        f();
        let elapsed = start.elapsed();  // ← BEFORE teardown()
        times.push(elapsed);
        teardown();                      // ← OUTSIDE the timed window
        // ... same exit as measure() ...
    }
}
```

### The discipline (verbatim)

CC.md line 74: "The teardown call is *outside* the timed window — `start.elapsed()` is captured *before* `teardown()` runs."

### Warmup also calls teardown

Note the warmup loop: `for w in 0..WARMUP_ITERS { f(); teardown(); }`. Warmup must leave the system in the same state the measured iters expect, so warmup also resets between iters. The warmup `teardown` is part of warmup cost (discarded along with the measurement); the measured `teardown` is excluded by the placement of `start.elapsed()`.

### `Fn` not `FnMut`

Both `F` and `T` are `Fn` — the closures must be re-entrant. State mutation lives in interior mutability or in the captured environment via `&Connection` / `&Pool` / `&Arc<Mutex<...>>`. This forces the scenario author to be explicit about what state is shared across iterations.

## Per-class instantiation

| Class | When teardown-outside applies | Typical `teardown` body |
|---|---|---|
| SQL | DELETE, UPDATE-where-affects-many, INSERT-then-cleanup, CREATE-then-DROP, schema-evolution benches | `DELETE FROM bench_t; VACUUM` or `DROP TABLE; CREATE TABLE` |
| RESP | DEL after SET-many, FLUSHDB between iters, AOF rewrite, RDB save | `FLUSHDB` or `redis-cli -n 0 FLUSHALL` |
| Numerical-Python | Allocator-pressure tests; explicit `gc.collect()`; releasing array references | `del large_arr; gc.collect(); np.empty(...)` reset |
| ML-System | Optim-step benches (zero gradients between iters), DataLoader iteration with `next()` exhausting an iterator | `optimizer.zero_grad(); model.reset_buffers(); torch.cuda.empty_cache()` |
| HTTP-Protocol | Connection-pool reset, session-cookie clear, in-memory store flush, OpenAPI cache invalidation | `pool.clear(); session.cookies.clear(); app.openapi_schema = None` |

For *idempotent* scenarios (a pure SELECT against immutable data, a UFUNC over a re-used array), use plain `measure()`; teardown is unnecessary and the extra function call is noise.

### When `setup` (rather than teardown) is needed

If state must be *built* before each iter (not torn down after), the symmetric pattern is `setup` *outside* the timed window before `f()`:

```rust
for iter in 0..MAX_ITERS {
    setup();             // ← OUTSIDE
    let start = Instant::now();
    f();
    let elapsed = start.elapsed();
    times.push(elapsed);
    // no teardown if setup is destructive enough
}
```

Most scenarios prefer teardown-outside (state lives across iters; reset after) because it makes the warmup case symmetric with the measured case.

## Composition

- [pattern:125-COMPREHENSIVE-BENCH](125-COMPREHENSIVE-BENCH.md) — `measure_with_teardown` is the same module as `measure`; both share the six timing constants.
- [pattern:130-FOCUSED-BENCHES](130-FOCUSED-BENCHES.md) — DML and write-heavy focused benches *always* use the teardown variant.
- [pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md) — frame-pointer-preserving profile is required so a flamegraph captured during one iter can be matched against the timer's measurement; the iteration boundary must be visible in the flamegraph.
- [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — when attributing a regression to a specific frame, ensure the flamegraph's sampling window aligned with the timed window, not the teardown.
- [pattern:170-ROBUST-REGRESSION-DETECTOR](170-ROBUST-REGRESSION-DETECTOR.md) — a regression masked by teardown-in-timer presents as bizarre cv_pct or non-monotone progression; the detector's MAD-based logic catches it as an outlier, not a regression — that's the bug. Always audit teardown placement before chasing a "weird" regression signal.

## Pitfalls

- **Calling `f()` then `start.elapsed()` *after* `teardown()`** — the bug this pattern exists to prevent. Easy to introduce when refactoring the loop body; always compare against the verbatim shape.
- **Putting both `f()` and `teardown()` inside one closure to "simplify"** — defeats the separation; the timer can't tell where one ends and the other begins.
- **Using `FnOnce` to allow `move` semantics in teardown** — must be `Fn` because the loop runs multiple times. State that needs `move` should live in the captured environment (`Arc<Mutex<...>>` or `RefCell`).
- **Skipping warmup teardown** — warmup with stale state from a prior run is not warmup, it's a measurement of a different scenario.
- **Letting `teardown()` allocate the next iteration's inputs** — that's setup, not teardown. Use a separate `setup()` closure outside the timer, or warm a pool once at scenario start.
- **Reporting `total_elapsed` (includes teardowns) instead of `Measurement.median`** — `total_elapsed` is only used for `TARGET_DURATION` budgeting; the timing values in `Measurement` exclude teardown by construction. Reporting wall time as "the result" reintroduces the bug.
- **Symmetric anti-pattern: `setup()` inside the timer** — same failure mode mirrored. Setup outside; iteration boundary clean; timer measures only `f()`.
- **Teardown that triggers async work which completes *during* the next iter** — e.g., `DELETE` that queues a background vacuum. The vacuum then steals CPU during the next measurement. Pin async work to complete before the next `start.elapsed()` begins (poll-to-completion or join the worker).
