# CLASSIFICATION-RUBRIC.md — (A) / (B) / (C) with Falsification Tests

> Misclassification is the cardinal sin. Read this file before classifying any site, and re-read it before every Phase 4 / Phase 6 pass.

The rubric is opinionated. The goal is to make classification **adversarially defensible** — every bucket has a falsification test that another reviewer can attack. If you can't write the justification in the required form, the site doesn't belong in that bucket.

This file IS the triangulated kernel of the skill per the `/operationalizing-expertise` Track A pattern. The marker-bounded section below is what `scripts/validate-corpus.py` and the orchestrator agents reference verbatim — do NOT edit between the markers without a corresponding skill-version bump.

<!-- KERNEL_START v1.0 unsafe-classification -->

---

## The Three Buckets

| Bucket | One-sentence definition | Cardinal failure mode |
|--------|--------------------------|-----------------------|
| **(A) STRICTLY_UNAVOIDABLE** | The language's type system cannot today express the invariant this `unsafe` upholds, AND no isomorphic safe formulation exists. | "Looks unavoidable" without an attacked falsification → technical debt cosplaying as physics. |
| **(B) PERF_ONLY** | A safe formulation exists and is correct; the `unsafe` is purely a measurable, profiled performance optimization. | Untested folklore — claimed perf with no `cargo bench` numbers. |
| **(C) REFACTORABLE** | A safe formulation exists, is correct, AND is plausibly isomorphic (same behavior, same perf within budget, same public API). | "Looks equivalent" without a property-based equivalence test → behavior drift on the failure paths. |

A site belongs in exactly ONE bucket. When in doubt between adjacent buckets, **default down**: (A)→(B), (B)→(C). The bias is toward "we can do better."

---

## (A) STRICTLY_UNAVOIDABLE

### Inclusion criteria

A site is (A) iff ALL of the following hold:

1. **No safe-Rust formulation exists today** that achieves the same goal with the same correctness and acceptable performance characteristics.
2. **The Rust language itself documents the invariant** as something the type system cannot express today (Rust Reference, Rustonomicon, or relevant RFC).
3. **Concrete safe alternatives have been considered and shown to fail**, with the failure traced to the cited language reference.

### Falsification test (mandatory write-up form)

Every (A) classification MUST include:

```
JUSTIFICATION

This site is (A) STRICTLY_UNAVOIDABLE because:
<one-sentence reason citing Rust Reference / RFC / nomicon section>

The following safe alternatives have been considered AND FAIL:

1. Alternative: <name + 1-sentence sketch>
   Why it fails: <specific technical reason, citing the language reference>

2. Alternative: <name + 1-sentence sketch>
   Why it fails: <specific technical reason, citing the language reference>

3. Alternative: <name + 1-sentence sketch>
   Why it fails: <specific technical reason, citing the language reference>

REVIEWER ATTACK SURFACE

The strongest plausible attack on this classification would be:
<one-paragraph steel-man of "this should be (B) or (C)">

The response to that attack:
<one-paragraph rebuttal>
```

If you cannot fill in three failing alternatives, or you cannot steel-man the attack and respond, **the site is not (A)**.

### Canonical (A) examples

These survive adversarial review in the exemplar repos. Detailed pattern entries in [00-CANONICAL-UNAVOIDABLE.md](../patterns/00-CANONICAL-UNAVOIDABLE.md).

| Pattern | Why unavoidable | Exemplar |
|---------|-----------------|----------|
| `extern "C"` FFI calls | The C ABI is outside Rust's type system; the safe wrapper IS the proof obligation | `frankenlibc::syscall::*` |
| Raw `libc::*` syscall wrappers | Same as above — syscalls have no safe representation in stable Rust today | `frankenlibc::io::*` |
| `mmap` / `io_uring` / `epoll(EPOLLET)` setup | These return raw pointers / fds with kernel-side aliasing the borrow checker can't model | `asupersync::io::ring` |
| `core::hint::unreachable_unchecked` for verified exhaustiveness | Required to communicate to the optimizer; safe `match _ => unreachable!()` loses the LLVM hint | `rich_rust::lexer::dispatch` |
| `GlobalAlloc::alloc` / `dealloc` impls | The allocator itself can't allocate to allocate; circular dependency | `frankenfs::alloc::SlabAllocator` |
| `Pin::new_unchecked` for self-referential async state machines | Self-references aren't expressible in safe Rust | `mcp_agent_mail_rust::ws::stream` |
| `intrinsics::atomic_load_unsynchronized` | Some atomic operations are not surfaced through safe `core::sync::atomic` | `franken_engine::sched::worker_park` |

