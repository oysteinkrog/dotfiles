# The Polish Bar — Detailed Rubric

This is the verbose version of the Polish Bar table in [SKILL.md](../SKILL.md). For each dimension: the test, how to verify it, what failure looks like, and which operator to apply.

A run that fails any dimension is *incomplete*, not *finished*.

---

## P1: Recovery completeness

**Test:** every stash in the initial inventory has:
- A backup ref at `refs/stash-backup/<N>`
- A diff at `<bundle>/diffs/<N>.diff`
- A meta file at `<bundle>/meta/<N>.txt`
- An index entry in `<bundle>/index.tsv`
- (If the stash was `-u`) materialized untracked files in `<bundle>/stashed-untracked/<N>/`

Byte-equality verified for every backup ref vs. live stash (Phase 3).

**How to verify:**
```bash
n_inventory=$(awk 'NR > 1' "$WORKSPACE/inventory.tsv" | wc -l)
n_backup_refs=$(git for-each-ref refs/stash-backup/ | wc -l)
n_diffs=$(find "$BUNDLE/diffs" -maxdepth 1 -regextype posix-extended -type f -regex '.*/[0-9]{3,}\.diff' | wc -l)
n_metas=$(find "$BUNDLE/meta" -maxdepth 1 -type f -name '*.txt' | wc -l)
n_index=$(awk 'NR > 1' "$BUNDLE/index.tsv" | wc -l)

# All must equal $n_inventory.
[[ $n_backup_refs -eq $n_inventory ]] || fail
[[ $n_diffs       -eq $n_inventory ]] || fail
[[ $n_metas       -eq $n_inventory ]] || fail
[[ $n_index       -eq $n_inventory ]] || fail

# Every has_untracked=true row must have materialized files.
awk -F'\t' -v bundle="$BUNDLE" 'NR > 1 && $11 == "true" {
  dir = sprintf("%s/stashed-untracked/%03d", bundle, $1)
  cmd = "find \"" dir "\" -mindepth 1 -print -quit 2>/dev/null"
  if ((cmd | getline line) <= 0 || line == "") print "MISSING_UNTRACKED", $1
  close(cmd)
}' $WORKSPACE/inventory.tsv
# Must print nothing.

# Verify byte-equality:
grep -c MISMATCH $WORKSPACE/bundle_verification.log
# Must be 0.
```

**Failure looks like:** `bundle_verification.log` has any `MISMATCH` lines, or the counts above don't match.

**Operator to apply:** `⬡ BUNDLE` — re-run Phase 3 from scratch.

---

## P2: Verdict evidence

**Test:** every row in `triage.tsv` has:
- A non-empty `verdict` field (not `unknown`)
- A `confidence` ≥ 0.7 (or has been surfaced to user in Phase 5)
- An `evidence_on_main` field that's either a file:line citation OR `none` (with apply-check evidence backing it up)
- A `fingerprint_summary` ≤ 120 chars

**How to verify:**
```bash
# Count rows with empty fields:
awk -F'\t' '$2=="" || $3<0.7 || $4=="" {print NR}' $WORKSPACE/triage.tsv | wc -l
# Must be 0 (all confidence < 0.7 entries should have been resolved in Phase 5).
```

**Failure looks like:** rows with `unknown` verdict that didn't get user-resolved.

**Operator to apply:** re-run `◐ VERIFY-ON-MAIN` for the stale rows; re-present in Phase 5.

---

## P3: No phantom keepers

**Test:** for every `novel-and-accretive` row, the FINGERPRINT-VERIFY-ON-MAIN evidence chain proves the symbols don't exist on primary. No row is marked novel without that proof.

**How to verify:**
```bash
# For each novel-and-accretive row, the evidence_on_main field should be "none"
# or include "no symbols found":
awk -F'\t' '$2=="novel-and-accretive" {if ($4 != "none" && !match($4, /no symbols found/)) print NR}' \
  $WORKSPACE/triage.tsv
# Must be empty.
```

