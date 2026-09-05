# pattern:225-DEVIRTUALIZE-MATCH-ARM

## What

Replace `&dyn Trait` virtual-dispatch with enum-match (or, equivalently, with a closure helper) when the concrete-type set is **small and stable**. The vtable load + indirect call cost shows up as a self-time frame in profiles (`<dyn Trait>::method`); collapsing it to a direct match-arm call lets the compiler inline the implementations and removes the indirect-jump branch predictor cost. The rule is *profile-driven*: don't devirtualize every method — only ones the profile attributes ≥0.1% self-time. Cold or shape-uniform methods stay on the trait object (less code churn, no measurable win to extract).

## Why

> "Replace `&dyn Trait` dispatch with enum-match when concrete-type set is small + stable." — CC.md §58 (verbatim)

Failure mode prevented: *trait-object dispatch dominating a hot loop*. The motivating case in FrankenSQLite was `TransactionKind`: three concrete variants (`Direct`, `Wal`, `Mvcc`), and `get_page` + `write_page_data` were being dispatched through a `&dyn TransactionKindTrait`. The vtable indirection appeared as two separate self-time entries at MT8 (0.36% + 0.29%). Devirtualizing collapsed both.

The MEMORY.md note from FrankenSQLite is crucial: "Other `TransactionKind` methods stay on the closure helpers — cold or shape-uniform." The point isn't "always devirtualize"; the point is "devirtualize the methods the profile cares about."

## Where in FrankenSQLite

- `TransactionKind::get_page` — devirtualized
- `TransactionKind::write_page_data` — devirtualized
- Commit: `0375b55e`
- (Source under `crates/fsqlite-mvcc/src/`.)

## Verbatim shape

Before (trait-object dispatch):

```rust
trait TransactionKindTrait {
    fn get_page(&self, pgno: u32) -> Result<Page>;
    fn write_page_data(&mut self, pgno: u32, data: &[u8]) -> Result<()>;
}

fn step(&self, txn: &dyn TransactionKindTrait, pgno: u32) -> Result<Page> {
    txn.get_page(pgno)  // ← indirect call through vtable
}
```

After (enum-match devirtualization for the hot methods only):

```rust
enum TransactionKind {
    Direct(DirectTxn),
    Wal(WalTxn),
    Mvcc(MvccTxn),
}

impl TransactionKind {
    #[inline]
    fn get_page(&self, pgno: u32) -> Result<Page> {
        match self {
            TransactionKind::Direct(t) => t.get_page(pgno),
            TransactionKind::Wal(t)    => t.get_page(pgno),
            TransactionKind::Mvcc(t)   => t.get_page(pgno),
        }
    }
    // write_page_data: same shape
    // Other methods: still go through a closure helper or trait object; cold path
}
```

## Measurement proof (verbatim)

| Frame | MT8 self-time closed |
|---|---|
| `<dyn TransactionKindTrait>::get_page` | 0.36% |
| `<dyn TransactionKindTrait>::write_page_data` | 0.29% |
| **Total** | **0.65%** removed |

Commit: `0375b55e`. MEMORY.md note: "Other `TransactionKind` methods stay on the closure helpers — cold or shape-uniform."

## Spot the shape

In an unfamiliar codebase:

1. A profile showing `<dyn SomeTrait>::method` in the top 10–20 self-time frames at ≥0.1%.
2. The concrete implementor set is **closed** (3–5 types, not dozens) and **stable** (not expected to grow).
3. The method is called from a hot loop (per-step, per-page, per-request) — the indirection cost compounds.
4. The trait does not require dynamic dispatch for plugin extensibility — e.g., it's an internal abstraction, not a public API.

If those four hold, profile-attribute the win and devirtualize *that one method*.

## Per-class transferability

| Class | Common small-stable dispatch sites that devirtualize well |
|---|---|
| **SQL** | Transaction-kind dispatch (Direct/Wal/Mvcc); page-cache backend dispatch; vfs-backend dispatch (in-memory/file/encrypted) |
| **RESP** | Client-state-machine dispatch (Normal/Pubsub/MultiExec/Monitor); persistence-backend dispatch (None/Aof/Rdb/AofAndRdb); reply-encoder dispatch (RESP2/RESP3) |
| **Numerical** | Array-dispatch by dtype (when the dtype set is finite); iterator-dispatch by axis order; broadcast-strategy dispatch |
| **ML** | Backend dispatch (CPU/CUDA/MPS/MetalShaders); device-memory-allocator dispatch; reduction-strategy dispatch |
| **HTTP** | Body-encoding dispatch (chunked/contentLength/eof-terminated); compression dispatch (gzip/brotli/none); auth-scheme dispatch (bearer/basic/apikey) |

## Composition

- Pairs with [pattern:200-HOT-OPCODE-PROMOTION](200-HOT-OPCODE-PROMOTION.md) — both concentrate hot-path dispatch; this one closes vtable cost, that one closes match-arm prediction cost.
- Pairs with [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — the rule "only devirtualize methods ≥0.1% self-time" *is* MT8 attribution discipline.
- Pairs with [pattern:235-MOVE-NOT-CLONE](235-MOVE-NOT-CLONE.md) — both reduce per-call overhead; both should be motivated by a profile, not by intuition.
- Pairs with [pattern:240-ONCELOCK-DERIVATION-CACHE](240-ONCELOCK-DERIVATION-CACHE.md) — if the trait was being constructed per-call, OnceLock the construction; if the dispatch was hot, devirtualize.

## Pitfalls

- **Devirtualizing every method on the trait.** The vast majority of methods are cold; converting them changes code with no measurable win. Profile-driven, one-method-at-a-time.
- **Picking a trait whose implementor set is *not* stable.** If a plugin can add a new transaction kind at runtime, the enum is wrong — trait objects are correct. Devirt only closed worlds.
- **Forgetting `#[inline]` on the enum-match arms.** Without inlining, the win is the indirect-call saving only; with inlining, the implementor's body can fold into the caller and the savings compound.
- **Per-class trap (ML): backend dispatch is *stable in the binary* but the device set chosen *at runtime* depends on configuration.** The enum is the right shape; the dispatch happens once at session start, not per-call.
- **Per-class trap (RESP): client-state dispatch via enum-match conflates with state-transition logic.** Keep the state machine pure and the per-state dispatch as enum-match; don't entangle them.
- **Devirtualizing without verifying the profile.** "It looked like it should be hot" is anti-pattern #7 (plausible hypothesis without profile). The 0.1% rule is the gate.
- **Leaving the trait around for "future flexibility" without using it.** Dead code rots; if the enum is the right shape, delete the trait.
