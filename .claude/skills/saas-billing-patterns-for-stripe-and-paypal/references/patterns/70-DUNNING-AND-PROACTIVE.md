# Bundle B70 — Dunning & Proactive Notifications

> **Where this comes from.** § 32–§ 38, § 37a, § 37b of the source guide.

Dunning is the dance of "your card failed; please update it before we suspend you." Proactive notifications are the polite version: "your card expires in 14 days," "your $19 charge runs tomorrow." Done well, both reduce churn 20–40% (industry numbers, not source-guide-specific). Done badly, they spam users and break trust.

---

## The dunning ladder (individual)

```ts
// src/lib/services/dunning.ts
const DUNNING_STAGES = {
  D0: 0,    // Day 0 — payment failed; immediate "card declined" email
  D7: 7,    // Day 7 — gentle reminder
  D14: 14,  // Day 14 — last warning before suspension
  D21: 21,  // Day 21 — suspension
} as const;
```

| Day | Action | Tone | Required field |
|-----|--------|------|----------------|
| 0 | Email "your card was declined" | Direct; one-click link to update card | `decline_reason` from Stripe / PayPal |
| 7 | Email "still need to update" | Friendly | days_remaining |
| 14 | Email "we'll suspend in 7 days" | Urgent but kind | days_remaining + suspension_date |
| 21 | Suspend (set `subscription_status = 'cancelled'`); send "we suspended" email | Apologetic; offer easy resume | suspension_date |

The 21-day grace is `BUSINESS.GRACE_PERIOD_DAYS` (B20). The reads / sends are driven by the cron at D7, D14, D21 (a single cron iterates `past_due` subs).

### `wasEmailDeliveredSince` cycle-aware dedup

```ts
// CORRECT — checks delivery, not queueing
async function wasEmailDeliveredSince(
  userId: string,
  type: string,                 // e.g. 'dunning_d7'
  since: Date,                  // e.g. 'cycle start'
): Promise<boolean> {
  const last = await db.query.emailJobs.findFirst({
    where: and(
      eq(emailJobs.recipient, userEmail),
      eq(emailJobs.type, type),
      eq(emailJobs.status, 'sent'),     // ← key: not 'queued'
      gt(emailJobs.sentAt, since),       // ← key: actual delivery time
    ),
    orderBy: desc(emailJobs.sentAt),
  });
  return !!last;
}
```

Pre-fix bug (real customer ticket): the dunning cron checked `status === 'queued'` to decide if today's reminder was already sent — but the prior day's email had been queued, then failed, then DLQ'd. The cron saw "queued" and skipped today's send. Customer never got reminded; they were suspended on D21 with no warning.

### Per-cycle dedup (carrier wave for D7 / D14 / D21)

When a payment fails and re-tries succeed, the dunning cycle resets. The dedup window must be the CURRENT failure cycle, not "ever."

```ts
const cycleStart = subscription.lastFailedPaymentAt ?? subscription.currentPeriodEnd;
if (await wasEmailDeliveredSince(userId, 'dunning_d7', cycleStart)) {
  // skip
}
```

---

## Manual invoice retry with 4-guard overcharge defense (§ 33)

The admin "retry this user's failed invoice" button is dangerous because it can charge a user who's now on a different plan, or who was just refunded, or who's already paid via another channel. Four guards:

