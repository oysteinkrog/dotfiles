---
name: triage-merger
description: Phase 6 — merge all batch tsvs into triage.tsv; build triage_decision.md (markdown decision table grouped by verdict, sorted by confidence, collapsible details for large groups). Present to user verbatim; capture overrides into user_overrides.tsv. USER GATE before Phase 7.
---

# Triage Merger

Owns Phase 6. The user-facing gate. No destructive actions in this phase — its job is to surface verdicts to the user and capture explicit go-ahead before the harmonization plan and any apply happens.

Why: Axiom 14 says authorization is per-plan, verbatim, recorded. Phase 6 produces the plan; Phase 7 (harmonization) and Phases 8 / 10 will reference it. Without explicit user sign-off here, no later phase mutates anything.

## Inputs

- `{WORKSPACE}` — workspace dir
- `{PROJECT}` — absolute path

## Outputs

- `<workspace>/triage.tsv` — merged + sorted union of all `triage/batch_*.tsv` rows (header from first batch, rows from all). Source of truth for downstream phases from this point on.
- `<workspace>/triage_decision.md` — user-facing decision table grouped by verdict (KEEP / KEEP-WITH-HARMONIZATION / KEEP-WITH-SPLIT / KEEP-DIRTY / MANUAL / SKIP / PROTECTED), sorted within each section by confidence ascending; large groups wrapped in `<details>` collapsibles; MANUAL sections never collapsed.
- `<workspace>/user_overrides.tsv` — `name|original_verdict|new_verdict|original_strategy|new_strategy|user_reason`; one row per user override applied.
- `<workspace>/phase6_user_authorization.txt` — verbatim user go-ahead text + UTC timestamp.
- **Side effects:** read-only against repo state. No commits, no `git apply`, no `git checkout`, no `git branch -d`. Updates `triage.tsv` to reflect overrides — the merged file is the source of truth from this point.
- **Decision contract:** Phase 7 (harmonization-planner) and all downstream phases refuse to start without `phase6_user_authorization.txt` present. If overrides change >5 verdicts, the merger re-presents the updated table and re-asks for confirmation before declaring the gate passed.

## Workflow

1. **Merge** — concatenate all `<workspace>/triage/batch_*.tsv` (header from first, rows from all). Sort by `kind` then `name`. Write to `<workspace>/triage.tsv`. Run `scripts/merge-triage.sh` for the heuristic merge; verify it didn't drop rows.

2. **Build decision table** — emit `<workspace>/triage_decision.md` with one section per verdict, sorted within each section by confidence ascending (most ambiguous first, so the user sees them top of page):

   ```markdown
   # Triage Decision Table

   Canonical: <name> (detected via <method>)
   Total: B branches + W dirty worktrees = T entries

   ## KEEP — novel-and-accretive (N entries)

   | name | files | confidence | evidence | strategy |
   |------|-------|------------|----------|----------|
   | feat/parser-hardening | 6 | 0.92 | `parse_strict_mode` introduced (not on canonical, grep-empty); cherry shows 4+/0- | cherry-pick |
   | ... |

   ## KEEP-WITH-HARMONIZATION — divergent-refactor (M entries)

   | name | colliding files | confidence | evidence | other branches on same files |
   |------|-----------------|------------|----------|------------------------------|
   | agent-cleanup-pass-3 | src/redact.rs, src/parse.rs | 0.81 | `redact_secrets` signature differs from canonical | feat/parse-hardening, wip/null-checks |
   | ... |

   ## KEEP-WITH-SPLIT — partially-novel (P entries)

   ## KEEP-DIRTY — dirty-worktree-only (D entries)

   ## MANUAL — novel-but-stale (K entries)   ← user must direct (archaeology + rewrite, or drop)

   ## MANUAL — unknown (J entries)            ← user must resolve

   ## SKIP — already-merged (X entries)       ← collapsed `<details>`

   ## SKIP — superseded (Y entries)           ← collapsed `<details>`

   ## SKIP — garbage (Z entries)              ← collapsed `<details>`

   ## PROTECTED — protected-preserve (R entries)   ← collapsed `<details>`
   ```

   Each KEEP-WITH-HARMONIZATION row also lists which other branches touched the same files — Phase 7's harmonization-planner consumes this to know which variant matrices to build.

   For groups with >20 entries, wrap the table in `<details><summary>…</summary>` so the user can scroll. The MANUAL sections are NEVER collapsed — they need attention.

3. **Present to user** — print the table verbatim. Wait for response.

4. **Apply overrides** — if user replies with "actually keep agent-cleanup-pass-3 as cherry-pick instead of harmonization" or similar, capture in `<workspace>/user_overrides.tsv` (`name`, `original_verdict`, `new_verdict`, `original_strategy`, `new_strategy`, `user_reason`). Update `triage.tsv` to reflect overrides. The merged file is the source of truth from this point on.

5. **Sanity-check overrides** — if overrides change >5 verdicts, re-present the updated table and re-ask for confirmation. Why: a large override set may indicate the triage rubric misfired and the user is correcting course; the user needs a chance to see the corrected plan whole.

6. **Capture explicit go-ahead** — wait for the user to type words like "go", "proceed", "approved" (or the equivalent in their language). Record in `<workspace>/phase6_user_authorization.txt` with UTC timestamp. This is the gate Phase 7 reads before building the harmonization plan.

7. **Hand off to Phase 7** — emit a one-line summary: "Phase 6 complete. Verdicts frozen. <H> entries headed for harmonization (<list of file-collision groups>); <K> headed for direct apply; <S> skipped. Phase 7 (harmonization plan) starts next; user reviews the plan before any mutation."

## Critical rules

- **No commits in this phase.** No `git apply`, no `git checkout`, no `git branch -d`. Phase 6 is read-only.
- **Confidence < 0.7 rows force surface.** Even if the user said "approve all", these need explicit per-row decision.
- **User overrides are recorded.** Never silently change a verdict.
- **Never bypass pre-commit hooks.**
- **Never use sed/awk on source files.**
- **Never disturb concurrent agents' working-tree state.**
- **Never delete files without express user permission.**
- **Never run mass-delete primitives.**

## Coordination

- File reservation: `paths=[".worktree_branch_rationalization_workspace/triage.tsv", ".worktree_branch_rationalization_workspace/triage_decision.md", ".worktree_branch_rationalization_workspace/user_overrides.tsv", ".worktree_branch_rationalization_workspace/phase6_user_authorization.txt"]`, `exclusive=true`, `reason="branch-rationalization-phase6"`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] `triage.tsv` row count == `branches.tsv` row count + dirty-worktree row count from `worktrees.tsv`
- [ ] No row has `verdict=unknown` after user resolution
- [ ] `phase6_user_authorization.txt` exists with explicit go-ahead text and UTC timestamp
- [ ] If overrides applied: `user_overrides.tsv` records each one with `user_reason`
- [ ] Every KEEP-WITH-HARMONIZATION row lists ≥1 colliding file and ≥1 other branch touching that file

## Exit criteria

User explicitly authorized proceeding to Phase 7; `triage.tsv` reflects final verdicts; main agent posts the harmonization-plan summary as the next-step preview.
