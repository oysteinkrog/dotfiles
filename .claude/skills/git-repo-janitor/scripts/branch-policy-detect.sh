#!/usr/bin/env bash
# Phase 1: detect per-repo branch policy (main only, main:master mirror, master only, etc.).
# Outputs JSON to stdout for inclusion in project_profile.json.
# Usage: branch-policy-detect.sh <project>
set -euo pipefail

project="${1:?usage: branch-policy-detect.sh <project>}"
cd "$project"

# Detect primary branch
primary=""
if remote_head=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null); then
    primary="${remote_head##*/}"
fi
if [[ -z "$primary" ]]; then
    primary=$(git config init.defaultBranch 2>/dev/null || echo "")
fi
if [[ -z "$primary" ]]; then
    for cand in main master develop trunk default; do
        if git show-ref --verify --quiet "refs/heads/$cand"; then
            primary="$cand"
            break
        fi
    done
fi
[[ -z "$primary" ]] && primary="main"

# Detect synonym branches (branches that mirror primary)
synonyms=()
for cand in master develop release main; do
    [[ "$cand" == "$primary" ]] && continue

    # Check if this branch exists locally or on origin
    if git show-ref --verify --quiet "refs/heads/$cand" || git show-ref --verify --quiet "refs/remotes/origin/$cand"; then
        # Compare HEAD of this branch to primary; if same SHA, it's a mirror
        local_sha=$(git rev-parse "refs/heads/$cand" 2>/dev/null || echo "")
        primary_sha=$(git rev-parse "refs/heads/$primary" 2>/dev/null || echo "")
        if [[ -n "$local_sha" ]] && [[ "$local_sha" == "$primary_sha" ]]; then
            synonyms+=("$cand")
        else
            # Compare via origin
            origin_local=$(git rev-parse "refs/remotes/origin/$cand" 2>/dev/null || echo "")
            origin_primary=$(git rev-parse "refs/remotes/origin/$primary" 2>/dev/null || echo "")
            if [[ -n "$origin_local" ]] && [[ "$origin_local" == "$origin_primary" ]]; then
                synonyms+=("$cand")
            fi
        fi
    fi
done

# Detect remote URL
origin_url=$(git config --get remote.origin.url 2>/dev/null || echo "")

# Detect if it's a third-party fork (heuristic: origin URL doesn't match user's GitHub user).
# Use `.login // empty` so jq emits nothing on null (rather than the literal string "null").
user=""
if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    user=$(gh api user 2>/dev/null | jq -r '.login // empty' 2>/dev/null || echo "")
fi
third_party_fork=false
if [[ -n "$user" ]] && [[ -n "$origin_url" ]]; then
    if [[ "$origin_url" == *"github.com"* ]] && [[ "$origin_url" != *"$user"* ]]; then
        third_party_fork=true
    fi
fi

# Build JSON
emit_json() {
    echo "{"
    echo "  \"primary_branch\": \"$primary\","
    if [[ ${#synonyms[@]} -gt 0 ]]; then
        printf '  "branch_synonyms": ['
        first=true
        for s in "${synonyms[@]}"; do
            [[ "$first" == "false" ]] && printf ", "
            first=false
            printf '"%s"' "$s"
        done
        echo "],"
    else
        echo "  \"branch_synonyms\": [],"
    fi
    echo "  \"origin_url\": \"$origin_url\","
    echo "  \"third_party_fork\": $third_party_fork"
    echo "}"
}

# Always emit to stdout
emit_json

# If project_profile.json exists in the workspace, merge in-place via jq.
ws=".repo_janitor_workspace"
if [[ -f "$ws/project_profile.json" ]] && command -v jq >/dev/null 2>&1; then
    syn_json="[]"
    if [[ ${#synonyms[@]} -gt 0 ]]; then
        syn_json=$(printf '%s\n' "${synonyms[@]}" | jq -R . | jq -s .)
    fi
    jq --arg primary "$primary" \
       --argjson synonyms "$syn_json" \
       --arg origin_url "$origin_url" \
       --argjson tpf "$third_party_fork" \
       '. + {primary_branch: $primary, branch_synonyms: $synonyms, origin_url: $origin_url, third_party_fork: $tpf}' \
       "$ws/project_profile.json" > "$ws/project_profile.json.tmp"
    mv "$ws/project_profile.json.tmp" "$ws/project_profile.json"
fi