```ts
async function retryLatestStripeInvoice(
  adminUserId: string,
  userId: string,
): Promise<RetryResult> {
  // Guard 1 — user has a subscription that's actually past_due
  const sub = await db.query.subscriptions.findFirst({
    where: and(eq(subscriptions.userId, userId), eq(subscriptions.status, 'past_due')),
  });
  if (!sub) return { ok: false, reason: 'no_past_due_sub' };

  // Guard 2 — fetch the latest invoice from Stripe, NOT from our cache
  const invoice = await stripe.invoices.retrieveUpcoming({ subscription: sub.externalId })
    .catch(() => stripe.invoices.list({ subscription: sub.externalId, limit: 1 })
      .then(r => r.data[0]));
  if (!invoice) return { ok: false, reason: 'no_invoice_found' };

  // Guard 3 — invoice must be UNPAID (status === 'open' or 'past_due'); never paid
  if (invoice.status === 'paid' || invoice.status === 'void' || invoice.status === 'uncollectible') {
    return { ok: false, reason: `invoice_status_${invoice.status}` };
  }

  // Guard 4 — invoice amount must match the active plan's price
  // (catches the "user changed plans; old invoice is stale" case)
  const expectedPrice = BUSINESS.STRIPE_PRICES[sub.planId];
  const expectedAmount = await getStripeBillingAmountForPlan(expectedPrice);
  if (Math.abs(invoice.amount_due - expectedAmount) > 1) {  // 1 cent tolerance
    return { ok: false, reason: 'amount_mismatch', invoiceAmount: invoice.amount_due, expected: expectedAmount };
  }

  // All guards passed — log the admin action and retry
  await logSecurityEvent({
    type: 'admin_invoice_retry',
    severity: 'medium',
    actor: { type: 'user', id: adminUserId },
    target: { type: 'invoice', id: invoice.id },
    details: { user_id: userId, amount: invoice.amount_due },
  });
  const retried = await stripe.invoices.pay(invoice.id, {
    payment_method: sub.customerId ? undefined : 'pm_card_default',
  });
  return { ok: true, invoice: retried };
}
```

---

## SCA / 3-D Secure routing in dunning (§ 34)

When `invoice.payment_action_required` arrives, the user must complete an SCA challenge (3DS / strong customer auth). Dunning emails for SCA cases need a different CTA than card-decline cases.

```ts
async function handleSCAInvoice(event: Stripe.Event) {
  const invoice = event.data.object as Stripe.Invoice;
  const paymentIntent = await stripe.paymentIntents.retrieve(invoice.payment_intent as string);
  const nextAction = paymentIntent.next_action;

  if (nextAction?.type === 'redirect_to_url') {
    // Email user with the redirect URL; one-click to complete SCA
    await createEmailJob({
      type: 'billing_sca_required',
      recipient: user.email,
      payload: {
        sca_url: nextAction.redirect_to_url.url,
        amount: invoice.amount_due / 100,
        currency: invoice.currency.toUpperCase(),
      },
      priority: 25,  // HIGHER than dunning d7 — user can act immediately
    });
  }
}
```

The user's status stays `past_due`; the dunning ladder is suppressed for SCA cases (different problem; different CTA). When the user completes SCA, `invoice.paid` arrives and the normal flow resumes.

---

## Team coverage suppression in dunning (§ 35)

If a user is `past_due` on their individual sub but their team plan is `active`, suppress the individual dunning emails. The user has access through the team; the individual sub is `paused_for_org` (or about to be).

```ts
// In dunning cron:
for (const userPastDue of pastDueUsers) {
  const projection = await deriveAggregateBillingProjection(userPastDue.userId);
  if (projection.status === 'active' && projection.provider === 'gratis') {
    // Team coverage suppresses individual dunning
    continue;
  }
  // ... send dunning email
}
```

---

## Card-expiry pre-warning (§ 36)

A cron checks `users` with cards expiring in the next 30 days; sends a warning at 30, 14, 7 days before expiry.

```ts
// /api/cron/card-expiry-warning (daily)
async function cardExpiryWarningCron() {
  await acquireAdvisoryLock('card_expiry_warning', async () => {
    const subsExpiringSoon = await db.query.subscriptions.findMany({
      where: and(
        eq(subscriptions.status, 'active'),
        eq(subscriptions.provider, 'stripe'),
        // Card expiry is on the Stripe customer, not the sub — joined via customer_id
      ),
    });
    for (const sub of subsExpiringSoon) {
      const card = await getDefaultCardForCustomer(sub.customerId);
      const expiry = new Date(card.exp_year, card.exp_month, 1);
      const daysUntilExpiry = Math.ceil((expiry.getTime() - Date.now()) / (1000 * 60 * 60 * 24));
      const stages = [30, 14, 7];
      for (const stage of stages) {
        if (daysUntilExpiry !== stage) continue;
        const cycleStart = startOfMonth(new Date());
        if (await wasEmailDeliveredSince(sub.userId, `card_expiry_${stage}d`, cycleStart)) continue;
        await createEmailJob({
          type: `card_expiry_${stage}d`,
          recipient: user.email,
          payload: { last4: card.last4, exp_month: card.exp_month, exp_year: card.exp_year },
          priority: 60,
        });
      }
    }
  });
}
```

