# 95-INDEX.md — Symptom → Pattern Lookup

Reverse-lookup table. Given a symptom or unsafe-kind, find the relevant pattern bundle(s).

Use during Phase 4 classification: when you see a symptom, look it up here, follow to the bundle, apply the bundle's rules.

---

## By unsafe-kind

| Unsafe kind | Primary bundle | Secondary |
|-------------|----------------|-----------|
| `unsafe { libc::* }` | [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md) | [00-CANONICAL-UNAVOIDABLE.md § 2](00-CANONICAL-UNAVOIDABLE.md) |
| `extern "C" { ... }` | [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md) | [45-WASM-AND-CXX.md](45-WASM-AND-CXX.md) (if cxx/wasm) |
| `core::ptr::read_volatile` / `write_volatile` | [55-EMBEDDED-PATTERNS.md](55-EMBEDDED-PATTERNS.md) | [00-CANONICAL-UNAVOIDABLE.md § 10](00-CANONICAL-UNAVOIDABLE.md) |
| `mem::transmute` | [70-UNINIT-AND-TRANSMUTE.md § T-1..T-4](70-UNINIT-AND-TRANSMUTE.md) | — |
| `MaybeUninit::assume_init*` | [70-UNINIT-AND-TRANSMUTE.md § U-1..U-4](70-UNINIT-AND-TRANSMUTE.md) | — |
| `Pin::new_unchecked` | [80-PIN-PROJECTIONS.md](80-PIN-PROJECTIONS.md) | — |
| `Pin::get_unchecked_mut` / `map_unchecked_mut` | [80-PIN-PROJECTIONS.md](80-PIN-PROJECTIONS.md) | — |
| `unsafe impl Send` / `unsafe impl Sync` | [50-SEND-SYNC-IMPLS.md](50-SEND-SYNC-IMPLS.md) | — |
| `slice::get_unchecked` | [20-SIMD-AND-PERF.md § Refactor S-4](20-SIMD-AND-PERF.md) | — |
| `core::arch::*` (SIMD intrinsics) | [20-SIMD-AND-PERF.md](20-SIMD-AND-PERF.md) | — |
| `core::arch::asm!` | [00-CANONICAL-UNAVOIDABLE.md § 10](00-CANONICAL-UNAVOIDABLE.md) | [55-EMBEDDED-PATTERNS.md](55-EMBEDDED-PATTERNS.md) |
| `core::hint::unreachable_unchecked` | [25-INTRINSICS-AND-COMPILER-HINTS.md § HU-1](25-INTRINSICS-AND-COMPILER-HINTS.md) | [00-CANONICAL-UNAVOIDABLE.md § 6](00-CANONICAL-UNAVOIDABLE.md) |
| `core::hint::assert_unchecked` / `core::intrinsics::assume` | [25-INTRINSICS-AND-COMPILER-HINTS.md § HU-2..HU-4](25-INTRINSICS-AND-COMPILER-HINTS.md) | — |
| `core::ptr::read` / `write` / `swap` / `drop_in_place` | [25-INTRINSICS-AND-COMPILER-HINTS.md § PR-1, PR-5, PR-6](25-INTRINSICS-AND-COMPILER-HINTS.md) | [10-POINTER-MIGRATIONS.md](10-POINTER-MIGRATIONS.md) |
| `core::ptr::read_unaligned` / `write_unaligned` | [25-INTRINSICS-AND-COMPILER-HINTS.md § PR-2](25-INTRINSICS-AND-COMPILER-HINTS.md) | [70-UNINIT-AND-TRANSMUTE.md](70-UNINIT-AND-TRANSMUTE.md) |
| `core::ptr::copy` / `copy_nonoverlapping` | [25-INTRINSICS-AND-COMPILER-HINTS.md § PR-4](25-INTRINSICS-AND-COMPILER-HINTS.md) | — |
| `core::ptr::read_volatile` / `write_volatile` | [25-INTRINSICS-AND-COMPILER-HINTS.md § PR-3](25-INTRINSICS-AND-COMPILER-HINTS.md) | [55-EMBEDDED-PATTERNS.md](55-EMBEDDED-PATTERNS.md) |
| `core::intrinsics::atomic_*_unsynchronized` | [25-INTRINSICS-AND-COMPILER-HINTS.md § AT-1](25-INTRINSICS-AND-COMPILER-HINTS.md) | [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md) |
| `UnsafeCell::<T>` / `UnsafeCell::new` / `UnsafeCell::get` | [27-UNSAFECELL-PATTERNS.md](27-UNSAFECELL-PATTERNS.md) | [50-SEND-SYNC-IMPLS.md § UC-7](50-SEND-SYNC-IMPLS.md) |
| `Cell` / `RefCell` / `OnceCell` candidates for refactor | [27-UNSAFECELL-PATTERNS.md § UC-1..UC-3](27-UNSAFECELL-PATTERNS.md) | — |
| Atomic ops with explicit Ordering | [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md) | [75-LOCK-FREE-PATTERNS.md](75-LOCK-FREE-PATTERNS.md) |
| `core::sync::atomic::fence` | [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md) | — |
| Raw pointer math (`p.add(n)`, `p as usize`, etc.) | [10-POINTER-MIGRATIONS.md](10-POINTER-MIGRATIONS.md) | [PROVENANCE-MODEL.md](../methodology/PROVENANCE-MODEL.md) |
| `Box::from_raw` / `Box::into_raw` | [10-POINTER-MIGRATIONS.md](10-POINTER-MIGRATIONS.md) | [65-ALLOCATOR-PATTERNS-DEEP.md](65-ALLOCATOR-PATTERNS-DEEP.md) |
| `Arc::into_raw` / `Arc::from_raw` | [75-LOCK-FREE-PATTERNS.md § LF-1](75-LOCK-FREE-PATTERNS.md) | [10-POINTER-MIGRATIONS.md](10-POINTER-MIGRATIONS.md) |
| `GlobalAlloc::alloc` / `dealloc` | [65-ALLOCATOR-PATTERNS-DEEP.md § AL-5](65-ALLOCATOR-PATTERNS-DEEP.md) | [00-CANONICAL-UNAVOIDABLE.md § 7](00-CANONICAL-UNAVOIDABLE.md) |
| Macro-generated `unsafe` (zerocopy, pin-project, etc.) | [40-MACRO-GENERATED-UNSAFE.md](40-MACRO-GENERATED-UNSAFE.md) | — |
| Project-own derive emitting unsafe | [85-PROC-MACRO-UNSAFE.md](85-PROC-MACRO-UNSAFE.md) | [40-MACRO-GENERATED-UNSAFE.md](40-MACRO-GENERATED-UNSAFE.md) |

