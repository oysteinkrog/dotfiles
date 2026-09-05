# Bundle B90 — Reliability Machinery

> **Where this comes from.** § 46–§ 54 of the source guide.

This is the "Layer 2 / 3 catches Layer 1's silent failures" bundle. Without it, a single missed webhook propagates to a customer support ticket. With it, missed webhooks are detected within minutes and reconciled.

---

## Orphan-cancel queue (post-deletion ghost subs) — § 46

When a user is GDPR-deleted (or the user account is closed for any reason), their PROVIDER-side subscription doesn't auto-cancel. Without an orphan-cancel queue, you have a "ghost sub" still billing a card whose owner no longer exists in your DB.

### The race that motivated it

Pre-fix:
```ts
async function deleteUser(userId: string) {
  await db.transaction(async (tx) => {
    await tx.delete(users).where(eq(users.id, userId));
  });
  // BUG: provider cancel happens AFTER delete tx
  await stripe.subscriptions.cancel(userSub.externalId).catch(err => {
    logger.error({ err, userId }, 'Failed to cancel sub during user delete');
  });
}
```

If the cancel fails (Stripe outage, network blip, anything), the user is gone but the sub keeps billing. There's no record we needed to retry.

Post-fix:
```ts
async function deleteUser(userId: string) {
  const subs = await db.transaction(async (tx) => {
    // Read user's subs INSIDE tx
    const subs = await tx.query.subscriptions.findMany({
      where: and(eq(subscriptions.userId, userId), inArray(subscriptions.status, ['active', 'past_due', 'paused_for_org'])),
    });

    // Persist orphan-cancel rows BEFORE deleting user
    for (const sub of subs) {
      await tx.insert(orphanSubscriptionCancels).values({
        provider: sub.provider,
        externalId: sub.externalId,
        userId,
      });
    }

    // Now delete
    await tx.delete(users).where(eq(users.id, userId));
    return subs;
  });

  // Best-effort inline cancel
  for (const sub of subs) {
    try {
      await cancelProviderSub(sub.provider, sub.externalId);
      await db.update(orphanSubscriptionCancels).set({ resolvedAt: new Date() }).where(eq(orphanSubscriptionCancels.externalId, sub.externalId));
    } catch (err) {
      logger.warn({ err, sub }, 'Inline orphan cancel failed; cron will retry');
    }
  }
}
```

The retry cron (`/api/cron/retry-orphan-sub-cancels`) iterates `WHERE resolved_at IS NULL AND next_retry_at <= now()`, calls the provider, and marks resolved on success.

Bead trail: `bd-bfwcy.6 / BILLING-M5`. Real customer ticket: a deleted user kept getting charged for 3 months because the cancel call failed silently.

---

## Webhook reconciliation core + per-event claim lease — § 47

The reconciliation cron drains `payment_events WHERE processed_at IS NULL AND age > 5m`. Per-event claim lease prevents two cron isolates processing the same row.

```ts
// /api/cron/webhook-reconciliation (every 5 min)
async function webhookReconciliationCron() {
  await acquireAdvisoryLock('webhook_reconciliation', async () => {
    const candidates = await db.query.paymentEvents.findMany({
      where: and(
        isNull(paymentEvents.processedAt),
        lt(paymentEvents.createdAt, new Date(Date.now() - 5 * 60 * 1000)),
        lt(paymentEvents.retryCount, MAX_RETRY_COUNT),  // 5
      ),
      orderBy: asc(paymentEvents.createdAt),
      limit: 50,  // bounded scan
    });

    for (const event of candidates) {
      // Per-event claim lease: increment retry_count BEFORE processing
      // so a concurrent invocation doesn't double-process
      const claimResult = await db.update(paymentEvents)
        .set({ retryCount: sql`${paymentEvents.retryCount} + 1`, lastError: null })
        .where(and(
          eq(paymentEvents.id, event.id),
          eq(paymentEvents.retryCount, event.retryCount),  // optimistic concurrency
        ))
        .returning({ id: paymentEvents.id });
      if (claimResult.length === 0) continue;  // someone else claimed it

      try {
        await processPaymentEvent(event);
        await db.update(paymentEvents)
          .set({ processedAt: new Date(), reconciledAt: new Date() })
          .where(eq(paymentEvents.id, event.id));
      } catch (err) {
        await db.update(paymentEvents)
          .set({ lastError: err.message })
          .where(eq(paymentEvents.id, event.id));

        // Per-event terminal alarm
        if (event.retryCount + 1 >= MAX_RETRY_COUNT) {
          await fireTerminalEventAlert(event, err);
        }
      }
    }
  });
}
```