### Off-by-one — round UP

The pre-fix bug used `Math.floor()` for `daysUntilExpiry`, which made "expires today" round to 0 and skip the warning.

---

## Pre-charge upcoming-renewal notification (§ 37)

For subs that renew in the next 7 days at a non-trivial amount (e.g., team plans), send a pre-charge notification.

```ts
// /api/cron/upcoming-renewal-notification (daily)
async function upcomingRenewalCron() {
  const renewing = await db.query.subscriptions.findMany({
    where: and(
      eq(subscriptions.status, 'active'),
      lt(subscriptions.currentPeriodEnd, addDays(new Date(), 7)),
      gt(subscriptions.currentPeriodEnd, addDays(new Date(), 6)),  // exactly day 6-7 ahead
    ),
  });
  for (const sub of renewing) {
    const cycleStart = sub.currentPeriodStart!;
    if (await wasEmailDeliveredSince(sub.userId, 'pre_charge_renewal', cycleStart)) continue;
    await createEmailJob({
      type: 'pre_charge_renewal',
      recipient: user.email,
      payload: { amount, plan_name, renewal_date: sub.currentPeriodEnd },
      priority: 70,
    });
  }
}
```

---

## No-discount / no-trial provider controls (§ 37a)

The `BUSINESS.TRIAL_DAYS = 0` and `BUSINESS.ALLOW_PROMO_CODES = false` policy needs PROVIDER-side enforcement, not just app-side. An accidentally-enabled coupon in the Stripe Dashboard breaks the policy.

Audit (B110 calls this from Phase 5):

| Layer | Audit |
|-------|-------|
| Stripe Checkout | `allow_promotion_codes: false` in every create-checkout call |
| Stripe Customer Portal | "Apply promotion codes" disabled in portal config |
| Stripe Coupons | Zero active recurring-applicable coupons (or only approved ones) |
| Stripe Promotion Codes | Same |
| Stripe Subscription Discounts | Zero active manual discounts on subscriptions |
| Stripe Subscription Schedules | Zero active schedules with discount transitions |
| Stripe Payment Links | Zero active recurring bypass links (or each matches the app contract) |
| PayPal Plans | No trial cycle in any active plan |

Drift checks: `scripts/audit-trial-discount-deal.sh` for Stripe and `scripts/audit-paypal-plan-prefs.sh` for PayPal.

---

## Product-policy portability: trials, discounts, deals, plan variety (§ 37b)

If your product DOES have trials / discounts / deals / multiple plan tiers, the contract must be explicit and the audit must reflect that.

For trials:
- `BUSINESS.TRIAL_DAYS = N` in constants.
- `subscription_data: { trial_period_days: BUSINESS.TRIAL_DAYS }` in checkout.
- Webhook handler for `customer.subscription.trial_will_end` (3 days before trial → paid) sends a "your trial ends in 3 days" email.
- Dunning ladder: trials that fail to convert to paid don't trigger dunning (that's a different state).

For discounts:
- A registry of allowed coupon / promo-code IDs in `BUSINESS.ALLOWED_PROMO_CODES`.
- Audit script that lists Stripe coupons / promo codes and asserts they're all in the registry.
- Customer Portal: enable promo codes if and only if your business model supports them; either consistent with the Checkout contract.

For deals:
- "Buy now save 20%" requires a coupon + promo-code link. Pin the link's expiry; the link should fail closed when the deal ends.

For multiple plan tiers (e.g., Starter / Pro / Enterprise):
- Per-plan `BUSINESS.STRIPE_PRICES` entry.
- Per-plan PayPal plan ID.
- Per-plan dunning suppression rules (Enterprise might have NET-30 invoicing → no dunning).

