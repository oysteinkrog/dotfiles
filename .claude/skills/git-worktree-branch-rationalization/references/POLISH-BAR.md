# The Polish Bar — Detailed Rubric

This is the verbose version of the Polish Bar table in [SKILL.md § Polish Bar](../SKILL.md#the-polish-bar-non-negotiable). For each dimension: the test, how to verify it, what failure looks like, the per-phase checklist, and which operator to apply.

A run that fails any dimension is *incomplete*, not *finished*. The check script that runs all 10 dimensions is `scripts/polish-bar-check.sh`; Phase 11 runs it before declaring the run successful.

---

## P1: Recovery Completeness

**Test:** every branch in `branches.tsv` has:
- A backup ref at `refs/branch-rationalization-backup/<slug>`
- A diff at `<bundle>/branches/<slug>/diff-vs-merge-base.diff`
- A format-patch series under `<bundle>/branches/<slug>/format-patch/*.patch`
- A `meta.txt` at `<bundle>/branches/<slug>/meta.txt`
- A `commits.tsv` at `<bundle>/branches/<slug>/commits.tsv`
- An index entry in `<bundle>/index.tsv`

Every worktree in `worktrees.tsv` has:
- A `staged.diff` at `<bundle>/worktrees/<wt-slug>/staged.diff`
- An `unstaged.diff` at `<bundle>/worktrees/<wt-slug>/unstaged.diff`
- A `.untracked.list` at `<bundle>/worktrees/<wt-slug>/.untracked.list` (if the worktree had untracked content at Phase 3)
- An `untracked.tar.gz` at `<bundle>/worktrees/<wt-slug>/untracked.tar.gz` (if the worktree had untracked content at Phase 3)
- A `status.txt` at `<bundle>/worktrees/<wt-slug>/status.txt`
- A `meta.txt` at `<bundle>/worktrees/<wt-slug>/meta.txt`
- An index entry in `<bundle>/index.tsv`

Plus: byte-equality verified for every backup ref vs. live branch (Phase 3); `object-bundle.pack` round-trips via `git bundle list-heads` (Phase 3).

**Per-phase checklist:**
- Phase 3 — `⬡ BUNDLE` produces every artifact AND verifies. **Hard gate.**
- Phase 11 — `scripts/polish-bar-check.sh` re-runs the verification before emitting `handoff_report.md`.

**How to verify:**
```bash
n_branches=$(awk 'NR > 1' "$WS/branches.tsv" | wc -l)
n_worktrees=$(awk 'NR > 1' "$WS/worktrees.tsv" | wc -l)

# Per-branch artifacts
n_backup_refs=$(git -C "$PROJECT" for-each-ref refs/branch-rationalization-backup/ | wc -l)
n_branch_diffs=$(find "$BUNDLE/branches" -mindepth 2 -maxdepth 2 -type f -name 'diff-vs-merge-base.diff' | wc -l)
n_format_dirs=$(find "$BUNDLE/branches" -mindepth 2 -maxdepth 2 -type d -name 'format-patch' | wc -l)
n_branch_metas=$(find "$BUNDLE/branches" -mindepth 2 -maxdepth 2 -type f -name 'meta.txt' | wc -l)
n_branch_commits=$(find "$BUNDLE/branches" -mindepth 2 -maxdepth 2 -type f -name 'commits.tsv' | wc -l)

# Canonical is excluded from branches.tsv. Every inventoried branch gets the
# recovery layers, including protected branches; the bundle is for recovery, not
# only for deletion candidates.
n_expected=$n_branches

[[ $n_backup_refs    -eq $n_expected ]] || fail "backup ref count mismatch"
[[ $n_branch_diffs   -eq $n_expected ]] || fail "branch diff count mismatch"
[[ $n_format_dirs    -eq $n_expected ]] || fail "format-patch dir count mismatch"
[[ $n_branch_metas   -eq $n_expected ]] || fail "branch meta count mismatch"
[[ $n_branch_commits -eq $n_expected ]] || fail "branch commits.tsv count mismatch"

# Per-worktree artifacts
n_wt_staged=$(find "$BUNDLE/worktrees" -mindepth 2 -maxdepth 2 -type f -name 'staged.diff' | wc -l)
n_wt_unstaged=$(find "$BUNDLE/worktrees" -mindepth 2 -maxdepth 2 -type f -name 'unstaged.diff' | wc -l)
n_wt_status=$(find "$BUNDLE/worktrees" -mindepth 2 -maxdepth 2 -type f -name 'status.txt' | wc -l)
n_wt_metas=$(find "$BUNDLE/worktrees" -mindepth 2 -maxdepth 2 -type f -name 'meta.txt' | wc -l)

[[ $n_wt_staged   -eq $n_worktrees ]] || fail "wt staged count mismatch"
[[ $n_wt_unstaged -eq $n_worktrees ]] || fail "wt unstaged count mismatch"
[[ $n_wt_status   -eq $n_worktrees ]] || fail "wt status count mismatch"
[[ $n_wt_metas    -eq $n_worktrees ]] || fail "wt meta count mismatch"

# Worktrees with untracked content (worktrees.tsv:untracked_count, column 13)
# must have .untracked.list and untracked.tar.gz. `sanitize_path` must match scripts/project-root.sh.
. "$SKILL_DIR/scripts/project-root.sh"
while IFS=$'\t' read -r path _branch _detached _bare _locked _prunable _sha _date _dirty _staged _unstaged _untracked_bytes untracked_count _rest; do
  [[ "$path" == "path" ]] && continue
  [[ "${untracked_count:-0}" -gt 0 ]] || continue
  wt_slug=$(sanitize_path "$path")
  test -s "$BUNDLE/worktrees/$wt_slug/.untracked.list" || \
    echo "MISSING_UNTRACKED_MANIFEST $path"
  test -s "$BUNDLE/worktrees/$wt_slug/untracked.tar.gz" || \
    echo "MISSING_UNTRACKED $path"
done < "$WS/worktrees.tsv"
# Must print nothing.

# Index covers everything
n_index=$(awk 'NR > 1' "$BUNDLE/index.tsv" | wc -l)
[[ $n_index -eq $((n_expected + n_worktrees)) ]] || fail "index.tsv count mismatch"

# Byte-equality + bundle round-trip
grep -c MISMATCH "$WS/bundle_verification.log"
# Must be 0.
```

**Failure looks like:** `bundle_verification.log` has any `MISMATCH` lines, or any of the counts above don't match.

**Operator to apply:** `⬡ BUNDLE` — re-run Phase 3 from scratch.

---

## P2: Verdict Evidence

**Test:** every row in `triage.tsv` has:
- A non-empty `verdict` field (not `unknown`, unless surfaced and resolved by user)
- A `confidence` ≥ 0.7 (or has been surfaced to user in Phase 6)
- An `evidence_on_canonical` field that's either a file:line citation OR `none` (with apply-check + cherry-summary evidence backing it up)
- A `fingerprint_summary` ≤ 120 chars
- A `strategy` field with a known value (`skip` / `cherry-pick` / `squash-merge` / `rebase-and-merge` / `harmonized-synthesis-via-Edit` / `split-commits-hunks` / `worktree-dirty-state` / `manual`)
- A `files_touched` field (count of files in the diff vs merge-base)

**Per-phase checklist:**
- Phase 5 — `✦ FINGERPRINT` + `◐ VERIFY-ON-CANONICAL` per worker; every row produced by every batch.
- Phase 6 — merger fills in any blanks; user resolves any `unknown` rows.

**How to verify:**
```bash
# Count rows with empty fields or sub-threshold confidence:
awk -F'\t' '
  NR > 1 && ($3 == "" || $4 < 0.7 || $5 == "" || $7 == "" || $8 == "")
' "$WS/triage.tsv" | wc -l
# Must be 0 (all confidence < 0.7 entries should have been resolved in Phase 6).

# No remaining `unknown` rows:
awk -F'\t' 'NR > 1 && $3 == "unknown"' "$WS/triage.tsv" | wc -l
# Must be 0.
```

**Failure looks like:** rows with `unknown` verdict that didn't get user-resolved, or rows with confidence < 0.7 that weren't surfaced.

**Operator to apply:** re-run `◐ VERIFY-ON-CANONICAL` for the stale rows; re-present in Phase 6.

---

## P3: No Phantom Keepers

**Test:** for every `novel-and-accretive` row, the `✦ FINGERPRINT` → `◐ VERIFY-ON-CANONICAL` evidence chain proves the symbols don't exist on canonical AND the cherry-summary shows at least one `+` line. No row is marked novel without that proof.

> **Why:** [SKILL.md "Polish Bar" P3](../SKILL.md#the-polish-bar-non-negotiable): "No branch is marked 'novel' without FINGERPRINT proving its symbols don't appear on canonical AND `git cherry -v` showing at least one `+` line; 'I think it's novel' is never acceptable."

**Per-phase checklist:**
- Phase 5 — every `novel-and-accretive` row's `evidence_on_canonical` field is `none` OR cites grep-empty output proving "no symbols found".
- Phase 5 — every `novel-and-accretive` row's underlying branch has `cherry_pluses ≥ 1` in `branches.tsv`.

**How to verify:**
```bash
# For each novel-and-accretive row, the evidence_on_canonical field should be
# "none" or include "no symbols found":
awk -F'\t' '
  $3 == "novel-and-accretive" {
    if ($5 != "none" && !match($5, /no symbols found/)) print NR
  }
' "$WS/triage.tsv"
# Must be empty.

# For each novel-and-accretive row, the underlying branch must have cherry_pluses ≥ 1:
join -t$'\t' -1 2 -2 1 \
  <(awk -F'\t' 'NR>1 && $3=="novel-and-accretive" {print $1"\t"$2}' "$WS/triage.tsv" | sort -k2,2) \
  <(awk -F'\t' 'NR>1 && $1=="branch" {print $1"\t"$5}' "$WS/branches.tsv" | sort -k1,1) \
| awk -F'\t' '$3 < 1 {print "phantom-novel:", $1}'
# Must be empty.
```

**Failure looks like:** a `novel-and-accretive` row whose `evidence_on_canonical` cites a `file:line` (meaning the symbol IS on canonical, contradicting the verdict), OR whose underlying branch's `cherry_pluses == 0` (meaning every commit's patch-id is already on canonical).

**Operator to apply:** re-classify with the file:line evidence; should likely flip to `superseded` or `already-merged`.

---

## P4: Harmonization Fidelity

**Test:** every file touched by ≥2 non-protected branches (or by any combination of branches + dirty-worktree-only) has an entry in `harmonization_plan.md` with:
- A variant matrix table
- An intent-groups section
- A proposed synthesis with explicit base-branch + grafted-hunks attribution
- A "Why this beats any single variant" section
- Source-branch credit for the commit message

> **Why:** [SKILL.md Polish Bar "Harmonization fidelity"](../SKILL.md#the-polish-bar-non-negotiable): "Every file touched by ≥2 non-protected branches has an entry in `harmonization_plan.md` with the variant matrix; every entry cites specific source branches; every synthesis explains *why* this combination beats any single variant."

**Per-phase checklist:**
- Phase 7 — `◇ HARMONIZE` produces `harmonization_plan.md` with one block per colliding-file group.
- Phase 8 — every harmonized-synthesis-via-Edit commit references a block in `harmonization_plan.md`.

**How to verify:**
```bash
# Build the colliding-file set from triage.tsv (filtered to non-protected,
# non-already-merged, non-garbage):
awk -F'\t' '
  NR > 1 && $3 !~ /protected-preserve|already-merged|garbage|canonical/ {
    n = split($9, files, ",")
    for (i = 1; i <= n; i++) print files[i] "\t" $2
  }
' "$WS/triage.tsv" | \
  sort | \
  awk -F'\t' '{a[$1] = a[$1] "," $2; c[$1]++} END {for (f in c) if (c[f] >= 2) print f}' \
  > "$WS/_colliding_files.txt"

# Every colliding file must appear in harmonization_plan.md:
while read -r file; do
  grep -qF "## File: $file" "$WS/harmonization_plan.md" || \
    echo "MISSING_HARMONIZATION_BLOCK: $file"
done < "$WS/_colliding_files.txt"
# Must print nothing.

# Every harmonized-synthesis-via-Edit commit must reference harmonization_plan.md:
git log "$RB" --grep='harmonized' --format='%h %s' | \
  while read -r sha rest; do
    body=$(git log -1 --format='%b' "$sha")
    echo "$body" | grep -qF 'harmonization_plan.md' || echo "ORPHAN_HARMONIZED: $sha $rest"
  done
# Must print nothing.
```

**Failure looks like:** a file touched by ≥2 branches that has no `## File:` block in `harmonization_plan.md`, OR a harmonized-synthesis commit whose body doesn't cite the plan.

**Operator to apply:** re-run `◇ HARMONIZE` for the missing colliding-file groups; re-present in Phase 7.

---

## P5: Per-Apply Gates

**Test:** every Phase 8 / Phase 8b commit has `gates_status=passed` in `apply_log.tsv` / `partial_split_log.tsv`. No commit was authored without all gates exiting 0 (or with a `pre-existing-ok: <user-text>` annotation that includes the user's verbatim authorization).

> **Why:** [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms): "Per-apply gates are non-negotiable. Compounding errors across recoveries are an order of magnitude harder to debug than per-keeper failures."

**Per-phase checklist:**
- Phase 8 — `⊕ RECOVER` after every successful apply.
- Phase 8b — `⊕ RECOVER` after every split-apply.

**How to verify:**
```bash
# Every applied row must have gates_status=passed (or explicitly user-OKd
# pre-existing failure):
awk -F'\t' '
  NR > 1 && $4 != "" && $6 != "passed" && !match($6, /^pre-existing-ok:/)
' "$WS/apply_log.tsv" "$WS/partial_split_log.tsv"
# Must be empty.

# No commit on the rationalization branch lacks an apply_log.tsv row:
git log "$RB" --not "$CANONICAL" --format='%H' | sort \
  > "$WS/_rb_commits.txt"
awk -F'\t' 'NR > 1 && $4 != "" {print $4}' "$WS/apply_log.tsv" | sort \
  > "$WS/_logged_commits.txt"
diff "$WS/_rb_commits.txt" "$WS/_logged_commits.txt"
# Must be empty (every RB commit is in the log; every logged commit is on RB).
```

**Failure looks like:** a `gates_status=failed-skipped` row that has a `new_commit_sha` (meaning a commit was authored despite a gate failing), OR a commit on the rationalization branch with no corresponding apply_log row.

**Operator to apply:** roll back the offending commit via `git reset --soft HEAD~1`; re-attempt with the gate fix.

---

## P6: Focused Commit Messages

**Test:** every Phase 8 / Phase 8b commit message:
- Starts with a present-tense verb (`recover`, `restore`, `integrate`, `harmonize`)
- Cites the source branch(es) (or "from worktree dirty state")
- Cites the bundle path or backup ref name
- Explains the *why* in 2–4 sentences (or per-variant attribution for harmonized syntheses)
- Names variant intents for harmonized syntheses (e.g., "defensive null-check from cod-3", "v3 architecture from cc-12")
- Does NOT include `Co-Authored-By` lines unless explicitly asked

> **Why:** [SKILL.md Polish Bar "Focused commit messages"](../SKILL.md#the-polish-bar-non-negotiable): "Each keeper-commit explains *why* this content is being recovered, naming source branches and variant intents: not 'cherry-pick from agent-cleanup-pass-3' but 'recover defensive null-check from agent-cleanup-pass-3 + parser-fixture from feature/parse-hardening + type-narrowing from worktree dirty-state, harmonized on top of canonical's current structure'."

**Per-phase checklist:**
- Phase 8 — every apply commit message follows the focused-commit-message rubric.
- Phase 8b — every split-apply commit message explicitly notes "split-apply: novel commits/hunks only".

**How to verify:**
```bash
# Every commit on the rationalization branch (not on canonical) cites a source:
git log "$RB" --not "$CANONICAL" --format='%H%n%s%n%b%n---' | \
  awk '
    /^---$/ {
      if (subj && !match(body, /(refs\/branch-rationalization-backup|harmonization_plan\.md|worktree dirty state|stash@\{)/)) {
        print "ORPHAN: " sha " " subj
      }
      sha = ""; subj = ""; body = ""; next
    }
    /^[a-f0-9]{40}$/ && !sha { sha = $0; next }
    !subj { subj = $0; next }
    { body = body "\n" $0 }
  '
# Output should be empty.

# No commit body has a Co-Authored-By line (unless user requested):
git log "$RB" --not "$CANONICAL" --grep='Co-Authored-By' --format='%H' | wc -l
# Should be 0.
```

**Failure looks like:** a commit message that's just `cherry-pick agent-cc-12-feat-parser` — no why, no context, no source citation.

**Operator to apply:** rewrite via `git commit --amend` (the only `--amend` use-case in this skill, and only on the rationalization branch's tip while it's not yet pushed).

---

## P7: Order of Cleanup

**Test:** Phase 10's `cleanup_log.tsv` schema is `phase, kind, target, verdict, command_run, backup_ref, timestamp_utc, notes` and shows operations in the order: **worktrees first** (Phase A: `git worktree remove` per worktree, then `git worktree prune`), **then branches** (Phase B: garbage; Phase C: superseded; Phase D: already-merged; Phase E: novel-stale; Phase F: divergent-refactor (opt-in); Phase G: applied-keepers).

Within each branch bucket, deletions are independent; ordering within a bucket doesn't matter for correctness, but the bucket-bucket ordering does.

> **Why:** [SKILL.md Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms): "Worktrees are removed first, branches second. A worktree pinned to a branch protects that branch from `git branch -d`. Removing the worktree first frees the branch."

**Per-phase checklist:**
- Phase 10 — `⊙ PRUNE-WORKTREE` runs in Phase A (all worktree removals), then `git worktree prune` for residual metadata, then `⊘ DELETE-BRANCH` runs in Phases B–G.

**How to verify:**
```bash
# Every cleanup_log row has a phase letter (A through G) and command_run:
awk -F'\t' 'NR > 1 && ($1 !~ /^[A-G]$/ || $5 == "") {print "BAD CLEANUP ROW:", $0}' "$WS/cleanup_log.tsv"
# Must be empty.

# Phase A rows all come before Phase B rows; B before C; … :
awk -F'\t' '
  NR > 1 {
    cur = $1
    if (cur < prev) { print "ORDER VIOLATION: row " NR " phase=" cur " after phase=" prev; exit }
    prev = cur
  }
' "$WS/cleanup_log.tsv"
# Must be empty.

# All worktree removals (kind=worktree) are in Phase A:
awk -F'\t' 'NR > 1 && $2 == "worktree" && $1 != "A" {print "BAD KIND/PHASE:", $0}' \
  "$WS/cleanup_log.tsv"
# Must be empty.

# All branch deletions (kind=branch) are in Phases B–G:
awk -F'\t' 'NR > 1 && $2 == "branch" && $1 !~ /^[B-G]$/ {print "BAD KIND/PHASE:", $0}' \
  "$WS/cleanup_log.tsv"
# Must be empty.
```

**Failure looks like:** a `git branch -d` row with phase=A or before any phase=A row — likely caused a `-d` refusal because the branch was still pinned by a worktree.

**Operator to apply:** halt the run; investigate which worktree was missed; recover via the bundle's per-worktree captures; re-run Phase 10 with corrected order.

---

## P8: Verbatim Authorization

**Test:** `cleanup_authorization.txt` contains the user's exact text + UTC timestamp. The authorization line must match the cleanup-conductor phrase (`yes I understand and want to rationalize per the plan above`), not merely contain a vague substring like "proceed with cleanup".

For dirty-worktree force-removals: per-worktree sub-authorization captured alongside `cleanup_log.tsv:command_run` and validated against the `🌳 WORKTREE-CHECK` flow.

> **Why:** AGENTS.md "Document the confirmation": "If that record is absent, the operation did not happen." [SKILL.md Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms).

**Per-phase checklist:**
- Phase 10 — `⚠ CONFIRM` writes `cleanup_authorization.txt` before any operation.
- Phase 10 sub-gate — every `git worktree remove --force` has a separate sub-authorization recorded inline in `cleanup_log.tsv`.

**How to verify:**
```bash
test -s "$WS/cleanup_authorization.txt" || fail "no authorization recorded"

AUTHORIZATION_RE='^[[:space:]]*yes[[:space:]]+i[[:space:]]+understand[[:space:]]+and[[:space:]]+want[[:space:]]+to[[:space:]]+rationalize[[:space:]]+per[[:space:]]+the[[:space:]]+plan[[:space:]]+above[[:space:]]*$'
grep -Eiq "$AUTHORIZATION_RE" "$WS/cleanup_authorization.txt" || \
  fail "authorization phrase not specific enough"

# Every cleanup row must have a recorded command_run:
awk -F'\t' 'NR > 1 && $5 == "" {print "MISSING_COMMAND:", $0}' "$WS/cleanup_log.tsv"
# Must be empty.
```

**Failure looks like:** missing file, file contains "yes" / "ok" alone, file contains a vague phrase that doesn't quote the command, OR a `cleanup_log.tsv` row whose command doesn't appear in the verbatim plan.

**Operator to apply:** `⚠ CONFIRM` re-asked with explicit phrase template; never proceed without specific phrase.

---

## P9: Idempotent on a Clean Repo

**Test:** running the skill twice in succession on a freshly-cleaned repo produces no new commits, no new removals, no new deletions, and reports "nothing to rationalize."

> **Why:** [SKILL.md Polish Bar "Idempotent on a clean repo"](../SKILL.md#the-polish-bar-non-negotiable): "Re-running on a freshly-cleaned repo produces no commits and reports 'nothing to rationalize.'"

**Per-phase checklist:**
- Phases 5+ — short-circuit when `triage.tsv` has no non-protected, non-already-merged rows.
- Phase 8 — short-circuit when `triage.tsv` has zero `novel-and-accretive` / `partially-novel` / `dirty-worktree-only` / harmonized-synthesis rows.
- Phase 10 — short-circuit when there's nothing to remove or delete.

**How to verify:**
```bash
# First run completes; record HEAD:
sha1=$(git -C "$PROJECT" rev-parse HEAD)
n_branches_1=$(git -C "$PROJECT" branch | wc -l)
n_worktrees_1=$(git -C "$PROJECT" worktree list | wc -l)

# Re-run the skill on the same project. Expected behavior:
# - Phase 0: re-uses workspace; offers resume vs fresh; user says fresh.
# - Phase 1: re-uses project_profile.json (fresh enough).
# - Phase 2: produces inventories with only canonical + protected + rationalization branch.
# - Phase 3: produces empty bundle (or detects existing one with byte-eq match).
# - Phase 4: protection list = canonical + rationalization branch + previous protected.
# - Phases 5–10: short-circuit ("nothing to rationalize").
# - Phase 11: handoff_report.md says "0 branches triaged, 0 commits authored, 0 removals".

sha2=$(git -C "$PROJECT" rev-parse HEAD)
n_branches_2=$(git -C "$PROJECT" branch | wc -l)
n_worktrees_2=$(git -C "$PROJECT" worktree list | wc -l)

[[ "$sha1" == "$sha2" ]]                || fail "second run authored commits"
[[ "$n_branches_1" -eq "$n_branches_2" ]] || fail "second run changed branches"
[[ "$n_worktrees_1" -eq "$n_worktrees_2" ]] || fail "second run changed worktrees"
```

**Failure looks like:** second run authors commits, removes worktrees, or deletes branches.

**Operator to apply:** investigate Phase 5/8/10's logic for "nothing to do" detection; should short-circuit when the relevant TSV has no candidate rows.

---

## P10: Resumable Mid-Run

**Test:** a run interrupted mid-Phase 8 can be resumed without re-applying already-applied keepers OR re-removing already-removed worktrees OR re-deleting already-deleted branches.

> **Why:** [SKILL.md Polish Bar "Resumable"](../SKILL.md#the-polish-bar-non-negotiable): "If interrupted mid-Phase 8, re-running picks up from the last successful commit using `apply_log.tsv` + git log on the rationalization branch."

**Per-phase checklist:**
- Phase 0 — detects existing `.worktree_branch_rationalization_workspace/` and offers resume.
- Phase 3 — verifies existing bundle via byte-equality + round-trip; reuses if clean.
- Phase 5 — re-runs only batches without complete `batch_NNN.tsv`.
- Phase 8 — reads `apply_log.tsv` and skips already-applied entries.
- Phase 10 — refuses to re-run; if `cleanup_log.tsv` exists, the user must explicitly archive workspace and start fresh.

**How to verify:**
```bash
# Spawn the run; let it apply 2 of 5 keepers; kill it.
# Re-spawn the run on the same project.
# Expected: it detects the existing workspace, offers resume, picks up where Phase 8 stopped.
# Verifies via apply_log.tsv:
applied_count=$(awk -F'\t' 'NR > 1 && $4 != "" && $6 == "passed" {n++} END {print n}' \
  "$WS/apply_log.tsv")
# After resume, this should reflect all 5 applies, with 2 from before-interrupt
# (no duplicates).

# No duplicate commits on the rationalization branch:
git log "$RB" --not "$CANONICAL" --format='%H' | sort -u | wc -l
git log "$RB" --not "$CANONICAL" --format='%H' | wc -l
# Must be equal.
```

**Failure looks like:** resume re-applies already-applied keepers and produces duplicate commits.

**Operator to apply:** Phase 8's resume logic must compare `kind|name` against `apply_log.tsv` and skip rows already marked applied.

---

## P-Bonus: No Phantom Side Effects

**Test:** the skill does NOT:
- Modify the canonical branch
- Push anything to a remote
- Delete the bundle
- Delete `refs/branch-rationalization-backup/*`
- Run any of: `git push --delete`, `git push --force`, `rm -rf`, `git reset --hard`, `git clean -fd`, `git update-ref -d`
- Stash, revert, or overwrite changes from other agents in any worktree
- Remove the currently-active worktree (the user's CWD)
- Create files outside the workspace and bundle directories
- Modify files in the source repo other than the recovered hunks (committed only on the rationalization branch)

**How to verify:**
```bash
# Canonical branch unchanged (matches origin's tip if remote exists):
local_canonical=$(git -C "$PROJECT" rev-parse "$CANONICAL")
remote_canonical=$(git -C "$PROJECT" rev-parse "origin/$CANONICAL" 2>/dev/null || echo "no-remote")
[[ "$remote_canonical" == "no-remote" || "$local_canonical" == "$remote_canonical" ]] \
  || fail "canonical branch advanced locally"

# Bundle still exists:
test -d "$BUNDLE" || fail "bundle directory missing"
test -s "$BUNDLE/object-bundle.pack" || fail "object bundle missing"

# Backup refs still exist:
n_backup=$(git -C "$PROJECT" for-each-ref refs/branch-rationalization-backup/ | wc -l)
[[ $n_backup -ge 1 ]] || fail "no backup refs left"

# No remote operations in reflog:
git -C "$PROJECT" reflog --all | grep -E '^\w+ (refs/remotes|HEAD@\{[0-9]+\}: push)' \
  | grep -v "<expected>"
# Should be empty.

# Active worktree (CWD) is still in the worktree list:
test -d "$PROJECT" || fail "active worktree gone"
```

**Failure looks like:** any of the above tripped.

**Operator to apply:** halt the run; investigate which phase did the unauthorized action; revert via the bundle.

---

## Polish-Bar Self-Check Script

`scripts/polish-bar-check.sh` runs all 10 dimensions plus the bonus dimension and reports pass/fail. Phase 11 should run this before declaring the run successful; any failures escalate to the user.

The script uses the verification queries above, formatted as one-test-per-dimension. Output is a markdown table:

```
| Dimension                         | Status | Failures |
|-----------------------------------|--------|----------|
| P1: Recovery completeness         | PASS   | —        |
| P2: Verdict evidence              | PASS   | —        |
| P3: No phantom keepers            | PASS   | —        |
| P4: Harmonization fidelity        | FAIL   | src/auth.rs missing harmonization block |
| P5: Per-apply gates               | PASS   | —        |
| P6: Focused commit messages       | PASS   | —        |
| P7: Order of cleanup              | PASS   | —        |
| P8: Verbatim authorization        | PASS   | —        |
| P9: Idempotent on a clean repo    | (skipped — needs second run) | — |
| P10: Resumable mid-run            | (skipped — needs interrupt test) | — |
| Bonus: No phantom side effects    | PASS   | —        |
```

P9 and P10 are integration tests that the per-run check skips by default; they're run by `scripts/integration-test.sh` against synthetic repos.

---

## When the Polish Bar Conflicts With User Direction

If the user explicitly authorizes a Polish-Bar violation (e.g., "go ahead and commit even though clippy fails — that warning is pre-existing and unrelated"):

1. Record the user's exact text in `apply_log.tsv:gates_status` as `pre-existing-ok: <user-authorization-text>`.
2. Proceed.
3. Report the override in the handoff report under a "Polish Bar overrides" section.

The Polish Bar is the default, not a hard wall — but every override needs a paper trail.

> **Why:** AGENTS.md "Mandatory explicit plan" + "Document the confirmation" — overrides are user authorizations, and authorizations must be recorded with verbatim text.

---

## Quick Cross-Reference

| Polish-Bar Dimension | Operator that fixes it | Phase that enforces it |
|----------------------|------------------------|------------------------|
| P1 Recovery completeness | `⬡ BUNDLE` | 3 |
| P2 Verdict evidence | `✦ FINGERPRINT` + `◐ VERIFY-ON-CANONICAL` | 5 |
| P3 No phantom keepers | `✦ FINGERPRINT` + `◐ VERIFY-ON-CANONICAL` (+ cherry-summary check) | 5 |
| P4 Harmonization fidelity | `◇ HARMONIZE` | 7 |
| P5 Per-apply gates | `⊕ RECOVER` | 8, 8b |
| P6 Focused commit messages | (commit message rubric in this file + `git commit --amend` if needed) | 8, 8b |
| P7 Order of cleanup | `⊙ PRUNE-WORKTREE` (Phase A) → `⊘ DELETE-BRANCH` (Phases B–G) | 10 |
| P8 Verbatim authorization | `⚠ CONFIRM` | 6, 7, 10 |
| P9 Idempotent on a clean repo | (short-circuit logic in each phase) | all |
| P10 Resumable mid-run | (resume logic in each phase) | all |
| Bonus No phantom side effects | (whole-skill discipline; AGENTS.md "Irreversible Git & Filesystem Actions") | all |

When a polish-bar dimension fails, the verification query points at the offending row(s) / file(s), the operator card explains the cognitive move to apply, and the phase that owns the dimension is the place to re-run.
