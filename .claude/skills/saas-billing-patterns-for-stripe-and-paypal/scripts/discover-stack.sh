#!/usr/bin/env bash
# discover-stack.sh — Detect framework, ORM, DB, cron host, payment libs of a target SaaS project.
#
# Usage: ./scripts/discover-stack.sh <project-path>
#
# Output: <project-path>/.billing_workspace/phase0_stack.json with shape:
#   {
#     "framework": "next-app-router | next-pages-router | remix | sveltekit | nuxt | express | fastify | hono | fastapi | django | flask | rails | phoenix | unknown",
#     "orm": "drizzle | prisma | sequelize | sqlalchemy | django-orm | activerecord | ecto | none",
#     "db": "postgres | mysql | sqlite | unknown",
#     "cron_host": "vercel | cloudrun | render | fly | github-actions | self-hosted | none",
#     "email": "resend | postmark | ses | sendgrid | mailgun | none",
#     "providers": ["stripe", "paypal"],
#     "deployment": "vercel | cloudflare-pages | self-hosted | railway | render | fly | unknown",
#     "billing_surfaces": [list of billing-touching files detected]
#   }

set -euo pipefail

PROJECT="${1:-.}"
PROJECT="$(cd "$PROJECT" && pwd)"
WORKSPACE="$PROJECT/.billing_workspace"
mkdir -p "$WORKSPACE"

cd "$PROJECT"

# Helpers
has_dep() {
  local pat="$1"
  if [[ -f package.json ]]; then
    grep -q "\"$pat\"" package.json && return 0
  fi
  if [[ -f pyproject.toml ]] && grep -q "$pat" pyproject.toml; then return 0; fi
  if [[ -f requirements.txt ]] && grep -q "$pat" requirements.txt; then return 0; fi
  if [[ -f Gemfile ]] && grep -q "$pat" Gemfile; then return 0; fi
  if [[ -f mix.exs ]] && grep -q "$pat" mix.exs; then return 0; fi
  return 1
}

has_dir() { [[ -d "$1" ]]; }
has_file() { [[ -f "$1" ]]; }

# Framework
FRAMEWORK=unknown
if has_dep next; then
  if has_dir src/app || has_dir app; then FRAMEWORK=next-app-router; else FRAMEWORK=next-pages-router; fi
elif has_dep "@remix-run/"; then FRAMEWORK=remix
elif has_dep "@sveltejs/kit"; then FRAMEWORK=sveltekit
elif has_dep nuxt; then FRAMEWORK=nuxt
elif has_dep hono; then FRAMEWORK=hono
elif has_dep fastify; then FRAMEWORK=fastify
elif has_dep express; then FRAMEWORK=express
elif has_dep fastapi; then FRAMEWORK=fastapi
elif has_dep django; then FRAMEWORK=django
elif has_dep flask; then FRAMEWORK=flask
elif has_dep "rails "; then FRAMEWORK=rails
elif has_dep phoenix; then FRAMEWORK=phoenix
fi

# ORM
ORM=none
if has_dep drizzle-orm; then ORM=drizzle
elif has_dep "@prisma/client"; then ORM=prisma
elif has_dep sequelize; then ORM=sequelize
elif has_dep sqlalchemy; then ORM=sqlalchemy
elif has_dep "Django"; then ORM=django-orm
elif has_dep "activerecord"; then ORM=activerecord
elif has_dep "ecto"; then ORM=ecto
fi

# Providers
PROVIDERS=()
has_dep stripe && PROVIDERS+=('"stripe"')
{ has_dep paypal || has_dep "@paypal/checkout-server-sdk" || has_dep paypalrestsdk; } && PROVIDERS+=('"paypal"')

