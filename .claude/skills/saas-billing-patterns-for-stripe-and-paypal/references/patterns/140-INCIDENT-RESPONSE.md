# Bundle B140 — Incident Response Patterns

> **Where this comes from.** § 30 (operational runbooks) + § 72 (failure-mode catalog) + § 78 (the 9 most common ways this still goes wrong) of the source guide. Plus the methodology in `INCIDENT-RESPONSE-PLAYBOOK.md`.

This bundle is the code-level patterns that make incident response fast and recoverable. The methodology / framework is in `INCIDENT-RESPONSE-PLAYBOOK.md`; THIS bundle is the in-code patterns that incidents flow through.

---

## Pattern 1 — Per-class containment helpers

When an incident happens, you reach for a containment move (per the playbook's "stop the bleed" decision tree). Build those moves as helpers; don't reach for raw SQL under pressure.

```ts
// src/lib/incident/containment.ts

/**
 * Refund a customer for a known-bad charge. Wraps Stripe's refund API
 * with explicit reason logging and synchronous cache invalidation.
 *
 * NOT for routine refunds — those go through the Customer Portal /
 * admin UI. This is for incident response only.
 */
export async function incidentRefund(params: {
  chargeId: string;
  reason: 'duplicate_charge' | 'incident_remediation' | 'fraud';
  ticketId: string;        // your support ticket ID for traceability
  authorizedBy: string;    // operator name
}): Promise<{ refundId: string }> {
  await logSecurityEvent({
    type: 'incident_refund_issued',
    severity: 'high',
    actor: { type: 'user', id: params.authorizedBy },
    target: { type: 'charge', id: params.chargeId },
    details: { reason: params.reason, ticket: params.ticketId },
  });
  const refund = await stripe.refunds.create({
    charge: params.chargeId,
    reason: 'requested_by_customer',
    metadata: {
      incident_reason: params.reason,
      ticket: params.ticketId,
      authorized_by: params.authorizedBy,
    },
  });
  // Synchronous cache invalidation for the affected user (per B60 § Refunds)
  const userId = await resolveUserFromCharge(params.chargeId);
  if (userId) {
    await Promise.race([invalidateUserCaches(userId), sleep(2000)]);
  }
  return { refundId: refund.id };
}

/**
 * Suspend a Stripe sub IMMEDIATELY. Wraps `stripe.subscriptions.cancel`
 * with explicit incident attribution.
 */
export async function incidentSuspendStripeSub(params: {
  subscriptionId: string;
  reason: string;
  ticketId: string;
  authorizedBy: string;
}): Promise<void> {
  await logSecurityEvent({
    type: 'incident_subscription_suspended',
    severity: 'high',
    actor: { type: 'user', id: params.authorizedBy },
    target: { type: 'subscription', id: params.subscriptionId },
    details: { reason: params.reason, ticket: params.ticketId },
  });
  await stripe.subscriptions.cancel(params.subscriptionId, {
    invoice_now: false,
    prorate: false,
  });
}

// ... similar for PayPal cancellation, manual entitlement revoke, account lock, etc.
```

The pattern: every incident-response move logs a `compliance_events` row + `logSecurityEvent` for audit. Operators don't reach for raw SQL or raw Stripe API calls under pressure; they reach for these helpers.

---

## Pattern 2 — Kill switches as feature flags

For each high-blast-radius failure mode, have a feature flag that disables the affected code path. When the incident happens, flip the flag; affected code falls back to the safe path.

```ts
// src/lib/feature-flags.ts (or your project's flag system)
export const FEATURE_FLAGS = {
  // Disable Stripe webhook handler entirely (route returns 200 + records to DLQ)
  WEBHOOK_HANDLER_STRIPE_DISABLED: process.env.FF_WEBHOOK_HANDLER_STRIPE_DISABLED === 'true',
  WEBHOOK_HANDLER_PAYPAL_DISABLED: process.env.FF_WEBHOOK_HANDLER_PAYPAL_DISABLED === 'true',

  // Disable verify-as-write (fall back to webhook-only)
  VERIFY_AS_WRITE_DISABLED: process.env.FF_VERIFY_AS_WRITE_DISABLED === 'true',

  // Disable team checkout (e.g., during a team-plan incident)
  TEAM_CHECKOUT_DISABLED: process.env.FF_TEAM_CHECKOUT_DISABLED === 'true',

  // Disable admin event publishers (during an incident producing spurious events)
  ADMIN_EVENT_PUBLISHERS_DISABLED: process.env.FF_ADMIN_EVENT_PUBLISHERS_DISABLED === 'true',

  // Disable the manual-retry button in admin (for incidents involving retries)
  ADMIN_INVOICE_RETRY_DISABLED: process.env.FF_ADMIN_INVOICE_RETRY_DISABLED === 'true',

  // Disable proactive emails (card-expiry, upcoming-renewal) during incident
  PROACTIVE_EMAILS_DISABLED: process.env.FF_PROACTIVE_EMAILS_DISABLED === 'true',
};
```

Each handler/cron/route checks the relevant flag at the top:

```ts
export async function POST(request: Request) {
  if (FEATURE_FLAGS.WEBHOOK_HANDLER_STRIPE_DISABLED) {
    // Record to DLQ for later replay; return 200
    const body = await request.text();
    await db.insert(webhookDlq).values({ provider: 'stripe', body, recordedAt: new Date() });
    return NextResponse.json({ received: true, outcome: 'flagged_off' });
  }
  // ... normal handler
}
```

Flag flip = env var change in Vercel + redeploy (~2 min). Faster than code-fix-and-deploy.

Document flag flips in incident timeline.

---

## Pattern 3 — Webhook DLQ for incident replay

When a webhook handler is flagged off (Pattern 2) or fails repeatedly, drop the raw payload into a DLQ for later replay:

```sql
CREATE TABLE webhook_dlq (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider      subscription_provider NOT NULL,
  body          text NOT NULL,
  headers       jsonb,
  reason        text,                    -- 'flagged_off' | 'parse_error' | 'persistent_error'
  recorded_at   timestamptz NOT NULL DEFAULT now(),
  replayed_at   timestamptz
);
CREATE INDEX webhook_dlq_unreplayed_idx ON webhook_dlq (recorded_at) WHERE replayed_at IS NULL;
```

After the incident is resolved, a one-shot replay script:

```ts
// scripts/replay-webhook-dlq.ts
async function replayDlq() {
  const rows = await db.query.webhookDlq.findMany({
    where: isNull(webhookDlq.replayedAt),
    orderBy: asc(webhookDlq.recordedAt),
  });
  for (const row of rows) {
    // Re-POST to the same webhook route as if Stripe sent it now
    // (You need to re-derive the signature OR bypass sig check during replay)
    await fetch(`${env.APP_URL}/api/${row.provider}/webhook?replay=true`, {
      method: 'POST',
      headers: { 'X-Replay-Token': env.REPLAY_TOKEN, ...JSON.parse(row.headers ?? '{}') },
      body: row.body,
    });
    await db.update(webhookDlq).set({ replayedAt: new Date() }).where(eq(webhookDlq.id, row.id));
  }
}
```

Replay route auth: a separate `REPLAY_TOKEN` env var so the operator (not a random attacker) can trigger replay.

---

## Pattern 4 — Per-row recovery

For data-corruption incidents (e.g., an UPDATE that affected 200 wrong rows), have a per-row recovery helper:

```ts
// src/lib/incident/recovery.ts
export async function recoverSubscription(params: {
  subscriptionId: string;
  toState: SubscriptionStatus;
  ticketId: string;
  authorizedBy: string;
}): Promise<void> {
  await db.transaction(async (tx) => {
    const sub = await tx.query.subscriptions.findFirst({
      where: eq(subscriptions.id, params.subscriptionId),
    });
    if (!sub) throw new Error(`subscription ${params.subscriptionId} not found`);

    // Snapshot current state for audit
    await tx.insert(complianceEvents).values({
      eventType: 'incident_recovery',
      actorId: params.authorizedBy,
      targetType: 'subscription',
      targetId: params.subscriptionId,
      metadata: {
        ticket: params.ticketId,
        snapshot_before: { status: sub.status, lastEventAt: sub.lastEventAt },
        target_state: params.toState,
      },
    });

    // Mutate. Note: bypass last_event_at gate intentionally — this IS a recovery action.
    await tx.update(subscriptions)
      .set({
        status: params.toState,
        lastEventAt: new Date(),  // mark as freshly authoritative
        updatedAt: new Date(),
      })
      .where(eq(subscriptions.id, params.subscriptionId));
  });
}
```

The pattern: every recovery action is logged with the operator + ticket + before/after snapshot. If the recovery is wrong, you can roll back from the audit log.

---

## Pattern 5 — Incident metadata on every commit during the incident

When committing fixes during an incident, prefix commit messages with the incident ID:

```
incident-2026-05-04-triple-charge: add cross-provider probe to Stripe checkout

Refs: bd-1m86f
Fixes: <postmortem>
```

This makes `git log` filterable for the incident later.

---

## Pattern 6 — Incident-only auth bypass (carefully)

Sometimes during an incident you need to do something normally blocked (e.g., issue a refund outside the normal window; manually transition a sub state). Build incident-only bypass:

```ts
// src/lib/incident/auth.ts
export async function requireIncidentAuthorization(params: {
  request: Request;
  incidentTicket: string;     // must match an open incident in the system
  capability: string;         // 'refund_outside_window' | 'manual_state_transition' | etc.
}): Promise<{ authorizedBy: string }> {
  // 1. User must be admin
  const user = await getCurrentUser(params.request);
  if (!user.isAdmin) throw new HttpError(403, 'admin_required');

  // 2. Incident must be open
  const incident = await db.query.incidents.findFirst({ where: eq(incidents.ticketId, params.incidentTicket) });
  if (!incident || incident.closedAt) throw new HttpError(403, 'no_open_incident');

  // 3. Capability must be in the incident's authorized capabilities
  if (!incident.authorizedCapabilities.includes(params.capability)) {
    throw new HttpError(403, 'capability_not_authorized_for_incident');
  }

  // 4. Log the authorization use
  await logSecurityEvent({
    type: 'incident_auth_bypass_used',
    severity: 'high',
    actor: { type: 'user', id: user.id },
    target: { type: 'incident', id: params.incidentTicket },
    details: { capability: params.capability },
  });

  return { authorizedBy: user.id };
}
```

The bypass is auditable; bounded in time (incident must be open); restricted to specific capabilities.

---

## Pattern 7 — Postmortem-driven test addition

After every incident, the test that pins the fix is named after the incident:

```ts
// __tests__/incidents/incident-2026-05-04-triple-charge.test.ts
describe('incident-2026-05-04-triple-charge regression', () => {
  test('cross-provider probe blocks Stripe checkout when PayPal sub exists', async () => {
    // Set up: user has active PayPal sub
    await createTestPayPalSub(userId);

    // Attempt: Stripe checkout
    const result = await POST('/api/stripe/create-checkout', { userId });

    // Assert: rejected with cross_provider_active_sub
    expect(result.status).toBe(409);
    expect(result.body.error).toBe('cross_provider_active_sub');
  });

  test('cross-provider probe queries OTHER provider, not just DB', async () => {
    // Set up: user has active PayPal sub at PROVIDER but DB says no (stale webhook)
    const paypalSubId = await createPayPalSubAtProviderOnly(userId);

    // Attempt: Stripe checkout
    const result = await POST('/api/stripe/create-checkout', { userId });

    // Assert: STILL rejected because probe queries PayPal directly
    expect(result.status).toBe(409);
  });
});
```

The test name carries the trace. Future engineers see "incident-2026-05-04-triple-charge" and can grep for the postmortem.

---

## Pattern 8 — Customer-impact tally

For incidents that affected real customers, maintain a tally:

```sql
CREATE TABLE incident_customer_impact (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id     text NOT NULL,
  user_id         uuid REFERENCES users(id),
  org_id          uuid REFERENCES organizations(id),
  impact_type     text NOT NULL,       -- 'overcharged' | 'access_blocked' | 'spurious_email' | 'data_visible'
  impact_value    numeric,             -- $$ if overcharged; minutes if access_blocked
  remediation     text,                -- 'refunded' | 'access_restored' | 'apology_email_sent' | 'support_contacted'
  remediation_at  timestamptz,
  recorded_at     timestamptz NOT NULL DEFAULT now()
);
```

Use during the incident to track who's affected; use after to confirm everyone's been remediated.

---

## Pattern 9 — Status page integration

If the user has a status page (statuspage.io, Atlassian, instatus, BetterStack, hyperping), wire incident lifecycle to it:

```ts
// On incident detection
await statusPageClient.createIncident({
  title: 'Investigating billing issue',
  status: 'investigating',
  components: ['billing'],
});

// On containment
await statusPageClient.updateIncident(incidentId, {
  status: 'identified',
  message: 'We identified the cause; working on a fix.',
});

// On resolution
await statusPageClient.updateIncident(incidentId, {
  status: 'resolved',
  message: 'Resolved. Postmortem to follow.',
});
```

Status page updates are NOT optional for customer-visible incidents; they're how customers know you're aware.

---

## Pattern 10 — Postmortem retention + searchability

Postmortems live at `<project>/docs/postmortems/<date>-<short-name>.md`. Build an index:

```ts
// scripts/postmortem-index.ts
const postmortems = await glob('docs/postmortems/*.md');
const index = postmortems.map(p => parsePostmortem(p));
writeFileSync('docs/postmortems/INDEX.md', renderIndex(index));
```

The index is searchable by:
- Date.
- Severity.
- Failure class.
- Root cause keyword.
- Action item status.

When a NEW incident happens, the on-call engineer searches the index BEFORE diving in. Often the same class has been seen before; the prior postmortem has the fix recipe.

---

## Polish Bar checks for B140

- [ ] Per-class containment helpers exist for the top 5 failure classes.
- [ ] Kill-switch flags for high-blast-radius code paths.
- [ ] `webhook_dlq` table + replay script for flagged-off webhooks.
- [ ] Per-row recovery helpers with audit logging.
- [ ] Incident-only auth bypass with explicit capability authorization.
- [ ] Every incident fix has a `__tests__/incidents/incident-<date>-<name>.test.ts`.
- [ ] Customer-impact tally table.
- [ ] Status page wired to incident lifecycle.
- [ ] Postmortem index searchable.
- [ ] On-call doc references the containment helpers (not raw SQL / raw API).
- [ ] Containment helpers tested in staging at least quarterly (drill).

---

## Common B140 mistakes

- **Containment via raw SQL under pressure.** Operator typoes a query; data corruption worse than original incident.
- **No kill switches.** Only fix is "deploy the bug fix"; takes 15 min instead of 2.
- **DLQ exists but no replay script.** Webhooks lost forever after the incident.
- **Recovery actions don't log.** Audit trail is broken; auditor questions resolution.
- **Incident auth bypass with no expiration.** Bypass token lives forever; future operator (or attacker) uses it.
- **Postmortems written but not indexed.** Same incident class recurs; nobody finds the prior postmortem.
- **No status page update.** Customers blast support with "is X down?" queries.
- **Containment helpers untested.** Operator first-uses them under pressure; helper has a bug; incident worsens.
- **Customer-impact tally not built.** Random remediation; some customers get refunds, some don't, support inconsistency.
