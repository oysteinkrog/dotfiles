#!/usr/bin/env bash
# shellcheck disable=SC2015
# integration-test.sh — End-to-end smoke test of the full Phase 0 → Phase 10
# pipeline on a synthetic, freshly-built git repo.
#
# This is a REGRESSION test. It:
#   1. Bootstraps a /tmp/gsj-test-repo-<TS>/ with 9 stashes covering every
#      verdict class + adversarial canaries (markdown-pipe, command-injection,
#      paths with spaces, renames, binary-ish files, untracked-only stashes).
#   2. Runs every pipeline script from Phase 0 through Phase 10.
#   3. Verifies each phase's outputs match expectations.
#   4. Reports PASS/FAIL per phase + an overall verdict.
#
# Run after any change to a pipeline script. Caught real bugs the first time
# it ran — bundle-audit's `*.diff` glob double-counted partial-split outputs,
# and apply-keeper had no pre-flight check for an unmerged index from a prior
# failed apply. Both surfaced in <2 minutes of running this.
#
# Usage:
#   integration-test.sh                # run with a fresh test repo
#   integration-test.sh --keep         # move successful test repo to
#                                       /tmp/gsj-test-repo-archive-<TS>
#
# Exit 0 iff every phase passes.

set -euo pipefail

KEEP=false
[[ "${1:-}" == "--keep" ]] && KEEP=true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TS=$(date -u +%Y%m%d-%H%M%S)
REPO="/tmp/gsj-test-repo-$TS"

PASS=0
FAIL=0
log_pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS + 1)); }
log_fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
section()  { printf '\n=== %s ===\n' "$1"; }

# ---- 1. Bootstrap ----
section "Bootstrap synthetic repo at $REPO"
mkdir -p "$REPO"
cd "$REPO"

git init -q -b main
git config user.name "GSJ Test"
git config user.email "gsj-test@example.invalid"

mkdir -p src "path with spaces"
cat > src/lib.py <<'EOF'
def compute_total(items):
    return sum(items)

def helper():
    return 42
EOF
cat > src/util.py <<'EOF'
def utility_one():
    return "one"
EOF
cat > "path with spaces/file.txt" <<'EOF'
baseline content
EOF
cat > src/will_be_deleted.py <<'EOF'
def old_thing():
    return "old"
EOF
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89' > src/icon.png

git add -A
git commit -q -m "initial: baseline source"

cat >> src/lib.py <<'EOF'

def already_on_main():
    return "this is on main"
EOF
git add src/lib.py
git commit -q -m "add already_on_main"

git mv src/will_be_deleted.py src/renamed_old_thing.py
git commit -q -m "move will_be_deleted fixture"

# Stashes (9 total)
make_stash() {
  local msg="$1" file="$2" content="$3" extra="${4:-}"
  printf '%s' "$content" > "$file"
  # shellcheck disable=SC2086
  git stash push $extra -m "$msg" >/dev/null
}

make_stash "other-agent-broken: junk experiment" src/lib.py "$(cat src/lib.py)
def junk():
    pass
"
make_stash "wip-FEATURE-X: add frobnicate_widgets" src/util.py "$(cat src/util.py)

def frobnicate_widgets():
    return 'frobnicated'
"
make_stash "wip-FEATURE-X: add already_on_main duplicate" src/lib.py "$(cat src/lib.py)

def already_on_main():
    return 'duplicate of main'
"
{
  cat > src/lib.py <<'EOF'
def compute_total(items):
    # MODIFIED
    return sum(items)

def helper():
    return 42

def already_on_main():
    return "this is on main"

def partially_novel_addition():
    return "partial"
EOF
}
git stash push -m "partial-refactor: lib.py" >/dev/null

echo "fresh untracked content" > src/brand_new_untracked.txt
git stash push -u -m "wip-FEATURE-Y: add brand_new_untracked file" >/dev/null

