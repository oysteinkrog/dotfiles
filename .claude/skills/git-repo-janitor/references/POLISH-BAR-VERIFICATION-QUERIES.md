# Polish Bar Verification Queries

Each Polish-Bar dimension in [POLISH-BAR.md](POLISH-BAR.md) is a binary check. This reference provides the LITERAL grep / git command / script invocation that proves each dimension passed.

Source: saas-billing-patterns POLISH-BAR.md pattern.

---

## Dimension 1: Recovery completeness

**Check:** Every candidate has a working-tree-copy in the bundle AND a meta entry AND an index row; byte-equality verified before any destructive phase.

**Verification queries:**

```bash
# Number of candidates
candidate_count=$(tail -n +2 .repo_janitor_workspace/candidates.tsv | wc -l)

# Number of working-tree-copies in the bundle
bundle=$(cat .repo_janitor_workspace/bundle_path.txt)
copy_count=$(find "$bundle/working-tree-copies" -type f 2>/dev/null | wc -l)

# Number of meta files
meta_count=$(find "$bundle/meta" -name '*.txt' 2>/dev/null | wc -l)

# Number of index rows
index_count=$(tail -n +2 "$bundle/index.tsv" 2>/dev/null | grep -v '^#' | wc -l)

# All four must be equal
[[ "$candidate_count" == "$copy_count" ]] || echo "FAIL: copies ($copy_count) != candidates ($candidate_count)"
[[ "$candidate_count" == "$meta_count" ]] || echo "FAIL: metas ($meta_count) != candidates ($candidate_count)"
[[ "$candidate_count" == "$index_count" ]] || echo "FAIL: index rows ($index_count) != candidates ($candidate_count)"

# Byte-equality verification log must show 0 mismatches
mismatch_count=$(grep -c MISMATCH .repo_janitor_workspace/bundle_verification.log 2>/dev/null || echo 0)
[[ "$mismatch_count" == "0" ]] || echo "FAIL: $mismatch_count byte-equality mismatches"
```

**Pass condition:** All four counts equal AND zero MISMATCH lines.

---

## Dimension 2: Verdict evidence

**Check:** Every triage row cites concrete evidence; "looks like junk" alone is never acceptable.

**Verification query:**

```bash
# Every row's evidence column is non-empty
empty_evidence=$(tail -n +2 .repo_janitor_workspace/triage.tsv | awk -F'\t' '$4 == ""' | wc -l)
[[ "$empty_evidence" == "0" ]] || echo "FAIL: $empty_evidence rows with empty evidence"

# Every row's evidence has at least one key=value pair
no_kv=$(tail -n +2 .repo_janitor_workspace/triage.tsv | awk -F'\t' '$4 !~ /=/' | wc -l)
[[ "$no_kv" == "0" ]] || echo "FAIL: $no_kv rows lack key=value evidence"
```

**Pass condition:** All evidence columns non-empty AND contain at least one `key=value` pair.

---

## Dimension 3: No false-positive deletes

**Check:** No file is deleted when REFERENCE-GREP finds ≥1 inbound hit; verdict flips to `surface-to-user`.

**Verification query:**

```bash
# Get all delete-verdict candidates
delete_ids=$(awk -F'\t' '$2 ~ /^delete/ {print $1}' .repo_janitor_workspace/triage.tsv | tail -n +2)

violations=0
for id in $delete_ids; do
    # The reference graph row for this id
    ref_count=$(jq -r --arg id "$id" '.candidates[$id].inbound_refs | length' .repo_janitor_workspace/reference_graph.json 2>/dev/null || echo 0)
    if [[ "$ref_count" -gt 0 ]]; then
        echo "FAIL: candidate $id has verdict=delete-* but ref_count=$ref_count"
        violations=$((violations + 1))
    fi
done

[[ "$violations" == "0" ]] || echo "FAIL: $violations delete verdicts with non-empty inbound refs"
```

**Pass condition:** Zero rows with `delete-*` verdict AND non-empty inbound refs.

---

## Dimension 4: No silently-broken references

**Check:** Every move's reference graph was checked; every reference either was rewritten OR surfaced to user.

**Verification query:**

