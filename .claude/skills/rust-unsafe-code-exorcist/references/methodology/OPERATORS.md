# OPERATORS.md — Cognitive Moves for Unsafe Audit

Operators are composable thinking moves. Apply them to any `unsafe` site, FFI surface, or proposed safe rewrite. Each card has: **trigger**, **failure modes**, **prompt module**, **fix section**.

Phase 4 classifier and Phase 6 adversarial reclassifier both walk down this list per site, in the [Composition cheat-sheet](#composition-cheat-sheet) order.

---

## ⊙ Invariant-Locator

**Trigger.** Any `unsafe` block, `unsafe fn`, or `unsafe impl`.

**Question.** What soundness invariant is this `unsafe` upholding, and who enforces it?

**Failure modes.**
- "It's just unsafe" — refuses to name an invariant. Cannot classify until you do.
- "The SAFETY comment says X" — copies the comment without verifying it against current code.
- Names the invariant but cannot trace who enforces it (caller? trait bound? type invariant?).

**Prompt module.**
> Read this `unsafe` block. Name the precise soundness invariant it upholds in the form: "The block is sound IFF [condition]." Then trace the call graph to find every code path that could violate [condition]. Cite specific line numbers. If you cannot name the invariant, the site fails this operator.

**Fix section.** [CLASSIFICATION-RUBRIC.md § Invariant-discovery](CLASSIFICATION-RUBRIC.md#invariant-locator)

---

## ⊕ Reachability-From-Safe

**Trigger.** The unsafe site is in a function (or transitively reachable from one) that is `pub` or otherwise exposed outside the unsafe boundary's enforcing module.

**Question.** Is this `unsafe` reachable from a safe public API? If so, the invariant must be enforced before the unsafe runs.

**Failure modes.**
- The invariant is enforced by the caller but the public API doesn't require the caller to know it.
- Invariant relies on a private field's state, but a `pub` method allows mutation that breaks it.
- The unsafe is sound only because of an implicit type invariant the safe public API can violate (e.g., constructing the type via `Default::default()` skips the invariant-establishing constructor).

**Prompt module.**
> Trace the call graph from every `pub` function in this crate to this `unsafe` block. For each path, list the invariant the `unsafe` requires AND name the function on the path that establishes it. If any path reaches the unsafe without an enforcing function, the public API is unsound.

**Fix section.** [50-SEND-SYNC-IMPLS.md](../patterns/50-SEND-SYNC-IMPLS.md), [80-PIN-PROJECTIONS.md](../patterns/80-PIN-PROJECTIONS.md)

---

## ⊗ Falsifiable-Justification

**Trigger.** Any site being classified as (A) STRICTLY_UNAVOIDABLE.

**Question.** Have I stated, in a form a reviewer can attack, WHY a safe alternative fails?

**Failure modes.**
- "Performance" used as the (A) reason (that's (B)).
- "Idiomatic" or "everyone does it this way" — popularity is not soundness.
- "Looks impossible" without three concrete failed alternatives.

**Prompt module.**
> If you are about to classify this site as (A): write the JUSTIFICATION block per [CLASSIFICATION-RUBRIC.md § (A) STRICTLY_UNAVOIDABLE](CLASSIFICATION-RUBRIC.md#a-strictly_unavoidable). You MUST name at least three safe alternatives and explain why each fails, citing the Rust Reference / nomicon / RFC. If you cannot do this, the site is NOT (A).

**Fix section.** [CLASSIFICATION-RUBRIC.md § (A) falsification test](CLASSIFICATION-RUBRIC.md#falsification-test-mandatory-write-up-form)

---

## ⌖ Macro-X-Ray

**Trigger.** The crate uses `#[derive(...)]`, custom macros, `macro_rules!`, or pulls in `*-derive` deps.

**Question.** Does `cargo expand` reveal `unsafe` inside macro output that the source code never shows?

**Failure modes.**
- Audit only looks at source text and misses macro-generated `unsafe`.
- Audit looks at expand output but treats each expansion as a separate site instead of clustering by macro source.
- The macro generates `unsafe` differently per type — site count is wrong.

**Prompt module.**
> Run `cargo expand --crate <crate-name>` and save the output as `<audit-dir>/phase1/<crate>__expand.rs`. Search for `unsafe` in the expanded output. For every hit that doesn't have a corresponding source-text site, add an inventory row with `macro_origin: true` and `macro_origin_path: <expand-path>:<line>`. Cluster by the macro source (e.g., `zerocopy-derive::FromBytes`) when proposing refactors.

**Fix section.** [40-MACRO-GENERATED-UNSAFE.md](../patterns/40-MACRO-GENERATED-UNSAFE.md)

---

## ⏱ Profile-Or-It-Didn't-Happen

**Trigger.** A site is classified (or proposed to be classified) as (B) PERF_ONLY.

**Question.** Do I have `cargo bench` + `hyperfine` + flamegraph numbers showing the perf delta, or is this folklore?

**Failure modes.**
- "Faster" without a measurement.
- Microbench delta that doesn't propagate to wall-clock.
- Untested on every target the project ships (e.g., x86_64 benched but aarch64 ignored).

**Prompt module.**
> Before classifying as (B), produce the three artifacts: (1) `cargo bench` mean + p99 on the canonical benchmark suite, (2) `hyperfine` end-to-end timing on a representative workload, (3) `cargo flamegraph` diff showing the unsafe-path % vs safe-path %. Paste numbers into `audit/plans/site-<id>.md § PERF JUSTIFICATION`. If no measurable regression on the canonical workload, graduate to (C).

**Fix section.** [20-SIMD-AND-PERF.md § Measurement protocol](../patterns/20-SIMD-AND-PERF.md)

---

## 🔒 Panic-In-Drop-Trace

**Trigger.** Any `unsafe` that touches a resource with a `Drop` impl (file, fd, socket, mmap, allocation).

**Question.** If a panic unwinds through this unsafe, what state does it leave the world in?

**Failure modes.**
- `Drop` runs during unwind and itself panics → process abort.
- The unsafe assumes a destructor will release a resource, but the destructor runs in an order that violates the invariant.
- Double-drop because the unsafe set up a manual destructor that races with the type's `Drop`.

**Prompt module.**
> Trace what happens if `panic!()` is called between every two operations in this `unsafe` block. Specifically: (1) is any temporary allocated, mmapped, or fd-opened that wouldn't be released by the destructor? (2) is the type's `Drop` impl sound IF the constructor didn't finish? (3) does any held lock leak on unwind? Cite the specific safety hazard.

**Fix section.** [00-CANONICAL-UNAVOIDABLE.md § unwinding](../patterns/00-CANONICAL-UNAVOIDABLE.md#unwinding)

---

## 🔁 Async-Cancellation-Trace

**Trigger.** Any `unsafe` reachable from an `async fn` or inside a `Pin`-projected state machine.

**Question.** If the future containing this unsafe is dropped at an await point, is every invariant restored?

**Failure modes.**
- The unsafe sets up state that's restored only on the success path; cancellation leaks.
- A locked mutex's guard is held across an await; cancellation between unsafe and unlock is UB-equivalent at the deadlock level.
- A `Pin::new_unchecked` future is moved after pinning by a cancellation handler.

**Prompt module.**
> Identify every `.await` reachable from this unsafe in the call graph. For each, trace what happens if the future is dropped at that point. Specifically: (1) does any acquired resource leak? (2) does any temporary `Pin`ned-then-moved type violate pin's "never move" invariant? (3) does any lock guard survive past the cancellation?

**Fix section.** [80-PIN-PROJECTIONS.md § Async cancellation](../patterns/80-PIN-PROJECTIONS.md)

---

## ⚖ Send-Sync-Audit

**Trigger.** `unsafe impl Send for T` or `unsafe impl Sync for T`.

**Question.** Does this impl quietly assume an invariant enforced elsewhere?

**Failure modes.**
- The impl assumes the field types are all `Send`/`Sync`, but a later refactor adds an `Rc<...>` field — now the impl is unsound.
- The impl exists because of a raw pointer field where the pointer is treated as "always thread-local"; removing the impl requires proving the pointer never escapes.
- The auto-derive would have provided the impl after a small refactor — the explicit `unsafe impl` is dead weight.

**Prompt module.**
> List every field of `T`. For each, state whether it is `Send`/`Sync` by auto-derive. If any field is NOT `Send`/`Sync`, name the invariant the impl is asserting (e.g., "the `*const u8` is only used on the thread that constructed `T`"). Then check: would the auto-derive cover this after a small field-level refactor (e.g., wrap the raw pointer in `SendPtr<T>(*const T)` where `SendPtr` is a newtype with audited `Send` impl)? If so, the explicit unsafe impl is (C) — refactor it away.

**Fix section.** [50-SEND-SYNC-IMPLS.md](../patterns/50-SEND-SYNC-IMPLS.md)

---

## 🪟 FFI-Boundary-Contract

**Trigger.** `extern "C"` block, FFI-bound `unsafe fn`, or any call into `libc` / `windows-sys` / `core-foundation` / similar.

**Question.** What does the C side promise? What does the Rust side promise? Is there a written contract?

**Failure modes.**
- Rust assumes a null-terminated string but C returns a length-prefixed buffer.
- Rust assumes the FFI returns an owned pointer the caller must `free`; C actually returned a static.
- Endianness, calling convention, struct padding mismatches between Rust `#[repr(C)]` and C's actual layout.

**Prompt module.**
> Produce the FFI boundary contract per [60-FFI-PATTERNS.md § contract template](../patterns/60-FFI-PATTERNS.md). For each `extern "C" fn`, list: (1) ownership of every pointer in/out, (2) lifetime of every pointer relative to the call, (3) endianness, padding, and ABI assumptions, (4) what errors the C side can return and how they're conveyed (errno? out-param? sentinel?), (5) whether the C side can panic / abort / longjmp, and what that means for Rust unwinding.

**Fix section.** [60-FFI-PATTERNS.md](../patterns/60-FFI-PATTERNS.md)

---

## 🗄 Init-Order-Discipline

**Trigger.** `MaybeUninit::assume_init*`, `mem::uninitialized` (deprecated), or manual partial-initialization patterns.

**Question.** Does `assume_init*` run only after every field has been written?

**Failure modes.**
- Field initialization order depends on a loop that can break early — `assume_init` runs on partial init.
- The struct contains a `Drop` field that gets initialized first; if a later init step panics, the partially-init struct's `Drop` runs on uninit fields.
- `assume_init_read` followed by a subsequent `assume_init` on the same `MaybeUninit` (double-read).

**Prompt module.**
> Trace every code path leading to `assume_init*`. For each, confirm: (1) every field of the target type is written exactly once before `assume_init` runs, (2) no early-return / panic / `?` can leave the `MaybeUninit` partially populated, (3) if any field's `Drop` would run on partial init, the panic-in-the-middle case is handled (typically via `ManuallyDrop` or a guard pattern).

**Fix section.** [70-UNINIT-AND-TRANSMUTE.md](../patterns/70-UNINIT-AND-TRANSMUTE.md)

---

## ⊞ Loom-Reachable-Interleaving

**Trigger.** Any `unsafe` in concurrent code (atomics, lock-free, manual `Send`/`Sync`).

**Question.** Have I exhausted the interleavings under `loom` that could violate the invariant?

**Failure modes.**
- The `loom` test exists but only models the success path.
- The `loom` test models all paths but the test budget (`LOOM_MAX_BRANCHES`) is too small for the actual state space.
- The implementation uses `unsafe` to bypass loom's atomic instrumentation — invisible to the model.

**Prompt module.**
> Write a `loom` model that exercises every public method of the type from at least 2 threads. Run with `RUSTFLAGS="--cfg loom" cargo test --features loom_concurrency_tests --release`. If the test completes within the default budget AND no panic is produced AND no UB is reported, the interleavings are exhausted. If the budget is hit, expand explicitly via `loom::model::Builder::preemption_bound`.

**Fix section.** [TOOLCHAIN-RUNBOOK.md § loom](TOOLCHAIN-RUNBOOK.md#loom)

---

## 🧪 Equivalence-Witness

**Trigger.** Any (C) classification proposing a safe rewrite.

**Question.** Do I have a property-based test where the unsafe original and the safe rewrite produce identical output on the same input?

**Failure modes.**
- The test exists but doesn't cover the failure path (panics, errors).
- The unsafe and safe versions live in different modules with different visibility; the property test only exercises one.
- The property test passes because both versions have the SAME bug.

**Prompt module.**
> Author a `proptest` or `quickcheck` test in `tests/equivalence_<site_id>.rs` that, for arbitrary inputs, asserts `f_unsafe(x) == f_safe(x)` AND `panics_of_f_unsafe(x) == panics_of_f_safe(x)` AND `errors_of_f_unsafe(x) == errors_of_f_safe(x)`. Run for at least 10,000 cases under `cargo test --release`. Then run under `cargo +nightly miri test --features miri_safe_test` to detect UB hidden behind the original `unsafe`.

**Fix section.** [10-POINTER-MIGRATIONS.md § Equivalence proof](../patterns/10-POINTER-MIGRATIONS.md)

---

## 🔐 Soundness-Surface-Marker

**Trigger.** Phase 3 synthesis.

**Question.** Is this `unsafe` reachable from `pub`? If yes, it lives on the project's soundness surface.

**Failure modes.**
- Site marked private but actually reachable via `pub use` re-export.
- Site reachable via trait impl whose trait is `pub`.
- Site reachable via type alias used in `pub` signatures.

**Prompt module.**
> Use rustdoc JSON to walk every `pub` item. For each, list the unsafe sites it transitively reaches (via the inventory's call-graph edges). Sites with at least one such caller are on the soundness surface. Sites NOT on the soundness surface have less stringent requirements but still need full classification.

**Fix section.** [PHASES.md § Phase 3](PHASES.md#phase-3--synthesize)

---

## 📐 Allocator-Identity

**Trigger.** A proposed (C) rewrite replaces a manually-allocated type (arena, bump, slab) with a standard owned type (`Vec`, `Box`, `String`).

**Question.** Did the proposed safe rewrite quietly change the allocator?

**Failure modes.**
- Original used `bumpalo::Vec` in a per-request arena; rewrite uses `std::vec::Vec` — silent global allocator pressure.
- Original used a `Slab<T>` for cache locality; rewrite uses `HashMap<usize, T>` — silent O(1)→amortized-O(1) with cache misses.
- Original lived in shared memory (mmap); rewrite is heap-allocated.

**Prompt module.**
> Before approving a (C) rewrite, identify the allocator used by the original. If it is NOT the global allocator (`std::alloc::System` or `mimalloc` etc.), the rewrite must preserve that allocator identity. Use `bumpalo::Vec` / `bumpalo::collections::Vec`, `slab::Slab`, `typed-arena::Arena`, or similar. Document the allocator choice in the plan; have benches confirm cache-locality and allocation-pressure are preserved.

**Fix section.** [00-CANONICAL-UNAVOIDABLE.md § allocator-identity](../patterns/00-CANONICAL-UNAVOIDABLE.md#allocator-identity)

---

## 🪞 Bidirectional-Geiger

**Trigger.** Before and after any refactor pass.

**Question.** Has `cargo +nightly geiger` delta vs baseline been computed? Does it match the planned change?

**Failure modes.**
- Geiger count went DOWN but a new unsafe was added elsewhere (net zero — refactor moved unsafe instead of removing it).
- Geiger count went UP because the refactor wrapped existing unsafe in a thicker abstraction that itself uses unsafe.
- Geiger count went DOWN by replacing unsafe with `expect()` panics — a different kind of bad.

**Prompt module.**
> Run `cargo +nightly geiger --json > <audit-dir>/geiger-after.json`. Diff against `<audit-dir>/phase1/cargo-geiger.txt`. Confirm: (1) the count delta matches the planned (C) refactor count, (2) no new unsafe was added in unexpected files, (3) the perf-path unsafe count under `--features safe-only` is zero.

**Fix section.** [TOOLCHAIN-RUNBOOK.md § geiger](TOOLCHAIN-RUNBOOK.md#geiger)

---

## ⚑ Pre-Existing-UB-Isolator

**Trigger.** Phase 7 / Phase 9 turns up miri / fuzz / loom findings in code outside the refactor scope.

**Question.** Did the harness uncover UB that wasn't in scope? File it as a separate `pre-existing-ub` bead — never fold it into the refactor plan.

**Failure modes.**
- Refactor PR "fixes" pre-existing UB silently; later regression confuses bisection.
- Pre-existing UB is mentioned in the refactor PR description but not filed as a separate issue → loses tracking.
- Refactor scope is widened to "fix" the UB, blowing past the user's authorized scope.

**Prompt module.**
> For every miri / fuzz / loom finding, classify: IN-SCOPE (the refactor introduced or modified the site) or OUT-OF-SCOPE (the finding is in code untouched by the refactor). For each OUT-OF-SCOPE finding: (1) file a `pre-existing-ub-N` bead with full reproduction steps, (2) DO NOT modify the code as part of the current refactor pass, (3) note the finding in `audit/synthesis/pre-existing-ub.md`.

**Fix section.** [90-OPERATIONS.md § Pre-existing-UB protocol](../patterns/90-OPERATIONS.md#pre-existing-ub-protocol)

---

## ⤴ Drop-Glue-Sanity

**Trigger.** After a (C) rewrite is drafted; during Phase 7 fresh-eyes.

**Question.** After the rewrite, does every owned resource still run its destructor on every exit path (panic, return, await drop)?

**Failure modes.**
- Rewrite replaces `Box::into_raw(b); /* later */ Box::from_raw(p);` with raw `&mut *b` — `b` no longer owns; original release path is lost.
- Rewrite uses `mem::forget` to skip a destructor; needs justification.
- Rewrite holds a `MutexGuard` across an early return without releasing.

**Prompt module.**
> For every owned resource in the rewrite, trace its destructor invocation on: (1) the success path, (2) every `return` early exit, (3) every `?` propagation, (4) every `panic!` reachable from the function, (5) every `.await` drop (async cancellation). Confirm each invocation happens AND happens in the correct order. Cite line numbers.

**Fix section.** [00-CANONICAL-UNAVOIDABLE.md § unwinding](../patterns/00-CANONICAL-UNAVOIDABLE.md#unwinding)

---

## ⊟ Strict-Provenance-Witness

**Trigger.** Any pointer-int cast: `p as usize`, `usize as *mut T`, `*mut T as *const U`, tagged pointer manipulation, XOR linked lists.

**Question.** Does this site survive `MIRIFLAGS="-Zmiri-strict-provenance"`, or is it relying on the permissive provenance model?

**Failure modes.**
- `(p as usize | flag) as *mut T` — synthesizes "no provenance" pointer; dereferencing is UB under strict-provenance.
- XOR linked lists — pointers reconstructed from XOR'd ints have no provenance.
- Casts through `usize` losing provenance even though the bit pattern is identical.

**Prompt module.**
> Run `MIRIFLAGS="-Zmiri-strict-provenance" cargo +nightly miri test --test <site-test>`. If it errors with "pointer with no provenance," the site needs a strict-provenance API: `p.addr()`, `p.with_addr(...)`, `p.map_addr(...)`, `p.expose_addr()` / `ptr::with_exposed_provenance(...)`. For XOR linked lists, the pattern is fundamentally incompatible — refactor to slab-indexed (per `[65-ALLOCATOR-PATTERNS-DEEP.md § AL-1]`).

**Fix section.** [PROVENANCE-MODEL.md](PROVENANCE-MODEL.md), [COMMON-FAILURE-CASES.md § F-008](COMMON-FAILURE-CASES.md).

---

## ⊠ Stacked-vs-Tree-Borrows-Reconciliation

**Trigger.** Any (C) rewrite involving `&mut T` reborrowed through raw pointer, or interleaved iterator + raw view.

**Question.** Does the rewrite pass BOTH `-Zmiri-stacked-borrows` (default) AND `-Zmiri-tree-borrows`?

**Failure modes.**
- Rewrite passes Tree, fails Stacked → likely Stacked-Borrows false positive Tree fixed; document, scope test to Tree.
- Rewrite passes Stacked, fails Tree → rare; investigate / file upstream.
- Both fail → genuine UB; reject the rewrite.

**Prompt module.**
> Run miri in both modes. For mismatches, follow [STACKED-VS-TREE-BORROWS.md § Why the audit runs both](STACKED-VS-TREE-BORROWS.md). Don't pin one mode silently; document the choice in the SAFETY comment.

**Fix section.** [STACKED-VS-TREE-BORROWS.md](STACKED-VS-TREE-BORROWS.md), [COMMON-FAILURE-CASES.md § F-007](COMMON-FAILURE-CASES.md).

---

## ⋈ Kani-Reach (formal-verification candidate)

**Trigger.** Phase 5 plan for a (C) site on the soundness surface where the blast radius is high.

**Question.** Is this site formally verifiable via kani? If yes, the (C) rewrite gets a kani proof in addition to property tests.

**Failure modes.**
- FFI-touching sites — kani can't model `extern "C"`.
- Unbounded-loop sites — model blow-up.
- Heavy heap sites — `Vec<Vec<...>>` confuses the model.

**Prompt module.**
> Per [FORMAL-VERIFICATION.md § Decision tree](FORMAL-VERIFICATION.md), check: (1) Is the site on the soundness surface? (2) Is the blast radius high (CVE-level)? (3) Can the invariant be expressed as a kani-checkable property? If all yes, author a `#[kani::proof]` fn in `<project>/proofs/site_<id>.rs` per `assets/kani-proof-template.rs`.

**Fix section.** [FORMAL-VERIFICATION.md](FORMAL-VERIFICATION.md), [subagents/kani-prover.md](../../subagents/kani-prover.md).

---

## ✺ Dep-Soundness-Reach

**Trigger.** Phase 3 synthesis — for projects where a dependency has `cargo geiger > 0`.

**Question.** Does this project's pub API transitively call into the dependency's unsafe? If yes, the dep's proof obligation transfers to us — either we enforce it, or we wrap, or we file upstream, or we replace.

**Failure modes.**
- Project's pub fn calls dep's pub fn calls dep's `unsafe { ... }` with an unstated precondition. Our caller violates it; UB.
- Dep ships a "safe" public API that's actually unsound under specific inputs we forward.

**Prompt module.**
> Per [DEP-SOUNDNESS-PROTOCOL.md](DEP-SOUNDNESS-PROTOCOL.md), per dep with non-zero geiger: enumerate the dep APIs we reach, identify their proof obligations, and assign per-API to WRAP / REPLACE / UPSTREAM / JUSTIFY.

**Fix section.** [DEP-SOUNDNESS-PROTOCOL.md](DEP-SOUNDNESS-PROTOCOL.md), [subagents/upstream-issue-filer.md](../../subagents/upstream-issue-filer.md).

---

## ⌗ API-Stability-Audit

**Trigger.** Any (C) rewrite affecting a `pub` item.

**Question.** Does the rewrite change the public API? If yes, is the change classified (non-breaking / breaking-trivial / breaking-deep) and accompanied by an appropriate migration path?

**Failure modes.**
- Adding `#[non_exhaustive]` retroactively — silently breaks downstream `match`.
- Removing `Send`/`Sync` impl — breaks cross-thread consumers.
- Changing return type from `Vec<u8>` to `Box<[u8]>` — looks similar; different consumer expectations.
- Adding `Drop` to a type that didn't have one — breaks field-moves.

**Prompt module.**
> Per [API-STABILITY-AND-MIGRATION.md](API-STABILITY-AND-MIGRATION.md), classify the change. For breaking-trivial: draft a `#[deprecated]` shim. For breaking-deep: write `MIGRATION.md`. Run `cargo public-api --diff-git-checkouts` and `cargo semver-checks check-release` to verify.

**Fix section.** [API-STABILITY-AND-MIGRATION.md](API-STABILITY-AND-MIGRATION.md), [subagents/api-stability-reviewer.md](../../subagents/api-stability-reviewer.md).

---

## ✦ Ordering-Witness (atomics)

**Trigger.** Any atomic operation with explicit `Ordering`.

**Question.** Is the chosen Ordering the WEAKEST that produces the required happens-before relationships?

**Failure modes.**
- `Relaxed` on a flag that gates other state → race; reader sees flag=true with stale state.
- `SeqCst` everywhere → correct but over-synchronized; perf cliff on aarch64.
- `Release` on a write without a matching `Acquire` reader → no synchronization.
- AcqRel CAS where Acquire-on-success suffices → wasted Release.

**Prompt module.**
> Name the happens-before relationships the code requires. For each Ordering, justify: (a) "weakest correct" with the proof, OR (b) "SeqCst conservative default" with the perf-cost acknowledgement. Add a loom model per [35-ATOMICS-AND-ORDERINGS.md § loom model templates](../patterns/35-ATOMICS-AND-ORDERINGS.md).

**Fix section.** [35-ATOMICS-AND-ORDERINGS.md](../patterns/35-ATOMICS-AND-ORDERINGS.md), [75-LOCK-FREE-PATTERNS.md](../patterns/75-LOCK-FREE-PATTERNS.md).

---

## ⊰ Drop-Order-Trace

**Trigger.** Any (C) rewrite where the original held multiple owned resources (Vec, Box, File, Mutex guard) with mutual ordering.

**Question.** After the rewrite, do destructors run in the SAME order as before? Or have we silently changed Drop ordering?

**Failure modes.**
- Test passes; production trips a lock-already-held assertion because the new code drops the guard later.
- File descriptor closes BEFORE the buffer that referred to it; subsequent panic on use-after-close.
- Arc reference count decremented in a different order; clean-up runs in unexpected sequence.

**Prompt module.**
> Use a `DropTracker` test fixture (per [10-POINTER-MIGRATIONS.md § Equivalence-proving patterns](../patterns/10-POINTER-MIGRATIONS.md)) to log destructor invocations from both the unsafe and the safe versions. Assert the logs match. If they differ, either preserve the original order or document the change + get user approval.

**Fix section.** [COMMON-FAILURE-CASES.md § F-013](COMMON-FAILURE-CASES.md), [10-POINTER-MIGRATIONS.md](../patterns/10-POINTER-MIGRATIONS.md).

---

## Composition cheat-sheet

The operators are deliberately overlapping. A single FFI block typically deserves four or five. Phase 4/6 application order:

| Site shape | Operator sequence |
|------------|-------------------|
| FFI / `extern "C"` call | ⊙ → 🪟 → ⊕ → 🔒 → 🔁 → ⊗ |
| `unsafe impl Send/Sync` | ⊙ → ⚖ → ⊕ → 🔐 → ⊗ |
| SIMD intrinsic in hot path | ⊙ → ⏱ → 🪞 → ⊕ → (decide B vs C) |
| `MaybeUninit::assume_init` | ⊙ → 🗄 → 🔒 → 🧪 → (almost always C) |
| `Pin::new_unchecked` for self-ref | ⊙ → 🔁 → ⊕ → ⊗ |
| `mem::transmute` for endian / repr cast | ⊙ → 🧪 → (almost always C, swap for `zerocopy` / `bytemuck`) |
| `slice::get_unchecked` in inner loop | ⊙ → ⏱ → (decide B vs C based on bounds-check elimination) |
| Macro-generated unsafe (zerocopy etc.) | ⌖ → ⊙ → 🧪 → (cluster all per macro source) |
| Allocator impl | ⊙ → 📐 → ⊗ → 🔒 |
| Lock-free / concurrent unsafe | ⊙ → ⚖ → ⊞ → 🔁 → 🧪 |

Phase 9 (verify.sh harness) applies 🪞 and ⚑ globally to the run output.

Phase 7 fresh-eyes pass applies ⤴ on every (C) rewrite, then re-walks the per-site sequence.

### Extended operator sequences (post-v1 additions)

Apply the new operators alongside the v1 set per site shape:

| Site shape | Extended sequence (additions in bold) |
|------------|---------------------------------------|
| Pointer-int cast / tagged pointer | ⊙ → **⊟** → ⊕ → ⊗ |
| Raw-pointer reborrow through `&mut` | ⊙ → **⊠** → 🔒 → 🧪 |
| High-blast-radius (C) on soundness surface | All v1 + **⋈** (kani-reach) + **⌗** (API stability) |
| Atomic with explicit Ordering | ⊙ → **✦** → ⚖ → ⊞ (loom) → 🧪 |
| Multi-resource Drop interaction | ⊙ → **⊰** (Drop-order) → 🔒 → 🔁 |
| Site reachable from dep with non-zero geiger | ⊙ → **✺** → ⊕ → ⊗ |
| Any (C) plan touching `pub` items | (existing) + **⌗** API stability |
| Phase 6 adversarial re-check | (re-walk v1 sequence) + **⊟** + **⊠** if not yet applied |

The post-v1 operators are ADDITIVE to the v1 set, not replacements. The composition cheat-sheet table above is the v1 baseline; the extended sequences add for sites where the new operator's trigger fires.

### When operators conflict

Two operators can recommend incompatible actions on the same site. Common conflicts:

- **⊕ (Reachability-From-Safe) vs ⏱ (Profile-Or-It-Didn't-Happen).** A site reachable from `pub` (operator ⊕ wants hardening) AND in a hot path (operator ⏱ wants perf-justification). Resolution: it's a hybrid (A)+(B); see [50-SEND-SYNC-IMPLS.md § reachable-perf](../patterns/50-SEND-SYNC-IMPLS.md). The (A) hardening lands; the (B) safe-only path covers the perf-trade scenario.
- **📐 (Allocator-Identity) vs 🧪 (Equivalence-Witness).** The "obvious" safe rewrite swaps allocator; the equivalence test passes for "behavior" but allocator identity is broken. Resolution: 📐 wins; refine the rewrite to preserve allocator.
- **⊠ (Stacked-vs-Tree) vs (the rest).** Rewrite passes everything except Stacked Borrows. Resolution: document the Stacked false-positive in the SAFETY comment; scope the miri test to Tree; file upstream if egregious.

When operators conflict, document the resolution in the per-site classification AND in the plan. Future reviewers can audit the trade-off.
