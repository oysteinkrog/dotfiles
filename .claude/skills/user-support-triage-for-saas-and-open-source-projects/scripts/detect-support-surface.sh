#!/usr/bin/env bash
# detect-support-surface.sh — classify a project's support surface and write
# <project>/.claude/support-triage/_detection.json
#
# Usage:  detect-support-surface.sh /path/to/project

set -euo pipefail

PROJECT="${1:-}"
if [[ -z "$PROJECT" ]] || [[ ! -d "$PROJECT" ]]; then
  echo "usage: detect-support-surface.sh <project-path>" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to emit _detection.json" >&2
  exit 2
fi

PROJECT="$(cd "$PROJECT" && pwd)"
cd "$PROJECT"

OUT_DIR="$PROJECT/.claude/support-triage"
mkdir -p "$OUT_DIR"
DET="$OUT_DIR/_detection.json"

surfaces=()
channel_hints=()
support_archetypes=()
language="unknown"
framework="unknown"
auth="unknown"
provider="null"
email="null"
base_url="null"
github_repo="null"
github_visibility="unknown"

append_surface() {
  local candidate="$1"
  local existing
  for existing in "${surfaces[@]}"; do
    [[ "$existing" == "$candidate" ]] && return 0
  done
  surfaces+=("$candidate")
}

append_channel_hint() {
  local candidate="$1"
  local existing
  for existing in "${channel_hints[@]}"; do
    [[ "$existing" == "$candidate" ]] && return 0
  done
  channel_hints+=("$candidate")
}

append_archetype() {
  local candidate="$1"
  local existing
  for existing in "${support_archetypes[@]}"; do
    [[ "$existing" == "$candidate" ]] && return 0
  done
  support_archetypes+=("$candidate")
}

# Language / framework signals
[[ -f Cargo.toml ]] && language="rust"
[[ -f go.mod ]] && language="go"
[[ -f pyproject.toml || -f setup.py || -f requirements.txt ]] && language="py"
[[ -f Gemfile ]] && language="rb"
[[ -f composer.json ]] && language="php"
if [[ -f package.json ]]; then
  language="ts"
  if grep -q '"next"' package.json 2>/dev/null; then framework="nextjs"; fi
  if grep -q '"@sveltejs/kit"' package.json 2>/dev/null; then framework="sveltekit"; fi
fi
[[ "$language" == "rb" && -f config.ru ]] && framework="rails"
[[ "$language" == "py" ]] && grep -qrlE "django|fastapi|flask" pyproject.toml requirements.txt 2>/dev/null && framework="$(grep -hoE 'django|fastapi|flask' pyproject.toml requirements.txt 2>/dev/null | head -1)"

# Custom DB ticketing
if grep -rqlE "supportTickets|support_tickets|supportMessages|support_messages" \
   src/ db/ schema.ts schema.sql schema/ 2>/dev/null \
   || [[ -d src/app/api/admin/support || -d src/app/admin/support || -d app/api/admin/support || -d app/admin/support ]]; then
  append_surface "saas-custom"
fi

