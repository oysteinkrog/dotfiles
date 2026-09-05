# REJECTED-PATTERNS.md — Refactors We Explicitly Chose NOT to Land

This catalog answers the question:

> "We tried to make this safe. We measured. We kept the `unsafe`. Why?"

Every entry below is a refactor that was **considered, evaluated, and rejected** in the exemplar corpus — usually because the safe alternative imposed a measurable, unrecoverable cost (perf, semantics, build complexity, or downstream ABI). Future adversarial reviewers should consult this file **before** re-proposing any of these as candidate (B) → (C) graduations. They've already been litigated; re-litigating wastes audit budget unless new evidence has arrived.

This file is the *negative space* of the audit. The positive space — patterns we did refactor — lives in [00-CANONICAL-UNAVOIDABLE.md](../patterns/00-CANONICAL-UNAVOIDABLE.md) and the per-kind pattern bundles. Both views together explain WHY a project's current `unsafe` posture looks the way it does.

---

## How to use this catalog

1. **Phase 4 / 6 classifier reviewers:** before downgrading an (A) → (B) or (B) → (C), check whether the project's site matches any rejected pattern below. If it does, the burden of proof is on the reviewer to show *what changed since rejection* — new toolchain feature, new crate, new perf profile, different target.
2. **Phase 10 maintainer-empathy reviewer:** scan for patterns the audit is about to recommend that have already been rejected upstream. If so, surface that in `REVIEWER_RESPONSES.md` so the maintainer doesn't have to discover it themselves.
3. **Skill maintainers:** as new rejection events surface (from the exemplar repos OR from third-party audits the skill runs), append entries here with the `[R-NNN]` anchor format. Cross-reference the originating `[E-NNN]` in [EXEMPLAR-CATALOG.md](../source/EXEMPLAR-CATALOG.md).

---

## The rejections table

Each row: pattern proposed, exemplar evidence, measured cost, decision rationale, and the *specific condition* under which the rejection might be revisited.