---

## By symptom

| Symptom | Likely failure mode | See |
|---------|---------------------|-----|
| miri "no item granting read access" | Stacked Borrows reborrow violation | [STACKED-VS-TREE-BORROWS.md](../methodology/STACKED-VS-TREE-BORROWS.md), [COMMON-FAILURE-CASES.md § F-007](../methodology/COMMON-FAILURE-CASES.md) |
| miri "pointer with no provenance" | Strict-provenance violation | [PROVENANCE-MODEL.md](../methodology/PROVENANCE-MODEL.md), [COMMON-FAILURE-CASES.md § F-008](../methodology/COMMON-FAILURE-CASES.md) |
| miri "out-of-bounds pointer use" | Pointer arithmetic past allocation | [10-POINTER-MIGRATIONS.md](10-POINTER-MIGRATIONS.md) |
| miri "reading uninitialized memory" | `MaybeUninit::assume_init` on partial init | [70-UNINIT-AND-TRANSMUTE.md](70-UNINIT-AND-TRANSMUTE.md), [COMMON-FAILURE-CASES.md § F-002](../methodology/COMMON-FAILURE-CASES.md) |
| Process abort on panic from FFI callback | Panic across `extern "C"` | [60-FFI-PATTERNS.md § F-3](60-FFI-PATTERNS.md), [COMMON-FAILURE-CASES.md § F-004](../methodology/COMMON-FAILURE-CASES.md) |
| Use-after-free in linked-list / cache | Raw pointer to Vec-backed nodes | [10-POINTER-MIGRATIONS.md § P-1](10-POINTER-MIGRATIONS.md), [65-ALLOCATOR-PATTERNS-DEEP.md § AL-1](65-ALLOCATOR-PATTERNS-DEEP.md), [COMMON-FAILURE-CASES.md § F-001](../methodology/COMMON-FAILURE-CASES.md) |
| Double-drop / double-free | Panic during `MaybeUninit` init | [70-UNINIT-AND-TRANSMUTE.md § U-3](70-UNINIT-AND-TRANSMUTE.md), [COMMON-FAILURE-CASES.md § F-002](../methodology/COMMON-FAILURE-CASES.md) |
| Nondeterministic data corruption | Data race / wrong `unsafe impl Sync` | [50-SEND-SYNC-IMPLS.md](50-SEND-SYNC-IMPLS.md), [COMMON-FAILURE-CASES.md § F-003](../methodology/COMMON-FAILURE-CASES.md) |
| Async future segfault after move | Self-referential type moved | [80-PIN-PROJECTIONS.md § P-3](80-PIN-PROJECTIONS.md), [COMMON-FAILURE-CASES.md § F-005](../methodology/COMMON-FAILURE-CASES.md) |
| `MAP_FAILED: too many mappings` | mmap leaked on async cancellation | [60-FFI-PATTERNS.md § F-2](60-FFI-PATTERNS.md), [COMMON-FAILURE-CASES.md § F-006](../methodology/COMMON-FAILURE-CASES.md) |
| Wrong values after sequential ops | Wrong atomic Ordering | [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md), [COMMON-FAILURE-CASES.md § F-016](../methodology/COMMON-FAILURE-CASES.md) |
| Deadlock under cancellation | Mutex held across await | [COMMON-FAILURE-CASES.md § F-014](../methodology/COMMON-FAILURE-CASES.md) |
| Allocation pressure regression after refactor | Allocator identity changed | [65-ALLOCATOR-PATTERNS-DEEP.md](65-ALLOCATOR-PATTERNS-DEEP.md), [COMMON-FAILURE-CASES.md § F-010](../methodology/COMMON-FAILURE-CASES.md) |
| loom "preemption_bound exceeded" | Test budget too small | [COMMON-FAILURE-CASES.md § F-011](../methodology/COMMON-FAILURE-CASES.md), [TOOLCHAIN-RUNBOOK.md § loom](../methodology/TOOLCHAIN-RUNBOOK.md) |
| Test passes after mutation | Test isn't pinning behavior | [TOOLCHAIN-RUNBOOK.md § cargo-mutants](../methodology/TOOLCHAIN-RUNBOOK.md), [COMMON-FAILURE-CASES.md § F-012](../methodology/COMMON-FAILURE-CASES.md) |

