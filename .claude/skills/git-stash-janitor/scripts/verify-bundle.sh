#!/usr/bin/env bash
# verify-bundle.sh — Phase 3 gate: byte-equality verification of every
# backup ref vs. its live stash + every diff.
#
# Exit 0 = all verified.
# Exit 1 = any mismatch (run is unsafe; halt before destructive phases).

set -euo pipefail

PROJECT="${1:?Usage: verify-bundle.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
INVENTORY="$WORKSPACE/inventory.tsv"
BUNDLE="$(cat "$WORKSPACE/bundle_path.txt")"
LOG="$WORKSPACE/bundle_verification.log"

if [[ ! -d "$BUNDLE" ]]; then
  echo "ERROR: bundle not found at $BUNDLE" >&2
  exit 2
fi

: > "$LOG"
MISMATCH_COUNT=0
TOTAL=0

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

# shellcheck disable=SC2034 # inventory columns are positional; only some feed verification.
awk -F'\t' 'NR > 1' "$INVENTORY" | while IFS=$'\t' read -r n ref sha parent_sha date author message files ins dels has_untracked; do
  npad=$(printf '%03d' "$n")
  TOTAL=$((TOTAL + 1))

  # 1. Backup ref byte-equality
  live_sha="$sha"
  backup_sha=$(git -C "$PROJECT_ABS" rev-parse "refs/stash-backup/$npad" 2>/dev/null || echo "MISSING")
  if [[ "$live_sha" != "$backup_sha" ]]; then
    echo "MISMATCH n=$n REF: live=$live_sha backup=$backup_sha" >> "$LOG"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
  else
    echo "OK n=$n REF: $sha" >> "$LOG"
  fi

  # 2. Diff round-trip. Re-derive via $sha (frozen inventory identity), NOT
  # via $ref (live stash@{N} stack position). If a concurrent agent ran
  # `git stash push` between Phase 2 inventory and Phase 3 verify, stash@{N}
  # now points at a DIFFERENT commit than what the bundle captured — a $ref
  # round-trip would compare bundle-of-stash-A vs. live-of-stash-B and report
  # a spurious MISMATCH. $sha is the stable identity used at build-bundle
  # time, so re-deriving via $sha is the apples-to-apples comparison.
  if [[ ! -f "$BUNDLE/diffs/$npad.diff" ]]; then
    echo "MISSING n=$n DIFF: $BUNDLE/diffs/$npad.diff not found" >> "$LOG"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
  else
    live_hash=$(git -C "$PROJECT_ABS" stash show -p --binary "$sha" 2>/dev/null | sha256sum | awk '{print $1}')
    bundle_hash=$(sha256sum "$BUNDLE/diffs/$npad.diff" | awk '{print $1}')
    if [[ "$live_hash" != "$bundle_hash" ]]; then
      echo "MISMATCH n=$n DIFF: live_sha256=$live_hash bundle_sha256=$bundle_hash" >> "$LOG"
      MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    fi
  fi

  # 3. Meta file presence
  if [[ ! -f "$BUNDLE/meta/$npad.txt" ]]; then
    echo "MISSING n=$n META: $BUNDLE/meta/$npad.txt not found" >> "$LOG"
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
  fi

  # 4. Untracked-file materialization. `git stash show -p --binary` does not include
  # untracked files, so this directory is part of the recovery contract when
  # the stash commit has a third parent. Derive that from the commit too; the
  # inventory flag is evidence to cross-check, not the source of truth.
  untracked_dir="$BUNDLE/stashed-untracked/$npad"
  untracked_tree="${sha}^3"
  actual_has_untracked=false
  if git -C "$PROJECT_ABS" rev-parse --verify --quiet "$untracked_tree" >/dev/null; then
    actual_has_untracked=true
  fi
  if [[ "$has_untracked" == "true" || "$actual_has_untracked" == "true" ]]; then
    if [[ "$has_untracked" != "true" && "$actual_has_untracked" == "true" ]]; then
      echo "MISMATCH n=$n UNTRACKED: inventory has_untracked=$has_untracked but $untracked_tree exists" >> "$LOG"
      MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    fi
    if [[ "$actual_has_untracked" != "true" ]]; then
      echo "MISSING n=$n UNTRACKED: $untracked_tree not found" >> "$LOG"
      MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    elif [[ ! -d "$untracked_dir" ]]; then
      echo "MISSING n=$n UNTRACKED: $untracked_dir not found" >> "$LOG"
      MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    elif [[ -z "$(find "$untracked_dir" -mindepth 1 -print -quit)" ]]; then
      echo "MISSING n=$n UNTRACKED: $untracked_dir is empty" >> "$LOG"
      MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    else
      expected_manifest="$WORKSPACE/.verify_${npad}_untracked_expected.tsv"
      actual_manifest="$WORKSPACE/.verify_${npad}_untracked_actual.tsv"
      write_git_tree_manifest "$untracked_tree" "$expected_manifest"
      write_materialized_tree_manifest "$untracked_dir" "$actual_manifest"
      if cmp -s "$expected_manifest" "$actual_manifest"; then
        echo "OK n=$n UNTRACKED: materialized files match $untracked_tree" >> "$LOG"
      else
        echo "MISMATCH n=$n UNTRACKED: materialized files differ from $untracked_tree" >> "$LOG"
        diff -u "$expected_manifest" "$actual_manifest" >> "$LOG" || true
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
      fi
    fi
  fi

done

# Recount from log directly (the while ran in a subshell so MISMATCH_COUNT
# doesn't propagate). `grep -c` exits non-zero when there are 0 matches,
# so guard with `|| true` and normalize empty output to 0.
count_lines() {
  local out
  out=$(grep -cE "$1" "$2" 2>/dev/null || true)
  printf '%s' "${out:-0}"
}
ACTUAL_MISMATCHES=$(count_lines '^MISMATCH|^MISSING' "$LOG")
OK_ROWS=$(count_lines '^OK ' "$LOG")
TOTAL_ROWS=$(awk 'NR > 1' "$INVENTORY" | wc -l)

echo "Verification complete:"
echo "  Total stashes:    $TOTAL_ROWS"
echo "  OK rows:          $OK_ROWS"
echo "  Mismatch / missing: $ACTUAL_MISMATCHES"
echo
echo "Full log: $LOG"

if [[ "$ACTUAL_MISMATCHES" -gt 0 ]]; then
  echo
  echo "*** GATE FAILURE ***"
  echo "Some bundle artifacts do not match the live stashes."
  echo "Inspect $LOG for details. Do NOT proceed to destructive phases."
  exit 1
fi

echo "Gate passed. Bundle is byte-equality-verified. Safe to proceed."
exit 0
