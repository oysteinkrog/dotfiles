# Miri Shims — Patterns For Code Miri Can't Run

Miri is an interpreter for Rust's abstract machine. It cannot execute foreign code (FFI), most OS syscalls, asm!, or anything that escapes the abstract machine's model. To audit code paths that depend on these, we author **shims**: `#[cfg(miri)]` Rust implementations that *preserve the aliasing contract* of the real call while letting Miri proceed.

The shim must be at least as strict as the real call — never a softer model that hides UB. A shim that makes the code "Miri-clean" while the real implementation would race is worse than no shim.

This file is the recipe catalogue.

---

## Shim Principle Of Least Permission

A shim's signature, lifetimes, mutability constraints, and Send/Sync requirements must be **identical to or stricter than** the real call. If the real `libc::write` accepts a `*const c_void` and treats it as read-only for `nbyte` bytes:

```rust
// Real signature (Rust binding):
pub fn write(fd: c_int, buf: *const c_void, nbyte: size_t) -> ssize_t;

// CORRECT shim — same constraints
#[cfg(miri)]
unsafe fn write(fd: c_int, buf: *const c_void, nbyte: size_t) -> ssize_t {
    // Miri can simulate: read nbyte bytes through buf to "exercise" the aliasing contract
    let slice = unsafe { std::slice::from_raw_parts(buf as *const u8, nbyte) };
    std::hint::black_box(slice); // prevent optimization away
    nbyte as ssize_t              // pretend the write succeeded
}

// WRONG shim — softer constraints
#[cfg(miri)]
unsafe fn write(_fd: c_int, _buf: *const c_void, nbyte: size_t) -> ssize_t {
    nbyte as ssize_t  // BUG: doesn't actually read buf; misses aliasing UB
}
```

The wrong shim never touches `buf`, so any aliasing UB at the buf pointer is invisible to Miri. Always exercise the contract.

---

## Shim Categories

### S1 — Pure-pretend (when the call has no observable side effect in the abstract machine)

For `libc::getpid()`, `libc::geteuid()`, etc:

```rust
#[cfg(miri)]
fn getpid() -> libc::pid_t { 12345 }

#[cfg(miri)]
fn geteuid() -> libc::uid_t { 1000 }
```

These calls don't aliasing-touch any Rust memory. The shim just returns a plausible value.

### S2 — Exercise-the-pointer (when the call reads/writes through a raw pointer)

For `libc::write`, `libc::read`, `libc::memcpy`, `libc::memset`:

```rust
#[cfg(miri)]
unsafe fn memcpy(dst: *mut c_void, src: *const c_void, n: size_t) -> *mut c_void {
    let s = std::slice::from_raw_parts(src as *const u8, n);
    let d = std::slice::from_raw_parts_mut(dst as *mut u8, n);
    d.copy_from_slice(s);
    dst
}

#[cfg(miri)]
unsafe fn memset(s: *mut c_void, c: c_int, n: size_t) -> *mut c_void {
    let dst = std::slice::from_raw_parts_mut(s as *mut u8, n);
    dst.fill(c as u8);
    s
}
```

These exercise the abstract-machine memory model exactly as the real call would.

### S3 — File-descriptor pretend (when the call returns a handle that's later passed back)

For `libc::open`, `libc::socket`, `libc::dup`:

```rust
#[cfg(miri)]
fn open(_path: *const c_char, _flags: c_int) -> c_int {
    // Return a fake fd; downstream code must accept it
    use std::sync::atomic::{AtomicI32, Ordering};
    static NEXT_FD: AtomicI32 = AtomicI32::new(100);
    NEXT_FD.fetch_add(1, Ordering::SeqCst)
}

#[cfg(miri)]
fn close(_fd: c_int) -> c_int { 0 }
```

Caveat: fake fds don't connect to real file state. Tests that read/write back from the fd need a fake VFS layer. For most Miri tests, just verifying the close happens (no double-close, no leak) is enough.

### S4 — Allocator (when the call returns memory ownership)

For `libc::malloc`, `libc::free`, `libc::calloc`:

```rust
#[cfg(miri)]
unsafe fn malloc(size: size_t) -> *mut c_void {
    let layout = std::alloc::Layout::from_size_align(size, 16).unwrap();
    std::alloc::alloc(layout) as *mut c_void
}

#[cfg(miri)]
unsafe fn free(ptr: *mut c_void) {
    if ptr.is_null() { return; }
    // BUG-PRONE: we don't know the original layout.
    // For Miri, deallocate with align 16 and a recorded size.
    // Better: maintain a side-table of (ptr -> layout) for the fakes.
    let layout = std::alloc::Layout::from_size_align(1, 16).unwrap();
    std::alloc::dealloc(ptr as *mut u8, layout);
}
```

**WARNING:** This shim is incomplete because Rust's `dealloc` needs the original layout. The real fix is a side-table:

```rust
#[cfg(miri)]
mod miri_alloc_table {
    use std::collections::HashMap;
    use std::sync::Mutex;
    use once_cell::sync::Lazy;
    pub static ALLOCATIONS: Lazy<Mutex<HashMap<usize, std::alloc::Layout>>> =
        Lazy::new(|| Mutex::new(HashMap::new()));
}
```

Then `malloc` records, `free` looks up.

### S5 — Threading (when the call spawns or joins)

For `pthread_create`, `pthread_join`:

```rust
#[cfg(miri)]
unsafe fn pthread_create(
    thread: *mut pthread_t,
    _attr: *const pthread_attr_t,
    start: extern "C" fn(*mut c_void) -> *mut c_void,
    arg: *mut c_void,
) -> c_int {
    let handle = std::thread::spawn(move || {
        let _ = unsafe { start(arg) };
    });
    *thread = Box::into_raw(Box::new(handle)) as pthread_t;
    0
}
```

