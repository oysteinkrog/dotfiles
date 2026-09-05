#!/usr/bin/env bash
# provider-diagnostics.sh — Read-only Stripe + PayPal diagnostics with mandatory redaction.
#
# Usage: ./scripts/provider-diagnostics.sh [--provider stripe|paypal|both] [--full-scan]
#
# This is the operational equivalent of B35 / B120 audit. Outputs counts-only
# evidence to stdout (and optionally to .billing_workspace/provider_audit_log.md).
#
# Requires:
#   STRIPE_SECRET_KEY (read-only restricted key strongly recommended)
#   PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET (read-only)
#   PAYPAL_API_BASE  (e.g., https://api-m.paypal.com or sandbox)
#
# SECURITY: This script NEVER prints secrets, OAuth tokens, full URLs with sensitive
# query params, raw customer rows, or full webhook event bodies. If you observe
# such output, that's a bug — file an issue.

set -uo pipefail

PROVIDER="${1:-both}"
if [[ "$PROVIDER" == "--provider" ]]; then PROVIDER="${2:-both}"; shift 2; fi
FULL_SCAN=false
if [[ "${1:-}" == "--full-scan" || "${2:-}" == "--full-scan" ]]; then FULL_SCAN=true; fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 2
fi

CHECKED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

stripe_api() {
  curl -sS --config - "$@" <<CURLCFG
user = "${STRIPE_SECRET_KEY}:"
CURLCFG
}

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

echo "{"
echo "  \"checked_at\": \"$CHECKED_AT\","
echo "  \"environment\": \"production\","
echo "  \"scope\": \"read_only_provider_diagnostics\","
echo "  \"redaction\": \"counts_only_no_customer_rows_no_tokens_no_urls\","
echo "  \"full_scan\": $FULL_SCAN"

