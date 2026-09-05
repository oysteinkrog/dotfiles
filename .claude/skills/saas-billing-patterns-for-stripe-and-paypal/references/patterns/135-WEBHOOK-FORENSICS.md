# Bundle B135 — Webhook Forensics

> **Where this comes from.** § 15 (the smoking-gun query) + § 30.1-30.5 (operational runbooks) + B140 (incident response). Plus operational reality: when something's wrong, you need to investigate webhook history fast.

When a customer ticket arrives or an alarm fires, the first questions are: WHAT events arrived, WHEN, in what order, with what payload, with what error. Webhook forensics is the toolset for answering that.

---

## Pattern 1 — The smoking-gun query (per § 15)

For PayPal team hijack investigation, the canonical query:

```sql
SELECT
  o.id,
  o.subscription_status,
  o.paypal_status,
  o.paypal_subscription_id AS current_subscription_id,
  e.payload->'resource'->>'id' AS attempted_subscription_id,
  e.payload->'resource'->'subscriber'->>'payer_id' AS attacker_payer_id,
  e.payload->'resource'->>'plan_id' AS attempted_plan_id,
  e.created_at AS event_recorded_at,
  e.processed_at IS NOT NULL AS event_processed
FROM organizations o
JOIN payment_events e
  ON e.provider = 'paypal'::subscription_provider
 AND e.event_id = '<event-id>'
WHERE o.id = '<org-id>'::uuid;
```

Interpretation:
- `current_subscription_id != attempted_subscription_id` → SA-01 contained it. ✓
- `current_subscription_id == attempted_subscription_id` → containment failed. Restore from PITR.

Generalize this pattern for other classes:

```sql
-- Stripe webhook event detail (sanitized)
SELECT
  e.event_id, e.event_type, e.created_at, e.processed_at,
  e.payload->>'type' AS event_type_payload,
  e.payload->'data'->'object'->>'id' AS object_id,
  e.payload->'data'->'object'->>'customer' AS customer_id,
  e.payload->'data'->'object'->>'subscription' AS subscription_id,
  e.payload->'data'->'object'->>'status' AS object_status,
  e.payload->'data'->'object'->>'amount' AS amount,
  e.payload->'data'->'object'->>'currency' AS currency,
  e.last_error,
  e.retry_count
FROM payment_events e
WHERE e.provider = 'stripe'
  AND (e.event_id = $1 OR e.payload->'data'->'object'->>'customer' = $2)
ORDER BY e.created_at DESC
LIMIT 50;
```

Each forensic query lives in `<project>/docs/forensics/queries/<name>.sql`.

---

## Pattern 2 — Per-customer event timeline

For "what happened to this customer":

```sql
WITH customer_events AS (
  SELECT
    e.created_at as ts,
    'webhook' as kind,
    e.event_type as detail,
    e.processed_at IS NOT NULL as processed,
    e.last_error
  FROM payment_events e
  WHERE e.payload->'data'->'object'->>'customer' = $1
     OR e.payload->'resource'->>'custom_id' = $2

  UNION ALL

  SELECT
    s.updated_at as ts,
    'subscription_state' as kind,
    s.status as detail,
    NULL as processed,
    NULL as last_error
  FROM subscriptions s
  WHERE s.user_id = $2

  UNION ALL

  SELECT
    j.created_at as ts,
    'email' as kind,
    j.type as detail,
    j.status = 'sent' as processed,
    j.last_error
  FROM email_jobs j
  WHERE j.recipient = $3

  UNION ALL

  SELECT
    a.created_at as ts,
    'admin_action' as kind,
    a.event_type as detail,
    NULL, NULL
  FROM audit_log a
  WHERE a.event_data->>'user_id' = $2

  UNION ALL

  SELECT
    sl.occurred_at as ts,
    'settlement' as kind,
    sl.type || ': $' || sl.gross_amount as detail,
    NULL, NULL
  FROM settlement_ledger sl
  WHERE sl.user_id = $2
)
SELECT * FROM customer_events ORDER BY ts DESC LIMIT 200;
```

A timeline view of EVERY billing-relevant thing that happened to a customer. Investigators can spot the bug class within 30 seconds.

---

## Pattern 3 — Replay tool (manual)

For investigating: replay an event against a staging environment to see what WOULD happen.