```bash
# Every move's references are accounted for
moves=$(tail -n +2 .repo_janitor_workspace/triage.tsv | awk -F'\t' '$2 == "move" {print $1}')

violations=0
for id in $moves; do
    # Number of inbound refs in graph
    graph_refs=$(jq -r --arg id "$id" '.candidates[$id].inbound_refs | length' .repo_janitor_workspace/reference_graph.json 2>/dev/null || echo 0)

    # Number of rewrites logged for this id
    log_rewrites=$(grep -c "candidate_id=$id" .repo_janitor_workspace/reference_rewrite_log.tsv 2>/dev/null || echo 0)

    # Number of surfaced refs (user resolved manually)
    surfaced=$(grep -c "candidate_id=$id" .repo_janitor_workspace/conflicts/*.context.md 2>/dev/null || echo 0)

    if [[ "$graph_refs" != "$((log_rewrites + surfaced))" ]]; then
        echo "FAIL: candidate $id has $graph_refs refs but only $log_rewrites rewrites + $surfaced surfaces"
        violations=$((violations + 1))
    fi
done

[[ "$violations" == "0" ]]

# Final post-Phase-9 grep — ensure no stale refs
ws=$(cat .repo_janitor_workspace/bundle_path.txt)/working-tree-copies
for moved in $(awk -F'\t' '$2 == "move" {print $3}' .repo_janitor_workspace/triage.tsv); do
    if grep -rln -F --include='*.rs' --include='*.toml' --include='*.md' --include='*.sh' --include='*.py' \
        --exclude-dir={.git,target,node_modules,.repo_janitor_workspace,.next} \
        "$moved" . 2>/dev/null | grep -v "$ws" > /dev/null; then
        echo "FAIL: stale ref to moved path: $moved"
    fi
done
```

**Pass condition:** Every move's refs are either logged-as-rewritten OR surfaced. Zero stale refs in final grep.

---

## Dimension 5: Per-commit gates

**Check:** Every Phase 6/7/8 commit has run the project's full test/typecheck/lint/build suite.

**Verification query:**

```bash
# Every commit on the recovery branch should have a corresponding apply_log entry with gates_status=passed
recovery_branch=$(git config --get repo-janitor.recovery-branch || git branch --show-current)
expected_commits=$(git log --oneline "$recovery_branch" ^origin/main 2>/dev/null | wc -l)
log_passed=$(awk -F'\t' '$5 == "passed"' .repo_janitor_workspace/apply_log.tsv | tail -n +2 | wc -l)

[[ "$expected_commits" == "$log_passed" ]] || echo "FAIL: $expected_commits commits, $log_passed gates passed"

# No FAIL markers in apply_log
fail_count=$(grep -ci FAIL .repo_janitor_workspace/apply_log.tsv 2>/dev/null || echo 0)
[[ "$fail_count" == "0" ]] || echo "FAIL: $fail_count gate failures recorded"
```

**Pass condition:** Number of commits matches number of `gates_status=passed` rows; zero `FAIL` markers.

---

## Dimension 6: `.gitignore` shadowing audit

**Check:** Every newly-added `.gitignore` line was run through `git ls-files <glob>` to surface tracked-file shadowing.

**Verification query:**

```bash
# Each addition has a SHADOW or OK line in the audit log
proposed_patterns=$(grep -v '^#' .repo_janitor_workspace/gitignore_plan.md | grep -v '^$' | wc -l)
audited_patterns=$(grep -cE '^(SHADOW|OK) pattern=' .repo_janitor_workspace/gitignore_shadowing_audit.log 2>/dev/null || echo 0)

[[ "$proposed_patterns" == "$audited_patterns" ]] || echo "FAIL: $proposed_patterns proposed but $audited_patterns audited"

# SHADOW entries must have user authorization
shadow_count=$(grep -c '^SHADOW' .repo_janitor_workspace/gitignore_shadowing_audit.log 2>/dev/null || echo 0)
if [[ "$shadow_count" -gt 0 ]]; then
    auth_for_shadows=$(grep -c 'phase=8.*shadowing' .repo_janitor_workspace/cleanup_authorization.txt 2>/dev/null || echo 0)
    [[ "$auth_for_shadows" -gt 0 ]] || echo "FAIL: $shadow_count shadowed patterns but no Phase 8 shadowing auth"
fi
```

