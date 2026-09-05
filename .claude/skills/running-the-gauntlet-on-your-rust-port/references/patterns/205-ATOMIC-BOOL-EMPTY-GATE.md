# pattern:205-ATOMIC-BOOL-EMPTY-GATE

## What

Wrap an O(N) sweep, cleanup, or notification operation behind a single `AtomicBool` flag that lets the empty case short-circuit to O(1). The flag is *set before publishing* any work into the data structure and *cleared after sweeping*. The empty case (which dominates in practice — e.g., `clear()` called on a cache that's almost always already empty) becomes a single relaxed atomic load.

## Why

> "Wrap O(N) cleanup/scan ops in a single dirty/has-waiters boolean gate; the empty case becomes O(1)." — CC.md §54 (verbatim)

Failure mode prevented: *the cleanup loop that always runs because it might have something to do*. When `clear()` is called from a hot path and the structure is empty 99% of the time, the for-loop-over-shards or the mutex acquisition dominates the cost. The flag turns 99% of calls into a single atomic-load-and-branch.

The flag is **allowed false positive but never false negative**. False positive (flag says "has stuff" but actually empty): O(N) sweep runs and finds nothing — correct, just slow. False negative (flag says "empty" but actually has stuff): correctness bug. Therefore: **set the flag before publishing the work; clear the flag after sweeping**. This ordering makes a missed update impossible.

## Where in FrankenSQLite

- `ConcurrentPublishedPages::clear()` — overflow-page sweep
- `ShardedPageCache::clear()` — sharded cache invalidation
- `InProcessPageLockTable::notify_all_waiters` — SeqCst-fenced waiter notification

(Source paths in the FrankenSQLite tree under `crates/fsqlite-mvcc/` and `crates/fsqlite-core/`.)

## Verbatim shape

From CC.md §54:

```rust
fn clear(&self) {
    if !self.has_anything.load(Ordering::Relaxed) { return; }
    for shard in &self.shards { shard.lock().clear(); }
    self.has_anything.store(false, Ordering::Relaxed);
}
```

Symmetric writer-side:

```rust
fn publish(&self, item: Item) {
    self.has_anything.store(true, Ordering::Relaxed);  // BEFORE publishing
    self.shards[shard_for(&item)].lock().push(item);
}
```

## Measurement proof (verbatim)

| Site | Before | After | Speedup |
|---|---|---|---|
| `ConcurrentPublishedPages::clear()` empty-overflow | 2.92µs | 1 ns | **~2922x** |
| `ShardedPageCache::clear()` empty-shards | 529 ns | 5 ns | **~106x** |
| `InProcessPageLockTable::notify_all_waiters` SeqCst-fenced | 1057.8 ns | 8.2 ns | **−99.2%, ~129x** |

## Spot the shape

In an unfamiliar codebase, look for:

1. A function named `clear` / `reset` / `flush` / `notify_all` / `invalidate` *called from a hot path* (e.g., per-commit, per-request, per-step).
2. The function body contains a `for` loop over shards/buckets OR an unconditional `Mutex::lock()`.
3. A profile shows the function in the top 10 self-time frames at ≥0.1%, with most of its time in the loop or in the lock.
4. The function is *idempotent on empty* — calling it with no work to do is correctness-equivalent to not calling it.

If those four hold, an AtomicBool gate likely turns 99% of calls into ~1ns.

## Per-class transferability

| Class | Empty-O(N)-sweep sites that benefit |
|---|---|
| **SQL** | Overflow-page sweep; schema-cache invalidation; prepared-statement cache clear; WAL-frame notification |
| **RESP** | AOF buffer flush when no pending writes; PUBSUB subscriber-list iteration when no subscribers; expired-key sweep when no TTL keys; cluster-slot cache invalidation |
| **Numerical** | Array view-tracking cleanup; broadcast-shape cache invalidation when no entries; per-op temporary-buffer release |
| **ML** | Autograd tape clear when no captured ops; gradient-accumulator zeroing when no model state; CUDA stream sync when no pending kernels; KV-cache eviction when empty |
| **HTTP** | Connection-cleanup loop when no idle connections; middleware-state reset when no middleware bound; CORS preflight cache invalidation; per-request span buffer flush |

## Composition

- Pairs with [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — the ~2922x speedup came from a profile that attributed 0.44% MT8 self-time to `PublishedPages::clear`.
- Pairs with [pattern:210-ALGEBRAIC-COUNTER-ELIMINATION](210-ALGEBRAIC-COUNTER-ELIMINATION.md) — both are "every hot call cost vs report-time cost" inversions, but this one targets *work*, that one targets *counters*.
- Pairs with [pattern:250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md) — the false-positive-but-never-false-negative subtlety needs the 5-line proof: ordering preserved, no observable change.
- Pairs with [pattern:145-HOT-PATH-COUNTERS](145-HOT-PATH-COUNTERS.md) — keep a counter for "flag-skip" vs "real-sweep" calls to track that the gate is actually firing.

## Pitfalls

- **Storing the flag *after* publishing the work.** False negative: another thread reads the flag (false), skips the sweep, and misses the work. Always: `store(true, Relaxed)` → publish; clear: sweep → `store(false, Relaxed)`.
- **Using `Ordering::SeqCst` for the flag.** Relaxed is correct; the data structure's own lock provides the synchronization for the data. SeqCst costs the win.
- **Allocating an `AtomicBool` per-instance and ignoring cache-line sharing.** If the AtomicBool lives next to a hot Mutex on the same cache line, the false-sharing cost can exceed the win. Pad it (`#[repr(align(64))]`) when the structure is small.
- **Forgetting the symmetric `store(true)` site.** The reader-side gate is half the pattern; the writer-side flag-set is the other half. Missing the writer side means the gate never opens — false negative.
- **Per-class trap (ML): autograd tape gates that don't account for the tape's persistence across forward passes.** The flag's reset point matters; reset only when the tape is *actually* drained, not on every forward.
- **Treating `notify_all` as if O(N) is the goal.** The win at `notify_all_waiters` was 1057.8 → 8.2 ns *because the waiter list is empty 99% of the time*. If your waiter list is usually populated, this pattern is the wrong tool.
- **Gating something that has side effects beyond data clearing.** If the loop also flushes metrics or fires hooks, the gate skips them too. The gate is for *pure* O(N) sweeps.