### Per-event-type retry caps (§ 29.8 anti-pattern fix)

The shared `retry_count` was a mistake. A high-failure-rate event type (e.g., a malformed `BILLING.PLAN.UPDATED` we don't care about) maxed the counter for its whole class. Now retry caps are per-event-type at the handler level:

```ts
async function processPaymentEvent(event: PaymentEventRow) {
  const cap = RETRY_CAPS_BY_EVENT_TYPE[event.eventType] ?? MAX_RETRY_COUNT;
  if (event.retryCount >= cap) {
    // Mark as terminal but don't keep retrying
    await db.update(paymentEvents).set({ processedAt: new Date(), reconciledAt: new Date() }).where(eq(paymentEvents.id, event.id));
    return;
  }
  // Dispatch by event_type to handler
  await dispatchHandler(event);
}

const RETRY_CAPS_BY_EVENT_TYPE: Record<string, number> = {
  'BILLING.PLAN.UPDATED': 1,            // we don't care; one shot then drop
  'invoice.payment_succeeded': 5,       // care a lot
  'charge.refunded': 5,                 // care a lot
  // default: MAX_RETRY_COUNT (5)
};
```

---

## Webhook-staleness alarm + terminal-stuck digest — § 48

```ts
// /api/cron/webhook-staleness (every 5 min)
async function webhookStalenessAlarm() {
  await acquireAdvisoryLock('webhook_staleness_alarm', async () => {
    const stuck = await db.query.paymentEvents.findMany({
      where: and(
        isNull(paymentEvents.processedAt),
        lt(paymentEvents.createdAt, new Date(Date.now() - 10 * 60 * 1000)),  // > 10 min
      ),
      limit: 100,
    });
    if (stuck.length === 0) return;

    // Dedupe within 60-min window (don't spam the operator)
    const lastAlertSent = await getRedisValue('staleness_last_alert');
    if (lastAlertSent && Date.now() - parseInt(lastAlertSent) < 60 * 60 * 1000) return;

    await createEmailJob({
      type: 'admin_ops_alert',
      recipient: env.ADMIN_EMAIL,
      payload: {
        subject: `Webhook staleness: ${stuck.length} events stuck > 10min`,
        eventIds: stuck.slice(0, 20).map(e => `${e.provider}:${e.eventId}`),
      },
      priority: 30,
    });
    await setRedisValue('staleness_last_alert', String(Date.now()), { ex: 3600 });

    // Terminal-stuck digest re-pages every 24h
    const terminalStuck = stuck.filter(e => e.retryCount >= MAX_RETRY_COUNT);
    if (terminalStuck.length > 0) {
      const lastTerminal = await getRedisValue('staleness_last_terminal');
      if (!lastTerminal || Date.now() - parseInt(lastTerminal) > 24 * 60 * 60 * 1000) {
        await createEmailJob({
          type: 'admin_ops_alert',
          recipient: env.ADMIN_EMAIL,
          payload: { subject: `${terminalStuck.length} payment_events terminally stuck`, ... },
          priority: 20,
        });
        await setRedisValue('staleness_last_terminal', String(Date.now()), { ex: 86400 });
      }
    }
  });
}
```

---

## Provider-authoritative reconciliation sweep — § 49

The reconciliation cron (above) drains OUR `payment_events` rows. The provider-sweep cron (every 6h) reads from THE PROVIDER directly to catch silent webhook losses (Marco Fanti's `bd-1ug5i`).

```ts
// /api/cron/provider-reconciliation (every 6h)
async function providerReconciliationCron() {
  await acquireAdvisoryLock('provider_reconciliation', async () => {
    // Stripe side
    const cursor = await getCursorValue('provider_recon_stripe_cursor');
    const stripeSubs = await stripe.subscriptions.list({
      status: 'active',
      limit: 100,
      starting_after: cursor,
    });
    for (const stripeSub of stripeSubs.data) {
      const dbSub = await db.query.subscriptions.findFirst({
        where: and(eq(subscriptions.provider, 'stripe'), eq(subscriptions.externalId, stripeSub.id)),
      });
      if (!dbSub || dbSub.status !== mapStripeStatus(stripeSub.status)) {
        // Drift! Reconcile via canonical writer
        await updateSubscriptionStatus({
          provider: 'stripe',
          externalSubscriptionId: stripeSub.id,
          customerId: stripeSub.customer as string,
          status: mapStripeStatus(stripeSub.status),
          currentPeriodStart: new Date(stripeSub.current_period_start * 1000),
          currentPeriodEnd: new Date(stripeSub.current_period_end * 1000),
          eventAt: new Date(),  // use current time; provider state is authoritative now
        });
        await emitDriftAlert({ provider: 'stripe', externalId: stripeSub.id, dbStatus: dbSub?.status, providerStatus: stripeSub.status });
      }
    }
    if (stripeSubs.has_more) {
      await setCursorValue('provider_recon_stripe_cursor', stripeSubs.data[stripeSubs.data.length - 1].id);
    } else {
      await setCursorValue('provider_recon_stripe_cursor', null);  // restart at top
    }

    // PayPal side: similar pattern using PayPal's /v1/billing/subscriptions list
  });
}
```

The `emitDriftAlert` is non-blocking — log + bump a metric; only email if drift count exceeds a threshold.

---

## Daily billing integrity audit (the backstop) — § 50

Daily backstop. Lists billable subs grouped by email; alerts on any user with > 1.

```ts
// /api/cron/billing-integrity-audit (daily)
async function billingIntegrityAudit() {
  const result = await db.execute(sql`
    SELECT u.email, count(*) as count, array_agg(s.id) as sub_ids
    FROM users u
    JOIN subscriptions s ON s.user_id = u.id
    WHERE s.status IN ('active', 'past_due')
      AND ${analyticsExclusions.notExcluded(u.email)}
    GROUP BY u.email
    HAVING count(*) > 1
  `);
  for (const row of result.rows) {
    await createEmailJob({
      type: 'admin_ops_alert',
      recipient: env.ADMIN_EMAIL,
      payload: { subject: `Integrity audit: ${row.email} has ${row.count} active subs`, sub_ids: row.sub_ids },
      priority: 25,
    });
    await logComplianceEvent({
      eventType: 'integrity_audit_duplicate_subs',
      target: { type: 'user_email', id: row.email },
      metadata: { sub_ids: row.sub_ids, count: row.count },
    });
  }
}
```

This is the Tom-Hunter-class backstop: if everything else missed it, the daily audit catches it within 24h.

---

## Cron defenses — advisory locks, bounded scans, dry-run — § 51

The `acquireAdvisoryLock` helper:

```ts
// src/lib/db/advisory-lock.ts
export async function acquireAdvisoryLock<T>(
  lockName: string,
  fn: () => Promise<T>,
): Promise<T | null> {
  const lockKey = createHash('sha256').update(lockName).digest().readBigInt64BE(0);

  // Reserve a connection so the lock+work happen on the same conn
  const conn = await pgPool.reserve();
  try {
    const result = await conn.query<{ acquired: boolean }>('SELECT pg_try_advisory_lock($1) as acquired', [lockKey]);
    if (!result.rows[0].acquired) {
      logger.info({ lockName }, 'Advisory lock not acquired (another isolate is running)');
      return null;
    }
    try {
      return await fn();
    } finally {
      await conn.query('SELECT pg_advisory_unlock($1)', [lockKey]);
    }
  } finally {
    conn.release();   // CRITICAL — must release in finally
  }
}
```

### The famous `finally { conn.release() }` mistake (failure #8 in source guide)

If you forget the `finally`, the reserved connection is held forever (until process restart). Pool exhausts under repeated cron invocations.

### Bounded scans

- Reconciliation: `LIMIT 50`
- Verify-as-write reconciliation: `LIMIT 100`
- Dunning: `LIMIT 5000`
- Card-expiry: `LIMIT 1000` per cron tick (re-runs daily)

The bound matches the per-run wall-time budget. A Vercel cron with 300s timeout shouldn't try to process 10000 rows in one tick.

### Dry-run mode for destructive crons

Crons that suspend / cancel / refund users should support `?dryRun=true`:

```ts
async function dunningCron(req: Request) {
  const dryRun = new URL(req.url).searchParams.get('dryRun') === 'true';
  // ... compute what would happen
  if (dryRun) {
    return NextResponse.json({ wouldSuspend: candidates.map(c => c.userId), wouldEmail: ... });
  }
  // actually execute
}
```

Use `?dryRun=true` during testing + before production rollout of any new cron.

---

## Email queue priority + failsafe escalation — § 52

The email queue table (B10) has `priority smallint` and `(priority, next_retry_at, created_at)` index. The processor:

```ts
// /api/cron/email-queue (every 1 min)
async function emailQueueCron() {
  await acquireAdvisoryLock('email_queue', async () => {
    const jobs = await db.query.emailJobs.findMany({
      where: and(
        eq(emailJobs.status, 'queued'),
        lt(emailJobs.nextRetryAt, new Date()),
      ),
      orderBy: [asc(emailJobs.priority), asc(emailJobs.nextRetryAt), asc(emailJobs.createdAt)],
      limit: 100,
    });
    for (const job of jobs) {
      try {
        await sendViaResend(job);
        await db.update(emailJobs).set({ status: 'sent', sentAt: new Date() }).where(eq(emailJobs.id, job.id));
      } catch (err) {
        const newRetry = job.retryCount + 1;
        if (newRetry >= MAX_EMAIL_RETRIES) {
          await db.update(emailJobs).set({ status: 'dlq', lastError: err.message }).where(eq(emailJobs.id, job.id));
          await db.insert(emailDlq).values({ ...job, lastError: err.message });
        } else {
          await db.update(emailJobs).set({
            retryCount: newRetry,
            nextRetryAt: new Date(Date.now() + Math.pow(2, newRetry) * 60 * 1000),  // exp backoff
            lastError: err.message,
          }).where(eq(emailJobs.id, job.id));
        }
      }
    }

    // Failsafe sweep — DLQ entries > 30 min trigger summary via OPS_FAILSAFE_EMAIL
    await failsafeSweep();
  });
}

async function failsafeSweep() {
  const dlqOldEnough = await db.query.emailDlq.findMany({
    where: and(
      ilike(emailDlq.type, 'billing_%'),
      lt(emailDlq.insertedAt, new Date(Date.now() - 30 * 60 * 1000)),
    ),
  });
  if (dlqOldEnough.length === 0) return;

  // Bypass marker prevents double-summary
  const bypassKey = `failsafe_summary_${dlqOldEnough.map(j => j.id).sort().join(',')}`;
  if (await wasSummarySent(bypassKey)) return;

  // Send DIRECT (not via queue) — the queue is what's broken
  await sendDirectViaResend({
    to: env.OPS_FAILSAFE_EMAIL,  // DIFFERENT INBOX from ADMIN_EMAIL
    subject: `[FAILSAFE] ${dlqOldEnough.length} billing alerts in DLQ`,
    body: dlqOldEnough.map(j => `${j.type}: ${j.lastError}`).join('\n'),
  });
  await markSummarySent(bypassKey);
}
```

### Why a different inbox for `OPS_FAILSAFE_EMAIL`

The original failure mode (`bd-ja8c0 / Billing-H1`): Resend was down. ALL emails to ADMIN_EMAIL failed. Including the DLQ alert. Including the alert about the DLQ alert failing.

Fix: `OPS_FAILSAFE_EMAIL` is a different mailbox at a different domain (e.g., a Gmail backup), reached via a direct send (not the queue). Even when the queue itself is broken, the failsafe lands.

---

## Test-fixture exclusion across analytics — § 53

The single canonical exclusions module:

```ts
// src/lib/analytics/exclusions.ts
const EXCLUDED_DOMAINS = ['example.test', 'example.com', 'test.local'];
const EXCLUDED_PREFIXES = ['test_', 'qa_', 'ci_'];

export const analyticsExclusions = {
  // SQL fragment for use in WHERE clauses
  sqlFragment: sql`(NOT (
    email LIKE ANY(${EXCLUDED_PREFIXES.map(p => `${p}%`)})
    OR email LIKE ANY(${EXCLUDED_DOMAINS.map(d => `%@${d}`)})
  ))`,

  // Predicate for code-side filtering
  isExcluded: (email: string): boolean => {
    return EXCLUDED_PREFIXES.some(p => email.startsWith(p))
        || EXCLUDED_DOMAINS.some(d => email.endsWith(`@${d}`));
  },

  // Composite SQL helper for joining `users` table
  joinClause: () => sql`AND ${analyticsExclusions.sqlFragment}`,
};
```

EVERY cron / publisher / analytics read imports this. The drift-guard test (B110) lists every cron and asserts the import.

---

## Admin events — analytics-aware activity feed — § 54

Two-gate publisher: previousStatus AND analytics exclusion.

```ts
// src/lib/events/admin-event-publishers.ts
export async function publishSubscriptionEvent(params: {
  userId: string;
  email: string;
  previousStatus: SubscriptionStatus | null;
  currentStatus: SubscriptionStatus;
  provider: SubscriptionProvider;
}): Promise<void> {
  // Gate 1: analytics exclusion
  if (analyticsExclusions.isExcluded(params.email)) return;

  // Gate 2: previousStatus → was this a real transition or noise?
  const becameActive = params.previousStatus !== 'active' && params.currentStatus === 'active';
  const becameCancelled = params.previousStatus === 'active' && params.currentStatus === 'cancelled';
  // (other transitions...)

  if (becameActive) {
    await publishAdminEvent({ type: 'new_subscriber', ...params });
  } else if (becameCancelled) {
    await publishAdminEvent({ type: 'subscription_cancelled', ...params });
  }
  // (etc.)
}
```

Without gate 1, the activity feed shows test signups. Without gate 2, every UPDATE on a subscription publishes "new subscriber!" even when the sub was already active.

---

## Polish Bar checks for B90

- [ ] `orphan_subscription_cancels` table exists; rows inserted INSIDE delete tx.
- [ ] Retry cron drains orphan-cancels with bounded retries + terminal digest.
- [ ] `webhook-reconciliation` cron uses per-event claim lease (optimistic concurrency on retry_count).
- [ ] Per-event-type retry caps (no shared MAX_RETRY_COUNT for everything).
- [ ] `webhook-staleness` cron fires on > 10min stuck rows; deduped within 60min.
- [ ] Terminal-stuck digest re-pages every 24h.
- [ ] `provider-reconciliation` cron sweeps Stripe + PayPal every 6h with cursor pagination.
- [ ] `billing-integrity-audit` cron daily; alerts on >1 active sub per email.
- [ ] `acquireAdvisoryLock` reserves a connection AND releases in `finally`.
- [ ] Every cron has bounded scan (`LIMIT N`) matching its wall-time budget.
- [ ] Destructive crons (suspend / cancel / refund) support `?dryRun=true`.
- [ ] Email queue processor uses `(priority, next_retry_at, created_at)` index.
- [ ] Failsafe sweep sends to `OPS_FAILSAFE_EMAIL` (different inbox) directly (bypass queue).
- [ ] Bypass marker prevents double-summary.
- [ ] Canonical `analytics/exclusions` module imported by every cron / publisher / reader.
- [ ] Admin event publishers gate on previousStatus AND exclusion.
- [ ] Regression test: orphan-cancel retry succeeds after provider recovers.
- [ ] Regression test: per-event claim lease prevents concurrent processing.
- [ ] Regression test: failsafe fires when DLQ ages > 30min.
- [ ] Drift-guard test pinning every cron's import of exclusions.

---

## Common B90 mistakes

- **Orphan-cancel rows inserted AFTER user delete.** User is gone; nothing to retry against. Insert INSIDE the delete tx.
- **`acquireAdvisoryLock` without `finally` connection release.** Pool exhaustion (failure #8 of source guide).
- **Reconciliation cron uses `WHERE processed_at IS NULL` without the partial index.** Full table scans as `payment_events` grows.
- **`webhook-staleness` alarm fires on every tick** without dedupe. Operator notification fatigue; real alerts ignored.
- **Provider-reconciliation cron has no cursor.** Re-fetches all subs every 6h; rate-limited by provider.
- **`integrity-audit` doesn't filter exclusions.** Test users show up as duplicates daily; operator learns to ignore the alert.
- **Email queue priority not respected because no index.** Queue processor pulls in `created_at` order; refunds wait behind newsletters.
- **Failsafe email sent VIA the queue.** Defeats the entire purpose; use direct send.
- **`OPS_FAILSAFE_EMAIL = ADMIN_EMAIL` in production env.** Production-refine in B20 catches this.
