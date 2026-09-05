# Bundle B45 — Admin Operations Surface

> **Where this comes from.** Cross-reference with `/admin-page-for-nextjs-sites`. Plus the operational reality that operators need a UI for billing actions; raw SQL under pressure produces incidents.

The admin UI is what stands between operators and raw database / provider API access. Without it, every billing operation is a `psql` command typed under stress. With it, operations are auditable, bounded, and recoverable.

---

## Pattern 1 — The admin route hierarchy

```
/admin
├── /billing
│   ├── /subscriptions/<id>           ← view + actions per sub
│   ├── /customers/<id>               ← user's billing state aggregated
│   ├── /events/<id>                  ← payment_event detail + replay
│   ├── /disputes                     ← active disputes queue
│   ├── /refunds                      ← refund queue + approval
│   ├── /reconciliation               ← reconciliation health + manual trigger
│   ├── /metrics                      ← MRR / churn / health snapshots
│   └── /provider-config              ← live provider catalog audit results
├── /incidents                        ← incident dashboard
├── /audit-log                        ← every admin action
└── /support                          ← support ticket integration
```

Each route has:
- Server-side auth check (admin role required).
- Audit-log on every action.
- Rate limit (operators don't need to fire 1000 actions/min).
- CSRF + browser-bound session.

---

## Pattern 2 — Every action is auditable

Every button click that mutates state writes to `audit_log`:

```sql
CREATE TABLE audit_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES users(id),     -- the admin who did it
  event_type  text NOT NULL,                  -- 'admin.refund_issued', 'admin.subscription_cancelled', etc.
  event_data  jsonb NOT NULL,                 -- structured details
  ip_address  inet,
  user_agent  text,
  request_id  text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_log_user_id_idx ON audit_log (user_id, created_at DESC);
CREATE INDEX audit_log_event_type_idx ON audit_log (event_type, created_at DESC);
```

Every admin route uses a wrapper:

```ts
async function requireAdminAndAudit<T>(
  request: Request,
  eventType: string,
  action: (admin: User) => Promise<{ result: T; eventData: unknown }>,
): Promise<T> {
  const admin = await requireAdmin(request);
  const { result, eventData } = await action(admin);
  await db.insert(auditLog).values({
    userId: admin.id,
    eventType,
    eventData,
    ipAddress: getClientIp(request),
    userAgent: request.headers.get('user-agent'),
    requestId: request.headers.get('x-request-id'),
  });
  return result;
}
```

The audit_log is the SOC2 evidence for "admin actions are tracked."

---

## Pattern 3 — Refund button (operator-facing)

The most-clicked admin action. Wraps `incidentRefund(...)` (B140 Pattern 1):

```tsx
function RefundButton({ chargeId, amount, customerEmail }: Props) {
  const [reason, setReason] = useState('');
  const [confirmed, setConfirmed] = useState(false);

  const onSubmit = async () => {
    if (reason.length < 10) return alert('Reason required (min 10 chars)');
    if (!confirmed) return alert('Confirm to proceed');

    const res = await fetch('/api/admin/billing/refund', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chargeId, reason, ticketId }),
    });
    const data = await res.json();
    if (data.ok) toast.success(`Refund issued: ${data.refundId}`);
    else toast.error(`Refund failed: ${data.error}`);
  };

  return (
    <Modal title="Issue Refund">
      <div className="text-sm text-amber-700 mb-2">
        ⚠ This action is irreversible. Funds will return to {customerEmail} within 5-10 business days.
      </div>
      <input placeholder="Refund reason (required, min 10 chars)" value={reason} onChange={...} />
      <input placeholder="Support ticket ID (required)" value={ticketId} onChange={...} />
      <Checkbox checked={confirmed} onChange={setConfirmed}>
        I confirm refund of ${amount / 100} to {customerEmail}.
      </Checkbox>
      <Button onClick={onSubmit} disabled={!confirmed || reason.length < 10}>
        Issue Refund
      </Button>
    </Modal>
  );
}
```

Server side:

```ts
// /api/admin/billing/refund/route.ts
export async function POST(request: Request) {
  return requireAdminAndAudit(request, 'admin.refund_issued', async (admin) => {
    const { chargeId, reason, ticketId } = await request.json();

    if (!reason || reason.length < 10) throw new HttpError(400, 'reason_too_short');
    if (!ticketId) throw new HttpError(400, 'ticket_required');

    const result = await incidentRefund({
      chargeId,
      reason: 'incident_remediation',
      ticketId,
      authorizedBy: admin.id,
    });

    return {
      result: { ok: true, refundId: result.refundId },
      eventData: { chargeId, reason, ticketId, refundId: result.refundId },
    };
  });
}
```

Two layers of confirmation (modal + checkbox); two pieces of justification (reason + ticket); audit log on every call.

---

## Pattern 4 — Manual invoice retry button

Wraps `retryLatestStripeInvoice(...)` from B70 § 33. The 4-guard logic prevents over-charges; the button just triggers it.

UI shows the 4 guards' results so operator can understand WHY a retry was rejected:

```tsx
function RetryInvoiceButton({ subscriptionId }: Props) {
  // ... fetch subscription state
  // ... fetch latest invoice via /api/admin/billing/preview-retry
  // ... show: invoice status, attempt count, next scheduled retry, amount
  return (
    <div>
      <h3>Retry latest invoice</h3>
      <dl>
        <dt>Subscription status</dt><dd>{sub.status} {sub.status === 'past_due' ? '✓ eligible' : '✗ ineligible'}</dd>
        <dt>Latest invoice</dt><dd>{invoice.id} ({invoice.status})</dd>
        <dt>Attempt count</dt><dd>{invoice.attempt_count} / 6 max</dd>
        <dt>Next scheduled retry</dt><dd>{invoice.next_payment_attempt ? formatTime(invoice.next_payment_attempt) : 'none'}</dd>
        <dt>Amount</dt><dd>${invoice.amount_due / 100}</dd>
      </dl>
      <Button disabled={!eligible} onClick={onRetry}>Retry invoice now</Button>
      {!eligible && <p>Reason: {ineligibleReason}</p>}
    </div>
  );
}
```

---

## Pattern 5 — Manual webhook event replay

For investigating stuck events:

```tsx
function ReplayEventButton({ paymentEventId }: Props) {
  const [overrideReason, setOverrideReason] = useState('');
  const [forced, setForced] = useState(false);
  // ... fetch event details
  return (
    <div>
      <h3>Replay payment event</h3>
      <dl>
        <dt>Event ID</dt><dd>{event.id}</dd>
        <dt>Provider</dt><dd>{event.provider}</dd>
        <dt>Type</dt><dd>{event.event_type}</dd>
        <dt>Created</dt><dd>{event.created_at}</dd>
        <dt>Age</dt><dd>{ageDays} days</dd>
        <dt>Already processed?</dt><dd>{event.processed_at ? 'YES' : 'NO'}</dd>
        <dt>Last error</dt><dd>{event.last_error}</dd>
      </dl>
      {(ageDays > 7 || event.processed_at) && (
        <>
          <input placeholder="Override reason (required)" value={overrideReason} ... />
          <Checkbox checked={forced} onChange={setForced}>
            I confirm this replay; I understand this may cause duplicate side effects.
          </Checkbox>
        </>
      )}
      <Button onClick={onReplay} disabled={...}>Replay</Button>
    </div>
  );
}
```

Maps to admin-retry-with-overrides per B50 § Admin retry path.

---

## Pattern 6 — Subscription state inspector

Per-customer aggregated view:

```tsx
function CustomerBillingPage({ userId }: Props) {
  // ... fetch user, subscriptions, recent payment_events, recent emails, dispute history
  return (
    <Page>
      <Section title="User"><DenormalizedSubscriptionStatus user={user} /></Section>
      <Section title="Subscriptions">
        {subscriptions.map(s => (
          <SubscriptionCard sub={s}>
            <CancelButton subId={s.id} />
            <RetryInvoiceButton subId={s.id} />
            <ChangeStatusButton subId={s.id} />  {/* gated; rare; audit-heavy */}
          </SubscriptionCard>
        ))}
      </Section>
      <Section title="Recent payment events">
        {paymentEvents.map(e => (
          <EventRow event={e}>
            <ReplayEventButton paymentEventId={e.id} />
            <ViewPayloadButton paymentEventId={e.id} />  {/* gated; PII-redacted preview */}
          </EventRow>
        ))}
      </Section>
      <Section title="Recent emails sent"><EmailLog userId={userId} /></Section>
      <Section title="Disputes"><DisputeList userId={userId} /></Section>
      <Section title="Refunds"><RefundList userId={userId} /></Section>
    </Page>
  );
}
```

---

## Pattern 7 — Reconciliation health dashboard

Live view of:
- Backlog count (`payment_events WHERE processed_at IS NULL`).
- Oldest pending event age.
- Reconciliation freshness (per § 64 / B100).
- Recent cron run summaries.
- Per-event-type retry counts.

With actions:
- "Trigger reconciliation cron now" (rate-limited).
- "Trigger provider-reconciliation cron now" (rate-limited).
- "View terminal-stuck events" (paginated; counts only by default).

```tsx
function ReconciliationHealth() {
  // ... fetch /api/admin/billing/reconciliation-health
  return (
    <Dashboard>
      <Tile title="Backlog">{telemetry.backlog_count}</Tile>
      <Tile title="Oldest pending" provenance={telemetry.provenance}>
        {formatAge(telemetry.oldest_pending_event_age)}
      </Tile>
      <Tile title="Last reconciliation">{formatRelative(telemetry.last_reconciliation_at)}</Tile>
      <Button onClick={triggerReconciliationCron}>Trigger reconciliation now</Button>
    </Dashboard>
  );
}
```

---

## Pattern 8 — MRR + financial dashboard

Provenance-aware. Renders never as "$0" if data unavailable.

```tsx
function MrrDashboard() {
  const { data } = useSwr('/api/admin/billing/mrr-snapshot', fetcher);

  if (!data || data.provenance === 'unavailable') {
    return <ErrorTile>MRR data unavailable. Reconciliation may be lagging. <RefreshButton /></ErrorTile>;
  }

  return (
    <Dashboard>
      <Tile title="Total MRR" provenance={data.provenance} computedAt={data.computedAt}>
        ${data.totalMrr.toFixed(2)}
      </Tile>
      <Tile title="ARR (×12)">${data.arr.toFixed(2)}</Tile>
      <Tile title="Stripe MRR">${data.byProvider.stripe.totalMrr.toFixed(2)}
        {data.byProvider.stripe.source !== 'live' && <ProvenanceWarning />}
      </Tile>
      <Tile title="PayPal MRR">${data.byProvider.paypal.totalMrr.toFixed(2)}</Tile>
      <Tile title="Active count">{data.totalCount}</Tile>
      {data.qualityNote && <NoticeBar>{data.qualityNote}</NoticeBar>}
    </Dashboard>
  );
}
```

---

## Pattern 9 — Audit log viewer

Operators need to verify their own actions are recorded:

```tsx
function AuditLogPage() {
  // Filterable by: admin email, event type, target type, time range
  return (
    <Table>
      <THead><tr><th>When</th><th>Admin</th><th>Action</th><th>Target</th><th>Details</th></tr></THead>
      <TBody>
        {logs.map(l => (
          <tr key={l.id}>
            <td>{l.created_at}</td>
            <td>{l.user.email}</td>
            <td><EventTypeBadge>{l.event_type}</EventTypeBadge></td>
            <td>{renderTarget(l.event_data)}</td>
            <td><JsonViewer data={sanitize(l.event_data)} /></td>
          </tr>
        ))}
      </TBody>
    </Table>
  );
}
```

For SOC2: this view is also the auditor's view; sanitization makes it safe to share.

---

## Pattern 10 — Self-attack helper (Sev0 control)

Per B50 + ADMIN security: explicit `admin_self_target_blocked` event. The admin UI prevents an admin from running destructive actions ON THEIR OWN account:

```ts
async function refundCharge(adminUserId, chargeId) {
  const charge = await stripe.charges.retrieve(chargeId);
  const targetUserId = await resolveUserFromCharge(charge);
  if (targetUserId === adminUserId) {
    await logSecurityEvent({
      type: 'admin_self_target_blocked',
      severity: 'critical',
      actor: { type: 'user', id: adminUserId },
      target: { type: 'user', id: targetUserId },
      details: { action: 'refund', chargeId },
    });
    throw new HttpError(403, 'admin_self_target_not_allowed');
  }
  // ... proceed
}
```

Why: insider threat. Don't let an admin refund themselves silently. Forces them to escalate to ANOTHER admin → 4-eye principle.

---

## Pattern 11 — Break-glass emergency access

For extreme cases (compromised admin account, primary admin unreachable), there's a documented break-glass:

```ts
// `admin_break_glass` event — Sev0; pages CTO + COO; auto-rotates the key after use
async function breakGlassRefund(...) {
  await logSecurityEvent({
    type: 'admin_break_glass',
    severity: 'critical',
    ...
  });
  // ... proceed
  await rotateBreakGlassKey();  // single-use
  await pageCTO();
  await pageCOO();
}
```

The break-glass is documented in `docs/runbooks/break-glass.md`. It's not a "convenience" path; it's the last resort.

---

## Pattern 12 — Admin UI as the implementation target for B140 helpers

B140 (Incident Response) defines the helpers (`incidentRefund`, `incidentSuspendStripeSub`, `recoverSubscription`, etc.). B45 is the UI that EXPOSES those helpers.

Don't duplicate logic in the UI — the helpers are the single source of truth. The UI is the input/output surface.

---

## Polish Bar checks for B45

- [ ] Admin role auth check on every route.
- [ ] `audit_log` row on every mutating action.
- [ ] Refund button: 2-step confirmation + reason + ticket.
- [ ] Manual invoice retry button: 4-guard preview + button-disable on ineligible.
- [ ] Manual webhook event replay: age + processed-state checks; override-reason gated.
- [ ] Customer billing page aggregates: subs + events + emails + disputes + refunds.
- [ ] Reconciliation health dashboard with manual-trigger buttons (rate-limited).
- [ ] MRR dashboard renders provenance correctly; never `$0` for `unavailable`.
- [ ] Audit log viewer with filters; sanitized for sharing.
- [ ] `admin_self_target_blocked` enforced.
- [ ] Break-glass documented + audit-logged + key rotated after use.
- [ ] All buttons wrap B140 helpers, not raw SQL/API.

---

## Common B45 mistakes

- **Action without audit.** Operator clicks button; no audit; SOC2 fails.
- **Action without confirmation.** Click-rage refunds.
- **Self-target allowed.** Admin refunds own subscription; insider-threat exposure.
- **Raw SQL exposed via UI.** Operator types under pressure; data corruption.
- **Provenance ignored.** MRR tile shows $0 during outage; CEO pings engineering at 2am.
- **Buttons without rate limits.** Operator scripts the UI; thousands of refunds in seconds.
- **No break-glass procedure documented.** When primary admin is unreachable, business halts.
- **Admin UI exposed publicly.** Should be VPN / IP-allowlisted at minimum.
- **Audit log mutable.** Append-only constraint missing; insider can hide actions.
- **No 4-eye for high-value actions.** Refunds > $X should require manager approval in-product.