```ts
// scripts/replay-event-to-staging.ts
import { db } from '@/lib/db';

async function replayEventToStaging(eventId: string) {
  const event = await db.query.paymentEvents.findFirst({ where: eq(paymentEvents.eventId, eventId) });
  if (!event) throw new Error(`Event ${eventId} not found`);

  // Construct a re-signed request to staging
  const body = JSON.stringify(event.payload);
  const signature = createTestSignature(body, env.STAGING_WEBHOOK_SECRET);

  const response = await fetch(`${env.STAGING_URL}/api/${event.provider}/webhook?replay=true`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      [event.provider === 'stripe' ? 'stripe-signature' : 'paypal-transmission-id']: signature,
      'X-Replay-Authorized-By': 'forensics-investigator',
    },
    body,
  });

  console.log({
    status: response.status,
    body: await response.json(),
    eventId,
    eventType: event.event_type,
  });
}
```

Auth: STAGING accepts replay requests with `X-Replay-Authorized-By` header (gated on a separate token, NOT the production webhook secret).

---

## Pattern 4 — Webhook traffic analysis

For "is provider X having delivery issues":

```sql
-- Webhook traffic over time
SELECT
  date_trunc('hour', created_at) as hour,
  provider,
  count(*) as events_received,
  count(*) FILTER (WHERE processed_at IS NULL) as still_pending,
  count(*) FILTER (WHERE processed_at IS NOT NULL) as processed,
  count(*) FILTER (WHERE retry_count > 0) as required_retry,
  avg(extract(epoch from (processed_at - created_at))) FILTER (WHERE processed_at IS NOT NULL) as avg_processing_time_sec
FROM payment_events
WHERE created_at > now() - interval '7 days'
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

Look for:
- Sudden drops in `events_received` (provider not delivering).
- Spikes in `still_pending` after a recent hour (cron not draining).
- Spikes in `required_retry` (handler bug).
- Spikes in `avg_processing_time_sec` (slow handler; risk of timeout).

---

## Pattern 5 — Per-event-type processing-failure analysis

```sql
-- Which event types are failing
SELECT
  event_type,
  count(*) as total_events,
  count(*) FILTER (WHERE last_error IS NOT NULL) as failed_count,
  (count(*) FILTER (WHERE last_error IS NOT NULL) * 100.0 / count(*))::numeric(5,2) as failure_rate_pct,
  string_agg(DISTINCT substring(last_error, 1, 80), ' | ') as sample_errors
FROM payment_events
WHERE created_at > now() - interval '24 hours'
GROUP BY event_type
HAVING count(*) FILTER (WHERE last_error IS NOT NULL) > 0
ORDER BY failure_rate_pct DESC;
```

Surfaces handler bugs by event type. > 5% failure rate on any event type = investigate.

---

## Pattern 6 — Hijack attempt forensics

```sql
-- Recent abuse signals related to webhook hijacks
SELECT
  a.created_at,
  a.signal,
  a.metadata->>'received_account' as wrong_account,
  a.metadata->>'received_payer_id' as attacker_payer_id,
  a.metadata->>'reason' as reason,
  a.target_id,
  a.target_type
FROM abuse_signals a
WHERE a.signal IN (
  'webhook_event_rejected',
  'webhook_hijack_attempt',
  'paypal_user_id_mismatch',
  'webhook_signature_failed'
)
AND a.created_at > now() - interval '7 days'
ORDER BY a.created_at DESC;
```

For each row, the next step is: which user/org was targeted? Did containment work?

---

## Pattern 7 — Reconciliation drift detection

```sql
-- Subscriptions where DB and provider may disagree
WITH local_subs AS (
  SELECT
    s.id, s.external_id, s.provider, s.status, s.last_event_at,
    extract(epoch from (now() - s.last_event_at)) / 3600 as hours_since_last_event
  FROM subscriptions s
  WHERE s.status IN ('active', 'past_due')
    AND (s.last_event_at IS NULL OR s.last_event_at < now() - interval '24 hours')
)
SELECT * FROM local_subs ORDER BY hours_since_last_event DESC LIMIT 100;
```

Subscriptions where we haven't received an event in > 24h are candidates for provider-reconciliation. If many → reconciliation cron is broken.

---

## Pattern 8 — Stuck-event triage flow

```
1. webhook-staleness alarm fires
2. Run: SELECT count(*), min(created_at) FROM payment_events WHERE processed_at IS NULL AND retry_count < MAX_RETRY_COUNT;
3. If count > 0 and min(created_at) > 10min ago:
   a. Check Stripe / PayPal status pages for outage
   b. Manually trigger reconciliation cron
   c. If still stuck: read last_error column → grep error → identify class
   d. Fix root cause; re-run cron