This actually creates a real `std::thread`, so Miri can simulate inter-thread aliasing. But Miri's threading is limited (it runs threads sequentially with a chosen interleaving). For thorough concurrency testing, supplement with loom.

### S6 — Signal-handler (when the call installs a signal handler)

For `libc::signal`, `libc::sigaction`:

```rust
#[cfg(miri)]
fn signal(_signum: c_int, _handler: usize) -> usize {
    // Miri can't deliver real signals. Return a fake "previous handler" address.
    0
}
```

**Limitation:** Code that depends on the handler actually firing won't get tested under Miri. For that, use the real binary + TSan + a triggering test.

### S7 — Time (when the call reads the clock)

For `libc::time`, `libc::clock_gettime`:

```rust
#[cfg(miri)]
unsafe fn clock_gettime(_clk_id: clockid_t, tp: *mut timespec) -> c_int {
    if !tp.is_null() {
        (*tp).tv_sec = 1700000000; // some fixed plausible epoch
        (*tp).tv_nsec = 0;
    }
    0
}
```

Time-dependent tests usually shouldn't be Miri-driven anyway.

### S8 — mmap (when the call maps memory)

For `libc::mmap`, `libc::munmap`:

This is the trickiest shim because mmap returns a fresh allocation that the rest of the program treats as a flat memory region. The Miri shim allocates a normal Rust allocation:

```rust
#[cfg(miri)]
unsafe fn mmap(
    addr: *mut c_void, length: size_t, _prot: c_int,
    _flags: c_int, _fd: c_int, _offset: off_t,
) -> *mut c_void {
    if !addr.is_null() {
        // We can't honor MAP_FIXED in the shim; downstream code must tolerate this
        return libc::MAP_FAILED;
    }
    let layout = std::alloc::Layout::from_size_align(length, 4096).unwrap();
    let p = std::alloc::alloc_zeroed(layout);
    if p.is_null() { libc::MAP_FAILED } else { p as *mut c_void }
}
```

**Aliasing fidelity:** This shim does NOT simulate cross-process visibility (the *whole point* of `MAP_SHARED`). Multi-process tests need to run for-real, not under Miri. For single-process Miri tests, this shim is enough to exercise the Rust-side aliasing contract.

### S9 — io_uring / epoll (when the call is event-driven)

Don't shim these. Move the io_uring layer behind a trait, and provide a `MockReactor` for `#[cfg(miri)]` that completes operations synchronously in-line. This is *not* a shim — it's a parallel implementation. The trait boundary is where you verify the aliasing contract.

---

## How To Author A Shim Systematically

1. **Identify the calls Miri can't run.** Run `cargo +nightly miri test 2>&1 | grep "unsupported operation"` and collect them.
2. **For each call, classify into S1–S9.** Use the categories above.
3. **Author the shim in a `#[cfg(miri)] mod miri_shims { ... }` module.**
4. **Re-route the existing FFI call:** `#[cfg(miri)] use miri_shims::write; #[cfg(not(miri))] use libc::write;`
5. **Test the shim itself.** Add a Miri test that exercises the shim's aliasing contract (e.g., for memcpy, write through dst while a `&` to src is live and expect Miri to flag).
6. **Document the shim's fidelity.** Specifically: what does it NOT model? Multi-process visibility, signal delivery, time progression, etc. Record this in `phase3_raw/miri_shim_notes.md`.

---

## Where Shims Don't Help

Cases where you should NOT shim but instead run a non-Miri test:

- Multi-process behavior (`MAP_SHARED`, fcntl locking, named pipes)
- Real-time scheduling (`SCHED_FIFO`, etc.)
- Signal delivery (delivered asynchronously to a running thread)
- Hardware interaction (MMIO, DMA)
- LLVM-specific optimizations (vectorization, FMA fusion)
- ASLR / address-dependent behavior

For these, use the real binary under sanitizers (ASan, TSan, LSan) + targeted fuzz/property tests instead.

---

## Shim Composition Patterns

For projects with extensive FFI (frankenlibc, frankensqlite), centralize the shims:

```rust
// crates/<proj>/src/miri_shims.rs
#![cfg(miri)]

mod allocator;
mod io;
mod threading;
mod time;

pub use allocator::{malloc, free, calloc};
pub use io::{open, close, read, write, mmap, munmap};
pub use threading::{pthread_create, pthread_join};
pub use time::clock_gettime;
```

Then the rest of the crate has:
```rust
#[cfg(miri)] use crate::miri_shims as os;
#[cfg(not(miri))] use libc as os;
```

This minimizes the diff between Miri and native code paths.

---

## Anti-Patterns

| ✗ | Why |
|---|---|
| Shim that doesn't touch the pointer | Misses aliasing UB at the call boundary |
| Shim that's softer than the real call | Hides UB that the real call would expose |
| `unimplemented!()` for "later" | The Miri test fails forever; better to have a real shim now |
| Shim in production code (no `#[cfg(miri)]`) | Slows native execution |
| Shim that calls real FFI through a different name | Doesn't fix the problem; Miri still can't run it |
| Forgetting to document the shim's fidelity gap | Future maintainer assumes Miri-clean = fully sound |

---

## Tool support

`cargo +nightly miri test 2>&1 | scripts/miri-unsupported-extract.sh` (in the script catalogue if installed) extracts the "unsupported operation: X" lines and groups by call name. Use this to prioritize shim authoring.
