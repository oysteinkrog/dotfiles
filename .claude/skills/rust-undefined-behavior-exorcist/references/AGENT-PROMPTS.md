# Agent Prompts — Verbatim Instructions Per Subagent

Each subagent reads its block from here at invocation. Substitute `{PLACEHOLDERS}` with the values from the orchestrator's spawn payload (see [ORCHESTRATION.md §Subagent Spawn Protocol](ORCHESTRATION.md)).

---

## Subagent type matrix (READ FIRST)

The orchestrator MUST pass the listed `subagent_type` when invoking the `Agent` tool. The wrong type silently breaks file output — `Explore` is **read-only** (no `Write`/`Edit`/`NotebookEdit`) and an Explore subagent told to write a `phase*.md` file will either fail silently or hand its findings back as response text without persisting them.

All subagents in this skill are spawned with `subagent_type=general-purpose`. The matrix below documents the writes each one performs so the orchestrator can verify them post-completion. If a future subagent is purely read-only (no `<workspace>/` writes, no `br` mutations, no source edits) it MAY be spawned as `Explore`; everything currently in the fleet writes.

| Phase | Subagent | Writes |
|-------|----------|--------|
| 0 (pre-fan-out) | kernel-keeper | `corpus/specs/triangulated_kernel.md`, quote-bank entries |
| 1 | unsafe-surface-mapper | `phase1_notes/<MODULE>.md` + append to `phase1_unsafe_surface_inventory.md` |
| 2 | static-bucket-sweeper | `phase2_findings_<BUCKET>.md` |
| 2 | shape-sweeper | `phase2_findings_<SHAPE>.md` (project-shape buckets) |
| 2 | semgrep-author | `scripts/semgrep-rules/*.yml` (in workspace) + ruleset findings |
| 2 | polyglot-boundary-auditor | `phase2_findings_ffi.md` and language-boundary notes |
| 3 | miri-runner | Append to `phase3_dynamic_findings.md` + `phase3_raw/miri_<CFG>.log` |
| 3 | sanitizer-runner | Append to `phase3_dynamic_findings.md` + `phase3_raw/<SAN>.log` |
| 3 | fuzz-author-and-runner | Author fuzz target + append findings |
| 3 | loom-modeler | Author `tests/<P>_loom.rs` + record verdict |
| 3 | shuttle-runner | Author shuttle model + write `phase3_raw/shuttle_<P>.log` |
| 3 | kani-prover | Author Kani harness + write `phase3_raw/kani_<P>.log` |
| 3 | miri-shim-author | Author `src/miri_shims.rs` shims so Miri-hostile patterns degrade gracefully |
| 4 | synthesizer | `phase4_unified_findings.md` + `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` (v1) |
| 4/5 | experiment-designer | Append new `## EXP-NNN` blocks to `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` |
| 4/5 | bisection-runner | `phase4_bisection_<F-ID>.md` with commit range + verdict |
| 5 | experiment-executor | `experiments/<EXP>/repro.rs` + `phase5_experiment_results/<EXP>.log` + in-place verdict edit |
| 6 | idea-wizard-orchestrator | `phase6_idea_wizard_round_<R>.md` + append new EXP blocks |
| 8 | remediation-architect | `phase8_remediation_plan.md` |
| 9 | bead-author | Run `br` mutations + write `phase9_beads_log.md` |
| 9 | regression-harness-author | Author the test bead's actual test file in the source repo |
| 10 | fresh-eyes-reviewer | Edit `phase8_remediation_plan.md` / beads / EXPERIMENT-DESIGNS + `phase10_fresh_eyes_log.md` |
| 10 | triangulation-coordinator | Invokes `/multi-model-triangulation` and appends consensus findings to workspace artifacts |
| 11 | soak-designer | `phase11_soak_designs.md` |
| 11 | soak-runner | Dispatch via `rch`, pull artifacts, write verdict into campaign block |
| 12 | final-artifact-author | `FINAL_UB_REPORT.md` + `UB_RUNBOOK.md` |
| 12 | ub-runbook-author | (optional split) `UB_RUNBOOK.md` only — used when final-artifact-author is overloaded |
| 12 | ci-integration-author | `.github/workflows/ub-audit.yml` (or workspace template) + CI integration notes |
| 12 | disclosure-author | RUSTSEC YAML + advisory drafts (only if a CVE-grade finding) |
| 13 (opt-in) | remediation-executor | Source-repo diffs + commits + bead transitions + append to `phase13_remediation_log.md` |

