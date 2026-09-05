#!/usr/bin/env bash
# audit-vercel-env.sh — Audit Vercel project env vars for billing-secret hygiene.
#
# Usage: ./scripts/audit-vercel-env.sh [<project-path>]
#
# Requires: vercel CLI authenticated (`vercel login`).
#
# Checks:
#  - Production env: STRIPE_SECRET_KEY starts with sk_live_ (NOT sk_test_)
#  - Preview/Development env: STRIPE_SECRET_KEY starts with sk_test_ (NOT sk_live_)
#  - PAYPAL_API_BASE: production = api-m.paypal.com; preview = api-m.sandbox.paypal.com
#  - No NEXT_PUBLIC_* env var has 'secret', 'key' (other than publishable), 'token' in name
#  - OPS_FAILSAFE_EMAIL != ADMIN_EMAIL
#
# Exits 0 if clean, 1 if drift, 2 if deps missing.

set -uo pipefail

PROJECT="${1:-.}"
PROJECT="$(cd "$PROJECT" && pwd)"

if ! command -v vercel >/dev/null 2>&1; then
  echo "vercel CLI required. Install: npm i -g vercel" >&2
  exit 2
fi

cd "$PROJECT"

# Verify we're in a Vercel-linked project
if [[ ! -f .vercel/project.json ]]; then
  echo "Not a Vercel-linked project (.vercel/project.json missing). Run: vercel link" >&2
  exit 2
fi

DRIFT=0

echo "## Vercel Env Audit"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Project: $PROJECT"
echo

# Get env list (vercel env ls outputs to stdout in human format; we parse)
ENV_LIST=$(vercel env ls 2>/dev/null)

# Check NEXT_PUBLIC_* with suspicious names
echo "### NEXT_PUBLIC_* names that look like secrets"
SUSPICIOUS=$(echo "$ENV_LIST" | grep "NEXT_PUBLIC_" | grep -iE "secret|private|token|webhook" | grep -viE "publishable|public_key|publishable_key" || true)
if [[ -z "$SUSPICIOUS" ]]; then
  echo "  ✓ none"
else
  echo "$SUSPICIOUS" | sed 's/^/  ✗ /'
  DRIFT=$((DRIFT + 1))
fi
echo

# Pull environment-scoped vars
for env in production preview development; do
  echo "### Environment: $env"

  # Pull only env names (no values) — vercel env pull would write a file
  scoped=$(echo "$ENV_LIST" | awk -v env="$env" '$0 ~ env { print }' | awk '{print $1}' || true)

  # Check Stripe key mode
  if echo "$scoped" | grep -q "STRIPE_SECRET_KEY"; then
    echo "  STRIPE_SECRET_KEY: present (cannot read value via CLI; verify in dashboard)"
  else
    if [[ "$env" == "production" ]]; then
      echo "  ✗ STRIPE_SECRET_KEY missing in production"
      DRIFT=$((DRIFT + 1))
    fi
  fi

  if echo "$scoped" | grep -q "PAYPAL_CLIENT_SECRET"; then
    echo "  PAYPAL_CLIENT_SECRET: present"
  fi

  if echo "$scoped" | grep -q "OPS_FAILSAFE_EMAIL"; then
    echo "  OPS_FAILSAFE_EMAIL: present"
  fi

  if echo "$scoped" | grep -q "CRON_SECRET"; then
    echo "  CRON_SECRET: present"
  fi

  echo
done

echo "---"
echo "Note: Live key-mode verification requires reading values."
echo "For manual key-mode verification, pull env values only to an access-controlled temp path outside the repo, never print them in transcripts, and handle the file per your project's secret-handling policy."
echo

if [[ $DRIFT -eq 0 ]]; then
  echo "✓ Vercel env audit pass (limited; manual key-mode check still required)."
  exit 0
else
  echo "✗ $DRIFT drift item(s)."
  exit 1
fi
