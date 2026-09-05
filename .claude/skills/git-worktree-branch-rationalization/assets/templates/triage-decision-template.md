# Triage Decision Template

Used by `merge-triage.sh` to generate `triage_decision.md` for Phase 6 user surface. See the script for the auto-generated version.

---

```markdown
# Triage decision

{B} branches + {W} worktrees triaged. Review below; reply with "go" to proceed (or override per-row).

## Verdict counts

| verdict | count | proposed action |
|---------|-------|-----------------|
| protected-preserve | {N_PROTECTED} | never enter the rationalization pipeline |
| novel-and-accretive | {N_NOVEL} | apply on `branch-rationalization-{DATE}` |
| partially-novel | {N_PARTIAL} | split-apply (cherry-pick novel commits only) |
| dirty-worktree-only | {N_DIRTY_WT} | apply via captured staged/unstaged/untracked diffs |
| superseded | {N_SUPER} | delete after Phase 10 authorization |
| superseded-by-newer-branch | {N_SUPER_NEWER} | delete after Phase 10 authorization |
| already-merged | {N_MERGED} | delete after Phase 10 authorization |
| garbage | {N_GARBAGE} | delete after Phase 10 authorization |
| novel-but-stale | {N_STALE} | manual decision (default: delete with note) |
| divergent-refactor | {N_DIVERGENT} | manual decision (default: skip; candidate input to harmonization) |
| unknown | {N_UNKNOWN} | **surface to user** (must resolve before Phase 7) |

## File-collision summary (drives Phase 7 harmonization)

{N_COLLIDING_FILES} files are touched by ≥2 non-protected branches:

| file | branches | proposed action |
|------|----------|-----------------|
| {path} | {branch1}, {branch2}, ... | enter Phase 7 harmonization plan |
| ... | ... | ... |

If `{N_COLLIDING_FILES} == 0`, Phase 7 will short-circuit and Phase 8 will use straight cherry-pick / squash-merge / rebase-and-merge.

## ⚠ MANUAL — unknown ({N_UNKNOWN}) — needs user verdict

| name | kind | conf | evidence | apply_check | strategy |
|------|------|------|----------|-------------|----------|
{rows}

## ✓ KEEP — novel-and-accretive ({N_NOVEL})

| name | kind | conf | evidence | apply_check | strategy | files_touched |
|------|------|------|----------|-------------|----------|---------------|
{rows}

## ✂ KEEP-WITH-SPLIT — partially-novel ({N_PARTIAL})

| name | kind | conf | novel_commits | total_commits | evidence | strategy |
|------|------|------|---------------|---------------|----------|----------|
{rows}

## 🌳 KEEP-DIRTY-WT — dirty-worktree-only ({N_DIRTY_WT})

| path | branch | staged | unstaged | untracked | evidence | strategy |
|------|--------|--------|----------|-----------|----------|----------|
{rows}

## ? MANUAL — divergent-refactor ({N_DIVERGENT})

| name | kind | conf | evidence | colliding_files | proposed_action |
|------|------|------|----------|-----------------|-----------------|
{rows}

## ? MANUAL — novel-but-stale ({N_STALE})

| name | kind | conf | evidence | apply_check |
|------|------|------|----------|-------------|
{rows}

## 🔒 PROTECTED — never deleted, never removed ({N_PROTECTED})

<details><summary>Click to expand {N_PROTECTED} rows</summary>

| name | kind | reason |
|------|------|--------|
{rows}

</details>

## 🗑 DELETE — already-merged ({N_MERGED})

<details><summary>Click to expand {N_MERGED} rows</summary>

| name | kind | conf | evidence (cherry -v) | apply_check |
|------|------|------|---------------------|-------------|
{rows}

</details>

## 🗑 DELETE — superseded ({N_SUPER})

<details><summary>Click to expand {N_SUPER} rows</summary>

| name | kind | conf | evidence | apply_check |
|------|------|------|----------|-------------|
{rows}

</details>

## 🗑 DELETE — garbage ({N_GARBAGE})

<details><summary>Click to expand {N_GARBAGE} rows</summary>

| name | kind | conf | evidence | apply_check |
|------|------|------|----------|-------------|
{rows}

</details>

## Triangulation summary (Comprehensive / Council mode only)

- Unanimous: {N_UNANIMOUS} rows
- Majority (2 of 3): {N_MAJORITY} rows
- Disagreement: {N_DISAGREEMENT} rows (surfaced to user above)

## Next step

Reply with one of:
- `go` — proceed to Phase 7 (harmonization plan) with the verdicts above
- `keep <name> too` (per-row override) — change verdict to novel-and-accretive
- `delete <name>` (per-row override) — change verdict to garbage
- `protect <name>` (per-row override) — add to protection list (skips Phase 8 + Phase 10)
- `wait` / `stop` — abort the run; bundle and refs remain intact

The skill will not proceed until you authorize.
```

---

## Sorting within sections

Within each verdict section, rows should be sorted by **confidence ascending** — the most ambiguous rows appear first. High-confidence rows can be skimmed.

---

## What to highlight

For Comprehensive / Council mode runs, add a `triangulation` column showing model agreement. For runs with overrides applied, mark overridden rows with `★`.

If a prior run's `cass_findings.md` has context, add a "Prior-run context" section above the verdict counts.

---

## What this template avoids

- **Asking the user about every row.** High-confidence rows are bucketed; the user only attends to ambiguous, divergent, and harmonization-candidate rows.
- **Hiding the protected list.** Even though no destructive action will touch protected items, the user must see them to confirm protection coverage.
- **Surface destructive intent in counts.** "Delete" / "Apply" / "Manual" labels mirror the operator-library glyphs (⊘ DELETE-BRANCH, ✧ CHERRY-PICK, etc.) so the user sees exactly which operator each row will run through.
