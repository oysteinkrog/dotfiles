# The 10 Winning Optimization Patterns (+ MT8 Attribution Bonus)

> Glyph: `⊕` **Isomorphic-Rewrite** — "What are 2+ behavior-preserving rewrites for this code path, and what does each cost on the rubric?"

Verbatim from PART XIII of CC.md (§§53-63). Each pattern is mined from a real FrankenSQLite optimization with measured proof. **The numbers are not estimates** — they're recorded keep-gate decisions with both focused and broad gates moving in the same run window.

For each pattern, this file gives: the **verbatim rule**, the **code example**, the **measurement proof**, the **"spot the shape" heuristic**, and **transferability notes** for the 5 project classes (SQL, RESP, Numerical, ML, HTTP).

---

## Pattern 1: Promote a Hot Opcode into `try_execute_hot_opcode`

### Verbatim rule (CC.md §53)
Identify opcodes firing in inner loops; extract them to a pre-match hot-path function to reduce branch misprediction overhead.

### Verbatim code example
```rust
fn try_execute_hot_opcode(&mut self, op: &VdbeOp, pc: &mut usize, ...) -> Result<bool> {
    match op.opcode {
        Opcode::Column              => { ... return Ok(true); }
        Opcode::ColumnSubstrPrefix  => { ... return Ok(true); }
        Opcode::ResultRow           => { ... return Ok(true); }
        // ... more pre-matched opcodes ...
        _ => Ok(false),
    }
}
```

### Measurement proof (CC.md §53.1)
| Opcode | Gain (1t) | Gain (MT8) |
|---|---|---|
| `SCopy` | +38.6% | +37.8% |
| `IfNot` | +31.5% | +32.7% |
| `IsNull` | +27.5% | +27.2% |

### Spot the shape
Look for a `match` / `switch` in an inner loop executed billions of times. If histogram shows one arm firing ≥50%, extract pre-match.

### Transferability notes
- **SQL (FrankenSQLite, SQLModel Rust):** VDBE opcode dispatch — the canonical example.
- **RESP (FrankenRedis):** Command dispatch table (`commandTable[]` style); hot commands (GET, SET, INCR, LPUSH) firing 80%+ in production traces; pre-match in `process_command()` before falling through to `bsearch`.
- **Numerical (FrankenNumPy):** Ufunc dispatch in the BLAS layer; hot dtypes (`float64`, `float32`, `int64`) pre-matched before falling through to generic loop selection.
- **ML (FrankenTorch, FrankenJAX):** Aten op dispatch in `c10`-style core dispatcher; hot ops (`add`, `mul`, `matmul`, `relu`) pre-matched.
- **HTTP (FastAPI Rust, FastMCP Rust):** Route-match trie traversal; hot routes (root, health, common API endpoints) pre-matched before falling through to full trie.

---

## Pattern 2: AtomicBool Gate for an O(N) Sweep That's Usually O(1)

### Verbatim rule (CC.md §54)
Wrap O(N) cleanup/scan ops in a single dirty/has-waiters boolean gate; the empty case becomes O(1).

### Verbatim code example
```rust
fn clear(&self) {
    if !self.has_anything.load(Ordering::Relaxed) { return; }
    for shard in &self.shards { shard.lock().clear(); }
    self.has_anything.store(false, Ordering::Relaxed);
}
```

### Measurement proof
| Site | Before | After | Speedup |
|---|---|---|---|
| `ConcurrentPublishedPages::clear()` empty-overflow | 2.92µs | 1 ns | **~2922x** |
| `ShardedPageCache::clear()` empty-shards | 529 ns | 5 ns | **~106x** |
| `InProcessPageLockTable::notify_all_waiters` SeqCst-fenced | 1057.8 ns | 8.2 ns | **−99.2%, ~129x** |

### Subtlety
Flag is allowed false positive but **never** false negative. Set flag *before* publishing, clear *after* sweeping.

### Spot the shape
Search for `for` loop or `mutex lock` inside a function called from hot paths. If loop usually empty, add AtomicBool gate.

### Transferability notes
- **SQL:** Overflow-page sweeps, schema-cache invalidation, prepared-statement cache clear (all 3 sites realized in FrankenSQLite).
- **RESP:** AOF buffer flush when no pending writes; PUBSUB subscriber-list iteration when no subscribers; expired-key sweep when no TTL keys.
- **Numerical:** Array view-tracking cleanup; broadcast-shape cache invalidation when no entries.
- **ML:** Autograd tape clear when no captured ops; gradient-accumulator zeroing when no model state; CUDA stream sync when no pending kernels.
- **HTTP:** Connection-cleanup loop when no idle connections; middleware-state reset when no middleware bound; CORS preflight cache invalidation.

