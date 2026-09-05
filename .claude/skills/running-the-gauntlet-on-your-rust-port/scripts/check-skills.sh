#!/usr/bin/env bash
# check-skills.sh — Inventory helper skills referenced by the gauntlet.
# Probes `jsm list` and ~/.claude/skills, ~/.codex/skills, ~/.gemini/skills.
#
# USAGE:
#   check-skills.sh <workspace-path>
#
# OUTPUT FILE: <workspace>/phase0_skill_inventory.json
# EXIT CODES:
#   0 — every required skill present in at least one harness
#   1 — at least one required skill missing
#   2 — usage error
#
# IDEMPOTENT.

set -euo pipefail

usage() {
  sed -n '2,12p' "$0"
  exit "${1:-2}"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage 0
fi

WORKSPACE="${1:-}"
[ -n "$WORKSPACE" ] || usage
mkdir -p "$WORKSPACE"

# Public helper skills referenced in references/orchestration/SKILL-BOOTSTRAP.md.
# Missing entries are advisory because the gauntlet carries inline fallbacks.
SKILLS=(
  operationalizing-expertise codebase-archaeology codebase-report
  profiling-software-performance extreme-software-optimization
  testing-metamorphic testing-fuzzing testing-conformance-harnesses
  testing-golden-artifacts testing-real-service-e2e-no-mocks
  multi-pass-bug-hunting deadlock-finder-and-fixer
  lean-formal-feedback-loop multi-agent-swarm-workflow
  agent-fungibility-philosophy flywheel idea-wizard beads-workflow
  cass agent-mail ubs dcg rch
)

declare -a SKILL_NAMES=()
declare -a SKILL_CLAUDE=()
declare -a SKILL_CODEX=()
declare -a SKILL_GEMINI=()
declare -a SKILL_JSM=()
declare -a SKILL_AVAILABLE=()

JSM_AVAILABLE=0
JSM_LIST=""
if command -v jsm >/dev/null 2>&1; then
  JSM_AVAILABLE=1
  JSM_LIST="$(jsm list 2>/dev/null || true)"
fi

probe_dir() {
  # echo 1 if skill exists at given root, 0 otherwise
  local root="$1" skill="$2"
  if [ -d "$root/$skill" ] || [ -f "$root/$skill/SKILL.md" ]; then
    echo 1
  else
    echo 0
  fi
}

MISSING=0
for s in "${SKILLS[@]}"; do
  cl="$(probe_dir "$HOME/.claude/skills" "$s")"
  cx="$(probe_dir "$HOME/.codex/skills" "$s")"
  gm="$(probe_dir "$HOME/.gemini/skills" "$s")"
  in_jsm=0
  if [ "$JSM_AVAILABLE" -eq 1 ] && grep -q "^${s}[[:space:]]\|^${s}$" <<<"$JSM_LIST"; then
    in_jsm=1
  fi
  available=0
  if [ "$cl" = "1" ] || [ "$cx" = "1" ] || [ "$gm" = "1" ]; then available=1; fi
  [ "$available" -eq 0 ] && MISSING=$((MISSING+1))
  SKILL_NAMES+=("$s")
  SKILL_CLAUDE+=("$cl")
  SKILL_CODEX+=("$cx")
  SKILL_GEMINI+=("$gm")
  SKILL_JSM+=("$in_jsm")
  SKILL_AVAILABLE+=("$available")
done

OUT="$WORKSPACE/phase0_skill_inventory.json"
{
  printf '{\n'
  printf '  "schema_version": "gauntlet.phase0_skill_inventory.v1",\n'
  printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "jsm_available": %s,\n' "$([ $JSM_AVAILABLE -eq 1 ] && echo true || echo false)"
  printf '  "missing_count": %d,\n' "$MISSING"
  printf '  "skills": [\n'
  for i in "${!SKILL_NAMES[@]}"; do
    sep=","; [ "$i" -eq $((${#SKILL_NAMES[@]}-1)) ] && sep=""
    printf '    {"name":"%s","claude":%s,"codex":%s,"gemini":%s,"jsm_installable":%s,"available":%s}%s\n' \
      "${SKILL_NAMES[$i]}" \
      "$([ ${SKILL_CLAUDE[$i]} -eq 1 ] && echo true || echo false)" \
      "$([ ${SKILL_CODEX[$i]} -eq 1 ] && echo true || echo false)" \
      "$([ ${SKILL_GEMINI[$i]} -eq 1 ] && echo true || echo false)" \
      "$([ ${SKILL_JSM[$i]} -eq 1 ] && echo true || echo false)" \
      "$([ ${SKILL_AVAILABLE[$i]} -eq 1 ] && echo true || echo false)" \
      "$sep"
  done
  printf '  ]\n'
  printf '}\n'
} > "$OUT"

echo "Wrote $OUT"
echo "Missing skills: $MISSING / ${#SKILLS[@]}"
[ "$MISSING" -eq 0 ] || exit 1
