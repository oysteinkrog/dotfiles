# Jargon — Terms This Skill Uses

When you read `phase2_findings_aliasing.md` or `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`, the vocabulary here is what each term means *in this skill's context*. Names from the broader Rust community keep their meaning; project-specific terms are flagged.

---

## A

**Aliasing model** — Rust's rules about which references can co-exist. `&T` shares; `&mut T` is unique; raw pointers don't care but their derefs must obey the rules of whatever borrow gave them life.

**Anchor** *(project term)* — a stable identifier for a quote in [EXEMPLARS.md](EXEMPLARS.md) (`E-001`) or a quote in `corpus/quote_bank/` (`Q-001`). Used to cite sources in operator cards and remediation rationales.

**Audit boundary** — the line between source files and audit artifacts. The workspace is inside the source project at `.ub-exorcism/<run-id>/`; the skill writes there, touches `.beads/` only with permission, and never edits other source files automatically.

## B

**Beads** — issue-tracking system used to convert remediations into actionable work. See `/beads-workflow`. Always `br` (CLI), never bare `bv` (TUI).

**Bucket** *(project term)* — one of the 25 UB-taxonomy categories in [UB-TAXONOMY.md](UB-TAXONOMY.md). Findings are tagged with one or more buckets; Phase 2 spawns one subagent per bucket.

## C

**CONFIRMED_UB** *(project term)* — verdict on an experiment whose expected signal was observed. Tracked in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`.

**Convergence** *(project term)* — the loop exit condition: two consecutive rounds with <3 new findings AND zero OPEN/NEEDS_REFINEMENT AND ≥10 rounds total. Measured by `scripts/convergence-tracker.sh`.

**Corpus** — the directory `corpus/` in the workspace AND in this skill, holding primary sources (cass quotes, exemplar code) and triangulated kernel. From `/operationalizing-expertise`.

## D

**DEFERRED** *(project term)* — verdict on an experiment that's been explicitly punted with rationale and re-check criteria. Counts toward convergence as "resolved".

**Distillation** — model-specific notes derived from a corpus reading, under `corpus/distillations/{opus,codex,gemini}/` (subdirs exist as placeholders; populated when distillation rounds are actually run). Inputs to the triangulated kernel.

**Dynamic sweep** — Phase 3. Runs Miri / sanitizers / loom / shuttle / fuzz against the project to surface UB observable at runtime (vs. static sweep, which is pattern-based).

## E

**Experiment** *(project term)* — an entry in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`. Has ID `EXP-NNN`, hypothesis, reproducer, expected signal, falsifiability, invocation, verdict.

**Exemplar** — a mined pattern from `/dp/*` projects with stable anchor `E-NN`. Lives in [EXEMPLARS.md](EXEMPLARS.md).

## F

**Falsifiability** *(experiment field)* — what evidence would refute the hypothesis. An experiment without this is a demo, not a test.

**Finding** *(project term)* — a row in `phase4_unified_findings.md`. Has ID `F-NNN`, file:line, bucket(s), severity, status. May have ≥1 associated experiment.

**Fresh-eyes** — Phase 10. The three verbatim review prompts adapted from the documentation-website skill. Loops until two consecutive clean passes.

## H

**Hypothesis** *(experiment field)* — the falsifiable claim. One sentence. The experiment's job is to confirm or refute.

## I

**Idea-wizard round** — Phase 6. Invokes `/idea-wizard` Phase-2 prompt with project narrowing to surface UB-detection techniques specific to *this* codebase's shape.

**Isomorphic rewrite** *(project term)* — a remediation candidate that preserves the original behavior modulo UB. Phase 8 enumerates ≥2 per CONFIRMED_UB finding.

## K

**Kernel** — `corpus/specs/triangulated_kernel.md`. Marker-bounded (KERNEL-START / KERNEL-END), parseable, contains only consensus content across model distillations. From `/operationalizing-expertise`.

## L

**LIKELY-UB** *(severity)* — strong static signal that the site is UB, but dynamic confirmation is the arbiter.

