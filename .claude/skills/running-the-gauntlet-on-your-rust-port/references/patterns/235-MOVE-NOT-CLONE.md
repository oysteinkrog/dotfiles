# pattern:235-MOVE-NOT-CLONE

## What

Replace `.clone()` on hot paths with **move semantics** by refactoring builders/constructors to take values (`T`) instead of references (`&T`). The typical anti-shape is a builder API that accepts `&Probe` and clones internally to take ownership; the refactor flips the signature to take `Probe` so the caller's existing owned value moves in without copying. The pattern is most painful when the cloned content is itself a `Box<T>` — then every clone is a heap allocation for the Box plus a deep copy of the contents.

## Why

> "Replace `.clone()` on hot paths with move semantics; refactor builders to take values not `&`." — CC.md §60 (verbatim)

Failure mode prevented: *deep clones of boxed content in hot constructors*. The motivating case in FrankenSQLite was the planner's `AccessPath` builder. On the single-table `order_joins` path, the builder accepted a `&Box<Probe>` and cloned it internally — a deep clone, meaning a fresh `Box` allocation plus a recursive copy of the probe tree. On the MISS path of `oltp_cost_estimation_hot_paths` (which is hit when no cached plan matches), this clone happened on every estimation.

The fix was a signature change: take `Box<Probe>` by value, document that the caller transfers ownership, update the two call sites.

## Where in FrankenSQLite

- `AccessPath` builder, planner's single-table `order_joins` path
- Workload: `oltp_cost_estimation_hot_paths`, MISS path
- Commit: `b35e1f9c`
- Bead: `bd-4ndk2`
- Date: 2026-05-20

## Verbatim shape

Before (`&Box<Probe>` + internal clone):

```rust
impl AccessPathBuilder {
    pub fn with_probe(mut self, probe: &Box<Probe>) -> Self {
        self.probe = Some(probe.clone());  // ← deep clone: new Box + recursive copy
        self
    }
}

// caller:
let path = AccessPathBuilder::new()
    .with_probe(&owned_probe)  // caller has ownership but passes by ref
    .build();
```

After (take `Box<Probe>` by value, caller moves):

```rust
impl AccessPathBuilder {
    pub fn with_probe(mut self, probe: Box<Probe>) -> Self {
        self.probe = Some(probe);  // ← move; no allocation, no copy
        self
    }
}

// caller:
let path = AccessPathBuilder::new()
    .with_probe(owned_probe)  // moves; caller can't use owned_probe afterward
    .build();
```

## Measurement proof (verbatim)

**−21.9% on the MISS path** of `oltp_cost_estimation_hot_paths` (commit `b35e1f9c`, bead `bd-4ndk2`).

The win is specifically on the MISS path because cache hits skip the builder entirely. The HIT path was already cheap; the MISS path was where the deep clone bit.

## Spot the shape

In an unfamiliar codebase:

1. `rg '\.clone\(\)' --type rust` in hot paths.
2. For each match, check the type. **Especially boxed clones** (`Box<T>::clone`, `Arc<Vec<T>>::clone`, anything that wraps a heap allocation): these double-allocate (the wrapper + the contents).
3. Trace the data flow: is the cloned value owned by the caller and immediately discarded after the call? If yes, the clone is dispensable — make the API take by value.
4. Profile attribution: `<X as Clone>::clone` in the top 20 self-time frames at ≥0.1%, especially with a clone-of-clone chain visible.

## Per-class transferability

| Class | Common boxed-clone-on-hot-path sites |
|---|---|
| **SQL** | Probe/AccessPath builders; expression-AST builders; join-order candidate generation; bound-parameter cloning in prepared-stmt cache lookup |
| **RESP** | Command-arg builders (RESP frames clone arg vectors); PUBSUB-message broadcasting (often clones unnecessarily to fan out); cluster-redirect builders |
| **Numerical** | Array-view builders; einsum-script builders; broadcast-shape builders (clone shape vectors when a move would do) |
| **ML** | Op-fusion candidate builders; gradient-accumulator builders; module-state builders (clone weight handles when a move would do); JIT-graph builders |
| **HTTP** | Request/response builders; header-map builders; cookie-jar builders; route-param builders |

## Composition

- Pairs with [pattern:240-ONCELOCK-DERIVATION-CACHE](240-ONCELOCK-DERIVATION-CACHE.md) — if the clone is needed because the original is constructed expensively, OnceLock the construction so a shared `&'static T` is available without cloning.
- Pairs with [pattern:225-DEVIRTUALIZE-MATCH-ARM](225-DEVIRTUALIZE-MATCH-ARM.md) — both fix hot-path overhead and both are profile-driven.
- Pairs with [pattern:230-ENABLED-LEVEL-TRACING-GATE](230-ENABLED-LEVEL-TRACING-GATE.md) — both eliminate per-call allocation; that one targets trace-argument allocation, this one targets builder argument.
- Pairs with [pattern:250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md) — the refactor preserves observable behavior trivially; the only risk is double-use of the moved value, caught at compile time.

## Pitfalls

- **Cloning at the call site instead of the builder.** Moves the work but doesn't eliminate it. The point is to *remove* the clone, not relocate it. If the caller really has shared ownership, use `Arc` (cheap clone) instead of `Box` (deep clone).
- **Forgetting that the caller may no longer hold the value.** A `with_probe(owned_probe)` call consumes `owned_probe`. If the caller uses it after, you get a compile error — the fix is to clone *at the call site* if the caller truly needs both copies, which is the rare case that justifies the original `&`-clone API.
- **Per-class trap (RESP): PUBSUB fan-out clones because each subscriber needs its own copy.** The optimization there is `Arc<Bytes>` or `Bytes` (cheap shared ref), not move; PUBSUB is one of the cases where shared ownership is correct.
- **Per-class trap (ML): module-state clone is sometimes load-bearing for autograd (the tape captures the version).** Audit autograd semantics before flipping the API.
- **Per-class trap (HTTP): request-builder pattern often takes `&str` for ergonomics, then clones to `String` internally.** The fix is to take `impl Into<String>` so the caller picks whether to allocate.
- **Treating every `.clone()` as a bug.** Plenty of clones are legitimately cheap (`Arc`, `Copy` types). The pattern targets boxed/deep clones on hot paths specifically.
- **No profile attribution.** A signature change that ripples through the API is expensive; the win must be measured and the bead must include the proof.
