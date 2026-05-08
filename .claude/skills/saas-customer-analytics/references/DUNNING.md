# Dunning & Payment Recovery

> Failed payments cause 20-40% of all SaaS churn. Most of it is involuntary — the customer didn't intend to leave. Dunning is your highest-leverage retention mechanism.

## The Dunning Timeline

```
Day 0:  Payment fails → status = 'past_due' → dunning email #1 (immediate)
        │
Day 7:  First reminder email → "Your payment method needs updating"
        │
Day 14: Final warning email → "Access will be suspended in 7 days"
        │
Day 21: Grace period expires → status = 'cancelled' → access revoked
```

**Grace period = 21 days** from period end (NOT from payment failure date). This is critical — the period end is the contractual boundary, not the API event timestamp.

---

## Email Sequence

### Email 1: Payment Failed (Day 0)

```
Subject: Action needed: your payment didn't go through
Body: "We tried to charge your card ending in •••• 4242 for your $20/month
subscription but it was declined. Please update your payment method to
keep your access."
CTA: [Update Payment Method] → /settings/billing
```

### Email 2: Reminder (Day 7)

```
Subject: Reminder: please update your payment method
Body: "Your subscription payment is still outstanding. If we can't
process payment within 14 days, your access will be suspended."
CTA: [Update Payment Method] → /settings/billing
```

### Email 3: Final Warning (Day 14)

```
Subject: Final notice: your subscription will be cancelled in 7 days
Body: "This is your final reminder. If payment isn't resolved by [date],
your subscription will be cancelled and you'll lose access to premium features."
CTA: [Update Payment Method] → /settings/billing
```

---

## Organization (Team) Dunning

Teams have a **shorter grace period** because multiple users are affected:

```
Day 0:  Payment fails → notification to billing admin
Day 3:  First reminder → "Your team's access is at risk"
Day 7:  Suspended → team enters read-only mode
Day 30: Deactivated → all member access revoked
```

**Key difference:** Team dunning notifies the `org_owner` or `billing_email`, not individual members.

---

## Implementation Patterns

### Grace Period Check

```typescript
const GRACE_PERIOD_DAYS = 21;

function isWithinGracePeriod(subscription: Subscription): boolean {
  if (subscription.status !== 'past_due') return false;
  if (!subscription.currentPeriodEnd) return false;

  const graceEnd = new Date(subscription.currentPeriodEnd);
  graceEnd.setDate(graceEnd.getDate() + GRACE_PERIOD_DAYS);

  return new Date() <= graceEnd;
}
```

### Access Rule During Grace Period

```
if status === 'past_due' AND isWithinGracePeriod():
  → GRANT access (user is still "paying" in spirit)
  → Show banner: "Your payment needs attention"
else if status === 'past_due' AND NOT isWithinGracePeriod():
  → REVOKE access
  → Transition to 'cancelled'
```

### Dunning Cron Job

```typescript
// Runs daily at 9am UTC
async function processDunningReminders() {
  // Acquire advisory lock to prevent overlap across Vercel isolates
  const lockAcquired = await db.execute(
    sql`SELECT pg_try_advisory_lock(hashtext('dunning-cron'))`
  );
  if (!lockAcquired.rows[0].pg_try_advisory_lock) return; // Another instance running

  try {
    const pastDueSubscriptions = await db.select()
      .from(subscriptions)
      .where(eq(subscriptions.status, 'past_due'));

    for (const sub of pastDueSubscriptions) {
      const daysSincePeriodEnd = daysBetween(sub.currentPeriodEnd, new Date());

      if (daysSincePeriodEnd >= 7 && daysSincePeriodEnd < 14) {
        await sendDunningReminderEmail(sub.userId);
      } else if (daysSincePeriodEnd >= 14 && daysSincePeriodEnd < 21) {
        await sendFinalWarningEmail(sub.userId);
      } else if (daysSincePeriodEnd >= 21) {
        await suspendWithStatusGuard(sub);
      }
    }
  } finally {
    await db.execute(sql`SELECT pg_advisory_unlock(hashtext('dunning-cron'))`);
  }
}
```

### Dunning Suspension Race Condition (Critical)

Between the SELECT that finds past_due subscriptions and the UPDATE that suspends them, a webhook may reactivate the subscription. Without a status guard on the UPDATE, you'll immediately re-suspend a user who just recovered:

```typescript
// WRONG — blindly suspends regardless of current state
await db.update(subscriptions).set({ status: 'cancelled' }).where(eq(id, sub.id));

// RIGHT — only suspend if still past_due (concurrent webhook may have fixed it)
const result = await db.update(subscriptions)
  .set({ status: 'cancelled' })
  .where(and(eq(id, sub.id), eq(status, 'past_due')))
  .returning();
if (result.length === 0) {
  logger.info({ subId: sub.id }, 'Subscription recovered before suspension — skipping');
}
```

### Unsubscribe State Reset on Full Re-Subscribe

When a user re-enables all email categories via the preferences page, clear the unsubscribe metadata:

```typescript
if (allCategoriesEnabled) {
  await db.update(users).set({
    unsubscribedAt: null,
    unsubscribeReason: null,
  }).where(eq(users.id, userId));
}
```

Stale `unsubscribedAt` causes inconsistent behavior in email-gating logic even though all categories are technically enabled.

### Preference URL: Path vs Full URL

Split link generation into two functions:
- `generatePreferencePath(userId)` → `/settings/email?token=...` (for in-app navigation, avoids cross-environment redirects in dev/test)
- `generatePreferenceUrl(userId)` → `https://yourdomain.com/settings/email?token=...` (for outbound emails that need full URLs)

