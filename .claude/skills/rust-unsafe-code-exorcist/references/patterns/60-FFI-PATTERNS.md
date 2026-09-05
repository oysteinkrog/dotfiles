# 60-FFI-PATTERNS.md — Foreign Function Interface

FFI is where the (A) bucket lives. The audit's job here is not removal — it's HARDENING: writing the boundary contract, ensuring panics don't unwind through C, and clustering the unsafe into single safe-wrappers per surface.

---

## The FFI boundary contract

Per FFI call (or `extern "C"` block), write the contract:

```markdown
# Boundary contract for `libc::open` (frankenlibc::sys::open_safe)

## C side promises
- Reads up to a null byte from `path`; returns -1 if path is invalid.
- Returns -1 with errno set on failure; ≥ 0 on success.
- No callback into Rust; no longjmp; no asynchronous-signal interaction beyond
  `errno` (which is thread-local on supported platforms).

## Rust side promises (caller of open_safe)
- `path` is a `&CStr` (null-terminated by type invariant).
- `flags` is a valid combination of `O_*` constants (caller must ensure).
- Caller may panic AFTER open_safe returns, but not DURING (open_safe's body has
  no panic-points; it's a thin call + branch).

## Ownership of returned values
- Returned `RawFd` is owned by Rust. Caller must release via `libc::close` or
  via the OwnedFd wrapper.

## Errors
- errno is translated to `io::Error::last_os_error()` immediately. Caller never
  sees raw errno.

## Panicking
- The wrapper is non-panicking by construction.
- If the C side itself aborts (e.g., due to setrlimit RLIMIT_CPU expiration), the
  process aborts; no Rust unwinding occurs.

## Thread safety
- `libc::open` is thread-safe (POSIX guarantee).
- The wrapper holds no shared state; safe to call from any thread.

## Endianness / padding / ABI
- N/A — open takes no compound types.
- For functions taking structs (e.g., `libc::stat`): explicit `#[repr(C)]` on
  the Rust struct; field-for-field match against libc's C definition; document
  the C version + endianness assumption.
```

This template lives in `assets/ffi-boundary-template.md`. Every `extern "C"` block in the audit gets its own filled-in contract.

---

## Patterns from the exemplar repos

### Pattern F-1: thin safe wrapper per syscall

`/dp/frankenlibc/src/sys/syscall.rs` covers 200+ syscalls in one file. Each is the same pattern:

```rust
pub fn open(path: &CStr, flags: i32) -> io::Result<RawFd> {
    let fd = unsafe { libc::open(path.as_ptr(), flags) };
    if fd < 0 { Err(io::Error::last_os_error()) } else { Ok(fd) }
}

pub fn close(fd: RawFd) -> io::Result<()> {
    if unsafe { libc::close(fd) } == 0 { Ok(()) } else { Err(io::Error::last_os_error()) }
}

pub fn read(fd: RawFd, buf: &mut [u8]) -> io::Result<usize> {
    // SAFETY: buf is a valid &mut [u8]; libc::read writes up to buf.len() bytes
    // and returns the count, or -1.
    let n = unsafe { libc::read(fd, buf.as_mut_ptr() as *mut _, buf.len()) };
    if n < 0 { Err(io::Error::last_os_error()) } else { Ok(n as usize) }
}
```

Every wrapper is non-panicking, returns `io::Result`, takes typed Rust inputs (CStr, &mut [u8], RawFd) instead of raw pointers. The unsafe is one line per wrapper.

### Pattern F-2: owned-handle types

Raw fds are wrapped in `OwnedFd` with `Drop` calling `close`:

```rust
pub struct OwnedFd(RawFd);
impl OwnedFd {
    pub fn from_raw(fd: RawFd) -> Self { OwnedFd(fd) }
    pub fn as_raw(&self) -> RawFd { self.0 }
}
impl Drop for OwnedFd {
    fn drop(&mut self) {
        let _ = unsafe { libc::close(self.0) };   // close errors are intentionally ignored on drop
    }
}
```

(Stdlib has `std::os::fd::OwnedFd`; use it when available.)

### Pattern F-3: panic boundary at extern "C" entry

For Rust functions called FROM C (`#[no_mangle] pub extern "C" fn foo(...)`), Rust unwinding is UB. Wrap the body in `std::panic::catch_unwind`:

```rust
#[no_mangle]
pub extern "C" fn frankenlibc_init() -> i32 {
    let result = std::panic::catch_unwind(|| {
        // Rust code that might panic
        do_init()
    });
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => e.into_c_errno(),
        Err(_panic) => -1,    // panic from Rust; convert to C error code
    }
}
```

Document this pattern in the SAFETY comment and ENFORCE it via:

```toml
[profile.release]
panic = "abort"     # for crates that ship binaries
```

For library crates that may be linked into C programs, `panic = "abort"` is even more important — if the linking program uses `unwind` panic strategy, mismatched ABIs are UB.

### Pattern F-4: longjmp / setjmp avoidance

Some C libraries (sqlite, libpng) use setjmp/longjmp for error handling. Rust does NOT support longjmp through Rust frames; it's UB.

If the FFI library uses longjmp:

- Confine the longjmp to a "longjmp scope" inside the C side. Wrap with the C library's recommended error-handling API (sqlite has `sqlite3_busy_handler` etc.).
- Document the no-Rust-frames-on-the-longjmp-path invariant.

`/dp/frankensqlite/src/error.rs` has a worked example: the sqlite step/exec functions are wrapped so that all longjmp-able calls happen in a thin C-only wrapper invoked from Rust.

### Pattern F-5: C callbacks calling back into Rust

When C calls a Rust callback (e.g., `qsort_r`-style), the callback is `extern "C"`. The same panic-boundary pattern applies:

```rust
extern "C" fn my_compare(a: *const c_void, b: *const c_void) -> i32 {
    let _guard = std::panic::catch_unwind(|| {
        let a = unsafe { &*(a as *const i32) };
        let b = unsafe { &*(b as *const i32) };
        a.cmp(b) as i32
    });
    _guard.unwrap_or(0)    // panic → fallback to "equal"
}
```

For callbacks that the user provides, document the no-panic requirement OR wrap user callbacks with the catch_unwind boundary.

### Pattern F-6: bindgen-generated unsafe surfaces

`bindgen` emits `extern "C" { fn foo(...); }` plus `#[repr(C)] struct ...`. Hundreds of declarations. The audit treats them as a single cluster:

```
Cluster F-001: bindgen-generated bindings for libpng
  Member sites: site-2031..site-2289 (259 sites)
  Origin: build.rs runs bindgen on /usr/include/png.h
  Audit position: (A) cluster — wrapped in safe API at frankenimage::png::*
  Hardening: every safe wrapper has its own boundary-contract entry
```

Don't write 259 per-site write-ups. Write the cluster note + per-wrapper contracts.

---

## Common (C) opportunities at the FFI boundary

### C-1: pointer arithmetic → slice operations

```rust
// Before
let mut p = buf.as_mut_ptr();
let end = unsafe { p.add(buf.len()) };
while p < end {
    unsafe { *p = 0; p = p.add(1); }
}

// After
buf.fill(0);
```

The standard `slice::fill` is exactly as fast (LLVM lowers both to memset). Zero unsafe.

### C-2: C string conversion → CStr / CString

```rust
// Before
let c_str = unsafe { CStr::from_ptr(raw_ptr).to_str() }.unwrap();

// After (if raw_ptr comes from a known C function with documented null-termination)
let owned = unsafe { CStr::from_ptr(raw_ptr) }.to_str().expect("C side guarantees UTF-8");
// Use `owned` only within the lifetime where raw_ptr is valid.
```

The `unsafe` stays (CStr::from_ptr is unsafe because Rust can't verify null-termination); but the `.unwrap()` becomes `.expect()` with a documented rationale. For better safety, copy to `CString` immediately:

```rust
let owned = unsafe { CStr::from_ptr(raw_ptr) }.to_owned();
// Now `owned: CString` is independent of raw_ptr's lifetime.
```

### C-3: errno → io::Error

`io::Error::last_os_error()` reads errno safely on all supported platforms. Use it instead of `unsafe { libc::__errno_location() }`.

---

## Unwinding policies for FFI-heavy crates

In `Cargo.toml`:

```toml
[profile.release]
panic = "abort"

[profile.dev]
panic = "abort"
```

This ensures any panic terminates the process rather than unwinding through C. Document the choice in the README; downstream consumers of the crate need to know.

If the crate must support `panic = "unwind"` (e.g., it's a library used by programs that rely on unwinding), every `extern "C"` Rust function must use `catch_unwind`.

---

## Acceptance signal

An FFI surface passes when:

1. Each `extern "C"` block has a filled-in boundary contract.
2. Each FFI call goes through a thin safe wrapper (no raw FFI calls in user-facing code).
3. Owned-handle types exist for all returned resources.
4. Panic boundaries are in place (catch_unwind on extern "C" Rust functions; panic=abort if applicable).
5. Longjmp/setjmp paths are confined to C-only frames; no Rust on the longjmp path.
6. Cluster notes cover bindgen-generated bindings (no per-binding write-ups).
7. Every safe wrapper has its own SAFETY comment naming the boundary invariants.