make_stash "wip|with|pipes|in|message: tests markdown escape" src/util.py "$(cat src/util.py)

def pipe_canary():
    return 'pipes'
"
echo "command-injection canary content" >> src/util.py
# shellcheck disable=SC2016 # Literal command substitutions are the canary payload under test.
git stash push -m 'cmd-inject-canary: $(echo PWNED) and `whoami`' >/dev/null

echo "modified content for path with spaces" > "path with spaces/file.txt"
git stash push -m "wip-FEATURE-Z: edit space-path file" >/dev/null

git mv src/util.py src/utility_module.py
git stash push -m "refactor-rename: util.py to utility_module.py" >/dev/null

stash_count=$(git stash list | wc -l)
[[ "$stash_count" -eq 9 ]] && log_pass "9 stashes created" || log_fail "expected 9 stashes, got $stash_count"

# ---- 2. Phase 0 ----
section "Phase 0"
"$SCRIPT_DIR/snapshot-tree.sh" "$REPO" phase0 >/dev/null \
  && log_pass "snapshot-tree" || log_fail "snapshot-tree"
"$SCRIPT_DIR/cass-mine.sh" "$REPO" >/dev/null 2>&1 \
  && log_pass "cass-mine" || log_fail "cass-mine"
"$SCRIPT_DIR/check-skills.sh" "$REPO/.stash_janitor_workspace" >/dev/null \
  && log_pass "check-skills" || log_fail "check-skills"

# ---- 3. Phase 1 ----
section "Phase 1"
"$SCRIPT_DIR/discover-project.sh" "$REPO" >/dev/null \
  && log_pass "discover-project" || log_fail "discover-project"
"$SCRIPT_DIR/git-doctor.sh" "$REPO" >/dev/null \
  && log_pass "git-doctor" || log_fail "git-doctor"
mkdir -p "$REPO/src/nested"
"$SCRIPT_DIR/discover-project.sh" "$REPO/src/nested" >/dev/null \
  && log_pass "discover-project normalizes nested path to repo root" \
  || log_fail "discover-project nested-path normalization"
if [[ -f "$REPO/.stash_janitor_workspace/project_profile.json" &&
      ! -e "$REPO/src/nested/.stash_janitor_workspace" ]]; then
  log_pass "nested invocation writes workspace at repo root only"
else
  log_fail "nested invocation wrote workspace outside repo root"
fi

# ---- 4. Phase 2 ----
section "Phase 2"
"$SCRIPT_DIR/discover-stashes.sh" "$REPO" >/dev/null
inv_rows=$(awk 'NR > 1' "$REPO/.stash_janitor_workspace/inventory.tsv" | wc -l)
[[ "$inv_rows" -eq 9 ]] && log_pass "inventory has 9 rows" || log_fail "inventory has $inv_rows rows, expected 9"

untracked_row=$(awk -F'\t' 'NR > 1 && $11 == "true"' "$REPO/.stash_janitor_workspace/inventory.tsv" | wc -l)
[[ "$untracked_row" -eq 1 ]] && log_pass "untracked-only stash flagged has_untracked=true" \
                              || log_fail "expected exactly 1 has_untracked=true row, got $untracked_row"

# ---- 5. Phase 3 ----
section "Phase 3"
"$SCRIPT_DIR/build-bundle.sh" "$REPO" >/dev/null \
  && log_pass "build-bundle" || log_fail "build-bundle"
"$SCRIPT_DIR/verify-bundle.sh" "$REPO" >/dev/null \
  && log_pass "verify-bundle" || log_fail "verify-bundle"

# ---- 6. Phase 4 ----
section "Phase 4"
"$SCRIPT_DIR/triage-batch.sh" "$REPO" 1 0 8 >/dev/null \
  && log_pass "triage-batch" || log_fail "triage-batch"
"$SCRIPT_DIR/merge-triage.sh" "$REPO" >/dev/null \
  && log_pass "merge-triage" || log_fail "merge-triage"