**Loom** — exhaustive interleaving explorer for concurrent code. Use for ≤3 threads, ≤1000 inner iterations. See [TOOLING.md §Loom](TOOLING.md#loom).

## M

**MIRIFLAGS matrix** *(project term)* — the standard set of `MIRIFLAGS` configurations the skill runs: `default` (SB), `tree-borrows`, `strict-provenance`, `symbolic-alignment`. Modern Miri checks invalid enum/scalar values in plain runs; do not add the obsolete `-Zmiri-check-number-validity` flag. See `scripts/run-miri-matrix.sh`.

**MUST-BE-UB** *(severity)* — sound static analysis says this *is* UB; experiment will confirm shape.

## N

**NEEDS_REFINEMENT** *(verdict)* — the experiment surfaced a partial signal but a new variable appeared. Spawn a follow-up `EXP-NNN-a` to isolate. Counts against convergence.

**NO_EVIDENCE** *(verdict)* — clean run; the experiment did not produce the expected signal. Demote the finding's severity. Counts toward convergence.

## O

**Operator** *(project term)* — a named cognitive move (★ SUSPECT, ✦ ISOLATE, ◐ REPRO, ⬡ INSTRUMENT, ⚠ ESCALATE, ⊕ REWRITE, ⊙ DEBOUNCE-FALSE-POSITIVE, ⊞ SOAK, ⌘ REDUCE, ◇ TRIAGE, ⊛ STRESS, ✕ INVALIDATE, ⊢ PROVE, ⟂ ORTHOGONALIZE, ⌗ DECOMPOSE). Each has triggers, prompt module, exit criteria. See [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md).

**OPEN** *(verdict)* — experiment hasn't run yet. Convergence forbids this state across two quiet rounds.

## P

**Partition** *(project term)* — Phase 0 step where the main agent breaks the source repo into sections that map to subagents.

**Phase** — one of the 12 stages in the loop. See [PHASES.md](PHASES.md).

**Provenance** — a pointer's identity (which allocation it came from). `int → ptr` casts lose provenance under strict-provenance rules.

## Q

**Quiet round** *(project term)* — a Phase-7 round where <3 new findings emerged AND zero OPEN/NEEDS_REFINEMENT remain. Two consecutive quiet rounds = convergence.

**Quote bank** — `corpus/quote_bank/quote_bank.md`. Stable-anchored quotes from primary sources. From `/operationalizing-expertise` Track A.

## R

**Reservation** — an MCP Agent Mail file/tool lock. The skill reserves `tool://miri/<config>`, `tool://loom`, `tool://fuzz-corpus/<target>`, etc. See [ORCHESTRATION.md](ORCHESTRATION.md).

**Round** *(project term)* — one iteration of Phases 2–6. Tracked via `phase7_convergence_round_<N>.json`.

**Runbook** *(project term)* — `UB_RUNBOOK.md`. The Phase-12 deliverable describing how the maintainer keeps the project UB-free going forward.

## S

**Sanitizer matrix** *(project term)* — ASan, TSan, MSan, LSan. Each is mutually exclusive in a single build; never combine.

**SAFETY comment** — `// SAFETY:` block immediately preceding an `unsafe { … }` block. Documents the invariants the unsafe op depends on.

**Severity** *(finding field)* — one of `MUST-BE-UB` / `LIKELY-UB` / `SUSPICIOUS` / `CONTRACTUAL-BUT-DEFENSIBLE`.

**Shape** *(remediation term)* — a recurring UB pattern (self-ref struct, intrusive list, lock-free queue, etc.) that has a remediation playbook in [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md).

**Shuttle** — probabilistic concurrent-schedule explorer; loom's faster cousin.

**Soak** *(project term)* — Phase 11 long-running campaign (24h fuzz, multi-day Miri, 10⁴+ loom iters).

**Static sweep** — Phase 2. Runs ast-grep / clippy / syn walkers / cargo-geiger to surface candidate UB without running code.

**SUSPICIOUS** *(severity)* — pattern-match flag; may be false positive. Use `⊙ DEBOUNCE-FALSE-POSITIVE` before closing as NO_EVIDENCE.

**Synthesizer** — Phase 4 single agent that dedupes Phase 1–3 outputs and writes the first `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`.

## T

**Taxonomy** — the 25-bucket catalog of UB shapes the skill operates over. See [UB-TAXONOMY.md](UB-TAXONOMY.md).

**Tree borrows (TB)** — Miri's strictest aliasing model. Catches violations stacked borrows (SB) misses. Always run as part of the MIRIFLAGS matrix.

**Triangulation** — invoking `/multi-model-triangulation` for a high-stakes decision; recording consensus and dissent in the workspace.

## U

**Unsafe surface inventory** — `phase1_unsafe_surface_inventory.md`. Catalogues every `unsafe { ... }`, `unsafe fn`, `unsafe impl`, FFI decl, `static_assertions!`, atomic op, manual Drop, manual Send/Sync.

## V

**Verdict** *(experiment field)* — `OPEN` / `CONFIRMED_UB` / `NO_EVIDENCE` / `NEEDS_REFINEMENT` / `DEFERRED`. `convergence-tracker.sh` greps for these exact strings.

## W

**Workspace** — the in-project directory `<source>/.ub-exorcism/<run-id>/`. Holds every phase artifact and is the source of truth across compaction.