---

## Pattern 3: Algebraically-Redundant Counter Elimination

### Verbatim rule (CC.md §55)
If a counter is provably equal to algebraic combination of others, derive at read-time not write-time.

### Verbatim code example
`FSQLITE_SSI_VALIDATIONS_TOTAL` was static AtomicU64 incrementing on every SSI commit. Identity holds: `validations_total == commits_total + aborts_total` by construction. Drop the counter, derive at read-time.

### Measurement proof
**3.91 → 1.90 ns/call (−51.5%, ~2x)** (commit `36504496`).

### Spot the shape
Audit every counter in a hot path. Ask: "Can I derive this from existing counters?"

### Transferability notes
- **SQL:** Validation counters, commit/abort counters, retry counters that are obviously sums.
- **RESP:** `total_commands` ≡ `read_commands + write_commands`; AOF append count ≡ tracking that already exists in replication offset.
- **Numerical:** Allocation counts split by dtype that already sum to `total_alloc_bytes`.
- **ML:** Per-op call count where the dispatcher already tracks the dispatch.
- **HTTP:** Per-status-code counter where `total_responses` ≡ `2xx + 3xx + 4xx + 5xx`.

---

## Pattern 4: HashSet → Sorted Vec + binary_search

### Verbatim rule (CC.md §56)
Replace HashSet with sorted Vec when: (a) ≤100 elements, (b) built from sorted source, (c) queried for membership.

### Verbatim code example
2026-04-25 `HandleView` 6× HashSet → sorted-Vec rewrite. Insight: `summarize_witness_keys()` already produced sorted Vecs that old code re-collected into HashSets.

### Measurement proof
**1674.8 → 970.8 ns/build (−42.0%, ~1.7x)** on SSI commit path.

### Spot the shape
`rg 'HashSet' --type rust crates/` in hot paths; check if upstream already sorted.

### Transferability notes
- **SQL:** Witness/key sets in commit-time validation; small column-name sets in resolver; small foreign-key reference sets.
- **RESP:** Sorted-set rank lookups; small command-arg validators where the valid set has <100 entries.
- **Numerical:** Axis-tuple validation; small dtype-list checks.
- **ML:** Small backend-list lookups (`["cpu", "cuda", "mps"]`); per-op supported-dtype sets.
- **HTTP:** Allowed-methods sets for routes; CORS allowed-origins (when small + static); content-type-allowed lists.

---

## Pattern 5: Bounds-Elide via Const-Array Conversion

### Verbatim rule (CC.md §57)
Convert slice indexing to array conversion (`TryInto::<[u8; N]>` or `as_chunks::<N>`) to let compiler elide bounds-checks.

### Verbatim code example
`BtreePageHeader::parse` rewrite: 8 runtime bounds-checks → 1 array conversion.

### Measurement proof
**10.7 → 3.7 ns/parse (−65%, ~2.9x)**. The `#[inline]` annotation compounds. Sibling sites: `read_cell_pointers` −29%, `write_cell_pointers` −53%.

### Subtlety
Use `as_chunks::<N>()` not `chunks_exact()` — the latter still bounds-checks per element.

### Spot the shape
Profile shows bounds-check instructions dominating a parsing loop. Look for `slice[i..i+N]` patterns where `N` is a compile-time constant.

### Transferability notes
- **SQL:** B-tree page header parsing, WAL frame header parsing, varint decoding when length is known.
- **RESP:** RESP frame parsing (length-prefixed); RDB header parsing; integer-format inline parsing.
- **Numerical:** Strided slice reads of fixed-element-count vectors; NumPy header parse.
- **ML:** Tensor shape header parse; model checkpoint magic-number reads.
- **HTTP:** Fixed-format HTTP/2 frame header (9 bytes); WebSocket frame header (2-14 bytes); TLS record header (5 bytes).

---

## Pattern 6: Trait-Object → Match-Arm Devirtualization

### Verbatim rule (CC.md §58)
Replace `&dyn Trait` dispatch with enum-match when concrete-type set is small + stable.

### Verbatim code example
`TransactionKind::get_page` and `write_page_data` devirtualized (commit `0375b55e`). Closed two MT8 dispatch-frame self-time entries (0.36% + 0.29%).

### Measurement proof
MT8 self-time closure: 0.36% + 0.29% = 0.65% removed. MEMORY.md note: "Other `TransactionKind` methods stay on the closure helpers — cold or shape-uniform."

### Spot the shape
Profile shows `<dyn Trait>::method` frame attributing ≥0.1% self-time. Devirtualize that one only.

