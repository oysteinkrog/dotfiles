#!/usr/bin/env bash
# check-skills.sh — Detect installed helper skills + jsm state; write inventory JSON.
#
# Usage: ./scripts/check-skills.sh <workspace-dir>
#        e.g.  ./scripts/check-skills.sh .billing_workspace
#
# Output: <workspace-dir>/phase0_skill_inventory.json with shape:
#   { "installed": [...], "missing": [...], "jsm_available": bool, "jsm_authenticated": bool }

set -euo pipefail

WORKSPACE_DIR="${1:-.billing_workspace}"
mkdir -p "$WORKSPACE_DIR"

# Skills directly routed to by this skill (canonical names from the skills registry).
# Keep narrow and in sync with SKILL.md § Up-Front Confirmations / Scope Governor.
REFERENCED_SKILLS=(
  operationalizing-expertise
  codebase-archaeology
  codebase-report
  security-audit-for-saas
  multi-pass-bug-hunting
  multi-model-triangulation
  saas-customer-analytics
  ubs
  ru-multi-repo-workflow
  agent-mail
  br
  bv
  vercel
  supabase
  stripe-checkout
  e2e-testing-for-webapps
  testing-real-service-e2e-no-mocks
  testing-real-service-e2e-no-mocks
  idea-wizard
  cc-hooks
  github
  cass
  code-review-gemini-swarm-with-ntm
  multi-agent-swarm-workflow
)

# Standard skills directories to probe. Support both Claude and Codex homes.
SKILLS_DIRS=(
  "${CODEX_HOME:-$HOME/.codex}/skills"
  "$HOME/.codex/skills"
  "$HOME/.claude/skills"
  ".claude/skills"
)

# Add jsm-managed dir if jsm is installed
if command -v jsm >/dev/null 2>&1; then
  JSM_AVAILABLE=true
  if jsm whoami >/dev/null 2>&1; then
    JSM_AUTHENTICATED=true
  else
    JSM_AUTHENTICATED=false
  fi
  # jsm-managed skills dir (best-effort)
  JSM_DIR="$(jsm config get skills_dir 2>/dev/null || echo "")"
  if [[ -n "$JSM_DIR" ]]; then
    SKILLS_DIRS+=("$JSM_DIR")
  fi
else
  JSM_AVAILABLE=false
  JSM_AUTHENTICATED=false
fi

INSTALLED=()
MISSING=()

for skill in "${REFERENCED_SKILLS[@]}"; do
  found=false
  for d in "${SKILLS_DIRS[@]}"; do
    if [[ -f "$d/$skill/SKILL.md" ]]; then
      found=true
      break
    fi
  done
  if $found; then
    INSTALLED+=("$skill")
  else
    MISSING+=("$skill")
  fi
done

# Emit JSON
{
  printf '{\n'
  printf '  "installed": ['
  for i in "${!INSTALLED[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    printf '"%s"' "${INSTALLED[$i]}"
  done
  printf '],\n'
  printf '  "missing": ['
  for i in "${!MISSING[@]}"; do
    [[ $i -gt 0 ]] && printf ', '
    printf '"%s"' "${MISSING[$i]}"
  done
  printf '],\n'
  printf '  "jsm_available": %s,\n' "$JSM_AVAILABLE"
  printf '  "jsm_authenticated": %s\n' "$JSM_AUTHENTICATED"
  printf '}\n'
} > "$WORKSPACE_DIR/phase0_skill_inventory.json"

# Human-readable summary to stdout
echo "Skill inventory:"
echo "  Installed (${#INSTALLED[@]}): ${INSTALLED[*]:-none}"
echo "  Missing  (${#MISSING[@]}):   ${MISSING[*]:-none}"
echo "  jsm available:      $JSM_AVAILABLE"
echo "  jsm authenticated:  $JSM_AUTHENTICATED"
echo
echo "Inventory written to: $WORKSPACE_DIR/phase0_skill_inventory.json"
