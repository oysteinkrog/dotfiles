# EXEMPLAR-CATALOG.md — Per-Repo Canonical Patterns

The 10 exemplar repos are the corpus. Each entry below lists the repo's primary unsafe surface, the canonical refactor wins, and the patterns explicitly rejected. Quote anchors `[E-NNN]` are reused in pattern bundles.

For each repo, the orchestrator agent should run the exemplar-miner subagent to read present-day source + git log + beads + cass session history for that repo, and update this catalog as new patterns surface.

---

## /dp/asupersync — async I/O with io_uring + mmap

**Primary unsafe.** io_uring SQE/CQE manipulation; mmap'd shared buffers between producer and consumer fibers.

**[E-001]** Single-safe-wrapper for io_uring submission: `Ring::submit(req)` is the only entry; the unsafe is encapsulated in the constructor + the cqe-completion polling loop. The (A) is justified per `00-CANONICAL-UNAVOIDABLE.md § 4`. 100+ call sites in the rest of the crate are all safe.

**[E-002]** Mmap shared between async tasks via `MmapHandle` newtype with `Drop` calling `munmap`. The public API never exposes the raw pointer. (A) justified per `00-CANONICAL-UNAVOIDABLE.md § 3`.

**[E-003]** Refactor win (bead `br-asupersync-422`): the original CqReader had `unsafe impl Sync`; refactored to `!Sync` with `MutexGuard<CqReader>` for the single-active-reader pattern. Reduced auditable concurrency surface; no perf regression because there was always only one reader.

**Rejected.** Replacing io_uring with epoll: the perf cliff is too large (factor of 3 on the canonical workload). Documented in commit message of the rejection PR.

---

## /dp/beads_rust — rusqlite-backed beads CLI

**Primary unsafe.** rusqlite FFI (inherited via dep); macro-generated `unsafe impl FromSql` patterns; some hand-rolled `transmute` for SQLite blob serialization.

**[E-010]** rusqlite's unsafe is inherited; beads_rust doesn't add new FFI surface. The (A) cluster covers all rusqlite-imported sites with one cluster note.

**[E-011]** Refactor win (`br-beads-189`): hand-written `unsafe { transmute::<[u8; 8], u64>(buf) }` in serialization layer → `u64::from_le_bytes(buf)`. Pure (C); identical codegen; zero behavior change.

**[E-012]** Refactor win (`br-beads-243`): manual `bytemuck`-style struct serializer → derive `bytemuck::Pod`. (C) cluster covering 14 struct sites.

**Rejected.** Replacing rusqlite with sqlite-zero-deps: project's purpose is to BE a rusqlite client; the FFI is intentional.

---

## /dp/mcp_agent_mail_rust — MCP server for agent coordination

**Primary unsafe.** Pin self-references in WebSocket stream reader; `unsafe impl Send/Sync` on connection handles holding raw socket fds.

