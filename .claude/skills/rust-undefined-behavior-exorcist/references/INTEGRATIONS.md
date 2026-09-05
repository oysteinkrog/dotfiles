# Integrations — How This Skill Composes With Its Neighbors

This skill is one stop in a larger Rust-quality pipeline. Here are the composition recipes that work.

---

## With `/multi-pass-bug-hunting`

`/multi-pass-bug-hunting` is the umbrella "audit-fix-rescan" methodology. It owns the *iterative* loop; this skill owns the *Rust UB lane* within that loop.

**Recipe:** When `/multi-pass-bug-hunting` is driving a multi-class audit and reaches the "Rust UB" lane:

```
/multi-pass-bug-hunting → ... → "Rust UB lane" → /rust-undefined-behavior-exorcist
                                                  (returns CONFIRMED_UB findings + beads)
                                       ↓
                                  next lane
```

The UB-exorcist returns a structured findings list that the umbrella skill can consume.

---

## With `/rust-unsafe-code-exorcist`

See [BOUNDARIES.md §vs rust-unsafe-code-exorcist](BOUNDARIES.md#vs-rust-unsafe-code-exorcist). They run in sequence:

```
1. /rust-unsafe-code-exorcist   → fewer unsafe blocks, each one harder
2. /rust-undefined-behavior-exorcist → verify the result is also UB-free
                                        (catches what unsafe-exorcist isn't designed to find)
```

Both produce beads; the bead graphs link together via the `unsafe-audit-` / `ub-exorcism-` prefixes.

---

## With `/beads-workflow` (and `/beads-br`, `/beads-bv`)

Phase 9 invokes `/beads-workflow`'s exact plan-to-beads prompt. After polish, the remediation bead graph lives in the source repo's `.beads/`. The orchestrator can hand off to a swarm via `/vibing-with-ntm` or direct NTM orchestration to drive execution.

```
Phase 9 beads → br ready → swarm execution → br close
```

---

## With `/idea-wizard`

Phase 6 invokes `/idea-wizard` Phase 2 prompt verbatim with project narrowing. The wizard returns 30 → 5 ideas + 10 more. Net-new ideas (not already covered by existing findings) become new `EXP-NNN` entries.

```
Phase 6 → /idea-wizard Phase 2 → 15 techniques → promote net-new → append to EXPERIMENT-DESIGNS
```

The `/dueling-idea-wizards` variant can fan out two wizards in parallel for stress-test diversity.

---

## With `/multi-model-triangulation`

For high-stakes Phase 8 remediations (custom allocator, lock-free DS, public-API unsafe, FFI surface):

```
Phase 8 finding → /multi-model-triangulation (Claude + Codex + Gemini)
              → record consensus + dissent in phase8_remediation_plan.md
              → triangulation verdict feeds rubric scoring
```

Also useful when `⚠ ESCALATE` fires from `⬡ INSTRUMENT` — see [OPERATOR-LIBRARY.md §⚠ ESCALATE](OPERATOR-LIBRARY.md#-escalate--recruit-a-second-opinion) (the slug starts with a leading `-` because GitHub strips the `⚠` symbol from anchors).

---

## With `/code-review-gemini-swarm-with-ntm`

Phase 10 fresh-eyes can fan out to a Gemini swarm running on NTM tmux panes. The three prompts (A/B/C) are issued in parallel across panes; the orchestrator collects diffs.

```
Phase 10 → /code-review-gemini-swarm-with-ntm
        → 3 panes (one per prompt) review remediation plan + beads + experiment designs
        → diffs collected by orchestrator
        → second pass to confirm clean
```

---

## With `/testing-fuzzing`

`/testing-fuzzing` is the *campaign-grade* fuzzing skill — coverage-guided discovery, sanitizer-coupled execution, corpus minimization, regression conversion. UB-exorcist's Phase 3 fuzz step is targeted-and-shallow; for any UB found via fuzzing, the natural next move is to hand off to `/testing-fuzzing` for a deeper campaign.

**Three integration points across the phase model:**

**(a) Phase 3 — target authoring** (when an unsafe API lacks a fuzz target). The `fuzz-author-and-runner` subagent invokes `/testing-fuzzing` for the authoring step (its 10-phase loop is overkill for inline authoring; only steps Discover→Instrument→Seed→Harness are needed). UB-exorcist then runs the resulting target for 5–10 minutes inside Phase 3's time budget.

```bash
# Inside fuzz-author-and-runner:
#   /testing-fuzzing.Discover + .Harness  → fuzz/fuzz_targets/<name>.rs
#   Existing UB-exorcist                  → cargo +nightly fuzz run <name> -- -max_total_time=300
```

**(b) Phase 5 — campaign-grade execution** of Phase 4's interesting hypotheses. When Phase 4 synthesis flags a target as "high-value but the 5-minute pass didn't crash", `/testing-fuzzing` runs the **24-hour-class** campaign (its specialty). The artifacts (corpus, crashes, coverage report) flow back into UB-exorcist's Phase 7 iterate loop as new EXP entries.

```
UB-exorcist Phase 4 synthesis:           "EXP-N: parser, 5min clean, but high-value"
                ↓
/testing-fuzzing Run→Triage→Minimize:    24h campaign, corpus growth, crash dedup by stack hash
                ↓
UB-exorcist Phase 5/7 iterate:           each minimized crash → new EXP entry with verdict
```

**(c) Phase 13 — re-fuzz after remediation.** Once Phase 13's auto-remediation closes a bead, schedule a `/testing-fuzzing` ITERATE pass against the same target with the post-fix code to confirm the fix didn't move the bug rather than eliminate it.

**Sanitizer discipline:** both skills mandate ASan+UBSan at minimum. `/testing-fuzzing` adds TSan-coupled fuzzing (rare in plain cargo-fuzz workflows) — wire it in when Phase 1 flags concurrency hubs.

**Artifact sharing:** UB-exorcist Phase 3 writes targets under `$WORKSPACE/exp-harness-*/fuzz/`. `/testing-fuzzing` consumes those AS-IS — the harness layout is identical. After a `/testing-fuzzing` campaign, copy back `corpus/` and `crashes/` into the workspace for Phase 8 triage.

---

## With `/testing-metamorphic`

Standard UB detection has an oracle problem: "is this output correct?" is usually unanswerable without a reference implementation. Metamorphic relations sidestep this — instead of asking "is X correct?" you ask "is `f(X)` related to `f(g(X))` the way it should be?". `/testing-metamorphic` is the skill for designing and validating those relations.

**Three integration points:**

**(a) Phase 4/5 — MIRIFLAGS-axis metamorphic relations.** The MIRIFLAGS matrix is a built-in source of MRs that UB-exorcist already runs but doesn't formally exploit beyond [D-1 Cross-axis Miri verdict diff](UB-ADVANCED-DETECTORS.md). The next step up: **express the matrix as an MR suite** — "behavior under default ≡ behavior under tree_borrows for safe-input class S". When the MR fires, you have a CONFIRMED conditional UB.

```rust
// metamorphic relation: safe program output is borrow-model-independent
proptest! {
    #[test]
    fn safe_input_borrow_independent(s in safe_inputs()) {
        let default_out = run_with_miriflags(s.clone(), "");
        let tree_out    = run_with_miriflags(s.clone(), "-Zmiri-tree-borrows");
        prop_assert_eq!(default_out, tree_out, "axis-divergence on safe input");
    }
}
```

`/testing-metamorphic` is the skill that scores which MRs are worth implementing (its fault-sensitivity × independence rubric). Plug in at Phase 4 synthesis.

**(b) Phase 8 — remediation equivalence proof.** When Phase 8 picks "rewrite the unsafe SIMD as portable_simd", `/testing-metamorphic` authors a proptest that the safe path matches the unsafe path *byte-for-byte* across all inputs in the domain. The proptest becomes a regression-bead dep (Phase 9). This is exemplar E8 from [EXEMPLARS.md](EXEMPLARS.md).

**(c) Phase 5 — cross-sanitizer relations.** "Output under ASan ≡ output under MSan ≡ output under no-sanitizer" is an MR that catches sanitizer-divergent UB (uninitialized-memory reads that ASan misses but MSan catches). Author one MR per sanitizer pair.

**Composability with `/testing-fuzzing`:** the standard pattern is "fuzz generates inputs → MR validates relations". `/testing-fuzzing` explicitly mentions metamorphic as oracle-strength 4 in its hierarchy. UB-exorcist's Phase 3 fuzz harness becomes the input generator; `/testing-metamorphic`'s MR is the assertion inside `fuzz_target!`.

**This is the highest-leverage integration of the three** — it turns the existing MIRIFLAGS matrix and sanitizer matrix from independent verdict-collectors into a coherent relation suite.

---

## With `/testing-conformance-harnesses`

For FFI-heavy crates where the C library has a conformance suite (e.g., SQLite's TCL conformance):

```
Phase 3 dynamic sweep → /testing-conformance-harnesses runs the C-library's own
                       conformance suite against the Rust port
                    → divergences become UB candidates
```

---

## With `/testing-golden-artifacts`

Golden artifacts are the *anti-regression layer* — frozen, canonicalized outputs that fail CI on byte-level divergence. They are the natural complement to fuzzing (which finds NEW crashes) and metamorphic relations (which validate properties): goldens guarantee the SAME crash doesn't come back.

**Four integration points:**

**(a) Phase 5 — freeze the reproducer.** Every CONFIRMED_UB experiment in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` gets a golden capturing the *exact* tool output (Miri traceback, ASan crash report, Loom interleaving transcript). Future executions of the same reproducer that produce a different output indicate either a Rust upgrade-induced behavior change or a silent re-introduction.

```
experiments/EXP-007/repro.rs       # the source
experiments/EXP-007/repro.golden   # frozen Miri stderr (scrubbed)
phase5_experiment_results/EXP-007.log  # raw output for diff
```

`/testing-golden-artifacts` provides the canonicalization recipe (scrub timestamps, memory addresses, `at line N` numbers, thread IDs).

**(b) Phase 8 — remediation equivalence golden.** When the chosen remediation changes observable output (parser rewrite, formatter change, error message), goldens capture the pre-change output so the post-change output can be compared byte-for-byte. Use with `/testing-metamorphic` MRs for full coverage: MR catches semantic divergence, golden catches surface divergence.

**(c) Phase 9 — per-bead regression golden.** Every Phase 9 test-bead writes both a `#[test]` AND a golden snapshot of the (now-passing) Miri output. The bead's regression dep includes both. CI then runs the test + diffs the golden; a divergence on either signal opens the bead automatically.

```
tests/regression/ub_fix_proj_abc12.rs               # the test (Phase 9)
tests/regression/snapshots/proj_abc12_miri.snap     # frozen Miri-clean trace
```

**(d) Phase 13 — auto-remediation safety net.** Phase 13's auto-remediation closes beads when post-change gates pass. Adding a golden gate ("post-change Miri output must match the EXPECTED-CLEAN golden") catches the case where the fix changes the *kind* of UB rather than eliminating it — e.g., remediation makes default-Miri clean but Tree-Borrows now fails. Without the golden, the executor would close the bead; with it, the divergence shows up immediately.

`/testing-golden-artifacts` workflow (canonicalize → review → freeze → guard) maps 1:1 onto Phase 5/9 lifecycle: the experiment-executor or regression-harness-author subagent calls into it for the freeze step, then the executor's quality gate compares against the frozen golden.

**Conflict avoidance:** both skills use the word "artifact". UB-exorcist's `phase11_artifacts/` are *campaign outputs* (corpus, crash logs); `/testing-golden-artifacts`'s `.golden` files are *expected outputs*. Keep them in distinct subtrees — `phase11_artifacts/` vs `tests/golden/` or `experiments/<EXP>/snapshots/` — and the terminology overlap stays harmless.

---

## With `/testing-real-service-e2e-no-mocks`

Per AGENTS.md memory: **don't mock the database or FFI in concurrency tests**. This skill explicitly avoids mocks in the dynamic sweep. When `/testing-real-service-e2e-no-mocks` is available, the `fuzz-author-and-runner` subagent uses its patterns (real-DB transaction rollback for isolation, etc.).

---

## With `/deadlock-finder-and-fixer`

If Phase 3 dynamic sweep surfaces a *deadlock* rather than a *race*, hand off to `/deadlock-finder-and-fixer`. They share loom/shuttle infrastructure but the deadlock skill has deeper deadlock-specific operators.

```
Phase 3 surfaces deadlock symptom → /deadlock-finder-and-fixer takes over
                                  → returns root-cause + remediation suggestion
                                  → ub-exorcist absorbs the remediation into Phase 8
```

---

## With Kani / Prusti / Creusot (direct formal verification)

For findings where formal-verification-grade guarantees would justify the engineering cost (custom allocator, cryptographic primitive, kernel module FFI):

```
Phase 8 finding → operator ⊢ PROVE → cargo kani / cargo prusti / creusot
              → Kani / Prusti / Creusot bounded model check
              → formal proof becomes part of the remediation evidence
```

---

## With `/lean-formal-feedback-loop`

When Kani / Prusti / Creusot aren't sufficient and the user wants Lean-level proofs:

```
Phase 8 high-stakes finding → /lean-formal-feedback-loop
                            → Lean theorem proving on the soundness obligation
                            → proof committed alongside the remediation
```

Reserved for the very highest stakes — typically only one or two findings per audit, if any.

---

## With `/extreme-software-optimization`

When Phase 8 picks a safe rewrite that meets correctness but loses perf:

```
Phase 8 chosen rewrite → /extreme-software-optimization
                      → profile-driven optimization of the safe path
                      → measured perf delta updates rubric score
                      → may surface a better candidate to revisit
```

This is operator `⌘ REDUCE` in disguise — shrink the safe shell while preserving correctness.

---

## With `/cass`

Phase 0 bootstrap can mine prior agent sessions for UB-hunting rituals specific to this codebase:

```
Phase 0 → cass search 'frankensqlite miri' --robot --limit 10
        → cass view <session> -n <line> --json for top hits
        → seed phase0_project_priors.md with the recurring shapes
```

`/cass` is also used in Phase 6 to find ideas that worked in similar codebases.

---

## With `/codebase-archaeology` and `/codebase-report`

Phase 1 borrows the prompts from these skills. The `unsafe-surface-mapper` subagent uses `/codebase-archaeology`'s exploration prompt with a UB-focused lens.

```
Phase 1 unsafe-surface-mapper
  → invokes /codebase-archaeology shape (lens: "where does unsafe live?")
  → invokes /codebase-report shape for the module digest
```

---

## With `/operationalizing-expertise`

This entire skill is a Track A application of `/operationalizing-expertise`:

- `corpus/primary_sources/` — cass quotes + exemplar code (anchored)
- `corpus/quote_bank/quote_bank.md` — stable Q-NNN anchors
- `corpus/distillations/{opus,codex,gemini}/` — model-specific reads (subdirs exist as placeholders; populated when distillation rounds are run via `/operationalizing-expertise`)
- `corpus/specs/triangulated_kernel.md` — marker-bounded
- `corpus/specs/operator_library.md` — operator cards + prompt modules
- `scripts/validate-corpus.py`, `scripts/validate-operators.py`, `scripts/extract-kernel.py`

See [ARTIFACTS.md](ARTIFACTS.md) for the artifact shape.

---

## With `/flywheel` / `/ntm` / `/agent-mail`

For very large audits (Swarm tier in [ORCHESTRATION.md](ORCHESTRATION.md)):

```
Orchestrator → /agent-mail for file reservations + threads
            → /ntm for tmux pane fan-out of subagents
            → /flywheel for self-improving session methodology
```

This is the path for "audit `frankensqlite` end-to-end with 12 panes running in parallel".

---

## With `/rch` (remote compute hub)

Phase 11 soak campaigns always dispatch via `rch`:

```
soak-runner → rch exec --tag ub-exorcism-<run>-<campaign> -- <campaign cmd>
           → rch status --tag ... (poll)
           → rch sync --pull (gather artifacts)
```

Phase 3's heaviest runs (full Miri matrix on a big test suite, MSAN with std rebuild) can also offload via `rch` if local wall time > 5 min.

---

## With `/gh-actions`

Phase 12 `UB_RUNBOOK.md` includes the GitHub Actions YAML for the project's permanent CI:

```yaml
# Excerpt from a generated UB_RUNBOOK.md
name: ub-exorcism-ci
on: [push, pull_request]
jobs:
  miri-matrix:
    strategy: { matrix: { config: [default, tree-borrows, strict-provenance, symbolic-alignment] } }
    steps:
      - run: MIRIFLAGS="${{ matrix.miriflags }}" cargo +nightly miri test
  sanitizers:
    strategy: { matrix: { sanitizer: [address, thread, leak] } }
    ...
```

`/gh-actions` is the helper skill that turns the runbook's CI section into a maintainable workflow file.

---

## With `/dsr` / `/release-preparations`

For W7 (pre-release gate) workflows, this skill runs before `/release-preparations` so the release artifact ships with a clean soundness report:

```
/rust-undefined-behavior-exorcist (Standard or Exhaustive mode) → UB_RUNBOOK.md
                                                                ↓
/release-preparations → checksum + sign + cargo publish + GH release
                       (release notes link to the UB_RUNBOOK.md)
```

---

## Composition cheat sheet

```
Discovery:     /codebase-archaeology + /cass
Detection:     this skill (Phases 1–7)
Remediation:   this skill (Phase 8) + /multi-model-triangulation + Kani / Prusti / Creusot
Implementation:beads → swarm via /vibing-with-ntm or direct NTM orchestration
Verification:  /testing-fuzzing + /testing-metamorphic + /testing-golden-artifacts
Coordination:  /agent-mail + /beads-workflow + /beads-br + /beads-bv
Offload:       /rch
CI gate:       /gh-actions (from UB_RUNBOOK.md)
Release:       /release-preparations + /rust-crates-publishing
```
