# 85-PROC-MACRO-UNSAFE.md — Custom Derive Macros That Emit Unsafe

Custom proc-macros / derives that emit `unsafe { ... }` are a special audit case: every call site inherits the macro's soundness obligation, but the call site never sees the unsafe in source.

This is companion to [40-MACRO-GENERATED-UNSAFE.md](40-MACRO-GENERATED-UNSAFE.md) — that file covers EXTERNAL macros (zerocopy-derive, pin-project-lite, etc.); this file covers PROJECT-OWN proc macros.

---

## The audit's position on project-own proc macros

If the project HAS a `*-derive` crate that emits unsafe in its output, the audit treats it specially:

1. **The proc-macro code itself** lives in `<derive-crate>/src/lib.rs` and is audited like any other Rust code.
2. **The emitted unsafe** is audited per CALL SITE (each `#[derive(MyDerive)]` use).
3. **The derive's contract** must be documented: what invariants does the user-type need to satisfy for the derive's unsafe output to be sound?

---

## Pattern PM-1 — Derive that emits `unsafe impl SomeTrait`

```rust
// User code
#[derive(MyAudit)]
struct Foo {
    inner: Vec<u8>,
}

// Macro expansion
unsafe impl MyTrait for Foo {
    fn audit_method(&self) -> &[u8] {
        // SAFETY: emitted by MyAudit derive; relies on Foo's `inner` being `Vec<u8>`.
        unsafe { &*self.inner.as_ptr() }
    }
}
```

**Audit concern.** The derive assumes the user's type has a `Vec<u8>` field named `inner`. If the user adds a `MaybeUninit<u8>` field BEFORE `inner`, the derive's offset assumption breaks.

**Mitigation.** The derive's macro should EITHER:
- Generate field-position-independent code (use `&self.inner.as_ptr()`, NOT `(self as *const Foo).offset(N)`), OR
- Emit a compile-time check that catches user-type misuse.

---

## Pattern PM-2 — Derive that imposes a layout requirement

```rust
// User code
#[derive(MyAudit)]
#[repr(C)]    // required by the derive
struct Foo {
    a: u32,
    b: u32,
}
```

**Audit concern.** The derive needs `#[repr(C)]` to be sound. If the user omits it, the layout is `repr(Rust)` (undefined order); the derive's `unsafe { transmute }` is UB.

**Mitigation.** Use `static_assertions::const_assert!` or a `where` clause that enforces the layout. In the derive's emit:

```rust
const _: () = {
    // Compile error if Foo is not #[repr(C)]
    fn check<T>() where T: Sized + ::core::marker::Sized {
        let _ = <#name as MyAudit>::__layout_check();
    }
};
```

Or use the `bytemuck::Pod` derive's approach: require the user to also derive `bytemuck::Pod`, which itself requires `#[repr(C)]`.

---

## Pattern PM-3 — Derive that emits `unsafe` based on field types

```rust
// User code
#[derive(MyAudit)]
struct Foo {
    a: u32,
    b: u32,
}

// Macro expansion (only sound if all fields are Copy + 'static)
unsafe impl MyAudit for Foo {
    unsafe fn from_raw(p: *const u8) -> Self {
        unsafe { core::ptr::read(p as *const Foo) }
    }
}
```

