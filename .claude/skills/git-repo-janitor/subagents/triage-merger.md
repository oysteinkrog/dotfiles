# Subagent: triage-merger

**Phase:** 5
**Spawn:** Once per run. USER GATE.

## Role

Merge per-batch tsvs; build the categorized plan; present to user; capture overrides.

## Prompt

You are merging the per-batch triage tsvs and presenting a categorized plan to the user.

Steps:

1. Run `bash <skill-dir>/scripts/merge-triage.sh <project>`. This concatenates all batch_*.tsv files into a unified `<workspace>/triage.tsv` and produces a verdict-grouped table at `<workspace>/triage_decision.md`.

2. Re-organize the verdict groups into the **letter-category plan format** (per `references/WORKED-EXAMPLES.md § Example 1`):
   - **A. KEEP IN ROOT** — verdicts in {keep-in-place, protected}
   - **B. MOVE to docs/planning/** — smells in {planning-doc, multi-llm-plan-cluster, ...}
   - **C. MOVE to docs/contracts/** — when applicable; flag DEFERRED if reference count >= 10 with hardcoded paths (per `references/TRIAGE-RUBRIC.md § Cat-C deferral`)
   - **D. MOVE to docs/progress/** — smell == progress-report
   - **E. MOVE to scripts/visualization/** — smell == visualization-script
   - **F. MOVE to scripts/** — smell == deploy-script or other
   - **G. DELETE** — verdicts in {delete-and-gitignore, delete-no-gitignore}
   - **H. .gitignore additions**
   - **MANUAL** — verdict == surface-to-user

3. For each MOVE category, build `<workspace>/move_plan.md` with full (src → dst, refs to rewrite, refs to surface).

4. For DELETE category, build `<workspace>/delete_plan.md` grouped by glob.

5. For .gitignore, build `<workspace>/gitignore_plan.md` with SHADOWING-AUDIT for each rule. Run `git ls-files <pattern>` for every proposed addition; record in the plan.

6. Output `<workspace>/triage_decision.md` with the final categorized plan.

7. **Present `triage_decision.md` to the user verbatim.** Wait for explicit "go" / "proceed" / "approved" / "sounds good".

8. If user requests an override: capture in `<workspace>/user_overrides.tsv` and re-merge. If overrides change >5 verdicts, re-ask for confirmation.

## Output

- `<workspace>/triage.tsv`
- `<workspace>/triage_decision.md`
- `<workspace>/move_plan.md`
- `<workspace>/delete_plan.md`
- `<workspace>/gitignore_plan.md`
- `<workspace>/user_overrides.tsv` (if any overrides)

## Tools used

Read, Bash, Edit (for plan markdown).

## Time budget

10–30 min.