**Pass condition:** Every proposed pattern is in the audit log; any SHADOW entries have corresponding verbatim authorization.

---

## Dimension 7: Focused commit messages

**Check:** Each commit explains *why*; not "remove junk" but a categorical body.

**Verification query:**

```bash
# Every commit on recovery branch should have a multi-line body
recovery_branch=$(git config --get repo-janitor.recovery-branch || git branch --show-current)
shorts=$(git log --format=%B "$recovery_branch" ^origin/main | awk '/^$/{p++} END{print p}')
commits=$(git log --oneline "$recovery_branch" ^origin/main | wc -l)

# Should have ≥1 blank line per commit (separating subject from body)
expected_blank_lines=$((commits))
[[ "$shorts" -ge "$expected_blank_lines" ]] || echo "FAIL: $commits commits but only $shorts blank-line separators (probably missing bodies)"

# Specific anti-pattern: no commit message should be exactly 'cleanup'
bad=$(git log --format=%s "$recovery_branch" ^origin/main | grep -ciE '^cleanup$|^chore: cleanup$' || echo 0)
[[ "$bad" == "0" ]] || echo "FAIL: $bad commits have generic 'cleanup' subject"
```

**Pass condition:** Every commit has a body (multi-line); no generic "cleanup" subjects.

---

## Dimension 8: Order of operations

**Check:** moves → deletes → `.gitignore` updates (in that sequence).

**Verification query:**

```bash
# Categorize each commit by its scope
recovery_branch=$(git config --get repo-janitor.recovery-branch || git branch --show-current)
git log --oneline "$recovery_branch" ^origin/main --reverse | while read sha rest; do
    # Get changed files
    changes=$(git show --stat --format= "$sha")
    if echo "$changes" | grep -q '\.gitignore'; then
        echo "$sha gitignore"
    elif echo "$changes" | grep -q 'rename'; then
        echo "$sha move"
    elif echo "$changes" | grep -q 'delete mode'; then
        echo "$sha delete"
    else
        echo "$sha other"
    fi
done > /tmp/commit_order.txt

# Verify order: all `move` commits before all `delete` commits, both before `.gitignore`
last_move=$(grep -n 'move$' /tmp/commit_order.txt | tail -1 | cut -d: -f1 || echo 0)
first_delete=$(grep -n 'delete$' /tmp/commit_order.txt | head -1 | cut -d: -f1 || echo 999)
last_delete=$(grep -n 'delete$' /tmp/commit_order.txt | tail -1 | cut -d: -f1 || echo 0)
first_gitignore=$(grep -n 'gitignore$' /tmp/commit_order.txt | head -1 | cut -d: -f1 || echo 999)

[[ "$last_move" -lt "$first_delete" ]] || echo "FAIL: move commits interleaved with delete commits"
[[ "$last_delete" -lt "$first_gitignore" ]] || echo "FAIL: delete commits interleaved with gitignore commits"
```

**Pass condition:** All move commits precede all delete commits; all delete commits precede all gitignore commits.

---

## Dimension 9: Verbatim authorization

**Check:** Phases 7 and 8 only ran after the user typed the literal commands; recorded in `cleanup_authorization.txt`.

**Verification query:**

```bash
# If delete_plan.md exists, cleanup_authorization.txt must have phase=7 entry
if [[ -f .repo_janitor_workspace/delete_plan.md ]]; then
    has_p7=$(grep -c 'phase=7' .repo_janitor_workspace/cleanup_authorization.txt 2>/dev/null || echo 0)
    [[ "$has_p7" -gt 0 ]] || echo "FAIL: delete plan exists but no phase=7 auth"
fi

# If gitignore_plan.md proposes shadowing, cleanup_authorization.txt must have phase=8 entry
shadow_count=$(grep -c '^SHADOW' .repo_janitor_workspace/gitignore_shadowing_audit.log 2>/dev/null || echo 0)
if [[ "$shadow_count" -gt 0 ]]; then
    has_p8=$(grep -c 'phase=8' .repo_janitor_workspace/cleanup_authorization.txt 2>/dev/null || echo 0)
    [[ "$has_p8" -gt 0 ]] || echo "FAIL: gitignore shadowing detected but no phase=8 auth"
fi

# Each auth entry has plan_hash matching the actual plan file's hash
# (guards against re-using auth from a different plan)
```

