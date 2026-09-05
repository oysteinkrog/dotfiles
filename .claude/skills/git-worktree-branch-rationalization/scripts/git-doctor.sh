#!/usr/bin/env bash
# git-doctor.sh — Phase 0: pre-flight repo health check.
#
# Verifies the project is in a state where the rationalization skill can
# safely operate. Per SKILL.md § Decision Tree:
#   REFUSE if  : not a git work tree, bare repo, no commits on canonical,
#                mid-rebase / mid-merge / mid-cherry-pick / mid-revert /
#                mid-bisect on the active worktree, very old git (<2.20),
#                unwritable filesystem.
#   WARN if    : detached HEAD on the active worktree, non-empty working tree
#                (concurrent agents per AGENTS.md), no remote, branches with
#                [gone] upstream, locked worktrees on stale paths.
#
# Output: per-check status lines + an overall verdict line.
#
# Exit codes:
#   0  PASS (run may proceed)
#   1  REFUSE — not a git work tree
#   2  REFUSE — mid-operation (rebase/merge/cherry-pick/revert/bisect)
#   3  REFUSE — repo has no commits
#   4  REFUSE — bare repository
#   5  REFUSE — unwritable filesystem
#   6  REFUSE — git too old (<2.20)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: git-doctor.sh <project-path>

Phase 0 pre-flight health check. Refuses on any of:
  - not a git work tree
  - bare repository
  - mid-rebase / mid-merge / mid-cherry-pick / mid-revert / mid-bisect on the
    active worktree
  - no commits on canonical (HEAD does not resolve)
  - git version older than 2.20
  - unwritable filesystem at the work tree

Soft-warns on detached HEAD, non-empty working tree (concurrent agents per
AGENTS.md), missing remote, [gone]-upstream branches, locked worktrees on
stale paths.

Env:
  WORKSPACE   Workspace dir override (used to scope the working-tree-state
              probe so the skill's own artifacts don't masquerade as drift).

Exit codes:
  0  PASS
  1  not a git work tree
  2  mid-operation
  3  no commits
  4  bare repository
  5  unwritable filesystem
  6  git too old
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
# Don't exit on resolve_project_root failure — we want to print a structured
# refusal line first.
BARE_REPO=0
if PROJECT_ABS="$(resolve_project_root "$PROJECT" 2>/dev/null)"; then
  :
else
  PROJECT_ABS=""
  if input_abs="$(cd "$PROJECT" 2>/dev/null && pwd)" \
     && [[ "$(git -C "$input_abs" rev-parse --is-bare-repository 2>/dev/null || echo false)" == "true" ]]; then
    PROJECT_ABS="$input_abs"
    BARE_REPO=1
  fi
fi

REFUSALS=0
WARNINGS=0
record_refuse() { echo "REFUSE: $*"; REFUSALS=$((REFUSALS + 1)); }
record_pass()   { echo "OK:     $*"; }
record_warn()   { echo "WARN:   $*"; WARNINGS=$((WARNINGS + 1)); }

echo "=== git-doctor: ${PROJECT_ABS:-$PROJECT} ==="

# 1. Is it a git work tree at all? Check bare repositories first so a real
# bare repo gets the documented refusal instead of being flattened into "not a
# work tree" by resolve_project_root.
if [[ "$BARE_REPO" -eq 1 ]] || [[ "$(git -C "$PROJECT_ABS" config core.bare 2>/dev/null)" == "true" ]]; then
  record_refuse "bare repository (skill needs a working tree)"
  echo "=== VERDICT: REFUSE ==="
  exit 4
fi
if [[ -z "$PROJECT_ABS" ]] || ! git -C "$PROJECT_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  record_refuse "not a git work tree at $PROJECT"
  echo "=== VERDICT: REFUSE ==="
  exit 1
fi
record_pass "git work tree"
record_pass "not a bare repository"