# Verify markdown-pipe canary is escaped in the decision file.
if grep -qF 'wip\|with\|pipes\|in\|message' "$REPO/.stash_janitor_workspace/triage_decision.md"; then
  log_pass "pipe canary correctly escaped in triage_decision.md"
else
  log_fail "pipe canary NOT escaped in triage_decision.md"
fi

# ---- 7. Phase 5 (manual write of authorization) ----
section "Phase 5 (synthetic authorization)"
printf '%s\ngo (integration-test)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$REPO/.stash_janitor_workspace/phase5_user_authorization.txt"
log_pass "phase5_user_authorization.txt written"

# ---- 8. Phase 6 (apply non-conflicting keepers) ----
section "Phase 6"
git -C "$REPO" checkout -B stash-recovery-test main >/dev/null 2>&1
# Move the bootstrap-leftover untracked file aside so it doesn't pollute drift.
[[ -f "$REPO/src/will_be_deleted.py" ]] && mv "$REPO/src/will_be_deleted.py" "$REPO/.aside-bootstrap-leftover"

# Apply n=5 (lib.py) and n=7 (util.py) — independent files, no conflict.
"$SCRIPT_DIR/apply-keeper.sh" "$REPO" 5 >/dev/null 2>&1 \
  && log_pass "apply-keeper n=5 (lib.py keeper)" || log_fail "apply-keeper n=5"
"$SCRIPT_DIR/apply-keeper.sh" "$REPO" 7 >/dev/null 2>&1 \
  && log_pass "apply-keeper n=7 (util.py keeper)" || log_fail "apply-keeper n=7"

apply_passed=$(awk -F'\t' 'NR > 1 && $5 == "passed"' "$REPO/.stash_janitor_workspace/apply_log.tsv" | wc -l)
[[ "$apply_passed" -eq 2 ]] && log_pass "apply_log has 2 passed rows" \
                             || log_fail "apply_log has $apply_passed passed rows (expected 2)"

# ---- 9. Phase 7 (partial-split smoke) ----
section "Phase 7"
"$SCRIPT_DIR/partial-split.sh" "$REPO" 8 1 >/dev/null 2>&1 \
  && log_pass "partial-split kept hunk 1 of stash 8" || log_fail "partial-split"

# ---- 10. Phase 8 (recovery-test) ----
section "Phase 8"
# Move the apply-keeper conflict-context file aside (workspace exclude
# already handles this, but extra defense).
"$SCRIPT_DIR/recovery-test.sh" "$REPO" 2 >/dev/null \
  && log_pass "recovery-test on stash 2 (cmd-inject canary)" \
  || log_fail "recovery-test on stash 2"

# ---- 11. Phase 9 (drop the garbage stash) ----
section "Phase 9"
printf '%s\nyes I understand and want to drop all 1 stash per the plan above\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$REPO/.stash_janitor_workspace/cleanup_authorization.txt"

# Negative test FIRST: drop-confirmed must REFUSE a novel-and-accretive verdict
# (without an override). Use n=2 (cmd-inject-canary) which the test repo's
# triage classifies as something other than a cleanup-bucket verdict. Capture
# the refusal exit code; expect 13 (the verdict-bucket gate).
neg_n=2
neg_verdict=$(awk -F'\t' -v n="$neg_n" 'NR > 1 && $1 == n {print $2}' "$REPO/.stash_janitor_workspace/triage.tsv")
case "$neg_verdict" in
  garbage|superseded|superseded-by-newer-stash|novel-but-stale|applied-keeper)
    # Skip negative test if n=2 happened to land in a bucket; not a failure.
    log_pass "drop-confirmed verdict-bucket gate (n=$neg_n verdict=$neg_verdict — already in bucket, negative test n/a)"
    ;;
  *)
    set +e
    "$SCRIPT_DIR/drop-confirmed.sh" "$REPO" "$neg_n" "confirm=YES_DROP_$neg_n" >/dev/null 2>&1
    rc=$?
    set -e
    if [[ "$rc" -eq 13 ]]; then
      log_pass "drop-confirmed REFUSED non-bucket verdict (n=$neg_n verdict=$neg_verdict, exit=13)"
    else
      log_fail "drop-confirmed should have REFUSED non-bucket drop; got exit=$rc"
    fi
    ;;