**Audit concern.** If the user adds a `Vec<u8>` field (not Copy + 'static), `from_raw` produces a value that's bit-identical to memory but logically aliased — UB.

**Mitigation.** Emit field-level type bounds:

```rust
const _: fn() = || {
    fn assert_copy<T: Copy + 'static>() {}
    // For every field:
    assert_copy::<u32>();
    assert_copy::<u32>();
};
```

Or require the user to derive `Copy` AND `'static`:

```rust
#[proc_macro_derive(MyAudit)]
pub fn derive_my_audit(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    // Emit a where-clause requiring all fields to be Copy + 'static
    // ...
}
```

---

## Pattern PM-4 — Hygiene failures

Proc macros can emit code that references identifiers in unexpected ways. If a user's type shadows the macro's expected identifier, the emitted unsafe might call the wrong fn.

```rust
// Macro emits:
unsafe { Vec::from_raw_parts(p, len, cap) }

// User code shadows Vec:
mod my_user_code {
    struct Vec;   // shadows std::vec::Vec
    #[derive(MyAudit)]
    struct Foo {
        v: ::std::vec::Vec<u8>,
    }
}
```

**Mitigation.** Always emit fully-qualified paths in macro output:

```rust
// Good
unsafe { ::std::vec::Vec::from_raw_parts(p, len, cap) }

// Bad
unsafe { Vec::from_raw_parts(p, len, cap) }
```

The `quote!` macro should use `::std::` paths uniformly.

---

## Audit checklist per project-own proc macro

For each `*-derive` crate in the workspace:

- [ ] The proc-macro source is in the inventory (audited like any Rust code).
- [ ] `cargo expand` output is captured for every `#[derive(...)]` site.
- [ ] The contract is documented: what user-type properties does the derive require?
- [ ] Compile-time checks enforce the contract (where-clauses, const-asserts, mandatory derives).
- [ ] Identifiers in emitted code are fully qualified.
- [ ] The derive has unit tests for: correct usage (success), incorrect usage (compile error or runtime error documented).
- [ ] The derive's emitted unsafe has SAFETY comments in the macro source.
- [ ] Macro hygiene tests verify no identifier-shadowing bugs.

---

## Pattern PM-5 — Macro emits raw `transmute` (consider deletion)

Some project-own macros emit `unsafe { transmute(...) }`. The audit's bias is to delete these in favor of:

- `zerocopy-derive` for repr-cast.
- `bytemuck-derive` for Pod / Zeroable.
- `safe-transmute` (when stabilized).

If the project's derive duplicates what these crates do, delete the project's derive; use the established crate.

**Refactor (C):** identify the project-own derive's purpose; find the equivalent vetted derive; migrate.

---

## Pattern PM-6 — Macro emits `Send`/`Sync` impls

```rust
#[proc_macro_derive(SendIfFieldsAre)]
pub fn derive_send(input: TokenStream) -> TokenStream {
    // Emit: unsafe impl Send for #name where (each field: Send) {}
}
```

This is a manual auto-derive replication. The audit:

- Compare to `auto_impl` / `derive_more` / `derive-deftly` — there's almost always a vetted alternative.
- If the macro is justified (it has properties the alternatives don't), keep it BUT verify it emits `where` clauses that the compiler will check.

---

## Exemplar precedents

- `/dp/beads_rust/macros/src/repr_cast.rs` — project-own derive that emitted unsafe transmute; refactored to use `zerocopy-derive` ((C); bead `br-beads-243` analog).

---

## Anti-patterns

- **Derive that emits unsafe with no documentation of the user-type contract.** The derive's safety obligation transfers to every user; users can't satisfy it if they don't know it.
- **Derive that doesn't emit compile-time checks for its assumptions.** A user who violates an assumption may not see a compile error; might be a runtime UB instead.
- **Project-own derive duplicating zerocopy/bytemuck.** Unless there's a specific feature gap, delete the project's derive.
- **Derive that emits `unsafe impl Send`/`Sync` without proper `where` clauses.** Trivially unsound if added to a non-Send/Sync type.

---

## Acceptance signal

A project-own proc macro emitting unsafe passes when:

1. The proc-macro source is audited as Rust code.
2. Every `#[derive(...)]` user site has a `cargo expand` view.
3. The derive's contract is documented and enforced via compile-time checks.
4. Emitted unsafe has SAFETY comments (in the macro source).
5. Fully-qualified paths used throughout.
6. Hygiene tests pass.
7. If a vetted alternative exists, the (C) refactor to swap is filed (even if deferred).
