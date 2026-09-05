#!/usr/bin/env bash
# stripe-test-clock-drill.sh — Run a complete subscription lifecycle drill using Stripe Test Clocks.
#
# Usage: ./scripts/stripe-test-clock-drill.sh [scenario]
#
# Scenarios: renewal | failed-payment | cancellation | pause-resume
#
# Requires: stripe CLI authenticated, jq, STRIPE_TEST_SECRET_KEY env var.
#
# Drills cover B65 § Stripe Test Clocks scenarios.

set -uo pipefail

SCENARIO="${1:-renewal}"

if ! command -v stripe >/dev/null 2>&1; then
  echo "stripe CLI required. Install: https://stripe.com/docs/stripe-cli" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required." >&2
  exit 2
fi
if [[ -z "${STRIPE_TEST_SECRET_KEY:-}" ]]; then
  echo "STRIPE_TEST_SECRET_KEY env var required." >&2
  exit 2
fi

if [[ ! "$STRIPE_TEST_SECRET_KEY" == sk_test_* ]]; then
  echo "STRIPE_TEST_SECRET_KEY does not start with sk_test_. REFUSING to run drill against non-test account." >&2
  exit 2
fi

CHECKED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "## Stripe Test Clock Drill: $SCENARIO"
echo "Started: $CHECKED_AT"
echo
EXIT_STATUS=0

# Helper: API call with auth
api() {
  local method="$1"; shift
  local path="$1"; shift
  curl -sS --config - -X "$method" "https://api.stripe.com$path" "$@" <<CURLCFG
user = "${STRIPE_TEST_SECRET_KEY}:"
CURLCFG
}

# 1. Create test clock
echo "Creating test clock..."
NOW=$(date +%s)
CLOCK=$(api POST "/v1/test_helpers/test_clocks" -d "frozen_time=$NOW" -d "name=drill-$SCENARIO-$NOW")
CLOCK_ID=$(echo "$CLOCK" | jq -r '.id')
echo "  Clock: $CLOCK_ID"

# 2. Create test customer + subscription on the clock
echo "Creating test customer + subscription..."
CUSTOMER=$(api POST "/v1/customers" \
  -d "email=test_drill_${SCENARIO}@example.test" \
  -d "test_clock=$CLOCK_ID" \
  -d "payment_method=pm_card_visa" \
  -d "invoice_settings[default_payment_method]=pm_card_visa")
CUSTOMER_ID=$(echo "$CUSTOMER" | jq -r '.id')

# Use a test price; require user to set TEST_PRICE_ID
if [[ -z "${TEST_PRICE_ID:-}" ]]; then
  echo "  TEST_PRICE_ID env var required (a test-mode Stripe price)." >&2
  api DELETE "/v1/test_helpers/test_clocks/$CLOCK_ID" >/dev/null
  exit 2
fi
SUB=$(api POST "/v1/subscriptions" \
  -d "customer=$CUSTOMER_ID" \
  -d "items[0][price]=$TEST_PRICE_ID")
SUB_ID=$(echo "$SUB" | jq -r '.id')
echo "  Customer: $CUSTOMER_ID"
echo "  Subscription: $SUB_ID"

