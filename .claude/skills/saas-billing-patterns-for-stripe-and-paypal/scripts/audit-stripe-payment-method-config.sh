#!/usr/bin/env bash
# audit-stripe-payment-method-config.sh — Audit Stripe Payment Method Configuration per § 4.2a / B35.
#
# Usage: ./scripts/audit-stripe-payment-method-config.sh
#
# Verifies which payment methods are enabled (card, link, wallets, BNPL, bank debits, Stripe-hosted PayPal).
# Critical for detecting if Stripe-hosted PayPal turned ON when policy says separate provider.
#
# Requires: STRIPE_SECRET_KEY (read-only), jq.

set -uo pipefail

if [[ -z "${STRIPE_SECRET_KEY:-}" ]]; then
  echo "STRIPE_SECRET_KEY required (read-only restricted key recommended)." >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required." >&2
  exit 2
fi

stripe_api() {
  curl -sS --config - "$@" <<CURLCFG
user = "${STRIPE_SECRET_KEY}:"
CURLCFG
}

echo "## Stripe Payment Method Configuration Audit"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

CONFIGS=$(stripe_api https://api.stripe.com/v1/payment_method_configurations -G --data-urlencode "limit=10")

ACTIVE_COUNT=$(echo "$CONFIGS" | jq '[.data[] | select(.active == true)] | length')
DEFAULT_COUNT=$(echo "$CONFIGS" | jq '[.data[] | select(.is_default == true)] | length')

echo "### Configuration count"
echo "  total: $(echo "$CONFIGS" | jq '.data | length')"
echo "  active: $ACTIVE_COUNT"
echo "  default: $DEFAULT_COUNT"
echo

# Inspect each active configuration
echo "### Active configurations"
echo "$CONFIGS" | jq -c '.data[] | select(.active == true)' | while read -r config; do
  ID=$(echo "$config" | jq -r '.id')
  IS_DEFAULT=$(echo "$config" | jq -r '.is_default')
  NAME=$(echo "$config" | jq -r '.name // "(unnamed)"')

  echo "  Config: $ID (default: $IS_DEFAULT, name: $NAME)"
  for METHOD in card link apple_pay google_pay paypal klarna afterpay_clearpay affirm cashapp amazon_pay; do
    ENABLED=$(echo "$config" | jq -r ".$METHOD.display_preference.preference // \"unavailable\"")
    case "$ENABLED" in
      "on") echo "    ✓ $METHOD: ON" ;;
      "off") echo "    ✗ $METHOD: OFF" ;;
      "none") echo "    - $METHOD: not configured" ;;
      "unavailable") echo "    - $METHOD: unavailable" ;;
      *) echo "    ? $METHOD: $ENABLED" ;;
    esac
  done
  echo
done

# Specific drift checks
echo "### Drift checks"
DRIFT=0
DEFAULT_CONFIG=$(echo "$CONFIGS" | jq '.data[] | select(.is_default == true)')
PAYPAL_ON=$(echo "$DEFAULT_CONFIG" | jq -r '.paypal.display_preference.preference // "unavailable"')

if [[ "$PAYPAL_ON" == "on" ]]; then
  echo "  ⚠ Stripe-hosted PayPal is ON in default config."
  echo "    If your project uses PayPal as a SEPARATE provider, this is drift."
  echo "    If intentional, document in BUSINESS.PAYMENT_METHOD_CONFIG_RATIONALE."
  echo "  Severity: medium"
  DRIFT=$((DRIFT + 1))
else
  echo "  ✓ Stripe-hosted PayPal is $PAYPAL_ON (not ON)"
fi

if [[ $DRIFT -eq 0 ]]; then
  echo "✓ Stripe payment-method config audit pass."
  exit 0
else
  echo "✗ $DRIFT Stripe payment-method config drift item(s)."
  exit 1
fi
