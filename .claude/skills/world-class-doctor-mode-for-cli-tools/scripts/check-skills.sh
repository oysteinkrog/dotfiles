#!/usr/bin/env bash
# check-skills.sh — inventory referenced helper skills and jsm state.
#
# Usage: check-skills.sh <workspace>
# Output: writes phase0_skill_inventory.json to <workspace>/.

set -euo pipefail
case "${1:-}" in
    -h|--help)
        echo "usage: check-skills.sh <workspace>" >&2
        exit 0
        ;;
esac
workspace="${1:-}"
if [ -z "$workspace" ]; then
    echo "usage: check-skills.sh <workspace>" >&2
    exit 64
fi
mkdir -p "$workspace"

# The skills referenced by world-class-doctor-mode-for-cli-tools.
referenced=(
    operationalizing-expertise
    agent-ergonomics-and-intuitiveness-maximization-for-cli-tools
    codebase-archaeology codebase-report
    multi-pass-bug-hunting multi-model-triangulation
    ubs dcg agent-mail beads-br beads-bv cass idea-wizard
    testing-fuzzing testing-metamorphic
    testing-conformance-harnesses testing-golden-artifacts
    testing-real-service-e2e-no-mocks
    cc-hooks gh-actions gh-cli
)

# Detect skill installations across all standard locations:
#   1. The user's home skills dir.
#   2. The skills directory this script itself lives in (auto-derived from
#      $0 — works regardless of where the repo is checked out, replacing the
#      hardcoded path that was specific to one developer's machine).
#   3. The current working directory's .claude/skills/ (if invoked from a
#      project that bundles its own skills).
# Plus any caller-supplied path via the CLAUDE_SKILLS_DIRS env var (colon-
# separated, like PATH) for non-standard layouts.
script_dir="$(cd "$(dirname "$0")" && pwd)"
self_skills_dir="$(cd "$script_dir/../.." && pwd)"
candidate_dirs=(
    "$HOME/.claude/skills"
    "$self_skills_dir"
    "$(pwd)/.claude/skills"
)
if [ -n "${CLAUDE_SKILLS_DIRS:-}" ]; then
    IFS=':' read -ra _extra <<< "$CLAUDE_SKILLS_DIRS"
    candidate_dirs+=("${_extra[@]}")
fi

is_installed() {
    local name="$1"
    for d in "${candidate_dirs[@]}"; do
        [ -d "$d/$name" ] && return 0
    done
    return 1
}

# jsm state.
jsm_state="absent"
if command -v jsm >/dev/null 2>&1; then
    if jsm whoami >/dev/null 2>&1; then
        jsm_state="authenticated"
    else
        jsm_state="installed_unauth"
    fi
fi

esc() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

inventory_json="["
first=1
for s in "${referenced[@]}"; do
    if is_installed "$s"; then
        installed=true
    else
        installed=false
    fi
    [ "$first" -eq 0 ] && inventory_json+=","
    first=0
    inventory_json+="{\"name\":$(esc "$s"),\"installed\":$installed}"
done
inventory_json+="]"

cat > "$workspace/phase0_skill_inventory.json" <<EOF
{
  "schema_version": "1.0",
  "jsm_state": $(esc "$jsm_state"),
  "skills": $inventory_json
}
EOF

echo "wrote $workspace/phase0_skill_inventory.json (jsm: $jsm_state)" >&2
