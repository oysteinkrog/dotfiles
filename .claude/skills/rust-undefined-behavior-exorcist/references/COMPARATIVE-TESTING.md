# Comparative Testing — Prove Remediation Is Equivalent To Original

When Phase 8 picks a rewrite (operator `⊕ REWRITE`), the remediation must be *behaviorally equivalent* to the original modulo UB. This file is the playbook for proving it.

The goal: ship the rewrite while keeping the audit trail that proves correctness. Specifically, generate evidence that:
- Every input the original handled correctly is still handled correctly
- Every output the original produced is still produced (modulo UB-bearing outputs, which were never well-defined)
- The performance characteristics meet the rubric

---

## The cfg-gated A/B pattern

Add a Cargo feature for the original implementation. Keep the rewrite as default:

```toml
# Cargo.toml
[features]
default = ["impl-rewrite"]
impl-rewrite = []
impl-original = []   # NOT default
```

```rust
// src/atomic_u64_at.rs
#[cfg(feature = "impl-rewrite")]
pub unsafe fn atomic_u64_at<'a>(ptr: *const u8, offset: usize) -> &'a AtomicU64 {
    // SAFETY: caller must ensure:
    //   - offset + 8 <= the size of the allocation `ptr` points into
    //   - ptr.add(offset) is 8-byte aligned (AtomicU64 alignment requirement)
    //   - the lifetime `'a` does not outlive the underlying allocation
    //   - no other reference to the same 8-byte region is live for `'a`
    //   AtomicU64::from_ptr returns `&'a AtomicU64` bound to a generic lifetime;
    //   the caller's binding site chooses `'a`. Do NOT coerce to `'static`
    //   unless the allocation is itself 'static.
    let p = unsafe { ptr.add(offset) } as *mut AtomicU64;
    unsafe { AtomicU64::from_ptr(p as *mut u64) }
}

#[cfg(feature = "impl-original")]
pub unsafe fn atomic_u64_at<'a>(ptr: *const u8, offset: usize) -> &'a AtomicU64 {
    // SAFETY: <original SAFETY notes, kept for posterity>
    unsafe { &*((ptr.add(offset) as *mut u8) as *const AtomicU64) }
}
```

Now CI runs both:

```yaml
jobs:
  test-rewrite:
    steps: [..., run: cargo test --no-default-features --features impl-rewrite]
  test-original:
    steps: [..., run: cargo test --no-default-features --features impl-original]
  diff-outputs:
    steps:
      - run: |
          cargo run --no-default-features --features impl-rewrite -- < input > out-rewrite
          cargo run --no-default-features --features impl-original -- < input > out-original
          diff out-rewrite out-original
```

The `diff-outputs` job is the key — for *every* input, both impls must produce the same output.

---

## Property-test equivalence

For pure functions, propose an equivalence proptest:

```rust
#[cfg(all(test, feature = "impl-rewrite", feature = "impl-original"))]
mod equivalence {
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn rewrite_matches_original(
            input in any::<u32>()
        ) {
            let r = crate::rewrite::compute(input);
            let o = crate::original::compute(input);
            prop_assert_eq!(r, o);
        }
    }
}
```

Note: this requires both features enabled in the *same* binary. Use a side module structure:

```
src/
├── lib.rs
├── original.rs  (cfg(feature = "impl-original"))
├── rewrite.rs   (cfg(feature = "impl-rewrite"))
└── public.rs    (re-exports based on default feature)
```

Test crate enables both; production enables one.

---

## Differential fuzz

For functions where proptest can't enumerate the input space, fuzz both impls and compare:

```rust
// fuzz/fuzz_targets/equivalence.rs
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if data.len() < 4 { return; }
    let n = u32::from_le_bytes([data[0], data[1], data[2], data[3]]);
    let r = my_crate::rewrite::compute(n);
    let o = my_crate::original::compute(n);
    assert_eq!(r, o, "rewrite diverged from original on input {n}");
});
```

Run for 10–60 minutes; crashes indicate divergence.

---

## Performance comparison (Phase 8 rubric scoring)

Use `criterion`:

```rust
// benches/atomic_u64_at.rs
use criterion::{criterion_group, criterion_main, Criterion};

fn bench_rewrite(c: &mut Criterion) {
    let buf = vec![0u8; 4096];
    c.bench_function("rewrite", |b| b.iter(|| {
        my_crate::rewrite::atomic_u64_at(buf.as_ptr(), 8).load(Ordering::SeqCst)
    }));
}

