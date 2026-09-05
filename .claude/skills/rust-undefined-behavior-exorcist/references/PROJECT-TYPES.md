# Project-Type Priors — Per-Archetype What To Look For

The skill operates over any Rust project, but each *archetype* has UB shapes that recur. Phase 0 partition pattern-matches on the project and pre-loads the relevant priors. This file is the prior library.

For end-to-end walkthroughs see [COOKBOOK.md](COOKBOOK.md); for tool decision trees see [TOOLING.md §Tool decision tree](TOOLING.md). This file is the *taxonomy* of what each archetype *characteristically* has.

---

## P1. Rust Library — typical OSS crate published to crates.io

**Examples in corpus:** `beads_rust`, `rich_rust` (forbid-unsafe), `xf`.

**Surface markers:**
- `Cargo.toml` has `[lib]` and `crate-type = ["rlib"]` or default
- `src/lib.rs` exists; `src/main.rs` doesn't or is thin
- Public API surface in `src/lib.rs` exports

**Characteristic UB shapes:**
- Library-trait invariants (`Hash`+`Eq` consistency, `Iterator::size_hint` honesty, `Ord` consistency, custom `Allocator` if any)
- Manual `Send`/`Sync` impls on Sync-looking-but-not types
- Lifetime escape via raw-pointer-returning functions in the public API
- Panic safety on `Drop` impls of public types

**Pre-loaded buckets (Phase 2 priority order):**
1. #12 Std-library trait invariants
2. #25 Hash+Eq+Borrow consistency
3. #15 Lifetimes & escape (public API)
4. #11 Panic safety
5. #1 Aliasing (only if `unsafe` surface exists)

**Quick-win priors:**
- Run `cargo doc --document-private-items` and grep for unsafe-fn without `# Safety` doc — common in library code
- Property test every type used as a HashMap key
- `cargo public-api` to surface the API; audit each public function for soundness obligations

---

## P2. Rust Binary CLI

**Examples in corpus:** `dcg`, `xf`, `ubs`, `cass`, `ru`.

**Surface markers:**
- `Cargo.toml` has `[[bin]]` or `src/main.rs` is primary
- Uses argument parsers (`clap`, `argh`, `structopt`)
- May use child processes (`Command::new`, `Command::pre_exec`)

**Characteristic UB shapes:**
- `Command::pre_exec` requires `unsafe` (its closure runs in the child between fork and exec; very few APIs are signal-safe)
- File-descriptor leaks if `OwnedFd` isn't used consistently
- Async-Drop hazards if the binary uses tokio + spawns child processes from `Drop`
- Signal-handler unsafety (`signal::signal` requires unsafe)

**Pre-loaded buckets:**
1. #10 FFI contracts (signal handlers, child-process syscalls)
2. #20 Dangling Box / allocator pairing
3. #17 Async drop hazards (if tokio-based)
4. #11 Panic safety (Drop runs at process exit too)

**Quick-win priors:**
- See exemplar Q-021 (pi_agent_rust): use `/bin/sh -c 'trap - PIPE; exec "$@"'` to reset SIGPIPE without `Command::pre_exec`
- Use `std::os::fd::OwnedFd` for every fd field; never bare `RawFd`/`c_int`

---

## P3. Rust Workspace (multi-crate)

**Examples in corpus:** `frankensqlite`, `asupersync`, `frankenfs`, `mcp_agent_mail_rust`.

**Surface markers:**
- Top-level `Cargo.toml` has `[workspace]` with `members = ["crates/*"]`
- Some member crates have `#![forbid(unsafe_code)]`; others don't
- Cross-crate API boundaries

**Characteristic UB shapes:**
- Cross-crate aliasing: crate A returns `*mut T`; crate B reads it — the borrow contract crosses the crate boundary
- Cross-crate `Send`/`Sync`: crate A marks T `unsafe impl Send`; crate B holds T across thread boundaries
- Per-crate-feature-flag UB: `#[cfg(feature = "X")]` paths may have UB the no-feature path doesn't
- Workspace-wide MSRV drift: a feature flag enables newer-rustc behavior that older rustc rejects