| ID | Proposed refactor | Repo / evidence | Safe alt tried | Measured cost | Why kept unsafe | Re-litigate if |
|----|-------------------|-----------------|----------------|---------------|-----------------|----------------|
| [R-001] | Replace `io_uring` setup + SQE/CQE manipulation with `epoll` syscalls | `/dp/asupersync` § [E-001] | `mio::Poll` + `epoll(EPOLLET)` thin wrapper | 3× regression on canonical throughput benchmark; tail latency p99 worse by 2.4× | The (A) is the kernel ABI, not the Rust code. io_uring's submission ring IS the project's reason for existing. | Linux ships an `io_uring`-shaped safe Rust API in `std::os::linux` (tracking issue: none today). |
| [R-002] | Replace AVX-512 codegen path with AVX2-only | `/dp/rich_rust` § [E-040] § Rejected | `+avx2` only, no `+avx512f` | +18% mean on x86_64-v4 microbench; -40% on AVX-512-bound workloads when present | Kept as opt-in `+avx512` target_feature; default ships safe + AVX2 because consumer-CPU thermal throttling made AVX-512 perf unreliable | LLVM autovectorizes the same patterns to AVX-512 reliably (mature backend pass) OR target hardware is exclusively server-class. |
| [R-003] | Replace `core::intrinsics::atomic_load_unsynchronized` with `AtomicXxx::load(Relaxed)` | `/dp/franken_engine` § [E-070], [E-109] | `core::sync::atomic::AtomicU64::load(Relaxed)` | `Relaxed` has a fence guarantee the worker-parking protocol can't tolerate (subtle: the fence orders OTHER atomics, breaking the parking invariant). loom model under `Relaxed` reproduces the deadlock. | The protocol's correctness REQUIRES the unsynchronized read; documented loom proof | `core::sync::atomic` exposes a `load_unsynchronized` method (currently nightly-only unstable intrinsic). |
| [R-004] | Replace `[profile.release] panic = "abort"` with default unwind + `catch_unwind` boundaries | `/dp/frankenlibc` § [E-083], [E-105] | `std::panic::catch_unwind` at every `extern "C"` boundary | +2% binary size; "+catch_unwind" doesn't compose with `longjmp`-style C callbacks; some sites have NO Rust frame above them | Crate-wide `panic = "abort"` makes the cross-FFI behavior provable; per-site `catch_unwind` requires auditing every callsite for unwind-safety | Project no longer exposes `extern "C"` callbacks (then `catch_unwind` becomes viable). |
| [R-005] | Replace `mem::transmute` for inode-on-disk format with `serde` | `/dp/frankenfs` § [E-092] alternative | `serde_bincode::serialize_into` | +40% throughput regression on the canonical 1M-inode workload; serde's bincode does branch-per-field decoding vs. transmute's zero-cost reinterpret | `zerocopy::FromBytes` derive provides safe + zero-cost (`[E-092]` is the won refactor); serde is the path that didn't win. | Zerocopy doesn't support the type (e.g., enum with non-uniform variants); serde is then the realistic alternative. |
| [R-006] | Replace `Mutex<VecDeque<Task>>` for scheduler queue (eliminate lock-free) | `/dp/franken_engine` § [E-070] Rejected | `parking_lot::Mutex<VecDeque<Task>>` | Factor-of-10 throughput cliff under sustained 16-thread load; tail latency wildly skewed. Documented in `docs/why-lockfree.md`. | The project IS a scheduler; the lock-free queue IS the differentiator | Workload changes so that lock contention is rare (e.g., few workers, batched dispatch). |
| [R-007] | Replace sqlite3 C bindings with a pure-Rust sqlite implementation | `/dp/frankensqlite` § [E-050] Rejected | Hand-rolled or `rusqlite-mvp` | Behavior-parity gap: replicating "behaves exactly like sqlite3 in every corner case" is unbounded (lock manager, WAL, page format, etc.) | The FFI IS intentional; the project's contract IS sqlite3 compatibility | sqlite3 upstream provides a Rust port AND the port is bit-identical AND adopted by the project's customers. |
| [R-008] | Replace `volatile-register` with non-volatile reads | `/dp/pi_agent_rust` § [E-030] Rejected | Plain `*const u32` reads | LLVM at -O3 elides reads it considers redundant — silently miscompiles MMIO loops | MMIO requires volatile semantics by definition; no safe equivalent exists in stable Rust for non-volatile-elided reads | Embedded HAL provides a guaranteed-non-elided read primitive in core (currently does not). |
| [R-009] | Replace `pthread_kill` in signal handler with safe Rust signal-handling | `/dp/frankentui` § [E-061] (companion rejection) | `signal-hook` + channel | `signal-hook` itself uses unsafe internally + adds an allocator-touching path inside the handler (UB in async-signal context) | Handlers MUST be async-signal-safe; only `pthread_kill` + pre-allocated channel via `signalfd` qualifies | A Rust crate provides a verified async-signal-safe handler abstraction. |
| [R-010] | Replace `bumpalo::Vec` (arena) with `Vec` for the parse tree | `/dp/rich_rust` (companion rejection, not in [E-040..045]) | `Vec<Node>` + `Box<Node>` for the recursive parse tree | +60% allocation count, +35% wall-clock on the canonical parse benchmark, fragmentation visible in p99 latencies | The arena's allocator identity carries the perf profile; `Vec` is NOT isomorphic (operator 📐 Allocator-Identity catches this) | Per-arena allocators land in stable Rust + match bumpalo's perf. |
| [R-011] | Replace io_uring's `core::sync::atomic::fence(Ordering::Release/Acquire)` with `compiler_fence` | `/dp/asupersync` § [E-112] | `compiler_fence(Acquire)` / `compiler_fence(Release)` | `compiler_fence` is single-threaded ordering only; the kernel reads from a different CPU, requiring full memory-fence semantics | The kernel ABI requires the full fence | Future Rust adds a kernel-ABI-aware fence primitive (currently no proposal). |
| [R-012] | Replace `[E-102]`'s `slab::Slab` LRU with `generational-arena` | `/dp/frankenfs` § [E-102] alternative | `generational_arena::Arena<LruEntry>` | +5% memory overhead at 1M entries (extra u32 per slot for generation counter); the LRU lifecycle doesn't need use-after-free protection because the linked-list invariants already enforce it | `slab::Slab` wins on memory; the protection is redundant given the LRU's existing discipline | Memory budget loosens OR a different use case exposes use-after-free risk. |
| [R-013] | Replace per-shard `Mutex<HashMap>` with sharded-`Mutex<HashMap>` | `/dp/mcp_agent_mail_rust` § [E-103] alternative | `[Mutex<HashMap<MsgId, Msg>>; 16]` | -7% p99 lookup vs DashMap; -32% insert vs DashMap; high contention dominates | `DashMap` wins on the measured workload ([E-103] is the won refactor) | Project profile changes so that contention is low + the simpler primitive wins. |
| [R-014] | Replace `core::hint::unreachable_unchecked` with `unreachable!()` macro | `/dp/rich_rust` § [E-104] | Safe `match _ => unreachable!()` | +18% on 100M-call-per-second hot path; LLVM loses the codegen hint and adds a branch + panic infrastructure | The hint IS the optimization; the safe variant adds runtime cost the project's perf budget can't absorb | Compiler proves the unreachability + erases the panic path automatically (currently doesn't). |
| [R-015] | Replace `Pin<Box<WsStream>>` self-reference with split-struct (`ReaderHalf` + `BufferHalf`) | `/dp/mcp_agent_mail_rust` § [E-111] alternative | Decoupled types holding `Arc<Buffer>` | Adds an indirection + an `Arc` clone per receive; +9% on the canonical receive benchmark; the split also breaks the "single struct manages full lifecycle" maintainability invariant | The `Pin<Box<Self>>` self-ref is the actual mental model; the split is a workaround that paid both perf and clarity cost | A future Rust feature allows safe self-referential structs (e.g., `'self` lifetime accepted; currently no proposal). |
| [R-016] | Replace `unsafe impl Send` on `*const T` newtype with `Arc<T>` | Multiple repos — `/dp/franken_engine`, `/dp/frankenfs`, generic | `Arc<T>` for shared ownership | Forces atomic refcount overhead on the read path; some sites are read-mostly with the refcount provably redundant given the surrounding ownership | The `*const T` newtype is auditable + (A) at a single site; `Arc` would impose runtime cost across all readers | The site's ownership becomes ambiguous enough that the `Arc` discipline is needed for correctness, not just convention. |
| [R-017] | Replace `core::arch::asm!` for fast syscall path with `libc::syscall` | `/dp/frankenlibc` § (companion to [E-080]) | `libc::syscall(SYS_xxx, ...)` | +60ns per syscall in the canonical sysbench; `libc::syscall` is a varargs wrapper that adds register shuffling and a function-call boundary | Inline asm is single-instruction; the project's purpose IS the low-overhead syscall path | Project no longer cares about that 60ns OR LLVM adds a `naked_call` that compiles to single-instruction syscalls reliably. |
| [R-018] | Replace `nix` / `rustix` in `frankenlibc` to "use the safe wrapper" | `/dp/frankenlibc` § [E-080] Rejected | `nix` crate for the syscall surface | `nix` IS a downstream user of `frankenlibc` (and rustix is its sibling) — the project is the layer they consume. Cyclic dep. | The project's role is to BE the safe-wrapper crate | Project pivots to a different role in the ecosystem. |

---

## Discipline: how to use this when reviewing classifications

### For a (B) → (C) graduation candidate

Before recommending graduation, walk through:

1. Is the proposed safe alternative on this list?
2. Was it rejected in a repo of similar perf characteristics (same target, similar workload)?
3. Has the **measured cost** in the rejection still applicable today? Run the bench again before re-proposing.

If the rejection still holds, document the candidate's failure in the site's plan under "Graduation history — declined, prior art at [R-NNN]" and keep the site as (B).

### For an (A) classification challenge

Before challenging an (A), check whether the (A) survived a documented adversarial pass in the exemplar corpus (the [E-NNN] entries in [EXEMPLAR-CATALOG.md](../source/EXEMPLAR-CATALOG.md) note these). If yes, the challenger inherits the burden of explaining what's different in the project under audit — different platform target, different workload, different toolchain version, different crate version.

### For a SAFETY-comment rewrite

When hardening a SAFETY comment for a kept-unsafe site, include a reference to the relevant `[R-NNN]` entry if one exists, e.g.:

```rust
// SAFETY: io_uring submission ring; kernel ABI requires Release fence on write.
// See REJECTED-PATTERNS.md [R-001] and [R-011] for the rationale behind keeping
// this unsafe vs. the rejected safe alternatives.
```

This shortens the cold-read time for a future maintainer who wonders "couldn't we just…"

---

## Adding new rejections

When a new audit produces a rejection event:

1. Allocate the next `[R-NNN]` anchor.
2. Fill in the row above with measured numbers, NOT impressions.
3. Cross-reference any companion `[E-NNN]` in [EXEMPLAR-CATALOG.md](../source/EXEMPLAR-CATALOG.md).
4. Note the **specific condition** under which the rejection would be revisited. This is the most useful field — it tells the future reader when to re-litigate.

A rejection without a measured cost is not a rejection — it's a deferral. Either measure it now, or file a follow-up bead to measure it later. Don't let "we tried it and it felt slower" turn into folklore.

---

## See also

- [EXEMPLAR-CATALOG.md](../source/EXEMPLAR-CATALOG.md) — the positive-space companion (refactors that DID land).
- [00-CANONICAL-UNAVOIDABLE.md](../patterns/00-CANONICAL-UNAVOIDABLE.md) — the (A) patterns inventoried by language reference.
- [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md) — the (B) → (C) graduation rule that's most likely to trigger consulting this catalog.
- [subagents/adversarial-reclassifier.md](../../subagents/adversarial-reclassifier.md) — Phase 6 reviewer; reads this file before proposing reclassifications.