### Transferability notes
- **SQL:** Transaction-kind dispatch (Direct/Wal/Mvcc); page-cache backend dispatch; vfs-backend dispatch (in-memory/file/encrypted).
- **RESP:** Client-state-machine dispatch (Normal/Pubsub/MultiExec/Monitor); persistence-backend dispatch (None/Aof/Rdb/AofAndRdb).
- **Numerical:** Array-dispatch by dtype; iterator-dispatch by axis order.
- **ML:** Backend dispatch (CPU/CUDA/MPS/MetalShaders); device-memory-allocator dispatch.
- **HTTP:** Body-encoding dispatch (chunked/contentLength/eof-terminated); compression dispatch (gzip/brotli/none).

---

## Pattern 7: Trace-Ceremony Gated Behind `enabled!(LEVEL)`

### Verbatim rule (CC.md §59)
Gate non-trivial tracing arguments behind `if tracing::enabled!(Level)` to avoid argument evaluation when no subscriber.

### Verbatim code example
Planner perf 2026-05-20 found 3× `env::var` calls inside debug-trace ceremony. Gating behind `if tracing::enabled!(tracing::Level::INFO)`.

### Measurement proof
**4-10× oltp_cost** (commit `f43902e2`, bd-mziaw).

### Spot the shape
`rg 'tracing::(debug|info|trace)!' --type rust` and audit each argument; any `format!`, `env::var`, or non-trivial function call in the argument list is suspicious.

### Transferability notes
- **SQL:** Planner trace ceremony, VDBE step tracing, WAL-frame trace; anywhere a `format!` or `env::var` is in an argument list.
- **RESP:** Per-command tracing with argument formatting; slow-log entry construction.
- **Numerical:** ufunc selection tracing; broadcast-shape tracing with `format!("{:?}", shape)`.
- **ML:** Op-dispatch tracing with tensor-spec formatting; autograd-tape tracing with op-name formatting.
- **HTTP:** Per-request tracing with header serialization; route-match tracing with full URI logging.

---

## Pattern 8: Move-Not-Clone on Probe-Builder Hot Paths

### Verbatim rule (CC.md §60)
Replace `.clone()` on hot paths with move semantics; refactor builders to take values not `&`.

### Verbatim code example
2026-05-20 caught `AccessPath` deep-clone of `Box<Probe>` in planner's single-table `order_joins` path. Changed to move.

### Measurement proof
**−21.9% on MISS path** of `oltp_cost_estimation_hot_paths` (commit `b35e1f9c`, bd-4ndk2).

### Spot the shape
Every `.clone()` on hot path is suspicious. Especially boxed-content clones (double allocation: shallow + box contents).

### Transferability notes
- **SQL:** Probe/AccessPath builders; expression-AST builders; join-order candidate generation.
- **RESP:** Command-arg builders; PUBSUB-message broadcasting (often clones unnecessarily); cluster-redirect builders.
- **Numerical:** Array-view builders; einsum-script builders.
- **ML:** Op-fusion candidate builders; gradient-accumulator builders.
- **HTTP:** Request/response builders; header-map builders; cookie-jar builders.

---

## Pattern 9: OnceLock for One-Time-Derivable State

### Verbatim rule (CC.md §61)
Cache deterministic derivations (parsed views, compiled regexes, constant tables) behind `OnceLock<T>`.

### Verbatim code example
`VdbeProgram::OnceLock` (2026-04-23) cached a derivation previously recomputed on every commit.

### Measurement proof
Part of the cluster taking MT 8t throughput from **778 → 5458 (7.0x)** (jointly with Pattern 10).

### Conditions
- Derivation expensive but deterministic
- `Send + Sync` (so OnceLock can be shared)
- Pure derivation (no side effects)

### Spot the shape
`rg 'static .* Lazy<' --type rust` or `rg 'lazy_static' --type rust` are existing examples; look for *missing* OnceLocks where the same derivation is performed on every call.

### Transferability notes
- **SQL:** Compiled bytecode programs, parsed schema views, regex caches for LIKE/GLOB.
- **RESP:** Lua script bytecode cache; pre-compiled cluster-slot tables; sorted-set comparator caches.
- **Numerical:** Compiled ufunc loops per dtype; einsum-string parse cache.
- **ML:** Compiled JIT graphs; AOT-compiled model fragments; backend-capability detection (call once at process start).
- **HTTP:** Compiled OpenAPI schemas; compiled route-match tries; compiled middleware chains.

---

## Pattern 10: Detect the Cache-Eviction Bug — Architectural Fix

### Verbatim rule (CC.md §62)
Audit cache-key design: *for every cache key, list which inputs it depends on; for every cache invalidation, list which inputs should invalidate it; gap = bug*.