**Pass condition:** All required authorization entries present; plan hashes match.

---

## Dimension 10: Idempotence on a clean repo

**Check:** Re-running on a freshly-cleaned repo produces no commits.

**Verification query:**

```bash
# Save the recovery branch SHA
pre_sha=$(git rev-parse HEAD)

# Re-run the skill in --dry-run / smoke-test mode
# (or, in a test, full mode)
/git-repo-janitor mode=triage-only

# Verify HEAD didn't move
post_sha=$(git rev-parse HEAD)
[[ "$pre_sha" == "$post_sha" ]] || echo "FAIL: re-run created commits"

# triage.tsv should be empty (header only)
empty_triage=$(tail -n +2 .repo_janitor_workspace/triage.tsv | wc -l)
[[ "$empty_triage" == "0" ]] || echo "FAIL: re-run found $empty_triage candidates on supposedly-clean repo"
```

**Pass condition:** HEAD unchanged; triage.tsv empty.

---

## Dimension 11: Resumability

**Check:** If interrupted mid-Phase 6/7, re-running picks up from the last successful commit.

**Verification query:**

```bash
# Smoke test: kill mid-Phase-6, then resume
# (manual; not a single grep)

# After resume, verify no duplicate commits
recovery_branch=$(git config --get repo-janitor.recovery-branch)
duplicate_subjects=$(git log --format=%s "$recovery_branch" ^origin/main | sort | uniq -c | awk '$1 > 1' | wc -l)
[[ "$duplicate_subjects" == "0" ]] || echo "FAIL: $duplicate_subjects duplicate commit subjects (likely re-run produced duplicates)"
```

**Pass condition:** Zero duplicate commit subjects.

---

## Dimension 12: Build still works

**Check:** After Phase 9, the project's full quality gate suite passes.

**Verification query:**

```bash
# Read commands from project_profile.json
test_cmd=$(jq -r '.test_command' .repo_janitor_workspace/project_profile.json)
typecheck_cmd=$(jq -r '.typecheck_command' .repo_janitor_workspace/project_profile.json)
build_cmd=$(jq -r '.build_command' .repo_janitor_workspace/project_profile.json)

[[ -n "$test_cmd" ]] && eval "$test_cmd"
[[ -n "$typecheck_cmd" ]] && eval "$typecheck_cmd"
[[ -n "$build_cmd" ]] && eval "$build_cmd"
```

**Pass condition:** All commands exit 0.

---

## Dimension 13: Phase 2.5 ran clean

**Check:** `secret_findings.tsv` is empty OR every entry has a documented user resolution.

**Verification query:**

```bash
[[ -f .repo_janitor_workspace/secret_findings.tsv ]] || echo "FAIL: Phase 2.5 didn't run"

# Every row has a non-empty resolution column
unresolved=$(tail -n +2 .repo_janitor_workspace/secret_findings.tsv | awk -F'\t' '$NF == "pending" || $NF == ""' | wc -l)
[[ "$unresolved" == "0" ]] || echo "FAIL: $unresolved unresolved secret findings"
```

**Pass condition:** secret_findings.tsv exists; no `pending` resolutions.

---

## Dimension 14: Audit trail intact

**Check:** All required artifacts exist; bundle + backup ref present.

**Verification query:**

```bash
required_files=(
    project_profile.json
    candidates.tsv
    secret_findings.tsv
    bundle_path.txt
    triage.tsv
    apply_log.tsv
    handoff_report.md
)

for f in "${required_files[@]}"; do
    [[ -f ".repo_janitor_workspace/$f" ]] || echo "FAIL: missing $f"
done

# Bundle directory exists
bundle=$(cat .repo_janitor_workspace/bundle_path.txt)
[[ -d "$bundle" ]] || echo "FAIL: bundle directory $bundle missing"

# Backup ref exists
date_str=$(date -u +%Y-%m-%d)
git rev-parse "refs/repo-janitor-backup/${date_str}-pre-cleanup" >/dev/null 2>&1 || echo "FAIL: backup ref missing"
```

**Pass condition:** All required artifacts present; bundle dir + backup ref exist.

---

## Dimension 15 (new): Verification log written

**Check:** Every recommendation that depended on volatile git behavior produced a `verification_log.md` entry (Axiom 17).