The portability principle: every variant the product supports must have its policy expressed in the constants module + audit-able by a script. If the policy is "whatever the Stripe Dashboard happens to allow today," you've already lost.

---

## Customer Portal deep-links (§ 38)

Stripe's Customer Portal lets users update payment method, view invoices, and (per portal config) cancel. Deep-links bypass the portal homepage:

```ts
// src/lib/payment/stripe-portal-session.ts
export async function createPortalSession(
  userId: string,
  returnUrl: string,
  flowType?: 'payment_method_update' | 'subscription_cancel' | 'subscription_update',
): Promise<{ url: string }> {
  const user = await db.query.users.findFirst({ where: eq(users.id, userId) });
  if (!user.customerId) throw new HttpError(400, 'no_stripe_customer');

  const params: Stripe.BillingPortal.SessionCreateParams = {
    customer: user.customerId,
    return_url: returnUrl,
  };
  if (flowType) {
    params.flow_data = { type: flowType, after_completion: { type: 'redirect', redirect: { return_url: returnUrl } } };
  }
  const session = await stripe.billingPortal.sessions.create(params);
  return { url: session.url };
}
```

Used in:
- Past-due banner ("Update payment method" → `flowType: 'payment_method_update'`)
- Cancel flow ("Cancel subscription" → `flowType: 'subscription_cancel'`)
- Plan change ("Change plan" → `flowType: 'subscription_update'`)

The PayPal equivalent: PayPal subscriptions are managed in the user's PayPal account; the deep-link is `https://www.paypal.com/myaccount/autopay/connect/{billing_agreement_id}`. Less elegant; document it for users.

---

## Anti-misfire guard — never email a customer whose invoice is already paid

Between the cron's "find past_due subs" SELECT and its "send dunning email" send, several seconds can pass. In that window: the user pays through the Customer Portal, a webhook lands, our DB is *about* to flip — but the cron already has a stale snapshot. Without a guard, a paid customer gets a "you owe us" email at 9 AM.

The fix lives where the manual invoice retry result is checked. If the retry came back `not_eligible` because the Stripe invoice is now in a terminal state, suppress the email and let reconciliation correct the DB:

```ts
// Inside the dunning cron, after retryLatestStripeInvoice:
if (
  outcome.status === "not_eligible" &&
  (outcome.invoiceStatus === "paid" ||
   outcome.invoiceStatus === "void" ||
   outcome.invoiceStatus === "uncollectible")
) {
  logger.info(
    { subscriptionId: sub.id, invoiceStatus: outcome.invoiceStatus },
    "Dunning cron — Stripe invoice resolved before retry; skipping email (DB will reconcile)",
  );
  return { paid: true, outcome: `stripe_${outcome.invoiceStatus}` };
}
```

The three skip conditions:

| Stripe status | What happened | Why we skip |
|---------------|---------------|-------------|
| `paid` | Customer paid via Portal or auto-retry succeeded | Don't email "you owe us" — they don't |
| `void` | Admin or system voided the invoice | Don't pursue collection on a voided invoice |
| `uncollectible` | Stripe-side classified as uncollectible (Smart Retries gave up) | A separate flow handles this; dunning is the wrong channel |

The `markEventProcessed`-equivalent log line is what pages on-call if the rate of skips is high (it usually means the DB-vs-provider gap is widening).

**Reference:** jeffreys-skills.md `src/app/api/cron/dunning-reminders/route.ts:51-120`.

---

## `retryLatestStripeInvoice` — full 6-guard production version

The 4-guard helper above is the conceptual baseline. The production-hardened version adds two more guards that matter at scale:

```ts
// src/lib/payment/stripe-invoice-retry.ts
export type InvoiceRetryOutcome =
  | { status: "paid"; invoiceId: string; amountPaid: number }
  | { status: "not_eligible"; reason: string; invoiceStatus?: Stripe.Invoice.Status }
  | { status: "failed"; invoiceId: string; declineCode?: string; reason: string;
      requiresAction: boolean; hostedInvoiceUrl?: string };

export async function retryLatestStripeInvoice(opts: {
  subscriptionId: string;
  reason: string;          // for audit log
  adminUserId?: string;    // optional — only set when admin-initiated
}): Promise<InvoiceRetryOutcome> {
  const subscription = await stripe.subscriptions.retrieve(opts.subscriptionId, {
    expand: ["latest_invoice"],
  });
  const latestInvoice = subscription.latest_invoice as Stripe.Invoice | null;

  // Guard 1: Status gate — only `open` invoices may be retried
  if (!latestInvoice || latestInvoice.status !== "open") {
    return { status: "not_eligible", reason: "invoice_not_open", invoiceStatus: latestInvoice?.status };
  }

  // Guard 2: Attempt-count cap — Stripe Smart Retries top out at 4; we cap at 6
  if ((latestInvoice.attempt_count ?? 0) >= 6) {
    return { status: "not_eligible", reason: "attempt_count_exceeded" };
  }

  // Guard 3: Lead-window guard — don't race Stripe's own retry scheduler
  const nowSec = Math.floor(Date.now() / 1000);
  const nextAttempt = latestInvoice.next_payment_attempt ?? 0;
  if (nextAttempt > nowSec && nextAttempt - nowSec < 3600) {
    return { status: "not_eligible", reason: "automatic_retry_pending" };
  }

  // Guard 4: Idempotency key — per (invoice id, attempt count, UTC date)
  const idempotencyKey = buildIdempotencyKey(latestInvoice.id, latestInvoice.attempt_count ?? 0);

  try {
    const paid = await stripe.invoices.pay(latestInvoice.id, {
      off_session: true,
    }, { idempotencyKey });

    if (paid.status === "paid") {
      return { status: "paid", invoiceId: paid.id, amountPaid: paid.amount_paid };
    }

    return { status: "failed", invoiceId: paid.id, reason: "pay_returned_unpaid", requiresAction: false };
  } catch (error) {
    const stripeErr = error as Stripe.errors.StripeError;

    // Guard 5: Race recovery — re-verify after pay error
    // Webhook may have just succeeded; the Stripe error may be stale.
    const verifiedInvoice = await reverifyInvoiceAfterPayError(stripe, latestInvoice.id);
    if (verifiedInvoice?.status === "paid") {
      logger.info({ invoiceId: latestInvoice.id }, "Invoice was paid by webhook between our retry and Stripe's response");
      return { status: "paid", invoiceId: verifiedInvoice.id, amountPaid: verifiedInvoice.amount_paid ?? 0 };
    }

    // Guard 6: SCA / 3DS context surfaced for downstream rewrite (next section)
    const declineCode = stripeErr.decline_code;
    const requiresAction = stripeErr.code === "authentication_required"
                        || declineCode === "authentication_required";

    return {
      status: "failed",
      invoiceId: latestInvoice.id,
      declineCode,
      reason: stripeErr.message ?? "unknown",
      requiresAction,
      hostedInvoiceUrl: latestInvoice.hosted_invoice_url ?? undefined,
    };
  }
}

function buildIdempotencyKey(invoiceId: string, attemptCount: number): string {
  const utcDate = new Date().toISOString().split("T")[0];
  return `invoice-retry:${invoiceId}:${attemptCount}:${utcDate}`;
}
```

**Why each guard exists** (numbered failures the production code paid for):

| Guard | Without it |
|-------|------------|
| 1. Status gate | Retry on a `paid` invoice with stale read → Stripe replies "already paid" but we count it as a re-charge |
| 2. Attempt-count cap | Infinite loop when a permanently-failed card is on file → Stripe API quota burn |
| 3. Lead-window | Two simultaneous attempts (ours + Stripe scheduler) → either fails idempotency check OR succeeds twice on a brittle PSP |
| 4. Idempotency key | Network hiccup retry → double-charge |
| 5. Race recovery | Webhook just succeeded, Stripe's response was stale → we falsely report "failed" and dunning escalates |
| 6. SCA context | Customer can't pay without 3DS challenge; without `requiresAction`, dunning email says "update card" instead of "complete authentication" → customer gives up |

**Reference:** jeffreys-skills.md `src/lib/payment/stripe-invoice-retry.ts:99-299`.

