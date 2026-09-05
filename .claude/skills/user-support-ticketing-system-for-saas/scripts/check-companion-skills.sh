#!/usr/bin/env bash
# check-companion-skills.sh — detect which companion skills are installed,
# and whether jsm (jeffreys-skills.md CLI) is available + authenticated.
#
# Writes `<workspace>/skill_inventory.json` and prints a human-readable
# table to stdout.
#
# Usage:
#   check-companion-skills.sh [<workspace-dir>]
#
# Exits 0 even when skills/jsm are missing — it's a status check, not a gate.
# `de-slopify` is required for this skill's Hard Invariant ("every customer-
# visible reply runs through /de-slopify"); the run script will treat
# de-slopify-missing as blocking. The rest are helpful, not required.

set -euo pipefail

WORKSPACE="${1:-.support_ticketing_workspace}"
mkdir -p "$WORKSPACE"
OUT="$WORKSPACE/skill_inventory.json"

# Companion skills referenced by this ticketing pipeline.
# de-slopify is the only HARD-required companion (Hard Invariant in SKILL.md).
# Everything else is helpful but has degradation paths.
REQUIRED_SKILLS=(
  de-slopify
)

OPTIONAL_SKILLS=(
  user-support-triage-for-saas-and-open-source-projects
  admin-page-for-nextjs-sites
  supabase
  stripe-checkout
  vercel
  e2e-testing-for-webapps
  testing-real-service-e2e-no-mocks
  security-audit-for-saas
  ga4
  saas-customer-analytics
)

# Search paths for installed skills (in order of precedence).
SKILL_SEARCH_PATHS=(
  "${CLAUDE_SKILLS_PATH:-}"
  "$HOME/.claude/skills"
  ".claude/skills"
)

# Detect jsm
if command -v jsm >/dev/null 2>&1; then
  JSM_AVAILABLE=true
  JSM_VERSION="$(jsm --version 2>&1 | head -1 || echo 'unknown')"
else
  JSM_AVAILABLE=false
  JSM_VERSION=""
fi

# Detect authentication & subscription tier
JSM_AUTHED=false
SUBSCRIPTION_TIER="unknown"
if [[ "$JSM_AVAILABLE" == "true" ]]; then
  if jsm_whoami=$(jsm whoami 2>&1) && ! echo "$jsm_whoami" | grep -qi 'not logged in'; then
    JSM_AUTHED=true
    if tier=$(jsm whoami --json 2>/dev/null | grep -oE '"status"[^,}]*' | head -1 | sed 's/.*"\([^"]*\)".*/\1/'); then
      [[ -n "$tier" ]] && SUBSCRIPTION_TIER="$tier"
    fi
  fi
fi

find_skill() {
  local name="$1"
  for base in "${SKILL_SEARCH_PATHS[@]}"; do
    [[ -z "$base" ]] && continue
    if [[ -f "$base/$name/SKILL.md" ]]; then
      echo "$base/$name"
      return 0
    fi
  done
  return 1
}

emit_skill_row() {
  local name="$1" requirement="$2" idx="$3" total="$4"
  local status="" path=""
  if path=$(find_skill "$name"); then
    status="present"
  else
    status="missing"
  fi
  printf '    {"name": "%s", "status": "%s", "requirement": "%s", "path": "%s"}' \
    "$name" "$status" "$requirement" "$path"
  if (( idx < total - 1 )); then
    printf ','
  fi
  printf '\n'
}

# Build the JSON body
{
  printf '{\n'
  printf '  "checked_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "jsm_available": %s,\n' "$JSM_AVAILABLE"
  printf '  "jsm_version": "%s",\n' "$JSM_VERSION"
  printf '  "jsm_authenticated": %s,\n' "$JSM_AUTHED"
  printf '  "subscription_tier": "%s",\n' "$SUBSCRIPTION_TIER"
  printf '  "skills": [\n'

  combined=("${REQUIRED_SKILLS[@]}" "${OPTIONAL_SKILLS[@]}")
  total="${#combined[@]}"
  for idx in "${!combined[@]}"; do
    name="${combined[$idx]}"
    if (( idx < ${#REQUIRED_SKILLS[@]} )); then
      requirement="required"
    else
      requirement="optional"
    fi
    emit_skill_row "$name" "$requirement" "$idx" "$total"
  done

  printf '  ]\n}\n'
} > "$OUT"

# Human-readable summary
printf '\n=== Companion-skill inventory ===\n'
printf '%-58s  %-10s  %-9s  %s\n' 'skill' 'status' 'requires' 'location'
printf '%-58s  %-10s  %-9s  %s\n' "$(printf '%.0s-' {1..58})" "----------" "---------" "----------"
required_missing=0
for name in "${REQUIRED_SKILLS[@]}"; do
  if path=$(find_skill "$name"); then
    printf '%-58s  \033[32m%-10s\033[0m  required   %s\n' "$name" 'present' "$path"
  else
    printf '%-58s  \033[31m%-10s\033[0m  required   %s\n' "$name" 'MISSING' '(blocks build)'
    required_missing=$((required_missing+1))
  fi
done
for name in "${OPTIONAL_SKILLS[@]}"; do
  if path=$(find_skill "$name"); then
    printf '%-58s  \033[32m%-10s\033[0m  optional   %s\n' "$name" 'present' "$path"
  else
    printf '%-58s  \033[33m%-10s\033[0m  optional   %s\n' "$name" 'missing' '(jsm install or inline fallback)'
  fi
done

printf '\n'
if [[ "$JSM_AVAILABLE" == "true" ]]; then
  printf 'jsm: installed (%s); authenticated=%s; subscription=%s\n' \
    "$JSM_VERSION" "$JSM_AUTHED" "$SUBSCRIPTION_TIER"
else
  printf 'jsm: not installed. See references/SKILL-INSTALLATION.md to install.\n'
fi

if (( required_missing > 0 )); then
  printf '\n\033[31m%d required companion skill(s) missing.\033[0m\n' "$required_missing"
  printf 'Run scripts/install-companion-skills.sh to install missing skills via jsm.\n'
fi

printf '\nwrote %s\n' "$OUT"
