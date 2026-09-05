# Kickoff Prompts — Verbatim Templates The Orchestrator Sends

Per `/operationalizing-expertise` Track B: every session/phase starts with a kickoff prompt that establishes role + context + deliverables deterministically. Templates here. Substitute `{placeholders}` before sending.

---

## K1 — Run kickoff (orchestrator → user, after up-front confirmations)

```
I'm about to start a Rust UB exorcism on {project_path}.

  Mode:       {Quick | Standard | Exhaustive}
  Workspace:  {project_path}/.ub-exorcism/{run_id}/
  Offload:    {local | rch}
  Run ID:     {YYYY-MM-DD-slug-N}

The 12-phase loop (see references/PHASES.md):
  1. RECON — unsafe-surface inventory
  2. STATIC SWEEP — per-bucket findings
  3. DYNAMIC SWEEP — miri/sanitizers/loom/shuttle/fuzz
  4. SYNTHESIS — unified findings + first experiment registry
  5. EXPERIMENT EXECUTION — verdicts inline
  6. IDEA-WIZARD — project-shaped UB techniques
  7. ITERATE 2–6 — until convergence (≥10 rounds, two quiet)
  8. REMEDIATION DESIGN — ≥2 candidates per finding, rubric-scored
  9. BEADS HANDOFF — beads-workflow convert + polish 4–5x
  10. FRESH EYES — 3 verbatim review prompts, twice clean
  11. SOAK (Exhaustive) — 24h fuzz, multi-day miri, etc.
  12. FINAL ARTIFACTS — UB report + UB runbook + bead graph

Convergence criteria are non-negotiable. The in-project workspace is the source of truth across compaction. You'll see periodic status posts; ask me anything any time.

Starting Phase 0 now.
```

---

## K2 — Subagent kickoff (orchestrator → unsafe-surface-mapper for module {MODULE})

```
You are the unsafe-surface-mapper for module {MODULE} of {SOURCE_PATH} in run {RUN_ID}.

Read references/AGENT-PROMPTS.md §Phase 1 verbatim and execute. Your outputs:
  - Append rows to {WORKSPACE}/phase1_unsafe_surface_inventory.md
  - Write {WORKSPACE}/phase1_notes/{MODULE}.md (digest)

Quality gates:
  - Every `unsafe` keyword in this module has either a row or a documented-FP explanation
  - Every row has a UB-taxonomy bucket tag
  - SAFETY-comment status recorded per unsafe block
  - cargo expand ran; macro-generated unsafe captured

Time budget: 15-30 min.

Coordination thread: ub-exorcism-{RUN_ID}-phase1-{MODULE}.
Mail-channel reservation: none (read-only).

When done, post a one-paragraph summary to the thread and tag @orchestrator.
```

---

## K3 — Subagent kickoff (static-bucket-sweeper for bucket {BUCKET})

```
You are the static-bucket-sweeper for UB-taxonomy bucket {BUCKET} in run {RUN_ID}.

Read:
  - references/UB-TAXONOMY.md §{BUCKET} for the bucket's contract + common shapes + arsenal
  - {WORKSPACE}/phase1_unsafe_surface_inventory.md — filter to rows tagged {BUCKET}
  - references/AGENT-PROMPTS.md §Phase 2 for the workflow

Run the bucket's static arsenal:
  - ast-grep patterns: scripts/patterns/{BUCKET}-*.yml
  - syn walkers: scripts/syn-walkers/src/bin/{BUCKET}.rs (where applicable; run via `cargo run --manifest-path scripts/syn-walkers/Cargo.toml --bin {BUCKET} -- <src>`)
  - clippy lints: as listed in TOOLING.md for this bucket

Output: {WORKSPACE}/phase2_findings_{BUCKET}.md with one ## F-NNN block per finding. Format:

  ## F-NNN: <short title>
  **File:line:** ...
  **Kind:** ...
  **Bucket(s):** {BUCKET} (+ cross-tags)
  **Severity:** MUST-BE-UB | LIKELY-UB | SUSPICIOUS | CONTRACTUAL-BUT-DEFENSIBLE
  **Static evidence:** <quoted pattern match + diagnostic>
  **Draft experiment:** <≤10-line sketch in EXPERIMENT-DESIGNS.md format>
  **Cross-refs:** F-NNN (related); E-NN (exemplar matched)

If the bucket is N/A for this project (e.g., no FFI surface), write a single line saying so — do NOT skip the file.

Time budget: 30-60 min.

Coordination thread: ub-exorcism-{RUN_ID}-phase2-{BUCKET}.
Mail reservation: none.

Severity calibration is in UB-TAXONOMY.md §Bucket Severity Calibration. Don't inflate.
```

---

## K4 — Subagent kickoff (miri-runner for config {CONFIG})

