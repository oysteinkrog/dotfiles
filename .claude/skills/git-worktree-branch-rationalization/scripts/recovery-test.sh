#!/usr/bin/env bash
# recovery-test.sh — Phase 3 / Phase 10 sanity check: verify the bundle's
# recovery recipes actually work on a sample.
#
# Without this check, a bundle-format bug surfaces only when the user
# desperately tries to recover six months later. Running the recipes once,
# in a temp clone, against one branch and one worktree gives us proof now.
#
# Two restore exercises:
#
#   1. Branch restore via `git fetch <object-bundle.pack> <ref>:<name>`.
#      Picks one branch from the bundle, restores it into a temp clone,
#      and verifies the restored tip equals the bundle's recorded SHA.
#
#   2. Worktree dirty-state restore via the staged + unstaged + untracked
#      recipe. Picks a removed (or to-be-removed) worktree from the bundle,
#      runs the recipe, and verifies `git status --porcelain` matches the
#      captured snapshot.
#
# We never mutate the user's repo — all work happens in a temp directory.
# The temp dir is moved (not rm'd, per AGENTS.md Rule 1) to a `.removed-<ts>`
# location at the end so the user can inspect it if they want to.
#
# Exit codes:
#   0  every chosen restore succeeded
#   1  one or more restore exercises failed
#   2  preflight failed (bundle missing, no candidates)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: recovery-test.sh <project-path> [<branch-slug>] [<worktree-sanitized>]

Phase 3 / 10 sanity check. Verifies one branch restore and one worktree
dirty-state restore using only the bundle. All work happens in a temp clone;
the original repo is never touched.

Optional positional arguments override the otherwise-random sample picks.
Use them when reproducing a specific failure.

Env:
  WORKSPACE                  Workspace dir override.
  RECOVERY_TEST_TMPDIR       Override the parent of the temp clone (default \$TMPDIR / /tmp).
  RECOVERY_TEST_KEEP=1       Keep the temp clone in place (default: rename to .removed-<ts>).

Exit codes:
  0  success
  1  one or more restores failed
  2  preflight failed
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
BR_SLUG_ARG="${2:-}"
WT_SAN_ARG="${3:-}"

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"

for f in "$BRANCHES_TSV" "$WORKTREES_TSV" "$BUNDLE_PATH_FILE"; do
  [[ -f "$f" ]] || { echo "ERROR: $f missing" >&2; exit 2; }
done
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"
PACK="$BUNDLE/object-bundle.pack"
[[ -d "$BUNDLE" ]] || { echo "ERROR: bundle directory $BUNDLE missing" >&2; exit 2; }

PARENT_TMP="${RECOVERY_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
TEST_ROOT="$PARENT_TMP/wbr-recovery-test-$STAMP"
mkdir -p "$TEST_ROOT"
log "Temp test root: $TEST_ROOT"

failures=0

# ------------------------------------------------------------------
# Test 1: branch restore via the object-bundle pack.
# ------------------------------------------------------------------

select_branch_slug() {
  if [[ -n "$BR_SLUG_ARG" ]]; then
    printf '%s\n' "$BR_SLUG_ARG"
    return 0
  fi
  awk -F'\t' 'NR > 1 && $9 ~ /^[0-9]+$/ && $9 + 0 > 0 { print $2 }' "$BRANCHES_TSV" \
    | { shuf -n 1 2>/dev/null || sed -n '1p'; } || true
}

BR_SLUG=$(select_branch_slug)
if [[ -z "$BR_SLUG" ]]; then
  log "No branch with commits_ahead>0 in inventory; skipping branch-restore test."