**Pre-loaded buckets:**
- Same as P1 but apply the bucket sweepers *per-crate* and then *cross-crate*
- Add: "feature-gated UB" sweep — run static + dynamic with every feature combination tested in CI

**Quick-win priors:**
- Partition the audit by crate (Phase 0 partition matches `crates/*`)
- Phase 4 synthesis cross-links findings across crate boundaries
- Pay attention to `pub use` re-exports; UB in a buried crate becomes UB in the public API
- Run Miri once per relevant feature flag combination (Standard mode) or every combination (Exhaustive mode)

---

## P4. Embedded `no_std`

**Examples in corpus:** `frankenlibc` (libc reimplementation), MMIO drivers.

**Surface markers:**
- `#![no_std]` at the crate root
- Uses `core::*` instead of `std::*`
- `alloc` may be optional behind a feature flag
- Possibly `panic-halt` or custom panic handler

**Characteristic UB shapes:**
- MMIO (`read_volatile` / `write_volatile`) on potentially-misaligned pointers — see bucket #16
- Inline asm — bucket #18
- Manual `panic_handler` that doesn't honor `#[panic_handler]` contract
- Custom `#[global_allocator]` UB if the allocator is buggy — bucket #20
- `#[link_section = ...]` and `#[used]` interactions with linker scripts
- DMA buffer aliasing (peripheral and CPU both touch the same memory)

**Pre-loaded buckets:**
1. #16 Volatile contracts
2. #3 Alignment (MMIO often demands specific alignment)
3. #20 Dangling Box (custom allocator)
4. #18 Inline asm
5. #7 Data races (DMA / interrupt context)

**Quick-win priors:**
- Use `volatile-register` for typed MMIO instead of raw `read_volatile`
- DMA buffers need barriers: `core::sync::atomic::fence(SeqCst)` or device-specific
- Test under `qemu-system-...` rather than native Miri (Miri doesn't model the CPU's memory model for MMIO)

---

## P5. WebAssembly Crate (wasm32 target)

**Surface markers:**
- `crate-type = ["cdylib"]` for wasm-pack
- Uses `wasm-bindgen` macros
- Target is `wasm32-unknown-unknown` or `wasm32-wasi`

**Characteristic UB shapes:**
- `wasm-bindgen`'s `JsValue` reference counting (Rust holds a JS handle that may be GC'd)
- Linear-memory aliasing between Rust and JS callers
- Floating-point determinism: wasm specifies NaN canonicalization; native code may not
- Threads via `wasm-bindgen-rayon` or `wasm-mt` — share `SharedArrayBuffer` with all the race risk

**Pre-loaded buckets:**
1. #10 FFI contracts (the JS↔Rust boundary is FFI)
2. #4 Validity invariants (every JS value crossing into Rust)
3. #6 Type punning (lots of `transmute` in wasm-bindgen generated code — check via `cargo expand`)

**Quick-win priors:**
- `wee_alloc` is unmaintained — flag it as a soundness risk for new wasm crates
- `wasm-bindgen-test` for browser-runtime tests; Miri doesn't run wasm

---

## P6. Async Runtime / Custom Future

**Examples in corpus:** `asupersync` (custom runtime).

**Surface markers:**
- Implements `Future` by hand (not via `async fn`)
- Uses `RawWaker` / `RawWakerVTable`
- Custom executor with `Pin<&mut dyn Future>`

**Characteristic UB shapes:**
- `RawWaker` vtable: `Arc::from_raw` / `into_raw` / `forget` choreography (exemplar E4)
- `Pin::new_unchecked` on self-referential future state
- `mem::replace` near a `Pin` — bucket #9
- Cancellation safety: future dropped mid-`.await` leaves state inconsistent — bucket #17

**Pre-loaded buckets:**
1. #9 Pin invariants
2. #13 Refcount lifecycle (RawWaker)
3. #17 Async drop hazards
4. #7 Data races (executor scheduling)

**Quick-win priors:**
- Always pair `Arc::from_raw` with `into_raw` or `mem::forget`. Audit the four vtable fns as a quartet.
- Use `tokio_unstable` runtime metrics during testing to detect worker blocks
- Loom-model every sync primitive the runtime exposes

