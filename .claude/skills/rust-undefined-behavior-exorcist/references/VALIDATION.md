# Validation Gates — What Must Pass Before Declaring Done

Per `/operationalizing-expertise` Track A, every methodology needs explicit validation gates. This file is the minimum gate list. If any gate fails, the skill cannot declare its phase done.

---

## Phase 0 — Bootstrap gates

- [ ] `phase0_toolchain_inventory.json` exists and lists every required tool
- [ ] Every `status: "missing"` tool in the inventory is either installed (with user permission) or explicitly waived in `phase0_run.json`
- [ ] `phase0_partition.json` lists every section to audit
- [ ] User has confirmed the partition, run mode, and offload preference (local vs `rch`)
- [ ] Workspace path is inside the source repo at `.ub-exorcism/<run-id>/`; no sibling audit directory was created

## Phase 1 — Inventory gates

- [ ] `phase1_unsafe_surface_inventory.md` exists
- [ ] Row count ≥ output of `rg -c 'unsafe' --type rust <source>` (each unsafe keyword has a row OR is documented as a false-positive match)
- [ ] Every row has a UB-taxonomy bucket tag
- [ ] Every `unsafe { ... }` block has a SAFETY-comment status (PRESENT_STRONG / PRESENT_WEAK / MISSING)
- [ ] `cargo expand` was run; macro-generated unsafe is recorded with `MACRO_GENERATED` tag
- [ ] Per-module digest exists for every section in the partition

## Phase 2 — Static-sweep gates

- [ ] One `phase2_findings_<bucket>.md` per *project-relevant* bucket (others say "N/A; <reason>")
- [ ] Every Phase-1 row is either acknowledged in a Phase-2 bucket file or explicitly downgraded with rationale
- [ ] Every Phase-2 finding has: severity, static evidence (with quoted pattern + diagnostic), draft experiment
- [ ] `phase2_summary.md` rolls up the per-bucket counts
- [ ] Clippy ran with the safety-lint group from [TOOLING.md](TOOLING.md); output saved
- [ ] `cargo-geiger` ran; output saved
- [ ] `rustc -W` safety-lint pass ran; output saved
- [ ] At least one syn walker ran successfully (or all are documented as inapplicable)

## Phase 3 — Dynamic-sweep gates

- [ ] Miri ran across the full MIRIFLAGS matrix (default / tree-borrows / strict-provenance / symbolic-alignment); each has a `.log` in `phase3_raw/`
- [ ] Where the target supports them, ASan and TSan ran; LSan if supported; MSan optional (slow first run)
- [ ] TSan ran with `--test-threads=1` (verify in log)
- [ ] Sanitizers ran in *separate* builds (never combined)
- [ ] Every existing fuzz target ran a bounded campaign; results in `phase3_raw/fuzz_<target>.log`
- [ ] For every unsafe API identified in Phase 2 that lacks a fuzz target, a target was either authored OR a `SKIPPED-with-rationale` line was added
- [ ] Every concurrency primitive identified in Phase 1 has a loom model OR a `SKIPPED-with-rationale` line
- [ ] Every Miri/sanitizer/loom finding has a row in `phase3_dynamic_findings.md`

## Phase 4 — Synthesis gates

- [ ] `phase4_unified_findings.md` exists with the table
- [ ] Every Phase-1/2/3 finding is represented (no quiet drops)
- [ ] Duplicates merged with cross-refs preserved
- [ ] Severity is re-scored with a one-line rationale per change
- [ ] `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` (v1) exists
- [ ] Every OPEN finding has ≥1 experiment
- [ ] Every experiment block has all 8 fields (Finding ref, Bucket, Severity, Hypothesis, Reproducer, Expected signal, Falsifiability, Invocation, Verdict)
- [ ] Every reproducer is ≤30 lines

## Phase 5 — Experiment-execution gates

- [ ] Every `EXP-NNN` has a verdict ≠ `OPEN` after this phase
- [ ] Every verdict has a `phase5_experiment_results/<id>.log` file
- [ ] Every `NEEDS_REFINEMENT` spawned a follow-up `EXP-NNN-a`
- [ ] Verdicts are recorded *in place* (single instance per EXP-NNN block) — no duplicates

## Phase 6 — Idea-wizard gates (multi-round, investigate-all)

For each round (2 in Standard, 3 in Exhaustive):

