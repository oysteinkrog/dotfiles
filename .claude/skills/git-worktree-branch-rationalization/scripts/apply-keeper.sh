#!/usr/bin/env bash
# apply-keeper.sh — Phase 8 wrapper: apply ONE keeper (branch or worktree row)
# onto the rationalization branch using the strategy from triage.tsv.
#
# Usage:
#   apply-keeper.sh <project-path> branch <name>
#   apply-keeper.sh <project-path> worktree <path>
#
# Strategies (chosen per branch from triage.tsv apply_strategy column):
#   cherry-pick           — git cherry-pick --no-commit, gates, commit
#   squash-merge          — git merge --squash for small-coherent branches
#   rebase-and-merge      — replay branch commits onto rationalization-branch tip
#   harmonized-synthesis  — refused: main agent must Edit per harmonization_plan.md
#   split-commits-hunks   — refused at this layer: see scripts/partial-split helper (Phase 8b)
#   dirty-worktree-only   — apply staged.diff, unstaged.diff, copy untracked (separate commits)
#   none / none-default-drop — no-op apply (the entry will be dropped in Phase 10)
#
# Quality gates run after every apply. Pre-commit hooks are NEVER bypassed.
#
# Exit codes:
#   0  applied (or no-op for verdict=none)
#   3  refused: harmonized-synthesis (main agent's job)
#   4  gates failed
#   5  conflict / pre-conditions
#   8  preflight failed (workspace missing, wrong branch, etc.)
#   9  apply failed mid-flight

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage:
  apply-keeper.sh <project-path> branch   <name>
  apply-keeper.sh <project-path> worktree <path>

Phase 8 wrapper. Applies ONE keeper onto the rationalization branch using the
strategy recorded in <workspace>/triage.tsv. Runs the project's actual test/
typecheck/lint/UBS gates after every apply; never bypasses pre-commit hooks.

Env:
  WORKSPACE                       Workspace dir override.
  RATIONALIZATION_BRANCH          Override the rationalization branch name
                                  (default branch-rationalization-<DATE>).
  RATIONALIZATION_BRANCH_OVERRIDE_OK=1
                                  Allow apply on a non-rationalization branch (NOT recommended).

Exit codes:
  0  applied
  3  harmonized-synthesis (refused — main-agent's job)
  4  gates failed
  5  conflict / preconditions
  8  preflight failed
  9  apply failed mid-flight
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
KIND="${2:?missing kind: branch | worktree}"
TARGET="${3:?missing branch name or worktree path}"

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 8
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
TRIAGE="$WORKSPACE_DIR/triage.tsv"
PROFILE="$WORKSPACE_DIR/project_profile.json"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
APPLY_LOG="$WORKSPACE_DIR/apply_log.tsv"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"

for f in "$TRIAGE" "$PROFILE" "$BRANCHES_TSV" "$WORKTREES_TSV" "$BUNDLE_PATH_FILE"; do
  [[ -f "$f" ]] || { echo "ERROR: $f missing — run prior phases first." >&2; exit 8; }
done
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"
mkdir -p "$WORKSPACE_DIR/conflicts"

profile_value() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then jq -r --arg key "$key" '.[$key] // ""' "$PROFILE"; return; fi
  python3 - "$PROFILE" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f: data = json.load(f)
v = data.get(sys.argv[2], "")
if isinstance(v, bool): print("true" if v else "false")
elif v is None: print("")
else: print(v)
PY
}

CANONICAL=$(profile_value canonical_branch)
if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/heads/$CANONICAL"
elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/remotes/origin/$CANONICAL"
else
  echo "ERROR: canonical branch '$CANONICAL' does not resolve locally or as origin/$CANONICAL." >&2
  exit 8
fi
TEST_CMD=$(profile_value test_command)
TYPECHECK_CMD=$(profile_value typecheck_command)
LINT_CMD=$(profile_value lint_command)
UBS_AVAILABLE=$(profile_value ubs_available)

DATE_TAG=$(date -u +%Y-%m-%d)
PROFILE_RB=$(profile_value rationalization_branch)
[[ -z "$PROFILE_RB" ]] && PROFILE_RB="branch-rationalization-$DATE_TAG"
RB="${RATIONALIZATION_BRANCH:-$PROFILE_RB}"

# Initialize apply log.
if [[ ! -f "$APPLY_LOG" ]]; then
  printf 'kind\ttarget\tstrategy\tnew_commit_sha\tfiles_changed\tgates_status\tduration_s\tdrift\n' > "$APPLY_LOG"
