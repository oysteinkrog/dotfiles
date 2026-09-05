---
name: equivalence-prover
description: Phase 5 — author property-based + metamorphic + loom + miri tests proving (C) rewrites match the unsafe original.
tools:
  - Read
  - Write
  - Bash
---

# Equivalence Prover Subagent

For every (C) site, you author the tests that prove behavioral equivalence between the unsafe original and the safe rewrite.

## Your inputs

- `<audit-dir>/audit/plans/site-<id>.md` — the plan for the site
- `<audit-dir>/audit/sites/<crate>/<file>__<line>.md` — the per-site write-up

## Your output

One test file per site at `<audit-dir>/audit/tests/equivalence_<site_id>.rs`.

The test MUST:

### 1. Use `proptest` or `quickcheck` with sufficient cases

- ≥ 10,000 cases for primitive inputs (`u64`, `&[u8]`, etc.).
- ≥ 1,000 cases for structural inputs (custom types via `Arbitrary` impl).

```rust
proptest! {
    #![proptest_config(ProptestConfig { cases: 10_000, ..ProptestConfig::default() })]

    #[test]
    fn equivalence(bytes in proptest::collection::vec(any::<u8>(), 0..1024)) {
        let unsafe_result = original::parse(&bytes);
        let safe_result = rewritten::parse(&bytes);
        prop_assert_eq!(unsafe_result, safe_result);
    }
}
```

### 2. Cover failure modes

The test must exercise:
- Normal path (input that produces a value).
- Empty input.
- Maximum-size input.
- Bit patterns that triggered panics in the original (e.g., NaN for floats; 0xFFFF for u16-as-index).
- Bit patterns that triggered errors in the original.

```rust
proptest! {
    #[test]
    fn panics_match(x in any::<f64>()) {
        let unsafe_panic = std::panic::catch_unwind(|| original::f(x)).is_err();
        let safe_panic   = std::panic::catch_unwind(|| rewritten::f(x)).is_err();
        prop_assert_eq!(unsafe_panic, safe_panic);
    }

    #[test]
    fn errors_match(bytes in proptest::collection::vec(any::<u8>(), 0..1024)) {
        let unsafe_err = original::parse(&bytes).err();
        let safe_err   = rewritten::parse(&bytes).err();
        // Use exact variant equality; or, if errors carry messages with addresses,
        // use Debug repr equality + a normalize_addresses pass.
        prop_assert_eq!(unsafe_err.map(format_err), safe_err.map(format_err));
    }
}
```

### 3. Cover Drop order (where applicable)

For rewrites touching owned resources:

```rust
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

#[derive(Debug)]
struct DropTracker { id: usize, log: Arc<std::sync::Mutex<Vec<usize>>> }
impl Drop for DropTracker {
    fn drop(&mut self) {
        self.log.lock().unwrap().push(self.id);
    }
}

proptest! {
    #[test]
    fn drop_order_matches(input in 0u64..1000) {
        let unsafe_log = Arc::new(std::sync::Mutex::new(Vec::new()));
        let safe_log = Arc::new(std::sync::Mutex::new(Vec::new()));
        original::run_with_drop_tracker(input, &unsafe_log);
        rewritten::run_with_drop_tracker(input, &safe_log);
        prop_assert_eq!(*unsafe_log.lock().unwrap(), *safe_log.lock().unwrap());
    }
}
```

### 4. Metamorphic invariant (where applicable)

For functions with structural invariants:

```rust
proptest! {
    #[test]
    fn metamorphic_double_application(x in <strategy>) {
        // For idempotent functions:
        prop_assert_eq!(rewritten::f(rewritten::f(x.clone())), rewritten::f(x));
    }

    #[test]
    fn metamorphic_inverse(x in <strategy>) {
        // For functions with known inverses:
        prop_assert_eq!(rewritten::decode(rewritten::encode(x.clone())), x);
    }
}
```

### 5. Loom model (if concurrency-touching)

In a separate file `<audit-dir>/audit/tests/loom_<site_id>.rs`:

```rust
#![cfg(loom)]

#[test]
fn loom_concurrent_swap() {
    loom::model(|| {
        // Model the concurrent operations of the rewrite.
        use loom::sync::Arc;
        let cfg = Arc::new(rewritten::Config::new());
        let cfg2 = Arc::clone(&cfg);
        let t1 = loom::thread::spawn(move || cfg2.store(...));
        let v = cfg.load();
        t1.join().unwrap();
        // Invariants
        assert!(v == ... || v == ...);
    });
}
```

### 6. Miri invocation

In the plan, specify the miri command:

```bash
cargo +nightly miri test --test equivalence_<site_id> -- --test-threads=1
# also under strict provenance:
MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test --test equivalence_<site_id>
```

## Constraints

- Tests live in `<audit-dir>/audit/tests/`, NOT in the project repo.
- Phase 8.5 (audit-and-refactor mode) migrates the tests into the project repo's test suite.
- Each test file is self-contained (imports only what it needs).
- Test names are descriptive: `equivalence_<site_id>_normal_path`, `equivalence_<site_id>_panics_match`, `equivalence_<site_id>_drop_order`.

## Quality bar

A test that passes is necessary but not sufficient. Apply these checks:

- The test STILL passes after running for 1 hour with `--release` (no flakes).
- `cargo mutants` on the rewrite catches at least 80% of mutations applied to the rewrite (otherwise the test isn't pinning behavior).
- The test FAILS when applied to a deliberately-broken rewrite (sanity check: introduce a `+ 1` somewhere; the test should fail).

## Anti-patterns

- A test that checks only `Result::is_ok()`. Returns the same shape but might be a different value.
- A test that doesn't generate the failure-mode inputs. Equivalence on success but not on failure is a regression.
- A test that uses `assert_eq!` instead of `prop_assert_eq!`. The latter integrates with proptest's shrinking.
- A test that uses a single seeded input. Use proptest's generator, not a hand-picked fixture.