```
You are the miri-runner for configuration {CONFIG} in run {RUN_ID}.

Run the exact invocation from TOOLING.md §"The MIRIFLAGS matrix (run all four)" for {CONFIG}. Tee output to {WORKSPACE}/phase3_raw/miri_{CONFIG}.log. Filter signal: rg 'Undefined Behavior|TB violation|SB violation|^note:'.

For each Miri-reported UB, append a finding row to {WORKSPACE}/phase3_dynamic_findings.md:

  ## F-NNN (miri/{CONFIG}): <traceback head>
  **Tool:** miri ({CONFIG})
  **File:line:** ...
  **Severity:** CONFIRMED_UB
  **Traceback (first 20 lines):** ```...```
  **Cross-refs:** Phase-2 F-NNN it confirms

Reservation: tool://miri/{CONFIG} exclusive, TTL 3600s. Release when done.

Coordination thread: ub-exorcism-{RUN_ID}-phase3-miri-{CONFIG}.

Pitfalls (see TROUBLESHOOTING.md §Miri):
  - If Miri reports "unsupported operation: can't call foreign function", add a #[cfg(miri)] shim — do NOT silently skip the test.
  - If Miri runs forever, scope to --lib or to a single test.
```

---

## K5 — Subagent kickoff (experiment-executor for EXP-{ID})

```
You are the experiment-executor for {EXP_ID} in run {RUN_ID}.

Read the ## {EXP_ID} block in {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md.

Workflow:
  1. Write the reproducer to {WORKSPACE}/experiments/{EXP_ID}/repro.rs (and Cargo.toml if standalone). ≤30 lines.
  2. Reserve path://{WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md exclusive, TTL 5min, only while editing the verdict.
  3. Run the invocation. Tee to {WORKSPACE}/phase5_experiment_results/{EXP_ID}.log.
  4. Compare output against the "Expected signal" field.
  5. Update the Verdict in-place to one of: CONFIRMED_UB | NO_EVIDENCE | NEEDS_REFINEMENT | DEFERRED. Use the exact string — convergence-tracker.sh greps for it.
  6. If new hypotheses surface, append new experiments {EXP_ID}-a, {EXP_ID}-b, ... with "Follow-up of: {EXP_ID}" field.

Time budget: 5–30 min depending on experiment shape.

Coordination thread: ub-exorcism-{RUN_ID}-phase5-{EXP_ID}.
```

---

## K6 — Subagent kickoff (synthesizer, Phase 4)

```
You are the synthesizer for run {RUN_ID}.

Read everything:
  - {WORKSPACE}/phase1_unsafe_surface_inventory.md
  - {WORKSPACE}/phase1_notes/*.md
  - every {WORKSPACE}/phase2_findings_*.md
  - {WORKSPACE}/phase3_dynamic_findings.md

Write:
  - {WORKSPACE}/phase4_unified_findings.md — deduped table, severity-ranked
  - {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md (v1) — one experiment per OPEN finding using the exact format from EXPERIMENT-DESIGNS.md

Dedupe rule: a Phase-2 finding at file:line X and a Phase-3 miri traceback at the same site are the same finding. Merge with cross-refs preserved.

Severity re-score: every change from Phase-2 severity must have a one-line rationale (use the union of static + dynamic evidence).

Ambiguous findings get multiple experiments, each isolating a different assumption.

When done, post a 1-paragraph summary to the orchestrator thread + the top-5 highest-severity findings.

Coordination thread: ub-exorcism-{RUN_ID}-phase4.
Reservation: none (single-writer).
```

---

## K7 — Subagent kickoff (remediation-architect, Phase 8)

```
You are the remediation-architect for run {RUN_ID}.

Read:
  - {WORKSPACE}/phase4_unified_findings.md (final)
  - {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md (final)
  - references/REMEDIATION-PATTERNS.md (playbook)

For each finding with verdict CONFIRMED_UB:

  1. Identify the matching shape from REMEDIATION-PATTERNS.md.
  2. Enumerate ≥2 candidate rewrites for that shape.
  3. Score each on the 5-axis rubric (0-4 per axis).
  4. Pick the winner; document why it beat the runner-up on the dominant axis.
  5. Record runners-up with their scores so future maintainers can revisit.
  6. Cross-reference: EXP-NNN that proved original is UB AND EXP-NNN that will prove the remediation is sound (author it if it doesn't exist).

For high-stakes findings (custom allocator / lock-free DS / FFI public API), invoke /multi-model-triangulation:
  > Triangulate this remediation decision. Original UB: EXP-NNN.
  > Candidate rewrites: A (rubric: ...), B (rubric: ...), C (rubric: ...).
  > Which is optimal and why?

Record triangulation under each finding's `## Triangulation` heading; preserve consensus AND dissent.

Output: {WORKSPACE}/phase8_remediation_plan.md.

Coordination thread: ub-exorcism-{RUN_ID}-phase8.
```

---

## K8 — Subagent kickoff (bead-author, Phase 9)

```
You are the bead-author for run {RUN_ID}.

Reserve path://{SOURCE_PATH}/.beads/ exclusive, TTL 3600s, reason="ub-exorcism-{RUN_ID}-phase9".

cd {SOURCE_PATH} and run `br init` if not initialized.

Invoke /beads-workflow's EXACT Plan-to-Beads prompt verbatim against phase8_remediation_plan.md (reproduced in references/ORCHESTRATION.md §Beads Handoff).