fi

# Pre-condition: HEAD must be on the rationalization branch (or we create it).
CURRENT=$(git -C "$PROJECT_ABS" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
if [[ -z "${RATIONALIZATION_BRANCH_OVERRIDE_OK:-}" ]]; then
  if [[ -z "$CURRENT" ]]; then
    echo "ERROR: HEAD is detached. Apply requires a branch context." >&2
    exit 8
  fi
  if [[ "$CURRENT" == "$CANONICAL" ]]; then
    echo "ERROR: HEAD is on canonical '$CANONICAL'. Apply must run on the rationalization branch:" >&2
    echo "  git checkout -b $RB $CANON_REF    # if creating fresh" >&2
    echo "  git checkout $RB                  # if resuming" >&2
    echo "Set RATIONALIZATION_BRANCH_OVERRIDE_OK=1 to apply on the current branch anyway (NOT recommended)." >&2
    exit 8
  fi
  if [[ "$CURRENT" != "$RB" ]]; then
    echo "ERROR: current branch is '$CURRENT', not the rationalization branch '$RB'." >&2
    echo "Set RATIONALIZATION_BRANCH=$CURRENT if this is the intended rationalization branch." >&2
    echo "Set RATIONALIZATION_BRANCH_OVERRIDE_OK=1 only for a deliberate one-off override." >&2
    exit 8
  fi
fi

# Working-tree-drift snapshot (Axiom 12). Excludes the workspace.
WS_REL="$(basename "$WORKSPACE_DIR")"
DRIFT_FILE="$WORKSPACE_DIR/.apply_drift_$$.txt"
git -C "$PROJECT_ABS" status --porcelain=v2 --untracked-files=all -- . ":(exclude)$WS_REL" > "$DRIFT_FILE" 2>/dev/null || true
DRIFT="none"
if [[ -s "$DRIFT_FILE" ]]; then
  DRIFT="concurrent: $(wc -l < "$DRIFT_FILE") files"
  echo "ERROR: apply surface is not clean; refusing to create mixed recovery commits." >&2
  echo "  Drift snapshot: $DRIFT_FILE" >&2
  echo "  Run Phase 8 from a dedicated clean rationalization worktree, or finish/coordinate the existing changes first." >&2
  echo "  Per AGENTS.md, this script does not stash, revert, or overwrite concurrent work." >&2
  sed -n '1,20p' "$DRIFT_FILE" | sed 's/^/  /' >&2
  exit 8
fi

START=$(date +%s)
NEW_SHA=""
N_FILES=0
GATES_STATUS="passed"

# Look up triage row.
if [[ "$KIND" == "branch" ]]; then
  ROW=$(awk -F'\t' -v t="$TARGET" 'NR > 1 && $1 == "branch" && $2 == t {print; exit}' "$TRIAGE" || true)
elif [[ "$KIND" == "worktree" ]]; then
  ROW=$(awk -F'\t' -v t="$TARGET" 'NR > 1 && $1 == "worktree" && $2 == t {print; exit}' "$TRIAGE" || true)
else
  echo "ERROR: unknown kind '$KIND' (expected 'branch' or 'worktree')" >&2
  exit 8
fi
if [[ -z "$ROW" ]]; then
  echo "ERROR: no triage row for $KIND $TARGET" >&2
  exit 8
fi
verdict=""
conf=""
STRATEGY=""
evidence=""
files_csv=""
tsv_read "$ROW" _kind _name verdict conf STRATEGY evidence files_csv

# Idempotence: skip if already applied this entry.
if awk -F'\t' -v k="$KIND" -v t="$TARGET" 'NR > 1 && $1 == k && $2 == t && $4 != "" {found=1} END {exit !found}' "$APPLY_LOG"; then
  log "$KIND $TARGET already applied (per apply_log.tsv); skipping."
  exit 0
fi

# Run gates after a candidate commit lands. NEVER bypass pre-commit hooks.
run_profile_command() {
  local cmd="$1"
  case "$cmd" in
    "cargo test --workspace") cargo test --workspace ;;
    "bun test") bun test ;;
    "pnpm test") pnpm test ;;
    "yarn test") yarn test ;;
    "npm test") npm test ;;
    "pytest") pytest ;;
    "poetry run pytest") poetry run pytest ;;
    "go test ./...") go test ./... ;;
    "bundle exec rake test") bundle exec rake test ;;
    "cargo check --workspace") cargo check --workspace ;;
    "bun tsc --noEmit") bun tsc --noEmit ;;
    "npx tsc --noEmit") npx tsc --noEmit ;;
    "mypy .") mypy . ;;
    "go vet ./...") go vet ./... ;;
    "cargo clippy --workspace -- -D warnings") cargo clippy --workspace -- -D warnings ;;
    "npx eslint .") npx eslint . ;;
    "ruff check .") ruff check . ;;
    "golangci-lint run") golangci-lint run ;;
    *)
      echo "ERROR: unsupported gate command from project_profile.json: $cmd" >&2
      return 127
      ;;
  esac
}

