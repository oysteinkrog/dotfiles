---
name: unblocked-work-finder
description: Phase 11 — cross-references rationalization-branch commits with beads + Agent Mail to detect newly-actionable beads (`bv --robot-triage --diff-since`), closed-by-this-commit beads (`bv --robot-history`), open PRs whose head branch was rationalized (now mergeable?), invalidated beads (the recovery already contains the requested feature). Optional /idea-wizard integration: generate 5-10 new bead ideas with priority. Emit `unblocked_work.md` appended to `handoff_report.md`.
---

# Unblocked Work Finder

Phase 11 forward-looking subagent. Where `handoff-reporter` looks backward at *what just landed*, the unblocked-work finder looks forward at *what's now possible because of what landed*. The recovery may have unblocked downstream beads, made open PRs newly mergeable, or made some open beads obsolete (their requested feature is already in the recovery).

Why this exists: a rationalization run typically completes with N new commits on the rationalization branch. Each of those commits potentially affects the project's task graph — beads that were waiting on a feature now have it, beads that were duplicates of recovered work are now obsolete, PRs that depended on a branch that's been rationalized now have a clean rebase target. Surfacing those connections turns "I just finished a 200-branch cleanup" into "and here are the 14 beads you can ship next as a result."

The finder is read-only against beads, Mail, and `gh`. It surfaces; it never mutates beads or merges PRs.

## When invoked

After `handoff-reporter` writes the initial `handoff_report.md` skeleton; the unblocked-work finder appends an "Unblocked Work" section.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{RATIONALIZATION_BRANCH}` — branch with the keeper commits
- `{APPLY_LOG}` — `<workspace>/apply_log.tsv`
- `{HANDOFF_REPORT}` — `<workspace>/handoff_report.md`
- `{RUN_ID}` — beads issue id from Phase 0.5 (if available)

## Outputs

- `<workspace>/unblocked_work.md` — four core sections: Newly-actionable beads, Beads referenced by recovered commits (closes/fixes/resolves), Open PRs affected by rationalization, Potentially-obsolete beads (with confidence ≥0.7 only); plus optional /idea-wizard suggestions; ends with a Recommended next-steps script (DO NOT RUN AS-IS — emitted as text, never executed).
- `<workspace>/bv_diff_since.json` — `bv --robot-triage --diff-since` output (when bv is available).
- `<workspace>/open_prs.json` — `gh pr list` output (when gh is authenticated).
- `<workspace>/idea_wizard_suggestions.md` — only when `--invoke-idea-wizard-on-handoff` was set AND /idea-wizard is available.
- **Side effects:** APPENDS the unblocked-work content as a new section to `<workspace>/handoff_report.md`. Read-only on beads, Mail, gh — NEVER runs `br update`, `gh pr close`, or any mutation. Skips silently when bv/br/gh are absent (records `tool_skipped: true`).
- **Decision contract:** confidence-gated invalidation only surfaces matches ≥0.7 (below = noise). The Recommended next-steps script is verbatim copy-pasteable text the user runs themselves; the finder emits, never executes.

## Workflow

### 1. Newly-actionable beads (`bv --robot-triage --diff-since`)

If `bv` is available, run:

```bash
bv --robot-triage --diff-since=<phase-0.5-checkpoint-sha> > <workspace>/bv_diff_since.json
```

`bv` returns the bead graph diff between the Phase 0.5 inventory snapshot and the rationalization-branch tip. Parse:
- Beads whose blocker chain now has a satisfied dependency (the feature landed via a Phase 8 commit)
- Beads whose `ready` field flipped from false to true

For each newly-actionable bead, capture: id, title, blocker chain (which commit unblocked it), priority (from `bv`).

### 2. Closed-by-this-commit beads (`bv --robot-history`)

For each commit in `apply_log.tsv:new_commit_sha`, scan its commit message + body for beads ticket references (regex: `[A-Z]+-[0-9]+`). Run:

```bash
for SHA in $(awk -F'\t' 'NR>1 {print $X}' apply_log.tsv); do
  # Extract any beads-id mentions from the commit message
  git -C {PROJECT} log -1 --format=%B $SHA | grep -oE '[A-Z]+-[0-9]+'
done
```

For each bead id mentioned, run `br show <id>` and capture: status, whether the rationalization-branch commit closes it (commit message includes "closes <id>" / "fixes <id>" / "resolves <id>"), the recommended next status.

If `br` is available, the finder does NOT auto-close beads — it surfaces them for user authorization. Closing a bead is a user decision; the finder produces the list and the recommended `br update` commands.

### 3. Open PRs whose head was rationalized

If `gh` is authenticated and the project has a GitHub remote:

```bash
gh pr list --state=open --json=number,headRefName,baseRefName,mergeable,title \
  > <workspace>/open_prs.json