### Common (A) misclassifications to watch for

- **"It's faster"** — that's (B), not (A). Speed without a soundness wall is never (A).
- **"All the popular crates do it this way"** — popularity is not a soundness proof. Check whether the popular crate also has an unsafe (it usually does — they made the same trade-off you're about to make, in (B)).
- **"It would be complex to refactor"** — complexity is not the same as impossibility. (C) is "isomorphic-or-nearly-so safe rewrite plausible," not "easy to write."
- **"The SAFETY comment says it's necessary"** — the SAFETY comment was written by someone who may have been wrong, or correct at the time and wrong now. Re-derive from first principles.

---

## (B) PERF_ONLY

### Inclusion criteria

A site is (B) iff:

1. **A safe formulation exists** and is known to be correct.
2. **There is a measurable, profiled, regression-tested performance gap** between the safe and unsafe formulations on the project's canonical benchmark suite.
3. **The performance gap is large enough** to exceed the user's perf budget (default 5%) when expressed as an end-to-end metric the project actually cares about (not a microbench that doesn't propagate to wall-clock).

### Mandatory artifacts per (B) site

Every (B) site MUST get:

1. **Safe-only feature implementation.** A Cargo feature (default name: `safe-only` or `no-unsafe`) that, when enabled, swaps in the memory-safe alternative. The default feature set keeps the perf path.
2. **Measured before/after.** All three:
   - `cargo bench` (criterion microbench)
   - `hyperfine` end-to-end timing on a representative workload
   - `cargo flamegraph` diff before vs after
   Numbers go in `audit/plans/site-<id>.md` AND the bead's acceptance criteria.
3. **CI matrix entry.** Add `--features safe-only` as a new matrix axis to `.github/workflows/`. The `safe-only` build runs the same test suite under both miri and the regular runner.
4. **Graduation rule.** If the measured perf delta is within the user's budget (no measurable regression on the canonical workload), the site **graduates to (C)** — keep the safe form, delete the unsafe. Document the graduation in `audit/plans/site-<id>.md § Graduation history`.

### Falsification test (mandatory write-up form)

```
PERF JUSTIFICATION

Hot path: <which user-visible operation does this site live in?>
Workload: <which benchmark / hyperfine run measures it?>

Numbers (unsafe / safe / delta):
- criterion mean: <X ns> / <Y ns> / <Δ%>
- criterion p99:  <X ns> / <Y ns> / <Δ%>
- hyperfine mean: <X ms> / <Y ms> / <Δ%>
- flamegraph: <unsafe-path-percent> / <safe-path-percent>

Budget check: user budget is <N%>; measured delta is <M%>; <within / outside> budget.

If WITHIN budget: site graduates to (C). Refactor and delete the unsafe.
If OUTSIDE budget: site is (B); ship safe-only feature flag + CI matrix.

REVIEWER ATTACK SURFACE

The strongest plausible "this perf claim is folklore" attack:
<one-paragraph steel-man>

The response:
<one-paragraph rebuttal with the actual numbers>
```

### Canonical (B) examples

| Pattern | Safe alternative | Where (B) is justified |
|---------|------------------|------------------------|
| SIMD intrinsics in `std::arch` | `std::simd` / `wide` / autovec-friendly loops | When LLVM can't autovectorize AND `std::simd` lacks the operation OR is 1.5–10× slower on target |
| `slice::get_unchecked` in a tight inner loop | `slice[i]` with bounds-check | When profiler shows the bounds-check dominates AND the loop is on the critical path |
| Hand-rolled CAS loops with `Ordering::Relaxed` | `arc-swap` / `crossbeam` | When the contention pattern is too narrow for the general-purpose data structure AND bench shows a measurable delta |
| `Box::from_raw` round-trips in an arena | `bumpalo::Bump` | Almost never — `bumpalo` is usually equivalent. Most (B) arena claims graduate to (C) on measurement. |

### Common (B) misclassifications

