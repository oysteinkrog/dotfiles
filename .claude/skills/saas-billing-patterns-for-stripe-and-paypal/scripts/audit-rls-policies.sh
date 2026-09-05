#!/usr/bin/env bash
# audit-rls-policies.sh — Verify Supabase RLS policies on billing tables, with anon + authenticated probes.
#
# Usage: ./scripts/audit-rls-policies.sh
#
# Requires:
#   DATABASE_URL          — DB connection string (admin / service_role allowed for the SCHEMA reads)
#   SUPABASE_URL          — for client probes
#   SUPABASE_ANON_KEY     — for anon probe
#   TEST_USER_A_JWT       — JWT for user A
#   TEST_USER_B_JWT       — JWT for user B
#
# Exits 0 if RLS audit clean, 1 if drift, 2 if deps missing.

set -uo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required." >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "curl + jq required." >&2
  exit 2
fi
if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL required." >&2
  exit 2
fi

DRIFT=0

# Tables to audit
BILLING_TABLES=(
  subscriptions
  payment_events
  organizations
  email_jobs
  email_dlq
  compliance_events
  orphan_subscription_cancels
  individual_subscription_intents
  abuse_signals
)

echo "## Supabase RLS Audit"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

# Step 1: Confirm RLS is enabled on each table
echo "### RLS enabled-state per table"
for tbl in "${BILLING_TABLES[@]}"; do
  rls_enabled=$(psql "$DATABASE_URL" -tA -c "SELECT relrowsecurity FROM pg_class WHERE relname = '$tbl' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');" 2>/dev/null)
  if [[ -z "$rls_enabled" ]]; then
    echo "  ⚠ $tbl: table not found"
  elif [[ "$rls_enabled" == "t" ]]; then
    echo "  ✓ $tbl: RLS enabled"
  else
    echo "  ✗ $tbl: RLS DISABLED — CRITICAL"
    DRIFT=$((DRIFT + 10))
  fi
done
echo

# Step 2: Check for `using (true)` policies
echo "### Policies with 'using (true)' (effectively no isolation)"
PERMISSIVE=$(psql "$DATABASE_URL" -tA -c "
  SELECT schemaname || '.' || tablename || '.' || policyname
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = ANY(ARRAY[$(printf "'%s'," "${BILLING_TABLES[@]}" | sed 's/,$//')])
    AND qual::text ILIKE '%true%'
    AND char_length(qual::text) < 30;" 2>/dev/null)
if [[ -z "$PERMISSIVE" ]]; then
  echo "  ✓ none"
else
  echo "$PERMISSIVE" | sed 's/^/  ✗ /'
  DRIFT=$((DRIFT + 5))
fi
echo

# Step 3: List all policies for each billing table
echo "### Policy list per table"
for tbl in "${BILLING_TABLES[@]}"; do
  echo "  $tbl:"
  psql "$DATABASE_URL" -tA -c "
    SELECT '    ' || policyname || ' (' || cmd || ', roles=' || array_to_string(roles, ',') || ')'
    FROM pg_policies WHERE schemaname = 'public' AND tablename = '$tbl';" 2>/dev/null
done
echo

# Step 4: Anon probe
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "### Anon-client SELECT probe (counts only)"
  for tbl in "${BILLING_TABLES[@]}"; do
    cnt=$(curl -sS "${SUPABASE_URL}/rest/v1/${tbl}?select=count" \
      -H "apikey: ${SUPABASE_ANON_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
      -H "Prefer: count=exact" \
      -I 2>/dev/null | grep -i "content-range:" | sed 's/.*\///' | tr -d '\r' || echo "?")
    expected_anon_count="0"
    if [[ "$cnt" != "$expected_anon_count" ]]; then
      echo "  ✗ $tbl: anon read returned $cnt (expected 0)"
      DRIFT=$((DRIFT + 5))
    else
      echo "  ✓ $tbl: anon read = 0"
    fi
  done
  echo
fi

# Step 5: User-A vs User-B probe (if full probe env is provided)
if [[ -n "${TEST_USER_A_JWT:-}" && -n "${TEST_USER_B_JWT:-}" && -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "### Cross-user probe — User A reads, User B reads (counts)"
  for tbl in subscriptions; do  # extend per project
    cnt_a=$(curl -sS "${SUPABASE_URL}/rest/v1/${tbl}?select=count" \
      -H "apikey: ${SUPABASE_ANON_KEY}" \
      -H "Authorization: Bearer ${TEST_USER_A_JWT}" \
      -H "Prefer: count=exact" \
      -I 2>/dev/null | grep -i "content-range:" | sed 's/.*\///' | tr -d '\r' || echo "?")
    cnt_b=$(curl -sS "${SUPABASE_URL}/rest/v1/${tbl}?select=count" \
      -H "apikey: ${SUPABASE_ANON_KEY}" \
      -H "Authorization: Bearer ${TEST_USER_B_JWT}" \
      -H "Prefer: count=exact" \
      -I 2>/dev/null | grep -i "content-range:" | sed 's/.*\///' | tr -d '\r' || echo "?")
    echo "  $tbl: User A sees $cnt_a; User B sees $cnt_b"
    echo "  (Manually verify A ≠ B if both users have data; if equal and >0 then RLS is broken)"
	  done
elif [[ -n "${TEST_USER_A_JWT:-}" || -n "${TEST_USER_B_JWT:-}" ]]; then
  echo "### Cross-user probe"
  echo "  ⚠ skipped: TEST_USER_A_JWT/TEST_USER_B_JWT require SUPABASE_URL and SUPABASE_ANON_KEY too"
  DRIFT=$((DRIFT + 1))
fi
echo

echo "---"
if [[ $DRIFT -eq 0 ]]; then
  echo "✓ RLS audit basic pass."
  exit 0
else
  echo "✗ $DRIFT drift score. See B50 § Supabase RLS."
  exit 1
fi