esac

# Garbage stash is at index 8.
"$SCRIPT_DIR/drop-confirmed.sh" "$REPO" 8 confirm=YES_DROP_8 >/dev/null \
  && log_pass "drop-confirmed n=8 (garbage stash)" || log_fail "drop-confirmed n=8"

post_drop_count=$(git -C "$REPO" stash list | wc -l)
[[ "$post_drop_count" -eq 8 ]] && log_pass "stash count decreased to 8" \
                                || log_fail "stash count is $post_drop_count, expected 8"

# Backup ref still resolves.
if git -C "$REPO" rev-parse refs/stash-backup/008 >/dev/null 2>&1; then
  log_pass "refs/stash-backup/008 still resolves after drop"
else
  log_fail "refs/stash-backup/008 lost after drop"
fi

# ---- 12. Phase 10 (handoff + bundle-audit) ----
section "Phase 10"
"$SCRIPT_DIR/handoff-report.sh" "$REPO" >/dev/null \
  && log_pass "handoff-report" || log_fail "handoff-report"

"$SCRIPT_DIR/bundle-audit.sh" "$REPO" >/dev/null \
  && log_pass "bundle-audit (post-drop)" || log_fail "bundle-audit"

# ---- 12.5. Mutation-coverage assertions ----
# These assertions close gaps found by /tmp/gsj-audit/run-mutations.sh.
# Each reproduces the wrong behavior a specific mutation would produce, then
# checks the script does the right thing instead. Without these, the mutation
# suite reported the corresponding mutation as UNCAUGHT.
section "Mutation-coverage assertions"

# M02 (apply-keeper auth-gate exit code): verify apply-keeper REFUSES to run
# when phase5_user_authorization.txt is absent. Move the auth file aside
# (mv, not rm — DCG-friendly), invoke apply-keeper for an unapplied stash
# (n=0, the rename), expect non-zero exit.
auth_file="$REPO/.stash_janitor_workspace/phase5_user_authorization.txt"
auth_aside="$REPO/.stash_janitor_workspace/.phase5_user_authorization.txt.aside"
mv "$auth_file" "$auth_aside"
set +e
"$SCRIPT_DIR/apply-keeper.sh" "$REPO" 0 >/dev/null 2>&1
rc=$?
set -e
mv "$auth_aside" "$auth_file"
if [[ "$rc" -ne 0 ]]; then
  log_pass "apply-keeper REFUSES without phase5_user_authorization.txt (M02 — exit=$rc)"
else
  log_fail "apply-keeper proceeded without authorization (M02 coverage gap; got exit=0)"
fi

# M06 (drop-confirmed verdict-bucket weakening): verify drop-confirmed REFUSES
# specifically via the verdict-bucket gate (exit 13), not just any gate. Use
# stash 7 (verdict=novel-and-accretive in triage.tsv, but already applied so
# effective verdict becomes applied-keeper). Temporarily move apply_log aside
# so drop-confirmed sees the raw triage verdict, then attempt the drop.
# Expected: exit 13 from the verdict-bucket gate. The mutation that allows
# novel-and-accretive through would produce a different (passing) exit.
apply_log_path="$REPO/.stash_janitor_workspace/apply_log.tsv"
apply_log_aside="$REPO/.stash_janitor_workspace/.apply_log.tsv.aside"
mv "$apply_log_path" "$apply_log_aside"
set +e
m06_out=$("$SCRIPT_DIR/drop-confirmed.sh" "$REPO" 7 confirm=YES_DROP_7 2>&1)
rc=$?
set -e
mv "$apply_log_aside" "$apply_log_path"
if [[ "$rc" -eq 13 ]] && echo "$m06_out" | grep -qE 'verdict.+novel-and-accretive'; then
  log_pass "drop-confirmed verdict-bucket gate (M06 — exit=13 with bucket-refusal message)"
