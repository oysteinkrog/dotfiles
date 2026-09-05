# FORMAL-VERIFICATION.md — kani, prusti, creusot, and friends

Beyond miri (which finds UB on inputs you exercise) lies formal verification (which proves UB cannot occur on ANY input within a model). For sites with high-blast-radius soundness obligations, formal verification is worth the cost.

This file is the per-tool decision guide and integration plan.

---

## When formal verification is worth it

| Cost | Benefit |
|------|---------|
| **Time.** kani proofs take minutes-to-hours per harness. prusti's annotations are verbose. | **Coverage.** Miri exercises inputs you generate; kani proves the property over all inputs within the bounded model. |
| **Expertise.** Writing proofs requires understanding the tool's semantics. | **Confidence.** A passing proof is a much stronger guarantee than a passing test. |
| **Maintenance.** Proofs break as code evolves; the proof has to be re-verified. | **Documentation.** A proof IS executable documentation of the invariant. |

**Use when:**
- The site is on the soundness surface AND the proof obligation is non-trivial (e.g., a hand-rolled hash table that promises uniqueness; an arena allocator that promises non-aliasing).
- A regression in this site would be a CVE-level event.
- The user has explicit budget for the verification effort.

**Skip when:**
- The site's blast radius is low (deleted on next refactor anyway).
- The proof would be larger than the code under proof (the proof becomes the bug source).
- The site is unstable (still evolving rapidly; proofs don't pay back yet).

---

## kani — bounded model checker

**What it does.** Translates a Rust function into a CBMC verification problem. CBMC explores all paths within bounded loop iterations and integer ranges, looking for UB.

**Install.**

```bash
cargo install --locked kani-verifier
cargo kani setup
```

**Authoring a proof.**

```rust
#[cfg(kani)]
#[kani::proof]
fn my_invariant() {
    let x: u32 = kani::any();          // symbolic input
    kani::assume(x < 1000);            // bounded
    let result = my_safe_rewrite(x);
    assert!(invariant_holds(result));
}
```

**Run.**

```bash
cargo kani --harness my_invariant
```

**Audit integration.**

- For (C) rewrites where the equivalence claim is testable via a property test + kani proof, write BOTH.
- The plan's `bead acceptance criteria` includes the kani invocation alongside the proptest one.
- `scripts/run-kani.sh` runs all configured proofs as part of the verification harness.

**Limitations.**

- Loop unrolling is bounded; you must set `--unwind <N>` for non-trivial loops.
- Heap operations are modeled but expensive; large `Vec` interactions blow up.
- No FFI support; can't model `extern "C"` calls.
- Some unsafe patterns (raw `transmute` between non-Pod types) confuse the model.

---

## prusti — refinement-type-based deductive verification

**What it does.** Annotates functions with pre/post conditions and invariants; a Coq-based prover discharges the obligations.

**Install.**

```bash
# See https://github.com/viperproject/prusti-dev
# Requires a JVM + the Prusti binary release.
```

**Authoring.**

```rust
use prusti_contracts::*;

#[requires(x < 1000)]
#[ensures(result == x * 2)]
fn double(x: u32) -> u32 {
    x * 2
}
```

**When to use.**

- The invariant is expressible as a precise pre/post condition.
- The function is pure (no side effects).
- The team is willing to maintain the annotations.

**Limitations.**

- Steeper learning curve than kani.
- Less ergonomic for the "explore-all-inputs" style; better at "this function preserves invariant X."
- Active development; some patterns aren't yet supported.

---

## creusot — refinement-type-based deductive verification (via Why3)

Similar to prusti but uses Why3 as the backend. Slightly different annotation syntax, similar audience.

```rust
use creusot_contracts::*;

#[requires(x@ < 1000)]
#[ensures(result@ == x@ * 2)]
fn double(x: u32) -> u32 {
    x * 2
}
```

Pick prusti OR creusot per the team's tooling preference; both cover similar use cases.

---

## flux — refinement types via clippy-style lints

[Flux](https://flux-rs.github.io/) is a newer entrant — refinement types as a lint plug-in. Lower ceremony than prusti/creusot:

```rust
#[flux::sig(fn(n: i32{n >= 0}) -> i32{r: r == n + 1})]
fn inc(n: i32) -> i32 {
    n + 1
}
```

The annotations are checked at compile time. Less coverage than full deductive verification but much lower friction.

**Use when** you want lightweight refinement-type checking on hot-path functions without committing to a heavy framework.

---

## A combined verification flow

For sites that benefit from formal verification:

```
1. Write the (C) rewrite.
2. Write a proptest equivalence test (always).
3. Write a kani proof for the invariant the unsafe was upholding.
4. (Optional) Write prusti/creusot annotations for fine-grained pre/post.
5. Run miri (default + strict-provenance + tree-borrows) for UB.
6. Run loom (if concurrency).
7. Run cargo-fuzz (if widened public surface).
8. Run kani for the symbolic proof.
9. (Optional) Run prusti/creusot for the deductive proof.
10. If all pass: site is verified.
```

The audit summary line for a verified site:

```
site-NNNN: (C); verified via miri + loom + fuzz + kani + prusti.
```

That's a much stronger claim than "tests passed."

---

## Decision tree per site

```
Is this site on the soundness surface?
├─ No → skip formal verification; miri + proptest is enough.
└─ Yes → continue.

Is the blast radius high (CVE-level if it regressed)?
├─ No → kani is optional; miri + proptest + loom is the bar.
└─ Yes → continue.

Can the invariant be expressed as a kani-checkable property?
├─ No → write a prusti/creusot annotation (deductive proof).
├─ Yes → write a kani proof.
```

---

## Per-tool integration in verify.sh

The composite harness ([90-OPERATIONS.md § verify.sh](../patterns/90-OPERATIONS.md#verifysh)) includes a kani step if the project has `[kani]` proofs:

```bash
echo "==> [10/9+] kani (formal verification)"
if [ -d kani-proofs ] || grep -q '#\[kani::proof\]' src/**/*.rs 2>/dev/null; then
  cargo kani
else
  echo "    (no kani proofs configured; skipping)"
fi
```

prusti / creusot are not yet in the canonical harness; they're per-project opt-ins (some teams maintain a separate `verify-with-prusti.sh`).

---

## Acceptance signal

A site is formally verified when:

1. The site is on the soundness surface.
2. The blast radius justifies the cost.
3. A kani proof (and/or prusti/creusot annotation) exists at `proofs/<site_id>.rs`.
4. The proof PASSES on the rewrite AND FAILS on a deliberately-broken version (sanity check; mutate the rewrite to introduce a bug; the proof should catch it).
5. The proof is referenced in `audit/plans/site-<id>.md § Bead acceptance criteria` as a required gate.
6. The harness includes the proof in `verify.sh`.

If any of these is missing, the site is NOT formally verified — it's miri-tested. That's acceptable for most sites; for the highest-stakes ones, push for formal verification.