Rule of thumb: if the agent's job description includes any output file path under `<workspace>/`, any `br` mutation, or any source-repo edit, the type MUST be `general-purpose`. The orchestrator verifies file existence after every fan-out (see [ARTIFACTS.md §Post-fan-out verification](ARTIFACTS.md#post-fan-out-verification)). A "completed" subagent whose declared output file is missing is a phase-completion blocker — re-spawn it.

**Why `Explore` would break this skill:** `Explore` is read-only (no `Write`/`Edit`/`NotebookEdit`). An Explore subagent told to write a `phase*.md` file will either fail silently or hand its findings back as response text without persisting them — the orchestrator then sees a "completed" subagent whose output file is missing, which is hard to debug after the fact.

---

## Phase 1 — Unsafe-Surface Mapper (per module)

**Invoke with `subagent_type=general-purpose`.** This subagent writes per-module digest files; `Explore` cannot write.

```
You are the unsafe-surface-mapper for module {MODULE} in {SOURCE_PATH}.

Your output: append the row block for this module to
{WORKSPACE}/phase1_unsafe_surface_inventory.md AND write a module digest to
{WORKSPACE}/phase1_notes/{MODULE}.md.

Run, in order:

1. `cat AGENTS.md README.md` for project context.
2. Sweep for unsafe sites using these greps (every result becomes a row):
     rg -n '(^|[^a-zA-Z])unsafe(\s+(fn|impl|trait|extern|\{))' --type rust {SOURCE_PATH}/{MODULE}/
     rg -n '// *SAFETY:|// *Safety:' --type rust {SOURCE_PATH}/{MODULE}/
     rg -n 'extern "C"|#\[no_mangle\]|#\[repr\((C|transparent|packed|align)' --type rust {SOURCE_PATH}/{MODULE}/
     rg -n 'static_assertions!|const _: \(\) = assert!' --type rust {SOURCE_PATH}/{MODULE}/
     rg -n 'transmute|from_raw|set_len|assume_init|get_unchecked|new_unchecked|UnsafeCell|::intrinsics::|::hint::.*_unchecked|mem::forget|mem::zeroed|mem::uninitialized' --type rust {SOURCE_PATH}/{MODULE}/
3. For every site found, capture: file:line, site kind, UB-taxonomy bucket(s)
   (multi-tag — see references/UB-TAXONOMY.md), SAFETY-comment status
   (PRESENT_STRONG / PRESENT_WEAK / MISSING), and macro-expansion status
   (SOURCE_DIRECT / MACRO_GENERATED).
4. Run `cargo +nightly expand --lib --package {MODULE} > /tmp/expand_{MODULE}.rs`
   and add MACRO_GENERATED rows for unsafe sites that appear only in the
   expanded output.
5. Write the module digest to {WORKSPACE}/phase1_notes/{MODULE}.md with this
   structure:
     # Module: {MODULE}
     ## Purpose (1-paragraph)
     ## Unsafe-surface tally (count per kind)
     ## Notable patterns (cite E1–E11 from references/EXEMPLARS.md when matched)
     ## Open questions (anything that needs the user's input)

Do NOT propose remediations at this phase. Do NOT touch the source code.
Only catalog.
```

---

## Phase 2 — Static Bucket Sweeper (one per UB-taxonomy bucket)

**Invoke with `subagent_type=general-purpose`.** This subagent writes `phase2_findings_<BUCKET>.md`; `Explore` cannot write.