- **"Faster" without a benchmark** — that's folklore, not (B). Make it (C) by default until proven.
- **Microbench delta with no end-to-end propagation** — a 20% faster `parse()` that fixed 0.01% of wall-clock is not (B). Use hyperfine on the binary, not just criterion.
- **Cross-target untested** — `std::simd` may be slower on aarch64 even when it's faster on x86_64-v3. Bench BOTH targets the project ships before declaring (B).
- **The unsafe is doing more than perf** — sometimes `slice::get_unchecked` is reachable from `pub` and the caller-side proof obligation is non-trivial. That's a hybrid (A)+(B); see [50-SEND-SYNC-IMPLS.md](../patterns/50-SEND-SYNC-IMPLS.md) §reachable-perf for the protocol.

---

## (C) REFACTORABLE

### Inclusion criteria

A site is (C) iff:

1. **A safe formulation exists** and is plausibly isomorphic to the unsafe one (same behavior, same public API, same perf within budget).
2. **The rewrite can be drafted as full code** (not pseudocode).
3. **Behavioral equivalence can be proved** via property-based + metamorphic + miri + (where applicable) loom.

### Mandatory artifacts per (C) site

Every (C) site MUST get:

1. **Full safe replacement code.** Pasted into the plan. No "TODO: write the safe version."
2. **Property-based equivalence test.** `proptest` or `quickcheck` generating inputs that exercise the full state space, INCLUDING the failure modes the old unsafe code handled.
3. **Metamorphic test where applicable** (per `/testing-metamorphic`). Form: `forall x, f_safe(transform(x)) == transform(f_safe(x))` AND the same holds for `f_unsafe`.
4. **`loom` model test if concurrency-touching.** All interleavings the loom model can exhaust.
5. **`miri` run.** `cargo +nightly miri test -- <rewrite_module>` clean.
6. **Risk + API-surface estimate.** Low / Medium / High. If the public API changes, document the migration path for downstream users.

### Falsification test (mandatory write-up form)

```
EQUIVALENCE CLAIM

The proposed safe rewrite is behaviorally equivalent to the unsafe original under:
- All inputs that produce a value: <list invariants the property test enforces>
- All inputs that panic: <list the panic conditions the original had; safe version must match>
- All inputs that error: <list error variants the original returned>

PROOF

- Property test: <path-to-test>
- Metamorphic test: <path-to-test>
- Loom model:    <path-to-test or N/A>
- Miri command:  <exact cargo +nightly miri invocation>
- Perf bench:    <within budget? yes/no with numbers>

REVIEWER ATTACK SURFACE

The strongest plausible "your safe rewrite differs on input X" attack:
<one-paragraph steel-man, with the specific input X>

The response:
<one-paragraph rebuttal showing the property test handles X correctly>
```

### Canonical (C) examples

Detailed pattern entries in [10-POINTER-MIGRATIONS.md](../patterns/10-POINTER-MIGRATIONS.md), [40-MACRO-GENERATED-UNSAFE.md](../patterns/40-MACRO-GENERATED-UNSAFE.md), [70-UNINIT-AND-TRANSMUTE.md](../patterns/70-UNINIT-AND-TRANSMUTE.md).

| Pattern | Safe rewrite |
|---------|--------------|
| Raw pointer → `NonNull` → `Pin<&mut T>` → fully owned `Box<T>` / `Vec<T>` | Standard owned types |
| `mem::transmute<&[u8], &[u32]>` for endian read | `zerocopy::FromBytes` / `bytemuck::cast_slice` |
| Hand-written `MaybeUninit::assume_init` after manual field writes | `std::array::from_fn` / `Vec::from_iter` / `init_array!` macro |
| `unsafe impl Send/Sync for MyStruct` where every field is `Send/Sync` | Delete the impl; the auto-derive will provide it |
| Macro-generated `unsafe { transmute(...) }` in custom derive | Switch to `zerocopy-derive` / `bytemuck-derive` |
| Custom `UnsafeCell` interior mutability where `Cell` / `RefCell` / `OnceCell` suffices | Replace |

### Common (C) misclassifications

