# POLISH-BAR.md — Acceptance Rubric

A site has passed the bar when EVERY dimension below is satisfied for that site's bucket. The polish bar is what the Phase 10 maintainer-empathy reviewer will check against.

The Phase 6 adversarial reclassifier walks the rubric per site as part of its convergence test — any dimension marked "missing" reopens the site.

---

## Dimensions (applied per site)

### 1. Invariant named

**Test.** The site's write-up names the exact soundness invariant the `unsafe` upholds, in the form: "sound IFF [condition]." Cites the line(s) that establish [condition].

**Pass example.** *"This `transmute` is sound IFF the byte slice is at least `size_of::<u32>() * N` bytes and aligned to `align_of::<u32>()`. The caller-side check at `src/parse.rs:142` establishes both via `slice::align_to`."*

**Fail example.** *"This is safe because we know the input is well-formed."* — no named invariant, no caller-side citation.

### 2. Falsifiable justification (A only)

**Test.** Every (A) classification has the JUSTIFICATION block from [CLASSIFICATION-RUBRIC.md § (A)](CLASSIFICATION-RUBRIC.md#a-strictly_unavoidable), including three failed alternatives AND a steel-man attack AND the rebuttal.

**Pass.** Three concrete alternatives, each cited to Rust Reference / RFC / nomicon, with specific failure reasons.

**Fail.** "It would be hard to refactor" or "all the popular crates do it this way."

### 3. Profile-or-it-didn't-happen (B only)

**Test.** Every (B) classification has criterion mean + p99 numbers, hyperfine end-to-end timing, and a flamegraph diff pasted into the plan. The budget check is computed: measured delta vs user budget.

**Pass.** All three measurements present with numbers; budget check explicit; if within budget, the site is documented as graduated to (C).

**Fail.** "It's faster" without numbers; microbench without end-to-end propagation.

### 4. Equivalence witness (C only)

**Test.** Every (C) classification has a `proptest` / `quickcheck` test that:
- Generates at least 10,000 cases for primitive inputs (or 1,000 for structural inputs).
- Asserts `f_unsafe(x) == f_safe(x)` AND panic/error equality.
- Is runnable under `cargo test --release` AND `cargo +nightly miri test`.

**Pass.** Test file path + strategy + the failure modes it covers.

**Fail.** "Looks equivalent"; or a property test that only covers the success path.

### 5. Macro-expanded view (any macro-origin site)

**Test.** The site write-up references `phase1/<crate>__expand.rs:<line>`, not the macro invocation in source.

**Pass.** Inventory row has `macro_origin: true` AND `macro_origin_path` pointing to expanded output with line anchor.

**Fail.** Audit only mentions the macro invocation; misses macro-generated `unsafe`.

### 6. Soundness-surface marker

**Test.** Every site reachable from a `pub` API has a hardened SAFETY comment naming the caller-side proof obligation.

**Pass.** SAFETY comment lists: (a) what the caller must guarantee, (b) where that guarantee is established, (c) what breaks if violated.

**Fail.** Empty or vague SAFETY comment; or SAFETY comment that contradicts the call graph.

### 7. Send/Sync audit (any `unsafe impl Send/Sync`)

**Test.** Write-up names the field-level invariants the impl assumes and traces who enforces them.

**Pass.** Every field of the impl-targeted type is listed; each field's Send/Sync-ness is either auto-derive or explicitly justified by a named invariant. If the impl could be removed after a small refactor (e.g., wrapping a raw pointer in a `SendPtr<T>` newtype with audited Send), that refactor is in the plan.

**Fail.** Impl declared without field-level audit; or impl rationale is "compiler made me do it."

### 8. Drop-glue sanity (every (C) rewrite)

**Test.** The rewrite has been traced for panic-in-Drop and async-cancellation paths. Every owned resource has its destructor proved to run on every exit (success, return, `?`, panic, await drop).

**Pass.** A "Drop-glue trace" section in `audit/plans/site-<id>.md` enumerating every exit path AND the destructor invocations.

**Fail.** Trace missing; or trace omits the panic / await-drop paths.

### 9. Allocator identity preserved (any (C) rewrite touching allocations)

**Test.** The rewrite did not silently swap a custom allocator (arena / bump / slab) for the global allocator.

**Pass.** The plan names the original allocator AND the replacement; if they differ, the user has explicitly approved the change AND the benches show acceptable allocation pressure.

**Fail.** Original used `bumpalo::Vec`; rewrite uses `std::vec::Vec`; no benchmark covering allocation-pressure regression.

### 10. Pre-existing-UB separated (per Phase 7/9 finding)

**Test.** Any UB discovered in code that was NOT in scope for refactor is filed as `pre-existing-ub-N` bead, NOT folded into the refactor plan.

**Pass.** OUT-OF-SCOPE findings have their own bead; refactor PR doesn't claim credit for fixing them; `audit/synthesis/pre-existing-ub.md` lists each.

**Fail.** A pre-existing UB finding is silently included in a refactor commit.

### 11. Bead acceptance criteria (every bead)

**Test.** Each bead's acceptance criteria are exact `cargo` invocations a maintainer can copy-paste, with expected output.

**Pass.** Acceptance reads:
```
cargo test -p mycrate --features safe-only
# expected: all tests pass; 0 failed
cargo +nightly miri test -p mycrate --test equivalence_site_0142
# expected: tests run; 0 errors; no UB reports
```

**Fail.** "Run the tests"; or "make sure CI is green."

### 12. Maintainer-empathy review (Phase 10)

**Test.** A fresh agent read the audit cold and answered "would I land this?" with confidence + objections + missing-evidence list in `REVIEWER_RESPONSES.md`.

**Pass.** `REVIEWER_RESPONSES.md` exists; every objection is either addressed in revised plans or filed as a follow-up bead with explicit "deferred — see REVIEWER_RESPONSES.md §N" annotation.

**Fail.** No `REVIEWER_RESPONSES.md`; or objections noted but not addressed.

---

## Per-bucket required dimensions

| Bucket | Required dimensions |
|--------|---------------------|
| (A) | 1, 2, 6, 11, 12 (+ 5 if macro-origin, + 7 if Send/Sync impl) |
| (B) | 1, 3, 6, 11, 12 (+ 5 if macro-origin) |
| (C) | 1, 4, 6, 8, 9, 11, 12 (+ 5 if macro-origin, + 7 if Send/Sync impl, + 10 if Phase 7/9 surfaced anything during the rewrite) |
| pre-existing-ub | 10, 11 |

---

## Cross-cutting bar (applied across the audit, not per-site)

### a. Inventory totality

`unsafe-inventory.jsonl` row count matches the sum of:
- `cargo-geiger` count, AND
- `ast-grep` count across `unsafe { }`, `unsafe fn`, `unsafe impl`, `unsafe trait`, `extern { }`, `asm!`, AND
- macro-origin unsafe from `cargo expand`.

Any mismatch must be explained (e.g., "geiger counts X, ast-grep counts X+3, the 3 are in `*-derive` macro output; rows added").

### b. Soundness-surface completeness

`audit/synthesis/soundness-surface.md` covers every `pub` item in rustdoc JSON. No `pub fn` is missing a soundness-surface entry (even if the entry says "REACHES: none").

### c. Convergence proof

Phase 4 + Phase 6 convergence proofs (the two-pass diff showing <5% flips + zero (A)→(C)) are committed under `audit/classification/`.

### d. Harness green

`verify.sh` exits 0 on a clean run. If it doesn't, every finding is triaged via operator ⚑.

### e. Beads graph well-formed

`br ready` shows at least one unblocked bead at the start of refactor work. No cycles. Every bead has acceptance criteria.

### f. AGENTS.md compliance

No file was deleted in the audit dir; no destructive rewrite was used; no `git reset --hard` was run anywhere. The audit repo's git log shows incremental, reviewable progress.

---

## Self-check at end-of-Phase-5

Before Phase 6 starts, the orchestrator runs `scripts/check-polish-bar.sh` which:

1. Walks every site in `audit/classification/`.
2. For each, checks the required dimensions per its bucket.
3. Emits a pass/fail per site to `audit/phase5/polish-bar-check.md`.
4. Fails the phase if any site has a missing required dimension.

This is the explicit gate to Phase 6. Sites failing the gate go back to the refactor-planner for revision.

---

## Re-entry from Phase 6

Phase 6 adversarial reclassification can REOPEN dimensions:
- If a (A) is reclassified to (B), dimensions 2 → 3 (B needs perf numbers we may not have).
- If a (B) is graduated to (C), dimensions 3 → 4 (C needs property test we may not have).
- If a (C) equivalence claim is broken, dimension 4 fails until a stricter test exists.

In all cases, Phase 5 re-runs on the reopened sites; the polish-bar check re-runs; only then does Phase 7 start.

---

## End-of-audit summary line

After Phase 10, the audit emits a single line in `<audit-dir>/AUDIT_SUMMARY.md`:

```
Total sites: <N>
  (A) STRICTLY_UNAVOIDABLE: <a>  (all with falsifiable justification)
  (B) PERF_ONLY:            <b>  (all with safe-only feature + measured perf)
  (C) REFACTORABLE:         <c>  (all with property-based equivalence proof)
  pre-existing-ub:          <p>  (filed as separate beads, not in refactor scope)

Soundness surface entries: <s>  (every pub API path that reaches unsafe)
Convergence: Phase 4 in <p4> passes; Phase 6 in <p6> passes
Verify.sh: GREEN  (miri + careful + loom + fuzz + mutants + geiger + default + safe-only)
Reviewer: <confidence-level>  (Phase 10 maintainer-empathy)
```

This line is what the user pastes into the PR description when authorizing refactor-on-approve.
