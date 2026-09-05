#!/usr/bin/env bash
# Phase 1: VERIFY-LIVE on git/lfs/etc. Captures version into project_profile.json
# Usage: verify-git-version.sh <project>
set -euo pipefail

project="${1:?usage: verify-git-version.sh <project>}"
cd "$project"
ws=".repo_janitor_workspace"
mkdir -p "$ws"
out="$ws/verification_log.md"

{
    echo "## VERIFY-LIVE: git environment — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "### git --version"
    git --version
    echo ""
    echo "### git config (relevant settings)"
    for key in core.autocrlf core.ignorecase core.precomposeunicode core.filemode \
               diff.renames merge.renameLimit gc.auto pack.deltaCacheLimit \
               protocol.file.allow rerere.enabled; do
        val=$(git config --get "$key" 2>/dev/null || echo "<unset>")
        printf "  %-30s = %s\n" "$key" "$val"
    done
    echo ""
    echo "### git lfs"
    if command -v git-lfs >/dev/null 2>&1; then
        git lfs --version
        # Pipefail can fire if `git lfs ls-files` errors out (e.g., LFS not init'd
        # in this repo). Capture stdout in two steps so the wc always runs on
        # whatever was produced and never errors.
        lfs_listing=$(git lfs ls-files 2>/dev/null || true)
        lfs_count=$(printf '%s\n' "$lfs_listing" | grep -c . || echo 0)
        echo "lfs-tracked file count: $lfs_count"
    else
        echo "git-lfs: not installed"
    fi
    echo ""
    echo "### git filter-repo"
    if command -v git-filter-repo >/dev/null 2>&1; then
        git-filter-repo --version 2>&1 | head -3
    else
        echo "git-filter-repo: not installed (will be required for harden-secret-leak mode)"
    fi
    echo ""
    echo "### shallow / partial clone status"
    # In a worktree, .git is a file pointing to the actual git dir; resolve it.
    git_dir=$(git rev-parse --git-dir 2>/dev/null || echo ".git")
    if [[ -f "$git_dir/shallow" ]]; then
        echo "shallow clone: YES ($git_dir/shallow exists)"
    else
        echo "shallow clone: no"
    fi
    git config --get-regexp '^remote\..*\.partialclonefilter$' || echo "no partial-clone filter"
    echo ""
    echo "### Submodules"
    if [[ -f .gitmodules ]]; then
        echo "submodule count: $(grep -c '^\[submodule ' .gitmodules)"
        git submodule status | head -10
    else
        echo "no submodules"
    fi
    echo ""
    echo "### OS / shell"
    uname -a
    echo "shell: $SHELL"
    echo ""
    echo "---"
    echo ""
} > "$out"

echo "verification log written to $out"

# Update project_profile.json with the version info
if [[ -f "$ws/project_profile.json" ]]; then
    git_version=$(git --version | awk '{print $3}')
    autocrlf=$(git config --get core.autocrlf 2>/dev/null || echo "")
    has_lfs=$(command -v git-lfs >/dev/null 2>&1 && echo "true" || echo "false")
    has_filter_repo=$(command -v git-filter-repo >/dev/null 2>&1 && echo "true" || echo "false")
    git_dir=$(git rev-parse --git-dir 2>/dev/null || echo ".git")
    has_shallow=$([[ -f "$git_dir/shallow" ]] && echo "true" || echo "false")

    # Append to existing profile or use jq if available
    if command -v jq >/dev/null 2>&1; then
        jq --arg v "$git_version" \
           --arg a "$autocrlf" \
           --arg lfs "$has_lfs" \
           --arg fr "$has_filter_repo" \
           --arg sh "$has_shallow" \
           '. + {git_version: $v, core_autocrlf: $a, has_lfs: $lfs, has_filter_repo: $fr, has_shallow: $sh}' \
           "$ws/project_profile.json" > "$ws/project_profile.json.tmp"
        mv "$ws/project_profile.json.tmp" "$ws/project_profile.json"
    fi
fi
