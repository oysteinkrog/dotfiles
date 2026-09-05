# UB-Exorcism Triangulated Kernel

> The consensus rules across model distillations. Marker-bounded for deterministic extraction. Disagreements live in [DISPUTED](#disputed) and [UNIQUE](#unique) below the kernel; only consensus content lives between the KERNEL-START and KERNEL-END markers.

<!-- KERNEL-START -->

## I1. UB is the full Rustonomicon taxonomy

UB is NOT just `unsafe { ... }` blocks. It is *every* situation the Rustonomicon lists as undefined behavior. The audit must therefore operate over the full taxonomy (25 buckets in this skill) — not just the `unsafe`-keyword subset.

**Anchors:** Q-001 (cass; user's first-message statement), Q-014 (cass; frankensqlite session), E-001..E-011 (exemplar patterns from /dp/*).

## I2. Detection must compose static + dynamic + experimental

No single tool finds every UB shape. The skill must run, in order:
1. Static sweep (ast-grep / syn walkers / clippy / cargo-geiger) — fast, high recall, lots of false positives
2. Dynamic sweep (Miri matrix + sanitizers + loom + shuttle + fuzz) — slower, high precision on what it covers
3. Experimental verdict (each finding is proved or refuted by a designed experiment)

Tools that disagree are a SIGNAL, not a contradiction — escalate.

**Anchors:** Q-003 (cass; "Miri tree-borrows is gold"), Q-007 (cass; "TSan + --test-threads=1 is the only reliable race oracle").

## I3. Convergence is non-negotiable and measurable

The loop ends only when:
- Two consecutive rounds have <3 new findings AND zero OPEN/NEEDS_REFINEMENT
- AND total rounds ≥10

Below 10 rounds, the loop is in Quick mode (which is triage, not audit). Convergence is computed deterministically by `scripts/convergence-tracker.sh`; the orchestrator must respect that exit code.

**Anchors:** Q-018 (cass; "always 10 rounds minimum").

## I4. Remediation must enumerate alternatives

For every CONFIRMED_UB site, Phase 8 enumerates ≥2 candidate rewrites and rubric-scores them (correctness margin / perf delta / diff blast radius / reviewability / maintainability). Runners-up are preserved with their tradeoffs.

**Anchors:** E-008 (proptest oracle ritual), Q-021 (cass; "always document the alternatives you rejected").

## I5. Beads must carry test-bead + docs-bead dependencies

Every remediation bead has at least one test-bead dep (Miri / loom / sanitizer / fuzz / property) AND at least one docs-bead dep (SAFETY comment + `# Safety` doc section). Without both, the remediation is a one-shot fix with no regression canary.

**Anchors:** Q-025 (cass; user's repeated polish prompts), the beads-workflow skill.

## I6. The Phase-10 fresh-eyes prompts are verbatim

The three prompts (A/B/C) are calibrated; paraphrasing changes their effect. They are kept word-for-word from the documentation-website skill. Subagents that paraphrase get redirected.

**Anchors:** documentation-website skill's PHASES.md.

## I7. Compaction survival is the workspace files

The orchestrator never relies on in-memory state. Every phase artifact is a marker-recognizable file. A successor agent reads the files and resumes — see [ARTIFACTS.md §Compaction-survival contract](../../references/ARTIFACTS.md#compaction-survival-contract).

**Anchors:** documentation-website skill's resume protocol; /operationalizing-expertise Track B.

## I8. No mocks in concurrency tests

Per the user's memory: integration tests must hit a real database / real FFI / real services. Mocks hide the very races the audit is hunting. This is a hard rule.

**Anchors:** AGENTS.md memory `feedback_no_mocks_in_concurrency` (user feedback after a past incident).

## I9. SAFETY comments must be multi-part and substantive

Every `unsafe { ... }` block carries a SAFETY comment that names: (a) the invariant relied on, (b) where the invariant is enforced, (c) why the enforcement is sound. <40 char comments are flagged as PRESENT_WEAK in Phase 1. Missing comments are MISSING.

**Anchors:** E-001 (multi-part SAFETY contract pattern, /dp/* mining).

## I10. Manual `Send`/`Sync` impls require explicit synchronization story

`unsafe impl Send for T {}` says "T is safe to send across threads". If T holds raw state that another thread might touch, the SAFETY comment must name the synchronization mechanism + the only public deref path + why that path is sound.

**Anchors:** E-002 (frankensqlite shm.rs:59-61 dual unsafe impl).

## I11. `from_raw` is paired with `into_raw`/`forget`

Every `Arc::from_raw` / `Box::from_raw` / `Rc::from_raw` is paired elsewhere with `into_raw` or `mem::forget` to balance the refcount lifecycle. Phase 2's refcount-lifecycle bucket sweeper validates the pairing across the full codebase.

**Anchors:** E-004 (RawWaker vtable choreography, asupersync).

## I12. Layout assumptions need compile-time asserts

Every `#[repr(C|transparent|packed|align)]` type ships a `const _: () = assert!(size_of::<T>() == N)` and `const _: () = assert!(align_of::<T>() >= M)`. Catches silent layout regressions when refactoring.

**Anchors:** E-005 (frankentui Cell layout asserts).

## I13. Soak campaigns offload via `rch`

Phase 11 24h-fuzz / multi-day-Miri / 10⁴-loom-iter campaigns dispatch via `rch exec --`. Local runs burn the user's machine and contaminate the local cargo cache.

**Anchors:** the rch skill's "offload anything >5min" guidance.

## I14. Project-shaped UB needs `/idea-wizard`

Off-the-shelf checklists miss project-shape UB: custom allocators, custom self-ref, custom intrusive lists, custom lock-free queues, custom MMIO. Phase 6 always invokes `/idea-wizard` Phase 2 prompt with project narrowing.

**Anchors:** the idea-wizard skill; cass sessions where this caught real bugs.

## I15. Each experiment is falsifiable

An `EXP-NNN` entry without a `**Falsifiability:**` field is a demo, not a test. The synthesizer (Phase 4) and the experiment-designer (Phase 4/6) must produce falsifiable hypotheses — what evidence would refute the claim?

**Anchors:** Q-029 (cass; "always state what would refute the hypothesis").

<!-- KERNEL-END -->

## Disputed

(Items where model distillations disagreed — listed below but NOT in the kernel.)

- **Loom vs. shuttle thresholds.** Opus distillation says "loom for ≤3 threads, ≤1000 iters; shuttle past that". Codex distillation says "shuttle 10⁵ iters is the default; only use loom for ≤2 threads". Gemini distillation says "always start with loom; only switch when loom times out". Until consensus emerges, the skill default is Opus's threshold. ([TOOLING.md §Loom](../../references/TOOLING.md#loom)).

- **Whether `mem::zeroed::<bool>()` is UB.** It is technically *not* UB (0 is a valid bool). But Gemini distillation flags it as `SUSPICIOUS` because it implies sloppy thinking. The skill defaults to flagging only `mem::zeroed::<T>()` where T is non-zero-valid; bool is excluded.

## Unique

(Items only one model distillation surfaced. Not in the kernel; preserved here for future revisit.)

- **(Opus only)** Tree-borrows can produce different verdicts than stacked-borrows on the same code; running both is essential. The skill incorporates this in the MIRIFLAGS matrix.
- **(Codex only)** TSan false-positives are common in libstd traces; suppress with `TSAN_OPTIONS="suppressions=tsan.supp"` rather than treating as real findings. The skill incorporates this in [TROUBLESHOOTING.md §TSan](../../references/TROUBLESHOOTING.md#threadsanitizer-tsan).
- **(Gemini only)** Some UB shapes only manifest under specific LLVM versions; pinning the toolchain version in CI is part of the soundness story. Worth investigating but not yet in the kernel.

---

## Provenance map

| Invariant | Anchors | Distillation cross-reference |
|---|---|---|
| I1 (taxonomy) | Q-001, Q-014, E-001..E-011 | opus + codex + gemini |
| I2 (compose static + dynamic + experimental) | Q-003, Q-007 | opus + codex |
| I3 (convergence) | Q-018 | opus + codex |
| I4 (remediation alternatives) | E-008, Q-021 | opus + codex + gemini |
| I5 (beads test+docs deps) | Q-025, beads-workflow | opus + codex |
| I6 (verbatim fresh-eyes) | doc-website skill | opus + codex |
| I7 (compaction survival) | doc-website skill | opus + codex |
| I8 (no mocks) | AGENTS.md memory | opus + codex + gemini |
| I9 (SAFETY contracts) | E-001 | opus + codex + gemini |
| I10 (manual Send/Sync) | E-002 | opus + codex |
| I11 (from_raw pairing) | E-004 | opus + codex + gemini |
| I12 (compile-time asserts) | E-005 | opus + codex |
| I13 (rch offload) | rch skill | opus + gemini |
| I14 (project-shaped wizard) | idea-wizard skill | opus + codex + gemini |
| I15 (falsifiability) | Q-029 | opus + codex |