---

## By project shape

| Project shape | Read first | Then |
|---------------|------------|------|
| FFI-heavy (libc, windows-sys, bindgen) | [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md) | [00-CANONICAL-UNAVOIDABLE.md](00-CANONICAL-UNAVOIDABLE.md) |
| SIMD-heavy | [20-SIMD-AND-PERF.md](20-SIMD-AND-PERF.md) | [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md) (if vectorized atomics) |
| Async runtime | [80-PIN-PROJECTIONS.md](80-PIN-PROJECTIONS.md) | [75-LOCK-FREE-PATTERNS.md](75-LOCK-FREE-PATTERNS.md), [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md) |
| Custom allocator | [65-ALLOCATOR-PATTERNS-DEEP.md](65-ALLOCATOR-PATTERNS-DEEP.md) | [00-CANONICAL-UNAVOIDABLE.md § 7](00-CANONICAL-UNAVOIDABLE.md) |
| Embedded (cortex-m, etc.) | [55-EMBEDDED-PATTERNS.md](55-EMBEDDED-PATTERNS.md) | [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md) (if vendor SDK) |
| Wasm / cxx interop | [45-WASM-AND-CXX.md](45-WASM-AND-CXX.md) | [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md) |
| Project with custom derives | [85-PROC-MACRO-UNSAFE.md](85-PROC-MACRO-UNSAFE.md) | [40-MACRO-GENERATED-UNSAFE.md](40-MACRO-GENERATED-UNSAFE.md) |
| General library (mixed) | [10-POINTER-MIGRATIONS.md](10-POINTER-MIGRATIONS.md) | [50-SEND-SYNC-IMPLS.md](50-SEND-SYNC-IMPLS.md), [70-UNINIT-AND-TRANSMUTE.md](70-UNINIT-AND-TRANSMUTE.md) |
| Concurrent (Mutex / RwLock / arc-swap heavy) | [30-CONCURRENCY-PATTERNS.md](30-CONCURRENCY-PATTERNS.md) | [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md), [75-LOCK-FREE-PATTERNS.md](75-LOCK-FREE-PATTERNS.md) |
| Cryptography / secret-handling | [100-CRYPTOGRAPHY-AUDIT.md](100-CRYPTOGRAPHY-AUDIT.md) | [70-UNINIT-AND-TRANSMUTE.md](70-UNINIT-AND-TRANSMUTE.md) |
| Tagged-pointer / strict-provenance migration | [130-TAGGED-POINTER-MIGRATION.md](130-TAGGED-POINTER-MIGRATION.md) | [10-POINTER-MIGRATIONS.md](10-POINTER-MIGRATIONS.md), [PROVENANCE-MODEL.md](../methodology/PROVENANCE-MODEL.md) |
| Already audited — verify harness + CI integration | [90-OPERATIONS.md](90-OPERATIONS.md) | [CI-INTEGRATION.md](../methodology/CI-INTEGRATION.md) |