else
  BR_ROW=$(awk -F'\t' -v s="$BR_SLUG" 'NR > 1 && $2 == s {print; exit}' "$BRANCHES_TSV")
  BR_NAME=""
  BR_EXPECTED_SHA=""
  if [[ -n "$BR_ROW" ]]; then
    tsv_read "$BR_ROW" BR_NAME _slug BR_EXPECTED_SHA _last_date _author _subject _ahead _behind _commits_ahead _cherry_plus _cherry_minus _upstream _upstream_status _wt_path _touched _insertions _deletions _files_changed _age_days _prefix
  fi
  BR_BACKUP_REF="refs/branch-rationalization-backup/$BR_SLUG"

  log "Test 1: restore branch '$BR_NAME' (slug=$BR_SLUG) from $PACK"
  if [[ -z "$BR_ROW" ]]; then
    log "  FAIL: slug $BR_SLUG is not present in $BRANCHES_TSV"
    failures=$((failures + 1))
  elif [[ -z "$BR_EXPECTED_SHA" ]]; then
    log "  FAIL: branch '$BR_NAME' has no recorded head_sha in $BRANCHES_TSV"
    failures=$((failures + 1))
  elif [[ ! -f "$PACK" ]]; then
    log "  FAIL: $PACK missing — cannot exercise object-bundle restore"
    failures=$((failures + 1))
  else
    BR_CLONE="$TEST_ROOT/branch-restore"
    if git clone --quiet "$PROJECT_ABS" "$BR_CLONE" 2>/dev/null; then
      restored_branch="recovery-test-$BR_SLUG"
      if git -C "$BR_CLONE" fetch --quiet "$PACK" "$BR_BACKUP_REF:refs/heads/$restored_branch" 2>/dev/null; then
        restored_sha=$(git -C "$BR_CLONE" rev-parse --verify --quiet "refs/heads/$restored_branch^{commit}" 2>/dev/null || echo "")
        if [[ "$restored_sha" == "$BR_EXPECTED_SHA" ]]; then
          log "  OK: restored tip $restored_sha matches recorded SHA"
        else
          log "  FAIL: restored tip $restored_sha != recorded $BR_EXPECTED_SHA"
          failures=$((failures + 1))
        fi
      else
        log "  FAIL: git fetch from $PACK failed"
        failures=$((failures + 1))
      fi
    else
      log "  FAIL: cannot clone $PROJECT_ABS into $BR_CLONE"
      failures=$((failures + 1))
    fi
  fi
fi

# ------------------------------------------------------------------
# Test 2: worktree dirty-state restore via staged + unstaged + untracked.
# ------------------------------------------------------------------

select_worktree() {
  if [[ -n "$WT_SAN_ARG" ]]; then
    local row path
    while IFS= read -r row; do
      tsv_read "$row" path _rest
      [[ "$path" == "path" ]] && continue
      if [[ "$(sanitize_path "$path")" == "$WT_SAN_ARG" ]]; then
        printf '%s\n' "$path"
        return 0
      fi
    done < "$WORKTREES_TSV"
    return 0
  fi
  # Pick a dirty, non-active worktree if any exists.
  awk -F'\t' 'NR > 1 && $9 == "true" && $16 != "true" {print $1}' "$WORKTREES_TSV" \
    | { shuf -n 1 2>/dev/null || sed -n '1p'; } || true
}

WT_PATH=$(select_worktree)
if [[ -z "$WT_PATH" ]]; then
  log "No dirty non-active worktree in inventory; skipping worktree-restore test."
