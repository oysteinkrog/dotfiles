# pattern:245-CACHE-KEY-EVICTION-AUDIT

## What

Audit every cache in the codebase against a simple two-list discipline:

1. **For every cache key**, list which inputs the cached value actually depends on.
2. **For every cache invalidation**, list which inputs should invalidate it.
3. **Any input in (2) not in (1)** → over-eager invalidation (Pattern 10 candidate; throws away valid cache entries).
4. **Any input in (1) not in (2)** → stale-cache bug (returns wrong answer).

The gap between the two lists *is* the bug. The motivating fix in FrankenSQLite was the prepared-statement cache: the key included `db_generation`, but the bytecode only depends on the *schema*. Every COMMIT bumped `db_generation`, evicting the entire prepared-statement cache despite the schema being unchanged. The fix was to **separate the keys**: bytecode-cache key (schema-bound) vs data-cache key (generation-bound).

## Why

> "Audit cache-key design: *for every cache key, list which inputs it depends on; for every cache invalidation, list which inputs should invalidate it; gap = bug*." — CC.md §62 (verbatim)

Failure mode prevented: *catastrophic invalidation of a hot cache by an unrelated event*. The prepared-statement cache was the canonical example: a workload that did 90% reads + 10% writes was paying for full re-compilation of every prepared statement after each commit, because the writer bumped a generation counter that the cache key naively included. The cache "worked" in the sense that hits were fast, but the hit rate was near-zero in the realistic workload.

This is the most architectural of the 10 patterns: it requires understanding the *semantics* of the cached data, not just the mechanics of caching.

## Where in FrankenSQLite

- The prepared-statement cache (bytecode + execution state)
- Schema-bound vs generation-bound key separation
- Contribution: **MT 8t fs_wps 778 → 5458 (7.0x)** and **1t fs_wps 88k → 305k (3x+)** (jointly with pattern:240 OnceLock cluster)
- (Source under `crates/fsqlite-core/src/connection.rs` and `crates/fsqlite-vdbe/src/`.)

## Verbatim shape

Before (one key, over-eager invalidation):

```rust
struct PreparedCache {
    // Key includes db_generation → every COMMIT invalidates
    entries: HashMap<(SqlText, DbGeneration), PreparedStmt>,
}

impl Connection {
    fn commit(&mut self) {
        self.db_generation += 1;
        // self.prepared_cache implicitly invalidated because the key changed
    }
}
```

After (two keys, separated by dependency):

```rust
struct BytecodeCache {
    // Bytecode depends on SCHEMA only — survives commits
    entries: HashMap<(SqlText, SchemaHash), Bytecode>,
}

struct DataCache {
    // Data depends on generation — invalidates on commit
    entries: HashMap<(QueryHash, DbGeneration), CachedResult>,
}

impl Connection {
    fn commit(&mut self) {
        self.db_generation += 1;
        // bytecode_cache survives; data_cache invalidates per its key
    }
}
```

## Measurement proof (verbatim)

| Metric | Before | After | Speedup |
|---|---|---|---|
| MT 8t fs_wps | 778 | 5458 | **7.0x** |
| 1t fs_wps | 88k | 305k | **3x+** |

(Contributed jointly with pattern:240 OnceLock-cached derivation.)

## The audit rule (mandatory before declaring a cache "correct")

> "For every cache key, list which inputs it actually depends on; for every invalidation, list which inputs should invalidate it; gap = bug."

Concretely, for each cache in the codebase, fill in a 4-row table:

```
Cache name:       PreparedCache
Cached value:     PreparedStmt (bytecode + execution scratch)
Key components:   SqlText, DbGeneration   ← LIST 1: what the key includes
Actual deps:      SqlText, SchemaHash      ← LIST 2: what the cached value really depends on
Gap analysis:
  In key but not deps:  DbGeneration   → over-eager (Pattern 10 fix: remove)
  In deps but not key:  SchemaHash     → stale-cache bug (Pattern 10 fix: add)
```

