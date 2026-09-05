#!/usr/bin/env bash
# audit-stripe-event-coverage.sh — Compare HANDLED_STRIPE_EVENTS in code vs. live Stripe Dashboard webhook config.
#
# Usage: ./scripts/audit-stripe-event-coverage.sh <project-path>
#
# Requires: STRIPE_SECRET_KEY env var (read-only restricted key recommended).
#
# Exits 0 if bidirectional coverage is correct, 1 if drift detected, 2 if dependencies missing.

set -uo pipefail

PROJECT="${1:-.}"
PROJECT="$(cd "$PROJECT" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 2
fi
if [[ -z "${STRIPE_SECRET_KEY:-}" ]]; then
  echo "STRIPE_SECRET_KEY env var required (use a read-only restricted key)." >&2
  exit 2
fi
if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required." >&2
  exit 2
fi

cd "$PROJECT"

stripe_api() {
  curl -sS --config - "$@" <<CURLCFG
user = "${STRIPE_SECRET_KEY}:"
CURLCFG
}

# Step 1: Extract HANDLED_STRIPE_EVENTS from code
HANDLED_FILE=$(rg -l 'HANDLED_STRIPE_EVENTS' --type-add 'src:*.{ts,tsx,js,jsx}' -tsrc 2>/dev/null | head -1)
if [[ -z "$HANDLED_FILE" ]]; then
  echo "No HANDLED_STRIPE_EVENTS set found in code. Audit cannot proceed." >&2
  exit 2
fi

# Extract literals between brackets/quotes after HANDLED_STRIPE_EVENTS
# (Limited to a reasonable window; if the project structures the set unusually,
#  override the extraction by setting STRIPE_HANDLED_EVENTS env var to a newline-separated list.)
if [[ -n "${STRIPE_HANDLED_EVENTS:-}" ]]; then
  HANDLED_EVENTS=$(echo "$STRIPE_HANDLED_EVENTS" | sort -u)
else
  HANDLED_EVENTS=$(rg -A 100 'HANDLED_STRIPE_EVENTS' "$HANDLED_FILE" \
    | rg -o "['\"][a-z._]+['\"]" \
    | tr -d "'\"" \
    | sort -u)
fi

# Step 2: Fetch Stripe webhook endpoints
RESPONSE=$(stripe_api https://api.stripe.com/v1/webhook_endpoints \
  -G --data-urlencode "limit=10" 2>/dev/null)

if [[ -z "$RESPONSE" ]] || ! echo "$RESPONSE" | jq empty 2>/dev/null; then
  echo "Failed to fetch Stripe webhook endpoints." >&2
  exit 2
fi

# Step 3: For each enabled endpoint, get its enabled_events
SUBSCRIBED_EVENTS=$(echo "$RESPONSE" | jq -r '.data[] | select(.status == "enabled") | .enabled_events[]' | sort -u)

# Step 4: Compute the diffs
HANDLED_BUT_NOT_SUBSCRIBED=$(comm -23 <(echo "$HANDLED_EVENTS") <(echo "$SUBSCRIBED_EVENTS"))
SUBSCRIBED_BUT_NOT_HANDLED=$(comm -13 <(echo "$HANDLED_EVENTS") <(echo "$SUBSCRIBED_EVENTS"))

# Step 5: Report
echo "## Stripe Event Coverage Audit"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "### Handled in code (set hash: $(echo "$HANDLED_EVENTS" | sha256sum | cut -d' ' -f1 | head -c 8))"
echo "$HANDLED_EVENTS" | sed 's/^/  /'
echo
echo "### Subscribed in Stripe (set hash: $(echo "$SUBSCRIBED_EVENTS" | sha256sum | cut -d' ' -f1 | head -c 8))"
echo "$SUBSCRIBED_EVENTS" | sed 's/^/  /'
echo
echo "### Handled but NOT subscribed (DEAD CODE — code branch unreachable)"
if [[ -z "$HANDLED_BUT_NOT_SUBSCRIBED" ]]; then
  echo "  (none)"
else
  echo "$HANDLED_BUT_NOT_SUBSCRIBED" | sed 's/^/  ✗ /'
fi
echo
echo "### Subscribed but NOT handled (SILENT MISS — provider sends; code ignores)"
if [[ -z "$SUBSCRIBED_BUT_NOT_HANDLED" ]]; then
  echo "  (none)"
else
  echo "$SUBSCRIBED_BUT_NOT_HANDLED" | sed 's/^/  ✗ /'
fi
echo
echo "---"

DRIFT_COUNT=0
[[ -n "$HANDLED_BUT_NOT_SUBSCRIBED" ]] && DRIFT_COUNT=$((DRIFT_COUNT + $(echo "$HANDLED_BUT_NOT_SUBSCRIBED" | wc -l)))
[[ -n "$SUBSCRIBED_BUT_NOT_HANDLED" ]] && DRIFT_COUNT=$((DRIFT_COUNT + $(echo "$SUBSCRIBED_BUT_NOT_HANDLED" | wc -l)))

if [[ $DRIFT_COUNT -eq 0 ]]; then
  echo "✓ Bidirectional coverage is correct."
  exit 0
else
  echo "✗ $DRIFT_COUNT drift item(s) detected. Review B40 § Bidirectional event coverage."
  exit 1
fi