Run 4–5 polish rounds with the standard polish prompt. After each round, validate:
  - br dep cycles      # exit 0, empty output
  - bv --robot-insights | jq -e '.Cycles | length == 0'
  - every remediation bead has ≥1 test-bead dep + ≥1 docs-bead dep

When polish reaches steady state:
  - br sync --flush-only
  - Ask the user for permission to git commit + push.

Log to {WORKSPACE}/phase9_beads_log.md.

Coordination thread: ub-exorcism-{RUN_ID}-phase9.

DO NOT OVERSIMPLIFY. DO NOT LOSE FEATURES.
```

---

## K9 — Subagent kickoff (fresh-eyes-reviewer, Phase 10)

```
You are the fresh-eyes-reviewer for run {RUN_ID}.

Apply Prompts A → B → C in order. After each pass, run gates:
  ubs $(git -C {SOURCE_PATH} diff --name-only --cached)
  cargo check --all-targets
  cargo clippy --all-targets -- -D warnings
  cargo fmt --check
  cargo +nightly miri test  # against scratch-implemented remediations

Targets: {WORKSPACE}/phase8_remediation_plan.md, {SOURCE_PATH}/.beads/, {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md.

Loop until two consecutive passes produce only trivial changes (whitespace, typo, formatting).

Log to {WORKSPACE}/phase10_fresh_eyes_log.md.

Use the prompts VERBATIM from references/AGENT-PROMPTS.md §Phase 10 — do not paraphrase.

Coordination thread: ub-exorcism-{RUN_ID}-phase10.
```

---

## K10 — Subagent kickoff (idea-wizard-orchestrator, Phase 6)

```
You are the idea-wizard-orchestrator for run {RUN_ID}, round {ROUND}.

Read:
  - {WORKSPACE}/phase4_unified_findings.md
  - {WORKSPACE}/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md
  - {WORKSPACE}/phase1_notes/*.md (project-shape priors)

Invoke /idea-wizard's Phase 2 prompt with project narrowing:

  > Come up with your very best ideas for clever, non-obvious UB-detection
  > techniques that are specifically suited to THIS codebase. Consider its
  > custom allocators, self-referential structs, intrusive lists, lock-free
  > data structures, MMIO surfaces, FFI surfaces, and any unique aliasing
  > patterns. Generate 30 ideas, winnow to 5, then expand by 10 more. For
  > each of the 15, explain how to operationalize as an experiment.

For each of the 15:
  - If covered by existing F-NNN, mark "Already covered by F-NNN"
  - Otherwise, write a fresh ## EXP-NNN block in UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md (verdict OPEN)

Output: {WORKSPACE}/phase6_idea_wizard{_round_{ROUND} if not first}.md with the 30-list, the 5-pick, the 10-expansion, and a final mapping table.

Coordination thread: ub-exorcism-{RUN_ID}-phase6-round{ROUND}.
```

---

## K11 — Subagent kickoff (soak-runner, Phase 11)

```
You are the soak-runner for campaign {CAMPAIGN_ID} in run {RUN_ID}.

Read the campaign block in {WORKSPACE}/phase11_soak_designs.md.

Dispatch via:
  rch exec --tag ub-exorcism-{RUN_ID}-{CAMPAIGN_ID} -- <campaign command>

Poll via:
  rch status --tag ub-exorcism-{RUN_ID}-{CAMPAIGN_ID}

When done:
  rch sync --pull  # to {WORKSPACE}/phase11_artifacts/{CAMPAIGN_ID}/

Update the campaign block with verdict + raw output reference.

If new UB found:
  - Append a new ## EXP-NNN to UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md (verdict OPEN)
  - Loop back to Phase 8 with the new finding

Coordination thread: ub-exorcism-{RUN_ID}-phase11-{CAMPAIGN_ID} (long-lived; days).

DO NOT run the campaign locally. Always offload via rch.
```

---

## K12 — Final-artifact-author (Phase 12)

```
You are the final-artifact-author for run {RUN_ID}.

Produce:
  - {WORKSPACE}/FINAL_UB_REPORT.md
  - {WORKSPACE}/UB_RUNBOOK.md

FINAL_UB_REPORT.md:
  - Executive summary (1 paragraph + counts)
  - Full findings table (severity-ranked, with EXP-NNN and remediation bead IDs)
  - Convergence-evidence appendix (from phase7_convergence_round_*.json)
  - Open questions (DEFERRED items with re-check criteria)

UB_RUNBOOK.md (the project's permanent CI gates):
  - Minimum Clippy lint group
  - MIRIFLAGS matrix for CI
  - Loom models to keep green
  - Fuzz corpora to preserve
  - // SAFETY: comment template (3 lines minimum; cite invariants; reference enforcing code)
  - rustc -W flags to enable project-wide
  - "If you change X, re-run EXP-Y" recipes

Post a final summary to the user: counts, location of artifacts, recommendation to start with `br ready` in {SOURCE_PATH}.

Coordination thread: ub-exorcism-{RUN_ID}-phase12.
```