- [ ] `phase6_idea_wizard_round_<N>.md` exists for every round 1..N
- [ ] Each round file lists EXACTLY 30 ideas (not 25, not 35 — 30 lets cross-round comparison be clean)
- [ ] Each idea has a three-axis score (PROVABILITY / IMPACT / NOVELTY), each 1–5
- [ ] Each idea has a per-idea verdict from `{ALREADY_COVERED, NEW_EXP_PROMOTED, NEEDS_DEEPER_INVESTIGATION, NO_EVIDENCE, INAPPLICABLE}`
- [ ] Each round states its lens (STRUCTURAL / ADVERSARIAL / CROSS-SYSTEM) verbatim, distinct from prior rounds
- [ ] Every NEW_EXP_PROMOTED idea has a corresponding `## EXP-<R>NN` block in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` with verdict OPEN
- [ ] **Final round only:** `phase6_idea_wizard_rollup.md` exists with one row per (round, idea-id, verdict, EXP-NNN-if-promoted)

Across all rounds combined:

- [ ] ≥1 net-new experiment promoted (OR a documented convergence-evidence note explaining why none of the rounds produced new EXPs — only legitimate after the project has been deeply mined)
- [ ] No "TBD" verdicts in any round

## Phase 7 — Convergence gates

- [ ] `convergence-tracker.sh` ran after every round
- [ ] `phase7_convergence_round_<N>.json` exists for every round
- [ ] Total rounds ≥ the archetype-aware floor (≥10 for unsafe-touching crates; ≥3 Standard / ≥5 Exhaustive for pure-safe `#![forbid(unsafe_code)]` projects — see [CONVERGENCE.md §Archetype-aware round floor](CONVERGENCE.md#archetype-aware-round-floor))
- [ ] Last two rounds are both `"quiet": true`
- [ ] Verdict counts in the latest round: `OPEN: 0`, `NEEDS_REFINEMENT: 0`
- [ ] If the archetype was upgraded mid-run (e.g., `unsafe` discovered in a feature-gated module), the floor reverted to 10 and the run continued accordingly

## Phase 8 — Remediation-plan gates

- [ ] `phase8_remediation_plan.md` exists
- [ ] Every `CONFIRMED_UB` finding has a remediation section
- [ ] Every remediation has ≥1 runner-up where applicable (≥2 candidate rewrites total)
- [ ] Rubric scores quantitative on perf delta (benchmark when score is 0–1)
- [ ] High-stakes findings have triangulation results recorded
- [ ] Every remediation cross-references the proving experiment AND the regression-experiment

## Phase 9 — Beads gates

- [ ] `br dep cycles` returns empty
- [ ] `bv --robot-insights | jq '.Cycles | length'` returns 0
- [ ] **Downstream children of the parent epic are visible via `br show <epic>` under the `Dependents:` heading.** NOTE: `br dep tree <id>` shows only what the bead is blocked-by (upstream blockers), not what it blocks (downstream dependents). Use `br show <epic> --json | jq '.dependents'` (when available) or read the `Dependents:` text block from `br show <epic>` directly.
- [ ] Every remediation bead has ≥1 test-bead dependency (Miri / loom / sanitizer / fuzz / property)
- [ ] Every remediation bead has ≥1 docs-bead dependency
- [ ] Polish steady-state reached (≥4 rounds, last round trivial changes only)
- [ ] No bead has empty description
- [ ] Source repo's `.beads/` synced (`br sync --flush-only`) and committed (with user permission)

## Phase 10 — Fresh-eyes gates

- [ ] All three prompts (A/B/C) ran in order
- [ ] Two consecutive passes produced only trivial changes (whitespace, typo, formatting)
- [ ] `ubs $(git diff --name-only --cached)` clean (if `ubs` installed)
- [ ] `cargo check --all-targets` clean
- [ ] `cargo clippy --all-targets -- -D warnings` clean
- [ ] `cargo fmt --check` clean
- [ ] `cargo +nightly miri test` green on any scratch-implemented remediations
- [ ] `phase10_fresh_eyes_log.md` exists with the round-by-round log

## Phase 11 — Soak gates (Exhaustive only)

- [ ] `phase11_soak_designs.md` exists with one block per campaign
- [ ] Each campaign dispatched via `rch exec --` (tag `ub-exorcism-<run-id>-<campaign>`)
- [ ] Each campaign's artifacts pulled back to `phase11_artifacts/<campaign>/`
- [ ] Each campaign's verdict recorded inline in the campaign block
- [ ] Any new UB surfaced by a campaign is added to `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` AND triggers a Phase-8 re-entry

## Phase 12 — Final-artifact gates

- [ ] `FINAL_UB_REPORT.md` exists with: executive summary, findings table, convergence appendix, open-questions list
- [ ] `UB_RUNBOOK.md` exists with: minimum Clippy lint group, MIRIFLAGS matrix for CI, loom models to keep green, fuzz corpora to preserve, SAFETY-comment template, rustc -W flags, "if you change X re-run EXP-Y" recipes
- [ ] User has been notified with a summary + the recommendation to start with `br ready` in the source repo
- [ ] Auto-remediation offer made: at end of Phase 12, the agent asked the user explicitly (`AskUserQuestion` or equivalent) whether to run Phase 13. Default is hand-off; Phase 13 runs only on explicit "yes".
- [ ] Audit artifacts are either committed/tagged in the source repo with `ub-exorcism/<run-id>/final` or explicitly left uncommitted per user instruction

## Phase 13 — Auto-remediation gates (OPT-IN; skip if Phase 13 was not run)