# 3. Mid-operation check — every active-worktree mid-state aborts the run.
# Resolve the git-dir relative to the active worktree (not the common dir),
# because per-worktree state lives under .git/worktrees/<id>/ for linked
# worktrees and would be missed by a pure --git-common-dir lookup.
GIT_DIR=$(cd "$PROJECT_ABS" && git rev-parse --git-dir 2>/dev/null || echo .git)
case "$GIT_DIR" in
  /*) GD="$GIT_DIR" ;;
  *)  GD="$PROJECT_ABS/$GIT_DIR" ;;
esac

mid_op=""
[[ -d "$GD/rebase-merge"      ]] && mid_op="rebase-interactive"
[[ -d "$GD/rebase-apply"      ]] && mid_op="rebase-or-am"
[[ -f "$GD/MERGE_HEAD"        ]] && mid_op="merge"
[[ -f "$GD/CHERRY_PICK_HEAD"  ]] && mid_op="cherry-pick"
[[ -f "$GD/REVERT_HEAD"       ]] && mid_op="revert"
[[ -f "$GD/BISECT_LOG"        ]] && mid_op="bisect"
if [[ -n "$mid_op" ]]; then
  record_refuse "mid-$mid_op on active worktree (finish that operation first)"
  echo "=== VERDICT: REFUSE ==="
  exit 2
fi
record_pass "not mid-rebase / merge / cherry-pick / revert / bisect"

# 4. Has any commits?
if ! git -C "$PROJECT_ABS" rev-parse HEAD >/dev/null 2>&1; then
  record_refuse "repo has no commits (canonical is empty)"
  echo "=== VERDICT: REFUSE ==="
  exit 3
fi
record_pass "has commits"

# 5. Git version >= 2.20 (worktree semantics changed before that).
git_version=$(git --version | awk '{print $3}')
git_major=$(echo "$git_version" | cut -d. -f1)
git_minor=$(echo "$git_version" | cut -d. -f2)
if [[ "$git_major" -lt 2 ]] || { [[ "$git_major" -eq 2 ]] && [[ "$git_minor" -lt 20 ]]; }; then
  record_refuse "git version $git_version < 2.20 (worktree semantics changed in 2.20)"
  echo "=== VERDICT: REFUSE ==="
  exit 6
fi
record_pass "git version $git_version (>= 2.20)"

# 6. Writable filesystem (use [[ -w ]]; never create-and-delete a probe file —
# Rule 1).
if [[ -w "$PROJECT_ABS" ]]; then
  record_pass "writable filesystem"
else
  record_refuse "filesystem appears read-only at $PROJECT_ABS"
  echo "=== VERDICT: REFUSE ==="
  exit 5
fi

# === Soft warnings beyond this point ===

# 7. Detached HEAD on active worktree.
if ! git -C "$PROJECT_ABS" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
  record_warn "detached HEAD on active worktree (skill needs a base for the rationalization branch)"
fi

# 8. Working tree state. Exclude the skill's own workspace when present so
# we don't scare the user with a misleadingly large drift number on every run.
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
WS_BASENAME=$(basename "$WORKSPACE_DIR")
status_lines=$(git -C "$PROJECT_ABS" status --porcelain --untracked-files=all -- . ":(exclude)$WS_BASENAME" 2>/dev/null | wc -l)
if [[ "$status_lines" -gt 0 ]]; then
  record_warn "working tree has $status_lines uncommitted changes (likely concurrent agents per AGENTS.md; skill will not disturb them)"
fi

# 9. Remote.
if ! git -C "$PROJECT_ABS" remote -v 2>/dev/null | grep -q .; then
  record_warn "no remote configured (push instructions in handoff will degrade)"
fi

# 10. Branches with [gone] upstream tracking. These have unique commits even
# though the upstream is gone — Smell B15.
GONE_COUNT=$(git -C "$PROJECT_ABS" branch -vv 2>/dev/null | grep -cE '\[[^]]*: gone\]' || true)
if [[ "$GONE_COUNT" -gt 0 ]]; then
  record_warn "$GONE_COUNT branch(es) with [gone] upstream — triage normally; do NOT auto-prune"
fi

# 11. Locked worktrees on stale paths.
LOCKED_STALE=0
declare -a LOCKED_PATHS=()
while IFS= read -r line; do
  case "$line" in
    worktree\ *) curr_path="${line#worktree }" ;;
    locked|locked\ *)
      [[ -n "${curr_path:-}" && ! -d "$curr_path" ]] && {
        LOCKED_STALE=$((LOCKED_STALE + 1))
        LOCKED_PATHS+=("$curr_path")
      }
      ;;
  esac
done < <(git -C "$PROJECT_ABS" worktree list --porcelain 2>/dev/null)
if [[ "$LOCKED_STALE" -gt 0 ]]; then
  record_warn "$LOCKED_STALE locked worktree(s) on stale (deleted) paths:"
  for p in "${LOCKED_PATHS[@]}"; do
    echo "          $p"
  done
fi

# 12. Worktree count + branch count for sanity.
WT_COUNT=$(git -C "$PROJECT_ABS" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)
BR_COUNT=$(git -C "$PROJECT_ABS" for-each-ref refs/heads 2>/dev/null | wc -l)
echo "INFO:   $WT_COUNT worktree(s) (incl. main), $BR_COUNT local branch(es)"

# 13. Pre-commit hook indicators (informational only).
hooks=()
[[ -d "$PROJECT_ABS/.husky"                                ]] && hooks+=(husky)
[[ -f "$PROJECT_ABS/lefthook.yml" || -f "$PROJECT_ABS/lefthook.yaml" ]] && hooks+=(lefthook)
[[ -f "$PROJECT_ABS/.pre-commit-config.yaml"               ]] && hooks+=(pre-commit)
[[ -f "$PROJECT_ABS/.git/hooks/pre-commit" && -x "$PROJECT_ABS/.git/hooks/pre-commit" ]] && hooks+=(git-hook)
if [[ ${#hooks[@]} -gt 0 ]]; then
  echo "INFO:   pre-commit hooks active: ${hooks[*]} (skill respects them; never --no-verify)"
fi

echo
if [[ "$REFUSALS" -eq 0 ]]; then
  if [[ "$WARNINGS" -gt 0 ]]; then
    echo "=== VERDICT: PASS WITH WARNINGS ($WARNINGS) ==="
  else
    echo "=== VERDICT: PASS ==="
  fi
  exit 0
fi

# Defensive: if we got here with refusals and no earlier exit, fail.
echo "=== VERDICT: REFUSE ($REFUSALS refusals) ==="
exit 1
