# Bundle B80 — Team Plans

> **Where this comes from.** § 39–§ 45 of the source guide.

Team plans introduce orthogonal complexity: seat counting, individual-vs-team precedence, pause-resume races, and the individual→team upgrade orphan-cancel race. Skip this bundle if the product only has individual subs (mark the patterns `n/a` with justification).

---

## Two-tier seat pricing model (§ 39)

A team plan has discrete seat tiers — not arbitrary headcount. Reasons:

1. **Stripe's per-seat-quantity model is fragile** — quantity changes mid-cycle prorate weirdly; admins forget to update; auditors confuse.
2. **Tiered pricing matches B2B sales conversation** — "we sell 3-seat / 5-seat / 10-seat packs."
3. **PayPal doesn't model per-seat quantity well** — discrete plans per tier are necessary anyway.

```ts
// In BUSINESS:
TEAM_TIERS: [
  { seats: 3, monthly_usd: 50.00 },
  { seats: 5, monthly_usd: 80.00 },
  { seats: 10, monthly_usd: 150.00 },
] as const;

// In Stripe: one Price per tier
STRIPE_PRICES: {
  team_3_seats: 'price_...',
  team_5_seats: 'price_...',
  team_10_seats: 'price_...',
}
```

When the team grows beyond their tier, prompt to upgrade (via the seat-update flow below).

---

## Seat-aware checkout under advisory lock (§ 40)

Two admins of the same org can both click "Upgrade to 5-seat tier" simultaneously. Without a lock, you get two team-checkout sessions, two Stripe subs, double-billed.

```ts
// /api/teams/[orgId]/upgrade-checkout
async function teamUpgradeCheckout(orgId: string, requestedSeats: number) {
  return await acquireOrgAdvisoryLock(orgId, async (releaseLock) => {
    const tier = BUSINESS.TEAM_TIERS.find(t => t.seats >= requestedSeats);
    if (!tier) throw new HttpError(400, 'no_tier_supports_seat_count');

    // Same canonical sequence as B30, but on `organizations` instead of `users`
    return await db.transaction(async (tx) => {
      const org = await tx.query.organizations.findFirst({ where: eq(organizations.id, orgId) });

      // In-flight detection
      if (org.pendingCheckoutSessionId && org.pendingCheckoutExpiresAt >= new Date()) {
        return { url: org.pendingCheckoutUrl, reused: true };
      }

      // Cross-provider guard
      if (await orgHasActiveSubInOtherProvider(tx, orgId, 'stripe')) {
        throw new HttpError(409, 'cross_provider_active_sub');
      }

      // Create the session with idempotency key + correct price ID
      const session = await stripe.checkout.sessions.create({
        customer: org.stripeCustomerId ?? undefined,
        customer_email: !org.stripeCustomerId ? adminEmail : undefined,
        mode: 'subscription',
        line_items: [{ price: BUSINESS.STRIPE_PRICES[`team_${tier.seats}_seats`], quantity: 1 }],
        success_url: `${env.APP_URL}/team/${orgId}?from=checkout&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${env.APP_URL}/team/${orgId}/billing?from=checkout_cancel`,
        metadata: { orgId, tierSeats: tier.seats },
        // Same explicit no-trial / no-discount per BUSINESS policy
        allow_promotion_codes: false,
      }, {
        idempotencyKey: buildStripeIdempotencyKey(orgId, 'team_upgrade_checkout', String(tier.seats)),
      });

      await tx.update(organizations).set({
        pendingCheckoutProvider: 'stripe',
        pendingCheckoutSessionId: session.id,
        pendingCheckoutUrl: session.url!,
        pendingCheckoutExpiresAt: new Date(session.expires_at * 1000),
        maxSeats: tier.seats,  // pre-record the tier
      }).where(eq(organizations.id, orgId));

      return { url: session.url, reused: false };
    });
  });
}
```