---

## P7. FFI Binding (`-sys` crate)

**Examples in corpus:** `frankensqlite/fsqlite-c-api`, parts of `frankenlibc`.

**Surface markers:**
- `Cargo.toml` has `links = "<libname>"`
- `build.rs` invokes `bindgen` or `cc`
- Most of `src/lib.rs` is `extern "C" { ... }` declarations + safe wrappers

**Characteristic UB shapes:**
- `#[repr(C)]` mismatch between the Rust declaration and the actual C struct (alignment, padding, field order)
- `*const c_char` NUL-termination assumptions
- `Box::from_raw` on a pointer produced by `malloc` (bucket #20)
- FFI callbacks fired at signal-handler time
- Calling-convention drift (the C lib expects `cdecl`; Rust says `extern "C"` which is platform-dependent)

**Pre-loaded buckets:**
1. #10 FFI contracts
2. #3 Alignment (C structs often have non-Rust alignment)
3. #22 repr(packed) field addr (when wrapping packed C structs)
4. #20 Dangling Box
5. #21 FFI callback aliasing

**Quick-win priors:**
- Regenerate `bindgen` output and diff against committed file — drift catches a class of regressions
- Cross-reference every `extern "C"` declaration against the C header with `static_assertions!` for size + alignment + offsetof
- Wrap raw pointers in typed newtypes immediately at the boundary; never let raw pointers leak into business logic
- See exemplar Q-004 — the frankensqlite mmap-SHM was a master-class in this

---

## P8. Custom Allocator Crate

**Surface markers:**
- Implements `unsafe impl GlobalAlloc` or `unsafe impl Allocator`
- May export a global static `#[global_allocator]`

**Characteristic UB shapes:**
- Layout mismatch: `alloc(layout)` size != `dealloc(ptr, layout)` size
- Alignment too lax: `align_of::<T>()` > the actual alignment returned
- Concurrent allocator state without synchronization
- "Allocator may unwind from `dealloc`" — Drop runs through it; unwinding from dealloc is UB
- ZST handling: must not allocate or deallocate

**Pre-loaded buckets:**
1. #20 Dangling Box / allocator pairing
2. #3 Alignment
3. #7 Data races (allocator is shared mutable state)
4. #11 Panic safety (allocator must not panic in `dealloc`)

**Quick-win priors:**
- Kani / Prusti on the allocator's `alloc` + `dealloc` are high-value (see [REMEDIATION-PATTERNS.md Shape 15](REMEDIATION-PATTERNS.md))
- Heap-stomp fuzz harness: random allocate/deallocate/reallocate sequences via `Arbitrary`
- Cross-check against `bumpalo` (well-tested) on every workload

---

## P9. Lock-Free Data Structure Crate

**Surface markers:**
- Uses `crossbeam_epoch` or `seize` for EBR
- Hand-rolled atomics: `AtomicPtr`, `compare_exchange`
- Loom is a dev-dependency

**Characteristic UB shapes:**
- ABA hazard: pointer reuse after free between two operations on the same slot
- Memory ordering errors: `Relaxed` where `Acquire`/`Release` is needed
- Epoch-based reclamation bugs (grace period miscounting)
- Pointer tagging breaking provenance

**Pre-loaded buckets:**
1. #7 Data races
2. #2 Provenance (tagged pointers)
3. #13 Refcount lifecycle (if not using EBR)
4. #1 Aliasing (concurrent readers + 1 writer needs proof)

**Quick-win priors:**
- Loom model is mandatory (Phase 3 produces it if missing)
- See exemplar E4 + [REMEDIATION-PATTERNS.md Shape 13](REMEDIATION-PATTERNS.md) for the ABA recipes
- Triangulate the design with `/multi-model-triangulation` before shipping

---

## P10. Database / Storage Engine

**Examples in corpus:** `frankensqlite`, `frankenfs`.

**Surface markers:**
- Mmap-based storage
- WAL / journal files
- fcntl locking or POSIX advisory locks

**Characteristic UB shapes:**
- mmap pointer aliasing: kernel changes memory under our feet
- Atomic-via-mmap: see exemplar Q-004 (atomic ops at byte offset)
- Multi-process file locking races
- Page-level aliasing (two processes mmap the same file with different intents)
- fsync / fdatasync ordering (not UB but data loss; treat as adjacent concern)

**Pre-loaded buckets:**
1. #3 Alignment (mmap pointers need explicit alignment check)
2. #7 Data races (multi-process)
3. #8 Send/Sync invariants (mmap pointers)
4. #16 Volatile contracts (if kernel-side may write)

**Quick-win priors:**
- Q-004 is the textbook — use the SAFETY-NOTES-FIRST ritual for every new mmap-related unsafe block
- For multi-process: TSan can't help (TSan is single-process); fall back to long-running multi-process fuzz harnesses

---

## P11. Cryptographic Primitive Crate

**Surface markers:**
- Constant-time invariants (`subtle` crate)
- Side-channel resistance claims
- SIMD intrinsics in hot path

**Characteristic UB shapes:**
- Target-feature mismatch — bucket #19 — fatal for crypto correctness
- Constant-time properties broken by LLVM optimization
- Side-channel-sensitive `cmov`-like patterns broken by `match`/`if`
- Zeroization on `Drop` not happening (LLVM optimizes it away) — uses `zeroize` crate

**Pre-loaded buckets:**
1. #19 Target-feature mismatch
2. #6 Type punning (often `transmute` for byte-level access)
3. #11 Panic safety (zeroization must happen even on panic)

**Quick-win priors:**
- Use `subtle`, `zeroize`, `secrecy` crates
- Formal verification (Kani / Aeneas / hax) is worth the cost here
- DEK/wrap layers around hardware: HSM / TPM / SGX has its own contract

---

## P12. Network Service / HTTP Server

**Examples in corpus:** parts of `asupersync` (http client).

**Surface markers:**
- Uses `hyper`, `axum`, `tonic`, `tokio-tungstenite`
- Custom protocol parser (binary or text)
- Stateful per-connection handlers

**Characteristic UB shapes:**
- Buffer overruns in parsers (`get_unchecked`, `set_len`)
- Cancellation-safety on connection drop mid-state-machine
- Async drop hazards holding network FDs

**Pre-loaded buckets:**
1. #1 Aliasing (parser holds &buf while mutating len)
2. #5 Uninitialized memory (`set_len` patterns)
3. #15 Lifetime escape (per-connection state)
4. #17 Async drop hazards

**Quick-win priors:**
- Fuzz the parser via `cargo fuzz` with structured `Arbitrary` inputs
- Cancel-safe test harness: cancel every `.await` and assert state invariants

---

## P13. Kernel Module (linux-kernel-module-rust)

**Surface markers:**
- `#![no_std]`
- Uses `kernel::*` from the linux-kernel-module-rust shims
- Implements `Module` trait

**Characteristic UB shapes:**
- Interrupt-context allocation (must use atomic / NMI-safe allocator)
- RCU vs spinlock vs mutex (kernel-specific synchronization)
- Kernel ABI: every syscall is `unsafe extern "C"` and contracts are fragile across kernel versions
- Lifetime contracts on kernel structures (file* vs fdput, page* vs put_page)

**Pre-loaded buckets:** All P4 buckets plus #21 (FFI callback aliasing — interrupts).

**Quick-win priors:**
- Never use `std`; never use `alloc` without an explicit kernel-allocator wrapper
- Audit every `unsafe fn` against the kernel's CAP (capability) requirements
- Static analysis at the kernel boundary is critical; user-space Miri doesn't model kernel preemption

---

## P14. GPU Compute (wgpu / vulkano / cuda-rs)

**Surface markers:**
- Uses `wgpu` / `vulkano` / `cust` / `cudarc`
- Manual shader compilation
- Manual buffer management

**Characteristic UB shapes:**
- GPU buffer aliasing (host writes vs device reads)
- Shader UB (out-of-bounds index, divide-by-zero)
- Synchronization between command buffers
- ZBC (Zero Bandwidth Compression) state on Nvidia — kernel-level UB if mismanaged

**Pre-loaded buckets:** Mostly out-of-scope for this skill (Miri can't simulate GPUs). Tag findings as `DEFERRED` if they require GPU-side proof; route to vendor-specific validators.

---

## P15. Pure-Safe Forbid-Unsafe Projects

**Examples in corpus:** `beads_rust`, `rich_rust` (pure-safe variants where these crates set `forbid(unsafe_code)` at the crate root), agent-first CLI tools, pure-Rust storage engines that wrap a no-FFI dep.

**Surface markers:**
- `#![forbid(unsafe_code)]` at `src/lib.rs:1-N`
- No `extern "C"`, `extern fn`, `#[no_mangle]`, `asm!`, `unsafe impl Send/Sync` in crate code
- All dependencies are pure-Rust (no `*-sys`, no `links = ...` in Cargo.toml)
- May have FFI inside *deps* (e.g., a pure-Rust SQLite reimplementation that internally uses `unsafe`) — but that's the dep's audit boundary, not ours

**Characteristic UB-adjacent shapes (NOT classical UB; soundness-adjacent invariant drift):**
- **Library-trait invariant drift** — `Hash`+`Eq` consistency, `Ord` transitivity, `Iterator::size_hint` honesty, custom `Deserialize` round-trip with `Serialize`
- **Custom-case Eq distinction** — fallback variants like `Status::Custom(String)` that preserve original-case (so `Custom("FOO") != Custom("foo")` under derived PartialEq, defeating dedup)
- **Determinism leaks** — HashSet/HashMap iteration order leaking into user-visible output (CLI messages, JSONL exports, content hashes computed downstream)
- **Content-hash invariants** — separator-injection collisions (e.g., null-byte field separators in SHA-256 input), missing length-prefix encoding, exclusion of relevant fields, inclusion of locale-dependent fields
- **Panic safety in `Drop`** — Mutex poison handling, half-mutated state, unwind-during-drop double-panic
- **Send/Sync auto-derivation drift** — types crossing `thread::scope` whose Send/Sync derivation is technically correct but operationally surprising

**Pre-loaded buckets (Phase 2 priority order):**
1. #12 Std-library trait invariants — PRIMARY for pure-safe
2. #25 Hash+Eq+Borrow consistency
3. #11 Panic safety (Drop impls + mem::take/replace patterns)
4. #7 Data races (despite no `unsafe`, `Arc<Mutex<...>>` misuse is still in scope)
5. #8 Send/Sync invariants (auto-derivation correctness)

**Inapplicable buckets** (structurally impossible under `#![forbid(unsafe_code)]`):
- #1 Aliasing, #2 Provenance, #3 Alignment, #4 Validity, #5 Uninit memory, #6 Type punning, #9 Pin invariants, #10 FFI contracts, #13 Refcount lifecycle (`Arc::from_raw`), #14 Mutation through `*const T`, #15 Lifetimes & escape (via raw ptr), #16 Volatile contracts, #18 Inline asm, #19 Target-feature mismatch, #20 Dangling Box, #21 FFI callback aliasing, #22 `repr(packed)` field addr, #23 Observed type changes, #24 Coherence violations

Document these as `DEFERRED — requires unsafe in crate code; structurally impossible under forbid(unsafe_code)` in the experiment registry. They are not skipped — they are explicitly ruled out so future audits don't re-investigate.

**Phase 3 dynamic plan for pure-safe:**

| Tool | Use | Why |
|------|-----|-----|
| **Miri** (matrix) | YES — but on `--lib` tests only, not full test suite | Catches UB inside `std`'s unsafe (HashMap, BTreeMap, sort, alloc) when our trait impls violate Hash/Eq/Ord contracts. Use `-Zmiri-disable-isolation` (chrono::Utc::now etc.). |
| **TSan** | YES, on test suite that exercises `Arc<Mutex<...>>` | Catches data races even in `unsafe`-free code |
| **ASan/MSan/LSan** | NO (skip with rationale) | Without `unsafe` in crate code there are no aliasing/lifetime UB sites for these to catch |
| **cargo-fuzz** existing targets | YES, every target, short campaigns | The highest-ROI dynamic action — invariant testers per existing target |
| **cargo-fuzz** new targets | YES, for trait-invariant + content-hash properties | Author proptest-shaped fuzz targets for `Hash`+`Eq` consistency, content-hash collision-resistance |
| **Loom** | YES, if any `thread::scope` / `Arc<Mutex<...>>` cross thread boundaries | Cheap insurance for the atomic-ordering and lock-hold-time invariants |
| **cargo-geiger** | Optional with caveat | Tells you "all unsafe is in the deps" — already known. Skip with note. (See [TROUBLESHOOTING.md §cargo-geiger](TROUBLESHOOTING.md#cargo-geiger).) |
| **Kani** | YES, for the content-hash invariant after remediation | Bounded proof that `Hash` ⇔ `Eq` ⇔ `content_hash` agree |

**Convergence floor for pure-safe:**

| Run mode | Floor | Rationale |
|----------|-------|-----------|
| Quick | (phase 7 N/A) | — |
| Standard | **3 rounds** (NOT 10) | 19 of 25 UB buckets are structurally inapplicable; rounds 4-10 would be theater. Idea-wizard's 2 lenses (STRUCTURAL + ADVERSARIAL) finish the project-shape mining inside R2-R3. |
| Exhaustive | **5 rounds** | 3 idea-wizard rounds (STRUCTURAL + ADVERSARIAL + CROSS-SYSTEM) + 2 confirm-clean rounds. |

**Quick-win priors for pure-safe:**
- Phase 6 idea-wizard is **the load-bearing phase** for this archetype. The trait-invariant + content-hash bugs are exactly the shapes idea-wizard surfaces and static buckets miss. Field anchor: in `beads_rust` 2026-05-14, an idea-wizard round at sum-score-rank #30 found a SHA-256 collision in the content-hash primitive; top-5 by score did not contain it.
- Use the standalone-cargo-project harness for Phase 5 (see [EXPERIMENT-DESIGNS.md §Standalone Harness](EXPERIMENT-DESIGNS.md#standalone-cargo-project-harness-recommended-default)).
- The remediation pattern playbook reduces to: lowercase Custom-string fallbacks, BTreeSet over HashSet for determinism-sensitive output, length-prefix Hash field writers, document tombstone-keying-by-id (not content_hash).

---

## Archetype Quick-Card

| Archetype | Top 3 buckets | Phase 0 partition strategy | Time-to-Standard-completion |
|---|---|---|---|
| P1 Library | 12, 25, 15 | per top-level module | ½ day |
| P2 CLI | 10, 20, 17 | by signal/proc surface | ½ day |
| P3 Workspace | depends (apply per crate) | per `crates/*` member | ½–1 day |
| P4 Embedded | 16, 3, 18, 20 | per peripheral driver | ½ day |
| P5 WASM | 10, 4, 6 | per wasm-bindgen module | ¼ day |
| P6 Async runtime | 9, 13, 17 | per sync primitive + executor | ½ day |
| P7 FFI | 10, 3, 22, 20, 21 | per C library wrapped | ½–1 day |
| P8 Allocator | 20, 3, 7 | per allocation pathway | ½ day + Kani |
| P9 Lock-free | 7, 2, 13, 1 | per data structure + loom model | full day |
| P10 DB / Storage | 3, 7, 8, 16 | per page-storage layer | full day |
| P11 Crypto | 19, 6, 11 | per primitive + formal | day-plus + formal |
| P12 Net service | 1, 5, 15, 17 | per parser + handler | ½ day |
| P13 Kernel module | P4 + 21 | per syscall + per interrupt | day-plus |
| P14 GPU | — (mostly deferred) | route to vendor validator | ¼ day |
| P15 Pure-safe forbid-unsafe | 12, 25, 11, 7 | per top-level module; bucket-based | ¼–½ day (smaller floor) |

---

## Multi-Archetype Projects

Real projects often span archetypes (e.g., `frankensqlite` is P3 workspace + P7 FFI + P10 storage). The Phase 0 partition table tags each section with its archetype, and the per-section pre-loaded buckets are the union. Use the [WORKFLOWS.md](WORKFLOWS.md) archetype decision tree for the overall flow choice.
