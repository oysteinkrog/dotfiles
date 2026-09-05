# pattern:230-ENABLED-LEVEL-TRACING-GATE

## What

Gate every `tracing::debug!` / `tracing::trace!` / `tracing::info!` call that has **non-trivial arguments** behind `if tracing::enabled!(Level)`. Tracing's macros short-circuit when no subscriber is listening, but they short-circuit *after* evaluating the argument expressions. A `format!("...")`, an `env::var(...)`, a method call that allocates — all run on every call, subscriber or no. Wrapping the macro in an `enabled!` guard skips the argument evaluation entirely when the level is filtered out.

## Why

> "Gate non-trivial tracing arguments behind `if tracing::enabled!(Level)` to avoid argument evaluation when no subscriber." — CC.md §59 (verbatim)

Failure mode prevented: *invisible per-call overhead from "debug-only" logging*. The motivating case in FrankenSQLite (planner perf, 2026-05-20) was a debug-trace ceremony with **3× `env::var` calls** inside the argument list. `env::var` allocates a `String`, acquires a process-wide lock, and walks the environ table — for every planner call, in a release build, regardless of subscriber state. The cost was hidden because the log line was conditionally formatted but unconditionally *prepared*.

The gain on a workload that calls the planner heavily was extraordinary because the cost compounded per-call.

## Where in FrankenSQLite

- The planner trace ceremony (commit `f43902e2`, bead `bd-mziaw`)
- The general pattern: anywhere `tracing::debug!` / `trace!` is in a tight loop
- Date: planner perf pass, 2026-05-20

## Verbatim shape

Before (3× `env::var` in the argument list, runs on every call):

```rust
tracing::debug!(
    target: "planner.cost",
    cost = compute_full_cost(&plan),
    env_a = std::env::var("FSQLITE_PLANNER_A").unwrap_or_default(),
    env_b = std::env::var("FSQLITE_PLANNER_B").unwrap_or_default(),
    env_c = std::env::var("FSQLITE_PLANNER_C").unwrap_or_default(),
    plan = ?plan,
    "planner step"
);
```

After (the entire argument-evaluation block is dead code unless DEBUG is on):

```rust
if tracing::enabled!(tracing::Level::DEBUG) {
    tracing::debug!(
        target: "planner.cost",
        cost = compute_full_cost(&plan),
        env_a = std::env::var("FSQLITE_PLANNER_A").unwrap_or_default(),
        env_b = std::env::var("FSQLITE_PLANNER_B").unwrap_or_default(),
        env_c = std::env::var("FSQLITE_PLANNER_C").unwrap_or_default(),
        plan = ?plan,
        "planner step"
    );
}
```

## Measurement proof (verbatim)

**4-10× on `oltp_cost`** (commit `f43902e2`, bead `bd-mziaw`).

The wide range (4-10×) reflects that the win depends on how often the planner runs in the workload; in pure planner microbenches the multiplier is closer to 10×, in mixed OLTP it's closer to 4×.

## Spot the shape

In an unfamiliar codebase:

1. `rg 'tracing::(debug|info|trace)!' --type rust` — every match is a candidate.
2. For each, audit the argument list. Red flags: `format!`, `env::var`, any method call that allocates (`.to_string()`, `.collect()`), any function call with non-zero cost.
3. Check call frequency: a debug-log call inside a per-step or per-request hot path with non-trivial args is the classic shape.
4. `cargo asm` on the function shows the argument-evaluation code paths exist in the compiled binary — they're not optimized away just because the level is filtered.

If any of those hold, wrap the macro in `if tracing::enabled!(...)`.

## Per-class transferability

| Class | Common non-trivial-arg trace sites |
|---|---|
| **SQL** | Planner trace ceremony, VDBE step tracing, WAL-frame trace; anywhere a `format!` or `env::var` is in an argument list |
| **RESP** | Per-command tracing with argument formatting; slow-log entry construction (`format!("{:?}", args)`); cluster-redirect tracing |
| **Numerical** | Ufunc selection tracing; broadcast-shape tracing with `format!("{:?}", shape)`; dtype-promotion tracing |
| **ML** | Op-dispatch tracing with tensor-spec formatting; autograd-tape tracing with op-name formatting; CUDA-stream tracing with device-pointer dumps |
| **HTTP** | Per-request tracing with header serialization; route-match tracing with full URI logging; middleware-traversal tracing with span-context dumps |

## Composition

- Pairs with [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — the win was attributed to the planner-step frame on the `oltp_cost` workload at MT8-equivalent concurrency.
- Pairs with [pattern:235-MOVE-NOT-CLONE](235-MOVE-NOT-CLONE.md) — both eliminate per-call allocation; this one targets argument evaluation, that one targets `.clone()`.
- Pairs with [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) — the 4-10× win is easy to claim and hard to justify; the profile-pack baseline_profile must show the trace overhead.
- Pairs with [pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md) — debug builds do filter aggressively but release-perf benches with `INFO` subscriber will still pay; the gate is correct for all builds.

## Pitfalls

- **Trusting the macro's own short-circuit.** `tracing::debug!` *does* short-circuit publication, but the macro expansion evaluates the arguments first. The whole point of `enabled!` is to skip that.
- **Wrapping the macro with `if cfg!(debug_assertions)`.** That's a compile-time gate that removes the macro from release builds entirely; the runtime `enabled!` gate is what allows dynamic subscriber attachment in production.
- **`enabled!` with wrong level.** `enabled!(Level::INFO)` doesn't match a `debug!` macro; the level passed to `enabled!` must match (or be lower-priority than) the macro's level. Easier shape: `enabled!(Level::DEBUG)` + `debug!(...)`.
- **Forgetting the win is workload-dependent.** Microbench wins may be 10×; broad-workload wins may be 1.5×. The keep-gate rule still applies: both gates must move.
- **Per-class trap (HTTP): per-request tracing is often *required* for SLO observability.** Don't blindly gate it; instead, move the expensive formatting into a `tracing::field::display(fn || format!(...))` (lazy evaluation) so the format runs only on subscribe.
- **Adding `enabled!` to a trace that already has cheap args.** The gate adds a branch; for cheap-arg traces it's pessimization. The rule is "non-trivial arguments only".
- **Forgetting to remove the `env::var` calls entirely.** If the env vars are read once at session start, cache them in a `OnceLock` (pattern:240) and the trace's argument becomes a cheap load. Layered fix wins more.
