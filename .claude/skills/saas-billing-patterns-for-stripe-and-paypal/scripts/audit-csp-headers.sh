#!/usr/bin/env bash
# audit-csp-headers.sh — Check Content-Security-Policy headers on checkout pages for Stripe / PayPal allowance.
#
# Usage: ./scripts/audit-csp-headers.sh <base-url> [--paypal-sdk-rendered]
#
# Exits 0 if CSP is correct, 1 if drift, 2 if dependencies missing.

set -uo pipefail

BASE_URL="${1:-}"
PAYPAL_SDK=false
if [[ "${2:-}" == "--paypal-sdk-rendered" ]]; then
  PAYPAL_SDK=true
fi

if [[ -z "$BASE_URL" ]]; then
  echo "Usage: $0 <base-url> [--paypal-sdk-rendered]" >&2
  exit 2
fi

# Pages to audit (extend per project)
PAGES=(
  "/"
  "/pricing"
  "/checkout"
  "/dashboard"
)

# Required Stripe directives
declare -a REQUIRED_STRIPE=(
  "script-src.*https://js\.stripe\.com"
  "frame-src.*https://checkout\.stripe\.com"
  "frame-src.*https://js\.stripe\.com"
  "frame-src.*https://hooks\.stripe\.com"
  "connect-src.*https://api\.stripe\.com"
)

# Anti-clickjacking
declare -a SECURITY_BASELINE=(
  "frame-ancestors\s+'none'"
  "form-action\s+'self'"
)

DRIFT=0

echo "## CSP Audit"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Base URL: $BASE_URL"
echo "PayPal SDK rendered: $PAYPAL_SDK"
echo

for page in "${PAGES[@]}"; do
  echo "### $page"
  csp=$(curl -sI "${BASE_URL}${page}" 2>/dev/null | grep -i "^content-security-policy:" | head -1 | sed 's/^[Cc]ontent-[Ss]ecurity-[Pp]olicy:\s*//' | tr -d '\r')

  if [[ -z "$csp" ]]; then
    echo "  ✗ NO CSP HEADER"
    DRIFT=$((DRIFT + 1))
    echo
    continue
  fi

  # Check Stripe directives
  for directive in "${REQUIRED_STRIPE[@]}"; do
    if echo "$csp" | grep -qE "$directive"; then
      echo "  ✓ Stripe: $directive"
    else
      echo "  ✗ Stripe MISSING: $directive"
      DRIFT=$((DRIFT + 1))
    fi
  done

  # Check security baseline
  for directive in "${SECURITY_BASELINE[@]}"; do
    if echo "$csp" | grep -qE "$directive"; then
      echo "  ✓ Security: $directive"
    else
      echo "  ⚠ Security WEAK: $directive missing"
      DRIFT=$((DRIFT + 1))
    fi
  done

  # If PayPal SDK rendered
  if $PAYPAL_SDK; then
    if echo "$csp" | grep -qE "script-src.*paypal"; then
      echo "  ✓ PayPal: script-src includes paypal domain"
    else
      echo "  ✗ PayPal MISSING: PayPal SDK rendered but no PayPal CSP additions"
      DRIFT=$((DRIFT + 1))
    fi
  fi

  # Anti-patterns
  if echo "$csp" | grep -qE "'unsafe-eval'"; then
    echo "  ⚠ DANGER: 'unsafe-eval' present"
    DRIFT=$((DRIFT + 1))
  fi
  if echo "$csp" | grep -qE "script-src.*'unsafe-inline'"; then
    echo "  ⚠ DANGER: script-src 'unsafe-inline' present"
    DRIFT=$((DRIFT + 1))
  fi
  echo
done

echo "---"
if [[ $DRIFT -eq 0 ]]; then
  echo "✓ CSP audit clean."
  exit 0
else
  echo "✗ $DRIFT CSP issue(s). See B55 § 78a.5."
  exit 1
fi
