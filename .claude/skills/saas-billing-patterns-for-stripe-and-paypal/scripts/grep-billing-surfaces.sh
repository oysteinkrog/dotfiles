#!/usr/bin/env bash
# grep-billing-surfaces.sh — List billing-touching files in a project, partitioned by bundle.
#
# Usage: ./scripts/grep-billing-surfaces.sh <project-path>

set -euo pipefail

PROJECT="${1:-.}"
PROJECT="$(cd "$PROJECT" && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required." >&2
  exit 1
fi

cd "$PROJECT"

# Bundle-keyed search patterns (refine for your project's idioms)
declare -A PATTERNS=(
  [B10_schema]='\b(payment_events|subscription_status|subscription_provider|email_jobs|orphan_subscription_cancels|individual_subscription_intents|compliance_events|abuse_signals)\b'
  [B20_constants]='STRIPE_API_VERSION|getStripeClient|BUSINESS\.|WebhookErrorCodes|PaymentErrorCodes|ROUTES\.|env\.STRIPE_|env\.PAYPAL_'
  [B30_checkout]='/api/(stripe|paypal)/create-checkout|pendingCheckoutSessionId|hasActiveSubInOtherProvider|allow_promotion_codes|CHECKOUT_SESSION_ID|customers\.list'
  [B40_webhook]='/api/(stripe|paypal)/webhook|recordWebhookEvent|markEventProcessed|updateSubscriptionStatus|verifyPayPalWebhook|HANDLED_(STRIPE|PAYPAL)_EVENTS'
  [B50_security]='validatePayPalUserId|paypal_user_id_mismatch|webhook_hijack_attempt|FAIL_CLOSED_ENDPOINTS|trackAbuseSignal|logSecurityEvent|payment_event_replay_blocked'
  [B60_state]='pickBestSubscription|deriveAggregateBillingProjection|paused_for_org|stillInGrace|GRACE_PERIOD_DAYS|revokeAccessOnRefund|getPayPalParentPayment'
  [B70_dunning]='DUNNING_STAGES|wasEmailDeliveredSince|retryLatestStripeInvoice|inferEmailJobPriority|payment_action_required|card_expiry|upcoming_renewal|customerPortal|billingPortal'
  [B80_teams]='TEAM_TIERS|TEAM_DUNNING_STAGES|recordPauseIntent|applyPauseIntent|individualSubscriptionIntents|pendingIndividualSubCancel|maxSeats'
  [B90_reliability]='acquireAdvisoryLock|pg_try_advisory_lock|webhook-reconciliation|webhook-staleness|provider-reconciliation|billing-integrity-audit|orphan-sub-cancels|email-queue|OPS_FAILSAFE_EMAIL|failsafeSweep'
  [B100_analytics]='getCurrentMrrSnapshot|computeBlendedFeeRate|computeCustomerHealth|monteCarloRunway|reconciliationFreshnessMetrics|provenance|singleFlight|analyticsExclusions|canonicalSubscriptionCancellationTimestamp'
  [B110_ops]='cronsThatMustExclude|drift-guard|secret_custody|PaymentError|runbook'
)

echo "Billing surfaces in: $PROJECT"
echo

for bundle in $(echo "${!PATTERNS[@]}" | tr ' ' '\n' | sort); do
  pattern="${PATTERNS[$bundle]}"
  echo "## $bundle"
  rg -l -e "$pattern" \
     --type-add 'src:*.{ts,tsx,js,jsx,py,rb,ex,exs,go,rs,sql}' -tsrc \
     2>/dev/null | sort | head -50 | sed 's/^/  /'
  echo
done
