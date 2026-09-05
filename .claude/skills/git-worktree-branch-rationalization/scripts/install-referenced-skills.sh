#!/usr/bin/env bash
# install-referenced-skills.sh — Phase 0.5: bulk-install missing helper skills.
#
# Reads <workspace>/phase0_skill_inventory.json (produced by check-skills.sh)
# and runs `jsm install <name>` for each skill marked available=false. Skips
# silently if jsm isn't installed or unauthenticated; the skill always falls
# back to inline guidance (per SKILL.md § Up-Front Confirmations).
#
# Idempotent: re-running after a successful install produces "Nothing missing".
#
# Exit codes:
#   0  installs attempted (or nothing to do, or jsm not present)
#   2  not a git work tree
#   3  inventory missing (run check-skills.sh first)
#   8  jq not available (cannot parse inventory deterministically)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: install-referenced-skills.sh <project-path>

Phase 0.5. Reads phase0_skill_inventory.json and runs \`jsm install <name>\`
for every helper skill currently marked available=false. Idempotent. Skips
without error if jsm isn't installed or unauthenticated.

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  installs attempted (or nothing to do)
  2  not a git work tree
  3  inventory missing
  8  jq not available
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
INVENTORY="$WORKSPACE_DIR/phase0_skill_inventory.json"

if [[ ! -f "$INVENTORY" ]]; then
  echo "ERROR: inventory not found at $INVENTORY" >&2
  echo "Run check-skills.sh first." >&2
  exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required to parse $INVENTORY deterministically." >&2
  echo "Install jq, or run \`jsm install <skill>\` manually for each missing skill." >&2
  exit 8
fi

JSM_AVAILABLE=$(jq -r '.jsm.available' "$INVENTORY")
JSM_AUTHED=$(jq -r '.jsm.authenticated' "$INVENTORY")

if [[ "$JSM_AVAILABLE" != "true" ]]; then
  log "jsm not installed; skipping helper-skill installation."
  log "Inline fallbacks in SKILL.md cover every missing skill."
  exit 0
fi
if [[ "$JSM_AUTHED" != "true" ]]; then
  log "jsm installed but not authenticated; run \`jsm login\` first."
  log "Inline fallbacks in SKILL.md cover every missing skill."
  exit 0
fi

# Only install helper skills this skill explicitly references. The inventory is
# mutable workspace state; do not let arbitrary extra JSON keys trigger global
# `jsm install` side effects.
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
  multi-model-triangulation
  dcg
  cass
  slb
)

MISSING=""
for skill in "${REFERENCED_SKILLS[@]}"; do
  available=$(jq -r --arg skill "$skill" 'if (.skills | has($skill)) then .skills[$skill].available else true end' "$INVENTORY")
  if [[ "$available" == "false" ]]; then
    MISSING+="$skill"$'\n'
  fi
done
MISSING=${MISSING%$'\n'}
if [[ -z "$MISSING" ]]; then
  log "Nothing missing — every referenced helper skill is present."
  exit 0
fi

log "Installing missing skills via jsm:"
attempted=0
ok=0
fail=0
while IFS= read -r skill; do
  [[ -z "$skill" ]] && continue
  attempted=$((attempted + 1))
  log "  jsm install $skill"
  if jsm install "$skill"; then
    ok=$((ok + 1))
    log "    OK  $skill"
  else
    fail=$((fail + 1))
    log "    FAIL $skill (continuing; inline fallback will be used)"
  fi
done <<< "$MISSING"

log
log "jsm-install summary: attempted=$attempted ok=$ok fail=$fail"

# Refresh the inventory so downstream phases see the new state.
log "Refreshing phase0_skill_inventory.json..."
"$SCRIPT_DIR/check-skills.sh" "$PROJECT_ABS" >/dev/null

exit 0