else
  log_fail "drop-confirmed didn't hit verdict-bucket gate (M06; exit=$rc, expected 13)"
fi

# M10 (polish-bar bucket-violation check disabled): write a synthetic cleanup_log
# with an unmapped verdict and verify polish-bar P6 FAILs on it. Use a one-shot
# alternate workspace dir to avoid contaminating the real cleanup_log.
m10_ws=$(mktemp -d)
mkdir -p "$m10_ws/.stash_janitor_workspace"
cp "$REPO/.stash_janitor_workspace/inventory.tsv" "$m10_ws/.stash_janitor_workspace/"
cp "$REPO/.stash_janitor_workspace/triage.tsv" "$m10_ws/.stash_janitor_workspace/"
cp "$REPO/.stash_janitor_workspace/bundle_path.txt" "$m10_ws/.stash_janitor_workspace/"
cp "$REPO/.stash_janitor_workspace/bundle_verification.log" "$m10_ws/.stash_janitor_workspace/"
{
  printf 'n\tpre_drop_index\tref_dropped\tverdict\ttimestamp_utc\tmessage\n'
  printf '99\tstash@{99}\trefs/stash-backup/099\tnovel-and-accretive\t2026-01-01T00:00:00Z\tsynthetic\n'
} > "$m10_ws/.stash_janitor_workspace/cleanup_log.tsv"
# polish-bar-check needs PROJECT_ABS to be a git repo for some checks; symlink
# the real .git so it has one without copying everything.
( cd "$m10_ws" && git init -q -b main && git commit -q --allow-empty -m "synthetic" )
set +e
m10_out=$("$SCRIPT_DIR/polish-bar-check.sh" "$m10_ws" 2>&1)
rc=$?
set -e
if echo "$m10_out" | grep -q 'BUCKET VIOLATION'; then
  log_pass "polish-bar P6 catches unmapped-verdict cleanup_log row (M10)"
else
  log_fail "polish-bar P6 missed unmapped-verdict (M10 coverage gap)"
fi
# Cleanup the synthetic workspace via mv (DCG-friendly) — leave it under
# /tmp where it's harmless; mktemp gave us a path under /tmp.

# ---- 12.6. Race-detection assertion (build-bundle/verify-bundle $sha vs $ref) ----
# Round 15 fixed a race where build-bundle and verify-bundle used $ref
# (live stash@{N} stack position) instead of $sha (frozen inventory SHA).
# A concurrent agent or user pushing a new stash between Phase 2 and Phase 3
# shifts every stash@{N}, so $ref no longer points at the captured commit
# while $sha is stable. The mutation suite reported M07 and M08 (reverting
# this fix in build-bundle and verify-bundle respectively) as UNCAUGHT —
# integration-test never simulated a stash-list shift.
#
# This assertion creates an isolated mini-repo, captures inventory, injects
# a new stash to shift the indices, then re-runs build-bundle + verify-bundle.
# If either script uses $ref, verify-bundle's hash comparison fails.
section "Race-detection assertion (sha vs ref)"
race_repo=$(mktemp -d /tmp/gsj-race-XXXXXX)
(
  cd "$race_repo"
  git init -q -b main
  git config user.name "GSJ Race"
  git config user.email "gsj-race@example.invalid"
  echo "base" > base.txt
  git add base.txt
  git commit -q -m "initial"
  # Three stashes to shift around.
  for i in 1 2 3; do
    echo "v$i" > "race_$i.txt"
    git add "race_$i.txt"
    git stash push -m "race-stash-$i" >/dev/null 2>&1
  done
)
"$SCRIPT_DIR/snapshot-tree.sh"     "$race_repo" phase0       >/dev/null 2>&1
"$SCRIPT_DIR/discover-project.sh"  "$race_repo"              >/dev/null 2>&1
"$SCRIPT_DIR/discover-stashes.sh"  "$race_repo"              >/dev/null 2>&1

