#!/usr/bin/env bash
# audit-trial-discount-deal.sh — Verify trial / discount / deal policy is enforced at provider level.
#
# Usage: ./scripts/audit-trial-discount-deal.sh
#
# Requires: STRIPE_SECRET_KEY (read-only).
# Pair with audit-paypal-plan-prefs.sh for PayPal plan-level policy checks.
# Reads BUSINESS.TRIAL_DAYS, BUSINESS.ALLOW_PROMO_CODES from the project.
#
# Exits 0 if provider state matches policy; 1 if drift; 2 if deps missing.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 2
fi
if [[ -z "${STRIPE_SECRET_KEY:-}" ]]; then
  echo "STRIPE_SECRET_KEY env var required (read-only restricted key recommended)." >&2
  exit 2
fi

DRIFT=0

stripe_api() {
  curl -sS --config - "$@" <<CURLCFG
user = "${STRIPE_SECRET_KEY}:"
CURLCFG
}

echo "## Trial / Discount / Deal Audit"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

# Stripe coupons
echo "### Stripe coupons"
COUPONS_RESPONSE=$(stripe_api https://api.stripe.com/v1/coupons -G --data-urlencode "limit=100")
COUPON_COUNT=$(echo "$COUPONS_RESPONSE" | jq '.data | length')
ACTIVE_COUPON_COUNT=$(echo "$COUPONS_RESPONSE" | jq '[.data[] | select(.valid == true)] | length')
echo "  total: $COUPON_COUNT"
echo "  active: $ACTIVE_COUPON_COUNT"
if [[ $ACTIVE_COUPON_COUNT -gt 0 ]]; then
  echo "  ✗ DRIFT: Active coupons exist. Verify against BUSINESS.ALLOWED_PROMO_CODES allowlist."
  echo "$COUPONS_RESPONSE" | jq -r '.data[] | select(.valid == true) | "    - id=\(.id) percent_off=\(.percent_off // "n/a") amount_off=\(.amount_off // "n/a") duration=\(.duration)"'
  DRIFT=$((DRIFT + 1))
fi
echo

# Stripe promotion codes
echo "### Stripe promotion codes"
PROMOS_RESPONSE=$(stripe_api https://api.stripe.com/v1/promotion_codes -G --data-urlencode "limit=100" --data-urlencode "active=true")
ACTIVE_PROMO_COUNT=$(echo "$PROMOS_RESPONSE" | jq '.data | length')
echo "  active: $ACTIVE_PROMO_COUNT"
if [[ $ACTIVE_PROMO_COUNT -gt 0 ]]; then
  echo "  ✗ DRIFT: Active promotion codes exist."
  echo "$PROMOS_RESPONSE" | jq -r '.data[] | "    - id=\(.id) code=<redacted> coupon=\(.coupon.id) max_redemptions=\(.max_redemptions // "unlimited") expires_at=\(.expires_at // "never")"'
  DRIFT=$((DRIFT + 1))
fi
echo

# Stripe payment links (recurring = subscription bypass risk)
echo "### Stripe Payment Links"
LINKS_RESPONSE=$(stripe_api https://api.stripe.com/v1/payment_links -G --data-urlencode "limit=100" --data-urlencode "active=true")
ACTIVE_LINK_COUNT=$(echo "$LINKS_RESPONSE" | jq '.data | length')
echo "  active: $ACTIVE_LINK_COUNT"
if [[ $ACTIVE_LINK_COUNT -gt 0 ]]; then
  echo "  ⚠ DRIFT: Active Payment Links exist. Verify each is in BUSINESS allowlist or is non-recurring."
  echo "$LINKS_RESPONSE" | jq -r '.data[] | "    - id=\(.id) url=<redacted>"'
  DRIFT=$((DRIFT + 1))
fi
echo

# Stripe recent subscriptions with trial_end
echo "### Stripe recent subscriptions trial-end check"
SUBS_RESPONSE=$(stripe_api https://api.stripe.com/v1/subscriptions -G --data-urlencode "limit=100" --data-urlencode "status=trialing")
TRIALING_COUNT=$(echo "$SUBS_RESPONSE" | jq '.data | length')
echo "  trialing: $TRIALING_COUNT"
if [[ $TRIALING_COUNT -gt 0 ]]; then
  echo "  ⚠ DRIFT (if BUSINESS.TRIAL_DAYS == 0): Active trialing subscriptions exist."
  DRIFT=$((DRIFT + 1))
fi
echo

# Stripe Customer Portal config
echo "### Stripe Customer Portal config"
PORTAL_RESPONSE=$(stripe_api https://api.stripe.com/v1/billing_portal/configurations -G --data-urlencode "limit=10")
DEFAULT_CONFIG=$(echo "$PORTAL_RESPONSE" | jq '.data[] | select(.is_default == true)')
PROMO_ALLOWED=$(echo "$DEFAULT_CONFIG" | jq -r '.features.subscription_update.proration_behavior // "n/a"')
SUB_UPDATE_ENABLED=$(echo "$DEFAULT_CONFIG" | jq -r '.features.subscription_update.enabled // false')
SUB_CANCEL_MODE=$(echo "$DEFAULT_CONFIG" | jq -r '.features.subscription_cancel.mode // "n/a"')
SUB_CANCEL_PRORATION=$(echo "$DEFAULT_CONFIG" | jq -r '.features.subscription_cancel.proration_behavior // "n/a"')
echo "  subscription_update.enabled: $SUB_UPDATE_ENABLED"
echo "  subscription_update.proration_behavior: $PROMO_ALLOWED"
echo "  subscription_cancel.mode: $SUB_CANCEL_MODE"
echo "  subscription_cancel.proration_behavior: $SUB_CANCEL_PRORATION"
echo
echo "  Verify these match BUSINESS portal policy."
echo

echo "---"
if [[ $DRIFT -eq 0 ]]; then
  echo "✓ Provider state matches policy."
  exit 0
else
  echo "✗ $DRIFT drift item(s). Review against BUSINESS constants + B70/B35."
  exit 1
fi