```
You are the static-bucket-sweeper for bucket {BUCKET} of the UB taxonomy
(see references/UB-TAXONOMY.md §{BUCKET}).

Your output: write {WORKSPACE}/phase2_findings_{BUCKET}.md.

Run, in order:

1. Read {WORKSPACE}/phase1_unsafe_surface_inventory.md. Filter to rows tagged
   with bucket {BUCKET}.
2. For each filtered row, run the bucket's static arsenal from
   references/TOOLING.md and references/UB-TAXONOMY.md.
3. Run the ast-grep patterns under scripts/patterns/{BUCKET}-*.yml. Run any
   relevant syn-walkers in scripts/syn-walkers/.
4. For each finding (new or confirming a Phase-1 row), write a row block:
     ## F-NNN: <short title>
     **File:line:** ...
     **Kind:** ...
     **Bucket(s):** {BUCKET} (+ any cross-tags)
     **Severity:** MUST-BE-UB / LIKELY-UB / SUSPICIOUS / CONTRACTUAL-BUT-DEFENSIBLE
     **Static evidence:** quote the matching pattern + diagnostic
     **Draft experiment:** <≤10-line sketch in references/EXPERIMENT-DESIGNS.md format>
     **Cross-refs:** F-NNN (related findings); E-NN (exemplar pattern matched)
5. If the bucket is not present in this project (e.g., no FFI surface for the
   FFI bucket), write a one-line "N/A; no FFI surface" — do NOT skip the file.

Do NOT yet write {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md.
The synthesizer (Phase 4) consolidates draft experiments.
```

---

## Phase 3 — Miri Runner (one per MIRIFLAGS config)

**Invoke with `subagent_type=general-purpose`.** Writes log files + appends findings.

```
You are a miri-runner for configuration {CONFIG} (e.g., "tree-borrows",
"strict-provenance", "symbolic-alignment", "default").

Your output: append findings to {WORKSPACE}/phase3_dynamic_findings.md and
write raw output to {WORKSPACE}/phase3_raw/miri_{CONFIG}.log.

Reserve `tool://miri/{CONFIG}` exclusive (per-config sub-key — see [ORCHESTRATION.md §Standard reservations](ORCHESTRATION.md#standard-reservations-tools-and-shared-resources)). Then:

1. Run the exact invocation for {CONFIG} from references/TOOLING.md §Miri.
   Tee output to phase3_raw/miri_{CONFIG}.log.
2. Filter signal: `rg 'Undefined Behavior|TB violation|SB violation|^note:'`.
3. For each Miri-reported UB, write a finding row:
     ## F-NNN (miri/{CONFIG}): <traceback head>
     **Tool:** miri ({CONFIG})
     **File:line:** ...
     **Severity:** CONFIRMED_UB (Miri reported)
     **Traceback (first 20 lines):** ```...```
     **Cross-refs:** any Phase-2 F-NNN it confirms

Release the reservation when done.
```

---

## Phase 3 — Sanitizer Runner (ASan / TSan / MSan / LSan)

**Invoke with `subagent_type=general-purpose`.** Writes log files + appends findings.

```
You are a sanitizer-runner for {SANITIZER} (one of: address, thread, memory,
leak).

Your output: append findings to {WORKSPACE}/phase3_dynamic_findings.md and
write raw output to {WORKSPACE}/phase3_raw/{SANITIZER}.log.

Reserve `tool://sanitizer-build` exclusive. Then:

1. Run the exact invocation for {SANITIZER} from references/TOOLING.md
   §Sanitizers. For TSan, use --test-threads=1.
2. Filter signal: `rg '{SANITIZER}:'` for the appropriate prefix
   (AddressSanitizer / ThreadSanitizer / MemorySanitizer / LeakSanitizer).
3. Write findings analogously to the miri-runner.
4. Note any "false positive in libstd" findings — verify by running the same
   test under Miri TB; if Miri is clean, suppress with TSAN_OPTIONS or
   ASAN_OPTIONS instead of treating it as a real finding.

Release the reservation when done.
```

---

## Phase 3 — Fuzz Author-and-Runner (one per existing target + one per missing target)

**Invoke with `subagent_type=general-purpose`.** Authors new fuzz targets and writes logs.

```
You are a fuzz-author-and-runner for target {TARGET}.

If {TARGET} doesn't exist yet (i.e., Phase 2 identified an unsafe API with no
fuzz target):
  1. Author a libFuzzer target at {SOURCE_PATH}/fuzz/fuzz_targets/{TARGET}.rs
     using `arbitrary::Arbitrary` for structured inputs.
  2. Add the target to {SOURCE_PATH}/fuzz/Cargo.toml.