**Failure looks like:** a `novel-and-accretive` row whose `evidence_on_main` cites a file:line — meaning the symbol IS on main, contradicting the verdict.

**Operator to apply:** re-classify with the file:line evidence; should likely flip to `superseded`.

---

## P4: Per-apply gates

**Test:** every Phase 6 / Phase 7 commit has `gates_status=passed` in `apply_log.tsv` / `partial_split_log.tsv`. No commit was authored without all gates exiting 0.

**How to verify:**
```bash
# Every applied row must have gates_status=passed (or explicitly user-OKd
# pre-existing failure):
awk -F'\t' '$5 != "passed" && !match($5, /pre-existing-ok/) {print $0}' \
  $WORKSPACE/apply_log.tsv $WORKSPACE/partial_split_log.tsv
# Must be empty.
```

**Failure looks like:** a `gates_status=failed-skipped` row that has a `new_commit_sha` — meaning a commit was authored despite a gate failing.

**Operator to apply:** roll back the offending commit; re-attempt with the gate fix.

---

## P5: Focused commit messages

**Test:** every Phase 6 / Phase 7 commit message:
- Starts with a present-tense verb (`recover`, `restore`, `reapply`)
- Cites the source stash (`stash@{N}` and the bundle diff path)
- Explains the *why* in 2–4 sentences
- Does NOT include `Co-Authored-By` lines unless explicitly asked

**How to verify:**
```bash
git log stash-recovery-<DATE> --format='%s%n%b%n---' | \
  awk '/^---$/ {if (subj && !match(body, /stash@\{[0-9]+\}/)) print subj; subj=""; body=""; next}
       /^[a-z]/ && !subj {subj=$0; next}
       {body = body "\n" $0}'
# Output should be empty (every commit cites a stash).
```

**Failure looks like:** a commit message that's just `apply stash@{34}` — no why, no context.

**Operator to apply:** rewrite via `git commit --amend` (the only `--amend` use-case in this skill, and only on the recovery branch's tip while it's not yet pushed).

---

## P6: Order of drops

**Test:** Phase 9's `cleanup_log.tsv` shows drops in the order: garbage → superseded / superseded-by-newer-stash → novel-but-stale → applied-keeper, and within each bucket, indexes are descending.

**How to verify:**
```bash
# Verdicts should appear in the order garbage, superseded/superseded-by-newer-stash, novel-but-stale, applied-keeper:
awk -F'\t' 'NR > 1 {print $4}' "$WORKSPACE/cleanup_log.tsv" | uniq
# Should be a sequence like:
#   garbage
#   garbage
#   ...
#   superseded
#   ...
#   novel-but-stale
#   ...
#   applied-keeper

# Within each bucket, indexes (column 1, n) should be descending:
awk -F'\t' 'NR > 1 {if ($4 != prev_verdict) {prev_n=999999; prev_verdict=$4} \
  if ($1 >= prev_n) print "ORDER VIOLATION: row " NR; prev_n=$1}' \
  $WORKSPACE/cleanup_log.tsv
# Must be empty.
```

**Failure looks like:** drops out of order — likely caused indexes to shift wrong, drops the wrong stashes.

**Operator to apply:** halt the run; recovery via R6 (full restore from backup refs); re-run Phase 9 with corrected order.

---

## P7: Verbatim authorization

**Test:** `cleanup_authorization.txt` contains the user's exact text + UTC timestamp. The authorization line must match the cleanup-conductor template, not merely contain a vague substring like "proceed with cleanup".

**How to verify:**
```bash
test -s $WORKSPACE/cleanup_authorization.txt || fail "no authorization recorded"
AUTHORIZATION_RE='^[[:space:]]*yes[[:space:]]+i[[:space:]]+understand[[:space:]]+and[[:space:]]+want[[:space:]]+to[[:space:]]+drop[[:space:]]+all[[:space:]]+[0-9]+[[:space:]]+stash(es)?[[:space:]]+per[[:space:]]+the[[:space:]]+plan[[:space:]]+above[[:space:]]*$'
grep -Eiq "$AUTHORIZATION_RE" \
  $WORKSPACE/cleanup_authorization.txt || fail "authorization phrase not specific enough"
```