run_gates() {
  GATES_STATUS="passed"
  if [[ -n "$TEST_CMD" ]]; then
    log "  gate: $TEST_CMD"
    if ! ( cd "$PROJECT_ABS" && run_profile_command "$TEST_CMD" ); then GATES_STATUS="failed-test"; return 1; fi
  fi
  if [[ -n "$TYPECHECK_CMD" ]]; then
    log "  gate: $TYPECHECK_CMD"
    if ! ( cd "$PROJECT_ABS" && run_profile_command "$TYPECHECK_CMD" ); then GATES_STATUS="failed-typecheck"; return 1; fi
  fi
  if [[ -n "$LINT_CMD" ]]; then
    log "  gate: $LINT_CMD"
    if ! ( cd "$PROJECT_ABS" && run_profile_command "$LINT_CMD" ); then GATES_STATUS="failed-lint"; return 1; fi
  fi
  if [[ "$UBS_AVAILABLE" == "true" ]]; then
    log "  gate: ubs ."
    if ! ( cd "$PROJECT_ABS" && ubs . ); then GATES_STATUS="failed-ubs"; return 1; fi
  fi
  return 0
}

diff_paths() {
  local diff="$1"
  awk '
    function clean(p) { sub(/[[:space:]]+$/, "", p); return p }
    function emit(p) { p = clean(p); if (p != "" && p != "/dev/null" && !seen[p]++) print p }
    /^--- a\// { p = $0; sub(/^--- a\//, "", p); emit(p); next }
    /^\+\+\+ b\// { p = $0; sub(/^\+\+\+ b\//, "", p); emit(p); next }
    /^rename from / { p = $0; sub(/^rename from /, "", p); emit(p); next }
    /^rename to /   { p = $0; sub(/^rename to /,   "", p); emit(p); next }
    /^Binary files a\// {
      line = $0
      sub(/^Binary files a\//, "", line)
      split_pos = index(line, " and b/")
      if (split_pos > 0) {
        old = substr(line, 1, split_pos - 1)
        rest = substr(line, split_pos + length(" and b/"))
        new = rest; sub(/ differ$/, "", new)
        emit(old); emit(new)
      }
    }
  ' "$diff"
  git -C "$PROJECT_ABS" apply --numstat "$diff" 2>/dev/null \
    | awk -F'\t' 'NF >= 3 && $3 != "" {print $3}' || true
}

stage_path_list() {
  local list="$1"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! git -C "$PROJECT_ABS" add -A -- "$f"; then
      echo "ERROR: failed to stage recovered path: $f" >&2
      return 1
    fi
  done < "$list"
}

stage_nul_path_list() {
  local list="$1" f stage_path
  while IFS= read -r -d '' f; do
    [[ -z "$f" ]] && continue
    stage_path="${f#./}"
    if ! git -C "$PROJECT_ABS" add -A -- "$stage_path"; then
      printf 'ERROR: failed to stage recovered path: %q\n' "$stage_path" >&2
      return 1
    fi
  done < "$list"
}