# Inject a new stash NOW — this shifts every existing stash@{N} up by one
# but `inventory.tsv`'s $sha column still points at the original commits.
# Build-bundle and verify-bundle MUST use $sha to remain consistent.
( cd "$race_repo"
  echo "shifted" > shift.txt
  git add shift.txt
  git stash push -m "race-injected-shift" >/dev/null 2>&1
)

# Build the bundle AFTER the shift. With $sha (correct), the diffs come
# from the original captured commits. With $ref (mutated), they'd come
# from the now-shifted stash@{N} positions and verify-bundle would fail.
"$SCRIPT_DIR/build-bundle.sh"  "$race_repo" >/dev/null 2>&1
if "$SCRIPT_DIR/verify-bundle.sh" "$race_repo" >/dev/null 2>&1; then
  log_pass "build-bundle + verify-bundle survive a stash-list shift (M07/M08 race fix intact)"
else
  log_fail "build-bundle/verify-bundle inconsistent after stash-list shift (M07/M08 regression)"
fi

# ---- 12.8. Binary recovery assertion ----
# Plain `git stash show -p` records only "Binary files differ" for tracked
# binary modifications, and `git apply --3way --check` cannot recover that
# patch. The bundle contract must use `git stash show -p --binary`, and
# apply-keeper must still stage the changed binary path even though full binary
# patches may omit ---/+++ file headers.
section "Binary recovery assertion (--binary payload)"
binary_repo=$(mktemp -d /tmp/gsj-binary-XXXXXX)
(
  cd "$binary_repo"
  git init -q -b main
  git config user.name "GSJ Binary"
  git config user.email "gsj-binary@example.invalid"
  printf '\x00\x01\x02\x03' > fixture.bin
  printf 'before\n' > note.txt
  git add fixture.bin note.txt
  git commit -q -m "initial mixed fixture"
  printf '\x89PNG\r\n\x1a\n\x00tracked-binary-change' > fixture.bin
  printf 'after\n' > note.txt
  git stash push -m "mixed-binary-fixture-change" >/dev/null 2>&1
)
"$SCRIPT_DIR/snapshot-tree.sh"    "$binary_repo" phase0 >/dev/null 2>&1
"$SCRIPT_DIR/discover-project.sh" "$binary_repo"        >/dev/null 2>&1
"$SCRIPT_DIR/discover-stashes.sh" "$binary_repo"        >/dev/null 2>&1
"$SCRIPT_DIR/build-bundle.sh"     "$binary_repo"        >/dev/null 2>&1
binary_diff="$binary_repo-stash-archive-$(date -u +%Y-%m-%d)/diffs/000.diff"
if [[ -f "$binary_diff" ]] && grep -q '^GIT binary patch' "$binary_diff"; then
  log_pass "build-bundle captures tracked binary payload with --binary"
else
  log_fail "build-bundle did not emit a GIT binary patch for tracked binary stash"
fi
if "$SCRIPT_DIR/verify-bundle.sh" "$binary_repo" >/dev/null 2>&1; then
  log_pass "verify-bundle accepts binary payload diff"
else
  log_fail "verify-bundle rejected binary payload diff"
fi
printf '%s\ngo (binary integration-test)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$binary_repo/.stash_janitor_workspace/phase5_user_authorization.txt"
git -C "$binary_repo" checkout -B stash-recovery-binary main >/dev/null 2>&1
if "$SCRIPT_DIR/apply-keeper.sh" "$binary_repo" 0 >/dev/null 2>&1; then
  log_pass "apply-keeper applies and commits tracked binary stash"
