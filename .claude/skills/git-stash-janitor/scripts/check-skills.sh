#!/usr/bin/env bash
# check-skills.sh — Detect installed helper skills + jsm state; write inventory JSON.
#
# Usage: ./scripts/check-skills.sh <workspace-dir>
#        e.g. ./scripts/check-skills.sh .stash_janitor_workspace
#
# Output: <workspace-dir>/phase0_skill_inventory.json
#
# Exits 0 even when skills/jsm are missing — it's a status check, not a gate.

set -euo pipefail

WORKSPACE_DIR="${1:-.stash_janitor_workspace}"
mkdir -p "$WORKSPACE_DIR"

# Skills referenced by this skill (from SKILL.md § Up-Front Confirmations).
REFERENCED_SKILLS=(
  operationalizing-expertise
  codebase-archaeology
  codebase-report
  agent-mail
  br
  bv
  ubs
  idea-wizard
  multi-pass-bug-hunting
  dcg
  cass
)

SKILL_SEARCH_PATHS=(
  "${CLAUDE_SKILLS_PATH:-}"
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  ".claude/skills"
)

# Detect jsm
if command -v jsm >/dev/null 2>&1; then
  JSM_AVAILABLE=true
  JSM_VERSION="$(jsm --version 2>&1 | head -1 || echo unknown)"
else
  JSM_AVAILABLE=false
  JSM_VERSION=""
fi

JSM_AUTHED=false
if [[ "$JSM_AVAILABLE" == "true" ]]; then
  # Single jsm whoami invocation; check both exit code and output content.
  if jsm_whoami_out=$(jsm whoami 2>&1) && \
     ! printf '%s' "$jsm_whoami_out" | grep -qi 'not logged in'; then
    JSM_AUTHED=true
  fi
fi

find_skill() {
  local name="$1"
  local d
  for d in "${SKILL_SEARCH_PATHS[@]}"; do
    [[ -z "$d" ]] && continue
    if [[ -f "$d/$name/SKILL.md" ]]; then
      echo "$d/$name"
      return 0
    fi
  done
  return 1
}

OUT="$WORKSPACE_DIR/phase0_skill_inventory.json"
{
  printf '{\n'
  printf '  "checked_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "jsm_available": %s,\n' "$JSM_AVAILABLE"
  printf '  "jsm_version": "%s",\n' "$JSM_VERSION"
  printf '  "jsm_authenticated": %s,\n' "$JSM_AUTHED"
  printf '  "skills": [\n'

  total="${#REFERENCED_SKILLS[@]}"
  for idx in "${!REFERENCED_SKILLS[@]}"; do
    name="${REFERENCED_SKILLS[$idx]}"
    if path=$(find_skill "$name"); then
      status=present
    else
      status=missing
      path=""
    fi
    printf '    {"name": "%s", "status": "%s", "path": "%s"}' "$name" "$status" "$path"
    if (( idx < total - 1 )); then printf ','; fi
    printf '\n'
  done
  printf '  ]\n}\n'
} > "$OUT"

# Human summary
printf '\n=== Skill inventory ===\n'
printf '%-40s  %-10s  %s\n' skill status location
printf '%-40s  %-10s  %s\n' '----------------------------------------' '----------' '-------------------------------------------'
for name in "${REFERENCED_SKILLS[@]}"; do
  if path=$(find_skill "$name"); then
    printf '%-40s  \033[32m%-10s\033[0m  %s\n' "$name" present "$path"
  else
    printf '%-40s  \033[33m%-10s\033[0m  %s\n' "$name" missing '(use jsm install or inline fallback)'
  fi
done
printf '\n'
if [[ "$JSM_AVAILABLE" == "true" ]]; then
  printf 'jsm: installed (%s); authenticated=%s\n' "$JSM_VERSION" "$JSM_AUTHED"
else
  printf 'jsm: not installed.\n'
fi
printf '\nwrote %s\n' "$OUT"