The advisory lock key: `hashtext('org_checkout_' + orgId)` (Postgres's `pg_advisory_lock` takes a bigint; hash the org_id for uniqueness).

---

## Seat updates with proration asymmetry (§ 41)

Upgrade (3 → 5 seats): proration ON; user pays the difference today.
Downgrade (5 → 3 seats): proration OFF; the lower price kicks in next cycle, but no refund of the difference. (Refund-on-downgrade encourages cycle gaming.)

```ts
async function updateTeamSeatTier(orgId: string, newTier: TeamTier) {
  const org = await db.query.organizations.findFirst({ where: eq(organizations.id, orgId) });
  const currentTier = BUSINESS.TEAM_TIERS.find(t => t.seats === org.maxSeats);
  const isUpgrade = newTier.seats > currentTier.seats;

  await stripe.subscriptions.update(org.stripeSubscriptionId, {
    items: [{
      id: org.stripeItemId,
      price: BUSINESS.STRIPE_PRICES[`team_${newTier.seats}_seats`],
    }],
    proration_behavior: isUpgrade ? 'create_prorations' : 'none',
    billing_cycle_anchor: isUpgrade ? 'unchanged' : 'unchanged',
  });

  await db.update(organizations).set({ maxSeats: newTier.seats }).where(eq(organizations.id, orgId));
}
```

---

## Pause/resume — intent-then-act pattern (§ 42 / Billing-H4)

The bug that motivated this whole pattern: pause/resume Stripe API calls inside a DB transaction held a pool connection for 80s–3min during PayPal slowdowns; pool exhaustion = outage.

The fix: write the intent row, COMMIT, then call the provider, then close the loop.

```ts
// 1. Record intent (intent table; partial UNIQUE prevents two open intents per user)
async function recordPauseIntent(userId: string, orgId: string): Promise<string> {
  const result = await db.insert(individualSubscriptionIntents).values({
    userId, intent: 'pause', orgId,
  }).returning({ id: individualSubscriptionIntents.id });
  return result[0].id;
}

// 2. COMMIT (the insert above is in its own short tx)

// 3. Call the provider OUTSIDE any DB tx
async function applyPauseIntent(intentId: string) {
  const intent = await db.query.individualSubscriptionIntents.findFirst({ where: eq(individualSubscriptionIntents.id, intentId) });
  const sub = await db.query.subscriptions.findFirst({ where: and(eq(subscriptions.userId, intent.userId), inArray(subscriptions.status, ['active', 'past_due'])) });
  if (!sub) {
    await markIntentApplied(intentId, 'no_active_sub');
    return;
  }

  try {
    if (sub.provider === 'stripe') {
      await stripe.subscriptions.update(sub.externalId, { pause_collection: { behavior: 'mark_uncollectible' } });
    } else {
      await fetch(`${env.PAYPAL_API_BASE}/v1/billing/subscriptions/${sub.externalId}/suspend`, {
        method: 'POST', headers: { Authorization: `Bearer ${await getPayPalAccessToken()}` },
        body: JSON.stringify({ reason: 'paused_for_org' }),
      });
    }
    // 4. Close the loop: mark intent applied + update local status
    await db.transaction(async (tx) => {
      await tx.update(subscriptions).set({ status: 'paused_for_org' }).where(eq(subscriptions.id, sub.id));
      await markIntentApplied(intentId);
    });
  } catch (err) {
    await db.update(individualSubscriptionIntents).set({ lastError: err.message }).where(eq(individualSubscriptionIntents.id, intentId));
    // Reconciliation cron retries
  }
}

// 5. Reconciliation cron periodically picks up unapplied intents and retries (1)
```

Resume is symmetric.

### Why the partial UNIQUE on intents

`individual_subscription_intents` has `CREATE UNIQUE INDEX individual_intents_open_per_user_idx ON individual_subscription_intents (user_id) WHERE applied_at IS NULL`. This prevents two pending intents for the same user (which would deadlock the resume side).

---

## Team subscription state transitions (§ 43)

The same five-status enum applies to organizations. State machine:

```
                     create
            ┌─────────────────┐
            ▼                 │
        ┌───────┐  upgrade   ┌───────┐
none ──▶│active │◀───────────│active │
   ▲    │ tier  │   downgrade│ tier  │
   │    │  3   │───────────▶ │  5   │
   │    └───┬───┘            └───┬───┘
   │        │ payment failed     │
   │        ▼                    │
   │   ┌──────────┐              │
   │   │ past_due │  payment OK  │
   │   │ (grace)  │──────────────┘
   │   └────┬─────┘
   │        │ grace expired
   │        ▼
   │   ┌──────────┐
   └───│cancelled │
       └──────────┘
```

Same pattern as individual subs; no `paused_for_org` (orgs don't have "covering" entities — they ARE the covering entity).

---

## Team dunning ladder — compressed timeline (§ 44)

Team subs cost 5–10× individual; the dunning timeline is compressed to suspend faster (avoid extended free use):

```ts
const TEAM_DUNNING_STAGES = {
  D0: 0,    // immediate failure email to admins
  D3: 3,    // 3-day reminder (vs individual D7)
  D7: 7,    // 7-day urgent (vs individual D14)
  D30: 30,  // suspension (vs individual D21) — longer because B2B procurement is slower
} as const;
```

Why D30 not D21 for the suspension:
- B2B customers often have AP teams that take 30 days to update card details.
- A team that's late paying once is usually still a good customer; suspension destroys trust.

DON'T copy-paste the individual dunning code; the timing semantics are different. Two separate ladder constants + two separate cron paths (with shared `wasEmailDeliveredSince`).

---

## Individual → team upgrade with orphan-cancel (§ 45)

The race: user has an active individual sub; they accept a team invitation; their team plan becomes their active plan; we need to cancel their individual sub. If we just call `stripe.subscriptions.cancel(individualId)` inline, that call can fail (Stripe outage, network blip). The user is now paying for both.

The pattern: record a pending cancellation on the org row, then a cron retries.

```ts
// In acceptTeamInvitation:
async function acceptTeamInvitation(userId: string, orgId: string) {
  await db.transaction(async (tx) => {
    // 1. Add user to org
    await tx.insert(organizationMembers).values({ orgId, userId });

    // 2. If user has individual sub, mark for cancellation
    const individualSub = await tx.query.subscriptions.findFirst({
      where: and(eq(subscriptions.userId, userId), inArray(subscriptions.status, ['active', 'past_due'])),
    });
    if (individualSub) {
      await tx.update(organizations).set({
        pendingIndividualSubCancelUserId: userId,
        pendingIndividualSubCancelAttempts: 0,
        pendingIndividualSubCancelNextAt: new Date(),
      }).where(eq(organizations.id, orgId));
    }

    // 3. Update aggregate projection
    await deriveAggregateBillingProjection(userId, tx);
  });

  // 4. Outside tx: try the cancellation immediately (best-effort)
  await tryCancelIndividualSubForUser(userId).catch(err => {
    logger.warn({ userId, err }, 'Inline individual sub cancel failed; cron will retry');
  });
}
```

The retry cron (`/api/cron/retry-individual-sub-cancels`) iterates orgs with `pendingIndividualSubCancelNextAt <= now()`, calls the provider cancel, and clears the pending row on success.

If the cancel fails 5 times (per-row retry cap), fire a terminal-stuck digest:

```ts
async function fireTerminalStuckDigestForIndividualCancels() {
  const stuck = await db.query.organizations.findMany({
    where: and(
      not(isNull(organizations.pendingIndividualSubCancelUserId)),
      gte(organizations.pendingIndividualSubCancelAttempts, 5),
    ),
  });
  if (stuck.length === 0) return;
  await createEmailJob({
    type: 'admin_ops_alert',
    recipient: env.ADMIN_EMAIL,
    payload: { subject: 'Individual sub cancel stuck', count: stuck.length, orgs: stuck.map(o => o.id) },
    priority: 30,
  });
}
```

The org-side mirror of the orphan-cancel queue (`organizations.pending_individual_sub_cancel_*`) and the user-delete-side `orphan_subscription_cancels` (B90) are intentionally separate. Coupling them through one helper would ratchet toward a god-function.

---

## Polish Bar checks for B80

- [ ] `BUSINESS.TEAM_TIERS` defines discrete seat tiers; no per-seat quantity.
- [ ] Per-tier Stripe Price IDs and PayPal plan IDs in `BUSINESS`.
- [ ] Team checkout under advisory lock keyed on `orgId`.
- [ ] Same idempotency key + cross-provider guard pattern as individual checkout.
- [ ] Seat updates: upgrade prorates, downgrade does not.
- [ ] `individual_subscription_intents` table exists with open-per-user partial UNIQUE.
- [ ] `recordPauseIntent` + `applyPauseIntent` separated; provider call outside DB tx.
- [ ] Reconciliation cron retries unapplied intents.
- [ ] `paused_for_org` enum value used (NOT `cancelled`).
- [ ] Team dunning ladder is SEPARATE from individual (different timing).
- [ ] Team dunning sends to billing-owner, not all members.
- [ ] Individual→team accept flow records pending-individual-sub-cancel on org.
- [ ] Retry cron drains pending-individual-cancels.
- [ ] Terminal-stuck digest fires after retry-cap.
- [ ] Regression test: parallel team-upgrade clicks don't create double subs.
- [ ] Regression test: pause intent → provider failure → cron retries.
- [ ] Regression test: individual→team accept with provider failure → no double-bill (cron resolves).

---

## Common B80 mistakes

- **Per-seat quantity model in Stripe.** Looks easier early; nightmare to audit at scale. Use discrete tiers.
- **Pause/resume call inside DB tx.** Pool exhaustion. Re-read the intent-then-act pattern.
- **Treating org `paused_for_org` as if individuals can have it.** Orgs don't get `paused_for_org`; only individual users.
- **Reusing the individual dunning constants for teams.** Different timing semantics; will cause angry B2B customers.
- **Coupling the two orphan-cancel helpers.** They look similar; their schemas differ; sharing a god-function is a known anti-pattern (§ 29.5 of source).
- **Not pre-recording `maxSeats` at checkout creation.** When the webhook arrives, the org has no seat info; the welcome email is wrong.
- **Inline cancel of individual sub on team-accept without retry cron.** Network blip → user double-pays.
