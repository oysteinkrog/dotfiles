# STACKED-VS-TREE-BORROWS.md — Two Models for Aliasing UB

Miri implements TWO aliasing models. The audit must run BOTH, because:

- **Stacked Borrows** (the historical default) is stricter — it accepts fewer patterns.
- **Tree Borrows** (the newer experimental model, becoming default) accepts more — particularly around reborrows through raw pointers.

A rewrite that passes Tree but fails Stacked is interesting; the audit must triage whether it's a "Stacked Borrows false positive that Tree fixed" or a "the rewrite is unsound."

---

## What aliasing means here

Rust's borrow checker enforces aliasing at compile time. `&mut T` and `&T` cannot coexist for overlapping memory.

`unsafe` code can use raw pointers (`*mut T`, `*const T`) to bypass this. The COMPILER won't catch aliasing through raw pointers. But the LANGUAGE still requires non-aliasing semantics for `&mut T` derived from those pointers.

Stacked Borrows and Tree Borrows are two formalizations of "what aliasing is OK through raw pointers."

---

## Stacked Borrows in 90 seconds

Each allocation has a "borrow stack" attached. Every borrow ID (each `&T` / `&mut T` / `*mut T`) goes on the stack when created.

Reading through a borrow only succeeds if its ID is somewhere on the stack and shadowing rules allow.

Writing through a borrow POPS the stack — every borrow above it is invalidated.

```rust
let mut x = 0u8;
let r1 = &mut x;            // stack: [Unique(r1)]
let p = r1 as *mut u8;       // stack: [SharedRO(p), Unique(r1)]
*p = 1;                      // tries to write through SharedRO -> reborrows; stack: [Unique(r1), Unique(p_write)]
//                             but then Unique(r1) is shadowed; subsequent r1 use is UB
println!("{}", *r1);         // UB under stacked borrows
```

The classical breakage is: `&mut T` reborrowed as `*mut T`, then the original `&mut T` is used after the raw pointer wrote.

---

## Tree Borrows in 90 seconds

Same concept (every borrow tracked), but the model is a TREE instead of a STACK. Reborrowing is a tree branch; siblings can coexist as long as they don't overlap in writes.

```rust
let mut x = 0u8;
let r1 = &mut x;
let p = r1 as *mut u8;
*p = 1;
println!("{}", *r1);  // Tree Borrows: still valid (raw-pointer write doesn't invalidate the parent)
```

Tree Borrows accepts patterns where intermediate `*mut T` round-trips preserve the original borrow's validity.

---

## Why the audit runs both

If the rewrite passes Tree but fails Stacked:

| Case | Audit action |
|------|--------------|
| Rewrite is sound under both models; Stacked Borrows is being pedantic | Acceptable; document in SAFETY comment that "this is a known Stacked Borrows false positive accepted by Tree Borrows." Mark tests with `#[cfg_attr(miri, ignore)]` if blocking; pin Tree-only via `MIRIFLAGS`. |
| Rewrite is unsound; Tree Borrows missed it | Rare. Investigate via additional `loom` modeling, longer fuzz runs, or upstream issue against Tree Borrows. |

If the rewrite passes Stacked but fails Tree:

| Case | Audit action |
|------|--------------|
| Rewrite relies on Stacked's stricter shadowing semantics that Tree doesn't enforce | Investigate — the rewrite might be exploiting a pattern that's about to become illegal. |
| Tree Borrows bug | File upstream; pin Stacked for now. |

If both fail: the rewrite is unsound. Back to refactor-planner.

---

## How to run

```bash
# Stacked Borrows (default; the strict historical model)
cargo +nightly miri test --workspace

# Tree Borrows (experimental; the future default)
MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri test --workspace

# Optional: combine with strict-provenance for max coverage
MIRIFLAGS="-Zmiri-tree-borrows -Zmiri-strict-provenance" \
  cargo +nightly miri test --workspace
```

The skill's `run-miri.sh` runs Stacked + strict-provenance by default. For sites flagged as "Tree Borrows expected" (e.g., heavy raw-pointer round-trips, async pinning), add a `MIRI_MODE=tree` env to opt into Tree Borrows for that test.

---

## Patterns that historically failed Stacked but pass Tree

### `Vec::iter_mut` interleaved with raw-pointer view

```rust
let mut v = vec![1, 2, 3];
let p = v.as_mut_ptr();
for x in v.iter_mut() {
    // The raw pointer `p` exists but is unused.
    *x += 1;
}
unsafe { *p = 10; }   // Stacked Borrows historically flagged this
```

Tree Borrows accepts because `p` is a sibling, not a parent of `iter_mut`'s borrows.

### `Pin<&mut T>` projections through `get_unchecked_mut`

`pin-project-lite` generates patterns that Stacked sometimes flagged; Tree handles them cleanly. See [80-PIN-PROJECTIONS.md](../patterns/80-PIN-PROJECTIONS.md).

### Hand-rolled doubly-linked lists with `Cell<*mut Node>`

Used to be very Stacked-unfriendly. Tree allows the typical patterns IF the field-level UnsafeCell discipline is followed.

---

## Patterns that fail BOTH

These are unsoundness, not model disagreement:

- `&mut T` used after a `*mut T` write that overlaps. (Use-after-write.)
- Two `&mut T` to overlapping memory. (Mutable aliasing.)
- `&T` to memory while a `&mut T` write is in progress. (Read-during-write.)
- Reading uninitialized `MaybeUninit::assume_init`'d memory. (Uninit access.)
- Out-of-bounds access regardless of provenance.

If the rewrite triggers any of these, the rewrite is unsound. (C) → refactor again.

---

## Acceptance signal

A rewrite passes the aliasing check when:

1. **Stacked Borrows miri runs clean**, AND
2. **Tree Borrows miri runs clean**, AND
3. **Strict-provenance miri runs clean** (per [PROVENANCE-MODEL.md](PROVENANCE-MODEL.md)).

If any single mode fails, the rewrite is flagged for refactor-planner re-spawn.

The exception: documented Stacked-Borrows-false-positives where Tree accepts AND a Stacked-pin justification is in the SAFETY comment. These are rare; they should be flagged for upstream-issue against miri/Stacked.

---

## Resources

- [Stacked Borrows paper](https://plv.mpi-sws.org/rustbelt/stacked-borrows/) — the formal model.
- [Tree Borrows technical report](https://perso.crans.org/vanille/treebor/) — the newer model.
- Miri's `MIRIFLAGS` documentation — `-Zmiri-stacked-borrows` vs `-Zmiri-tree-borrows`.
- Rust nomicon §aliasing — the high-level rules without the formal model.
