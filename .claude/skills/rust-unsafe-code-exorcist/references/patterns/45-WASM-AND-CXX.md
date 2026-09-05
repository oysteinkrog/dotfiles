# 45-WASM-AND-CXX.md — wasm-bindgen + cxx Interop

Two interop targets that share the "Rust calls foreign; foreign calls Rust" shape but have distinct soundness invariants.

---

## wasm-bindgen

When Rust compiles to wasm32 and is invoked from JS / TS.

### What's unsafe by default

- Every `extern "C"` declaration to JS — JS values cross the boundary as opaque handles.
- `wasm_bindgen!` macro expansion contains `unsafe { ... }` blocks for value conversion.
- Memory access from JS via the wasm `Memory` object — JS can write to any address Rust exposed.

### Audit position

- The macro-generated unsafe is (A) inherited from `wasm-bindgen` (the library is audited; trust it like you'd trust libc).
- Project-side hand-written `#[wasm_bindgen]` impls need per-method audit: what does the JS side promise about argument lifetimes? What about thrown exceptions?

### Common (C) refactor opportunities

1. **`#[wasm_bindgen(catch)]` for JS-throwing methods** — instead of "JS may throw and we don't handle it" (which is UB if the Rust side has unwind=abort), use the `catch` attribute to translate JS exceptions to `Result<T, JsValue>`.

2. **`Vec<u8>` ↔ `Uint8Array` zero-copy** — avoid the per-call copy by passing the wasm memory pointer + length directly. wasm-bindgen has built-in support; document the lifetime constraints.

3. **Async fn → `Promise`** — wasm-bindgen handles this; ensure the future is `'static` (no borrows from caller's frame).

### Common (A) sites

- `#[no_mangle] pub extern "C" fn` exported to JS — the panic boundary is critical. Wrap body in `catch_unwind`; convert panics to thrown JS errors.

### Panic strategy for wasm

```toml
[profile.release]
panic = "abort"          # required for wasm; unwind isn't supported on wasm32

[profile.dev]
panic = "abort"          # same
```

Without this, the wasm-bindgen panic handler does the conversion. With it, panics abort the wasm instance immediately — usually preferred.

### Memory growth

`WebAssembly.Memory` can grow; Rust pointer values can become invalidated. The wasm-bindgen-internal `__wbindgen_malloc` / `__wbindgen_free` handle this; project-side code that retains raw pointers across memory-grow events is unsound.

### Acceptance signal

A wasm-bindgen site passes when:

1. Every `#[wasm_bindgen]` method's JS-side contract is documented in the boundary contract.
2. JS-throwing methods use `(catch)`.
3. Panic strategy is `abort`.
4. Async methods are `'static`.
5. Raw memory access across grow events is documented.

---

## cxx — Rust ↔ C++ interop

When Rust and C++ are linked together.

### What's unsafe by default

- `cxx::bridge!` declarations generate `extern "C++" { ... }` blocks (unsafe).
- C++ exceptions are caught at the boundary and converted to Rust `Result<T, cxx::Exception>`.
- C++ types crossing the boundary must be either trivial (POD) or use `UniquePtr` / `SharedPtr`.

### Audit position

- `cxx`-generated code is (A) — the cxx framework's authors audited the patterns.
- Project-side `cxx::bridge!` declarations need per-bridge audit:
  - Are the C++ side functions noexcept? Cxx requires it for `Result<T, ()>` returns.
  - Are pointer lifetimes documented?
  - Are C++ types `Send`/`Sync` per the cxx requirements?

### Common (C) refactor opportunities

1. **Hand-written `bindgen` output → cxx bridge** — bindgen produces `extern "C"` with manual struct definitions; cxx provides higher-level safety. The (C) refactor: convert per-function.

2. **C++ exceptions silently swallowed** → propagate via `Result<T, cxx::Exception>`.

### Common (A) sites

- The cxx bridge itself — auto-generated; trust it.
- C++ destructors interacting with Rust's `Drop` — usually fine, but document the ordering.

### Limitations of cxx

- Doesn't support C++ templates well (the `cxx` bridge has a fixed shape).
- Doesn't support C++ overloading.
- Has a fixed set of supported types; complex C++ types require glue layers.

For projects where cxx doesn't fit, fall back to manual `extern "C"` per [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md). cxx's value is the patterns it standardizes — not all FFI can use it.

### Acceptance signal

A cxx-using site passes when:

1. The `cxx::bridge!` declaration is complete and reviewed.
2. C++ side exception discipline is verified (functions Rust expects `Result` from are noexcept; functions Rust expects to potentially throw are documented).
3. C++ destructor ↔ Rust Drop ordering is documented for shared types.
4. The boundary contract per [60-FFI-PATTERNS.md](60-FFI-PATTERNS.md) is filled in for the bridge.

---

## Other interop surfaces (brief)

### `pyo3` (Python interop)

Similar shape: Python exceptions → Rust `PyResult`; Python's GIL is held across the call; Rust types crossing the boundary are wrapped.

Audit position: pyo3's macros are trusted; project-side `#[pyfunction]` impls need per-function audit (especially around GIL release and re-acquisition).

### `napi-rs` (Node.js interop)

Similar to wasm-bindgen but for Node.js. Async fns return `Promise`; the `tokio_runtime` setup is critical.

### `jni` (Java interop)

Manual JNI is heavy unsafe. The `jni` crate provides a thinner wrapper. Audit position: every `JNIEnv::*` call has documented invariants; per-call SAFETY comment required.

---

## Cross-cutting

For ANY interop surface:

- **Panic strategy** must be documented (abort or unwind across the boundary).
- **Exception/error mapping** must be explicit (catch and convert, never silently drop).
- **Threading model** must be documented (is the foreign side single-threaded, multi-threaded, GIL-held?).
- **Memory ownership** must be clear (who allocates; who frees; lifetime relationships).
- **Type representation** must match (`#[repr(C)]` for struct types; document the foreign-side struct layout).

These are the same dimensions as [60-FFI-PATTERNS.md § boundary contract](60-FFI-PATTERNS.md), specialized per interop tool.
