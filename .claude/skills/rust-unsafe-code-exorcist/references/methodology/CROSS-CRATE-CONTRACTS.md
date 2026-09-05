# CROSS-CRATE-CONTRACTS.md — Soundness Across Workspace Boundaries

In a workspace, soundness contracts often cross crate boundaries. Crate A's `pub fn` relies on crate B's invariant. The audit formalizes these contracts so cross-crate refactors stay sound.

---

## What's a cross-crate contract?

```rust
// crate-a/src/lib.rs
use crate_b::SafeHandle;

pub fn process(handle: SafeHandle) -> Result<u32, Error> {
    // SAFETY: SafeHandle's invariant is that .raw_fd() returns a valid open fd.
    // This invariant is enforced by crate_b's SafeHandle::new constructor.
    let raw = handle.raw_fd();
    let n = unsafe { libc::read(raw, buf.as_mut_ptr() as *mut _, buf.len()) };
    ...
}
```

`crate_a::process` relies on `crate_b::SafeHandle`'s invariant ("raw_fd is valid"). If `crate_b` ships a v2 where `raw_fd()` can return -1 in certain cases, `crate_a::process` becomes unsound — even though no code in `crate_a` changed.

This is a **cross-crate soundness contract**.

---

## The audit's job

For workspaces:

1. **Enumerate cross-crate contracts.** Phase 3 synthesis walks pub APIs of every crate; for each unsafe block that depends on another crate's invariant, document the contract.
2. **Verify each contract.** Cross-reference the asserted invariant against the cited crate's docs / source. Is the invariant still true?
3. **Test the contract.** A contract test sits in the consuming crate; it exercises the invariant + asserts it holds.
4. **Track contract drift.** Continuous mode watches: did the upstream crate change in a way that breaks the contract?

---

## Contract documentation format

`<audit-dir>/audit/synthesis/cross-crate-contracts.md`:

```markdown
# Cross-Crate Soundness Contracts

## Contract CCC-001 — crate_a::process depends on crate_b::SafeHandle

### Consumer
- Crate: `crate_a`
- Function: `crate_a::process(handle: SafeHandle)`
- Site: src/process.rs:142

### Provider
- Crate: `crate_b`
- Type: `crate_b::SafeHandle`
- Invariant: `SafeHandle::raw_fd() -> RawFd` always returns a valid open fd.

### Why it's a contract
The consumer's unsafe block calls `libc::read(handle.raw_fd(), ...)`. If `raw_fd()` returned -1, the read would be UB (libc would interpret -1 as a sentinel; the read would deref an invalid pointer).

### Enforced by (current verification)
- `crate_b::SafeHandle::new` constructor validates the fd via `libc::fcntl(fd, F_GETFD)`; returns Err on invalid.
- `crate_b::SafeHandle::drop` closes the fd; SafeHandle owns the lifetime.

### Test
- File: `crate_a/tests/cross_crate_safehandle.rs`
- Test: `safehandle_invariant_holds`
- Strategy: construct a SafeHandle via the safe API; exercise `raw_fd()` 1000 times; assert each return is valid.

### Drift watch
- If crate_b's `SafeHandle::raw_fd` signature changes, this contract needs revisiting.
- Continuous mode: track `crate_b`'s version in Cargo.lock; alert on bump.

## Contract CCC-002 — ...
```

---

## Per-contract test

Each contract has a test file in the CONSUMING crate:

```rust
// crate_a/tests/cross_crate_safehandle.rs
//! Cross-crate contract test for CCC-001.
//!
//! Verifies crate_b::SafeHandle::raw_fd() returns valid fds, as required by
//! crate_a::process's safety obligation.

use crate_b::SafeHandle;
use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig { cases: 100, ..ProptestConfig::default() })]

    #[test]
    fn safehandle_invariant_holds(seed in any::<u64>()) {
        // Construct a SafeHandle via the safe API (which should enforce the invariant).
        let handle = SafeHandle::new("/tmp/test.txt").unwrap();
        let fd = handle.raw_fd();
        // Invariant: fd is non-negative AND fcntl(F_GETFD) succeeds.
        prop_assert!(fd >= 0);
        let getfd = unsafe { libc::fcntl(fd, libc::F_GETFD) };
        prop_assert!(getfd != -1, "fcntl(F_GETFD) failed; SafeHandle invariant violated");
    }
}
```

The test EXERCISES the invariant the consumer relies on. If the provider's invariant ever weakens, the test fails.

---

## Verification protocol

Contract Verifier subagent ([subagents/contract-verifier.md](../../subagents/contract-verifier.md)) runs:

1. **Parse the cross-crate-contracts.md.**
2. **For each contract:**
   - Confirm the provider's invariant claim against the provider's docs (rustdoc JSON).
   - Confirm the contract test exists + passes.
   - Confirm the provider's version in Cargo.lock matches the audited version.
3. **Drift detection.**
   - Compare current provider version against audited version.
   - If different: re-verify the contract still holds.

---

## Workspace soundness map

`<audit-dir>/audit/synthesis/workspace-soundness-map.md` visualizes:

```
crate_a (consumer)
  ↓ CCC-001 (depends on SafeHandle)
crate_b (provider)
  ↓ CCC-007 (depends on AllocatorIdentity)
crate_c (allocator)

crate_a (consumer)
  ↓ CCC-002 (depends on PinProjection)
crate_d (async-runtime)

...
```

Stakeholders see the workspace's contract graph; a change in `crate_c::AllocatorIdentity` propagates through to `crate_a` via two hops.

---

## Refactor impact analysis

When proposing a refactor in `crate_b` that changes a contract-relevant API:

1. Search the cross-crate-contracts.md for contracts involving the affected API.
2. For each contract, list the CONSUMING crates.
3. The refactor's plan must include consumer-side test updates (or coordinate with consumers).
4. The refactor's PR must reference the contract IDs.

This prevents the "refactor crate B; breaks crate A silently" failure mode.

---

## Contract evolution

Contracts can evolve:

- **Strengthening.** Provider tightens its invariant; consumer benefits (no action required).
- **Weakening.** Provider relaxes its invariant; ALL consumers must be updated (or accept new unsoundness).
- **Removal.** Provider deletes the API; consumers must migrate.

Each evolution is documented in the contract:

```markdown
## Contract CCC-001 — version history

- v1.0 (2024-01-01): created. Invariant: raw_fd() returns valid open fd.
- v1.2 (2024-06-15): strengthened. Invariant: raw_fd() returns valid open fd AND fcntl(F_GETFD) returns success.
- v2.0 (2025-01-01): WEAKENED. Invariant: raw_fd() returns "the fd at construction time; caller must re-validate if SafeHandle has been mutated."
  - Impact: all consumers must add re-validation logic.
  - Migration: see crate_b/CHANGELOG-v2.md.
```

---

## When the workspace doesn't have cross-crate contracts

A single-crate project has no cross-crate contracts. Single-crate auditing uses the within-crate soundness-surface.md instead; this file is empty.

A workspace where every crate is independent (no inter-dep with unsafe interaction) also has none.

Skip the contract verification step entirely in those cases; document in `<audit-dir>/audit/synthesis/cross-crate-contracts-skipped.md`.

---

## Acceptance signal

A cross-crate-contracts audit passes when:

1. Every cross-crate unsafe interaction is documented as a CCC-NNN contract.
2. Every contract has a contract-test file in the consumer crate.
3. The contract-verifier subagent runs clean (all asserted invariants hold).
4. The workspace soundness map is generated + reviewable.
5. Refactor PRs touching contract-relevant APIs reference the contract IDs.