# Email
EMAIL=none
if has_dep resend; then EMAIL=resend
elif has_dep postmark; then EMAIL=postmark
elif has_dep "@aws-sdk/client-ses" || has_dep "boto3"; then EMAIL=ses
elif has_dep sendgrid || has_dep "@sendgrid/mail"; then EMAIL=sendgrid
elif has_dep mailgun || has_dep "mailgun-js"; then EMAIL=mailgun
fi

# DB
DB=unknown
if has_dep "@supabase/supabase-js" || has_dep psycopg || has_dep pg || has_dep "postgres "; then DB=postgres
elif has_dep mysql2 || has_dep mysql; then DB=mysql
elif has_dep "better-sqlite3" || has_dep "sqlite3"; then DB=sqlite
fi

# Cron host
CRON=none
if has_file vercel.json && grep -q '"crons"' vercel.json; then CRON=vercel
elif has_file render.yaml && grep -q '^[[:space:]]*type:[[:space:]]*cron' render.yaml; then CRON=render
elif has_file fly.toml && grep -q '\[\[cron\]\]' fly.toml; then CRON=fly
elif has_dir .github/workflows && grep -rq 'on:[[:space:]]*$\|schedule:' .github/workflows 2>/dev/null; then CRON=github-actions
elif has_file Dockerfile && grep -qi cron Dockerfile 2>/dev/null; then CRON=self-hosted
fi

# Deployment
DEPLOYMENT=unknown
if has_file vercel.json || has_file .vercel/project.json; then DEPLOYMENT=vercel
elif has_file wrangler.toml || has_file wrangler.jsonc; then DEPLOYMENT=cloudflare-pages
elif has_file railway.toml || has_file railway.json; then DEPLOYMENT=railway
elif has_file render.yaml; then DEPLOYMENT=render
elif has_file fly.toml; then DEPLOYMENT=fly
fi

# Billing surfaces — files mentioning stripe/paypal/webhook/subscription
SURFACES=()
if command -v rg >/dev/null 2>&1; then
  while IFS= read -r f; do SURFACES+=("\"$f\""); done < <(
    rg -l '\b(stripe|paypal|webhook|subscription|payment_events|recordWebhookEvent|updateSubscriptionStatus|MRR)\b' \
      --type-add 'src:*.{ts,tsx,js,jsx,py,rb,ex,exs,go,rs}' -tsrc \
      2>/dev/null | sort | head -200
  )
fi

# Emit JSON
{
  printf '{\n'
  printf '  "framework": "%s",\n' "$FRAMEWORK"
  printf '  "orm": "%s",\n' "$ORM"
  printf '  "db": "%s",\n' "$DB"
  printf '  "cron_host": "%s",\n' "$CRON"
  printf '  "email": "%s",\n' "$EMAIL"
  printf '  "providers": [%s],\n' "$(IFS=,; echo "${PROVIDERS[*]:-}")"
  printf '  "deployment": "%s",\n' "$DEPLOYMENT"
  printf '  "billing_surfaces": [%s]\n' "$(IFS=,; echo "${SURFACES[*]:-}")"
  printf '}\n'
} > "$WORKSPACE/phase0_stack.json"

# Recommended mode (heuristic)
if [[ ${#SURFACES[@]} -eq 0 ]]; then RECOMMENDED_MODE=greenfield
elif [[ ${#SURFACES[@]} -lt 5 ]]; then RECOMMENDED_MODE=add-feature
else RECOMMENDED_MODE=audit-and-fix
fi

# Human-readable summary
echo "Stack discovery for: $PROJECT"
echo "  Framework:   $FRAMEWORK"
echo "  ORM:         $ORM"
echo "  DB:          $DB"
echo "  Email:       $EMAIL"
echo "  Cron:        $CRON"
echo "  Deployment:  $DEPLOYMENT"
echo "  Providers:   ${PROVIDERS[*]:-none}"
echo "  Billing surfaces detected: ${#SURFACES[@]}"
echo
echo "Recommended mode: $RECOMMENDED_MODE"
echo
echo "Stack written to: $WORKSPACE/phase0_stack.json"
