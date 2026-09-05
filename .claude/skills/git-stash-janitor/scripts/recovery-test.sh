#!/usr/bin/env bash
# recovery-test.sh — Verify the bundle's recovery recipes actually work.
#
# Picks a random stash from the bundle, attempts recovery via:
#   (a) cherry-pick from refs/stash-backup/<NNN>
#   (b) git apply --3way <bundle>/diffs/<NNN>.diff
#   (c) materialized stashed-untracked/<NNN>/ files, when present
# on a detached HEAD smoke-test checkout. Reports success/failure for each path.
#
# Does NOT modify the recovery branch or primary branch.

set -euo pipefail

PROJECT="${1:?Usage: recovery-test.sh <project-path> [stash-n]}"
N="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
BUNDLE="$(cat "$WORKSPACE/bundle_path.txt")"
INVENTORY="$WORKSPACE/inventory.tsv"

# Pick a random n if not specified
if [[ -z "$N" ]]; then
  N=$(awk 'NR > 1 {print $1}' "$INVENTORY" | shuf -n 1 2>/dev/null)
  [[ -z "$N" ]] && N=$(awk 'NR > 1 {print $1; exit}' "$INVENTORY")
fi

if [[ -z "$N" ]]; then
  echo "ERROR: no stashes in inventory" >&2
  exit 1
fi

NPAD=$(printf '%03d' "$N")
DIFF="$BUNDLE/diffs/$NPAD.diff"
BACKUP_REF="refs/stash-backup/$NPAD"
HAS_TRACKED_DIFF=false
if [[ -f "$DIFF" ]] && grep -q '^diff --git ' "$DIFF"; then
  HAS_TRACKED_DIFF=true
fi

echo "=== Recovery test: stash@{$N} (n=$N) ==="

# Save current state. The smoke test changes checkout state, so refuse to run
# when local work is present rather than risk sweeping unrelated changes into a
# test commit or blocking checkout restoration.
dirty_for_test=$(git -C "$PROJECT_ABS" status --porcelain -- . ':(exclude).stash_janitor_workspace' 2>/dev/null)
if [[ -n "$dirty_for_test" ]]; then
  echo "ERROR: recovery-test.sh requires a clean working tree." >&2
  echo "$dirty_for_test" >&2
  echo "It switches to a detached HEAD for a smoke test; rerun after the run's worktree is clean." >&2
  exit 2
fi
ORIG_REF=$(git -C "$PROJECT_ABS" symbolic-ref --quiet --short HEAD 2>/dev/null \
           || git -C "$PROJECT_ABS" rev-parse HEAD)

# Test 1: cherry-pick from backup ref.
# Stash backup refs point at merge commits. `-m 1` selects the original HEAD
# parent and verifies the tracked/index recovery path. The test commit lands on
# detached HEAD, then the original ref is restored; no branch ref is created or
# deleted.
echo
echo "Test 1: cherry-pick -m 1 from $BACKUP_REF"
if [[ "$HAS_TRACKED_DIFF" != "true" ]]; then
  echo "  - skipped: stash has no tracked/index diff; untracked files are checked separately"
  test1_ok=false
elif git -C "$PROJECT_ABS" rev-parse "$BACKUP_REF" >/dev/null 2>&1; then
  git -C "$PROJECT_ABS" checkout -q --detach HEAD 2>/dev/null
  if git -C "$PROJECT_ABS" cherry-pick -m 1 --no-edit "$BACKUP_REF" >/dev/null 2>&1; then
    echo "  ✓ cherry-pick -m 1 from $BACKUP_REF works (test commit landed on detached HEAD)"
    test1_ok=true
  else
    echo "  ✗ cherry-pick -m 1 failed (conflicts; would need manual resolution in real recovery)"
    git -C "$PROJECT_ABS" cherry-pick --abort 2>/dev/null || true
    test1_ok=false
  fi
  git -C "$PROJECT_ABS" checkout -q "$ORIG_REF" 2>/dev/null
else
  echo "  ✗ $BACKUP_REF does not exist"
  test1_ok=false
fi

# Test 2: git apply --3way --check the bundle diff
echo
echo "Test 2: git apply --3way --check $DIFF"
if [[ "$HAS_TRACKED_DIFF" != "true" ]]; then
  echo "  - skipped: stash has no tracked/index diff; untracked files are checked separately"
  test2_ok=false
elif [[ -f "$DIFF" ]]; then
  if git -C "$PROJECT_ABS" apply --3way --check "$DIFF" 2>/dev/null; then
    echo "  ✓ apply --3way --check is clean"
    test2_ok=true
  else
    echo "  ✗ apply --3way --check fails (context drift; would need 3-way merge in real recovery)"
    test2_ok=false
  fi
else
  echo "  ✗ $DIFF does not exist"
  test2_ok=false
fi

# Test 3: meta and untracked-files coverage
echo
echo "Test 3: bundle artifacts complete for n=$N"
test3_ok=false
META="$BUNDLE/meta/$NPAD.txt"
if [[ -f "$META" ]]; then
  echo "  ✓ meta exists: $META"
else
  echo "  ✗ meta missing"
fi

has_u=$(awk -F'\t' -v n="$N" 'NR > 1 && $1 == n {print $11}' "$INVENTORY")
if [[ "$has_u" == "true" ]]; then
  UNTRACKED_DIR="$BUNDLE/stashed-untracked/$NPAD"
  if [[ ! -d "$UNTRACKED_DIR" ]]; then
    echo "  ✗ stashed-untracked/$NPAD/ missing (has_untracked=true)"
  elif [[ -z "$(find "$UNTRACKED_DIR" -mindepth 1 -print -quit)" ]]; then
    echo "  ✗ stashed-untracked/$NPAD/ is empty (has_untracked=true)"
  else
    echo "  ✓ stashed-untracked/$NPAD/ exists and is non-empty"
    test3_ok=true
  fi
fi

echo
if [[ "$test1_ok" == "true" || "$test2_ok" == "true" || "$test3_ok" == "true" ]]; then
  echo "✓ Recovery is possible for stash@{$N}"
  exit 0
else
  echo "✗ NEITHER recovery path works for stash@{$N}"
  exit 1
fi