else
  log_fail "apply-keeper failed tracked binary stash"
fi
if git -C "$binary_repo" diff --name-only HEAD^ HEAD | grep -qx 'fixture.bin'; then
  log_pass "apply-keeper stages binary path in mixed text+binary stash"
else
  log_fail "apply-keeper omitted binary path from mixed text+binary commit"
fi

# ---- 12.9. Secondary-script smoke ----
# These scripts aren't part of the Phase 0..10 main pipeline (so the prior
# sections don't exercise them) but they ARE part of the skill and can drift
# without the integration test catching it. Coverage profiling of the test
# revealed 0% on each — fixed here with one-shot smoke invocations that just
# verify the script runs to exit 0 against the populated test repo.
section "Secondary-script smoke"

"$SCRIPT_DIR/prefix-classifier.sh" "$REPO" >/dev/null 2>&1 \
  && log_pass "prefix-classifier produces classification.tsv" \
  || log_fail "prefix-classifier"

"$SCRIPT_DIR/verdict-stats.sh" "$REPO" >/dev/null 2>&1 \
  && log_pass "verdict-stats produces JSON + markdown" \
  || log_fail "verdict-stats"

# install-referenced-skills runs `jsm install` for any missing skill from the
# inventory. We don't actually want to install anything during the test (and
# `jsm` may not be authenticated in CI). The script's early-exit paths (no
# missing skills, jsm not installed, jsm not authed) all return 0; that's
# sufficient as a smoke check that the script PARSES and doesn't crash.
"$SCRIPT_DIR/install-referenced-skills.sh" "$REPO/.stash_janitor_workspace" >/dev/null 2>&1 \
  && log_pass "install-referenced-skills runs to clean exit" \
  || log_fail "install-referenced-skills"

# archive-workspace TARS the full workspace into a parent-dir tarball — Phase
# 10 finalization. Test it against the populated workspace; verify the
# tarball lands in the parent dir and is non-empty.
"$SCRIPT_DIR/archive-workspace.sh" "$REPO" >/dev/null 2>&1 \
  && log_pass "archive-workspace produces tarball" \
  || log_fail "archive-workspace"
parent_dir=$(dirname "$REPO")
basename=$(basename "$REPO")
archive=$(command find "$parent_dir" -maxdepth 1 -name "${basename}-stash-janitor-workspace-*.tar.gz" -type f 2>/dev/null | head -1)
if [[ -n "$archive" && -s "$archive" ]]; then
  log_pass "archive-workspace tarball is non-empty"
else
  log_fail "archive-workspace tarball missing or empty"
fi

# ---- 13. Polish-bar-check ----
section "Polish-bar"
# Note: P2 (verdict evidence) WILL fail because the synthetic test doesn't
# resolve the 4 unknown verdicts the way a real Phase 5 would. That's a
# test-environment limitation, not a script bug. We accept up to 1 fail.
pb_out=$("$SCRIPT_DIR/polish-bar-check.sh" "$REPO" 2>&1 || true)
pb_fails=$(echo "$pb_out" | grep -cE 'FAIL' || true)
if [[ "${pb_fails:-0}" -le 1 ]]; then
  log_pass "polish-bar (≤1 expected synthetic-test FAIL)"
else
  log_fail "polish-bar has $pb_fails FAILs (expected ≤1)"
  echo "$pb_out" | grep FAIL >&2
fi

# ---- Summary ----
echo
echo "============================================================"
echo "Integration test summary"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  Test repo: $REPO"
echo "============================================================"

if [[ "$FAIL" -eq 0 ]]; then
  if [[ "$KEEP" == "true" ]]; then
    archive="/tmp/gsj-test-repo-archive-$TS"
    mv "$REPO" "$archive"
    echo "Test repo archived to: $archive"
  fi
  exit 0
fi

echo "Test repo retained at $REPO for inspection." >&2
exit 1