4. If count == 0: alarm was correct; proceed to normal cron cycle
```

Document the flow in `docs/runbooks/webhook-staleness.md`.

---

## Pattern 9 — Forensics dashboard

For ops, a single page that aggregates the most-useful forensic queries:

```tsx
function ForensicsDashboard() {
  return (
    <Page>
      <Section title="Recent webhook traffic">
        <WebhookTrafficChart />  {/* Pattern 4 query */}
      </Section>
      <Section title="Event-type failure rates (24h)">
        <EventFailureRateTable />  {/* Pattern 5 */}
      </Section>
      <Section title="Hijack attempts (7d)">
        <HijackAttemptsTable />  {/* Pattern 6 */}
      </Section>
      <Section title="Reconciliation drift">
        <DriftSubscriptionsTable />  {/* Pattern 7 */}
      </Section>
      <Section title="Per-customer lookup">
        <CustomerEventTimelineLookup />  {/* Pattern 2 */}
      </Section>
    </Page>
  );
}
```

Bookmark for on-call.

---

## Pattern 10 — Sanitized webhook payload export

For sharing with Stripe / PayPal support:

```ts
// scripts/sanitize-webhook-payload.mjs
async function sanitizeForSupport(eventId: string) {
  const event = await db.query.paymentEvents.findFirst({ where: eq(paymentEvents.eventId, eventId) });
  const sanitized = redact(event.payload, [
    'email', 'name', 'address', 'phone',
    'card.last4', 'card.fingerprint',
    'paypal.payer.email', 'paypal.payer.name',
    // ... per-provider PII fields
  ]);
  return JSON.stringify(sanitized, null, 2);
}
```

Send the sanitized version when filing a Stripe support ticket. Keep the unsanitized version internal.

---

## Pattern 11 — Time-bounded forensic queries

When triaging a Sev1, time matters. Bound every query:

```sql
-- ALWAYS include a time bound
SELECT * FROM payment_events
WHERE provider = 'stripe'
  AND created_at > now() - interval '4 hours'  -- ← bound
  AND processed_at IS NULL
LIMIT 100;  -- ← also bound
```

Without bounds, a single forensic query during an incident can lock the table for minutes.

---

## Pattern 12 — Audit trail for forensic queries

Every forensic query against production should be logged:

```sql
-- Use Postgres's `pg_stat_statements` or per-query log
SET log_min_duration_statement = 1000;  -- log queries > 1s
SET log_statement = 'all';  -- log every query (HEAVY; use during incidents only)
```

Or in the admin UI: every "Run forensic query" button click writes to `audit_log` with the query + result count.

This protects against insiders running unauthorized queries during an incident.

---

## Pattern 13 — Replay corpus from real incidents

After every incident, if it was a webhook bug, save the relevant payment_events as a replay-corpus fixture:

```bash
# scripts/save-incident-corpus.sh
EVENT_IDS="evt_xxx evt_yyy evt_zzz"
for id in $EVENT_IDS; do
  psql "$DATABASE_URL" -tAc "SELECT payload FROM payment_events WHERE event_id = '$id'" \
    | sanitize-payload > "fixtures/replay-corpus/incident-$(date +%Y%m%d)-$id.json"
done
git add fixtures/replay-corpus/
git commit -m "incident-2026-05-04: save replay corpus"
```

Future engineers can replay these to verify their fix doesn't regress.

---

## Polish Bar checks for B135

- [ ] Smoking-gun query per known failure class lives in `docs/forensics/queries/`.
- [ ] Per-customer event timeline query (multi-source aggregation).
- [ ] Replay tool (to staging) wired with auth.
- [ ] Webhook traffic analysis query.
- [ ] Per-event-type failure-rate query.
- [ ] Hijack attempt forensics query.
- [ ] Reconciliation drift detection query.
- [ ] Forensics dashboard (admin UI page).
- [ ] Sanitized payload export tool for support tickets.
- [ ] Every forensic query is time-bounded.
- [ ] Forensic query execution audit-logged.
- [ ] Incident replay corpus saved per Sev0/Sev1 incident.

---

## Common B135 mistakes

- **No smoking-gun queries documented.** Operator under pressure invents queries; mistakes happen.
- **Forensic queries unbounded.** Locks the table during an incident.
- **Replay tool reuses production webhook secret.** Compromised replay = production data corruption.
- **Sanitized payload not actually sanitized.** PII shared with Stripe support; compliance issue.
- **Forensic queries not audit-logged.** Insider can investigate other users' billing without trace.
- **Per-customer timeline query missing some sources.** Investigator misses key event; wrong root cause.
- **No reconciliation drift detection.** Provider state diverges from DB; discovered weeks later.
- **Replay corpus not saved per incident.** Same class recurs; can't quickly verify fix.
- **Forensic dashboard requires SQL knowledge.** Support agent can't use; tickets escalate.
- **Sanitization regex too aggressive.** Removes information needed for diagnosis.
