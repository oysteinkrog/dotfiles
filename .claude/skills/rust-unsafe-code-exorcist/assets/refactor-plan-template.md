# site-NNNN — Refactor Plan

**Bucket.** `(A) | (B) | (C)`
**Cluster.** `<cluster-name>`
**Pattern.** `<FFI | Pin | allocator | SIMD | pointer migration | etc.>`
**Plan author.** `<agent + pass>`
**Risk.** `Low | Medium | High`

---

## If (A) — Hardening Plan

### Hardened SAFETY comment

To replace the existing comment AT the unsafe site:

```rust
/// <prose explanation of what the unsafe does, ~3-5 sentences>
///
/// # Safety
///
/// The caller MUST guarantee:
/// - <invariant 1 — specific and testable>
/// - <invariant 2>
/// - <invariant 3>
///
/// These invariants are enforced by:
/// - <where each invariant is established in code>
///
/// What breaks if any invariant is violated:
/// - <specific UB outcome>
///
/// Unwinding: <Rust unwinding through this site is UB / safe under panic="abort" / handled via catch_unwind>
/// Async cancellation: <not reachable from async / fully unwind-safe / handled via guard>
/// Allocator identity: <preserved / N/A>
```

### Clippy / lint rule (if expressible)

```toml
# clippy.toml additions:
disallowed-methods = [
    { path = "<violating call>", reason = "violates proof obligation for site-NNNN; use <safe wrapper> instead" },
]
```

If clippy doesn't cover the obligation: file a follow-up bead for a custom proc-macro lint.

### Acceptance criteria

```bash
# SAFETY comment landed
grep -B 2 -A 30 "fn <name>" <crate>/src/<file>.rs | grep "# Safety"
# Lint rule landed
cargo clippy -p <crate>
# Geiger count unchanged (A sites stay (A))
cargo +nightly geiger -p <crate>
```

---

## If (B) — safe-only Feature Plan

### Branch implementations

```rust
#[cfg(not(feature = "safe-only"))]
pub fn hot_fn(<args>) -> <ret> {
    // CURRENT UNSAFE
    <verbatim source>
}

#[cfg(feature = "safe-only")]
pub fn hot_fn(<args>) -> <ret> {
    // SAFE ALTERNATIVE
    <safe code>
}
```

### Per-target bench results

| Target | criterion (default) | criterion (safe-only) | hyperfine | Δ end-to-end |
|--------|---------------------|----------------------|-----------|--------------|
| x86_64-v2 | X ns | Y ns | A ms / B ms | +N% |
| x86_64-v3 | ... | ... | ... | ... |
| aarch64-linux | ... | ... | ... | ... |
| aarch64-macos | ... | ... | ... | ... |

**Budget:** `<N>%`
**Targets within budget:** <list>
**Targets over budget:** <list>

**Decision:**
- Targets within budget → graduate to (C) (delete unsafe for those target paths).
- Targets over budget → keep (B); ship safe-only feature.

### Cargo.toml change

```toml
[features]
default = []   # perf path on by default
safe-only = []
```

### CI matrix entry

```yaml
matrix:
  os: [ubuntu-latest, macos-14]
  feature: [all-features, safe-only]
  rustflags:
    - "-C target-cpu=x86-64-v2"
    - "-C target-cpu=x86-64-v3"
```

### Acceptance criteria

```bash
cargo test --features safe-only --no-default-features -p <crate>
cargo bench --bench <bench>
hyperfine './target/release/<bin>' './target/release/<bin>-safe'
```

---

## If (C) — Safe Refactor Plan

### Safe replacement code

<full safe code; paste-ready; not pseudocode>

```rust
// Before (current unsafe):
//
// <verbatim source>

// After (safe rewrite):
<full Rust code>
```

### Property-based equivalence test

```rust
// audit/tests/equivalence_site_NNNN.rs

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig { cases: 10_000, ..ProptestConfig::default() })]

    #[test]
    fn equivalence(x in <strategy>) {
        let unsafe_result = original::f(x.clone());
        let safe_result = rewritten::f(x.clone());
        prop_assert_eq!(unsafe_result, safe_result);
    }

    #[test]
    fn panics_match(x in <strategy>) {
        let unsafe_panic = std::panic::catch_unwind(|| original::f(x.clone())).is_err();
        let safe_panic = std::panic::catch_unwind(|| rewritten::f(x.clone())).is_err();
        prop_assert_eq!(unsafe_panic, safe_panic);
    }
}
```

Inputs covered:
- Normal path
- Empty input
- Maximum-size input
- Panic-triggering inputs (NaN, max-int, etc.)
- Error-returning inputs

### Metamorphic test (where applicable)

```rust
proptest! {
    #[test]
    fn metamorphic(x in <strategy>) {
        prop_assert_eq!(rewritten::f(transform(x.clone())), transform(rewritten::f(x)));
    }
}
```

### Loom model (if concurrency-touching)

```rust
#[cfg(loom)]
#[test]
fn loom_<...>() {
    loom::model(|| {
        // model
    });
}
```

### Miri command

```bash
cargo +nightly miri test --test equivalence_site_NNNN
MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test --test equivalence_site_NNNN
```

### Risk + API change

- **Risk:** `Low | Medium | High`
- **API change:** `none | additive | breaking`
- **Migration path (if breaking):** <description>

### Allocator identity

- **Original allocator:** `<name>`
- **Rewrite allocator:** `<name>`
- **Preserved?** `yes | no — <reason>`

### Drop-glue trace

| Exit path | Destructors run | Order | Concerns |
|-----------|-----------------|-------|----------|
| success | <list> | <order> | <none> |
| early return via `?` | <list> | <order> | <none> |
| panic in mid-init | <list> | <order> | <see operator 🔒> |
| await-drop (if async) | <list> | <order> | <see operator 🔁> |

### Acceptance criteria

```bash
cargo test -p <crate> --test equivalence_site_NNNN
cargo +nightly miri test -p <crate> --test equivalence_site_NNNN
cargo bench --bench <bench> -- --output-format bencher
  # expected: criterion mean within <N>% of baseline
cargo +nightly geiger -p <crate>
  # expected: count decreased by <delta>
```

---

## Cross-references

- Per-site write-up: `audit/sites/<crate>/<file>__<line>.md`
- Classification: `audit/classification/site-<id>.md`
- Equivalence test: `audit/tests/equivalence_site_NNNN.rs`
- Cluster note: `audit/plans/cluster-<R-NNN>.md`
- Bead (after Phase 8): `<br-id>`
