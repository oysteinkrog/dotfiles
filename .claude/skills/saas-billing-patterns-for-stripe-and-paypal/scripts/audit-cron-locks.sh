#!/usr/bin/env bash
# audit-cron-locks.sh — Detect crons missing pg_try_advisory_lock or finally-release pattern.
#
# Usage: ./scripts/audit-cron-locks.sh <project-path>

set -uo pipefail

PROJECT="${1:-.}"
PROJECT="$(cd "$PROJECT" && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required." >&2
  exit 2
fi

cd "$PROJECT"

# Find cron route files
CRON_FILES=$(find . -path '*/api/cron/*' -name 'route.ts' -o -path '*/api/cron/*' -name 'route.js' 2>/dev/null | sort)

# Fallback: any file with `cron` in the path
if [[ -z "$CRON_FILES" ]]; then
  CRON_FILES=$(find . -name '*.ts' -o -name '*.js' 2>/dev/null | xargs grep -l '/api/cron/' 2>/dev/null | sort | uniq)
fi

if [[ -z "$CRON_FILES" ]]; then
  echo "No cron handler files found."
  exit 0
fi

VIOLATIONS=0
echo "Auditing cron handlers for advisory-lock pattern..."
echo

for file in $CRON_FILES; do
  echo "Checking: $file"

  has_lock=$(rg -c 'pg_try_advisory_lock|acquireAdvisoryLock' "$file" 2>/dev/null || echo 0)
  has_release=$(rg -c 'pg_advisory_unlock|releaseAdvisoryLock' "$file" 2>/dev/null || echo 0)
  has_reserve=$(rg -c 'pgClient\.reserve|pool\.connect|pool\.reserve' "$file" 2>/dev/null || echo 0)
  has_finally=$(rg -c 'finally' "$file" 2>/dev/null || echo 0)

  if [[ $has_lock -eq 0 ]]; then
    echo "  VIOLATION: no advisory lock acquisition (pg_try_advisory_lock or acquireAdvisoryLock)"
    VIOLATIONS=$((VIOLATIONS + 1))
  elif [[ $has_reserve -gt 0 && $has_finally -eq 0 ]]; then
    echo '  VIOLATION: reserved a connection but no `finally` block detected for release'
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    echo "  OK"
  fi
done

echo
echo "---"
if [[ $VIOLATIONS -eq 0 ]]; then
  echo "All crons have advisory-lock + release patterns."
  exit 0
else
  echo "Found $VIOLATIONS cron(s) with potential lock-pattern violations."
  echo "Review each: every cron must use pg_try_advisory_lock + finally release (operator: ⊞)."
  exit 1
fi
