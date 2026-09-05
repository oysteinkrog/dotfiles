# 00-CANONICAL-UNAVOIDABLE.md — The (A) Bucket

This file catalogs the unsafe patterns the exemplar repos have shipped to production as **STRICTLY_UNAVOIDABLE**. Each entry has: pattern, why it survives (A) falsification, hardening template (SAFETY comment + proof obligation), and the exemplar precedent.

If your audit produces an (A) classification, it should match (or extend) one of these patterns. If it doesn't, the falsification justification is doing double duty and deserves an adversarial reclassification pass.

---

## 1. FFI: extern "C" calls into system libraries

**Pattern.** Calling C functions through `extern "C"` declarations or `libc::*`.

**Why (A).** The C ABI is outside Rust's type system. The Rust compiler cannot verify pointer lifetimes, null-termination, ownership transfer, or thread-safety on the C side. The unsafe IS the proof obligation — the Rust caller asserts the C contract is upheld.

**Falsification survives.**
- Alternative: pure-Rust reimplementation of the C library. → fails because the project's purpose IS to bind to the C library (e.g., `frankenlibc`, `frankensqlite`).
- Alternative: use a higher-level safe-binding crate. → fails when the project IS the safe-binding crate; the unsafe lives in its lowest layer.
- Alternative: `bindgen`-generate the bindings. → bindgen output is ALSO unsafe; it just moves the audit surface, doesn't eliminate it.

**Exemplar.** `/dp/frankenlibc/src/sys/syscall.rs` — `unsafe { libc::open(...) }` is (A). The hardening: every syscall goes through a `pub fn open_safe(path: &CStr, flags: i32) -> io::Result<RawFd>` that converts the C contract into a Rust contract.

**Hardening template.**

```rust
/// Open a file via `libc::open`.
///
/// # Safety
///
/// The caller MUST guarantee:
/// - `path` is a valid null-terminated C string (enforced here via `&CStr`).
/// - `flags` is a valid combination of `O_*` constants (cannot verify; documented).
///
/// On the C side: `libc::open` will read up to a null byte from `path`. It returns
/// either a valid file descriptor (≥ 0) or -1 with `errno` set.
///
/// The returned file descriptor is owned by Rust IFF the call succeeded. On error,
/// no file descriptor is allocated; nothing needs to be released.
///
/// Rust unwinding through this call would be UB. The wrapper is non-panicking by
/// construction (no `?`, no `unwrap`, no `expect`).
pub fn open_safe(path: &CStr, flags: i32) -> io::Result<RawFd> {
    // SAFETY: path is null-terminated (CStr invariant); flags is i32 (no type
    // hazard). No Rust panic can occur in the body — we only call libc and then
    // branch on the return value.
    let fd = unsafe { libc::open(path.as_ptr(), flags) };
    if fd < 0 { Err(io::Error::last_os_error()) } else { Ok(fd) }
}
```

The unsafe is one line. Everything above it is the contract; everything below it is the error mapping. The Rust caller never sees the raw `libc::open`.

---

## 2. Raw syscalls (libc / windows-sys / nix)

**Pattern.** Direct invocation of syscalls without an OS-abstraction crate.

**Why (A).** Same as FFI generally. Syscalls have OS-specific semantics that no safe abstraction can fully capture.

**Falsification survives.** Alternatives — `nix`, `rustix`, `windows`, `std::os::unix` — all bottom out in the same unsafe; they're convenience layers, not soundness layers.

**Exemplar.** `/dp/asupersync/src/io/ring.rs` — io_uring setup uses raw syscalls because no safe Rust crate currently exposes the full surface (especially edge-triggered and large-buffer modes).

**Hardening.** Identical pattern to FFI. Wrap each syscall in a `*_safe` function. Document errno / GetLastError mapping.

---

## 3. mmap and shared memory

**Pattern.** `libc::mmap`, `MapViewOfFile`, anonymous shared memory between processes.

**Why (A).** The pointer returned by `mmap` is aliased with the kernel and (for shared mappings) other processes. The borrow checker cannot model multi-process aliasing.