**Verification query:**

```bash
# verification_log.md must have entries if filter-repo or version-sensitive operations ran
if grep -q 'filter-repo\|--force-with-lease' .repo_janitor_workspace/apply_log.tsv 2>/dev/null; then
    [[ -s .repo_janitor_workspace/verification_log.md ]] || echo "FAIL: filter-repo ran but no verification_log entries"
fi
```

**Pass condition:** Verification log has entries for any volatile operation.

---

## Dimension 16 (new): Coverage matrix complete

**Check:** Every smell rule has a row; no blank cells (Axiom 18).

**Verification query:**

```bash
# Count smell rules in FILE-SMELLS.md
total_rules=$(grep -cE '^\| `' references/FILE-SMELLS.md 2>/dev/null || echo 0)

# Count rows in coverage matrix
matrix_rows=$(grep -cE '^\| ' .repo_janitor_workspace/coverage_matrix.md 2>/dev/null || echo 0)
matrix_rows=$((matrix_rows - 2))  # exclude header rows

# Approximately equal (some rules may not have a row if archetype-disabled)
[[ "$matrix_rows" -ge $((total_rules - 5)) ]] || echo "FAIL: coverage matrix has $matrix_rows rows but $total_rules expected"

# No blank status cells
blank=$(awk -F'|' 'NR>2 && $3 ~ /^\s*$/' .repo_janitor_workspace/coverage_matrix.md | wc -l)
[[ "$blank" == "0" ]] || echo "FAIL: $blank blank cells in coverage matrix"
```

**Pass condition:** Matrix has ≥(rules - 5) rows; no blank cells.

---

## Dimension 17 (new): Phantom deletions handled

**Check:** If phantom deletions were detected, they were resolved (restored or user-confirmed delete) before any cleanup commits landed (Axiom 24).

**Verification query:**

```bash
# Currently no D files in git status (after restore phase)
phantom_now=$(git status --porcelain | awk '$1 == "D"' | wc -l)

# If phantom_deletions.tsv was non-empty, the resolutions should be logged
if [[ -s .repo_janitor_workspace/phantom_deletions.tsv ]]; then
    expected_resolutions=$(tail -n +2 .repo_janitor_workspace/phantom_deletions.tsv | wc -l)
    actual_resolutions=$(tail -n +2 .repo_janitor_workspace/phantom_deletion_recovery.md 2>/dev/null | wc -l)
    [[ "$actual_resolutions" -ge "$expected_resolutions" ]] || echo "FAIL: $expected_resolutions phantom deletions but only $actual_resolutions resolutions"
fi
```

**Pass condition:** No outstanding phantom deletions; all resolved.

---

## Dimension 18 (new): Mode escalation recorded

**Check:** If a mode escalation occurred, `mode_escalation_decision.md` exists with user authorization.

**Verification query:**

```bash
# If multiple modes appeared in run_state.json's mode_history, escalation files should exist
mode_count=$(jq '.mode_history | length' .repo_janitor_workspace/run_state.json 2>/dev/null || echo 1)
escalation_count=$(ls .repo_janitor_workspace/mode_escalation_*.md 2>/dev/null | wc -l)

if [[ "$mode_count" -gt 1 ]]; then
    [[ "$escalation_count" -ge $((mode_count - 1)) ]] || echo "FAIL: $mode_count modes but only $escalation_count escalations"
fi
```

**Pass condition:** Each mode change has a corresponding escalation decision file.

---

## Running all queries

`scripts/polish-bar-check.sh` (already in the skill) ties all dimensions together. The verification queries here are the underlying logic each dimension's check uses.

---

## When a dimension fails

If polish-bar-check.sh fails on dimension N:

1. Read the failure detail in `<workspace>/polish_bar_failures.md`.
2. Investigate per the dimension's recovery path:
   - Dimension 1 fail: re-run Phase 3.
   - Dimension 4 fail: re-run reference-grep + apply missed rewrites.
   - Dimension 5 fail: identify gate failure, fix, re-commit.
   - Dimension 12 fail: hard. Recover via INCIDENT-PLAYBOOK § A reference rewrite breaks the build.
3. Re-run the polish-bar-check after the fix.

The skill cannot finalize Phase 10 with any failed dimension.