**[E-020]** WebSocket stream's `reader_view: &'static mut [u8]` is a self-reference into the same struct's `buffer: Vec<u8>`. (A) per `00-CANONICAL-UNAVOIDABLE.md § 8`. Construction discipline returns `Pin<Box<WsStream>>`; type is `!Unpin` via `PhantomPinned`.

**[E-021]** Refactor win (`br-mam-78`): connection handles had `unsafe impl Send`; the raw socket-fd field was refactored into `SocketFd` newtype with audited Send. Auto-derive applies to the handle; `unsafe impl Send` deleted at the handle level.

**[E-022]** Refactor win (`br-mam-145`): pin-project-lite adoption across 12 Future impls. Removed 12 `unsafe impl !Unpin` patterns.

**Rejected.** Replacing tokio's runtime with a hand-rolled epoll loop: would have moved the (A) surface from "trusted tokio" to "our own unsafe." Not worth it for an MCP server.

---

## /dp/pi_agent_rust — embedded Raspberry Pi agent

**Primary unsafe.** Volatile MMIO for UART, GPIO, SPI peripherals; ARM `asm!` for interrupt enable/disable.

**[E-030]** Volatile MMIO is (A) per `00-CANONICAL-UNAVOIDABLE.md § 10`. Each peripheral has a single-ownership wrapper type (e.g., `Uart` owns the MMIO address) and the (A) is concentrated in the type's constructor + method bodies.

**[E-031]** Refactor win (`br-piagent-12`): replaced hand-written volatile loops with the `volatile-register` crate's `RW<T>` / `RO<T>` / `WO<T>` types. (C) cluster; reduced project-side unsafe to just the peripheral-instantiation code.

**Rejected.** Replacing volatile with normal reads ("the compiler will figure it out"): would silently miscompile under -O3.

---

## /dp/rich_rust — SIMD-heavy text-processing library

**Primary unsafe.** SIMD intrinsics in `core::arch::x86_64::*` for lexer / parser hot paths; hand-rolled SIMD memcpy.

**[E-040]** All SIMD is (B); the crate ships with `safe-only` feature flag from the start (per project README). Per-target benches in `benches/` show the trade-offs.

**[E-041]** Refactor win (`br-rich-72`): `_mm_loadu_si128` byte-search loop → `wide::u8x16` for stable channel + `std::simd::u8x16` for nightly. (C) graduated from (B) on x86_64-v3+ targets where the safe versions tied; (B) retained on x86_64-v2 and wasm32.

**[E-042]** Refactor win (`br-rich-91`): hand-rolled SIMD memcpy → `slice::copy_from_slice` (autovectorizes to identical code on -O3).

**Rejected.** AVX-512 codegen on by default: thermal throttling on consumer CPUs made the perf benefit unreliable. Kept as opt-in `+avx512` target_feature.

---

## /dp/frankensqlite — sqlite client + extensions

**Primary unsafe.** sqlite3 C API via raw FFI bindings; `Statement` lifetime tracking; longjmp-aware error paths.

**[E-050]** sqlite FFI is (A) cluster of ~300 sites, all wrapped in safe Rust API in `src/sys.rs`. Hardened SAFETY comments per wrapper.

**[E-051]** Refactor win (`br-fsq-281`): hand-tracked statement lifetime → `Statement<'conn>` borrow-checker-tracked. Reduced 14 `unsafe impl Send for Statement` patterns to zero (the type is now `!Send` by `'conn` lifetime, which is correct).

**[E-052]** Refactor win (`br-fsq-302`): zerocopy migration for column-blob serialization. (C) cluster.

**Rejected.** Replacing sqlite3 with a pure-Rust sqlite implementation (rusqlite-mvp): the test surface of "behaves exactly like sqlite3" is too large to replicate; the FFI is intentional.

---

## /dp/frankentui — terminal UI library

**Primary unsafe.** termios for raw-mode terminal setup; signal handlers for SIGWINCH / SIGINT; some `slice::get_unchecked` in render hot paths.

**[E-060]** termios is (A) per `00-CANONICAL-UNAVOIDABLE.md § 9`. Single-ownership `TerminalMode` type guards entry/exit.

**[E-061]** Signal handlers: `pthread_kill`-only inside the handler; the heavy lifting is done in a Rust task pinged via a pidfd / signalfd channel. (A) for the handler body; the channel is safe.

**[E-062]** Refactor win (`br-ftui-44`): render hot path had `unsafe { *buf.get_unchecked(idx) }`; benched against `buf[idx]` showed LLVM eliminated the bounds-check on the natural loop. (C) graduated.

**Rejected.** Replacing termios with a pure-Rust terminal emulator (we'd need to implement the protocol from scratch).

---

## /dp/franken_engine — async runtime + scheduler

**Primary unsafe.** Scheduler atomics with platform-specific orderings; worker-parking protocol; some lock-free lockfree-queue primitives.

**[E-070]** Worker-parking uses `core::intrinsics::atomic_load_unsynchronized`. (A) per `00-CANONICAL-UNAVOIDABLE.md § 5`. Loom model in `tests/loom_worker_park.rs` proves the protocol.

**[E-071]** Refactor win (`br-fengine-198`): config hot-reload had hand-rolled `AtomicPtr<Config>` + `Arc::into_raw` round-trip. Refactored to `arc_swap::ArcSwap<Config>`. (C); 6 unsafe blocks deleted.

**[E-072]** Refactor win (`br-fengine-211`): inbox-shard's `unsafe impl Sync` was deleted after refactoring the shard type to use `crossbeam::queue::SegQueue<Msg>` per shard. (C); auto-derive provides Sync.

**Rejected.** Replacing the lock-free scheduler with a `Mutex<VecDeque<Task>>`: perf cliff factor-of-10 under load. Documented in `docs/why-lockfree.md`.

---

## /dp/frankenlibc — low-level syscall + libc bindings

**Primary unsafe.** Direct libc FFI; `extern "C"` blocks for ~250 syscalls; some inline asm for fast syscall path.

**[E-080]** Every syscall is (A) per `00-CANONICAL-UNAVOIDABLE.md § 2`. Each has a thin safe wrapper following pattern F-1 from `60-FFI-PATTERNS.md`.

**[E-081]** Refactor win (`br-flc-237`): clustered 213 `unsafe { libc::open(...) }` call sites into 12 wrappers (`open`, `open_with_mode`, `openat`, `openat_with_mode`, ...). cargo-geiger count fell from 213 to 12. Same perf (LLVM inlines the wrappers).

**[E-082]** Hardening (`br-flc-419`): every wrapper now has a docstring SAFETY-style block naming the C contract.

**[E-083]** Hardening (`br-flc-451`): `[profile.release] panic = "abort"` to guarantee no Rust unwinding across FFI.

**Rejected.** Using `nix` or `rustix` instead: the project's purpose IS to provide the lowest-level safe wrappers. nix/rustix are downstream users.

---

## /dp/frankenfs — userspace filesystem

**Primary unsafe.** `GlobalAlloc` impl for the slab allocator; FUSE FFI surface; some `mem::transmute` for inode-on-disk format.

**[E-090]** `SlabAllocator` impls `GlobalAlloc`; the (A) is per `00-CANONICAL-UNAVOIDABLE.md § 7`. Miri stacked-borrows AND tree-borrows runs on a test exercising every alloc/dealloc shape.

**[E-091]** Refactor win (`br-ffs-148`): in-crate callers of `Slab` switched from raw pointers to `bumpalo::Vec` / `slab::Slab<T>`. (C); 17 unsafe blocks deleted; the `Slab`'s internals stay (A).

**[E-092]** Refactor win (`br-ffs-203`): inode-on-disk `transmute` → `zerocopy::FromBytes` derive. (C) cluster on 5 inode-type variants.

**Rejected.** Replacing the `SlabAllocator` with the system allocator: defeats the project's purpose (the slab IS the project).

---

## Cross-repo patterns

| Pattern | Repos that use it | Reference |
|---------|-------------------|-----------|
| Thin safe wrapper per syscall | frankenlibc, frankensqlite, asupersync | 60-FFI-PATTERNS.md § F-1 |
| Owned-handle types with Drop | All FFI-touching repos | 60-FFI-PATTERNS.md § F-2 |
| arc-swap for config hot-reload | franken_engine, mcp_agent_mail_rust | 30-CONCURRENCY-PATTERNS.md |
| zerocopy migration for transmute | beads_rust, frankensqlite, frankenfs | 70-UNINIT-AND-TRANSMUTE.md |
| pin-project-lite adoption | mcp_agent_mail_rust, asupersync | 80-PIN-PROJECTIONS.md |
| safe-only feature flag for SIMD | rich_rust (canonical example) | 20-SIMD-AND-PERF.md |
| Newtype for Send/Sync on raw ptr | franken_engine, frankenfs | 10-POINTER-MIGRATIONS.md § Pattern P-2 |
| Slab-indexed doubly-linked list (replaces XOR / raw ptr) | frankenfs, mcp_agent_mail_rust | 65-ALLOCATOR-PATTERNS-DEEP.md § AL-1 |
| `panic = "abort"` profile for FFI-heavy crates | frankenlibc, frankensqlite, asupersync | 60-FFI-PATTERNS.md § F-3, COMMON-FAILURE-CASES.md § F-004 |
| `volatile-register` adoption | pi_agent_rust | 55-EMBEDDED-PATTERNS.md § E-1 |
| `cortex_m::interrupt::Mutex` for ISR-shared state | pi_agent_rust | 55-EMBEDDED-PATTERNS.md § E-4 |
| `crossbeam::deque::Worker`/`Stealer` for work-stealing | franken_engine | 75-LOCK-FREE-PATTERNS.md § LF-3 |
| `crossbeam::epoch` for lock-free memory reclamation | franken_engine | 75-LOCK-FREE-PATTERNS.md § LF-4 |
| `arrayvec` for bounded init-tracked vector | frankenfs | 70-UNINIT-AND-TRANSMUTE.md § U-3 |
| `static_assertions::assert_impl_all!` for Send/Sync invariants | franken_engine, mcp_agent_mail_rust | 50-SEND-SYNC-IMPLS.md |
| `#[deprecated]` migration shims (one-release retention) | beads_rust, frankensqlite | API-STABILITY-AND-MIGRATION.md |
| `cargo public-api --diff-git-checkouts` for API-change verification | rich_rust, beads_rust | API-STABILITY-AND-MIGRATION.md |
| Kani proofs for hash-table uniqueness invariants | frankensqlite, franken_engine | FORMAL-VERIFICATION.md |