# ============================================================
# Stripe
# ============================================================
if [[ "$PROVIDER" == "stripe" || "$PROVIDER" == "both" ]]; then
  echo ","
  if [[ -z "${STRIPE_SECRET_KEY:-}" ]]; then
    echo "  \"stripe_error\": \"STRIPE_SECRET_KEY not set\""
  else
    echo "  \"stripe\": {"

    # Account state
    ACCT=$(stripe_api https://api.stripe.com/v1/account)
    KEY_MODE=$(if [[ "$STRIPE_SECRET_KEY" == sk_live_* ]]; then echo "live"; elif [[ "$STRIPE_SECRET_KEY" == sk_test_* ]]; then echo "test"; else echo "restricted_or_unknown"; fi)
    echo "    \"account\": {"
    echo "      \"key_mode\": \"$KEY_MODE\","
    echo "      \"country\": $(echo "$ACCT" | jq '.country // "null"'),"
    echo "      \"default_currency\": $(echo "$ACCT" | jq '.default_currency // "null"'),"
    echo "      \"charges_enabled\": $(echo "$ACCT" | jq '.charges_enabled // false'),"
    echo "      \"payouts_enabled\": $(echo "$ACCT" | jq '.payouts_enabled // false')"
    echo "    },"

    # Webhook endpoints
    WHE=$(stripe_api https://api.stripe.com/v1/webhook_endpoints -G --data-urlencode "limit=10")
    EP_COUNT=$(echo "$WHE" | jq '.data | length')
    EP_API_VERSIONS=$(echo "$WHE" | jq '[.data[] | .api_version] | unique')
    EP_STATUSES=$(echo "$WHE" | jq '[.data[] | .status] | unique')
    echo "    \"webhook_endpoints\": {"
    echo "      \"count\": $EP_COUNT,"
    echo "      \"api_versions\": $EP_API_VERSIONS,"
    echo "      \"statuses\": $EP_STATUSES,"
    echo "      \"enabled_events_total_count\": $(echo "$WHE" | jq '[.data[] | select(.status == "enabled") | .enabled_events[]] | length')"
    echo "    },"

    # Recent events sample
    EVENTS=$(stripe_api https://api.stripe.com/v1/events -G --data-urlencode "limit=100")
    echo "    \"events_recent_sample\": {"
    echo "      \"count\": $(echo "$EVENTS" | jq '.data | length'),"
    echo "      \"type_counts\": $(echo "$EVENTS" | jq '[.data[] | .type] | group_by(.) | map({key: .[0], value: length}) | from_entries'),"
    echo "      \"api_version_counts\": $(echo "$EVENTS" | jq '[.data[] | .api_version] | group_by(.) | map({key: .[0], value: length}) | from_entries'),"
    echo "      \"livemode_counts\": $(echo "$EVENTS" | jq '[.data[] | .livemode] | group_by(.) | map({key: tostring, value: length}) | from_entries')"
    echo "    },"

    # Recent checkout sessions
    CKO=$(stripe_api https://api.stripe.com/v1/checkout/sessions -G --data-urlencode "limit=100")
    echo "    \"checkout_sessions_sample\": {"
    echo "      \"count\": $(echo "$CKO" | jq '.data | length'),"
    echo "      \"mode_counts\": $(echo "$CKO" | jq '[.data[] | .mode] | group_by(.) | map({key: .[0], value: length}) | from_entries'),"
    echo "      \"allow_promotion_codes_true_count\": $(echo "$CKO" | jq '[.data[] | select(.allow_promotion_codes == true)] | length'),"
    echo "      \"discounts_present_count\": $(echo "$CKO" | jq '[.data[] | select(.discounts != null and (.discounts | length) > 0)] | length'),"
    echo "      \"adaptive_pricing_enabled_count\": $(echo "$CKO" | jq '[.data[] | select(.adaptive_pricing.enabled == true)] | length'),"
    echo "      \"automatic_tax_enabled_count\": $(echo "$CKO" | jq '[.data[] | select(.automatic_tax.enabled == true)] | length'),"
    echo "      \"payment_link_present_count\": $(echo "$CKO" | jq '[.data[] | select(.payment_link != null)] | length')"
    echo "    },"

    # Active payment links
    PL=$(stripe_api https://api.stripe.com/v1/payment_links -G --data-urlencode "limit=100" --data-urlencode "active=true")
    echo "    \"active_payment_links\": {"
    echo "      \"count\": $(echo "$PL" | jq '.data | length')"
    echo "    },"

    # Coupons
    CPN=$(stripe_api https://api.stripe.com/v1/coupons -G --data-urlencode "limit=100")
    echo "    \"coupons\": {"
    echo "      \"count\": $(echo "$CPN" | jq '.data | length'),"
    echo "      \"valid_count\": $(echo "$CPN" | jq '[.data[] | select(.valid == true)] | length')"
    echo "    },"

    # Promotion codes
    PRM=$(stripe_api https://api.stripe.com/v1/promotion_codes -G --data-urlencode "limit=100" --data-urlencode "active=true")
    echo "    \"active_promotion_codes\": {"
    echo "      \"count\": $(echo "$PRM" | jq '.data | length')"
    echo "    }"

    echo "  }"
  fi
fi

# ============================================================
# PayPal
# ============================================================
if [[ "$PROVIDER" == "paypal" || "$PROVIDER" == "both" ]]; then
  echo ","
  if [[ -z "${PAYPAL_CLIENT_ID:-}" || -z "${PAYPAL_CLIENT_SECRET:-}" || -z "${PAYPAL_API_BASE:-}" ]]; then
    echo "  \"paypal_error\": \"PAYPAL_* env vars not set\""
  else
    # Mint OAuth token (DO NOT PRINT IT)
    TOKEN=$(paypal_oauth_token | jq -r .access_token)
    if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
      echo "  \"paypal_error\": \"OAuth token mint failed\""
    else
      echo "  \"paypal\": {"

      # Plans (list active)
      PLANS=$(paypal_api "$PAYPAL_API_BASE/v1/billing/plans?page_size=20&total_required=true")
      PLAN_COUNT=$(echo "$PLANS" | jq '.plans // [] | length')
      echo "    \"plans\": {"
      echo "      \"count\": $PLAN_COUNT,"
      echo "      \"status_counts\": $(echo "$PLANS" | jq '[.plans // [] | .[] | .status] | group_by(.) | map({key: .[0], value: length}) | from_entries')"
      echo "    },"

      # OAuth env confirmation (DO NOT PRINT TOKEN)
      ENV_LABEL=$(if [[ "$PAYPAL_API_BASE" == *"sandbox"* ]]; then echo "sandbox"; else echo "production"; fi)
      echo "    \"environment\": \"$ENV_LABEL\""

      echo "  }"
    fi
  fi
fi

echo "}"
