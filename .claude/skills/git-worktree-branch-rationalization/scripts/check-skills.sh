#!/usr/bin/env bash
# check-skills.sh — Phase 0.5: detect helper-skill availability and jsm state.
#
# Probes ~/.claude/skills/, ~/.codex/skills/, $CLAUDE_SKILLS_PATH, and the
# project-local .claude/skills/ for each helper skill referenced in SKILL.md
# § Up-Front Confirmations. Writes the result to
# <workspace>/phase0_skill_inventory.json so downstream phases (and the
# install-referenced-skills.sh helper) can act on it without re-probing.
#
# This is a status check, not a gate: missing skills never block the run —
# the skill always falls back to inline guidance.
#
# Output:
#   <workspace>/phase0_skill_inventory.json
#
# Exit codes:
#   0  inventory written (always, even when skills/jsm are absent)
#   2  not a git work tree (project-path malformed)
#   8  cannot write workspace

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: check-skills.sh <project-path>

Phase 0.5 of the git-worktree-branch-rationalization skill. Detects which
helper skills (/agent-mail, /beads-br, /beads-bv, /ubs, /idea-wizard,
/multi-pass-bug-hunting, /multi-model-triangulation, /dcg, /cass, /slb,
/codebase-archaeology, /codebase-report,
/operationalizing-expertise) are installed, plus jsm presence and auth state.
Writes phase0_skill_inventory.json. Never blocks; missing skills fall back to
inline guidance.

Env:
  WORKSPACE             Workspace dir override.
  CLAUDE_SKILLS_PATH    Extra search path searched first.

Exit codes:
  0  inventory written
  2  not a git work tree
  8  workspace not writable
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"

if ! mkdir -p "$WORKSPACE_DIR" 2>/dev/null; then
  echo "ERROR: cannot create workspace at $WORKSPACE_DIR" >&2
  exit 8
fi
if [[ ! -w "$WORKSPACE_DIR" ]]; then
  echo "ERROR: workspace at $WORKSPACE_DIR is not writable" >&2
  exit 8
fi

# Skills referenced by SKILL.md § Up-Front Confirmations + Skill Bootstrap.
REFERENCED_SKILLS=(
  operationalizing-expertise
  codebase-archaeology
  codebase-report
  agent-mail
  beads-br
  beads-bv
  ubs
  idea-wizard
  multi-pass-bug-hunting
  multi-model-triangulation
  dcg
  cass
  slb
)

# Search order: env override first (so a workspace pinned to a custom skills
# dir wins), then global, then project-local. We keep the order in the inventory
# JSON's source field via an explicit per-skill probe.
SKILL_SEARCH_PATHS=(
  "${CLAUDE_SKILLS_PATH:-}"
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$PROJECT_ABS/.claude/skills"
)

# Detect jsm.
JSM_AVAILABLE=false
JSM_VERSION=""
JSM_AUTHED=false
if command -v jsm >/dev/null 2>&1; then
  JSM_AVAILABLE=true
  JSM_VERSION="$(jsm --version 2>&1 | head -1 || echo unknown)"
  # `jsm whoami` exits 0 when authed, non-zero (or prints "not logged in")
  # otherwise. Combine both signals for robustness.
  if jsm_whoami_out=$(jsm whoami 2>&1) \
     && ! printf '%s' "$jsm_whoami_out" | grep -qi 'not logged in'; then
    JSM_AUTHED=true
  fi
fi

# Returns: <status>|<source>|<path>
#   status ∈ available | missing
#   source ∈ env | global | codex | project-local | project-relative | missing
find_skill() {
  local name="$1"
  local d
  for d in "${SKILL_SEARCH_PATHS[@]}"; do
    [[ -z "$d" ]] && continue
    if [[ -f "$d/$name/SKILL.md" ]]; then
      local label
      case "$d" in
        "${CLAUDE_SKILLS_PATH:-__none__}") label="env" ;;
        "$HOME/.claude/skills")            label="global" ;;
        "$HOME/.codex/skills")             label="codex" ;;
        "$PROJECT_ABS/.claude/skills")     label="project" ;;
        *)                                  label="other" ;;
      esac
      printf 'available|%s|%s/%s\n' "$label" "$d" "$name"
      return 0
    fi
  done
  printf 'missing|missing|\n'
  return 0
}