## Extended quote bank entries (post-v1)

These entries extend the per-repo catalog with additional patterns the exemplar repos demonstrate. Each entry uses the same `[E-NNN]` anchor format.

**[E-100]** — `/dp/asupersync/src/io/mmap.rs` — `MmapHandle::drop` calls `munmap` BEFORE the dependent `IoUringSqe::drop` runs, because `MmapHandle` was constructed first in the parent struct. The drop-order dependency is documented in the type's SAFETY comment; reversing field declaration order would be UB. Operator ⊰ Drop-Order-Trace catches this dependency.

**[E-101]** — `/dp/franken_engine/src/sched/work_steal.rs` — original hand-rolled work-stealing deque used `unsafe impl Sync` on a `*mut Slot<Task>` field. Refactored to `crossbeam::deque::Worker` + `Stealer`. The `crossbeam` API's per-thread Worker is `!Sync` by design (use-after-clone is impossible); Stealer is `Send + Sync`. Bead `br-fengine-203` analog documents the refactor + perf parity.

**[E-102]** — `/dp/frankenfs/src/cache/lru.rs` — generational-arena migration considered but rejected in favor of `slab::Slab`. Reason: gen-arena's extra u32-per-index was measured at +5% memory for 1M entries; the use-after-free protection wasn't worth it because the LRU's lifecycle is already well-bounded. Documented in REJECTED-PATTERNS.md (or per-repo REJECTED.md). Demonstrates the "consider alternatives but document the rejection" discipline.

