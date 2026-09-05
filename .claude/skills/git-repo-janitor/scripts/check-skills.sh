#!/usr/bin/env bash
# Detect helper skills + jsm state; write phase0_skill_inventory.json.
# Usage: check-skills.sh <workspace>
set -euo pipefail

ws="${1:?usage: check-skills.sh <workspace>}"
mkdir -p "$ws"
out="$ws/phase0_skill_inventory.json"

# List of skills the repo-janitor uses
skills=(
    sc sw operationalizing-expertise codebase-archaeology
    codebase-report agent-mail br bv ubs
    idea-wizard multi-pass-bug-hunting dcg git-stash-janitor
    multi-model-triangulation cass
)

# Check each
{
    echo "{"
    echo '  "checked_at": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
    echo '  "skills": {'
    first=true
    for s in "${skills[@]}"; do
        [[ "$first" == "true" ]] || echo ","
        first=false
        # Heuristic: check if the skill dir exists in ~/.claude/skills/ or ../skills/
        avail="false"
        for path in "$HOME/.claude/skills/$s" "$(dirname "$0")/../../$s" "$HOME/.gemini/skills/$s"; do
            if [[ -d "$path" ]]; then
                avail="true"
                break
            fi
        done
        printf '    "%s": %s' "$s" "$avail"
    done
    echo ""
    echo "  },"
    # jsm state
    if command -v jsm >/dev/null 2>&1; then
        echo '  "jsm_available": true,'
        echo '  "jsm_authenticated": '"$(jsm auth status 2>/dev/null | grep -q 'authenticated' && echo true || echo false)"
    else
        echo '  "jsm_available": false,'
        echo '  "jsm_authenticated": false'
    fi
    echo "}"
} > "$out"

echo "skill inventory at $out"