```

Cross-reference `headRefName` against `triage.tsv:branch_name`. For each match:
- If the branch was deleted in Phase 10 — the PR is now invalid; the head ref is gone. Surface to user with `gh pr close <num>` recommendation.
- If the branch was preserved (in `protected.tsv`) — the PR is unaffected; skip.
- If the branch was rationalized into the rationalization branch (KEEP row) AND the rationalization branch is pushed — the PR's content is now reachable from canonical via the rationalization-branch's eventual merge; the user may want to close the PR with a "superseded by branch-rationalization-<DATE>" note.

For each affected PR: capture number, title, head ref, base ref, current mergeability, recommended action.

### 4. Invalidated beads (recovery contains the requested feature)

For each open bead from step 1's `bv --robot-triage` baseline (the *full* open-beads list, not just newly-actionable), scan its description against the rationalization-branch's commit subjects + body. If a commit message matches the bead's described feature with high confidence (e.g., commit subject contains the bead's primary verb + noun, OR the commit's `paths_committed` set overlaps the bead's `affected_paths` ≥80%), surface as a candidate "potentially-obsolete bead — verify the feature is fully implemented before closing."

Confidence threshold: only surface ≥0.7. Below that, the matches are noise.

### 5. Optional /idea-wizard integration

If `/idea-wizard` is available AND the user opted in via `--invoke-idea-wizard-on-handoff`:

Hand the rationalization-branch commit set + the harmonization plan + the open-beads list to /idea-wizard with the prompt: "given the recovered work and the unblocked beads, generate 5–10 new beads ideas with priority — what should we build next?"

Capture the output to `<workspace>/idea_wizard_suggestions.md`. The finder appends a summary; the user reviews and runs `br create` on each accepted idea.

### 6. Emit `unblocked_work.md`

Structure:

```markdown
# Unblocked Work

Generated: <UTC>

## Newly-actionable beads (count: N)

| bead id | title | priority | unblocked-by-commit | recommended action |
|---|---|---|---|---|
| ABC-123 | Add parser support for X | P2 | abc1234 (recover wider grammar from feat/parser-hardening) | move to `ready` |
| ... |

## Beads referenced by recovered commits (closes / fixes / resolves)

| bead id | current status | commit | message subject | recommended action |
|---|---|---|---|---|
| ABC-456 | open | def5678 | harmonize src/redact.rs from agent-cleanup-pass-3 + ... | `br update ABC-456 --status=closed --reason="implemented in branch-rationalization-<DATE>"` |
| ... |

## Open PRs affected by the rationalization

| PR | title | head ref | base | recommended action |
|---|---|---|---|---|
| #234 | parser hardening | feat/parser-hardening (DELETED in Phase 10) | main | `gh pr close 234 --comment "superseded by branch-rationalization-<DATE>"` |
| ... |

## Potentially-obsolete beads (recovery may contain the feature)

| bead id | title | matching commit(s) | confidence | recommended action |
|---|---|---|---|---|
| ABC-789 | Defensive null-check on redact path | def5678 | 0.85 | verify and close |
| ... |

## /idea-wizard suggestions (if invoked)

(content of idea_wizard_suggestions.md)

## Recommended next-steps script (DO NOT RUN AS-IS — review each line)

# Move newly-actionable beads to ready
br update ABC-123 --status=ready
br update ABC-124 --status=ready

# Close beads completed by recovered commits
br update ABC-456 --status=closed --reason="implemented in branch-rationalization-<DATE>"

# Close superseded PRs (after pushing the rationalization branch)
gh pr close 234 --comment "superseded by branch-rationalization-<DATE>"
```

The recommended-next-steps script is **emitted as a list, not run**. The user reviews each line and runs the ones they want, exactly per Axiom 15's "remote cleanup is out of scope by default" pattern applied to bead/PR mutations.

### 7. Append to `handoff_report.md`

Append the `unblocked_work.md` content as a new section to the handoff report. The user sees the unblocked work in the same place they see the run summary.

## Critical rules

- **Never auto-close beads.** Closing a bead is a user decision. The finder surfaces; the user runs `br update`.
- **Never auto-close PRs.** Same reasoning. The finder surfaces; the user runs `gh pr close`.
- **Confidence-gated invalidation.** Below 0.7, matches are noise. Surface only high-confidence candidates and label them "potentially-obsolete — verify."
- **Skip silently if `bv` / `br` / `gh` are absent.** The finder degrades gracefully: empty section + `tool_skipped: true` recorded in the report.
- **Don't mutate beads or PRs.** The finder is read-only. The recommended-next-steps section is a script the user runs, never the finder.
- **Per AGENTS.md "No Script-Based Changes":** never run sed/awk on source files.
- **Per AGENTS.md "Note for Codex/GPT-5.5":** never disturb concurrent agents' working-tree state in any worktree.
- **Per AGENTS.md RULE NUMBER 1:** never delete files without express user permission.
- **Never bypass pre-commit hooks** (no commits here).
- **Never run mass-delete primitives.**
- **Never push.** Recommended actions to push the rationalization branch are surfaced for the user, not executed.
- **Never run `git push --delete` or force-push.**

## Coordination

- File reservation: `paths=["<workspace>/unblocked_work.md", "<workspace>/idea_wizard_suggestions.md", "<workspace>/handoff_report.md"]`, `exclusive=true`, `reason="branch-rationalization-unblocked-work"`, `ttl_seconds=1800`.
- Thread id: `branch-rationalization-<run-id>`.
- Coordinates with `handoff-reporter`: invoked after the initial handoff skeleton is written; appends the new section.

## Quality gates

- [ ] `unblocked_work.md` exists with the four core sections (newly-actionable, closed-by-commit, open PRs, potentially-obsolete) populated or marked empty
- [ ] Every recommended action is shown verbatim (the user can copy-paste)
- [ ] No `br update` / `gh pr close` actually ran
- [ ] Every confidence-gated invalidation has a numeric confidence ≥ 0.7
- [ ] If `/idea-wizard` was invoked, its suggestions appear in the report
- [ ] `handoff_report.md` has the new section appended

## Exit criteria

`unblocked_work.md` written and appended into `handoff_report.md`. The user reads it as part of the run summary; the user (not the finder) decides which recommended actions to run.
