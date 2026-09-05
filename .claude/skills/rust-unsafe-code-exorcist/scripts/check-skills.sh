#!/usr/bin/env bash
# check-skills.sh — detect referenced helper skills + jsm state
# Usage: ./check-skills.sh <audit-dir>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Sourced through runtime SCRIPT_DIR.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:-.}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ROOT")
mkdir -p "$AUDIT_DIR"

REFERENCED_SKILLS=(
  operationalizing-expertise
  codebase-archaeology codebase-report extreme-software-optimization
  multi-pass-bug-hunting multi-model-triangulation idea-wizard
  beads-workflow beads-br beads-bv
  ubs agent-mail cass
  testing-real-service-e2e-no-mocks testing-metamorphic
  testing-fuzzing testing-conformance-harnesses
  deadlock-finder-and-fixer
)

SKILLS_DIR_CLAUDE="${HOME}/.claude/skills"
SKILLS_DIR_CODEX="${HOME}/.codex/skills"
SKILLS_DIR_PROJECT="$PROJECT_ROOT/.claude/skills"
SKILL_DIRS=("$SKILLS_DIR_CLAUDE" "$SKILLS_DIR_CODEX" "$SKILLS_DIR_PROJECT")

JSM_INSTALLED=false
JSM_AUTHED=false
if command -v jsm >/dev/null 2>&1; then
  JSM_INSTALLED=true
  if jsm whoami >/dev/null 2>&1; then
    JSM_AUTHED=true
  fi
fi

INVENTORY="$AUDIT_DIR/phase0_skill_inventory.json"

json_string() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

skill_location() {
  local skill="$1"
  local dir
  for dir in "${SKILL_DIRS[@]}"; do
    if [ -d "$dir/$skill" ]; then
      printf '%s\n' "$dir/$skill"
      return 0
    fi
  done
  return 1
}

MISSING=()
PRESENT=()
for skill in "${REFERENCED_SKILLS[@]}"; do
  if skill_location "$skill" >/dev/null; then
    PRESENT+=("$skill")
  else
    MISSING+=("$skill")
  fi
done

n=${#REFERENCED_SKILLS[@]}
i=0
{
  printf '{\n'
  printf '  "jsm_installed": %s,\n' "$JSM_INSTALLED"
  printf '  "jsm_authenticated": %s,\n' "$JSM_AUTHED"
  printf '  "skill_search_dirs": [\n'
  for idx in "${!SKILL_DIRS[@]}"; do
    comma=,
    [ "$idx" -eq "$((${#SKILL_DIRS[@]} - 1))" ] && comma=""
    printf '    %s%s\n' "$(json_string "${SKILL_DIRS[$idx]}")" "$comma"
  done
  printf '  ],\n'
  printf '  "skills": [\n'
  for skill in "${REFERENCED_SKILLS[@]}"; do
    i=$((i+1))
    if location=$(skill_location "$skill"); then
      state=installed
      location_json=$(json_string "$location")
    else
      state=missing
      location_json=null
    fi
    comma=,
    [ "$i" -eq "$n" ] && comma=""
    printf '    {"name": %s, "state": "%s", "location": %s}%s\n' "$(json_string "$skill")" "$state" "$location_json" "$comma"
  done
  printf '  ],\n'
  printf '  "present_count": %d,\n' "${#PRESENT[@]}"
  printf '  "missing_count": %d\n' "${#MISSING[@]}"
  printf '}\n'
} > "$INVENTORY"

echo "Skill inventory written to $INVENTORY"
echo "Searched skill dirs:"
for dir in "${SKILL_DIRS[@]}"; do echo "  - $dir"; done
echo "Present: ${#PRESENT[@]} / $n"
echo "Missing: ${#MISSING[@]} / $n"

if [ ${#MISSING[@]} -gt 0 ]; then
  echo
  echo "Missing skills:"
  for s in "${MISSING[@]}"; do echo "  - $s"; done
  echo
  if [ "$JSM_INSTALLED" = "true" ] && [ "$JSM_AUTHED" = "true" ]; then
    echo "jsm is installed and authenticated."
    echo "To install all missing: ./install-referenced-skills.sh $AUDIT_DIR"
  else
    echo "jsm is not installed/authenticated. Inline fallbacks in references/methodology/SKILL-FALLBACKS.md."
  fi
fi
