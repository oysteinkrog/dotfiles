---
name: partial-splitter
description: Phase 7 — for each `partially-novel` stash, create a split copy of the diff to drop superseded hunks, then apply the novel-only diff.
---

# Partial Splitter

Owns Phase 7. The most error-prone phase. Gets its own subagent so it doesn't compete with Phase 6's working tree.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path

## Workflow

For each `partially-novel` row in `triage.tsv`:

1. Open `<bundle>/diffs/<n>.diff` for inspection.
2. Read the row's `hunk_breakdown` JSON (if present) or re-fingerprint per-hunk to identify novel vs. superseded.
3. **Create a split copy** of the diff at `<bundle>/diffs/<n>.split.diff`. Use the Edit tool for semantic/manual splits. Use `scripts/partial-split.sh` only when the row already gives exact hunk IDs to keep or drop. NEVER use ad hoc sed/awk/regex transformations. Drop the superseded hunks; keep the novel ones. Each remaining hunk's `@@` header stays intact (don't renumber).
4. `git apply --3way --check <bundle>/diffs/<n>.split.diff` — must be clean. If not, the split was wrong; re-edit.
5. Apply via the same APPLY-3WAY → RECOVER → commit flow as Phase 6.
6. The commit message must explicitly note "split-apply: novel hunks only; superseded hunks dropped per triage row":
   ```
   recover novel <description> from partial stash@{<n>}

   Originally stash@{<n>} mixed <X> with <Y>; <X> already landed via <Z>.
   This commit recovers only the <Y> portion (hunks 5–8 of 8).

   Hunks recovered: <count> of <total> (see <bundle>/diffs/<n>.split.diff).
   ```
7. Append to `<workspace>/partial_split_log.tsv` with `hunks_kept`, `hunks_dropped`, `new_commit_sha`.

## Critical rules

- **No ad hoc script edits.** Per AGENTS.md "No Script-Based Changes", never use custom sed/awk/regex transformations on the diff file. The bundled `scripts/partial-split.sh` is allowed only for exact hunk-number filtering and must pass `--3way --check`.
- **Apply-check must be clean** before actual apply. If the split is wrong, the apply will fail or apply incorrectly.
- **Never use `git apply --include=<path>`** for hunk-level filtering — it's path-level only.
- **Document hunks-kept and hunks-dropped explicitly** in the commit message.

## Coordination

- File reservation: `paths=["**", "{bundle}/diffs/<n>.split.diff"]`, `exclusive=true`, `reason="stash-janitor-phase7"`.
- Sequence with Phase 6 — Phase 7 runs only AFTER Phase 6 completes (so re-fingerprinting against the recovery branch HEAD is consistent).

## Quality gates

- [ ] Each `<n>.split.diff` exists and is non-empty
- [ ] Each `<n>.split.diff` applies cleanly via `--3way --check`
- [ ] Commit messages explicitly note "split-apply" and the hunks-kept count
- [ ] No `partially-novel` row remains without resolution (either applied, or `partial-skipped` with user direction)

## Exit criteria

`partial_split_log.tsv` has one row per `partially-novel` from `triage.tsv`; quality gates green on recovery branch tip.
