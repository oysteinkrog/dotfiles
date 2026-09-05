#!/usr/bin/env bash
# scaffold-workspace.sh — create the workspace directory tree and (optionally)
# a git worktree on `doctor-mode-pass-<N>` from the target's default branch.
#
# Usage: scaffold-workspace.sh <workspace> <target> [--worktree] [--pass=N]
#
# Exit 0 on success, 73 if the workspace can't be created.

set -euo pipefail
usage() {
    echo "usage: scaffold-workspace.sh <workspace> <target> [--worktree] [--pass=N]" >&2
}

workspace="${1:-}"
target="${2:-}"
if [ -z "$workspace" ] || [ -z "$target" ]; then
    usage
    exit 64
fi
shift 2

worktree=0
pass=1
for arg in "$@"; do
    case "$arg" in
        --worktree) worktree=1 ;;
        --pass=*) pass="${arg#--pass=}" ;;
    esac
done

if [ ! -d "$target" ]; then
    echo "error: target $target does not exist" >&2
    exit 66
fi

mkdir -p "$workspace"/{analysis/{failure_modes,repair_specs},baseline,agent_simulations} \
    || { echo "cant_create $workspace" >&2; exit 73; }

# .gitignore inside the workspace excludes pass-local scratch files.
cat > "$workspace/.gitignore" <<'EOF'
# Doctor workspace — most artifacts are committed; only ephemeral logs are not.
*.log
*.tmp
.DS_Store
__pycache__/
EOF

# Worktree creation (optional). Per AGENTS.md: never run a fresh `git init`.
# Use `git worktree add` to share the target's .git/.
if [ "$worktree" -eq 1 ]; then
    branch="doctor-mode-pass-${pass}"
    # Fallback chain: origin/HEAD (remote default) → local current branch
    # → "main" literal. The middle step is essential when there's no remote
    # set (e.g., fresh `git init` repos like the SELF-TEST tinycli) — without
    # it we'd try to branch from "main" which may not exist; older git
    # installations default to "master".
    default_branch=$(git -C "$target" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's@^origin/@@' || true)
    [ -z "$default_branch" ] && default_branch=$(git -C "$target" symbolic-ref --short HEAD 2>/dev/null || true)
    [ -z "$default_branch" ] && default_branch=main

    wt_path="$workspace/worktree"
    if [ ! -d "$wt_path" ]; then
        # If `$branch` already exists AND is checked out by another worktree
        # (common when re-running the SELF-TEST or running parallel passes),
        # `git worktree add` would fail with "already used by worktree". Try
        # the canonical attach first, then fall back to a unique branch name
        # `<branch>-<workspace-basename>` so independent passes don't collide.
        # Round-53 audit (script #17).
        if git -C "$target" rev-parse --verify "$branch" >/dev/null 2>&1; then
            # Capture git's output so we can decide whether to surface it.
            # Successful first attempt: show output (user sees worktree prep).
            # Failed first attempt: show output as context, then fall through.
            wt_attempt_log=$(git -C "$target" worktree add "$wt_path" "$branch" 2>&1) \
                && wt_attempt_rc=0 \
                || wt_attempt_rc=$?
            if [ -n "$wt_attempt_log" ]; then
                echo "$wt_attempt_log" >&2
            fi
            if [ "$wt_attempt_rc" -ne 0 ]; then
                # Branch exists but is held by another worktree. Mint a fresh
                # branch name suffixed with the workspace dir's basename so
                # parallel passes are deterministically distinct.
                # `tr -c` complements its set, which means it ALSO replaces
                # the trailing newline that `basename | ...` introduces with
                # `-`; strip the trailing `-` to keep branch names tidy.
                original_branch="$branch"
                wt_basename=$(basename "$workspace" | tr -c 'a-zA-Z0-9_-' '-')
                wt_basename="${wt_basename%-}"
                branch="${branch}-${wt_basename}"
                echo "scaffold-workspace: branch '$original_branch' attach failed (rc=$wt_attempt_rc); falling back to '$branch'" >&2
                git -C "$target" worktree add -b "$branch" "$wt_path" "$default_branch" >&2
            fi
        else
            git -C "$target" worktree add -b "$branch" "$wt_path" "$default_branch" >&2
        fi
    fi
    echo "worktree: $wt_path on $branch (from $default_branch)" >&2
fi

echo "scaffolded $workspace" >&2
echo "{\"workspace\":\"$workspace\",\"pass\":$pass,\"worktree\":$worktree}"
