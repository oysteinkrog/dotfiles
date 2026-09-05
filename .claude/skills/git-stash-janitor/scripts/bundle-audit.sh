#!/usr/bin/env bash
# bundle-audit.sh — Deep audit of bundle integrity beyond the verify-bundle gate.
#
# Goes beyond byte-equality:
# - Verifies the README's recipes parse correctly
# - Spot-checks 3 random stashes by re-deriving git stash show -p --binary
# - Audits untracked-files dirs match meta has_untracked flag
# - Counts file types and reports anomalies

set -euo pipefail

PROJECT="${1:?Usage: bundle-audit.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
BUNDLE="$(cat "$WORKSPACE/bundle_path.txt")"
INVENTORY="$WORKSPACE/inventory.tsv"
LOG="$WORKSPACE/bundle_audit.log"

: > "$LOG"
findings=0

note() { echo "[$1] $2" | tee -a "$LOG"; }
fail() { note FAIL "$1"; findings=$((findings + 1)); }
pass() { note PASS "$1"; }

write_git_tree_manifest() {
  local treeish="$1"
  local out="$2"
  git -C "$PROJECT_ABS" ls-tree -r -z "$treeish" \
    | while IFS=$'\t' read -r -d '' meta path; do
        mode=${meta%% *}
        rest=${meta#* }
        type=${rest%% *}
        object=${rest##* }
        printf '%s\t%s\t%s\t%s\n' "$mode" "$type" "$object" "$path"
      done \
    | sort > "$out"
}

write_materialized_tree_manifest() {
  local root="$1"
  local out="$2"
  (
    cd "$root"
    find . \( -type f -o -type l \) -print0 \
      | while IFS= read -r -d '' path; do
          rel=${path#./}
          if [[ -L "$path" ]]; then
            mode=120000
            target=$(readlink "$path")
            object=$(printf '%s' "$target" | git -C "$PROJECT_ABS" hash-object --stdin)
          else
            if [[ -x "$path" ]]; then mode=100755; else mode=100644; fi
            object=$(git -C "$PROJECT_ABS" hash-object -- "$root/$rel")
          fi
          printf '%s\tblob\t%s\t%s\n' "$mode" "$object" "$rel"
        done
  ) | sort > "$out"
}

# A1: README exists and has the canonical sections
if [[ -f "$BUNDLE/README.md" ]]; then
  if grep -qE '^## Recovery recipes' "$BUNDLE/README.md" && \
     grep -qE 'format-patch' "$BUNDLE/README.md"; then
    pass "README.md has recovery recipes + format-patch warning"
  else
    fail "README.md missing canonical sections"
  fi
else
  fail "README.md does not exist"
fi

# A2: index.tsv row count matches diff/meta counts.
# Both `ls glob | wc -l` AND `find /missing/dir | wc -l` abort under
# `set -euo pipefail` when the directory is missing — `ls` exits 2,
# `find` exits 1, both propagate via pipefail and trip set -e on
# `var=$(failing)`. Wrap with `|| true` inside braces to swallow the
# non-zero exit; wc gets empty input and outputs 0.
inv_rows=$(awk 'NR > 1' "$INVENTORY" | wc -l)
# Match ONLY the canonical bundle-diff filename pattern <NNN>.diff (at least 3
# digits + .diff). Without the strict regex, partial-split.sh's <NNN>.split.diff files
# (Phase 7 outputs) would also match `*.diff` and inflate the count, producing
# a spurious "count mismatch" failure on any run where Phase 7 actually ran.
# Discovered during the integration-test run after a partial-split produced
# 008.split.diff and bundle-audit reported diffs=10 instead of 9.
diff_count=$({ find "$BUNDLE/diffs" -maxdepth 1 -type f -regextype posix-extended -regex '.*/[0-9]{3,}\.diff' 2>/dev/null || true ; } | wc -l)
meta_count=$({ find "$BUNDLE/meta"  -maxdepth 1 -type f -name '*.txt'  2>/dev/null || true ; } | wc -l)
idx_rows=$({ awk 'NR > 1' "$BUNDLE/index.tsv" 2>/dev/null || true ; } | wc -l)

if [[ "$inv_rows" -eq "$diff_count" && "$inv_rows" -eq "$meta_count" && "$inv_rows" -eq "$idx_rows" ]]; then
  pass "counts match: inventory=$inv_rows diffs=$diff_count meta=$meta_count index=$idx_rows"
else
  fail "count mismatch: inventory=$inv_rows diffs=$diff_count meta=$meta_count index=$idx_rows"
fi

# A3: backup refs exist for every inventory row
backup_count=$(git -C "$PROJECT_ABS" for-each-ref refs/stash-backup/ 2>/dev/null | wc -l)
if [[ "$backup_count" -eq "$inv_rows" ]]; then
  pass "backup refs: $backup_count of $inv_rows"
else
  fail "backup refs: $backup_count, expected $inv_rows"
fi

# A4: untracked-files dirs match meta has_untracked flag and byte content.
# CAUTION: `awk | while` runs the loop in a subshell, so `fail()` inside it
# would not increment `findings`. We use a temp-file approach: append findings
# to a tally file inside the subshell, then count them in the parent shell.
A4_TALLY="$WORKSPACE/.audit_a4_tally"
: > "$A4_TALLY"
awk -F'\t' 'NR > 1' "$INVENTORY" | while IFS=$'\t' read -r n _ref _sha _parent_sha _date _author _message _files _ins _dels has_untracked; do
  npad=$(printf '%03d' "$n")
  has_dir=false
  untracked_dir="$BUNDLE/stashed-untracked/$npad"
  [[ -d "$BUNDLE/stashed-untracked/$npad" ]] && has_dir=true
  if [[ "$has_untracked" != "true" && "$has_dir" == "true" ]]; then
    echo "n=$n" >> "$A4_TALLY"
    note FAIL "n=$n: has_untracked=$has_untracked but stashed-untracked/$npad/ exists"
  elif [[ "$has_untracked" == "true" && "$has_dir" != "true" ]]; then
    echo "n=$n" >> "$A4_TALLY"
    note FAIL "n=$n: has_untracked=true but no stashed-untracked/$npad/ directory"
  elif [[ "$has_untracked" == "true" ]] && [[ -z "$(find "$BUNDLE/stashed-untracked/$npad" -mindepth 1 -print -quit)" ]]; then
    echo "n=$n" >> "$A4_TALLY"
    note FAIL "n=$n: has_untracked=true but stashed-untracked/$npad/ is empty"
  elif [[ "$has_untracked" == "true" ]]; then
    expected_manifest="$WORKSPACE/.audit_a4_${npad}_expected_untracked.tsv"
    actual_manifest="$WORKSPACE/.audit_a4_${npad}_actual_untracked.tsv"
    if ! write_git_tree_manifest "refs/stash-backup/$npad^3" "$expected_manifest"; then
      echo "n=$n" >> "$A4_TALLY"
      note FAIL "n=$n: cannot read third-parent untracked tree from refs/stash-backup/$npad^3"
    elif ! write_materialized_tree_manifest "$untracked_dir" "$actual_manifest"; then
      echo "n=$n" >> "$A4_TALLY"
      note FAIL "n=$n: cannot inventory materialized stashed-untracked/$npad/"
    elif ! cmp -s "$expected_manifest" "$actual_manifest"; then
      echo "n=$n" >> "$A4_TALLY"
      note FAIL "n=$n: materialized stashed-untracked/$npad/ does not byte-match refs/stash-backup/$npad^3"
    fi
  fi
done
a4_failures=$(wc -l < "$A4_TALLY")
findings=$((findings + a4_failures))

# A5: spot-check 3 random stashes for byte-equality.
# Use the BACKUP REF (refs/stash-backup/<NNN>), not stash@{N}: stash@{N} is a
# stack position that's gone after Phase 9 drops, so a bundle-audit run at
# Phase 10 handoff would falsely flag every spot-check as "BYTE MISMATCH"
# (live stash gone → empty stdout → empty hash → differs from bundle hash).
# The backup ref points at the same commit and survives drops/gc, so it's
# the stable identity for re-deriving the diff.
spot_check_failed=0
for n in $(awk 'NR > 1 {print $1}' "$INVENTORY" | shuf -n 3 2>/dev/null || awk 'NR > 1 {print $1}' "$INVENTORY" | head -3); do
  npad=$(printf '%03d' "$n")
  diff_path="$BUNDLE/diffs/$npad.diff"
  backup_ref="refs/stash-backup/$npad"
  if [[ -f "$diff_path" ]]; then
    if ! git -C "$PROJECT_ABS" rev-parse --verify --quiet "$backup_ref" >/dev/null 2>&1; then
      fail "spot-check n=$n: backup ref $backup_ref no longer resolves (cannot re-derive)"
      spot_check_failed=$((spot_check_failed + 1))
      continue
    fi
    live_hash=$(git -C "$PROJECT_ABS" stash show -p --binary "$backup_ref" 2>/dev/null | sha256sum | awk '{print $1}')
    bundle_hash=$(sha256sum "$diff_path" | awk '{print $1}')
    if [[ "$live_hash" == "$bundle_hash" ]]; then
      pass "spot-check n=$n: byte-equal (re-derived from $backup_ref)"
    else
      fail "spot-check n=$n: BYTE MISMATCH"
      spot_check_failed=$((spot_check_failed + 1))
    fi
  fi
done

# A6: README mentions current bundle path
if [[ -f "$BUNDLE/README.md" ]] && grep -qF "$BUNDLE" "$BUNDLE/README.md"; then
  pass "README references its own bundle path"
else
  fail "README does not reference its bundle path (template not substituted?)"
fi

# A7: every diff is non-empty UNLESS the inventory declares files=0 (which
# happens for untracked-only stashes — `git stash -u` with no tracked changes,
# where `git stash show -p --binary` legitimately produces no output). Without this
# filter, every untracked-only stash produces a spurious WARN — discovered
# during the integration-test run where stash@{4} (the -u canary) was flagged.
# Match the strict <NNN>.diff filename pattern (excludes Phase 7's split.diff).
empty_diffs=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ ! -s "$f" ]]; then
    bn=$(basename "$f" .diff)
    # Look up files count from inventory: files column is index 8 (1-based).
    inv_files=$(awk -F'\t' -v n="${bn#0}" -v n0="${bn#00}" -v n00="$bn" \
                  'NR > 1 && ($1 == n || $1 == n0 || $1 == n00) {print $8; exit}' "$INVENTORY")
    if [[ "${inv_files:-0}" -eq 0 ]]; then
      pass "diff $bn empty (consistent with inventory files=0; untracked-only stash)"
    else
      empty_diffs=$((empty_diffs + 1))
      note WARN "empty diff: $(basename "$f") (inventory says files=$inv_files — should NOT be empty)"
    fi
  fi
done < <( { find "$BUNDLE/diffs" -maxdepth 1 -type f -regextype posix-extended -regex '.*/[0-9]{3,}\.diff' 2>/dev/null || true ; } )
if [[ "$empty_diffs" -gt 0 ]]; then
  note WARN "$empty_diffs empty diffs with inventory files>0 (could indicate stash content issues)"
fi

echo
echo "=== Bundle audit summary ==="
echo "Findings: $findings"
echo "Empty diffs: $empty_diffs"
echo "Log: $LOG"

if [[ "$findings" -gt 0 ]]; then
  exit 1
fi
exit 0