**[E-103]** — `/dp/mcp_agent_mail_rust/src/inbox/dashmap_migration.rs` — `[Mutex<HashMap<MsgId, Msg>>; 16]` → `DashMap<MsgId, Msg>` migration. Performance: -7% on p99 lookup latency, -32% on insert latency (DashMap's lock-free path wins on high contention). Bead `br-mam-203` analog. Demonstrates measure-first-then-decide for concurrent-map refactors.

**[E-104]** — `/dp/rich_rust/src/lexer/dispatch.rs` — `core::hint::unreachable_unchecked()` retained as (A) after Phase 6 adversarial review attempted to defeat it. The (A) survives because: the preceding match covers every valid byte (validated upstream); the alternative `unreachable!()` adds a branch + panic infrastructure to a 100-million-call-per-second hot path; the perf delta is +18% on the canonical benchmark, far over budget. Demonstrates a properly-justified (A) for an optimizer-hint intrinsic.

**[E-105]** — `/dp/frankenlibc/src/sys/syscall.rs` — `[profile.release] panic = "abort"` + `[profile.dev] panic = "abort"` set crate-wide. Why dev too: prevents accidental panic-unwind in tests that link the crate's `#[no_mangle] extern "C"` exports. Demonstrates the principle that unwinding policy must be consistent across profiles for FFI-heavy crates.

**[E-106]** — `/dp/frankensqlite/src/error.rs` — sqlite's longjmp-based error handling confined to a C-only wrapper: `int frankensqlite_step_safe(stmt*)` wraps `sqlite3_step` and converts longjmp into a return code. Rust callers see only return codes; no Rust frames on the longjmp path. Demonstrates the "longjmp containment" pattern.

**[E-107]** — `/dp/frankentui/src/render.rs` — `slice::get_unchecked` in the inner-render loop was originally (B), then graduated to (C) when benches showed LLVM eliminated the bounds-check on the natural iterator-based version. The (C) refactor saved 3 unsafe blocks AND made the code more readable. Demonstrates the graduation-on-measurement discipline from operator ⏱.

**[E-108]** — `/dp/pi_agent_rust/src/uart.rs` — UART access via `volatile-register::RW<u32>` instead of raw `core::ptr::write_volatile`. The (A) is concentrated at the register-block construction (`unsafe { &*(0x40000000 as *const UartRegisters) }`); per-field accesses are typed methods. Demonstrates the "concentrate unsafe at the boundary, expose safe API to consumers" principle for embedded MMIO.

**[E-109]** — `/dp/franken_engine/src/sched/worker_park.rs` — `core::intrinsics::atomic_load_unsynchronized` retained as (A). Justification per operator ⊗ Falsifiable-Justification: (1) `AtomicXxx::load(Relaxed)` has a fence guarantee the protocol can't tolerate, (2) `compiler_fence(Ordering::Acquire)` exists but has different semantics, (3) the protocol's correctness depends on knowing exactly when the load happens relative to two specific fences. Documented loom model proves the protocol's correctness; SAFETY comment cites the loom test. Demonstrates a (A) that survived adversarial defense.

**[E-110]** — `/dp/beads_rust/src/serde/blob.rs` — hand-rolled `mem::transmute<&[u8], &[u32]>` for endian read replaced by `u32::from_le_bytes` (per [70-UNINIT-AND-TRANSMUTE.md § T-2]). Bench parity confirmed; (C) refactor saved 14 unsafe blocks across the codebase. Demonstrates the trivial-perf-equivalence + safety-improvement combination.

**[E-111]** — `/dp/mcp_agent_mail_rust/src/ws/stream.rs` — self-referential WebSocket reader keeps (A) classification across multiple adversarial reviews because `pin-project-lite` cannot project a `&mut [u8]` reference whose lifetime is tied to a sibling `Vec<u8>` field within the same struct. The (A) hardening includes: `!Unpin` via PhantomPinned, constructor returning `Pin<Box<Self>>`, SAFETY comment naming the field-level invariant, and a `static_assertions::assert_not_impl_any!(WsStream: Unpin)` test. Demonstrates a (A) that's genuinely unavoidable in current Rust.

**[E-112]** — `/dp/asupersync/src/io/ring.rs` — io_uring SQE write + kernel-side CQE poll synchronized via `core::sync::atomic::fence(Ordering::Release)` on the write side, `fence(Ordering::Acquire)` on the read side. The (A) survives because: the kernel ABI requires these specific fences (kernel docs cited), and miri can't model the kernel's writes (so loom's coverage is bounded but not zero). Demonstrates the "FFI-adjacent fence" pattern.

---

## How this catalog evolves

When a new audit surfaces a pattern not already in this catalog:

1. Add a new `[E-NNN]` entry under the relevant repo.
2. Cross-reference in the appropriate pattern bundle.
3. If the pattern is novel (not just a variation), consider promoting to the cross-repo table.
4. Commit to the skill repo so subsequent audits learn from it.

The catalog is the skill's institutional memory.
