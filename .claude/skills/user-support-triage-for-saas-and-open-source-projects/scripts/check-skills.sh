#!/usr/bin/env bash
# check-skills.sh — inventory referenced helper skills + jsm + subscription
#
# Usage:  check-skills.sh <workspace-dir>
#
# Writes <workspace>/skill_inventory.json. Exit 0 unless invocation or local
# dependencies are invalid.

set -euo pipefail

WS="${1:-.}"
mkdir -p "$WS"
WS="$(cd "$WS" && pwd)"
OUT="$WS/skill_inventory.json"
MISSING_MD="$WS/missing_skills.md"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to write $OUT" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_PARENT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_PROJECT=""
if [[ "$(basename "$WS")" == ".workspace" \
   && "$(basename "$(dirname "$WS")")" == "support-triage" \
   && "$(basename "$(dirname "$(dirname "$WS")")")" == ".claude" ]]; then
  TARGET_PROJECT="$(cd "$WS/../../.." && pwd)"
fi

REFERENCED=(
  codebase-archaeology
  codebase-report
  github
  admin-page-for-nextjs-sites
  user-support-ticketing-system-for-saas
  supabase
  stripe-checkout
  ga4
  saas-customer-analytics
  idea-wizard
  vercel
  e2e-testing-for-webapps
  security-audit-for-saas
  multi-model-triangulation
  cass
  agent-mail
  beads-workflow
  br
  bv
  de-slopify
)

# REQUIRED skills must be installed (or have a hard-blocking warning shown if
# install fails). de-slopify is the canonical example: every customer-facing
# reply MUST go through it before send (see references/DE-SLOPIFY-INTEGRATION.md).
# All other REFERENCED skills are accelerants with inline fallbacks.
REQUIRED_SKILLS=(
  de-slopify
)

is_required() {
  local name="$1"
  for r in "${REQUIRED_SKILLS[@]}"; do
    [[ "$r" == "$name" ]] && return 0
  done
  return 1
}

DIRS=(
  "$HOME/.claude/skills"
  "$SKILL_PARENT"
  "$PWD/.claude/skills"
  "${CODEX_HOME:-$HOME/.codex}/skills"
)
if [[ -n "$TARGET_PROJECT" ]]; then
  DIRS+=("$TARGET_PROJECT/.claude/skills")
fi

is_installed() {
  local name="$1"
  for d in "${DIRS[@]}"; do
    [[ -f "$d/$name/SKILL.md" ]] && { echo "$d/$name"; return 0; }
  done
  return 1
}

# jsm detection
jsm_available=false
jsm_authenticated=false
subscription_tier="unknown"

if command -v jsm >/dev/null 2>&1; then
  jsm_available=true
  if jsm whoami --json 2>/dev/null | jq -e '.email' >/dev/null 2>&1; then
    jsm_authenticated=true
    subscription_tier=$(jsm whoami --json 2>/dev/null | jq -r '.subscription.status // "unknown"' || echo "unknown")
  fi
fi

# Build skills array (required skills emitted with `required: true`)
skills_json="[]"
for s in "${REFERENCED[@]}"; do
  if is_required "$s"; then
    req_flag="true"
  else
    req_flag="false"
  fi
  if path=$(is_installed "$s"); then
    entry=$(jq -nc --arg n "$s" --arg p "$path" --argjson req "$req_flag" \
      '{name: $n, status: "present", path: $p, required: $req, can_install_via_jsm: false}')
  else
    entry=$(jq -nc --arg n "$s" --argjson req "$req_flag" \
      '{name: $n, status: "missing", path: null, required: $req, can_install_via_jsm: true}')
  fi
  skills_json=$(jq --argjson e "$entry" '. += [$e]' <<< "$skills_json")
done

# Emit JSON
jq -n \
  --arg t "$(date -u +%FT%TZ)" \
  --argjson av "$jsm_available" \
  --argjson au "$jsm_authenticated" \
  --arg tier "$subscription_tier" \
  --argjson skills "$skills_json" \
  '{checked_at: $t, jsm_available: $av, jsm_authenticated: $au, subscription_tier: $tier, skills: $skills}' \
  > "$OUT"

# Human summary
echo "→ wrote $OUT"
echo
printf "%-40s %-10s %s\n" "skill" "status" "location/note"
printf "%-40s %-10s %s\n" "----------------------------------------" "----------" "-------------------------------"
jq -r '.skills[] | [.name, .status, (.path // "(install via jsm)")] | @tsv' "$OUT" \
  | awk -F'\t' '{printf "%-40s %-10s %s\n", $1, $2, $3}'

echo
echo "jsm: available=$jsm_available  authenticated=$jsm_authenticated  tier=$subscription_tier"

# Missing-skills markdown
{
  echo "# Missing helper skills (logged at $(date -u +%FT%TZ))"
  echo
  jq -r '.skills[] | select(.status == "missing") | "- `" + .name + "` — referenced by user-support-triage; install via `jsm install " + .name + "` or use inline fallback"' "$OUT"
} > "$MISSING_MD"

if jq -e '.skills[] | select(.status == "missing")' "$OUT" >/dev/null 2>&1; then
  echo
  if [[ "$jsm_available" == "false" ]]; then
    cat <<EOF
jsm is NOT installed. To install (Linux/macOS):
    curl -fsSL https://jeffreys-skills.md/install.sh | bash

Or proceed without jsm — every referenced skill has an inline fallback.
EOF
  elif [[ "$jsm_authenticated" == "false" ]]; then
    cat <<EOF
jsm is installed but NOT authenticated. To authenticate:
    jsm login              # browser OAuth
    jsm auth               # API key (headless)
    jsm whoami             # verify

Then re-run this script + ./install-referenced-skills.sh.
EOF
  elif [[ "$subscription_tier" != "active" ]]; then
    cat <<EOF
jsm authenticated, but subscription tier is "$subscription_tier".
To install premium skills, subscribe at https://jeffreys-skills.md (\$20/month).
Or proceed with inline fallbacks.
EOF
  else
    echo "→ jsm ready. Run:  $(dirname "$0")/install-referenced-skills.sh \"$WS\""
  fi
fi

exit 0