### Verbatim code example
Prepared-statement cache evicted on *every COMMIT* because key included `db_generation`, but bytecode doesn't depend on generation — only schema. Fix: separate *bytecode-cache key* (schema-bound) from *data-cache key* (generation-bound).

### Measurement proof
Contributed to **MT 8t fs_wps 778 → 5458 (7.0x)** and **1t fs_wps 88k → 305k (3x+)**.

### Spot the shape
For each cache in the codebase:
1. Enumerate inputs the cached value depends on.
2. Enumerate inputs the invalidation fires on.
3. Diff. Any input in (2) not in (1) = over-eager invalidation (Pattern 10 candidate). Any input in (1) not in (2) = stale-cache bug.

### Transferability notes
- **SQL:** Prepared-statement caches, plan caches, schema caches.
- **RESP:** Cluster-slot caches, sorted-set rank caches, lua-script SHA caches.
- **Numerical:** Broadcast-shape caches, ufunc-loop selection caches.
- **ML:** JIT-graph caches (most common Pattern 10 site in PyTorch/JAX ports); autograd-replay caches.
- **HTTP:** OpenAPI-schema caches, route-match caches, CORS-preflight caches.

---

## Pattern Bonus: MT8 Attribution Profile (CC.md §63)

### Verbatim rule
Always attribute to the canonical concurrent workload (MT8 = 8-thread multi-writer bench). Profile must cite specific self-time frames ≥0.1% but <1%.

### Discipline (5 steps)
1. Run `mt-mvcc-bench --threads=8 --rows-per-thread=1000 --iters=3`.
2. Capture flamegraph during *steady-state* (post-warmup).
3. Identify top 5–10 self-time frames.
4. Each ≥0.1% is a *candidate*.
5. Pick highest cost-effort ratio (EV-scored per the proof-pack card).

### MEMORY.md citation format
- "Closed 0.44% MT8 PublishedPages::clear residual"
- "Closed 0.63% MT8 inclusive self-time"
- "Closed 0.51% MT8 self-time symbol"

### The 0.1–1% window
- **<0.1%:** Below noise floor of MT8 (cv_pct 3-5%) — the **micro-lever trap**. Effort wasted; gain dissolves into noise.
- **0.1–1%:** Productive optimization range. Cost-effective. Most Pattern 1-10 wins live here.
- **≥1%:** Rare and high-value. If you find one, drop everything else and harvest it.

### Transferability notes
- **SQL:** MT8 = 8-thread WAL writer workload (FrankenSQLite canonical).
- **RESP:** MT8 ≡ 8 concurrent clients on shared keyspace with mixed GET/SET/INCR.
- **Numerical:** Threading not relevant; substitute "MT8" with `OMP_NUM_THREADS=8` parallel ufunc on large array.
- **ML:** "MT8" ≡ 8-rank distributed all-reduce or 8-batch on single GPU.
- **HTTP:** MT8 ≡ 8-concurrent-connection wrk2 / oha benchmark at steady state.

---

## Cross-Pattern Notes

- **One pattern per change.** "Multiple changes per commit" is anti-pattern #2 from CC.md §87.4 — can't isolate regressions. Even if you see 3 Pattern 1 candidates in the same function, land them as 3 commits.
- **Both gates must move in the same run window.** Per [methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md), every kept perf change requires the focused gate AND the broad gate (`comprehensive-bench`) to move in the same `git`-state / `target/`-state / machine / minute.
- **Isomorphism proof required.** Every pattern is behavior-preserving by construction (none change semantic output). Every commit must include a 5-line isomorphism proof per [ISOMORPHISM-PROOF-TEMPLATE.md](ISOMORPHISM-PROOF-TEMPLATE.md): Change / Ordering / Tie-breaking / Floating-point / RNG / Golden.
- **Profile-first contract (CC.md §1 PART V).** No code-changing performance bead starts without measured hotspot evidence, an EV-scored recommendation card, a one-lever scope, and a proof pack. The 19 required fields per [tooling/BENCH-TOOLCHAIN.md § Proof-Pack].
- **Negative-ledger entry per rejected attempt.** Pattern attempts that don't earn a keep go into `docs/progress/perf-negative-results.md` with the retry-condition predicate. "No bounded micro-lever found" is the most common rejection class.

See also: [EXAMPLE-EXPERIMENTS-PERF.md](../experiments/EXAMPLE-EXPERIMENTS-PERF.md), [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md), [ISOMORPHISM-PROOF-TEMPLATE.md](ISOMORPHISM-PROOF-TEMPLATE.md).