- **"Looks equivalent" without property tests** — equivalence is a proof obligation, not a guess. Reject the plan until the property test exists.
- **"The safe version is one-liner equivalent" (using a crate)** — confirm the crate is actually a dep, isn't yanked, and matches the perf budget. Don't pull a 2MB crate to remove three lines of unsafe.
- **API-changing rewrite** that doesn't document the migration path — even adding a generic parameter is a breaking change. Document it.
- **Allocator identity change** — `Vec` instead of `bumpalo::Vec` is NOT isomorphic if the original was in an arena. See [00-CANONICAL-UNAVOIDABLE.md § allocator](../patterns/00-CANONICAL-UNAVOIDABLE.md#allocator-identity).

---

## Iteration discipline

### Phase 4 — same-context classification

Pass 1: the agent that did the per-site write-up classifies its own sites.

Pass 2..N: a fresh classifier agent re-classifies without seeing the prior decision. (See `subagents/classifier.md`.)

Convergence: two consecutive passes where fewer than 5% of sites flip bucket AND zero (A)→(C) flips occur. Once converged, Phase 4 exits.

### Phase 6 — adversarial reclassification

A different agent (preferably a different model — Codex or Gemini if available via `/multi-model-triangulation`) reads every classification cold and tries to defeat it:

- For each (A): propose a safe alternative and steel-man it. If it survives the original (A) write-up's falsification, reclassify.
- For each (B): hunt for a missed safe pattern. If found, run the perf comparison; if within budget, graduate to (C).
- For each (C): construct an input the rewrite would handle differently from the original. If found, refine the rewrite OR reclassify.

Convergence: same rule as Phase 4. Once converged, Phase 6 exits.

### What "marginal" means operationally

```
marginal = (sites_flipped / total_sites) < 0.05
       AND  count(A_to_C_flips) == 0
       AND  count(B_to_A_promotions) == 0   # never promote up; bias is downward
```

A→B and B→C demotions are encouraged at any time (they mean we found something to refactor). C→B promotions only happen if a property test fails AND no fix is available within budget. C→A promotions only happen if Phase 6 surfaces a soundness wall the original analyst missed; they're rare.

---

## The Decision Tree (Quick Reference)

```
                       Is this `unsafe`?
                              │
                              ▼
              Does a safe formulation exist today?
                ┌──────── NO ──────────┐    YES
                │                      ▼     │
                │            Are alternatives ▼
                │             demonstrably fail?     Can you draft full safe rewrite code?
                │            (3 alternatives in            │           │
                │             write-up form)               │           ▼
                │              │       │                  YES         NO (don't know yet)
                │             YES     NO                   │           │
                │              │       │                   ▼           ▼
                │              ▼       ▼          Does property test ▼  Refine; treat as (B)
                │           (A)      RECLASSIFY    show equivalence?   until equivalence proved
                │           STRICTLY  AS (B)            │
                │           UNAVOID                    YES NO
                │                                       │   │
                │                                       ▼   ▼
                │                                     (C)  (B) PERF_ONLY
                │                                          (or measure-and-graduate)
                │
                ▼
        Is the perf delta measurable + over budget?
              │
              ▼
            YES  NO
             │    │
             ▼    ▼
            (B)  (C) (graduated)
```

---

## Acceptance signal per bucket

When the classification passes muster, the site can move to Phase 5:

- **(A):** justification + 3 failed alternatives + steel-man attack + rebuttal, all in `site-<id>.md § JUSTIFICATION`.
- **(B):** all three benchmarks present + budget check + CI matrix entry sketched.
- **(C):** full safe code + property test + miri command + risk estimate, in `audit/plans/site-<id>.md`.

If a site is missing the required artifact for its bucket, it does NOT exit Phase 4 / 6 — the classifier reopens it.

<!-- KERNEL_END v1.0 unsafe-classification -->

---

## Hybrid sites — multiple bucket characteristics

Some sites carry characteristics from more than one bucket — most commonly an (A) FFI shim whose interior uses a (B) perf optimization like `get_unchecked`. The single-bucket rule still applies (classify by the **primary** unsafe-justification), but the secondary characteristic may require its own deliverable.

See [HYBRID-CLASSIFICATIONS.md](HYBRID-CLASSIFICATIONS.md) for the protocol — when it applies, how to write the classification file, and the worked examples (H-1 through H-3). Cited briefly here so the rubric's single-bucket rule is no longer ambiguous when reviewers encounter real-world hybrids.

---

## Kernel-version log

| Version | Date | Change |
|---------|------|--------|
| v1.0 | 2026-05-13 | Initial triangulated kernel; (A) / (B) / (C) with falsification tests. |

Future kernel revisions should:
- Bump the version.
- Add an entry above with the change rationale.
- Re-validate every cited `[E-NNN]` in the corpus.
- Re-validate every operator that depends on the kernel's buckets.

The validator `scripts/validate-corpus.py` checks the markers exist; the version log is a sanity gate for re-validation.