---

## By exemplar repo

| Repo | Primary pattern | See |
|------|-----------------|-----|
| `/dp/asupersync` | io_uring + mmap | [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md), [00-CANONICAL-UNAVOIDABLE.md § 3, 4](00-CANONICAL-UNAVOIDABLE.md) |
| `/dp/beads_rust` | rusqlite FFI + transmute | [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md), [70-UNINIT-AND-TRANSMUTE.md](70-UNINIT-AND-TRANSMUTE.md) |
| `/dp/mcp_agent_mail_rust` | Pin self-ref | [80-PIN-PROJECTIONS.md § P-3](80-PIN-PROJECTIONS.md) |
| `/dp/pi_agent_rust` | Volatile MMIO | [55-EMBEDDED-PATTERNS.md](55-EMBEDDED-PATTERNS.md) |
| `/dp/rich_rust` | SIMD | [20-SIMD-AND-PERF.md](20-SIMD-AND-PERF.md) |
| `/dp/frankensqlite` | C binding | [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md), [45-WASM-AND-CXX.md](45-WASM-AND-CXX.md) (longjmp) |
| `/dp/frankentui` | termios + signals | [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md), [00-CANONICAL-UNAVOIDABLE.md § 9](00-CANONICAL-UNAVOIDABLE.md) |
| `/dp/franken_engine` | scheduler atomics | [75-LOCK-FREE-PATTERNS.md](75-LOCK-FREE-PATTERNS.md), [35-ATOMICS-AND-ORDERINGS.md](35-ATOMICS-AND-ORDERINGS.md) |
| `/dp/frankenlibc` | Syscalls | [60-FFI-PATTERNS.md § F-1](60-FFI-PATTERNS.md) |
| `/dp/frankenfs` | Allocator | [65-ALLOCATOR-PATTERNS-DEEP.md](65-ALLOCATOR-PATTERNS-DEEP.md) |

---

## How to use this index during the audit

1. **Phase 4 classifier** — see a site; look up its kind in the unsafe-kind table; follow to the bundle; apply rules.
2. **Phase 6 adversarial** — see a (B) or (C) classification; check the bundle's anti-patterns to see if the classification is at risk.
3. **Phase 10 maintainer-empathy** — given a symptom from CI / production / reports, look up in the symptoms table to navigate to the relevant audit material.
4. **New audit kickoff** — given a project shape, find the entry points in the by-shape table.

The index is the entry point. The bundles are the depth.
