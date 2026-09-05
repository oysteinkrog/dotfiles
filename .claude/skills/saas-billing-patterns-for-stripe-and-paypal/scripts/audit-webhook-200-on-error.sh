#!/usr/bin/env bash
# audit-webhook-200-on-error.sh — Detect webhook handlers that return non-200 after recordWebhookEvent succeeds.
#
# Usage: ./scripts/audit-webhook-200-on-error.sh <project-path>
#
# Exits 0 if clean, 1 if any violations found, 2 if dependencies missing.

set -uo pipefail

PROJECT="${1:-.}"
PROJECT="$(cd "$PROJECT" && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required." >&2
  exit 2
fi

cd "$PROJECT"

# Find webhook route files (handle spaces / special chars via NUL delimiters)
mapfile -d '' WEBHOOK_FILES < <(rg -l0 -e '/api/(stripe|paypal)/webhook' --type-add 'src:*.{ts,tsx,js,jsx,py,rb,ex,exs}' -tsrc 2>/dev/null || true)

if [[ ${#WEBHOOK_FILES[@]} -eq 0 ]]; then
  echo "No webhook handler files found."
  exit 0
fi

VIOLATIONS=0
echo "Auditing ${#WEBHOOK_FILES[@]} webhook handler file(s) for 200-on-error contract..."
echo

for file in "${WEBHOOK_FILES[@]}"; do
  # Skip if the file doesn't actually call recordWebhookEvent (some routes may match the path filter
  # but not be the canonical handler — e.g. middleware shims).
  if ! rg -q 'recordWebhookEvent' "$file" 2>/dev/null; then
    continue
  fi

  # Capture the 50 lines following each recordWebhookEvent call; look for status: 500 or
  # an `throw` not wrapped in an outer try/catch. We're conservative: only flag explicit
  # `status: 500` returns to avoid false positives from commented-out code or test fixtures.
  if rg -A 50 -e 'recordWebhookEvent' "$file" 2>/dev/null | rg -q -e 'status:\s*500\b|NextResponse\.json\([^)]*\{[^)]*status:\s*500'; then
    matches=$(rg -n -A 50 -e 'recordWebhookEvent' "$file" 2>/dev/null | rg -e 'status:\s*500\b')
    if [[ -n "$matches" ]]; then
      echo "VIOLATION: ${file#$PROJECT/}"
      echo "$matches" | sed 's/^/  /'
      echo
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  fi
done

echo "---"
if [[ $VIOLATIONS -eq 0 ]]; then
  echo "No 200-on-error violations detected in webhook handlers."
  exit 0
else
  echo "Found $VIOLATIONS webhook handler(s) with potential 200-on-error violations."
  echo "Review each: webhook handlers MUST return 200 once recordWebhookEvent succeeds (operator: ⤴ 200-ON-ERROR)."
  echo "See: references/patterns/40-WEBHOOKS.md § The 5-step ingestion contract"
  exit 1
fi
