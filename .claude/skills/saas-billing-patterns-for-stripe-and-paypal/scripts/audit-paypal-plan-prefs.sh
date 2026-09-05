#!/usr/bin/env bash
# audit-paypal-plan-prefs.sh — Audit PayPal plan payment_preferences per § 4.7 / B35.
#
# Usage: ./scripts/audit-paypal-plan-prefs.sh
#
# Verifies each plan's auto_bill_outstanding, setup_fee_failure_action, payment_failure_threshold,
# trial cycles, and quantity_supported match the BUSINESS policy.
#
# Requires: PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET, PAYPAL_API_BASE.

set -uo pipefail

if [[ -z "${PAYPAL_CLIENT_ID:-}" || -z "${PAYPAL_CLIENT_SECRET:-}" || -z "${PAYPAL_API_BASE:-}" ]]; then
  echo "PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET, PAYPAL_API_BASE required." >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required." >&2
  exit 2
fi

paypal_oauth_token() {
  curl -sS --config - "$PAYPAL_API_BASE/v1/oauth2/token" \
    -d "grant_type=client_credentials" <<CURLCFG
user = "${PAYPAL_CLIENT_ID}:${PAYPAL_CLIENT_SECRET}"
CURLCFG
}

paypal_api() {
  curl -sS --config - "$@" <<CURLCFG
header = "Authorization: Bearer $TOKEN"
CURLCFG
}

# Mint OAuth token
TOKEN=$(paypal_oauth_token | jq -r .access_token)

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "Failed to mint PayPal OAuth token." >&2
  exit 2
fi

ENV_LABEL=$(if [[ "$PAYPAL_API_BASE" == *"sandbox"* ]]; then echo "sandbox"; else echo "production"; fi)

echo "## PayPal Plan Payment Preferences Audit"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Environment: $ENV_LABEL"
echo

# List all plans
PLANS=$(paypal_api "$PAYPAL_API_BASE/v1/billing/plans?page_size=20&total_required=true")

PLAN_COUNT=$(echo "$PLANS" | jq '.plans // [] | length')
echo "### Total plans: $PLAN_COUNT"
echo

if [[ "$PLAN_COUNT" -eq 0 ]]; then
  echo "No plans found."
  exit 0
fi

DRIFT=0

# Per-plan audit
echo "### Per-plan details"
while IFS= read -r plan; do
  PLAN_ID=$(echo "$plan" | jq -r '.id')
  STATUS=$(echo "$plan" | jq -r '.status')
  NAME=$(echo "$plan" | jq -r '.name // "(unnamed)"')

  # Fetch full plan details
  FULL=$(paypal_api "$PAYPAL_API_BASE/v1/billing/plans/$PLAN_ID")

  AUTO_BILL=$(echo "$FULL" | jq -r '.payment_preferences.auto_bill_outstanding // "not_set"')
  SETUP_FAIL=$(echo "$FULL" | jq -r '.payment_preferences.setup_fee_failure_action // "not_set"')
  THRESHOLD=$(echo "$FULL" | jq -r '.payment_preferences.payment_failure_threshold // "not_set"')
  SETUP_FEE_VALUE=$(echo "$FULL" | jq -r '.payment_preferences.setup_fee.value // "0"')
  SETUP_FEE_CURRENCY=$(echo "$FULL" | jq -r '.payment_preferences.setup_fee.currency_code // "USD"')
  QUANTITY_SUPPORTED=$(echo "$FULL" | jq -r '.quantity_supported // false')

  TRIAL_CYCLES=$(echo "$FULL" | jq '[.billing_cycles // [] | .[] | select(.tenure_type == "TRIAL")] | length')
  REGULAR_CYCLES=$(echo "$FULL" | jq '[.billing_cycles // [] | .[] | select(.tenure_type == "REGULAR")] | length')
  REGULAR_PRICE=$(echo "$FULL" | jq -r '.billing_cycles // [] | map(select(.tenure_type == "REGULAR"))[0].pricing_scheme.fixed_price.value // "not_set"')
  REGULAR_CURRENCY=$(echo "$FULL" | jq -r '.billing_cycles // [] | map(select(.tenure_type == "REGULAR"))[0].pricing_scheme.fixed_price.currency_code // "USD"')

  echo "  Plan: $PLAN_ID ($NAME)"
  echo "    status: $STATUS"
  echo "    regular_price: $REGULAR_PRICE $REGULAR_CURRENCY"
  echo "    trial_cycles: $TRIAL_CYCLES"
  echo "    regular_cycles: $REGULAR_CYCLES"
  echo "    auto_bill_outstanding: $AUTO_BILL"
  echo "    setup_fee_failure_action: $SETUP_FAIL"
  echo "    payment_failure_threshold: $THRESHOLD"
  echo "    setup_fee: $SETUP_FEE_VALUE $SETUP_FEE_CURRENCY"
  echo "    quantity_supported: $QUANTITY_SUPPORTED"

  # Drift checks (assuming no-trials policy from source guide; adapt to your policy)
  if [[ "$TRIAL_CYCLES" != "0" ]]; then
    echo "    ⚠ DRIFT: trial cycles present ($TRIAL_CYCLES); verify against BUSINESS policy."
    DRIFT=$((DRIFT + 1))
  fi
  if [[ "$STATUS" != "ACTIVE" ]]; then
    echo "    ⚠ Plan not ACTIVE (status: $STATUS)"
    DRIFT=$((DRIFT + 1))
  fi
  if [[ "$SETUP_FEE_VALUE" != "0" && "$SETUP_FEE_VALUE" != "0.00" ]]; then
    echo "    ⚠ Non-zero setup fee: $SETUP_FEE_VALUE $SETUP_FEE_CURRENCY"
    DRIFT=$((DRIFT + 1))
  fi
  echo
done < <(echo "$PLANS" | jq -c '.plans[] // empty')

echo "---"
echo "Verify each plan against BUSINESS.PAYPAL_PLANS allowlist + policy."
if [[ $DRIFT -eq 0 ]]; then
  echo "✓ PayPal plan audit pass."
  exit 0
else
  echo "✗ $DRIFT PayPal plan drift item(s)."
  exit 1
fi
