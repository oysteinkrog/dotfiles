---
name: triage-merger
description: Phase 5 — merge all triage batch tsvs, present decision table to user, capture overrides, USER GATE before destructive phases.
---

# Triage Merger

Owns Phase 5. The user-facing gate. No destructive actions in this phase — its job is to surface verdicts to the user and capture explicit go-ahead.

## Inputs

- `{WORKSPACE}` — workspace dir

## Workflow

1. **Merge** — concatenate all `<workspace>/triage/batch_*.tsv` (header from first, rows from all). Sort by `n` ascending. Write to `<workspace>/triage.tsv`.
2. **Build decision table** — emit `<workspace>/triage_decision.md` with sections per verdict, sorted within each section by confidence ascending (most ambiguous first):
   ```markdown
   ### KEEP — novel-and-accretive (N)
   | n | message | files | confidence | evidence | proposed action |
   ...
   ### KEEP-WITH-SPLIT — partially-novel (M)
   ...
   ### MANUAL — novel-but-stale (K)
   ...
   ### MANUAL — unknown (J)   ← user must resolve
   ...
   ### DROP — superseded (X)   ← collapsed `<details>`
   ...
   ### DROP — garbage (Y)      ← collapsed `<details>`
   ...
   ```
3. **Present to user** — print the table verbatim. Wait for response.
4. **Apply overrides** — if user replies with "actually keep stash@{47}" or similar, capture in `<workspace>/user_overrides.tsv` (`n`, `original_verdict`, `new_verdict`, `user_reason`). Update `triage.tsv` to reflect overrides. The merged file is the source of truth from this point on.
5. **Sanity-check overrides** — if overrides change >5 verdicts, re-present the updated table and re-ask for confirmation.
6. **Capture explicit go-ahead** — wait for the user to type words like "go", "proceed", "approved" (or the equivalent in their language). Record in `<workspace>/phase5_user_authorization.txt`.

## Critical rules

- **No commits in this phase.** No `git apply`. No `git stash drop`. Phase 5 is read-only.
- **Confidence < 0.7 rows force surface** — even if the user said "approve all", these need explicit per-row decision.
- **User overrides are recorded** — never silently change a verdict.

## Coordination

- File reservation: `paths=[".stash_janitor_workspace/triage.tsv", ".stash_janitor_workspace/triage_decision.md", ".stash_janitor_workspace/user_overrides.tsv"]`, `exclusive=true`, `reason="stash-janitor-phase5"`.

## Quality gates

- [ ] `triage.tsv` row count == `inventory.tsv` row count
- [ ] No row has `verdict=unknown` after user resolution
- [ ] `phase5_user_authorization.txt` exists with explicit go-ahead text
- [ ] If overrides applied: `user_overrides.tsv` records each one with reason

## Exit criteria

User explicitly authorized proceeding to Phase 6; `triage.tsv` reflects final verdicts; main agent posts the next-step plan.