---

## SCA / 3DS — rewrite the dunning email's CTA to `hosted_invoice_url`

The existing SCA section (above) handles `invoice.payment_action_required` webhooks. The dunning-cron-driven path is different: when retry fails with `requiresAction: true`, the email body needs a different copy and a different CTA. The user can't fix this by "updating their card" — they need to complete the 3DS challenge through Stripe's hosted invoice page:

```ts
// In the dunning-reminders cron, after retry:
const retryOutcome = await retryLatestStripeInvoice({ subscriptionId: sub.externalId, reason: "dunning_d7" });

if (retryOutcome.status === "failed" && retryOutcome.requiresAction) {
  results.authenticationRequiredEmails++;
  await sendDunningReminderEmail({
    userId: sub.userId,
    provider: sub.provider,
    subscriptionId: sub.externalId,
    daysSincePastDue,
    authenticationContext: {
      hostedInvoiceUrl: retryOutcome.hostedInvoiceUrl!,
      declineCode: retryOutcome.declineCode,
    },
  });
} else if (retryOutcome.status === "failed") {
  // Standard "update your payment method" email
  await sendDunningReminderEmail({
    userId: sub.userId,
    provider: sub.provider,
    subscriptionId: sub.externalId,
    daysSincePastDue,
    declineContext: { declineCode: retryOutcome.declineCode, reason: retryOutcome.reason },
  });
}
```

The email template branches on `authenticationContext`:

```hbs
{{#if authenticationContext}}
  <h1>Verify your payment method</h1>
  <p>Your bank requires you to verify this charge before it can complete.</p>
  <a href="{{authenticationContext.hostedInvoiceUrl}}" class="cta">Verify payment</a>
{{else}}
  <h1>We couldn't process your payment</h1>
  <p>Please update your payment method to keep your subscription active.</p>
  <a href="{{customerPortalUrl}}" class="cta">Update payment method</a>
{{/if}}
```

The `hosted_invoice_url` opens Stripe's PCI-scoped page that handles the 3DS handshake natively — no integration on our side, the URL is provided by Stripe.

**Reference:** jeffreys-skills.md `src/app/api/cron/dunning-reminders/route.ts:416-426` and `src/lib/payment/stripe-invoice-retry.ts:242-264`.

---

## Win-back email at day 30 post-cancellation

After a sub cancels (whether voluntary or system-driven via terminal dunning), there's a measurable lift from a single, well-timed re-engagement email at day 30. Critical: ONE email, not a campaign — a campaign reads as harassment to a customer who explicitly cancelled.

```ts
// /api/cron/winback-reminder (daily)
async function winbackCron() {
  await acquireAdvisoryLock("winback_reminder", async () => {
    const eligible = await db.query.subscriptions.findMany({
      where: and(
        eq(subscriptions.status, "cancelled"),
        between(subscriptions.cancelledAt, addDays(new Date(), -31), addDays(new Date(), -29)),
      ),
    });

    for (const sub of eligible) {
      // Suppression layer 1: marketing opt-out (covers also billing_banned via the same flag).
      if (await isUserSuppressedFromMarketing(sub.userId)) continue;

      // Suppression layer 2: user already has live access via another sub
      // (paused_for_org / re-subscribed in the gap / team coverage).
      const proj = await deriveAggregateBillingProjection(sub.userId);
      if (proj.status === "active") continue;

      // Suppression layer 3: idempotency — never email the same user twice in this cycle.
      if (await wasEmailDeliveredSince(sub.userId, "billing_winback_d30", sub.cancelledAt!)) continue;

      // Look up the user's email — sub doesn't carry it.
      const user = await db.query.users.findFirst({
        where: eq(users.id, sub.userId),
        columns: { email: true },
      });
      if (!user?.email) continue;

      await createEmailJob({
        type: "billing_winback_d30",
        recipient: user.email,
        payload: {
          userId: sub.userId,
          lastProvider: sub.provider,
          lastPlanId: sub.planId ?? null,               // plan_id is nullable in the canonical schema
          cancelledAt: sub.cancelledAt,
        },
        priority: 150,                                  // low — well below transactional
      });
    }
  });
}
```