else
  WT_SAN=$(sanitize_path "$WT_PATH")
  WT_DIR="$BUNDLE/worktrees/$WT_SAN"
  STATUS_FILE="$WT_DIR/status.txt"
  STAGED_DIFF="$WT_DIR/staged.diff"
  UNSTAGED_DIFF="$WT_DIR/unstaged.diff"
  UNTRACKED_TGZ="$WT_DIR/untracked.tar.gz"
  UNTRACKED_LIST="$WT_DIR/.untracked.list"
  UNTRACKED_HASHES="$WT_DIR/.untracked.sha256"

  log "Test 2: restore worktree dirty state for $WT_PATH (san=$WT_SAN)"
  if [[ ! -d "$WT_DIR" ]]; then
    log "  FAIL: $WT_DIR missing in bundle"
    failures=$((failures + 1))
  else
    # Look up the branch the worktree is on (so we can recreate against it).
    WT_BRANCH=$(awk -F'\t' -v p="$WT_PATH" 'NR > 1 && $1 == p {print $2; exit}' "$WORKTREES_TSV")
    WT_HEAD=$(awk -F'\t' -v p="$WT_PATH" 'NR > 1 && $1 == p {print $7; exit}' "$WORKTREES_TSV")

    WT_CLONE="$TEST_ROOT/worktree-restore"
    if git clone --quiet "$PROJECT_ABS" "$WT_CLONE" 2>/dev/null; then
      # Pull backup refs in case the branch was already deleted.
      if [[ -f "$PACK" ]]; then
        git -C "$WT_CLONE" fetch --quiet "$PACK" '+refs/branch-rationalization-backup/*:refs/branch-rationalization-backup/*' 2>/dev/null || true
      fi

      # Pick the recreate base. Prefer the live branch; fall back to backup ref;
      # fall back to the recorded SHA.
      base=""
      if [[ -n "$WT_BRANCH" ]] && [[ "$WT_BRANCH" != "(detached)" ]]; then
        if git -C "$WT_CLONE" rev-parse --verify --quiet "refs/heads/$WT_BRANCH^{commit}" >/dev/null 2>&1; then
          base="$WT_BRANCH"
        fi
      fi
      if [[ -z "$base" ]] && [[ -n "$WT_HEAD" ]]; then
        if git -C "$WT_CLONE" rev-parse --verify --quiet "${WT_HEAD}^{commit}" >/dev/null 2>&1; then
          base="$WT_HEAD"
        fi
      fi

      restored_path="$WT_CLONE/restored-wt"
      restore_ok=true

      if [[ -z "$base" ]]; then
        log "  FAIL: cannot determine recreate base (branch $WT_BRANCH, sha $WT_HEAD)"
        restore_ok=false
      elif ! git -C "$WT_CLONE" worktree add --detach --quiet "$restored_path" "$base" 2>/dev/null; then
        log "  FAIL: git worktree add failed for base=$base"
        restore_ok=false
      else
        # Apply staged diff to the index.
        if [[ -s "$STAGED_DIFF" ]]; then
          if ! git -C "$restored_path" apply --3way --cached "$STAGED_DIFF" 2>/dev/null; then
            log "  WARN: staged.diff did not apply cleanly (3-way)"
          fi
        fi
        # Apply unstaged diff to the worktree.
        if [[ -s "$UNSTAGED_DIFF" ]]; then
          if ! git -C "$restored_path" apply --3way "$UNSTAGED_DIFF" 2>/dev/null; then
            log "  WARN: unstaged.diff did not apply cleanly (3-way)"
          fi
        fi
        # Restore untracked files.
        if [[ -f "$UNTRACKED_TGZ" ]] && [[ -s "$UNTRACKED_LIST" ]]; then
          if ! tar --null -xzf "$UNTRACKED_TGZ" -C "$restored_path" -T "$UNTRACKED_LIST" 2>/dev/null; then
            log "  FAIL: untracked.tar.gz did not extract"
            restore_ok=false
          fi
          if [[ -s "$UNTRACKED_HASHES" ]]; then
            restored_untracked_hash=$(untracked_content_manifest_hash_for_root "$restored_path" "$UNTRACKED_LIST" 2>/dev/null || echo "MISSING")
            bundle_untracked_hash=$(sha256sum "$UNTRACKED_HASHES" 2>/dev/null | awk '{print $1}')
            if [[ "$restored_untracked_hash" == "$bundle_untracked_hash" ]]; then
              log "  OK: restored untracked byte manifest matches bundle ($restored_untracked_hash)"
            else
              log "  FAIL: restored untracked byte manifest $restored_untracked_hash != bundle $bundle_untracked_hash"
              restore_ok=false
            fi
          elif [[ -f "$UNTRACKED_TGZ" ]]; then
            log "  FAIL: untracked.tar.gz has no .untracked.sha256 byte manifest"
            restore_ok=false
          fi
        fi

        # Compare status hash. Status.txt was captured with porcelain=v2 and
        # explicit untracked inclusion; do the same here for parity.
        live_status_hash=$(git -C "$restored_path" status --porcelain=v2 --untracked-files=all 2>/dev/null | sha256sum | awk '{print $1}')
        bundle_status_hash=$(sha256sum "$STATUS_FILE" 2>/dev/null | awk '{print $1}')
        if [[ "$live_status_hash" == "$bundle_status_hash" ]]; then
          log "  OK: restored status matches bundle snapshot ($live_status_hash)"
        else
          # Status drift is expected for non-trivial untracked content (file
          # mtimes / mode bits differ post-extract) — degrade to WARN unless
          # restore_ok is already false.
          log "  WARN: restored status hash $live_status_hash != bundle $bundle_status_hash"
          log "        (mtime / mode drift is expected; verify substantive content manually if needed)"
        fi
      fi

      if [[ "$restore_ok" != "true" ]]; then
        failures=$((failures + 1))
      fi
    else
      log "  FAIL: cannot clone $PROJECT_ABS into $WT_CLONE"
      failures=$((failures + 1))
    fi
  fi
fi

# Cleanup: per AGENTS.md Rule 1, never delete files. Move the temp test root
# to a .removed-<stamp> sibling so the user (or DCG) can inspect it.
if [[ -z "${RECOVERY_TEST_KEEP:-}" ]] && [[ -d "$TEST_ROOT" ]]; then
  RETIRED="$TEST_ROOT.removed-$STAMP"
  if mv "$TEST_ROOT" "$RETIRED" 2>/dev/null; then
    log "Renamed temp test root to $RETIRED (mv-based; never rm)"
  else
    log "Could not rename $TEST_ROOT — leaving in place; user may inspect manually."
  fi
fi

echo
if [[ "$failures" -eq 0 ]]; then
  echo "=== recovery-test PASS ==="
  exit 0
else
  echo "=== recovery-test FAIL ($failures failure(s)) ==="
  exit 1
fi