**Falsification survives.**
- Alternative: copy-on-read instead of mmap. → fails when the project's purpose is zero-copy access to large files.
- Alternative: a safe mmap crate (`memmap2`). → memmap2's own internals are unsafe; it's a wrapper. Using it is fine and recommended, but it doesn't eliminate the (A) — it CLUSTERS it (see Refactor opportunity below).

**Exemplar.** `/dp/asupersync/src/io/mmap.rs` — mmap shared between async tasks. The (A) is hardened by a `MmapHandle` newtype with a custom `Drop` calling `munmap`; the public API is `pub fn map_file(path: &Path) -> io::Result<MmapHandle>` and downstream code never sees the raw pointer.

**Refactor opportunity (cluster).** Multiple call sites that mmap can usually share a single safe wrapper. The (A) count drops from N (one per call site) to 1 (one in the wrapper).

---

## 4. io_uring / epoll (edge-triggered) / kqueue

**Pattern.** Edge-triggered async I/O surfaces that the kernel exposes as raw structures.

**Why (A).** Same as syscalls + the structures (`io_uring` SQEs/CQEs) have kernel-side aliasing. The completion ring is shared memory between kernel and user space.

**Falsification survives.** Higher-level async runtimes (`tokio`, `glommio`, `monoio`) wrap io_uring with their own unsafe. Using their safe surface is recommended for application code; the lower-level unsafe is (A) in the runtime crate itself.

**Exemplar.** `/dp/asupersync/src/io/ring.rs` — io_uring is the crate's purpose; the unsafe stays.

**Hardening.** Document the kernel-side aliasing in the SAFETY comment. State explicitly: which fields the kernel reads, which the user space writes, and the memory-barrier requirements.

---

## 5. Atomic primitives outside std::sync::atomic's safe API

**Pattern.** `core::intrinsics::atomic_*_unsynchronized`, `core::sync::atomic::compiler_fence`, raw atomic CAS with `Ordering::Relaxed` on `usize`-as-pointer-bits patterns.

**Why (A).** Some atomics the language acknowledges but only via unstable intrinsics; some patterns (`fence` with platform-specific orderings) require unsafe to express.

**Falsification survives.**
- Alternative: use `std::sync::atomic::AtomicU64` instead of intrinsics. → fails for `unsynchronized` (the whole point is NO synchronization for performance/correctness in a specific lock-free protocol).
- Alternative: use `crossbeam_utils::atomic`. → CrossBeam wraps atomics; the unsynchronized variant is also unsafe there.

**Exemplar.** `/dp/franken_engine/src/sched/worker_park.rs` — uses `core::intrinsics::atomic_load_unsynchronized` for a lock-free worker-parking protocol. The (A) survives because the protocol's correctness depends on knowing the load happens between two specific fences, which the safe API can't express.

**Hardening.** Loom model of the lock-free protocol. The SAFETY comment cites the loom proof.

---

## 6. core::hint::unreachable_unchecked for verified exhaustiveness

**Pattern.** Telling the optimizer "this branch is unreachable, even though the compiler can't prove it" when the exhaustiveness is proved upstream (e.g., a `match` covers all valid states but the compiler sees `_ =>` as reachable).

**Why (A).** A safe `unreachable!()` panics; the unsafe form is an OPTIMIZER HINT that produces strictly better codegen. For hot paths, removing the panic-on-unreachable saves a branch + the panic infrastructure.

**Falsification survives.**
- Alternative: `unreachable!()` and trust the optimizer. → fails when benches show a measurable regression (turning this into a (B), not avoiding (A)).
- Alternative: use a `NonZero*` type to encode the invariant in the type system. → works when the invariant is "value is non-zero"; doesn't work for richer invariants.

**Exemplar.** `/dp/rich_rust/src/lexer/dispatch.rs` — after a match that covers all valid token-kind bytes, the catch-all is `unreachable_unchecked()` because upstream parsing has already validated the byte range.

**Hardening.** The SAFETY comment must name the upstream invariant AND cite the line that establishes it. If the upstream check is removable, the (A) is fragile — bind the invariant into the type via a newtype.

---

## 7. GlobalAlloc / Allocator impls

**Pattern.** Implementing the `GlobalAlloc` trait (stable) or `Allocator` trait (unstable).

