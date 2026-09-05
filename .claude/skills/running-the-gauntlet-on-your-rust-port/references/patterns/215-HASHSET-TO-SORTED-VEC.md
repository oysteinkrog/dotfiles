# pattern:215-HASHSET-TO-SORTED-VEC

## What

Replace a small `HashSet<T>` (typically ≤100 elements) built from an already-sorted source with a sorted `Vec<T>` queried via `binary_search`. The hash-and-allocate cost per insertion plus the bucket-walking cost per lookup dominates the asymptotic O(1) advantage at small N; a sorted Vec wins on every dimension: smaller memory footprint, fewer allocations, cache-friendly iteration, and `binary_search` is O(log N) which at N ≤ 100 is ≤ 7 comparisons.

## Why

> "Replace HashSet with sorted Vec when: (a) ≤100 elements, (b) built from sorted source, (c) queried for membership." — CC.md §56 (verbatim)

Failure mode prevented: *paying for hashing on tiny collections that were already sorted upstream*. The motivating case in FrankenSQLite was `HandleView`: `summarize_witness_keys()` already produced sorted Vecs, and the consumer immediately re-collected them into HashSets to do membership queries. The hash + bucket allocation + collision handling cost on each insertion dominated the workload at SSI commit time.

## Where in FrankenSQLite

- `HandleView` — 6× HashSet → sorted-Vec rewrite, 2026-04-25
- `summarize_witness_keys()` — the already-sorted upstream producer
- SSI commit path in `crates/fsqlite-mvcc/`

## Verbatim shape

Before:

```rust
let witness_set: HashSet<KeyId> = summarize_witness_keys(&txn).into_iter().collect();
// later: lookup
if witness_set.contains(&key) { ... }
```

After:

```rust
// Already sorted from summarize_witness_keys():
let witness_vec: Vec<KeyId> = summarize_witness_keys(&txn);
// later: lookup
if witness_vec.binary_search(&key).is_ok() { ... }
```

## Measurement proof (verbatim)

**1674.8 → 970.8 ns/build (−42.0%, ~1.7x)** on SSI commit path, 6× HashSet → sorted-Vec rewrite on 2026-04-25.

## Spot the shape

In an unfamiliar codebase:

1. `rg 'HashSet' --type rust crates/` in hot paths.
2. For each hit, trace the source: where does the iterator that fills the set come from? If the source is already a sorted `Vec` (e.g., from a B-tree iteration, an `Index`, a `BTreeMap::keys()`, or a manually-sorted slice), the HashSet is buying you nothing.
3. Check cardinality: a HashSet of unbounded size doesn't fit; this is a small-set pattern.
4. Check use: if the set is only queried for membership (`contains`), Vec + `binary_search` works. If you need set algebra (union, intersection), reach for a different approach.

## Per-class transferability

| Class | Small sorted-source HashSet → Vec sites |
|---|---|
| **SQL** | Witness/key sets in commit-time validation; small column-name sets in resolver; small foreign-key reference sets; small `IN (...)` value lists |
| **RESP** | Sorted-set rank lookups; small command-arg validators where the valid set has <100 entries; small expiration-bucket scans |
| **Numerical** | Axis-tuple validation; small dtype-list checks; small acceptable-shape lists; broadcast-shape compatibility sets |
| **ML** | Small backend-list lookups (`["cpu", "cuda", "mps"]`); per-op supported-dtype sets; small kernel-param value lists |
| **HTTP** | Allowed-methods sets for routes; CORS allowed-origins (when small + static); content-type-allowed lists; auth-scope membership for small scope sets |

## Composition

- Pairs with [pattern:220-BOUNDS-ELIDE-AS-CHUNKS](220-BOUNDS-ELIDE-AS-CHUNKS.md) — both target hot small-data paths; the Vec + binary_search version compiles to far fewer instructions than the hash + probe version.
- Pairs with [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — the win was attributable to the SSI commit-path frame at MT8.
- Pairs with [pattern:250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md) — order preservation is trivially preserved (Vec is already sorted); set equivalence is preserved (no duplicates from the source).
- Composes negatively with arbitrary-iteration use cases: if you actually need set algebra, this pattern doesn't apply.

## Pitfalls

- **Source isn't actually sorted.** The biggest trap: the consumer assumed the source was sorted, the source happened to *usually* return sorted output (because it iterated a BTreeMap that happened to be insertion-ordered), but a refactor breaks the invariant. Always add a `debug_assert!(v.windows(2).all(|w| w[0] <= w[1]))` after the source call.
- **Source has duplicates.** `binary_search` returns *any* matching index, so dupes are fine for membership; but if the consumer was using the HashSet for *deduplication*, the Vec version needs a `dedup()` call.
- **N grows above the threshold.** At N ≥ 1000 the HashSet's O(1) starts to genuinely win. Audit the source's output size; this is a *bounded-N* pattern.
- **Forgetting that `binary_search` returns `Result`, not `bool`.** `.is_ok()` or `.is_err()` is required; `if v.binary_search(&key)` doesn't compile.
- **Per-class trap (Numerical): axis-tuple sets where the iteration order matters for broadcasting.** Vec preserves order; HashSet didn't; if the consumer accidentally relied on the HashSet's *non*-deterministic order, the Vec version may expose a latent bug.
- **Per-class trap (RESP): small-but-growing acceptable-command lists.** A new release of the reference may add commands; the Vec needs a re-sort on construction, not a per-insert sort.
- **Treating this as a microbenchmark trick.** The 42% win came from the *aggregate* SSI commit path, not from any one `contains` call. The cost was the *construction*, not the lookup.