# 3. Run the scenario
case "$SCENARIO" in
  renewal)
    echo "Advancing time +31 days..."
    NEW_TIME=$((NOW + 31 * 86400))
    api POST "/v1/test_helpers/test_clocks/$CLOCK_ID/advance" -d "frozen_time=$NEW_TIME" >/dev/null

    echo "Waiting for clock to settle..."
    for i in $(seq 1 60); do
      STATUS=$(api GET "/v1/test_helpers/test_clocks/$CLOCK_ID" | jq -r '.status')
      if [[ "$STATUS" == "ready" ]]; then break; fi
      sleep 2
    done

    SUB_AFTER=$(api GET "/v1/subscriptions/$SUB_ID")
    NEW_PERIOD_END=$(echo "$SUB_AFTER" | jq -r '.current_period_end')
    echo "Sub current_period_end after advance: $(date -u -d @$NEW_PERIOD_END +%Y-%m-%dT%H:%M:%SZ)"

    if [[ $NEW_PERIOD_END -gt $((NOW + 27 * 86400)) ]]; then
      echo "✓ PASS: renewal advanced period_end correctly."
    else
      echo "✗ FAIL: period_end did not advance as expected."
      EXIT_STATUS=1
    fi
    ;;

  failed-payment)
    echo "Setting customer payment method to one that always fails..."
    api POST "/v1/customers/$CUSTOMER_ID" \
      -d "invoice_settings[default_payment_method]=pm_card_chargeDeclined" >/dev/null

    echo "Advancing time +31 days..."
    api POST "/v1/test_helpers/test_clocks/$CLOCK_ID/advance" \
      -d "frozen_time=$((NOW + 31 * 86400))" >/dev/null
    sleep 5

    SUB_AFTER=$(api GET "/v1/subscriptions/$SUB_ID")
    STATUS=$(echo "$SUB_AFTER" | jq -r '.status')
    echo "Sub status after failed payment: $STATUS"

    if [[ "$STATUS" == "past_due" || "$STATUS" == "incomplete" ]]; then
      echo "✓ PASS: subscription transitioned to past_due / incomplete."
    else
      echo "✗ FAIL: expected past_due / incomplete; got $STATUS."
      EXIT_STATUS=1
    fi
    ;;

  cancellation)
    echo "Cancelling subscription at period end..."
    api POST "/v1/subscriptions/$SUB_ID" -d "cancel_at_period_end=true" >/dev/null
    echo "Advancing time +31 days..."
    api POST "/v1/test_helpers/test_clocks/$CLOCK_ID/advance" \
      -d "frozen_time=$((NOW + 31 * 86400))" >/dev/null
    sleep 5

    SUB_AFTER=$(api GET "/v1/subscriptions/$SUB_ID")
    STATUS=$(echo "$SUB_AFTER" | jq -r '.status')
    echo "Sub status after period-end cancellation: $STATUS"

    if [[ "$STATUS" == "canceled" ]]; then
      echo "✓ PASS: subscription transitioned to canceled."
    else
      echo "✗ FAIL: expected canceled; got $STATUS."
      EXIT_STATUS=1
    fi
    ;;

  pause-resume)
    echo "Pausing subscription..."
    api POST "/v1/subscriptions/$SUB_ID" \
      -d "pause_collection[behavior]=void" \
      -d "metadata[paused_for_org]=test" >/dev/null

    SUB_AFTER=$(api GET "/v1/subscriptions/$SUB_ID")
    PAUSED=$(echo "$SUB_AFTER" | jq -r '.pause_collection.behavior')
    echo "Pause behavior: $PAUSED"

    echo "Resuming subscription..."
    api POST "/v1/subscriptions/$SUB_ID" -d "pause_collection=" >/dev/null

    SUB_AFTER=$(api GET "/v1/subscriptions/$SUB_ID")
    PAUSED=$(echo "$SUB_AFTER" | jq -r '.pause_collection // null')
    if [[ "$PAUSED" == "null" ]]; then
      echo "✓ PASS: pause + resume successful."
    else
      echo "✗ FAIL: pause not cleared; got $PAUSED."
      EXIT_STATUS=1
    fi
    ;;

  *)
    echo "Unknown scenario: $SCENARIO" >&2
    api DELETE "/v1/test_helpers/test_clocks/$CLOCK_ID" >/dev/null
    exit 1
    ;;
esac

# 4. Cleanup
echo "Cleaning up test clock..."
api DELETE "/v1/test_helpers/test_clocks/$CLOCK_ID" >/dev/null
echo "Done."
exit "$EXIT_STATUS"
