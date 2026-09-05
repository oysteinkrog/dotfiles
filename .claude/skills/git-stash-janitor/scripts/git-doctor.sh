#!/usr/bin/env bash
# git-doctor.sh — Pre-flight repo health check for the skill.
#
# Verifies the repo is in a state where the skill can safely operate.
# Exit 0 = healthy; exit non-zero = unhealthy with reason.

set -euo pipefail

PROJECT="${1:?Usage: git-doctor.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"

echo "=== git-doctor: $PROJECT_ABS ==="

# 1. Is it a git repo at all?
if ! git -C "$PROJECT_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: not a git work tree"
  exit 1
fi
echo "OK: git work tree"

# 2. Mid-operation check
GIT_DIR=$(cd "$PROJECT_ABS" && git rev-parse --git-dir)
case "$GIT_DIR" in /*) GD="$GIT_DIR" ;; *) GD="$PROJECT_ABS/$GIT_DIR" ;; esac

mid_op=""
[[ -d "$GD/rebase-merge"  ]] && mid_op="rebase-interactive"
[[ -d "$GD/rebase-apply"  ]] && mid_op="rebase-or-am"
[[ -f "$GD/MERGE_HEAD"    ]] && mid_op="merge"
[[ -f "$GD/CHERRY_PICK_HEAD" ]] && mid_op="cherry-pick"
[[ -f "$GD/REVERT_HEAD"   ]] && mid_op="revert"
[[ -f "$GD/BISECT_LOG"    ]] && mid_op="bisect"
if [[ -n "$mid_op" ]]; then
  echo "FAIL: mid-$mid_op (finish that operation first)"
  exit 2
fi
echo "OK: not mid-rebase / merge / cherry-pick / revert / bisect"

# 3. HEAD attached
if ! git -C "$PROJECT_ABS" symbolic-ref HEAD >/dev/null 2>&1; then
  echo "WARN: detached HEAD (the skill needs a target branch for the recovery branch)"
  echo "     Either checkout a branch, or supply a recovery-branch base manually."
fi

# 4. Has any commits?
if ! git -C "$PROJECT_ABS" rev-parse HEAD >/dev/null 2>&1; then
  echo "FAIL: repo has no commits (stashes need a base)"
  exit 3
fi
echo "OK: has commits"

# 5. Check git version
git_version=$(git --version | awk '{print $3}')
git_major=$(echo "$git_version" | cut -d. -f1)
git_minor=$(echo "$git_version" | cut -d. -f2)
if [[ "$git_major" -lt 2 || ( "$git_major" -eq 2 && "$git_minor" -lt 20 ) ]]; then
  echo "WARN: git version $git_version is older than 2.20 (recommend upgrading)"
fi
echo "OK: git version $git_version"

# 6. Bare repo check
if [[ "$(git -C "$PROJECT_ABS" config core.bare 2>/dev/null)" == "true" ]]; then
  echo "FAIL: bare repository (skill needs a working tree)"
  exit 4
fi
echo "OK: not a bare repo"

# 7. Read-only filesystem check.
# Use bash's [[ -w ]] test rather than create-and-delete a marker file. Per
# AGENTS.md Rule #1, the skill never deletes files (even ones it just created).
if [[ -w "$PROJECT_ABS" ]]; then
  echo "OK: writable filesystem"
else
  echo "FAIL: filesystem appears read-only at $PROJECT_ABS"
  exit 5
fi

# 8. Stash count
stash_count=$(git -C "$PROJECT_ABS" stash list 2>/dev/null | wc -l)
echo "INFO: stash count = $stash_count"
if [[ "$stash_count" -eq 0 ]]; then
  echo "INFO: no stashes; skill will short-circuit gracefully"
fi
if [[ "$stash_count" -ge 5 ]]; then
  echo "INFO: skill is most useful with ≥5 stashes (you have $stash_count)"
fi

# 9. Disk-space estimate for bundle
estimated_kb=$((stash_count * 50))
if [[ "$estimated_kb" -gt 524288 ]]; then  # >512MB
  echo "WARN: estimated bundle size ~${estimated_kb}KB (>512MB); ensure parent dir has space"
fi

# 10. Concurrent agent indication
agent_marks=()
[[ -f "$PROJECT_ABS/.beads/.lock" ]] && agent_marks+=("beads-lock")
[[ -f "$PROJECT_ABS/.agent-mail-lock" ]] && agent_marks+=("agent-mail-lock")
if [[ ${#agent_marks[@]} -gt 0 ]]; then
  echo "INFO: concurrent-agent indicators: ${agent_marks[*]}"
fi

# 11. Pre-commit hooks
hooks=()
[[ -d "$PROJECT_ABS/.husky" ]] && hooks+=(husky)
[[ -f "$PROJECT_ABS/lefthook.yml" || -f "$PROJECT_ABS/lefthook.yaml" ]] && hooks+=(lefthook)
[[ -f "$PROJECT_ABS/.pre-commit-config.yaml" ]] && hooks+=(pre-commit)
[[ -f "$PROJECT_ABS/.git/hooks/pre-commit" && -x "$PROJECT_ABS/.git/hooks/pre-commit" ]] && hooks+=(git-hook)
if [[ ${#hooks[@]} -gt 0 ]]; then
  echo "INFO: pre-commit hooks active: ${hooks[*]} (skill will respect them; never --no-verify)"
fi

# 12. Working tree state. Exclude the skill's own workspace: by Phase 1
# (when git-doctor runs), Phase 0 has already created
# `.stash_janitor_workspace/` with multiple artifacts that show up as
# untracked. Without the exclude this count would scare the user with a
# misleadingly large "uncommitted changes" number on every run.
status_lines=$(git -C "$PROJECT_ABS" status --porcelain -- . ':(exclude).stash_janitor_workspace' 2>/dev/null | wc -l)
if [[ "$status_lines" -gt 0 ]]; then
  echo "INFO: working tree has $status_lines uncommitted changes (likely concurrent agents; skill will not disturb them)"
fi

echo
echo "=== git-doctor: HEALTHY (exit 0) ==="
exit 0