Internal navigation should use paths (no base URL). Outbound emails need full URLs.

### Middleware Bypass for Token-Authenticated Pages

When your middleware gates all `/settings/*` routes behind auth, the token-based email preference page needs an explicit bypass:

```typescript
function isTokenBackedPreferencesRoute(path: string, params: URLSearchParams): boolean {
  return path === '/settings/email' && params.has('token') && params.get('token') !== '';
}
```

A common mistake is only updating the API layer while the proxy still redirects unauthenticated users to login.

### Distributed Lock Requirement

Any cron that produces side effects (emails, status changes, notifications) MUST acquire a distributed lock to prevent overlap across serverless isolates:
- Use `pg_try_advisory_lock` (non-blocking) at the cron level so a second instance skips immediately
- Use `pg_advisory_xact_lock` (blocking, transaction-scoped) at the per-entity level for webhook handlers
- Mixing these up causes either queue buildup (blocking at cron level) or missed work (non-blocking at entity level)
```

### Email Deduplication

Webhook providers may retry delivery, triggering duplicate dunning emails. Protect against this:

```typescript
async function shouldSendDunningEmail(userId: string, templateKey: string): boolean {
  const recentEmail = await db.select()
    .from(emailJobs)
    .where(and(
      eq(emailJobs.userId, userId),
      eq(emailJobs.templateKey, templateKey),
      gte(emailJobs.createdAt, new Date(Date.now() - 24 * 60 * 60 * 1000))
    ))
    .limit(1);

  return recentEmail.length === 0; // Only send if no email in last 24h
}
```

---

## Recovery Metrics

Track dunning effectiveness:

| Metric | Formula | Target |
|--------|---------|--------|
| Recovery Rate | Recovered / Total Past Due × 100 | > 50% |
| Avg Recovery Time | Mean days from past_due to active | < 5 days |
| Email Open Rate | Opens / Sent × 100 | > 40% |
| Email Click Rate | Clicks / Opens × 100 | > 15% |
| Involuntary Churn Rate | Expired Grace / Total Churn × 100 | Track trend |

**Key insight:** If involuntary churn > 30% of total churn, your dunning sequence isn't aggressive enough. Consider: SMS, in-app banners, shortening the email interval.

---

## Payment Method Update Flow

The CTA in dunning emails should link to a frictionless update page:

1. User clicks "Update Payment Method" → `/settings/billing`
2. Show current payment status with clear error message
3. Pre-fill what you can (email, name)
4. After successful update, immediately retry the failed charge
5. If retry succeeds: transition `past_due` → `active`, send confirmation email
6. If retry fails: show specific error, suggest alternative payment method

---

## Multi-Provider Considerations

### Stripe
- Stripe has built-in Smart Retries (retries failed payments automatically)
- Supplement with your own dunning emails — Stripe's are generic
- Listen for `invoice.payment_failed` to trigger dunning

### PayPal
- PayPal sends its own payment failure notifications
- Listen for `BILLING.SUBSCRIPTION.SUSPENDED` to trigger dunning
- PayPal subscriptions may auto-cancel after 3 consecutive failures (`payment_failure_threshold: 3`)

### Coordination
- Track dunning state per provider to avoid duplicate emails
- Use the `paymentEvents` ledger to determine which provider's payment failed
- Don't send Stripe dunning emails for PayPal failures (and vice versa)

---

---

## Refund vs. Cancellation: Opposite Access Rules

These are distinct operations with opposite access implications:

| Action | Access | `currentPeriodEnd` | `subscriptionStatus` |
|--------|--------|--------------------|-----------------------|
| Cancel (no refund) | Continues through period end | Unchanged | `cancelled` |
| Cancel (with refund) | Revoked immediately | Set to `NOW()` | `none` |

**Getting this wrong in either direction is a business-logic bug:**
- Revoking early on no-refund cancellations punishes paying users
- Continuing access after refund gives the product away for free

---

## Token-Based Email Preference Links

Every transactional email (dunning, digest, invite) must contain a per-user, token-authenticated link for preference management. Static `/settings/email` links require an active session — users who click from their inbox hit a login wall, violating CAN-SPAM spirit.

**Pattern:**
- `generatePreferenceUrl(userId)` produces a URL with a signed, time-limited token
- The preference page checks the token first, falls back to session auth
- When all categories are re-enabled, clear `unsubscribedAt` and `unsubscribeReason`

**Anti-pattern:** Hardcoding `${baseUrl}/settings/email` in every email template. Creates a login wall and means updating N templates when the route changes.

---

## Anti-Patterns

| Don't | Why | Do |
|-------|-----|-----|
| Start grace from failure date | Inconsistent with billing period | Start from `currentPeriodEnd` |
| Send dunning emails without dedup | Webhook retries → email spam | Check last 24h before sending |
| Cancel immediately on failure | Loses recoverable revenue | 21-day grace period |
| Use same grace for teams | Multiple users affected | Shorter grace (7 days to suspend) |
| Ignore involuntary churn | 20-40% of all churn | Track and optimize separately |
| Only email once | Users miss/ignore first email | 3-email sequence at 0/7/14 days |
| Suspend without status guard | Race with recovery webhook | `WHERE status = 'past_due'` on UPDATE |
| Run dunning cron without lock | Duplicate emails from cron overlap | `pg_try_advisory_lock` at cron level |
| Treat refund same as cancel | Opposite access implications | Refund = immediate revoke; cancel = paid-through |
| Hardcode settings URL in emails | Login wall for unauthenticated users | Token-based preference links |