fn bench_original(c: &mut Criterion) {
    let buf = vec![0u8; 4096];
    c.bench_function("original", |b| b.iter(|| {
        my_crate::original::atomic_u64_at(buf.as_ptr(), 8).load(Ordering::SeqCst)
    }));
}

criterion_group!(benches, bench_rewrite, bench_original);
criterion_main!(benches);
```

Run:
```bash
cargo bench --features impl-rewrite --bench atomic_u64_at -- --save-baseline rewrite
cargo bench --features impl-original --bench atomic_u64_at -- --baseline rewrite
```

The output gives p50/p95 percentage delta — exactly the input Phase 8 rubric needs for "performance delta" scoring.

---

## State-machine equivalence

For stateful APIs (databases, networking, parsers), a single function call isn't enough — the *sequence* of state transitions matters.

Use a model-based test:

```rust
#[cfg(test)]
mod model {
    use proptest::prelude::*;
    use proptest_derive::Arbitrary;

    #[derive(Arbitrary, Debug)]
    enum Op {
        Insert(u32),
        Get(u32),
        Delete(u32),
    }

    proptest! {
        #[test]
        fn rewrite_matches_original_on_sequence(ops: Vec<Op>) {
            let mut r = my_crate::rewrite::Map::new();
            let mut o = my_crate::original::Map::new();
            for op in ops {
                match op {
                    Op::Insert(k) => { r.insert(k, k); o.insert(k, k); }
                    Op::Get(k)    => { prop_assert_eq!(r.get(&k), o.get(&k)); }
                    Op::Delete(k) => { r.remove(&k); o.remove(&k); }
                }
            }
        }
    }
}
```

Sequences of arbitrary length explore the state machine; divergence at any step is a regression.

---

## Concurrent equivalence via loom

For concurrent APIs, neither rewrite nor original must change observable behavior under any legal schedule. Run both under loom:

```rust
#[cfg(loom)]
#[test]
fn loom_concurrent_equivalence() {
    loom::model(|| {
        let r = my_crate::rewrite::concurrent_thing();
        let o = my_crate::original::concurrent_thing();
        assert_eq!(r.observe(), o.observe());
    });
}
```

Caveat: both impls need their own `cfg(loom)` shims; this can be heavy. For one-off remediations, focus on the *failure mode* rather than full equivalence.

---

## Output golden artifacts

For "rendering"-style functions (formatters, code generators, serializers) where the bit-level output must remain stable, use golden tests:

```rust
#[test]
fn rewrite_matches_golden() {
    let out = my_crate::rewrite::render(&fixture());
    let golden = include_str!("../tests/golden/render_output.txt");
    assert_eq!(out, golden);
}
```

Generate the goldens from the original impl, then verify the rewrite matches. See `/testing-golden-artifacts` for the workflow.

---

## When NOT to do comparative testing

Comparative testing assumes the original is *correct except for UB*. If the original is also functionally buggy (the UB is symptomatic of a deeper logic error), comparative testing locks in the bug. Detect this case via:

- The original has known correctness bugs (file issues, comments saying "TODO: this is wrong")
- The remediation also changes observable behavior (e.g., the UB caused silent corruption; the fix returns an error)

In these cases, the remediation is *not* equivalence-preserving. Document explicitly in `phase8_remediation_plan.md`:

> **Equivalence:** This rewrite is NOT bit-identical to the original. The original returned silent garbage on overflow; the rewrite returns `Err(Overflow)`. Callers must be updated.

Add a "callers updated" sub-bead per call site that needs the new error-handling path.

---

## Phase 8 rubric mapping

| Equivalence evidence | Maps to rubric axis |
|---|---|
| Proptest passes 10⁴+ cases | Correctness margin 4 |
| Differential fuzz 1h+ clean | Correctness margin 4 |
| Criterion shows perf delta < 5% | Performance delta 3–4 |
| Criterion shows perf delta < 1% | Performance delta 4 |
| Diff is one function | Diff blast radius 4 |
| Diff is one module | Diff blast radius 3 |
| Diff is workspace-wide | Diff blast radius 1 |
| Golden-test stability | Reviewability 4 (deterministic outputs) |
| Loom-equivalent | Maintainability 4 (machine-checked) |

---

## Lifecycle

The `impl-original` feature is a *temporary* keep-original-around. After the remediation lands and 1–2 release cycles pass without regression, delete the `impl-original` code path. The `phase8_remediation_plan.md` should include a follow-up bead for this cleanup (with target version specified).

Keep the equivalence tests *forever* — they become regression tests for any future refactor of the same surface.