OUT="$WORKSPACE_DIR/phase0_skill_inventory.json"

# Probe first, then sign the observed results. Signing only the skill names and
# search paths would miss installs/removals that happen after the first run.
declare -A SKILL_PROBES=()
for name in "${REFERENCED_SKILLS[@]}"; do
  SKILL_PROBES["$name"]="$(find_skill "$name")"
done

SIGNATURE_INPUT=$(
  printf '%s\n' "$JSM_AVAILABLE" "$JSM_AUTHED" "$JSM_VERSION"
  printf '%s\n' "${SKILL_SEARCH_PATHS[@]}"
  for name in "${REFERENCED_SKILLS[@]}"; do
    printf '%s|%s\n' "$name" "${SKILL_PROBES[$name]}"
  done
)
if command -v sha1sum >/dev/null 2>&1; then
  SIGNATURE=$(printf '%s' "$SIGNATURE_INPUT" | sha1sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  SIGNATURE=$(printf '%s' "$SIGNATURE_INPUT" | shasum -a 1 | awk '{print $1}')
else
  SIGNATURE=$(printf '%s' "$SIGNATURE_INPUT" | cksum | awk '{printf "%08x%04x", $1, $2}')
fi

if [[ -f "$OUT" ]] && command -v jq >/dev/null 2>&1; then
  prior_sig=$(jq -r '.signature // ""' "$OUT" 2>/dev/null || echo "")
  if [[ "$prior_sig" == "$SIGNATURE" ]]; then
    log "phase0_skill_inventory.json signature matches; skipping re-probe."
    echo "wrote $OUT (resumed; signature $SIGNATURE)"
    exit 0
  fi
fi

# Build the JSON. We avoid sed/awk-based mutation (per AGENTS.md) and write
# the whole file fresh with explicit fields.
{
  printf '{\n'
  printf '  "signature": '; json_string "$SIGNATURE"; printf ',\n'
  printf '  "checked_at": '; json_string "$(date -u +%FT%TZ)"; printf ',\n'
  printf '  "project": '; json_string "$PROJECT_ABS"; printf ',\n'
  printf '  "jsm": {\n'
  printf '    "available": %s,\n' "$JSM_AVAILABLE"
  printf '    "version": '; json_string "$JSM_VERSION"; printf ',\n'
  printf '    "authenticated": %s\n' "$JSM_AUTHED"
  printf '  },\n'
  printf '  "skills": {\n'

  total="${#REFERENCED_SKILLS[@]}"
  for idx in "${!REFERENCED_SKILLS[@]}"; do
    name="${REFERENCED_SKILLS[$idx]}"
    probe="${SKILL_PROBES[$name]}"
    status=${probe%%|*}
    rest=${probe#*|}
    source=${rest%%|*}
    path=${rest#*|}
    available=true
    [[ "$status" == "missing" ]] && available=false
    printf '    '
    json_string "$name"
    printf ': {"available": %s, "source": ' "$available"
    json_string "$source"
    printf ', "path": '
    json_string "$path"
    printf '}'
    if (( idx < total - 1 )); then printf ','; fi
    printf '\n'
  done
  printf '  }\n'
  printf '}\n'
} > "$OUT"

# Human-readable summary
printf '\n=== Helper-skill inventory ===\n'
printf '%-36s  %-10s  %s\n' skill status location
printf '%-36s  %-10s  %s\n' '------------------------------------' '----------' '----------------------------------------'
for name in "${REFERENCED_SKILLS[@]}"; do
  probe="${SKILL_PROBES[$name]}"
  status=${probe%%|*}
  path=${probe##*|}
  case "$status" in
    available) printf '%-36s  %-10s  %s\n' "$name" present "${path:-unknown}" ;;
    *)         printf '%-36s  %-10s  %s\n' "$name" missing "(jsm install or inline fallback)" ;;
  esac
done
printf '\n'
if [[ "$JSM_AVAILABLE" == "true" ]]; then
  printf 'jsm: installed (%s); authenticated=%s\n' "$JSM_VERSION" "$JSM_AUTHED"
else
  printf 'jsm: not installed; missing skills will use inline fallback only.\n'
fi
printf '\nwrote %s\n' "$OUT"
exit 0
