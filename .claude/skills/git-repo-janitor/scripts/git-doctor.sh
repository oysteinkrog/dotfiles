#!/usr/bin/env bash
# Pre-flight repo health check. Exits non-zero on any blocking condition.
set -euo pipefail

project="${1:?usage: git-doctor.sh <project-path>}"
cd "$project"

problems=0

# Hard refusals
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $project is not inside a git work tree"
    exit 1
fi

if [[ "$(git rev-parse --is-bare-repository)" == "true" ]]; then
    echo "FAIL: bare repo (no working tree)"
    exit 1
fi

if ! git rev-parse HEAD >/dev/null 2>&1; then
    echo "FAIL: no commits"
    exit 1
fi

# Mid-operation states
git_dir=$(git rev-parse --git-dir)
if [[ -d "$git_dir/rebase-merge" ]] || [[ -d "$git_dir/rebase-apply" ]]; then
    echo "FAIL: rebase in progress; finish it first"
    exit 1
fi
if [[ -f "$git_dir/MERGE_HEAD" ]]; then
    echo "FAIL: merge in progress; finish it first"
    exit 1
fi
if [[ -f "$git_dir/CHERRY_PICK_HEAD" ]]; then
    echo "FAIL: cherry-pick in progress; finish it first"
    exit 1
fi
if [[ -f "$git_dir/REVERT_HEAD" ]]; then
    echo "FAIL: revert in progress; finish it first"
    exit 1
fi
if [[ -f "$git_dir/BISECT_LOG" ]]; then
    echo "FAIL: bisect in progress; finish it first"
    exit 1
fi

# Soft warnings
if [[ -z "$(git symbolic-ref -q HEAD)" ]]; then
    echo "WARN: detached HEAD; the recovery branch needs a base. Check out a branch first."
    problems=$((problems + 1))
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "WARN: working tree non-empty; per AGENTS.md, treat concurrent agents' changes as committed-by-self."
    # Not blocking; just warn
fi

if ! git remote -v | grep -q .; then
    echo "WARN: no remote configured; push instructions will degrade."
fi

if [[ -f "$git_dir/modules" ]] || [[ -f .gitmodules ]]; then
    echo "WARN: submodules present; their working trees are out of scope."
fi

# Git version (handles "2.43.0", "2", "2.43.0 (Apple Git-145)" forms)
git_ver=$(git --version | awk '{print $3}' | head -1)
git_major=$(echo "$git_ver" | cut -d. -f1)
git_minor=$(echo "$git_ver" | cut -d. -f2)
# Coerce non-numeric to 0 so the comparison doesn't fail under set -e
[[ "$git_major" =~ ^[0-9]+$ ]] || git_major=0
[[ "$git_minor" =~ ^[0-9]+$ ]] || git_minor=0
if (( git_major < 2 )) || (( git_major == 2 && git_minor < 20 )); then
    echo "WARN: git version $git_ver is old (<2.20); some operations may not work"
fi

# core.autocrlf
autocrlf=$(git config core.autocrlf || echo "")
if [[ "$autocrlf" == "true" ]]; then
    echo "WARN: core.autocrlf=true may cause SHA-256 drift in bundle copies. Skill will set it to false for this session."
fi

# .gitignore size
if [[ -f .gitignore ]] && [[ "$(wc -l <.gitignore)" -gt 200 ]]; then
    echo "WARN: .gitignore >200 lines; ordering bugs more likely."
fi

# LFS
if git lfs ls-files >/dev/null 2>&1 && [[ -n "$(git lfs ls-files | head -1)" ]]; then
    echo "WARN: LFS-tracked files present; bundle will smudge them."
fi

# .gitignore conflict with .repo_janitor_workspace
if [[ -f .gitignore ]] && grep -q '^\.repo_janitor_workspace' .gitignore; then
    : # already ignored
else
    if ! grep -q '^\.repo_janitor_workspace' .git/info/exclude 2>/dev/null; then
        echo "INFO: .repo_janitor_workspace/ will be added to .git/info/exclude (local-only, not committed)"
    fi
fi

if [[ "$problems" -gt 0 ]]; then
    echo ""
    echo "$problems blocking warning(s) — confirm before proceeding."
    exit 2  # warn-but-not-fail
fi

echo "git-doctor: PASS (repo is in a clean state)"
exit 0
