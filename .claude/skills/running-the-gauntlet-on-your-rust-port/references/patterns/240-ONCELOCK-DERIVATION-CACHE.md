# pattern:240-ONCELOCK-DERIVATION-CACHE

## What

Cache deterministic derivations (parsed views, compiled regexes, constant tables, schema-bound bytecode) behind a `OnceLock<T>`. The derivation runs on first access and is reused for every subsequent access in the same process. The conditions for `OnceLock` to be correct: (a) the derivation is **expensive** but **deterministic** — same input always yields the same output; (b) the result is `Send + Sync` so the OnceLock can be shared across threads; (c) the derivation is **pure** — no side effects, no observation of mutable state.

## Why

> "Cache deterministic derivations (parsed views, compiled regexes, constant tables) behind `OnceLock<T>`." — CC.md §61 (verbatim)

Failure mode prevented: *recomputing a pure function on every hot call*. The motivating case in FrankenSQLite was a `VdbeProgram` derivation cached behind `OnceLock` (2026-04-23). Before the cache, the derivation ran on every commit; after, it ran once per process. This was part of a cluster of fixes (joint with pattern:245) that took the MT 8t throughput from **778 → 5458 (7.0x)**.

`OnceLock` is the right primitive (over `lazy_static!`, `once_cell::Lazy`, manual `Mutex<Option<T>>`) because: it's in the std library since 1.70; it's zero-allocation for the lock state; it's lock-free on the fast path after initialization; and it composes with `Send + Sync` cleanly.

## Where in FrankenSQLite

- `VdbeProgram::OnceLock` — cached the bytecode derivation
- Date: 2026-04-23
- Cluster contribution: MT 8t throughput 778 → 5458 (7.0x), jointly with pattern:245
- (Source under `crates/fsqlite-vdbe/src/`.)

## Verbatim shape

Before (deterministic derivation runs every call):

```rust
impl Connection {
    fn execute(&self, sql: &str) -> Result<()> {
        let program = compile_to_vdbe(sql)?;  // ← runs every time
        self.run(program)
    }
}
```

After (derivation lifted to a `OnceLock`-cached field):

```rust
struct VdbeProgram {
    bytecode: OnceLock<Bytecode>,
    source: String,
}

impl VdbeProgram {
    fn bytecode(&self) -> Result<&Bytecode> {
        self.bytecode.get_or_try_init(|| compile_to_vdbe(&self.source))
    }
}

impl Connection {
    fn execute(&self, program: &VdbeProgram) -> Result<()> {
        let bytecode = program.bytecode()?;  // ← first call compiles; subsequent are O(1) load
        self.run(bytecode)
    }
}
```

## Measurement proof (verbatim)

Part of the cluster taking **MT 8t throughput from 778 → 5458 (7.0x)** (jointly with pattern:245 cache-key audit).

## Conditions (mandatory before applying)

- **Expensive derivation.** OnceLock has its own runtime cost (atomic load on every access). If the derivation is itself cheap (a few ns), the cache adds overhead with no win.
- **Deterministic.** Same input → same output. If the derivation observes time, env vars, RNG, or other mutable global state, the cache is wrong (returns stale).
- **`Send + Sync`.** Required for `OnceLock<T>` to be `Sync`. If `T: !Send`, use `thread_local!` instead.
- **Pure.** No side effects on derivation. If the derivation registers callbacks, allocates external resources, or fires metrics, those happen only once — usually wrong.

## Spot the shape

In an unfamiliar codebase:

1. `rg 'static .* Lazy<' --type rust` or `rg 'lazy_static' --type rust` — existing examples reveal the team's idiom for cached derivations.
2. Look for *missing* OnceLocks: a function that takes a deterministic input and produces a complex output, called from a hot path, with no caching. Common: regex compilation in a parser, AST → bytecode compilation, schema parsing, type-coercion tables.
3. Profile attribution: the derivation function shows up in the top 20 self-time frames; the input is invariant across calls.
4. Per-instance derivation that's actually per-process: if every `Connection` derives the same constant table, the OnceLock can be `static` not per-instance.

## Per-class transferability

| Class | Common deterministic-derivation OnceLock sites |
|---|---|
| **SQL** | Compiled bytecode programs (VdbeProgram); parsed schema views; regex caches for LIKE/GLOB; type-affinity coercion tables; pragma-default tables |
| **RESP** | Lua script bytecode cache; pre-compiled cluster-slot tables; sorted-set comparator caches; pattern-match (KEYS pattern) compiled glob caches |
| **Numerical** | Compiled ufunc loops per dtype; einsum-string parse cache; broadcast-strategy table; SIMD-capability detection (call once at process start) |
| **ML** | Compiled JIT graphs; AOT-compiled model fragments; backend-capability detection (CUDA version, MPS availability — call once); per-op kernel registry |
| **HTTP** | Compiled OpenAPI schemas; compiled route-match tries; compiled middleware chains; compiled regex matchers for path validators |

## Composition

- Pairs with [pattern:245-CACHE-KEY-EVICTION-AUDIT](245-CACHE-KEY-EVICTION-AUDIT.md) — together these formed the 7× MT 8t cluster. OnceLock without correct invalidation key is pattern:245's problem; pattern:245 without OnceLock is incomplete caching.
- Pairs with [pattern:235-MOVE-NOT-CLONE](235-MOVE-NOT-CLONE.md) — once a derivation is OnceLock-cached, consumers can borrow `&T` instead of cloning the result.
- Pairs with [pattern:230-ENABLED-LEVEL-TRACING-GATE](230-ENABLED-LEVEL-TRACING-GATE.md) — caching `env::var` reads in a `OnceLock<String>` makes the trace-gate target trivial.
- Pairs with [pattern:250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md) — the determinism condition *is* the isomorphism proof: `compile(x) == compile(x)` for all x.

## Pitfalls

- **OnceLock-ing a non-deterministic derivation.** If `compile_to_vdbe(sql, &self.schema)` depends on a *mutable* schema, OnceLock caches the result at one schema version and returns the stale value when the schema changes. This is exactly the bug pattern:245 fixes — the cache key was wrong.
- **OnceLock-ing per-instance when per-process would do.** A `OnceLock<RegexSet>` on a `Connection` runs the regex compilation per-connection; a `static REGEXES: OnceLock<RegexSet>` runs it once per process.
- **Using `Mutex<Option<T>>` instead of `OnceLock`.** Mutex acquires on every read; OnceLock is lock-free on the fast path after init.
- **`OnceLock::get_or_init` with a closure that can panic.** A panic during init leaves the cell poisoned in some senses; use `get_or_try_init` with `Result` for fallible derivations.
- **Per-class trap (ML): JIT-graph OnceLock interacts with autograd capture; the graph may be valid for one autograd context but not another.** The cache key needs to include the autograd-context fingerprint.
- **Per-class trap (RESP): Lua-script SHA cache must invalidate on `SCRIPT FLUSH`.** OnceLock alone is wrong; the cell is per-SHA, with the SHA as the cache key, and the registry of cells is what `SCRIPT FLUSH` clears.
- **Wrapping a hot-path computation in OnceLock when it's actually parameterized.** If `compile_to_vdbe(sql)` is called with thousands of distinct `sql` strings, a single `OnceLock` caches only the first; what's needed is a keyed cache (LRU or unbounded), with the cache-key audit from pattern:245.
- **Forgetting that `OnceLock` doesn't drop the inner value until the OnceLock itself drops.** For per-process statics, the inner value lives forever; for per-Connection OnceLocks, the inner value lives until the Connection drops.