**Why (A).** An allocator can't be implemented without unsafe — the allocator is asked to produce memory it doesn't own yet; the `*mut u8` return is the proof that the request was satisfied. The borrow checker has no way to model "this pointer is now valid for `layout.size()` bytes."

**Falsification survives.** No safe alternative exists; an allocator that wasn't unsafe would itself need an allocator.

**Exemplar.** `/dp/frankenfs/src/alloc/slab.rs` — slab allocator impl.

**Hardening.** Miri stacked-borrows AND tree-borrows runs on a test that exercises every alloc/dealloc pattern. The SAFETY comment in `alloc()` and `dealloc()` documents the layout invariants the allocator promises.

---

## 8. Pin::new_unchecked for self-referential types

**Pattern.** Constructing `Pin<&mut T>` where `T` contains a self-reference, after asserting the type won't be moved.

**Why (A).** Self-references aren't expressible in safe Rust. `pin-project` / `pin-project-lite` handle the COMMON case where the projection is straightforward; the self-referential case is what stays (A).

**Falsification survives.**
- Alternative: avoid self-reference (use index instead of pointer). → fails when the self-reference is across a generic / unowned type the index can't express.
- Alternative: use a different data structure (e.g., split into two `Arc`s). → fails when the perf cost or API change is unacceptable.
- Alternative: use `pin-project`. → use it where it applies; this entry covers only the cases where it doesn't.

**Exemplar.** `/dp/mcp_agent_mail_rust/src/ws/stream.rs` — WebSocket stream's reader holds a buffer-slice reference into its own buffer. `pin-project` can't express the lifetime tie; `Pin::new_unchecked` is used after asserting "we never move once constructed."

**Hardening.**

```rust
/// SAFETY: After construction, `WsStream` is wrapped in `Box::pin` (see
/// `WsStream::open`) and never moved. The buffer at `self.buf[self.read_pos..]`
/// remains at a stable address for the entire lifetime of the stream.
///
/// Moving a constructed `WsStream` would dangle `self.reader_view` and cause UB.
/// The constructor enforces this by returning `Pin<Box<WsStream>>` and the
/// `WsStream` is `!Unpin`.
fn project_reader_view(self: Pin<&mut Self>) -> &mut &mut [u8] {
    // SAFETY: see type-level comment above.
    unsafe { &mut self.get_unchecked_mut().reader_view }
}
```

The type is `!Unpin`; the constructor returns `Pin<Box<Self>>`; the moves are statically prevented.

---

## 9. Signal handlers and termios

**Pattern.** Installing async-signal-handlers via `libc::signal` / `sigaction`; setting terminal mode via `tcsetattr`.

**Why (A).** Signal handlers execute in an interrupted context where most of Rust's runtime is unsafe to touch (no allocator, no panic, no mutex acquisition). The handler must be carefully scoped to async-signal-safe operations.

**Falsification survives.**
- Alternative: signalfd / pidfd. → improves the case but still requires unsafe setup; the (A) moves rather than disappears.
- Alternative: tokio's `signal::ctrl_c()` and friends. → use them in application code; the (A) is in the runtime crate's signal-handling layer.

**Exemplar.** `/dp/frankentui/src/signal.rs` — installs SIGWINCH handler for terminal-resize. The (A) is hardened by ONLY calling `pthread_kill` (async-signal-safe) from the handler, never anything that allocates.

**Hardening.** Lint rule (clippy or custom) catching non-async-signal-safe calls inside the handler. Loom is not applicable (signals are not threads).

---

## 10. Embedded volatile MMIO and asm

**Pattern.** `core::ptr::read_volatile` / `write_volatile` for memory-mapped peripherals; `core::arch::asm!` for things like enabling interrupts.

**Why (A).** The compiler can't reason about memory the CPU itself modifies (peripherals); volatile is the language's way of opting out of optimization for these accesses. `asm!` is unsafe by definition because the compiler doesn't model the assembly's effects.

**Falsification survives.**
- Alternative: PAC / HAL crates (e.g., `embedded-hal`, `stm32f4xx-hal`). → use them in application code; the (A) is in the PAC/HAL itself.
- Alternative: vendor-provided C SDKs. → that's still FFI (A).

