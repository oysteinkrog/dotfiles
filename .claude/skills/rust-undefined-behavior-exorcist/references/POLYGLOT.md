# Polyglot — Rust + C / C++ / Python / JavaScript Boundary UB

Pure-Rust UB is one thing. UB at the boundary between Rust and another language is its own bestiary. This file is the boundary-UB playbook.

For the broader FFI bucket see [UB-TAXONOMY.md §10](UB-TAXONOMY.md). For per-archetype priors see [PROJECT-TYPES.md §P7 FFI Binding](PROJECT-TYPES.md). This file goes deeper.

---

## The polyglot UB principle

> If the foreign language can violate Rust's invariants, the boundary IS an unsafe surface. The audit must extend across the boundary.

A C function that Rust passes a `&mut T` to *can* aliased-write to that memory while Rust still holds the `&mut`. The audit must either:
- Prove the C side respects Rust's aliasing rules (read the C source / docs)
- Encapsulate the boundary so that aliasing is bounded (use `UnsafeCell<T>` + atomics; don't pass `&mut T` to C)

---

## P-1: Rust ↔ C

### Common UB shapes

| Shape | Example | Bucket |
|---|---|---|
| Rust's `&mut T` aliasing violated by C side | Rust gives C a pointer; C also has its own pointer to the same memory | #1, #21 |
| `*const c_char` not NUL-terminated | C string from a buffer with no terminator | #4, #15 |
| `extern "C" fn` calling convention mismatch | `cdecl` vs `stdcall` | #10 |
| Struct layout mismatch | `#[repr(C)]` differs from the actual C struct (alignment, packing) | #3, #10, #22 |
| Allocator mismatch | C `malloc` returned pointer fed to Rust `Box::from_raw` | #20 |
| Callback fired while Rust is mid-borrow | Signal handlers, atexit, etc. | #21 |
| FFI handle reuse | C closes the handle; Rust still holds it | #15 |

### Audit pattern

For every `extern "C"` block:

1. **Cross-reference against the C header.** If you have it, run `bindgen` and diff against the committed declaration. Drift = silent UB.
2. **Validate `#[repr(C)]` layout** with `static_assertions!`:
   ```rust
   use static_assertions::{assert_eq_size, assert_eq_align};
   assert_eq_size!(MyStruct, sys::my_struct);
   assert_eq_align!(MyStruct, sys::my_struct);
   // For specific field offsets:
   const _: () = assert!(std::mem::offset_of!(MyStruct, field) == sys::offset_of_my_struct_field as usize);
   ```
3. **Wrap raw pointers immediately** at the boundary. Don't let `*mut c_void` leak into business logic; convert to `OwnedFd` / typed newtype.
4. **Document the aliasing contract per function.** If C *might* aliased-mutate during the call, the Rust caller must use `&UnsafeCell<T>` or atomics.

### Miri shim

C calls are not Miri-runnable. Either author a `#[cfg(miri)]` shim (see [MIRI-SHIMS.md](MIRI-SHIMS.md)) or run that test path under native + ASan/TSan.

### Tooling specifically for Rust↔C

- **`bindgen`** to regenerate declarations; diff against committed
- **`cbindgen`** to generate C headers from Rust; for the reverse direction
- **`cargo-careful`** when running native tests; catches some Rust-side UB at the boundary
- **AddressSanitizer** is the primary native catcher for boundary memory errors
- **`cppcheck`** / **`clang-static-analyzer`** on the C side

---

## P-2: Rust ↔ C++

C++ has additional gotchas C doesn't:

### Common UB shapes (in addition to C's)

| Shape | Example |
|---|---|
| Exception unwinding across the FFI | C++ throws; Rust catches via `extern "C-unwind"` (Rust 1.71+) |
| C++ destructor running on Rust-managed memory | RAII C++ object passed by value to Rust |
| Virtual dispatch through pointer Rust holds | Rust holds `*mut Base`; actual object is `Derived` with hidden vtable |
| Name mangling | C++ function isn't `extern "C"`; bindgen sees mangled name |
| ABI break across compiler versions | C++ ABI is less stable than C ABI |

### Audit pattern

- **Always go through `extern "C"` shims.** Don't try to bind to C++ directly; bind to a C wrapper.
- **`extern "C-unwind"`** if exceptions might cross the boundary (Rust 1.71+). Unwinding to a non-unwind frame is UB.
- **Use `cxx` crate** for type-safe C++ interop where possible. It generates the boundary code with verified ABI.

### Tooling

- **`autocxx`** / **`cxx`** — type-safe C++ bindings
- **Clang AddressSanitizer** on the C++ side
- **`libcxx`** with `-D_LIBCPP_DEBUG=1` for additional runtime checks

---

## P-3: Rust ↔ Python (PyO3)

### Common UB shapes

| Shape | Example |
|---|---|
| GIL-not-held when Rust touches Python memory | Rust calls `PyAny::extract` without holding GIL |
| Python frees an object Rust holds a pointer to | Rust kept a borrowed `&PyAny` past its lifetime |
| Rust passes `&str` to Python; Python frees it | Rust's `&str` lifetime didn't outlive Python's borrow |
| Buffer protocol misuse | Rust accesses a Python buffer after Python's released the GIL |

### Audit pattern

- **Always use `Python<'py>` token** to mark GIL holding. The `pyo3` type system enforces it.
- **Avoid `Py<...>::clone_ref`** without GIL — it increments refcount; race if GIL not held.
- **Buffer protocol:** use `pyo3::buffer::PyBuffer<T>` which manages the lifetime.

### Tooling

- **`pyo3`'s `gil-refs` feature** — type-system enforcement of GIL holding
- **`pytest` with `pytest-pythreaded`** — exercise threading at the boundary
- **Python's `tracemalloc`** + Rust's leak detection — cross-check refcount balance

---

## P-4: Rust ↔ JavaScript (wasm-bindgen)

### Common UB shapes

| Shape | Example |
|---|---|
| JS callback fires while Rust holds `&mut Wasm_struct` | JS dispatches an event; Rust's borrow isn't done |
| `JsValue` outlives the JS scope that owns it | Rust holds `JsValue` after the JS function returned |
| Shared linear memory racing between Rust and JS | `SharedArrayBuffer` with both Rust and JS touching the same bytes |
| `f32`/`f64` NaN canonicalization | wasm canonicalizes NaNs; native may not |

### Audit pattern

- **Avoid long-lived `JsValue`** — convert at the boundary to Rust-owned types.
- **No `&mut` across an `.await`** that yields to JS — JS might re-enter Rust.
- **For `SharedArrayBuffer`:** atomics on both sides, treat as `&Cell<T>` semantics.

### Tooling

- **`wasm-bindgen-test`** — browser-driven tests
- **`web-sys` audited bindings** — don't hand-write the JS↔Rust glue
- **Chrome DevTools' "WebAssembly DWARF info"** for debugging

---

## P-5: Rust ↔ Go (cgo bidirectional)

Rare combination, but `cargo-go`-style projects do exist.

### Common UB shapes

| Shape | Example |
|---|---|
| Go GC moves a pointer Rust holds | Go's GC may move heap allocations; Rust pointer becomes dangling |
| Goroutine preemption in the middle of a Rust call | Rust function preempted by goroutine scheduler; state corruption |
| `cgo` calling convention mismatch | Go's calling convention is stackful; Rust expects stackless |

### Audit pattern

- Avoid passing Go pointers to Rust — copy into Rust-owned memory first
- Pin Go memory with `runtime.KeepAlive` during Rust calls
- Use `cbindgen`-generated headers with explicit C ABI

### Tooling

- **Go race detector** (`go test -race`) on the Go side
- **`cgo_traceback`** for cross-language stack traces

---

## P-6: Rust ↔ Lua (mlua, rlua)

### Common UB shapes

| Shape | Example |
|---|---|
| Lua state used after `lua_close` | Rust holds `&Lua` after the underlying state is freed |
| Coroutine yield while Rust holds Lua values | Lua coroutine yields; Rust's stack-allocated values are invalidated |
| Userdata cast mismatch | Rust registers `Foo`; Lua passes `Bar` userdata |

### Audit pattern

- `mlua` and `rlua` already type-check userdata at runtime; don't bypass
- Don't hold Lua values across `coroutine.yield` boundaries

---

## General polyglot audit checklist

Per boundary:
- [ ] Every `extern "<abi>"` block has the ABI verified against the foreign side
- [ ] Every `#[repr(C)]` type has `static_assertions!` for size + align + each field offset
- [ ] Every callback function has documented aliasing constraints
- [ ] Every passed pointer is wrapped in a typed newtype at the boundary
- [ ] The boundary is exercised under ASan + TSan against the real foreign side (Miri can't run FFI)
- [ ] The foreign side is *also* audited (where you have authority — at minimum, link to its audit status)
- [ ] Allocator pairing is documented per function
- [ ] Signal/exception handling is documented (does the foreign side install handlers? do exceptions propagate?)

---

## Subagent

The `polyglot-boundary-auditor` subagent specializes in this — fan it out for any project that ships an FFI surface. See `subagents/polyglot-boundary-auditor.md`.