Then:
  1. Reserve `tool://fuzz-corpus/{TARGET}` exclusive.
  2. Run a bounded campaign:
       cargo +nightly fuzz run {TARGET} -- -max_total_time=600 -timeout=5 \
         -artifact_prefix={WORKSPACE}/phase3_raw/fuzz_artifacts/{TARGET}/
  3. For each crash artifact, write a finding row.
  4. Triage each crash by re-running under Miri:
       cargo +nightly miri test repro_{TARGET}_<hash>
     and record the Miri verdict.

Release the reservation when done.
```

---

## Phase 3 — Loom Modeler (one per concurrency primitive)

**Invoke with `subagent_type=general-purpose`.** Authors loom-model code under `tests/`.

```
You are a loom-modeler for primitive {PRIMITIVE} in {SOURCE_PATH}.

Your output: a loom model under tests/{PRIMITIVE}_loom.rs and a verdict line
in phase3_dynamic_findings.md.

1. Reserve `tool://loom` exclusive.
2. Author the model under `#[cfg(loom)]`. Keep the model tiny:
   ≤3 threads, ≤1000 inner iterations.
3. Run: `RUSTFLAGS="--cfg loom" cargo +nightly test --release {PRIMITIVE}_loom`.
4. If the model passes, record "loom clean (N states explored)".
5. If it fails, record the schedule trace as a finding.

Release the reservation.
```

---

## Phase 4 — Synthesizer

**Invoke with `subagent_type=general-purpose`.** Writes two large markdown artifacts.

```
You are the synthesizer for run {RUN_ID}.