Either gap is a bug. Both gaps in the same cache (as in the prepared-statement case) is a *structural* bug requiring key separation.

## Spot the shape

In an unfamiliar codebase:

1. `rg 'HashMap|LruCache|moka::' --type rust` — every cache is a candidate.
2. For each, find the key construction and the invalidation sites.
3. For each cached value, trace back: what does it functionally depend on? Compare to the key.
4. Profile shape: if the cache exists but the hit rate is near-zero under a realistic workload, the audit usually finds either a wrong key or wrong invalidation.
5. Workload shape: a write-heavy workload that has high cache miss rate on what should be a read cache is suspicious.

## Per-class transferability

| Class | Common cache sites where the audit pays off |
|---|---|
| **SQL** | Prepared-statement caches; plan caches; schema caches; analyzer-result caches; constraint-check caches |
| **RESP** | Cluster-slot caches (don't invalidate on key writes, only on CLUSTER reshape); sorted-set rank caches (don't invalidate on unrelated key writes); lua-script SHA caches (don't invalidate on SCRIPT LOAD) |
| **Numerical** | Broadcast-shape caches (don't invalidate on dtype changes); ufunc-loop selection caches (don't invalidate on shape changes); BLAS-call caches |
| **ML** | JIT-graph caches — **most common Pattern 10 site in PyTorch/JAX ports** (cache key may include scoping that bytecode doesn't actually depend on); autograd-replay caches; kernel-arg caches |
| **HTTP** | OpenAPI-schema caches (invalidate only on schema reload, not on per-request mutation); route-match caches (don't invalidate on header changes); CORS-preflight caches (don't invalidate on body changes) |

## Composition

- Pairs with [pattern:240-ONCELOCK-DERIVATION-CACHE](240-ONCELOCK-DERIVATION-CACHE.md) — these two formed the 7× cluster. OnceLock without correct keying is this pattern's problem; correct keying without caching is incomplete optimization.
- Pairs with [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — the 7× win was attributed to MT 8t writes-per-second; the discovery came from realizing the WAL-write throughput was capped by cache misses, not by I/O.
- Pairs with [pattern:250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md) — separating the keys preserves behavior iff the two lists genuinely don't overlap; the proof is the audit table.
- Pairs with [pattern:115-CLOSURE-WAVE](115-CLOSURE-WAVE.md) — the audit is a closure-wave over the universe of caches; enumerate first, fill the table second.

## Pitfalls

- **Skipping the audit because "the cache works fine."** A cache with a high *hit rate* on cold workloads can have near-zero hit rate on realistic workloads; the audit catches the structural issue independent of the observed metric.
- **Auditing only one cache.** Pattern 10 is a *codebase-wide audit*. Every cache deserves the 4-row table.
- **Adding inputs to the key "to be safe."** Conservative keys reduce hit rate; the audit is to *remove* unnecessary inputs, not add them.
- **Per-class trap (ML): JIT-graph caches in PyTorch ports often include the autograd-context fingerprint when they shouldn't (compiled forward graph is autograd-context-independent).** The result is cache-busting on every backward pass.
- **Per-class trap (RESP): cluster-slot caches sometimes include client-id when they shouldn't (slot mapping is global, not per-client).** Multi-tenant deployments suffer the cost.
- **Per-class trap (HTTP): OpenAPI schema caches sometimes include header-version when they shouldn't (schema is HTTP-version-independent).** A mixed HTTP/1.1+HTTP/2 deployment thrashes the cache.
- **Treating "cache invalidation" as just `cache.clear()`.** Selective invalidation (per-key, per-prefix) is often the correct fix; nuking the cache is the wrong instrument.
- **Believing the cache is correct because tests pass.** Tests typically exercise individual queries; the bug is in the *aggregate* hit rate under realistic mix.
- **Adding the cache after the optimization.** Cache *adds* complexity; the audit must precede caching, not follow it. Cache only what the audit shows would benefit; the table is the gate.