- [ ] User gave explicit "yes" to the Phase 12 auto-remediation prompt; the answer is recorded in `phase13_remediation_log.md` header
- [ ] `phase13_remediation_log.md` has one entry per bead the executor attempted, with Outcome ∈ {CLOSED-WITH-FIX, CLOSED-OBSOLETE, DEFERRED-NEEDS-HUMAN}
- [ ] Every CLOSED-WITH-FIX bead has exactly one commit in the source repo with the bead ID in the message AND `git diff $PRE_HEAD $POST_HEAD --name-only` is a subset of `Files declared`
- [ ] Every CLOSED-WITH-FIX bead's regression test was re-run post-change and verified passing (the commit must NOT pre-date the test)
- [ ] Every CLOSED-OBSOLETE bead has NO new commit AND its log entry shows `Pre-change verdict: already-PASS`
- [ ] Every DEFERRED-NEEDS-HUMAN bead carries the `phase13-needs-human-review` label AND a comment with both failure traces (chosen + runner-up) AND `git diff $PRE_HEAD HEAD -- "${TOUCHED_FILES[@]}"` is empty (source successfully reverted)
- [ ] `br dep cycles` is empty post-Phase-13 (no cycle was silently introduced or hidden by a hedge close)
- [ ] No file was deleted by the executor (per project AGENTS.md rule)
- [ ] No destructive git invoked: `git reflog | grep -E 'reset --hard|clean -fd|push --force'` is empty since Phase 13 start
- [ ] `FINAL_UB_REPORT.md` has a "Phase 13 Execution Log" appendix with bead counts (CLOSED-WITH-FIX / CLOSED-OBSOLETE / DEFERRED-NEEDS-HUMAN) and links to the per-bead commits

### Sample Phase 13 queries

`phase13_remediation_log.md` is the single source of truth; parse it with grep/awk. The executor entries follow the schema documented in [PHASES.md §Phase 13 log](PHASES.md#phase-13-optional-auto-remediation--execute-the-plan).

```bash
LOG="$WORKSPACE/phase13_remediation_log.md"

# Every CLOSED-WITH-FIX bead has a matching commit (CLOSED-OBSOLETE has no commit by design)
awk '/^## /{id=$2} /^- Outcome: CLOSED-WITH-FIX/{print id}' "$LOG" | while read -r id; do
    git -C "$SOURCE" log --grep="$id" --since="$RUN_START" --oneline | grep -q "$id" || echo "MISSING COMMIT: $id"
done

# Every CLOSED-OBSOLETE bead has NO commit
awk '/^## /{id=$2} /^- Outcome: CLOSED-OBSOLETE/{print id}' "$LOG" | while read -r id; do
    if git -C "$SOURCE" log --grep="$id" --since="$RUN_START" --oneline | grep -q "$id"; then
        echo "UNEXPECTED COMMIT for obsolete bead: $id"
    fi
done

# No hedge close-reasons
br list --status closed --json | jq '.issues[] | select(.close_reason | test("Forced close|hedge"; "i"))'  # must be empty

# Phase 13 did not delete any tracked files
git -C "$SOURCE" diff --diff-filter=D --name-only "$PHASE13_START_SHA"..HEAD  # must be empty

# Every DEFERRED-NEEDS-HUMAN bead has the label AND a clean working tree for its declared files
awk '/^## /{id=$2} /^- Outcome: DEFERRED-NEEDS-HUMAN/{print id}' "$LOG" | while read -r id; do
    br show "$id" --json | jq -e '.labels[]? | select(. == "phase13-needs-human-review")' >/dev/null \
        || echo "MISSING LABEL: $id"
done
```

---

## Auto-validation script

`scripts/validate-phase.sh <workspace> <phase-number|all>` mechanizes the per-phase gates documented above. It exits 0 if every mechanizable gate passes, 1 if any fail. Qualitative gates (those requiring human judgment, e.g., "Partition posted to user before Phase 1 fan-out") are surfaced as `[?] MANUAL` lines but do not count against the exit status — the orchestrator must explicitly attest them.

```bash
./scripts/validate-phase.sh "$WORKSPACE" 0    # one phase
./scripts/validate-phase.sh "$WORKSPACE" all  # every phase that has phase0_run.json present
```

The per-phase grep + jq queries below are the canonical recipes the script mechanizes. Read them when a gate fails to understand what's being checked.

### Sample queries

```bash
# Phase 4 — every OPEN has ≥1 experiment
diff <(grep -oE '^## F-[0-9]+' phase4_unified_findings.md | sort -u) \
     <(grep -oE 'Finding ref:\*\* F-[0-9]+' UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md | awk '{print $NF}' | sort -u)

# Phase 5 — no OPEN remains
grep -c '\*\*Verdict:\*\* OPEN' UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md   # must be 0

# Phase 7 — two consecutive quiet rounds
jq -e '.quiet' phase7_convergence_round_$(N-1).json && jq -e '.quiet' phase7_convergence_round_N.json

# Phase 9 — every remediation has test+docs deps
bv --robot-insights | jq -e '
  [.beads[] | select(.title | test("Fix UB|Remediat"; "i")) |
   {has_test: ([.dependencies // [] | .[] | .target_title]
              | map(test("test|miri|loom|fuzz|property"; "i")) | any),
    has_docs: ([.dependencies // [] | .[] | .target_title]
              | map(test("docs|SAFETY|comment"; "i")) | any)}]
  | all(.has_test and .has_docs)
'
```