# Third-party providers
detect_provider() {
  for f in .env .env.example .env.production .env.local; do
    [[ -f "$f" ]] || continue
    if grep -qE "^ZENDESK_(SUBDOMAIN|API_TOKEN|EMAIL)" "$f"; then provider="zendesk"; break; fi
    if grep -qE "^INTERCOM_ACCESS_TOKEN" "$f"; then provider="intercom"; break; fi
    if grep -qE "^HELPSCOUT_(APP_ID|APP_SECRET)" "$f"; then provider="helpscout"; break; fi
    if grep -qE "^FRESHDESK_(DOMAIN|API_KEY)" "$f"; then provider="freshdesk"; break; fi
    if grep -qE "^CRISP_(IDENTIFIER|KEY|WEBSITE_ID)" "$f"; then provider="crisp"; break; fi
    if grep -qE "^PLAIN_API_KEY" "$f"; then provider="plain"; break; fi
    if grep -qE "^LINEAR_API_KEY" "$f"; then provider="linear"; break; fi
    if grep -qE "^FRONT_API_TOKEN" "$f"; then provider="front"; break; fi
    if grep -qE "^GORGIAS_(DOMAIN|API_KEY)" "$f"; then provider="gorgias"; break; fi
    if grep -qE "^HUBSPOT_(ACCESS_TOKEN|API_KEY)" "$f"; then provider="hubspot"; break; fi
    if grep -qE "^SALESFORCE_(CLIENT_ID|CLIENT_SECRET|INSTANCE_URL)" "$f"; then provider="salesforce"; break; fi
    if grep -qE "^JSM_(SITE_URL|EMAIL|API_TOKEN|PROJECT_KEY)" "$f"; then provider="jira-service-management"; break; fi
    if grep -qE "^ZOHO_DESK_(ORG_ID|CLIENT_ID|CLIENT_SECRET|REFRESH_TOKEN)" "$f"; then provider="zoho-desk"; break; fi
    if grep -qE "^PYLON_API_KEY" "$f"; then provider="pylon"; break; fi
  done
}
detect_provider
[[ "$provider" != "null" ]] && append_surface "saas-third-party"

# Email provider
detect_email() {
  for f in .env .env.example .env.production .env.local; do
    [[ -f "$f" ]] || continue
    if grep -qE "^RESEND_API_KEY" "$f"; then email="resend"; return; fi
    if grep -qE "^SENDGRID_API_KEY" "$f"; then email="sendgrid"; return; fi
    if grep -qE "^POSTMARK_(SERVER|API)_TOKEN" "$f"; then email="postmark"; return; fi
    if grep -qE "^SES_(ACCESS_KEY|REGION)" "$f"; then email="ses"; return; fi
    if grep -qE "^MAILGUN_(API_KEY|DOMAIN)" "$f"; then email="mailgun"; return; fi
    if grep -qE "^SMTP_HOST" "$f"; then email="smtp"; return; fi
  done
}
detect_email
if [[ "$email" != "null" ]]; then
  append_channel_hint "outbound-email-provider:$email"
fi

# Manual/community/support-channel hints. These are intentionally broad: they do
# not prove automation is available, but they prevent hidden manual channels
# from disappearing during onboarding.
if grep -rhE "^(SUPPORT_EMAIL|HELP_EMAIL|CONTACT_EMAIL)=" .env .env.example .env.production .env.local 2>/dev/null | grep -q . \
   || grep -rqliE "support@|help@|contact@|mailto:" README* docs .github package.json 2>/dev/null; then
  append_surface "email"
  append_channel_hint "email-or-contact-address"
fi
if grep -rqliE "discord|slack|discourse|forum|community|reddit|mastodon|twitter|x\\.com|linkedin|hacker news|news\\.ycombinator" README* docs .github package.json 2>/dev/null; then
  append_surface "community-manual"
  append_channel_hint "community-or-social"
fi
if grep -rqliE "shopify|woocommerce|app store|google play|marketplace|etsy|amazon seller|gorgias" README* docs .github package.json 2>/dev/null; then
  append_surface "marketplace-or-app-store"
  append_archetype "commerce-or-marketplace"
fi
if grep -rqliE "internal tool|internal users|employees|ops queue|operations team|backoffice" README* docs .github package.json 2>/dev/null; then
  append_surface "internal-ops"
  append_archetype "internal-tool"
fi
if grep -rqliE "hipaa|healthcare|medical|financial|finra|ferpa|student|minor|soc ?2|iso ?27001|regulated" README* docs .github package.json 2>/dev/null; then
  append_archetype "regulated-or-high-assurance"
fi

