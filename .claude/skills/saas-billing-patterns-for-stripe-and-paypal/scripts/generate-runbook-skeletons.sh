#!/usr/bin/env bash
# generate-runbook-skeletons.sh — Create runbook skeletons from the assets/runbook-template.md for every cron + alarm in the project.
#
# Usage: ./scripts/generate-runbook-skeletons.sh <project-path>
#
# Skeletons are NOT runbooks; they're starting points an engineer fills in.

set -uo pipefail

PROJECT="${1:-.}"
PROJECT="$(cd "$PROJECT" && pwd)"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$SKILL_DIR/assets/runbook-template.md"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template not found: $TEMPLATE" >&2
  exit 2
fi

mkdir -p "$PROJECT/docs/runbooks"

# Discover cron handlers
CRON_NAMES=()
if [[ -d "$PROJECT/src/app/api/cron" ]]; then
  while IFS= read -r dir; do
    NAME=$(basename "$dir")
    CRON_NAMES+=("$NAME")
  done < <(find "$PROJECT/src/app/api/cron" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
fi

# Standard alarm runbooks (per source guide § 74)
STANDARD_RUNBOOKS=(
  "webhook-staleness-alarm"
  "paypal-hijack-attempt"
  "triple-charge-incident"
  "mrr-snapshot-unavailable"
  "email-failsafe-alert"
  "cron-lock-stuck"
  "provider-outage"
  "secret-rotation"
  "manual-invoice-retry"
  "dispute-handling"
  "customer-deletion-with-active-sub"
  "subscription-projection-drift"
  "rate-limit-fail-closed-spike"
  "rate-limit-redis-outage"
  "chargeback"
  "break-glass"
)

# Combine cron-specific + standard
ALL_RUNBOOKS=("${STANDARD_RUNBOOKS[@]}")
for cron in "${CRON_NAMES[@]}"; do
  ALL_RUNBOOKS+=("cron-$cron-stuck")
done

CREATED=0
SKIPPED=0
for name in "${ALL_RUNBOOKS[@]}"; do
  TARGET="$PROJECT/docs/runbooks/$name.md"
  if [[ -f "$TARGET" ]]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  cp "$TEMPLATE" "$TARGET"
  # Replace title placeholder
  RUNBOOK_NAME="$name" perl -0pi -e 's/<runbook-name>/$ENV{RUNBOOK_NAME}/g' "$TARGET"
  CREATED=$((CREATED + 1))
  echo "Created: docs/runbooks/$name.md"
done

echo
echo "Summary:"
echo "  Created: $CREATED"
echo "  Skipped (already exist): $SKIPPED"
echo
echo "Next: open each new runbook and fill in the alarm condition + first-5-minutes commands."
echo "Reference: docs/runbooks/<name>.md uses the template at assets/runbook-template.md"