path_has_symlink_parent() {
  local rel="$1" current="$PROJECT_ABS" part
  local -a parts=()
  local i last

  IFS='/' read -r -a parts <<< "$rel"
  last=$((${#parts[@]} - 1))
  for ((i = 0; i < last; i++)); do
    part="${parts[$i]}"
    [[ -z "$part" || "$part" == "." ]] && continue
    current="$current/$part"
    if [[ -L "$current" ]]; then
      return 0
    fi
  done
  return 1
}

verify_untracked_tar_payload() {
  local wt_bundle="$1" manifest="$2"
  local expected_manifest="$wt_bundle/.untracked.sha256"
  local verify_root expected_hash actual_hash

  if [[ ! -s "$expected_manifest" ]]; then
    echo "ERROR: untracked tarball is missing its byte manifest: $expected_manifest" >&2
    return 1
  fi

  if ! verify_root="$(mktemp -d "$WORKSPACE_DIR/.apply_untracked_verify_XXXXXX")"; then
    echo "ERROR: could not create untracked payload verification directory under $WORKSPACE_DIR" >&2
    return 1
  fi

  if ! tar --null -xzf "$wt_bundle/untracked.tar.gz" -C "$verify_root" -T "$manifest"; then
    echo "ERROR: untracked tarball failed verification extraction: $wt_bundle/untracked.tar.gz" >&2
    return 1
  fi

  expected_hash=$(sha256sum "$expected_manifest" 2>/dev/null | awk '{print $1}')
  actual_hash=$(untracked_content_manifest_hash_for_root "$verify_root" "$manifest" 2>/dev/null || true)
  if [[ -z "$expected_hash" || -z "$actual_hash" || "$expected_hash" != "$actual_hash" ]]; then
    echo "ERROR: untracked tarball bytes do not match bundle byte manifest." >&2
    echo "  Archive: $wt_bundle/untracked.tar.gz" >&2
    echo "  Manifest: $expected_manifest" >&2
    echo "  Verification extract: $verify_root" >&2
    return 1
  fi
}

log_apply_row() {
  local sha="$1" gates="$2" dur="$3"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$KIND" "$TARGET" "$STRATEGY" "$sha" "$N_FILES" "$gates" "$dur" "$DRIFT" \
    >> "$APPLY_LOG"
}

# ---- Strategy dispatch ----

case "$STRATEGY" in
  none|none-default-drop)
    log "Strategy '$STRATEGY' for $KIND $TARGET — no apply; will be handled in Phase 10."
    log_apply_row "" "skipped-$STRATEGY" "$(( $(date +%s) - START ))"
    exit 0
    ;;

  harmonized-synthesis)
    echo "REFUSED: $KIND $TARGET is a harmonization participant." >&2
    echo "  See $WORKSPACE_DIR/harmonization_plan.md and have the main agent author the synthesis via Edit." >&2
    echo "  After synthesis, re-run with STRATEGY=cherry-pick or commit the synthesis directly to $RB." >&2
    log_apply_row "" "refused-harmonized" "$(( $(date +%s) - START ))"
    exit 3
    ;;

  split-commits-hunks)
    echo "REFUSED: split-commits-hunks for $TARGET is handled in Phase 8b (partial-split)." >&2
    echo "  This script applies whole-branch strategies only." >&2
    log_apply_row "" "refused-split" "$(( $(date +%s) - START ))"
    exit 3
    ;;

  cherry-pick)
    [[ "$KIND" != "branch" ]] && { echo "ERROR: cherry-pick strategy requires a branch target." >&2; exit 5; }
    TARGET_REF="refs/heads/$TARGET"
    # Find merge-base, cherry-pick all commits on the branch above it.
    MERGE_BASE=$(git -C "$PROJECT_ABS" merge-base "$CANON_REF" "$TARGET_REF" 2>/dev/null || true)
    [[ -z "$MERGE_BASE" ]] && { echo "ERROR: cannot resolve merge-base for $TARGET" >&2; exit 5; }
    log "cherry-pick $MERGE_BASE..$TARGET (dry-run first)..."
    # Build the list of SHAs.
    mapfile -t SHAS < <(git -C "$PROJECT_ABS" rev-list --reverse "$MERGE_BASE..$TARGET_REF" 2>/dev/null)
    if [[ ${#SHAS[@]} -eq 0 ]]; then
      log "$TARGET has no commits ahead of canonical; nothing to apply."
      log_apply_row "" "skipped-empty" "$(( $(date +%s) - START ))"
      exit 0
    fi
    # Apply each commit individually with --no-commit first to preview, then commit.
    for s in "${SHAS[@]}"; do
      if ! git -C "$PROJECT_ABS" cherry-pick --no-commit "$s" >/dev/null 2>&1; then
        echo "ERROR: cherry-pick conflict on $s" >&2
        echo "  Conflict context: $WORKSPACE_DIR/conflicts/branch_$(slugify_branch "$TARGET").context.md" >&2
        {
          printf '# Cherry-pick conflict: %s on %s\n\n' "$s" "$TARGET"
          printf '## git status\n\n```\n'
          git -C "$PROJECT_ABS" status --porcelain=v2 --untracked-files=all || true
          printf '```\n'
        } > "$WORKSPACE_DIR/conflicts/branch_$(slugify_branch "$TARGET").context.md"
        # Surface to user — abort the cherry-pick state explicitly.
        git -C "$PROJECT_ABS" cherry-pick --abort 2>/dev/null || true
        log_apply_row "" "conflict" "$(( $(date +%s) - START ))"
        exit 5
      fi
      # Stage was modified by cherry-pick; commit with the original message + recovery note.
      ORIG_MSG=$(git -C "$PROJECT_ABS" log -1 --format='%B' "$s" 2>/dev/null || echo "recover from $TARGET")
      if ! {
        printf '%s\n\n' "$ORIG_MSG"
        printf '(Recovered onto %s from branch %s, commit %s.)\n' "$RB" "$TARGET" "$s"
      } | git -C "$PROJECT_ABS" commit -F -; then
        echo "ERROR: commit failed (likely a pre-commit hook); not bypassing." >&2
        log_apply_row "" "commit-failed" "$(( $(date +%s) - START ))"
        exit 9
      fi
    done
    NEW_SHA=$(git -C "$PROJECT_ABS" rev-parse HEAD)
    N_FILES=$(git -C "$PROJECT_ABS" diff --name-only "${MERGE_BASE}..${NEW_SHA}" 2>/dev/null | wc -l)
    ;;

  squash-merge)
    [[ "$KIND" != "branch" ]] && { echo "ERROR: squash-merge requires a branch target." >&2; exit 5; }
    TARGET_REF="refs/heads/$TARGET"
    if ! git -C "$PROJECT_ABS" merge --squash "$TARGET_REF"; then
      echo "ERROR: squash-merge conflict on $TARGET" >&2
      git -C "$PROJECT_ABS" merge --abort 2>/dev/null || true
      log_apply_row "" "conflict" "$(( $(date +%s) - START ))"
      exit 5
    fi
    if ! {
      printf 'recover content from %s (squash)\n\n' "$TARGET"
      printf 'Source branch: %s\n' "$TARGET"
      printf 'Strategy: squash-merge (project merge style: %s)\n' "$(profile_value merge_style)"
      printf 'Triage verdict: %s; evidence: %s\n' "$verdict" "$evidence"
    } | git -C "$PROJECT_ABS" commit -F -; then
      log_apply_row "" "commit-failed" "$(( $(date +%s) - START ))"
      exit 9
    fi
    NEW_SHA=$(git -C "$PROJECT_ABS" rev-parse HEAD)
    N_FILES=$(git -C "$PROJECT_ABS" diff --name-only "${NEW_SHA}^..${NEW_SHA}" 2>/dev/null | wc -l)
    ;;

  rebase-and-merge)
    [[ "$KIND" != "branch" ]] && { echo "ERROR: rebase-and-merge requires a branch target." >&2; exit 5; }
    TARGET_REF="refs/heads/$TARGET"
    # Strategy: cherry-pick the branch's commits onto the rationalization tip,
    # then leave a marker commit. We do NOT mutate the source branch (per axiom
    # 12 — concurrent agents may be working there). For a true rebase-onto-RB,
    # the user's merge-style choice would call git rebase; we keep the cherry
    # path because it leaves the source intact for backup-ref byte-equality.
    MERGE_BASE=$(git -C "$PROJECT_ABS" merge-base "$CANON_REF" "$TARGET_REF" 2>/dev/null || true)
    [[ -z "$MERGE_BASE" ]] && { echo "ERROR: cannot resolve merge-base for $TARGET" >&2; exit 5; }
    if ! git -C "$PROJECT_ABS" cherry-pick "$MERGE_BASE..$TARGET_REF" >/dev/null 2>&1; then
      echo "ERROR: rebase-and-merge cherry-pick chain failed for $TARGET" >&2
      git -C "$PROJECT_ABS" cherry-pick --abort 2>/dev/null || true
      log_apply_row "" "conflict" "$(( $(date +%s) - START ))"
      exit 5
    fi
    NEW_SHA=$(git -C "$PROJECT_ABS" rev-parse HEAD)
    N_FILES=$(git -C "$PROJECT_ABS" diff --name-only "${MERGE_BASE}..${NEW_SHA}" 2>/dev/null | wc -l)
    ;;

  dirty-worktree-only)
    [[ "$KIND" != "worktree" ]] && { echo "ERROR: dirty-worktree-only requires a worktree target." >&2; exit 5; }
    san=$(sanitize_path "$TARGET")
    wt_bundle="$BUNDLE/worktrees/$san"
    [[ -d "$wt_bundle" ]] || { echo "ERROR: bundle worktree dir missing at $wt_bundle" >&2; exit 5; }
    DIRTY_START_SHA=$(git -C "$PROJECT_ABS" rev-parse HEAD)

    if [[ ! -s "$wt_bundle/staged.diff" && ! -s "$wt_bundle/unstaged.diff" && ! -f "$wt_bundle/untracked.tar.gz" ]]; then
      echo "ERROR: dirty-worktree-only bundle has no staged, unstaged, or untracked payload for $TARGET." >&2
      echo "  Bundle path: $wt_bundle" >&2
      log_apply_row "" "dirty-payload-missing" "$(( $(date +%s) - START ))"
      exit 5
    fi

    # 1. Apply staged.diff (committed first as "staged-state" commit).
    if [[ -s "$wt_bundle/staged.diff" ]]; then
      if ! git -C "$PROJECT_ABS" apply --3way --check "$wt_bundle/staged.diff" 2>/dev/null; then
        echo "ERROR: staged.diff for $TARGET fails apply-check" >&2
        log_apply_row "" "conflict-staged" "$(( $(date +%s) - START ))"
        exit 5
      fi
      if ! git -C "$PROJECT_ABS" apply --3way --index "$wt_bundle/staged.diff"; then
        echo "ERROR: staged.diff apply failed for $TARGET" >&2
        log_apply_row "" "conflict-staged-apply" "$(( $(date +%s) - START ))"
        exit 9
      fi
      if ! git -C "$PROJECT_ABS" diff --cached --quiet; then
        {
          printf 'recover staged dirty state from worktree %s\n\n' "$TARGET"
          printf 'Source: %s/staged.diff\n' "$wt_bundle"
        } | git -C "$PROJECT_ABS" commit -F - || { log_apply_row "" "commit-failed" "$(( $(date +%s) - START ))"; exit 9; }
      fi
    fi

    # 2. Apply unstaged.diff (separate commit).
    if [[ -s "$wt_bundle/unstaged.diff" ]]; then
      if ! git -C "$PROJECT_ABS" apply --3way --check "$wt_bundle/unstaged.diff" 2>/dev/null; then
        echo "ERROR: unstaged.diff for $TARGET fails apply-check" >&2
        log_apply_row "" "conflict-unstaged" "$(( $(date +%s) - START ))"
        exit 5
      fi
      UNSTAGED_PATHS="$WORKSPACE_DIR/.apply_unstaged_paths_$$.list"
      diff_paths "$wt_bundle/unstaged.diff" | sort -u > "$UNSTAGED_PATHS"
      git -C "$PROJECT_ABS" apply --3way "$wt_bundle/unstaged.diff" || { log_apply_row "" "conflict-unstaged-apply" "$(( $(date +%s) - START ))"; exit 9; }
      # Stage and commit only the files in this worktree bundle; leave
      # concurrent dirty-tree edits out of the recovery commit.
      stage_path_list "$UNSTAGED_PATHS" || { log_apply_row "" "unstaged-stage-failed" "$(( $(date +%s) - START ))"; exit 9; }
      if ! git -C "$PROJECT_ABS" diff --cached --quiet; then
        {
          printf 'recover unstaged dirty state from worktree %s\n\n' "$TARGET"
          printf 'Source: %s/unstaged.diff\n' "$wt_bundle"
        } | git -C "$PROJECT_ABS" commit -F - || { log_apply_row "" "commit-failed" "$(( $(date +%s) - START ))"; exit 9; }
      fi
    fi

    # 3. Untracked files (separate commit). Path-collision check first.
    if [[ -f "$wt_bundle/untracked.tar.gz" ]]; then
      CONFLICT_LIST="$WORKSPACE_DIR/.apply_untracked_conflicts_$$.list"
      UNTRACKED_MANIFEST="$wt_bundle/.untracked.list"
      : > "$CONFLICT_LIST"
      if [[ ! -s "$UNTRACKED_MANIFEST" ]]; then
        echo "ERROR: untracked tarball is missing its NUL path manifest: $UNTRACKED_MANIFEST" >&2
        log_apply_row "" "untracked-manifest-missing" "$(( $(date +%s) - START ))"
        exit 5
      fi
      while IFS= read -r -d '' p; do
        [[ -z "$p" ]] && continue
        p="${p#./}"
        case "$p" in
          ""|/*|..|../*|*/..|*/../*)
            printf 'ERROR: unsafe untracked path in manifest: %q\n' "$p" >&2
	        log_apply_row "" "untracked-unsafe-member" "$(( $(date +%s) - START ))"
	        exit 5
	        ;;
	    esac
	    if path_has_symlink_parent "$p"; then
	      printf 'ERROR: untracked path would extract through an existing symlink parent: %q\n' "$p" >&2
	      log_apply_row "" "untracked-symlink-parent" "$(( $(date +%s) - START ))"
	      exit 5
	    fi
	    if [[ -e "$PROJECT_ABS/$p" || -L "$PROJECT_ABS/$p" ]]; then
	      printf '%q\n' "$p" >> "$CONFLICT_LIST"
	    fi
      done < "$UNTRACKED_MANIFEST"
      if [[ -s "$CONFLICT_LIST" ]]; then
        echo "ERROR: untracked-files copy would overwrite $(wc -l < "$CONFLICT_LIST") existing path(s)." >&2
        head -5 "$CONFLICT_LIST" | sed 's/^/  /' >&2
        log_apply_row "" "untracked-collision" "$(( $(date +%s) - START ))"
        exit 5
      fi
      if ! verify_untracked_tar_payload "$wt_bundle" "$UNTRACKED_MANIFEST"; then
        log_apply_row "" "untracked-byte-mismatch" "$(( $(date +%s) - START ))"
        exit 5
      fi
      tar --null -xzf "$wt_bundle/untracked.tar.gz" -C "$PROJECT_ABS" -T "$UNTRACKED_MANIFEST" || { log_apply_row "" "untracked-extract-failed" "$(( $(date +%s) - START ))"; exit 9; }
      stage_nul_path_list "$UNTRACKED_MANIFEST" || { log_apply_row "" "untracked-stage-failed" "$(( $(date +%s) - START ))"; exit 9; }
      if ! git -C "$PROJECT_ABS" diff --cached --quiet; then
        {
          printf 'recover untracked files from worktree %s\n\n' "$TARGET"
          printf 'Source: %s/untracked.tar.gz\n' "$wt_bundle"
        } | git -C "$PROJECT_ABS" commit -F - || { log_apply_row "" "commit-failed" "$(( $(date +%s) - START ))"; exit 9; }
      fi
    fi
    NEW_SHA=$(git -C "$PROJECT_ABS" rev-parse HEAD)
    if [[ "$NEW_SHA" == "$DIRTY_START_SHA" ]]; then
      echo "ERROR: dirty-worktree-only apply produced no recovery commit for $TARGET." >&2
      echo "  Bundle path: $wt_bundle" >&2
      log_apply_row "" "dirty-no-recovery-commit" "$(( $(date +%s) - START ))"
      exit 5
    fi
    N_FILES=$(git -C "$PROJECT_ABS" diff --name-only "${DIRTY_START_SHA}..${NEW_SHA}" 2>/dev/null | wc -l)
    ;;

  *)
    echo "ERROR: unsupported strategy '$STRATEGY' for $KIND $TARGET" >&2
    log_apply_row "" "unsupported-strategy" "$(( $(date +%s) - START ))"
    exit 8
    ;;
esac

# Run gates AFTER apply.
if ! run_gates; then
  echo "ERROR: gates failed: $GATES_STATUS"
  echo "  HEAD is on the rationalization branch with the apply still committed."
  echo "  To roll back this apply only: git -C $PROJECT_ABS reset --soft HEAD~1   # then user inspects"
  echo "  (Skill never runs --hard; this is a recovery hint for the user.)"
  log_apply_row "$NEW_SHA" "$GATES_STATUS" "$(( $(date +%s) - START ))"
  exit 4
fi

DUR=$(( $(date +%s) - START ))
log_apply_row "$NEW_SHA" "$GATES_STATUS" "$DUR"

echo
echo "✓ Applied $KIND $TARGET via $STRATEGY"
echo "  HEAD: $NEW_SHA"
echo "  Files: $N_FILES"
echo "  Gates: $GATES_STATUS"
echo "  Duration: ${DUR}s"

: "$conf" "$files_csv"