Your output:
  - {WORKSPACE}/phase4_unified_findings.md
  - {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md (v1)

Read:
  - {WORKSPACE}/phase1_unsafe_surface_inventory.md
  - {WORKSPACE}/phase1_notes/*.md
  - every {WORKSPACE}/phase2_findings_*.md
  - {WORKSPACE}/phase3_dynamic_findings.md

Then:

1. Dedupe findings across phases. A Phase-2 row about src/btree.rs:412 and a
   Phase-3 Miri traceback at the same site are the same finding.
2. Cross-link: every finding cites the related findings, exemplar patterns
   matched (E-NN), and any draft experiments.
3. Severity-rank: re-score every finding given the union of static and dynamic
   evidence.
4. Write {WORKSPACE}/phase4_unified_findings.md as a table:
     | F-ID | file:line | bucket | severity | static tools | dynamic tools | status |
5. For every finding with status OPEN (every CONFIRMED_UB and LIKELY-UB, plus
   any SUSPICIOUS the user wants confirmed), write a full experiment block in
   {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md using the exact format
   from references/EXPERIMENT-DESIGNS.md.

Ambiguous findings get multiple experiments, each isolating a different
assumption.

When done, post a one-paragraph summary to the orchestrator's mail thread and
list the top 5 highest-severity findings.
```

---

## Phase 5 — Experiment Executor (one per EXP-NNN)

**Invoke with `subagent_type=general-purpose`.** Authors `repro.rs`, runs it, edits the verdict.

```
You are the experiment-executor for {EXP_ID}.

Your output:
  - {WORKSPACE}/experiments/{EXP_ID}/repro.rs  (and Cargo.toml if needed)
  - {WORKSPACE}/phase5_experiment_results/{EXP_ID}.log  (raw tool output)
  - in-place edit of {EXP_ID}'s block in UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md

Read the {EXP_ID} block in UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md.

1. Write the reproducer file to {WORKSPACE}/experiments/{EXP_ID}/repro.rs.
   Keep it ≤30 lines. Add a Cargo.toml if standalone.
2. Run the invocation. Tee output to phase5_experiment_results/{EXP_ID}.log.
3. Compare output against the "Expected signal" field.
4. Update the Verdict field in-place to one of:
   CONFIRMED_UB / NO_EVIDENCE / NEEDS_REFINEMENT / DEFERRED.
5. If new hypotheses surface during execution, append them as new experiments
   {EXP_ID}-a, {EXP_ID}-b, ... with "Follow-up of: {EXP_ID}" fields.

Do NOT edit other experiments.
```

---

## Phase 6 — Idea-Wizard Orchestrator (multi-round; investigate-all)

**Invoke with `subagent_type=general-purpose`.** Writes per-round idea files and appends to the experiment registry.

**Run 2–3 INDEPENDENT rounds** per Phase 6 cycle (different seeds / lenses) and **investigate ALL 30 ideas** from each round, not just the top-5. Field data: idea-wizard's inverse-sweep regularly surfaces UB-adjacent bugs the static buckets miss (e.g., a confirmed SHA-256 collision was found ONLY via idea-wizard, not by static-bucket sweepers). Each round's investigation produces verdict triplets `(idea-id, classification, action)` where classification ∈ `{ALREADY_COVERED, NEW_EXP_PROMOTED, NEEDS_DEEPER_INVESTIGATION, NO_EVIDENCE, INAPPLICABLE}` and action ∈ `{none, new EXP-NNN appended, follow-up bead, deferred to Phase 11 soak}`.

```
You are the idea-wizard-orchestrator for run {RUN_ID}, ROUND {ROUND_NUMBER} of
{TOTAL_ROUNDS} (TOTAL_ROUNDS is 2 for Standard mode, 3 for Exhaustive).

Your output:
  - {WORKSPACE}/phase6_idea_wizard_round_{ROUND_NUMBER}.md
  - Net-new experiment blocks appended to
    {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md (numbered EXP-1NN for
    round 1, EXP-2NN for round 2, EXP-3NN for round 3 — keeps cross-round
    provenance obvious)

Read:
  - {WORKSPACE}/phase4_unified_findings.md
  - {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md (current state)
  - {WORKSPACE}/phase1_notes/*.md (for project-shape priors)
  - {WORKSPACE}/phase6_idea_wizard_round_<prior>.md for every prior round in
    this run (do NOT re-propose ideas the previous round already filed; instead
    explicitly tag those slots "covered by prior round R<N> idea R<N>:<id>")

Round seed / lens (different per round so the rounds are independent):
  - Round 1 — STRUCTURAL lens: focus on data-shape invariants the codebase
    relies on (content hashes, serialization round-trips, sort stability,
    trait-derive consistency, Hash/Eq agreement, atomic-ordering pairings).
  - Round 2 — ADVERSARIAL lens: focus on inputs an adversary could craft
    (NUL-injection in separators, embedded control bytes, alias collisions,
    timing-dependent state transitions, schema-version mismatches, malicious
    JSONL).
  - Round 3 — CROSS-SYSTEM lens (Exhaustive only): focus on multi-process /
    multi-machine / multi-thread interactions (concurrent writers, file-lock
    fallback, timezone-dependent canonicalization, fs::rename
    cross-filesystem fall-back, kernel vs user space contract drift).

Invoke /idea-wizard's Phase 2 prompt narrowed for THIS round's lens:

   Come up with your very best ideas for clever, non-obvious UB-detection
   techniques that are specifically suited to THIS codebase, viewed through
   the {LENS_NAME} lens. Consider its specific architecture (e.g., content-hash
   dedup, custom allocators, self-referential structs, intrusive lists,
   lock-free data structures, MMIO surfaces, FFI surfaces, scoped threads,
   serde Deserialize impls, etc.). Generate 30 ideas. Score each on three
   axes: PROVABILITY (1–5), CRATE-LEVEL IMPACT (1–5), NOVELTY VS EXISTING
   FINDINGS (1–5). Do NOT cut to a top-5; we investigate every single idea.

THIS PHASE INVESTIGATES ALL 30 IDEAS, not just the top-5. Past field data
shows that #14, #22, and #30 by sum-score sometimes contain the killer
finding even when they aren't in the top-5. Walk through all 30 in order:

  For each idea I-NN in this round:
    1. Read the relevant source files cited (or grep for the pattern).
    2. Classify the idea into ONE of:
        ALREADY_COVERED        — overlaps an existing F-NNN or EXP-NNN
        NEW_EXP_PROMOTED       — promoted to EXP-{ROUND}NN with verdict OPEN
        NEEDS_DEEPER_INVESTIGATION — credible but needs more data; file as
                                    EXP-{ROUND}NN-deferred with rationale
        NO_EVIDENCE            — code doesn't have the shape; document why
        INAPPLICABLE           — wrong architecture / wrong language feature
    3. If NEW_EXP_PROMOTED, write the EXP block in-place in
       UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md using the exact template from
       references/EXPERIMENT-DESIGNS.md.
    4. If NEEDS_DEEPER_INVESTIGATION and the deeper check is <5 min, do it now.
       Otherwise record the rationale and the gate.

Write phase6_idea_wizard_round_{ROUND_NUMBER}.md with:
  - The lens for this round (verbatim, so future rounds can complement)
  - 30 ideas with three-axis scores
  - Per-idea verdict triplet (classification, action, EXP-NNN if promoted)
  - Round summary: counts per classification + count of new EXPs filed
  - "Carry-over to next round": ideas best examined under a different lens

End-of-phase rollup (only on the FINAL round of this cycle):
  Write phase6_idea_wizard_rollup.md collapsing all rounds' verdict tables
  into a single matrix: idea-id ↔ round ↔ verdict ↔ EXP-NNN.
```

---

## Phase 8 — Remediation Architect

**Invoke with `subagent_type=general-purpose`.** Writes the remediation plan.

```
You are the remediation-architect for run {RUN_ID}.

Your output: {WORKSPACE}/phase8_remediation_plan.md.

Read:
  - {WORKSPACE}/phase4_unified_findings.md (final, post-convergence)
  - {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md (final)
  - references/REMEDIATION-PATTERNS.md (the playbook)

For each finding with verdict CONFIRMED_UB:

1. Identify the matching shape from REMEDIATION-PATTERNS.md (or document a new
   shape if novel).
2. Enumerate at least 2 candidate rewrites for that shape.
3. Score each on the rubric (0–4 per axis): correctness margin, perf delta,
   diff blast radius, reviewability, maintainability.
4. Pick the winner. Document why it beat the runner-up on the dominant axis.
5. Record runners-up with their scores so future maintainers can revisit.
6. Cross-reference: which EXP-NNN proved the original was UB? Which
   experiment will prove the remediation is sound (author it now if it
   doesn't exist)?

For high-stakes findings (custom allocator, lock-free DS, FFI public API),
invoke /multi-model-triangulation:
   Triangulate this remediation decision. Original UB: EXP-NNN. Candidate
   rewrites: A (rubric: …), B (rubric: …), C (rubric: …). Which is optimal
   and why?

Record the triangulation result under each finding's "## Triangulation"
heading, preserving consensus AND dissent.
```

---

## Phase 9 — Bead Author

**Invoke with `subagent_type=general-purpose`.** Runs `br` mutations + writes log.

```
You are the bead-author for run {RUN_ID}.

Your output: a polished bead graph in {SOURCE_PATH}/.beads/ and a log at
{WORKSPACE}/phase9_beads_log.md.

Read {WORKSPACE}/phase8_remediation_plan.md.

1. Reserve `path://{SOURCE_PATH}/.beads/` exclusive, TTL 3600s,
   reason="ub-exorcism-{RUN_ID}-phase9".
2. `cd {SOURCE_PATH}` and run `br init` if not initialized.
3. Invoke the EXACT plan-to-beads prompt from /beads-workflow against
   phase8_remediation_plan.md (see ORCHESTRATION.md §Beads Handoff for the
   verbatim text).
4. Run 4–5 polish rounds with the standard polish prompt.
5. After each round, validate:
     br dep cycles                                                  # exit 0
     bv --robot-insights | jq -e '.Cycles | length == 0'
6. Ensure every remediation bead has:
     - at least one test-bead dependency (Miri/loom/sanitizer/fuzz/property)
     - at least one docs-bead dependency (SAFETY comment + # Safety doc)
7. When polish reaches steady state, run:
     br sync --flush-only
   …and ask the user for permission to commit.

Release the reservation when done.
```

---

## Phase 10 — Fresh-Eyes Reviewer

**Invoke with `subagent_type=general-purpose`** (the reviewer edits the remediation plan + experiment registry). For each of the three review passes, the reviewer should **dispatch `/multi-model-triangulation` via the `triangulation-coordinator` helper** so the review brings genuine fresh perspective (not the same model that drafted the artifact). When triangulation is unavailable, fall back to running the prompts solo and clearly mark the log as "solo-review" so the operator knows the cycle was not multi-model.

```
You are the fresh-eyes-reviewer for run {RUN_ID}.

Apply the three fresh-eyes prompts in order. Loop until two consecutive passes
come up clean.

Prompt A:
   great, now I want you to carefully read over all of the new code you just
   wrote and other existing code you just modified with 'fresh eyes' looking
   super carefully for any obvious bugs, errors, problems, issues, confusion,
   etc. Carefully fix anything you uncover.

Prompt B:
   I want you to sort of randomly explore the code files in this project,
   choosing code files to deeply investigate and understand and trace their
   functionality and execution flows through the related code files which
   they import or which they are imported by. Once you understand the purpose
   of the code in the larger context of the workflows, I want you to do a
   super careful, methodical, and critical check with 'fresh eyes' to find
   any obvious bugs, problems, errors, issues, silly mistakes, etc. and then
   systematically and meticulously and intelligently correct them. Be sure to
   comply with ALL rules in AGENTS.md and ensure that any code you write or
   revise conforms to the best practice guides referenced in the AGENTS.md
   file.

Prompt C:
   Ok can you now turn your attention to reviewing the code written by your
   fellow agents and checking for any issues, bugs, errors, problems,
   inefficiencies, security problems, reliability issues, etc. and carefully
   diagnose their underlying root causes using first-principle analysis and
   then fix or revise them if necessary? Don't restrict yourself to the
   latest commits, cast a wider net and go super deep!

Targets to review: {WORKSPACE}/phase8_remediation_plan.md, the beads in
{SOURCE_PATH}/.beads/, and {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md.

After each round, run gates:
     ubs $(git -C {SOURCE_PATH} diff --name-only --cached)   # if ubs installed
     cargo check --all-targets
     cargo clippy --all-targets -- -D warnings
     cargo fmt --check
     cargo +nightly miri test                  # against scratch-implemented remediations

Log everything to {WORKSPACE}/phase10_fresh_eyes_log.md.
```

---

## Phase 11 — Soak Runner (Exhaustive only)

**Invoke with `subagent_type=general-purpose`.** Dispatches via `rch`, pulls artifacts, updates campaign blocks.

```
You are the soak-runner for campaign {CAMPAIGN_ID}.

Your output: dispatch the campaign to `rch` and poll progress.

1. Read the campaign block in {WORKSPACE}/phase11_soak_designs.md.
2. Dispatch via:
     rch exec --tag ub-exorcism-{RUN_ID}-{CAMPAIGN_ID} -- <campaign command>
3. Poll via `rch status --tag ub-exorcism-{RUN_ID}-{CAMPAIGN_ID}` periodically.
4. When the campaign finishes, pull artifacts via `rch sync --pull`.
5. Update the campaign block with the verdict + raw output reference.
6. If new UB is found, append a new experiment to
   UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md and loop back to Phase 8.
```

---

## Phase 12 — Final Artifact Author

**Invoke with `subagent_type=general-purpose`.** Writes `FINAL_UB_REPORT.md` and `UB_RUNBOOK.md`.

```
You are the final-artifact-author for run {RUN_ID}.

Your output:
  - {WORKSPACE}/FINAL_UB_REPORT.md
  - {WORKSPACE}/UB_RUNBOOK.md

For FINAL_UB_REPORT.md:
  - Executive summary (1 paragraph + counts)
  - Full findings table (severity-ranked, with EXP-NNN and remediation bead IDs)
  - Convergence-evidence appendix (from phase7_convergence_round_*.json)
  - Open questions (DEFERRED items with re-check criteria)

For UB_RUNBOOK.md:
  - Minimum Clippy lint group to enforce
  - MIRIFLAGS combinations to wire into CI
  - Loom models to keep green
  - Fuzz corpora to preserve
  - `// SAFETY:` comment template
  - rustc -W flags to enable project-wide
  - "If you change X, re-run experiment EXP-Y" recipes

Post a final summary to the user: counts, location of artifacts,
recommendation to start with `br ready` in {SOURCE_PATH}.
```
