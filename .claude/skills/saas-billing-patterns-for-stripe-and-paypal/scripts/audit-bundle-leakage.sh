#!/usr/bin/env bash
# audit-bundle-leakage.sh — Scan built Next.js / Remix / etc. bundle for leaked Stripe/PayPal/Supabase/cron tokens.
#
# Usage: ./scripts/audit-bundle-leakage.sh <project-path>
#
# Requires the project to be built first (npm run build / next build / etc.).

set -uo pipefail

PROJECT="${1:-.}"
PROJECT="$(cd "$PROJECT" && pwd)"

# Common build output dirs to scan
BUILD_DIRS=(
  ".next/static"
  ".next/server"
  ".vercel/output/static"
  "build"
  "dist"
  "public/_app"
  "out"
)

EXISTING_DIRS=()
for d in "${BUILD_DIRS[@]}"; do
  if [[ -d "$PROJECT/$d" ]]; then EXISTING_DIRS+=("$PROJECT/$d"); fi
done

if [[ ${#EXISTING_DIRS[@]} -eq 0 ]]; then
  echo "No build output dirs found. Run 'npm run build' (or equivalent) first." >&2
  exit 2
fi

echo "Scanning build output for leaked secrets..."
echo "Dirs: ${EXISTING_DIRS[*]}"
echo

# Patterns that signal leaked secrets in bundled / shipped output.
# Each pattern is a regex; the audit greps the build output recursively.
declare -A PATTERNS=(
  [stripe_secret_live]='sk_live_[a-zA-Z0-9]{20,}'
  [stripe_secret_test]='sk_test_[a-zA-Z0-9]{20,}'
  [stripe_restricted_live]='rk_live_[a-zA-Z0-9]{20,}'
  [stripe_restricted_test]='rk_test_[a-zA-Z0-9]{20,}'
  [stripe_webhook_secret]='whsec_[a-zA-Z0-9]{20,}'
  # PayPal client secrets are 80+ char base64-ish strings starting with E and following the
  # client-secret entropy shape. Catches leaked sandbox + live secrets via shape + length.
  [paypal_client_secret]='\bE[A-Za-z0-9_-]{55,90}\b'
  # Supabase service role keys are JWTs starting with eyJ; live anon key is also JWT but
  # is intentionally exposed so we don't alarm on JWTs of moderate length. Service role
  # JWTs are >300 chars and contain "service_role" claim base64-encoded as "c2VydmljZV9yb2xl".
  [supabase_service_role]='c2VydmljZV9yb2xl'
  [resend_api_key]='re_[a-zA-Z0-9_]{16,}'
  [openai_key]='sk-proj-[a-zA-Z0-9]{20,}|sk-[a-zA-Z0-9]{40,}'
  [anthropic_key]='sk-ant-[a-zA-Z0-9_-]{20,}'
  [aws_access_key]='AKIA[0-9A-Z]{16}'
  [generic_jwt_long]='eyJ[a-zA-Z0-9._-]{200,}'
)

VIOLATIONS=0
for label in "${!PATTERNS[@]}"; do
  pattern="${PATTERNS[$label]}"
  echo -n "Checking $label ... "
  match_count=$(grep -rEl "$pattern" "${EXISTING_DIRS[@]}" 2>/dev/null | wc -l | tr -d ' ')
  match_files=$(grep -rEl "$pattern" "${EXISTING_DIRS[@]}" 2>/dev/null | head -3 || true)
  if [[ "$match_count" -gt 0 ]]; then
    echo "VIOLATION"
    echo "  matched_files: $match_count (showing up to 3; secret values redacted)"
    echo "$match_files" | sed "s#^$PROJECT/##" | sed 's/^/  - /'
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    echo "OK"
  fi
done

echo
echo "---"
if [[ $VIOLATIONS -eq 0 ]]; then
  echo "No secrets detected in build output."
  exit 0
else
  echo "Found $VIOLATIONS secret-pattern hit(s) in build output."
  echo "REMEDIATE IMMEDIATELY: secrets bundled into client JS are publicly indexable."
  echo "  1. Identify the source: rg <secret> src/"
  echo "  2. Move from NEXT_PUBLIC_* to server-only env."
  echo "  3. Rotate the leaked secret."
  echo "  4. Re-build and re-run this audit."
  exit 1
fi
