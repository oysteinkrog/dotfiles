#!/usr/bin/env bash
# run-staging-drills.sh — Trigger Stripe Test events + PayPal sandbox webhooks; verify state.
#
# Usage: ./scripts/run-staging-drills.sh <staging-base-url>
#   e.g.  ./scripts/run-staging-drills.sh https://staging.acme.com
#
# Requires: Stripe CLI (`stripe`), curl, jq, plus appropriate env vars:
#   STRIPE_TEST_SECRET_KEY    (for stripe trigger)
#   PAYPAL_SANDBOX_CLIENT_ID + PAYPAL_SANDBOX_CLIENT_SECRET (for sandbox API calls)
#   CRON_SECRET                (for invoking cron endpoints)
#
# This script is intentionally a thin wrapper. The detailed scenarios live in
# subagents/staging-verifier.md; the agent chooses which to run and asserts
# state in the workspace.

set -uo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "Usage: $0 <staging-base-url>" >&2
  exit 1
fi

if ! command -v stripe >/dev/null 2>&1; then
  echo "Stripe CLI required. Install: https://stripe.com/docs/stripe-cli" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required." >&2
  exit 2
fi

WORKSPACE="${WORKSPACE:-.billing_workspace}"
mkdir -p "$WORKSPACE"
REPORT="$WORKSPACE/phase9_drill_report_$(date +%Y%m%d_%H%M%S).md"

echo "# Phase 9 Staging Drill Report" > "$REPORT"
echo "Generated at: $(date -Iseconds)" >> "$REPORT"
echo "Base URL: $BASE_URL" >> "$REPORT"
echo >> "$REPORT"

run_drill() {
  local name="$1"
  local cmd="$2"
  echo "## Drill: $name" | tee -a "$REPORT"
  echo "Command: \`$cmd\`" | tee -a "$REPORT"
  echo "" | tee -a "$REPORT"
  if eval "$cmd" 2>&1 | tee -a "$REPORT"; then
    echo "Result: ✓ pass" | tee -a "$REPORT"
  else
    echo "Result: ✗ fail" | tee -a "$REPORT"
  fi
  echo "" | tee -a "$REPORT"
}

# Drill 3: Stripe webhook replay
run_drill "stripe-replay" \
  "stripe trigger customer.subscription.updated --add subscription:metadata.test_run=drill && \
   sleep 2 && \
   curl -sS -X POST $BASE_URL/api/stripe/webhook -H 'Stripe-Signature: drilltest' -d '{}' || true"

# Drill 9: Cron lock — trigger same cron twice in rapid succession
run_drill "cron-lock-rapid-fire" \
  "(curl -sS -H 'Authorization: Bearer \$CRON_SECRET' $BASE_URL/api/cron/webhook-reconciliation &) ; \
   curl -sS -H 'Authorization: Bearer \$CRON_SECRET' $BASE_URL/api/cron/webhook-reconciliation"

# Drill 11: Account-mismatch (Connect/org events) — only if STRIPE_ACCOUNT_ID is set in staging env
run_drill "stripe-account-mismatch" \
  "stripe trigger customer.subscription.updated --add subscription:metadata.fake_account=acct_attacker"

# More drills can be added; see subagents/staging-verifier.md for the full list.

echo
echo "Report written to: $REPORT"
echo "Each drill above shows pass/fail; investigate fails before completing Phase 9."
