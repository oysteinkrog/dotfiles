# CLIPPY-LINT-AUTHORING.md — Encoding Proof Obligations as Lints

Some (A) sites' proof obligations are testable: the caller must not pass null, must not call concurrently, must hold a specific lock. When the obligation is testable, a lint should catch violations at compile time.

This file is the lint-authoring guide.

---

## Three levels of lint encoding

### Level 1 — clippy.toml `disallowed-methods` / `disallowed-types`

The lowest-friction option. Add to `clippy.toml`:

```toml
disallowed-methods = [
    { path = "some::risky::method", reason = "violates the proof obligation for site-NNNN; use safe_wrapper instead" },
]

disallowed-types = [
    { path = "some::RawPtr", reason = "use SafeWrapper instead — see site-NNNN" },
]
```

Use when:
- The obligation is "don't call X / don't use type Y".
- A specific safe alternative exists.

Doesn't work for:
- Conditional obligations ("don't call X if Y").
- Per-argument obligations ("the first arg must be non-null").

---

### Level 2 — clippy's `disallowed-script-idents`, `arithmetic-side-effects`, etc.

Built-in lints can be turned on/off in `clippy.toml`. Useful for blanket policies:

```toml
arithmetic-side-effects-allowed = [
    "u32",  # we accept arithmetic overflow on u32 with explicit wrap
]
```

The unsafe-exorcist's lint config (template at `assets/clippy-lint-template.toml`):

```toml
# Strict lints for unsafe-touching code
disallowed-methods = [
    # Per-audit, per-site obligations
]
arithmetic-side-effects-allowed = []
allow-unwrap-in-tests = false   # safety-grade tests don't use unwrap
allow-expect-in-tests = false
```

---

### Level 3 — custom proc-macro lints

For obligations clippy can't express, write a custom proc-macro lint. The pattern:

```rust
// In a sibling crate `myproj-lints`:
use proc_macro::TokenStream;

#[proc_macro_attribute]
pub fn require_held_lock(attr: TokenStream, item: TokenStream) -> TokenStream {
    // Inspect `item`; emit a compile error if the fn doesn't take the
    // lock-guard type as its first parameter.
    // ...
}
```

Use:

```rust
use myproj_lints::require_held_lock;

#[require_held_lock(MyMutex)]
fn requires_mutex(guard: &MutexGuard<State>, x: u32) -> u32 {
    // The lint guarantees `guard` is in the signature.
    state_lock_held_op(x)
}
```

The proc-macro lint can be MUCH more precise than clippy. Cost: it's an extra crate; the team has to maintain it; build time grows.

---

### Level 4 — clippy custom lint (compiler-internal)

Heaviest weight; write a `clippy_lints::*` rule that ships with a custom build of clippy. Used by very large projects (rustc itself; mozilla; cloudflare).

For most audit-touching projects, level 1–3 is enough.

---

## Per-pattern lint recommendations

### FFI null-termination

**Pattern.** Functions taking `*const c_char` must receive null-terminated strings.

**Lint.** clippy's `disallowed-types` for raw `*const c_char` in pub APIs; require `&CStr`.

```toml
disallowed-types = [
    { path = "*const ::std::os::raw::c_char", reason = "use &CStr in pub APIs to enforce null-termination" },
]
```

### `unsafe impl Send` on a raw-pointer field

**Pattern.** A field of type `*mut T` makes the type `!Send`. The `unsafe impl Send` must justify why it's safe.

**Lint.** No clippy lint; the audit's `audit-allocator-changes.sh`-style script can grep for `unsafe impl Send for X { ... *mut/*const ...}` and require a SAFETY comment in the same impl block.

```bash
# Custom CI check:
for impl_block in $(ast-grep run -l Rust -p 'unsafe impl Send for $T { }' --json); do
  # Check that the same span contains a // SAFETY: comment
  ...
done
```

### `Pin<&mut T>` not held across an await

**Pattern.** `tokio::pin!`-produced `Pin<&mut Fut>` must not survive a `.await` that drops it.

**Lint.** clippy's `await_holding_lock` is closest but not exact. Custom proc-macro lint needed for precision.

### `MaybeUninit::assume_init` after manual writes

**Pattern.** Every field must be written before `assume_init`.

**Lint.** Hard to express generally; per-type custom proc-macro lint that wraps the `assume_init` call:

```rust
#[require_all_fields_initialized]
fn build_my_struct(...) -> MyStruct {
    let mut m = MaybeUninit::<MyStruct>::uninit();
    // ... writes ...
    unsafe { m.assume_init() }
}
```

The macro inspects the function body to verify every field of `MyStruct` is written.

### Allocator identity preservation

**Pattern.** A type that uses `bumpalo::Bump` for its internal vec must not switch to `std::vec::Vec`.

**Lint.** clippy's `disallowed-types` in a per-module config:

```toml
# In src/cache/clippy.toml:
disallowed-types = [
    { path = "::std::vec::Vec", reason = "use bumpalo::collections::Vec to preserve arena identity in this module" },
]
```

(Per-module clippy.toml requires nightly clippy as of 2026 mid-year; check the version.)

---

## Lint scoping

Lints can be:

- **Crate-wide** (`#![deny(clippy::disallowed_methods)]` in `lib.rs`).
- **Module-wide** (`#![deny(...)]` in the module file).
- **Per-function** (`#[deny(clippy::disallowed_methods)]` on the fn).

For audit-grade enforcement, prefer module-wide on the modules containing unsafe. Crate-wide can be aspirational ("we want this everywhere") but module-wide is enforceable.

---

## Lint authoring workflow

The `safety-comment-author` subagent (per `safety-comment-author.md`) drafts the SAFETY comment AND proposes any clippy lint that would catch caller-side violations.

1. Read the (A) justification.
2. Identify which invariants are EXTERNALLY testable (i.e., the lint can check at the call site).
3. Author the clippy.toml entry OR sketch the custom proc-macro lint.
4. The implementer agent integrates the lint config when landing the SAFETY comment.

---

## Lint failure-mode policy

When a lint catches a violation:

- **In CI**: the build fails. The PR author must address.
- **In dev**: clippy emits a warning. The author should fix or document with `#[allow(clippy::disallowed_methods)]` + a justification comment.

Don't `#[allow(...)]` lints silently. Every allow is documented:

```rust
#[allow(clippy::disallowed_methods)]   // SAFETY: ...; see site-NNNN
unsafe fn some_op() { ... }
```

---

## Acceptance signal

The lint authoring for an (A) site passes when:

1. Either: a clippy.toml entry exists that would catch caller-side violations.
2. Or: a custom proc-macro lint exists in the project (or follow-up bead is filed).
3. Or: the SAFETY comment explicitly documents that the obligation is not lintable AND why (rare).
4. The clippy.toml entry is committed in the project repo through the Phase 8.5 active-checkout flow.
5. The CI matrix runs `cargo clippy --workspace -- -D warnings`.

If no lint is expressible AND no follow-up bead is filed AND the SAFETY comment doesn't explain — the (A) hardening is incomplete.