detect_base_url() {
  local f line value
  for f in .env.local .env .env.production .env.example; do
    [[ -f "$f" ]] || continue
    line=$(grep -hE "^(NEXT_PUBLIC_URL|PUBLIC_URL|APP_URL|SITE_URL|VERCEL_PROJECT_PRODUCTION_URL)=" "$f" 2>/dev/null | head -1 || true)
    [[ -n "$line" ]] || continue
    value="${line#*=}"
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    [[ -n "$value" ]] || continue
    if [[ "$value" != http://* && "$value" != https://* ]]; then
      value="https://$value"
    fi
    base_url="${value%/}"
    return
  done
}
detect_base_url

# Auth strategy (rough — Next.js focused; expand as needed)
if [[ -f package.json ]]; then
  if grep -q '"@supabase/supabase-js"' package.json 2>/dev/null; then auth="supabase"; fi
  if grep -q '"@clerk' package.json 2>/dev/null; then auth="clerk"; fi
  if grep -q '"next-auth"' package.json 2>/dev/null; then auth="nextauth"; fi
fi

# GitHub
if command -v gh >/dev/null 2>&1; then
  gh_info=$(gh repo view --json nameWithOwner,visibility -q '.nameWithOwner + "|" + .visibility' 2>/dev/null || echo "null|unknown")
  github_repo="${gh_info%%|*}"
  github_visibility="${gh_info#*|}"
fi
if [[ "$github_repo" != "null" && "$github_repo" != "" ]]; then
  if [[ "$github_visibility" == "PUBLIC" || -f LICENSE || -d .github/ISSUE_TEMPLATE ]]; then
    append_surface "github-only"
  fi
fi

# None-yet: SaaS but no ticketing
if [[ "$framework" == "nextjs" || "$framework" == "rails" || "$framework" == "django" ]] \
   && [[ ${#surfaces[@]} -eq 0 || ( ${#surfaces[@]} -eq 1 && "${surfaces[0]}" == "github-only" ) ]]; then
  surfaces+=("none-yet")
fi

# Emit JSON. Use jq for escaping; project paths and env values can contain
# spaces, quotes, or backslashes.
if [[ ${#surfaces[@]} -eq 0 ]]; then
  surfaces_json="[]"
else
  surfaces_json="$(printf '%s\n' "${surfaces[@]}" | jq -R . | jq -s .)"
fi
if [[ ${#channel_hints[@]} -eq 0 ]]; then
  channel_hints_json="[]"
else
  channel_hints_json="$(printf '%s\n' "${channel_hints[@]}" | jq -R . | jq -s .)"
fi
if [[ ${#support_archetypes[@]} -eq 0 ]]; then
  support_archetypes_json="[]"
else
  support_archetypes_json="$(printf '%s\n' "${support_archetypes[@]}" | jq -R . | jq -s .)"
fi
jq -n \
  --arg project_path "$PROJECT" \
  --argjson surfaces "$surfaces_json" \
  --argjson channel_hints "$channel_hints_json" \
  --argjson support_archetypes "$support_archetypes_json" \
  --arg framework "$framework" \
  --arg language "$language" \
  --arg auth "$auth" \
  --arg provider "$provider" \
  --arg email "$email" \
  --arg base_url "$base_url" \
  --arg github_repo "$github_repo" \
  --arg github_visibility "$github_visibility" \
  --arg detected_at "$(date -u +%FT%TZ)" \
  '{
    project_path: $project_path,
    surfaces: $surfaces,
    channel_hints: $channel_hints,
    support_archetypes: $support_archetypes,
    framework: $framework,
    language: $language,
    auth_strategy: $auth,
    third_party_provider: (if $provider == "null" then null else $provider end),
    outbound_email: (if $email == "null" then null else $email end),
    base_url: (if $base_url == "null" then null else $base_url end),
    github_repo: (if $github_repo == "null" then null else $github_repo end),
    github_visibility: $github_visibility,
    missing_skills: [],
    detected_at: $detected_at
  }' > "$DET"

echo "→ wrote $DET"
cat "$DET"