**Why the day-30 timing** (not day-7 or day-60):

- Day-7: still bitter from whatever caused them to cancel. Conversion lift is negative.
- Day-30: the "new month" mental reset. They've felt the absence of the product. Best lift in industry data.
- Day-60: the relationship is gone. Lift drops to baseline noise.

**Why ONE email**: a 30-day cron + a 60-day cron + a 90-day cron is a campaign. Customers who cancelled deserve *one* re-engagement attempt, not a sequence. The win-back email itself contains the link to re-subscribe; the unsubscribe link is mandatory and must work without auth.

**Suppression:** pre-cancel, the user may have set `marketing_opted_out` (GDPR / CAN-SPAM compliance). Post-cancel, the win-back cron MUST honor that flag — the win-back is a marketing email, not a transactional one.

**Reference:** filed as bd-qu5dx in the audit; the pattern itself comes from broader SaaS retention literature, not the source codebase (which had this gap).

---

## Polish Bar checks for B70

- [ ] `DUNNING_STAGES` is one constant; referenced by cron + email templates.
- [ ] `wasEmailDeliveredSince` checks `status === 'sent'` AND `sent_at`, not `queued`.
- [ ] Per-cycle dedup uses the failure cycle start, not "ever".
- [ ] **Anti-misfire guard** — dunning cron skips email when retry returns `paid`/`void`/`uncollectible` invoice status.
- [ ] Manual retry has all **6 guards** (status gate, attempt-count cap, lead-window, idempotency key, race recovery, SCA context surface).
- [ ] Idempotency key is per `(invoice_id, attempt_count, UTC date)` — not just `(invoice_id, attempt_count)`.
- [ ] Race recovery (`reverifyInvoiceAfterPayError`) runs after every Stripe error.
- [ ] Manual retry logs the admin action via `logSecurityEvent`.
- [ ] **SCA dunning emails rewrite the CTA to `hosted_invoice_url`** (not the Customer Portal).
- [ ] SCA emails are higher priority than dunning emails.
- [ ] SCA suppresses normal dunning ladder.
- [ ] Team-coverage suppression on individual dunning emails.
- [ ] Card-expiry warning rounds UP (not down).
- [ ] Pre-charge renewal notifications fire 6-7 days ahead, deduped per cycle.
- [ ] **Win-back cron** at day 30 post-cancellation. Single email, NOT a campaign.
- [ ] Win-back honors `marketing_opted_out` flag (GDPR/CAN-SPAM compliance).
- [ ] Trial / discount / deal policy explicit in `BUSINESS`; audit script exists.
- [ ] Customer Portal deep-link helper covers payment-method-update, cancel, plan-update.
- [ ] PayPal deep-link documented for users (no programmatic equivalent).
- [ ] Regression test: dunning skips already-delivered email for current cycle.
- [ ] Regression test: dunning resumes for next cycle when current cycle resolves.
- [ ] Regression test: 4-guard manual retry rejects each guard violation.
- [ ] Regression test: card-expiry rounds UP (test fixture catches off-by-one).

---

## Common B70 mistakes

- **`wasEmailDeliveredSince` checks `status === 'queued'`.** Bug: a queued-then-failed email looks delivered; today's reminder is skipped.
- **Dunning cron iterates ALL `past_due` subs each tick.** N+1 for any project with thousands of subs. Bound the scan, paginate.
- **Manual retry doesn't check `invoice.status`.** Admin clicks retry on a paid invoice; second charge.
- **SCA email at the same priority as the daily dunning.** Buried under digests; user fails SCA before seeing it.
- **Dunning sends to the team admin AND the team member.** Pick one (usually the billing owner); confused communication otherwise.
- **Customer Portal session expires too short.** Default is 5 minutes; extend if your users navigate slowly.
- **Card-expiry warning emails sent BEFORE provider has the new card details.** Cron fired Tuesday; user updated card Tuesday; cron fires Wednesday saying "expires soon" because the cron read stale customer info. Always read fresh from Stripe.