**Exemplar.** `/dp/pi_agent_rust/src/uart.rs` — bare-metal UART access via `read_volatile` on `0x4000_0000` + ARM `asm!` for memory barriers.

**Hardening.** Per-peripheral safe-wrapper type. `Uart` owns the MMIO address; its methods are safe because they enforce single-ownership of the peripheral.

---

## Allocator-identity (cross-cutting)

A frequent (A)-vs-(C) confusion: a (C) rewrite that "removes" an `unsafe { Box::from_raw(ptr) }` by switching to a `Vec<T>` ALSO silently switches the allocator if the original was in an arena.

**Rule.** Allocator identity is part of the soundness contract. A (C) rewrite must preserve the allocator:

| Original | Preserved-allocator rewrite |
|----------|-----------------------------|
| `bumpalo::Bump`-allocated arrays | `bumpalo::collections::Vec<T>` |
| `slab::Slab`-allocated entries | `slab::Slab<T>` (no rewrite needed) |
| Custom-allocator `Box<T, A>` | Keep custom allocator generic |
| `mmap`-backed buffer | `memmap2::Mmap` (NOT `Vec<u8>`) |
| Page-aligned for io_uring | Custom `Layout::from_size_align(N, 4096)` (NOT `Vec<u8>` then transmute) |

If the rewrite NEEDS to change the allocator, that's a user-visible behavior change. Document in the plan; require explicit user approval.

---

## Unwinding (cross-cutting)

(A) sites that touch any of: FFI, signal handlers, allocators, async cancellation, MUST be `unwind = "abort"` or use `catch_unwind` to convert panics into errors. Rust unwinding through `extern "C"` is UB; signal handlers panicking is UB; allocator panic is process-fatal.

In `Cargo.toml`:

```toml
[profile.release]
panic = "abort"   # for FFI-heavy crates that ship binaries

[profile.dev]
panic = "abort"
```

Or, for library crates, document that the crate's `unsafe` functions are non-panicking by construction.

---

## Common (A) misclassifications observed in audits

| Looks like (A) | Actually | Reason |
|----------------|----------|--------|
| `unsafe { transmute(...) }` for repr-cast | (C) | `zerocopy` / `bytemuck` cover this safely |
| Hand-rolled `Box::from_raw` round-trip | (C) | The original pattern likely just needed `&mut T` |
| `slice::get_unchecked` in inner loop | (B) | Perf-bucket; measure to decide vs (C) |
| `unsafe impl Send for X(*const T)` | (C) | Newtype with audited `Send` impl |
| `MaybeUninit::assume_init` after manual writes | (C) | `std::array::from_fn` or `init_array!` |
| `Pin::new_unchecked` in a Future | (C) usually | `pin-project-lite` covers most cases |

The (A) bucket should be SMALLER than your first instinct suggests. The default lean is downward to (C).

---

## When (A) is correctly large

Some crates ARE FFI / allocator / runtime. Their (A) bucket is large by design:

- `frankenlibc` — purpose is FFI; (A) ≈ 60% of all sites.
- `frankenfs` — purpose is allocator + filesystem; (A) ≈ 50%.
- `mcp_agent_mail_rust::ws` — runtime-level Pin; (A) ≈ 30%.

For these crates, the audit's goal isn't reducing (A) — it's hardening every (A) with a sharp SAFETY comment, a clear proof obligation, and a clippy lint enforcing caller-side correctness.

---

## Acceptance signal

An (A) classification passes when:

1. **The JUSTIFICATION block** is filled in per [CLASSIFICATION-RUBRIC.md § (A)](../methodology/CLASSIFICATION-RUBRIC.md#a-strictly_unavoidable) — 3 failed alternatives + steel-man attack + rebuttal.
2. **The SAFETY comment** in the code names the caller-side proof obligation explicitly.
3. **A clippy / lint rule** (if expressible) catches caller-side violations.
4. **Allocator identity** is documented if relevant.
5. **Unwinding policy** is documented if relevant (signal handlers, FFI, allocators).
6. **The Phase 6 adversarial reclassifier** has tried to defeat the (A) and failed.

If any of these is missing, the site doesn't exit Phase 4 / Phase 6.
