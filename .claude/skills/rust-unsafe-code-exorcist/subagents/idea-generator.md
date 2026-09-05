---
name: idea-generator
description: Phase 10 — generate alternative refactor strategies the original audit might have missed (/idea-wizard shape).
tools:
  - Read
  - Write
---

# Idea Generator Subagent

You implement the `/idea-wizard` methodology for this audit. Read the synthesis files + classification summary; for each refactor cluster, brainstorm 3–5 alternative strategies the original audit did NOT propose.

## Your inputs

- `<audit-dir>/audit/synthesis/refactor-clusters.md`
- `<audit-dir>/audit/synthesis/invariants.md`
- `<audit-dir>/audit/classification/pass<final>_summary.jsonl`
- `<audit-dir>/audit/plans/INDEX.md`
- A sample of `audit/plans/cluster-R-NNN.md` files

## What you produce

`<audit-dir>/audit/phase10/idea-wizard-output.md`:

```markdown
# Idea-Wizard Output

For each refactor cluster, alternative strategies the original audit might have missed.

## Cluster R-001: pointer-migration in src/cache/lru.rs

**Original plan.** Migrate `*mut LruEntry` doubly-linked list to `slab::Slab<LruEntry>` with `usize` next/prev indices.

**Alternative A — Generational arena.**
Use `generational-arena::Arena<LruEntry>` instead of `slab::Slab`. Adds generation-counter to indices, catching use-after-free at the type level. Cost: extra `u32` per index, slightly larger memory footprint; benefit: stronger safety invariant.

**Alternative B — `intrusive-collections`.**
The `intrusive-collections` crate provides a doubly-linked list with explicit safety contracts, used by `tokio` and similar runtimes. Cost: bigger dep, learning curve; benefit: well-tested for exactly this pattern.

**Alternative C — `petgraph::stable_graph::StableGraph` for the LRU adjacency.**
Reuse a graph library; node-stable indices match the use case. Cost: overkill for a doubly-linked list; benefit: shared infrastructure if the project already uses petgraph.

**Recommendation.** Original plan (slab::Slab) is sound. Alternative A is worth considering if soundness > memory footprint. Alternative B is overkill for this size. Alternative C is overkill in general.

---

## Cluster B-001: SIMD safe-only feature

**Original plan.** `std::simd::u8x16` for x86_64-v3+ and aarch64; `wide::u8x16` for x86_64-v2 stable; keep `core::arch::x86_64::_mm_*` behind `#[cfg(not(feature = "safe-only"))]` for older targets.

**Alternative A — `pulp` crate (runtime SIMD-level selection).**
`pulp` picks SIMD width at runtime per CPU feature detection. Single safe binary covers all x86_64 levels. Cost: dynamic dispatch overhead (~5 cycles per call); benefit: no #[cfg] sprawl, no per-target build matrix complexity.

**Alternative B — `multiversion` crate.**
Generates multiple versions of a function (per target_feature) at compile time, picks at runtime. Like `pulp` but compile-time multi-version. Cost: larger binary; benefit: zero runtime dispatch overhead.

**Alternative C — `simba` for generic-over-SIMD code.**
`simba` provides a SIMD trait abstraction; code is generic and the SIMD-vs-scalar choice is at instantiation. Used by `nalgebra`. Cost: complex generics; benefit: one source covers all targets.

**Recommendation.** Alternative A (`pulp`) is the most promising if the dynamic-dispatch overhead is acceptable on the project's hot path — typically it is for high-cycle-cost operations and not for tight loops. Re-bench against the original safe-only path to compare.

---

## Cluster A-001: FFI surface in src/sys/syscall.rs (hardening only)

**Original plan.** Hardened SAFETY comments per wrapper; clippy lint for missing CStr null-termination at call sites.

**Alternative A — `cxx` for safer C++ interop.**
If any of the FFI is actually to C++ rather than C, `cxx` generates safer bindings than manual `extern "C"`. Cost: requires cxx-compatible interface; benefit: type-safe across the boundary.

**Alternative B — `rustix` for the POSIX subset.**
`rustix` provides safer wrappers for many syscalls (uses i/o-safety types, validates inputs). Cost: dep; benefit: less project-side unsafe.

**Recommendation.** Alternative B (`rustix`) is worth considering for the open/close/read/write subset; the rest of the FFI surface stays as-is. The hardening per the original plan IS landing; the `rustix` migration would be a follow-up bead.

---

## Patterns NOT yet attempted in the exemplar repos

Patterns observed in the wider Rust ecosystem that none of our exemplars have tried:

- **`generic_array::GenericArray<T, N>` for compile-time-sized buffers** (avoid Vec for fixed-size).
- **`auto_enums::auto_enum`** for branchless enum dispatch in async code.
- **`itoa` / `ryu` for number formatting** (replace hand-rolled SIMD formatters).
- **`crc32fast` / `xxhash-rust` for hashing** (replace hand-rolled SIMD hashers).

These are worth considering if the project has the relevant patterns; they're absent from the exemplar catalog because we haven't shipped them yet.

## How the original planner should respond

For each alternative:
- ACCEPT: revise the plan to use the alternative.
- DEFER: file a follow-up bead with "see idea-wizard-output.md § N".
- REJECT: document why the alternative was considered and rejected (perf, complexity, dep churn).

The original planner agent makes these decisions; the orchestrator tracks the choices for the audit summary.
```

## Constraints

- Be SPECIFIC. Cite real crates by name (with crates.io confirmation if possible).
- Be HONEST about trade-offs. Every alternative has a cost; document it.
- Don't propose "use a totally different language" or other non-actionable ideas.
- Don't propose alternatives the user has already explicitly rejected (per phase0_scope_decision.md § not-doing list).
- Don't modify plans yourself — your output is INPUT to the original planner agent.
