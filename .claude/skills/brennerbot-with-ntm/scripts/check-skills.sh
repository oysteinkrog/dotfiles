#!/usr/bin/env bash
# check-skills.sh — Inventory installed helper skills + jsm state
# Outputs JSON to stdout (for $WORKSPACE/.brenner_workspace/phase0_skill_inventory.json)

set -uo pipefail

WORKSPACE="${1:-.}"

# Helper skills this skill references
SKILLS=(
  ntm vibing-with-ntm agent-mail beads-br beads-bv cass cass-memory flywheel
  multi-model-triangulation operationalizing-expertise idea-wizard
  multi-pass-bug-hunting ubs open-beads-weighted-tmux-agent-sessions
  codebase-archaeology codebase-report reality-check-for-project
  modes-of-reasoning-project-analysis fixing-beads-problems sw sc
  flywheel-with-two-agents-per-repo agent-fungibility-philosophy
  dueling-idea-wizards cc-hooks
)

# Detect jsm
JSM_AVAILABLE="false"
JSM_AUTHENTICATED="false"
if command -v jsm >/dev/null 2>&1; then
  JSM_AVAILABLE="true"
  if jsm whoami 2>/dev/null | grep -q '@'; then
    JSM_AUTHENTICATED="true"
  fi
fi

# Detect each skill's installation
FALLBACKS=""

skill_installed() {
  local name="$1"
  # Check user skills dir
  if [ -d "$HOME/.claude/skills/$name" ]; then
    echo "user"
    return 0
  fi
  # Check repo-local
  if [ -d "$(dirname "$0")/../../$name" ]; then
    echo "repo"
    return 0
  fi
  # Check jsm-installed (heuristic: jsm install path varies)
  if [ "$JSM_AVAILABLE" = "true" ] && jsm list 2>/dev/null | grep -q "^$name "; then
    echo "jsm"
    return 0
  fi
  echo "missing"
  return 1
}

# Detect tool binaries (orthogonal to skill installation)
br_bin="false"
ntm_bin="false"
ubs_bin="false"
command -v br >/dev/null 2>&1 && br_bin="true"
command -v ntm >/dev/null 2>&1 && ntm_bin="true"
command -v ubs >/dev/null 2>&1 && ubs_bin="true"

# Build JSON to stdout (caller redirects to phase0_skill_inventory.json)
echo "{"
echo "  \"checked_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
echo "  \"jsm_available\": $JSM_AVAILABLE,"
echo "  \"jsm_authenticated\": $JSM_AUTHENTICATED,"
echo "  \"binaries\": {"
echo "    \"br\": $br_bin,"
echo "    \"ntm\": $ntm_bin,"
echo "    \"ubs\": $ubs_bin"
echo "  },"
echo "  \"skills\": {"
first=1
for s in "${SKILLS[@]}"; do
  via=$(skill_installed "$s")
  [ $first -eq 1 ] && first=0 || echo ","
  if [ "$via" = "missing" ]; then
    printf "    \"%s\": {\"installed\": false}" "$s"
    FALLBACKS="$FALLBACKS $s"
  else
    printf "    \"%s\": {\"installed\": true, \"via\": \"%s\"}" "$s" "$via"
  fi
done
echo ""
echo "  },"
echo "  \"fallbacks_active\": ["
first=1
for f in $FALLBACKS; do
  [ $first -eq 1 ] && first=0 || echo ","
  printf "    \"%s\"" "$f"
done
echo ""
echo "  ]"
echo "}"

# Summary to stderr (operator-visible)
echo "" >&2
echo "Skill inventory summary:" >&2
if [ -n "$FALLBACKS" ]; then
  echo "  Missing skills (using inline fallback):$FALLBACKS" >&2
  if [ "$JSM_AVAILABLE" = "true" ] && [ "$JSM_AUTHENTICATED" = "true" ]; then
    echo "  Run: ./scripts/install-referenced-skills.sh $WORKSPACE" >&2
  elif [ "$JSM_AVAILABLE" = "true" ]; then
    echo "  jsm available but not authenticated. Run: jsm login" >&2
  else
    echo "  jsm not installed. Install via: curl -fsSL https://jeffreys-skills.md/install.sh | bash" >&2
  fi
else
  echo "  All referenced skills installed." >&2
fi
