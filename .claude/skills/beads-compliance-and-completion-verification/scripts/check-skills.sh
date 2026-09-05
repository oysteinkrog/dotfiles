#!/usr/bin/env bash
# check-skills.sh — Detect referenced helper skills and offer to install missing ones via jsm.
#
# Usage:
#   check-skills.sh <audit-dir>
#
# Output (stdout):
#   JSON inventory of which referenced skills are present, missing, or unavailable.
#   Also written to <audit-dir>/passes/<latest>/skill_inventory.json.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

AUDIT_DIR="${1:?audit dir required}"
LATEST_PASS="$(ls -1d "$AUDIT_DIR/passes"/*/ 2>/dev/null | sort | tail -1)"

REFERENCED_SKILLS=(
  br
  bv
  beads-workflow
  fixing-beads-problems
  mock-code-finder
  reality-check-for-project
  multi-pass-bug-hunting
  testing-conformance-harnesses
  testing-fuzzing
  testing-golden-artifacts
  testing-metamorphic
  testing-perfect-e2e-integration-tests-with-logging-and-no-mocks
  testing-real-service-e2e-no-mocks
  codebase-archaeology
  comprehensive-codebase-report
  cass
  agent-mail
  multi-agent-swarm-workflow
  operationalizing-expertise
  sw
  sc
)

# Search standard skill locations. The skill's own dir is included so co-located
# helper skills are discovered even when the global skills tree is empty.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_PARENT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_PATHS=(
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "${CLAUDE_SKILLS_DIR:-}"
  "$SKILLS_PARENT"
  ".claude/skills"
)
# Drop empty entries and duplicates while preserving order.
declare -A SEEN
RESOLVED_PATHS=()
for sp in "${SKILL_PATHS[@]}"; do
  [ -z "$sp" ] && continue
  [ -d "$sp" ] || continue
  abs="$(cd "$sp" && pwd)"
  [ -n "${SEEN[$abs]:-}" ] && continue
  SEEN[$abs]=1
  RESOLVED_PATHS+=("$abs")
done
SKILL_PATHS=("${RESOLVED_PATHS[@]}")

INVENTORY="[]"
for skill in "${REFERENCED_SKILLS[@]}"; do
  found_path=""
  for sp in "${SKILL_PATHS[@]}"; do
    if [ -d "$sp/$skill" ] && [ -f "$sp/$skill/SKILL.md" ]; then
      found_path="$sp/$skill"
      break
    fi
  done
  if [ -n "$found_path" ]; then
    status="present"
  else
    status="missing"
  fi
  INVENTORY="$(printf '%s' "$INVENTORY" | jq --arg s "$skill" --arg st "$status" --arg p "$found_path" \
    '. + [{name: $s, status: $st, path: ($p | select(. != "") )}]')"
done

# Check jsm availability.
JSM_PRESENT=false
JSM_AUTHED=false
if command -v jsm >/dev/null 2>&1; then
  JSM_PRESENT=true
  if jsm whoami >/dev/null 2>&1; then
    JSM_AUTHED=true
  fi
fi

OUT="$(jq -n \
  --argjson inventory "$INVENTORY" \
  --argjson jsm_present "$JSM_PRESENT" \
  --argjson jsm_authed "$JSM_AUTHED" \
  '{
    inventory: $inventory,
    jsm_present: $jsm_present,
    jsm_authenticated: $jsm_authed,
    missing: ($inventory | map(select(.status == "missing") | .name)),
    install_hint: (if $jsm_authed then "jsm install <name>" else "install jsm first: curl -fsSL https://jeffreys-skills.md/install.sh | bash; then jsm login" end)
  }')"

echo "$OUT"

if [ -n "$LATEST_PASS" ]; then
  echo "$OUT" > "${LATEST_PASS}skill_inventory.json"
fi

# Print human summary to stderr.
MISSING_COUNT=$(printf '%s' "$OUT" | jq '.missing | length')
if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "Missing $MISSING_COUNT helper skills:" >&2
  printf '%s' "$OUT" | jq -r '.missing[]' | sed 's/^/  - /' >&2
  if [ "$JSM_AUTHED" = "true" ]; then
    echo "" >&2
    echo "Install with: jsm install <name>" >&2
  else
    echo "" >&2
    echo "To install: curl -fsSL https://jeffreys-skills.md/install.sh | bash && jsm login" >&2
  fi
else
  echo "All referenced skills present." >&2
fi
