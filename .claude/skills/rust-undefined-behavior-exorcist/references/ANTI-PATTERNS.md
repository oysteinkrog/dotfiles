# Anti-Patterns — How UB Audits Fail

Catalog of audit failure modes, each with the reason it fails and the correction. Mined from real /dp/* sessions plus the broader Rust-audit literature.

---

## A1. Grepping `unsafe` and calling it an audit

**Why it fails:** Misses macro-expanded unsafe, FFI-contract violations (which can be reached through safe wrappers), library-trait invariant drift (`Hash`+`Eq` lies), data races between safe-but-incorrect atomic Orderings, and Miri-detectable aliasing violations in safe-looking code.

**Correction:** Phase 1 sweep also runs `cargo expand` to find macro-generated `unsafe`. Phase 2 runs *25 bucket sweepers*, not just an "unsafe-block sweep". Phase 3 runs Miri matrix + sanitizers + loom + fuzz — most of which catch UB without ever inspecting an `unsafe` keyword.

---

## A2. Running Miri once with default flags and shipping

**Why it fails:** Miri's default aliasing model is stacked borrows (SB); the stricter tree borrows (TB) catches a different (and larger) set of violations. Strict-provenance and symbolic-alignment are off by default. A single Miri run gives 1-in-4 coverage of what the matrix gives.

**Correction:** Always run `scripts/run-miri-matrix.sh` (SB + TB + strict-provenance + symbolic-alignment). See [TOOLING.md §Miri matrix](TOOLING.md#the-miriflags-matrix-run-all-four).

---

## A3. Treating a clean fuzz run as proof of soundness

**Why it fails:** Fuzz coverage is incidental — libFuzzer reaches what it reaches. A 10-minute campaign tests <0.1% of the input space for non-trivial parsers. A clean fuzz means "no input we tried crashed", which is *much* weaker than "no UB".

**Correction:** Always **triage crashes under Miri** to confirm they were genuine UB, and conversely run Miri *on the test suite* to catch UB that fuzz didn't reach. Phase 11 soak campaigns (24h+) raise confidence further but never to certainty.

---

## A4. Mocking the database or the FFI in concurrency tests

**Why it fails:** The race you're hunting often lives *in the interaction between Rust and the foreign side*. Mocking that side replaces the very component whose behavior matters. From AGENTS.md feedback: "we got burned last quarter when mocked tests passed but the prod migration failed".

**Correction:** Use real FFI / real DB in concurrency tests. For Miri, where FFI is unsupported, add a `#[cfg(miri)]` shim that *also has the same aliasing contract* as the real FFI — never a strictly safer shim that masks UB.

---

## A5. "It compiles, so it's sound"

**Why it fails:** The borrow checker checks safe code, not raw-pointer or FFI code. Soundness in the presence of `unsafe` is empirical until proven. Every `unsafe { … }` block opens an obligation that the compiler does not discharge.

**Correction:** Treat every `unsafe { … }` block, Rust→FFI call site, and manual `Send`/`Sync` impl as `LIKELY-UB` until an experiment confirms `NO_EVIDENCE`. Treat manual `Hash`/`Eq` as a correctness invariant target; escalate it to UB only when a concrete unsafe boundary depends on it.

---

## A6. Picking the first remediation that compiles

**Why it fails:** Many UB shapes have ≥2 isomorphic rewrites with different correctness margins / perf deltas / blast radii. The first one that compiles is rarely the optimal one. Future maintainers revisit choices that lacked alternatives.

**Correction:** Phase 8 enumerates ≥2 candidates, scores each on the 5-axis rubric (correctness margin / perf delta / diff blast radius / reviewability / maintainability), picks the winner, records runners-up. See [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md).

---

## A7. Severity inflation

**Why it fails:** Marking every ambiguous finding `MUST-BE-UB` destroys the signal-to-noise of the unified findings table. Reviewers stop paying attention; real `MUST-BE-UB` findings get lost.

**Correction:** Use the severity calibration in [UB-TAXONOMY.md](UB-TAXONOMY.md). Reserve `MUST-BE-UB` for findings where sound static analysis is enough to prove UB. Use `LIKELY-UB` when the dynamic check is the arbiter. `SUSPICIOUS` for pattern matches you can't yet articulate. `CONTRACTUAL-BUT-DEFENSIBLE` for sites that depend on a caller contract that *is* documented and enforced.

---

## A8. Skipping the rewrite runners-up

**Why it fails:** Future maintainers will revisit the choice when the runner-up becomes preferable (new tooling lands, perf characteristics change, neighbor code changes). Without recorded alternatives, they re-derive the analysis from scratch — often poorly.

**Correction:** Phase 8 records runners-up with their scores and rationale. The `phase8_remediation_plan.md` is intentionally redundant on purpose; bandwidth is cheap, re-derivation is expensive.

---

## A9. Running a soak campaign locally without `rch`

**Why it fails:** A 24h fuzz campaign on the user's main machine burns CPU/disk/battery for a day and tangles with the user's other work. Worse, it ties up the local cargo cache, slowing everything else.

**Correction:** Phase 11 always offloads via `rch exec --` to worker hosts. Local runs are fine for <5min experiments; anything longer goes to `rch`. See `/rch` skill.

---

## A10. Closing a bead without test- and docs-bead deps

**Why it fails:** A remediation without a regression test gets re-broken in a subsequent refactor; nobody notices. A remediation without updated `// SAFETY:` docs gets re-interpreted, and the next reader implements the wrong invariant.

**Correction:** Phase 9 validation gate requires every remediation bead to have ≥1 test-bead dep AND ≥1 docs-bead dep. The `bead-author` subagent enforces this; `bv --robot-insights | jq` validates.

---

## A11. Combining sanitizers in one build

**Why it fails:** LLVM sanitizers conflict at the runtime level. ASan + TSan + MSan in the same binary doesn't work — they fight over signal handlers, shadow memory, and instrumentation passes.

**Correction:** Run each sanitizer in its own build pass. The `run-sanitizer-matrix.sh` script runs them sequentially.

---

## A12. Single-pass `⊙ DEBOUNCE-FALSE-POSITIVE`

**Why it fails:** A single clean Miri run isn't proof of absence. Miri's coverage isn't exhaustive; rare schedules can hide races; corpus-warm fuzz coverage can mask new shapes.

**Correction:** A `NO_EVIDENCE` verdict is closed only after two fresh-eyes runs (different round, possibly different model/agent) confirm absence. See operator `⊙ DEBOUNCE-FALSE-POSITIVE` in [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md).

---

## A13. Blocking I/O in `Drop`

**Why it fails:** `Drop` runs synchronously even in async context. Blocking I/O in `Drop` blocks the runtime worker; calls into `tokio::runtime::Handle::block_on` from `Drop` while inside a Tokio runtime deadlock.

**Correction:** Either (a) use a non-blocking variant in `Drop` (e.g., `waitpid(WNOHANG)` instead of `wait`), or (b) require explicit `close()` and `Drop` only releases memory. See [REMEDIATION-PATTERNS.md Shape 10](REMEDIATION-PATTERNS.md#shape-10-drop-that-performs-blocking-io).

---

## A14. `transmute` as a quick fix

**Why it fails:** `transmute<A, B>` is sound only if A and B are layout-compatible — which depends on `#[repr]`, padding, niches, and compiler version. Cross-version regressions are common. Reaching for `transmute` to "make the types line up" almost always introduces UB.

**Correction:** Prefer `bytemuck::cast` (compile-time-verified via `Pod`/`Zeroable`), `zerocopy::FromBytes`, `f32::to_bits` for primitive bit-casts, or explicit byte copies. `transmute` is the last resort, and even then requires a `# Safety` block enumerating every assumption.

---

## A15. Manual `Send`/`Sync` without a synchronization story

**Why it fails:** `unsafe impl Send for T {}` says "T is safe to send across threads". If T contains a raw pointer to data that another thread might mutate, this is a lie. Compilers happily accept the impl; UB shows up under load.

**Correction:** Every manual `unsafe impl (Send|Sync)` must have a SAFETY comment naming: (a) the external synchronization mechanism, (b) the only public deref path, (c) why that path is sound. See exemplar [E2 in EXEMPLARS.md](EXEMPLARS.md#pattern-e2--unsafe-impl-sendsync-with-external-synchronization).

---

## A16. Skipping the project-shaped `/idea-wizard` round

**Why it fails:** Off-the-shelf UB checklists miss project-specific shapes — custom allocators, custom self-ref structs, custom intrusive lists, custom lock-free queues, custom MMIO patterns. These shapes are exactly where the most expensive UB lives.

**Correction:** Phase 6 always runs `/idea-wizard` with project-narrowing. Even if the wizard surfaces "Already covered by F-NNN" for 14 of 15 ideas, the 15th can be the one that catches the production bug.

---

## A17. Treating Loom failures as flakes

**Why it fails:** Loom is deterministic — it explores every legal interleaving. A failing schedule is not a "flake"; it's *the bug*. Dismissing it because the test "usually passes" is shipping a known race.

**Correction:** Every Loom assertion failure is a `CONFIRMED_UB` (data race or violated synchronization invariant). Record the schedule trace; treat it the same as a Miri-reported UB.

---

## A18. Forgetting `--test-threads=1` with TSan

**Why it fails:** Without `--test-threads=1`, `cargo test` runs multiple tests in parallel. The races TSan reports may be *between tests* rather than within the code under test. The signal becomes noise.

**Correction:** `run-sanitizer-matrix.sh` always passes `-- --test-threads=1` for TSan. Verify in the log.

---

## A19. Auditing only the latest commit

**Why it fails:** UB often lives in code untouched in the latest commit. The latest commit may have *introduced* a regression elsewhere by changing assumptions, but the regression manifests in old code.

**Correction:** The whole audit runs against the *current tree*, not just the diff. Even when used as a pre-PR gate, Phase 1 inventory walks the whole project.

---

## A20. Filing pre-existing UB as part of the current PR's remediation

**Why it fails:** Conflates "this PR's regressions" with "the project's pre-existing bugs". Reviewers can't tell what *this* PR changed. Worse, a long-time UB site gets silently fixed as a side effect, losing the audit trail.

**Correction:** Pre-existing UB gets a separate bead with the `pre-existing-ub` label, scoped to its own remediation cluster. Never folded silently into a refactor PR.

---

## A21. Deleting a workspace file to "clean up"

**Why it fails:** AGENTS.md Rule #1. No file deletion without permission. Even files you created. Even files that "look obsolete".

**Correction:** Move-aside (with permission) or archive into a subdir; don't delete. The orchestrator's resume protocol depends on the workspace being intact.

---

## A22. Using `bare bv` (TUI) in an automated session

**Why it fails:** Bare `bv` launches the interactive TUI and blocks the session indefinitely. Per AGENTS.md: "CRITICAL: Use ONLY `--robot-*` flags."

**Correction:** Every `bv` call must use `--robot-triage`, `--robot-insights`, `--robot-next`, etc. The `bead-author` subagent enforces this.

---

## A23. Hand-paraphrasing the Phase 10 fresh-eyes prompts

**Why it fails:** The three prompts (A/B/C) are calibrated; paraphrasing changes their effect. Documentation-website skill's experience: when paraphrased, agents skip prompt B's "trace functionality through related code files" instruction, missing cross-file regressions.

**Correction:** Use them *verbatim* from [AGENT-PROMPTS.md §Phase 10](AGENT-PROMPTS.md#phase-10--fresh-eyes-reviewer). If unsure of the exact text, copy from there.

---

## A24. Declaring convergence after a single quiet round

**Why it fails:** A single quiet round can happen by accident (the round's queries didn't hit a new UB pattern). Two consecutive quiet rounds give a small probabilistic guarantee that the loop is genuinely saturated.

**Correction:** `convergence-tracker.sh` exits 0 only when *this* round is quiet AND the *previous* round was also quiet AND ≥10 rounds have run. The orchestrator must respect that exit code.

---

## A25. Skipping the `UB_RUNBOOK.md` deliverable

**Why it fails:** The runbook is what keeps the project UB-free *after* the audit. Without it, every new contributor re-discovers which Miri flags to enable, which loom models to keep green, which fuzz corpora are gold. The audit's value decays in months instead of years.

**Correction:** Phase 12 always produces `UB_RUNBOOK.md` with the project's permanent CI gates. See [PHASES.md §Phase 12](PHASES.md#phase-12-final-artifacts).