**Failure looks like:** missing file, file contains "yes" / "ok" alone, or a negated sentence such as "do not proceed with cleanup" that happens to include an old loose substring.

**Operator to apply:** `⚠ CONFIRM` re-asked with explicit phrase template; never proceed without specific phrase.

---

## P8: Idempotent on a clean repo

**Test:** running the skill twice in succession on a freshly-cleaned repo produces no new commits and reports "nothing to do."

**How to verify:**
```bash
# First run completes; record HEAD:
sha1=$(git -C <project> rev-parse HEAD)

# Re-run the skill on the same project. Expected behavior:
# - Phase 1: re-uses project_profile.json (fresh)
# - Phase 2: produces empty inventory.tsv
# - Phase 3: produces empty bundle (or detects existing one with byte-eq match)
# - Phases 4–9: short-circuit ("nothing to do")
# - Phase 10: handoff_report.md says "0 stashes triaged, 0 commits authored"

sha2=$(git -C <project> rev-parse HEAD)
[[ "$sha1" == "$sha2" ]] || fail "second run authored commits on a clean repo"
```

**Failure looks like:** second run authors commits or modifies files.

**Operator to apply:** investigate Phase 6's logic for "nothing to apply" detection; should short-circuit when `triage.tsv` has zero `novel-and-accretive` rows.

---

## P9: Resumable mid-run

**Test:** a run interrupted mid-Phase 6 can be resumed without re-applying already-applied stashes.

**How to verify:**
```bash
# Spawn the run; let it apply 2 of 5 keepers; kill it.
# Re-spawn the run on the same project.
# Expected: it detects the existing workspace, offers resume, picks up where Phase 6 stopped.
# Verifies via apply_log.tsv:
awk -F'\t' '{if ($3) applied++} END {print applied}' $WORKSPACE/apply_log.tsv
# After resume, this should reflect all 5 applies, with 2 from before-interrupt.
```

**Failure looks like:** resume re-applies the first 2 keepers and produces duplicate commits.

**Operator to apply:** Phase 6's resume logic must compare `n` against `apply_log.tsv` and skip rows already marked applied.

---

## P10: No phantom side effects

**Test:** the skill does NOT:
- Modify the primary branch
- Push anything to a remote
- Delete the bundle
- Delete `refs/stash-backup/*`
- Create files outside the workspace and bundle directories
- Modify files in the source repo other than the recovered hunks

**How to verify:**
```bash
# Primary branch unchanged:
git rev-parse origin/<primary> == $(git rev-parse <primary>)

# Bundle still exists:
test -d $BUNDLE

# Backup refs still exist:
[[ $(git for-each-ref refs/stash-backup/ | wc -l) -eq <expected_count> ]]

# No remote operations:
git -C <project> reflog --all | grep -E 'push|fetch' | grep -v "<expected>"
# Should be empty.
```

**Failure looks like:** any of the above tripped.

**Operator to apply:** halt the run; investigate which phase did the unauthorized action; revert.

---

## Polish-Bar Self-Check Script

`scripts/polish-bar-check.sh` runs all 10 dimensions and reports pass/fail. Phase 10 should run this before declaring the run successful; any failures escalate to the user.

---

## When the Polish Bar Conflicts With User Direction

If the user explicitly authorizes a Polish-Bar violation (e.g., "go ahead and commit even though clippy fails — that warning is pre-existing and unrelated"):

1. Record the user's exact text in `apply_log.tsv:gates_status` as `pre-existing-ok: <user-authorization-text>`.
2. Proceed.
3. Report the override in the handoff report.

The Polish Bar is the default, not a hard wall — but every override needs a paper trail.
