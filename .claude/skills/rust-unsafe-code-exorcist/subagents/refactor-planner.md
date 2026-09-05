---
name: refactor-planner
description: Phase 5 — draft refactor plans per cluster. (C) gets full safe code; (B) gets safe-only impl; (A) gets hardened SAFETY.
tools:
  - Read
  - Write
  - Edit
  - Bash
---

# Refactor Planner Subagent

You are assigned ONE cluster from `<audit-dir>/audit/synthesis/refactor-clusters.md`. You draft the full plan for every member site of that cluster.

## Your inputs

- The cluster note (member sites, shared invariant, proposed safe wrapper).
- Per-site write-ups for every member.
- The classification per member.
- The pattern bundle most relevant to the cluster's shape (e.g., `references/patterns/10-POINTER-MIGRATIONS.md`).

## Your output

For each member site, a file at `<audit-dir>/audit/plans/site-<id>.md` per `assets/refactor-plan-template.md`.

The output form depends on the bucket:

### (C) plan

```markdown
# site-NNNN — Plan

Bucket: (C) REFACTORABLE
Cluster: R-XXX
Pattern: <name>

## Safe replacement code

<!-- FULL code, not pseudocode, not sketch. Paste-ready. -->

```rust
// Before (current unsafe):
// <verbatim source>

// After (safe rewrite):
<full Rust code>
```

## Property-based equivalence test

```rust
// <path: audit/tests/equivalence_site_NNNN.rs>
use proptest::prelude::*;

proptest! {
    #[test]
    fn equivalence(x in <strategy>) {
        let unsafe_result = original::f(x.clone());
        let safe_result = rewritten::f(x.clone());
        prop_assert_eq!(unsafe_result, safe_result);
    }
}
```

Inputs covered:
- normal path
- failure path (panic / error / edge case)
- allocator-pressure (where relevant)

## Metamorphic test (where applicable)

```rust
proptest! {
    #[test]
    fn metamorphic(x in <strategy>) {
        let transformed = transform(x.clone());
        prop_assert_eq!(f_safe(transformed.clone()), transform(f_safe(x)));
    }
}
```

## Loom model (if concurrency-touching)

```rust
#[cfg(loom)]
#[test]
fn loom_<...>() {
    loom::model(|| {
        // model
    });
}
```

## Miri command

```bash
cargo +nightly miri test --test equivalence_site_NNNN
# expected: 0 errors, no UB reports
```

## Risk + API change

Risk: <Low | Medium | High>
API change: <none | additive | breaking>
Migration path (if breaking): <description>

## Allocator identity

Original allocator: <name>
Rewrite allocator: <name>
Preserved? <yes | no — explain>

## Drop-glue trace

For every exit path (success, return, `?`, panic, await-drop):
- success path: <which destructors run, in what order>
- panic in mid-init: <state>
- await-drop: <state>

All destructors confirmed to run? <yes | no — explain>

## Bead acceptance criteria

```
cargo test -p <crate> --test equivalence_site_NNNN
cargo +nightly miri test -p <crate> --test equivalence_site_NNNN
cargo bench --bench <bench> -- --output-format bencher
  expected: criterion mean within <X>% of baseline
cargo +nightly geiger -p <crate>
  expected: count decreased by 1
```
```

### (B) plan

```markdown
# site-NNNN — Plan

Bucket: (B) PERF_ONLY
Pattern: SIMD / get_unchecked / lock-free

## Safe-only branch

```rust
#[cfg(not(feature = "safe-only"))]
pub fn hot_fn(...) -> ... {
    // current unsafe
}

#[cfg(feature = "safe-only")]
pub fn hot_fn(...) -> ... {
    // safe alternative via std::simd / wide / autovec
}
```

## Per-target benches

| Target | criterion (default) | criterion (safe-only) | hyperfine (default) | hyperfine (safe-only) | Δ |
|--------|---------------------|----------------------|---------------------|----------------------|---|
| x86_64-v2 | X ns | Y ns | A ms | B ms | +N% |
| x86_64-v3 | ... | ... | ... | ... | ... |
| aarch64 | ... | ... | ... | ... | ... |

User budget: <N%>
Targets within budget: <list>
Targets over budget: <list>

Graduation decision per target:
- Within budget → graduate to (C); refactor and delete unsafe for that target's path.
- Outside budget → keep (B); ship safe-only feature.

## CI matrix entry

```yaml
matrix:
  os: [ubuntu-latest, macos-14]
  feature: [all-features, safe-only]
  rustflags:
    - "-C target-cpu=x86-64-v2"
    - "-C target-cpu=x86-64-v3"
    - "-C target-cpu=apple-m1"  # macos-14
```

## Bead acceptance criteria

```
cargo test --features safe-only --no-default-features -p <crate>
cargo bench --bench <bench>
hyperfine ...
```
```

### (A) plan

```markdown
# site-NNNN — Plan

Bucket: (A) STRICTLY_UNAVOIDABLE
Pattern: <FFI | Pin self-ref | allocator | atomic intrinsic | signal handler | volatile MMIO>

## Hardened SAFETY comment

Place AT the unsafe site:

```rust
/// <prose explanation of what the unsafe does>
///
/// # Safety
///
/// The caller MUST guarantee:
/// - <specific invariant 1>
/// - <specific invariant 2>
///
/// These invariants are enforced by:
/// - <where the invariant is established in code>
///
/// What breaks if violated:
/// - <specific UB or panic outcome>
///
/// Unwinding through this site is UB / safe IFF ...
/// Async cancellation: ...
/// (relevant cross-cutting concerns)
unsafe fn or_block_or_impl(...) {
    ...
}
```

## Clippy / lint rule (if expressible)

```toml
# clippy.toml or .clippy.toml
disallowed-methods = [
    { path = "...", reason = "violates the proof obligation for site-NNNN; use ..." },
]
```

If clippy doesn't cover it, document the lint as a follow-up bead (custom proc-macro lint).

## Bead acceptance criteria

```
# SAFETY comment landed
grep -A 20 "fn or_block_or_impl" <crate>/src/... | grep "# Safety"
# Lint rule landed (if applicable)
cargo clippy -p <crate>
# No regression in cargo-geiger (this site stays in (A); count unchanged)
cargo +nightly geiger -p <crate>
```
```

## Cluster-level harmonization

After drafting all per-site plans for your cluster, check:
- Do all member-site plans use the same safe wrapper? If not, propose a single one.
- Does any member's plan contradict another's (e.g., conflicting API changes)?
- Are any member sites missing a plan?

Write `<audit-dir>/audit/plans/cluster-R-NNN.md` with the cluster-level decisions and per-member back-references.

## What you do NOT do

- Do NOT modify the project repo.
- Do NOT implement the rewrite IN the project (only in the audit dir's plan).
- Do NOT introduce a new branch.
- Per AGENTS.md: no destructive rewrites; no file deletion; incremental edits only.

## Constraints

- Code in plans must be paste-ready (compileable in isolation, given the cluster's safe wrapper exists).
- No `unwrap()` / `expect()` without a SAFETY-style comment explaining why.
- Allocator identity must be preserved.
- Public API changes must be documented + migration path provided.
