# Bundle B30 — Checkout

> **Where this comes from.** § 6, § 9, § 28, § 29, § 37a, § 37b, § 67 of the source guide.

Checkout is where the most-attempted attacks land (every retry, every double-click, every cross-provider switch, every URL-encoding edge case). It's also where most race conditions live. This bundle is dense for a reason.

---

## The canonical sequence (provider-symmetric)

```ts
// Pseudo-code for both Stripe and PayPal create-checkout routes.
// Path: src/app/api/{stripe,paypal}/create-checkout/route.ts

export async function POST(request: Request) {
  // 1. Authenticate the user (your project's auth)
  const userId = await requireUserId(request);

  // 2. Validate the requested plan against the registry
  const planId = parsePlanFromBody(request);              // throws if invalid
  const plan = BUSINESS.STRIPE_PRICES[planId];            // throws if not in registry

  // 3. Acquire a per-user transaction with FOR UPDATE on `users`.
  return await db.transaction(async (tx) => {
    const user = await tx.query.users.findFirst({
      where: eq(users.id, userId),
      // FOR UPDATE — blocks parallel checkout attempts in same tx
    });

    // 4. Cross-provider duplicate-sub guard
    if (await hasActiveSubInOtherProvider(tx, userId, 'stripe')) {
      throw new HttpError(409, 'cross_provider_active_sub');
    }

    // 5. Stale-checkout TTL recovery
    if (user.pendingCheckoutSessionId && user.pendingCheckoutExpiresAt < new Date()) {
      // Old attempt is dead; clear the row so we can start fresh
      await tx.update(users).set({
        pendingCheckoutSessionId: null,
        pendingCheckoutUrl: null,
        pendingCheckoutExpiresAt: null,
        pendingCheckoutProvider: null,
      }).where(eq(users.id, userId));
      // Best-effort: expire the prior provider session so it can't complete
      try { await stripe.checkout.sessions.expire(user.pendingCheckoutSessionId); }
      catch { /* OK if already expired */ }
    }

    // 6. In-flight detection — second click returns the existing URL
    if (user.pendingCheckoutSessionId && user.pendingCheckoutExpiresAt >= new Date()) {
      return NextResponse.json({ url: user.pendingCheckoutUrl, reused: true });
    }

    // 7. Customer reuse — never create a duplicate Stripe customer for the same email
    let customerId = user.customerId;
    if (!customerId) {
      const existing = await stripe.customers.list({ email: user.email, limit: 1 });
      customerId = existing.data[0]?.id;
      if (!customerId) {
        const created = await stripe.customers.create({
          email: user.email,
          metadata: { userId: user.id },
        }, { idempotencyKey: buildStripeIdempotencyKey(user.id, 'create_customer') });
        customerId = created.id;
      }
      await tx.update(users).set({ customerId }).where(eq(users.id, userId));
    }

    // 8. Create the provider session with idempotency key
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      mode: 'subscription',
      line_items: [{ price: plan, quantity: 1 }],
      // CRITICAL: template-literal success_url with raw {CHECKOUT_SESSION_ID}
      success_url: `${env.APP_URL}${ROUTES.CHECKOUT_SUCCESS}&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${env.APP_URL}${ROUTES.CHECKOUT_CANCEL}`,
      metadata: {
        userId: user.id,
        planId,
      },
      // Explicit no-trial / no-discount per BUSINESS policy
      subscription_data: { trial_period_days: undefined },
      allow_promotion_codes: false,
      // PayPal equivalent: NO_SHIPPING + adaptive pricing handled in PayPal helper
    }, {
      idempotencyKey: buildStripeIdempotencyKey(user.id, 'create_checkout', planId),
    });

    // 9. Persist the lock surface so subsequent calls bail out at step 6
    await tx.update(users).set({
      pendingCheckoutProvider: 'stripe',
      pendingCheckoutSessionId: session.id,
      pendingCheckoutUrl: session.url!,
      pendingCheckoutExpiresAt: new Date(session.expires_at * 1000),
    }).where(eq(users.id, userId));

    return NextResponse.json({ url: session.url, reused: false });
  });
}
```

This is intentionally written long-form. Every step is load-bearing.

---

## The cross-provider duplicate-sub guard (`bd-1m86f`)

```ts
async function hasActiveSubInOtherProvider(
  tx: TxLike,
  userId: string,
  newProvider: SubscriptionProvider,
): Promise<boolean> {
  // Read DB first
  const dbSubs = await tx.query.subscriptions.findMany({
    where: and(
      eq(subscriptions.userId, userId),
      ne(subscriptions.provider, newProvider),
      inArray(subscriptions.status, ['active', 'past_due']),
    ),
  });
  if (dbSubs.length > 0) return true;

  // Probe the OTHER provider too — webhooks can be stale
  if (newProvider === 'stripe') {
    const probe = await probePayPalForUser(userId);   // see B40 — checks PayPal for live subs
    if (probe.hasLive) return true;
  } else {
    const probe = await probeStripeForUser(userId);
    if (probe.hasLive) return true;
  }

  return false;
}
```

Why both: if PayPal's webhook is 3 hours late, a Stripe checkout opens, and we end up with both providers charging the same customer. The probe is the live read that closes the gap.

---

## The `{CHECKOUT_SESSION_ID}` placeholder trap (`bd-lp3vu`)

`URL.toString()` percent-encodes `{` and `}`:

```ts
// WRONG — Stripe receives `?session_id=%7BCHECKOUT_SESSION_ID%7D`
//         and never substitutes the real session ID, breaking the success page.
const url = new URL('/dashboard', env.APP_URL);
url.searchParams.set('session_id', '{CHECKOUT_SESSION_ID}');
const success_url = url.toString();

// CORRECT — template literal preserves the placeholder for Stripe to substitute
const success_url = `${env.APP_URL}${ROUTES.CHECKOUT_SUCCESS}&session_id={CHECKOUT_SESSION_ID}`;
```

Pin this with a regression test:

```ts
test('bd-lp3vu__success_url_preserves_session_id_placeholder', () => {
  const success_url = buildStripeSuccessUrl();
  expect(success_url).toContain('{CHECKOUT_SESSION_ID}');
  expect(success_url).not.toContain('%7B');
});
```

A lint rule helps too:

```json
// .eslintrc.json
{
  "no-restricted-syntax": [
    "error",
    {
      "selector": "CallExpression[callee.object.name='url'][callee.property.name='toString']",
      "message": "Don't use URL.toString() for Stripe success_url; it percent-encodes {CHECKOUT_SESSION_ID}. Use a template literal."
    }
  ]
}
```

---

## Customer reuse (`bd-1m86f` Layer 3)

Without the `customers.list({ email })` reuse step, every checkout retry creates a fresh Stripe customer. When the webhook lands and `cus_X` is for a duplicate customer, the Tom-Hunter triple-charge becomes real.

The defense (in step 7 above): *before* creating, ask Stripe if it already has a customer for this email. Critical: do NOT make this an `email + metadata.userId` filter — the email is the unique identity Stripe sees, and the cleanup of dangling customers will deduplicate by email anyway.

---

## Stale-checkout race guard (`bd-bfwcy.4 / BILLING-M2`)

Three races to consider:

| Race | Cause | Defense |
|------|-------|---------|
| A — User clicks Subscribe twice rapidly | Two requests, both miss step 6 | `FOR UPDATE` on `users` row in the transaction |
| B — Webhook for OLD session arrives after user starts NEW session | Provider sent `checkout.session.completed` for an abandoned-then-resumed flow | Webhook handler checks `incoming.session.id === user.pendingCheckoutSessionId` |
| C — User abandons checkout, returns days later | Stale `pendingCheckoutSessionId` row | TTL recovery in step 5 |

The webhook-side B race guard (in B40):

```ts
// In handleStripeCheckoutCompleted:
const user = await db.query.users.findFirst({ where: eq(users.id, customId) });
if (user.pendingCheckoutSessionId && user.pendingCheckoutSessionId !== session.id) {
  // The user has moved on to a NEWER session; this one is stale.
  await queueStaleCheckoutAlert({ user, staleSessionId: session.id });
  return;
}
```

---

## Idempotency keys (B20 + B30 surface)

```ts
// In step 8 above:
}, {
  idempotencyKey: buildStripeIdempotencyKey(user.id, 'create_checkout', planId),
});
```

The user-hour-bucketed key from B20 means:
- Two clicks within the same hour → same Stripe session URL returned (idempotent).
- A click an hour later → fresh session (state may have changed).

For PayPal:

```ts
// PayPal's POST /v1/billing/subscriptions accepts PayPal-Request-Id header
const response = await fetch(`${env.PAYPAL_API_BASE}/v1/billing/subscriptions`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${await getPayPalAccessToken()}`,
    'PayPal-Request-Id': buildPayPalRequestId(user.id, 'create_checkout', planId),
    'PayPal-Partner-Attribution-Id': 'YOUR-COMPANY-PARTNER-ID',  // optional
  },
  body: JSON.stringify({
    plan_id: BUSINESS.PAYPAL_PLANS[planId],
    custom_id: user.id,                              // attacker-controllable; cross-checked in B40
    application_context: {
      brand_name: env.APP_NAME,
      shipping_preference: 'NO_SHIPPING',            // mandatory for digital goods
      user_action: 'SUBSCRIBE_NOW',
      return_url: `${env.APP_URL}${ROUTES.CHECKOUT_SUCCESS}`,
      cancel_url: `${env.APP_URL}${ROUTES.CHECKOUT_CANCEL}`,
    },
  }),
});
```

---

## `PendingCheckoutSessionId` partial UNIQUE migration (BILLING-L2)

The lock surface depends on:

```sql
CREATE UNIQUE INDEX users_pending_checkout_session_idx
  ON users (pending_checkout_session_id)
  WHERE pending_checkout_session_id IS NOT NULL;
```

Same on `organizations`. If two users somehow both have the same pending session ID (which would mean Stripe session-ID collision — practically impossible but worth the defense), the second insert fails the UNIQUE.

---

## Trial / discount / deal policy (`§ 37a`, `§ 37b`)

The product policy decision should be EXPLICIT, not "whatever the Stripe Dashboard happens to allow."

If your product is `no trial / no discount` (the default in this skill's `BUSINESS` constants):

```ts
// In create-checkout:
allow_promotion_codes: false,          // Stripe Checkout
subscription_data: { trial_period_days: undefined },  // Explicit no trial

// In Customer Portal config (Stripe Dashboard or via API):
//   - Disable subscription pausing
//   - Disable plan changes (or restrict to allowed plans)
//   - Disable cancellation reasons collection (or wire to intercom)

// PayPal equivalent: ensure the PayPal plan doesn't have a trial cycle
//   (PayPal plans encode trials in the plan itself, not at checkout time;
//    create the plan with no trial cycle).
```

If your product DOES use trials / discounts:

- Pin the policy in `BUSINESS.TRIAL_DAYS` and `BUSINESS.ALLOW_PROMO_CODES`.
- Audit the Stripe Dashboard: only the approved coupons + promotion codes exist.
- Audit Stripe Payment Links: zero active recurring bypass links, OR each link matches the app contract.
- Audit Stripe Customer Portal: cancellation, prorations, plan updates, promotion codes consistent with the app policy.
- For PayPal: per-plan payment-preferences matrix matches the app policy.

The "trial/discount/deal provider audit" is a B110 item; the contract is set here.

---

## PayPal-specific gotchas

- **`shipping_preference: 'NO_SHIPPING'`** is required for digital goods; without it, PayPal asks for a shipping address and your conversion drops.
- **`custom_id`** is the only place you can stash your user ID; it's attacker-controllable, so B40's `validatePayPalUserId` is mandatory.
- **PayPal subscriptions don't have a "create then activate later" flow like Stripe Checkout** — once approved, they're live. Your "draft" is the create call before the user approves.
- **Adaptive Pricing** (PayPal's currency conversion for subscribers): turn on per-plan if you sell internationally; documented per-plan in the `BUSINESS.PAYPAL_PLANS` registry.

---

## Stripe-specific gotchas

- **`mode: 'subscription'` requires `customer` (not `customer_email`)** if you want sessions reusable across products.
- **`automatic_payment_methods: { enabled: true }`** lets Stripe show the dynamic payment-method set (Apple Pay, Google Pay, BNPL, Link, bank debits per region). Pair with `automatic_payment_methods_configuration` if you want fine control.
- **`payment_method_collection: 'always'`** for paid plans; `'if_required'` only for free trials (which we don't use by default).
- **`expires_at`** on Checkout Sessions defaults to 24h; the TTL-recovery step uses this.
- **`subscription_data.metadata`** is the place to stash plan-related metadata; `metadata` on the session is for the session itself.

---

## TOCTOU prevention — the access check must run INSIDE the row lock

The single most common race in checkout: a webhook activates the user's subscription between the access check and the session create. The fix is non-negotiable: open the transaction, take the row lock with `.for("update")`, then re-read the subscription status. The lock blocks any concurrent webhook writer from mutating the row until the transaction commits.

```ts
// src/app/api/{stripe,paypal}/create-checkout/route.ts
const pending = await db.transaction(async (tx) => {
  const [row] = await tx
    .select({ /* fields needed for the rest of the flow */ })
    .from(users)
    .where(eq(users.id, userId))
    .for("update");                               // ← Postgres row-level lock

  if (!row) return { kind: "not_found" as const };

  // CHECK INSIDE THE LOCK — calculate access state after acquiring it.
  // A concurrent webhook cannot mutate users.subscriptionStatus while
  // we hold this row lock, so the answer here is the truth at commit time.
  const currentSubscriptions = await listSubscriptionRecordsForUser(userId);
  const hasCurrentIndividualAccess = calculateHasIndividualAccess(currentSubscriptions);
  if (hasCurrentIndividualAccess) {
    return { kind: "already_subscribed" as const };
  }

  // Reserve the pending checkout window (TTL described below).
  await tx.update(users).set({
    pendingCheckoutProvider: "stripe",
    pendingCheckoutExpiresAt: new Date(Date.now() + CHECKOUT_PENDING_TTL_MS),
  }).where(eq(users.id, userId));

  return { kind: "ok" as const, /* echo fields */ };
});
```

Why this is load-bearing: `calculateHasIndividualAccess` is grace-period-aware — it counts `active`, `past_due` (in grace), `cancelled` (in paid period), and `paused_for_org` as "still has access." Doing this check *outside* the lock means a concurrent webhook can flip `past_due → cancelled` between your read and your write, and you'll happily charge a customer who already cancelled. The lock pins the answer.

**Reference:** jeffreys-skills.md `src/app/api/stripe/create-checkout/route.ts:104-234` and `src/app/api/paypal/create-checkout/route.ts` (same pattern, both providers).

---

## Cross-provider probes — the actual probe interface

The "probe the other provider" sentence in the canonical sequence is the contract. The implementation is two functions that return a distinct shape — and a `reusableCustomerId` field that doubles as the customer-reuse signal (next section).

```ts
// src/lib/billing/probe-stripe-individual.ts
export type ExistingStripeSub = {
  subscriptionId: string;
  customerId: string;
  status: "active" | "past_due" | "trialing" | "incomplete";
};

export type StripeGuardResult = {
  existingSub: ExistingStripeSub | null;   // Blocking: live sub found → return 400
  reusableCustomerId: string | null;       // Non-blocking: customer to re-use on create
};

// "Billable" = Stripe's per-Stripe-doc set of statuses that imply an active
// or in-flight collection attempt. trialing + incomplete are included so we
// don't double-create on a checkout that's still finalizing.
const BILLABLE_STATUSES: ReadonlySet<Stripe.Subscription.Status> =
  new Set(["active", "past_due", "trialing", "incomplete"]);

export async function probeStripeForExistingBillableSub(
  stripe: Stripe,
  email: string | null | undefined,
  knownCustomerId: string | null,
): Promise<StripeGuardResult> {
  const liveCandidateIds = new Set<string>();
  const candidateCreatedAt = new Map<string, number>();

  // 1. If we have a known customer ID, check it first (cheapest).
  //    We don't have its Stripe-side created timestamp without an extra GET,
  //    so its candidateCreatedAt stays unset — handled in step 4.
  if (knownCustomerId) liveCandidateIds.add(knownCustomerId);

  // 2. Look up by email (Stripe is the source of truth for customer↔email)
  if (email) {
    const search = await stripe.customers.list({ email, limit: 100 });
    for (const c of search.data) {
      liveCandidateIds.add(c.id);
      candidateCreatedAt.set(c.id, c.created);
    }
  }

  // 3. For each candidate, list subs and check for any in BILLABLE_STATUSES
  for (const customerId of liveCandidateIds) {
    const subs = await stripe.subscriptions.list({
      customer: customerId,
      status: "all",
      limit: 100,
    });
    for (const s of subs.data) {
      if (BILLABLE_STATUSES.has(s.status)) {
        return { existingSub: { subscriptionId: s.id, customerId, status: s.status }, reusableCustomerId: null };
      }
    }
  }

  // 4. No billable sub. Pick the OLDEST customer (deterministic) for reuse.
  //    A known customer ID without a created timestamp wins the tie-break
  //    by sorting at -1 — the previously-linked customer is the right reuse target.
  let reusableCustomerId: string | null = null;
  let oldestCreated = Number.POSITIVE_INFINITY;
  for (const id of liveCandidateIds) {
    const created = candidateCreatedAt.has(id) ? candidateCreatedAt.get(id)! : -1;
    if (created < oldestCreated) { oldestCreated = created; reusableCustomerId = id; }
  }
  return { existingSub: null, reusableCustomerId };
}
```

Symmetric file: `probe-stripe-team.ts` filters by `metadata.organization_id` instead of email; PayPal probes use `GET /v1/billing/subscriptions` filtered by `custom_id`.

**Caller wiring** (Stripe checkout creating a Stripe sub still calls the Stripe probe — the duplicate-customer leg, not just the cross-provider leg):

```ts
// PayPal cross-provider defense (run BEFORE Stripe probe)
const existingPaypalSub = await probePayPalForExistingBillableSub(userId);
if (existingPaypalSub) {
  logger.warn({ userId, paypalSubscriptionId: existingPaypalSub.subscriptionId },
    "Blocked Stripe checkout: PayPal reports existing billable subscription");
  return NextResponse.json(paymentError.toJSON(), { status: 400 });
}

// Stripe duplicate-sub + customer-discovery probe
const stripeProbe = await probeStripeForExistingBillableSub(stripe, pending.email, pending.customerId ?? null);
if (stripeProbe.existingSub) {
  logger.warn({ userId, stripeSubscriptionId: stripeProbe.existingSub.subscriptionId },
    "Blocked duplicate checkout: Stripe reports existing billable subscription");
  return NextResponse.json(paymentError.toJSON(), { status: 400 });
}
```

The probe's two-headed return (block OR reuse) is the trick: a single API round-trip serves both the "duplicate sub guard" and the "find the customer to reuse" requirements — they're literally the same scan.

**Reference:** jeffreys-skills.md `src/lib/billing/probe-stripe-individual.ts:46-138`, `probe-stripe-team.ts:46-124`, callers in both create-checkout routes.

---

## Customer reuse — pick oldest, backfill into the DB on session create

The probe returns `reusableCustomerId`. On checkout-session create, prefer the DB's stored `customerId`, fall back to the probe's pick:

```ts
const reusableCustomerId = pending.customerId ?? stripeProbe.reusableCustomerId;

const session = await stripe.checkout.sessions.create({
  mode: "subscription",
  customer: reusableCustomerId ?? undefined,
  customer_email: reusableCustomerId ? undefined : pending.email,
  line_items: [{ price: env.STRIPE_PRICE_ID, quantity: 1 }],
  // ...
}, { idempotencyKey });

// CRITICAL: backfill so the next checkout doesn't repeat the email lookup
const shouldBackfillCustomerId = pending.customerId === null && reusableCustomerId !== null;

await db.update(users).set({
  pendingCheckoutSessionId: session.id,
  pendingCheckoutUrl: session.url,
  ...(shouldBackfillCustomerId ? { customerId: reusableCustomerId } : {}),
}).where(eq(users.id, userId));
```

Why "oldest": deterministic. Two probes for the same email always return the same customer ID, so retries don't drift across customers. Defends against using `created_at = max` (which would converge on the *most recent* duplicate, exactly the one most likely to be a fresh attacker-created customer).

**Reference:** jeffreys-skills.md `src/app/api/stripe/create-checkout/route.ts:428, 497-507` and `src/lib/billing/probe-stripe-individual.ts:127-137`.

---

## Pending-checkout TTL values

```ts
const STRIPE_CHECKOUT_PENDING_TTL_MS = 60 * 60 * 1000;          // 1 hour
const PAYPAL_CHECKOUT_PENDING_TTL_MS = 30 * 60 * 1000;          // 30 minutes
```

Why asymmetric: PayPal's approval URL has a documented 3-hour validity window, but the *user* experience is that approval happens within minutes; if a user hasn't approved within 30 min, they've abandoned. Stripe Checkout Sessions have a default 24-hour `expires_at`, but the same UX reasoning bounds reservations at 1 hour. Both are well under the provider's hard expiry, so the TTL clear + provider-side `expire()` keeps state consistent.

**TTL is on the row**, not in code:

```ts
await tx.update(users).set({
  pendingCheckoutProvider: "stripe",
  pendingCheckoutSessionId: null,            // populated post-create
  pendingCheckoutUrl: null,                  // populated post-create
  pendingCheckoutExpiresAt: new Date(Date.now() + STRIPE_CHECKOUT_PENDING_TTL_MS),
}).where(eq(users.id, userId));
```

Step 5 in the canonical sequence (TTL recovery) reads `pendingCheckoutExpiresAt < new Date()` to decide whether to clear and rebuild.

---

## Stale-session expire — extract into a named helper

The `try { stripe.checkout.sessions.expire(...) } catch { ... }` snippet from step 5 deserves its own named helper because it's called from at least two places (TTL recovery, and explicit "user requested cancel"):

```ts
// src/app/api/stripe/create-checkout/route.ts (or src/lib/billing/...)
async function expireStripeCheckoutSession(
  stripe: Stripe,
  sessionId: string,
  context: { userId: string; requestId: string | null; reason: string },
): Promise<void> {
  try {
    await stripe.checkout.sessions.expire(sessionId);
    logger.info({ userId: context.userId, sessionId, reason: context.reason },
      "Expired Stripe checkout session before creating replacement");
  } catch (expireErr) {
    // Most common: Stripe says it's already expired or completed. Log + continue.
    logger.info({ err: expireErr, userId: context.userId, sessionId, reason: context.reason },
      "Stripe checkout session expire failed (likely already terminal) — continuing");
  }
}
```

The named helper makes the structured log line searchable (`Expired Stripe checkout session before creating replacement` is a Splunk/Datadog query you'll want).

---

## Eager PayPal subscription-id persistence — write the ID immediately, even before approval URL parsing

PayPal's `POST /v1/billing/subscriptions` returns a subscription ID in the response body before the user has approved anything. The naive flow is:

1. Create PayPal sub → get `subscriptionId`
2. Parse + validate approval URL
3. Persist `subscriptionId` to `users.lastPaypalSubscriptionId`
4. Return approval URL

The bug: if step 2 or 3 throws (network blip, validation reject, DB write failure), the user retries from a fresh state, and the cross-provider probe at step "1" can't find the orphan because `lastPaypalSubscriptionId` is still null. PayPal-side they have a half-created subscription that will eventually be auto-cancelled, but in the meantime the user can create a *second* one and end up double-billed at activation.

The fix: persist eagerly, between create and validation. (`rollbackPayPalSubscriptionId` is the function-scoped `let` defined in the next section's "Created-PayPal-sub rollback" — both code blocks live in the same checkout-route handler scope.)

```ts
// After PayPal returns the sub ID
const createdSubscriptionId = data.id;
rollbackPayPalSubscriptionId = createdSubscriptionId;   // arms the rollback (next section)

// EAGER PERSIST — write before any other failable step
try {
  await db.update(users)
    .set({ lastPaypalSubscriptionId: createdSubscriptionId })
    .where(eq(users.id, userId));
} catch (eagerErr) {
  // Don't abort — the probe will eventually find it via PayPal API too,
  // and the main update below will retry. Log loudly so this surfaces.
  logger.warn({ err: eagerErr, userId, subscriptionId: createdSubscriptionId },
    "Eager lastPaypalSubscriptionId persist failed; main update will retry");
}

const approvalUrl = getApprovalUrl(data.links, paypalEnvironment);  // can fail
if (!approvalUrl) {
  await rollbackCreatedPayPalSubscription("no_approval_url", "...");
  return NextResponse.json(paymentError.toJSON(), { status: 502 });
}
```

**Reference:** jeffreys-skills.md `src/app/api/paypal/create-checkout/route.ts:653-675`.

---

## Created-PayPal-sub rollback — cancel any sub that wasn't fully persisted

Eager persistence isn't enough on its own. If we hit the approval-URL-missing branch (or any other terminal error after the create), we have a real PayPal sub that the user never saw. Cancel it:

```ts
let rollbackPayPalSubscriptionId: string | null = null;

async function rollbackCreatedPayPalSubscription(reason: string, failureMessage: string) {
  if (!rollbackPayPalSubscriptionId) return;
  const subscriptionId = rollbackPayPalSubscriptionId;
  rollbackPayPalSubscriptionId = null;     // single-shot

  try {
    const cancelled = await cancelPayPalSubscription(subscriptionId, reason);
    if (!cancelled) logger.error({ userId, subscriptionId }, failureMessage);
  } catch (rollbackError) {
    logger.error({ err: rollbackError, userId, subscriptionId }, failureMessage);
  }
}

// On any error after create:
await rollbackCreatedPayPalSubscription(
  "Checkout failed before approval state was persisted",
  "Failed to cancel PayPal subscription after checkout persist error",
);
```

The single-shot pattern (clearing `rollbackPayPalSubscriptionId` first) prevents a double-cancel if the rollback path itself throws and a higher-level handler retries.

**Reference:** jeffreys-skills.md `src/app/api/paypal/create-checkout/route.ts:161-177, 700-733`.

---

## PayPal approval URL allowlisting — only paypal.com / sandbox.paypal.com

PayPal's create-subscription response returns a `links[]` array. The `rel: "approve"` link is what you redirect the user to. Trusting the URL blindly is an open-redirect waiting to happen; a compromised PayPal partner integration could deliver a phishing URL on a known PayPal-shaped domain.

```ts
type PayPalEnvironment = "production" | "sandbox";

const PAYPAL_APPROVAL_HOSTS: Record<PayPalEnvironment, string> = {
  production: "www.paypal.com",
  sandbox:    "www.sandbox.paypal.com",
};

function isAllowedPayPalApprovalUrl(href: string, environment: PayPalEnvironment): boolean {
  try {
    const u = new URL(href);
    return u.protocol === "https:" &&
           u.hostname.toLowerCase() === PAYPAL_APPROVAL_HOSTS[environment];
  } catch { return false; }
}

function getApprovalUrl(links: PayPalLink[] | undefined, environment: PayPalEnvironment): string | undefined {
  return links
    ?.filter((link) => link.rel === "approve")
    .find((link) => isAllowedPayPalApprovalUrl(link.href, environment))
    ?.href;
}
```

A `getApprovalUrl` returning undefined triggers the rollback path above.

**Reference:** jeffreys-skills.md `src/app/api/paypal/create-checkout/route.ts:92-111`.

---

## PayPal `application_context` — the full polish set

The shipping_preference / locale recommendation isn't optional polish — `NO_SHIPPING` removes a checkout-killer for digital subscriptions. The full set worth pinning:

```ts
application_context: {
  brand_name: env.APP_NAME,                  // shown above PayPal logo on approval page
  locale: "en-US",                           // forces English (or your localized value)
  shipping_preference: "NO_SHIPPING",        // CRITICAL for digital — drops shipping prompt
  user_action: "SUBSCRIBE_NOW",              // shows "Subscribe Now" button (vs "Continue")
  payment_method: {                          // optional but recommended
    payer_selected: "PAYPAL",
    payee_preferred: "IMMEDIATE_PAYMENT_REQUIRED",
  },
  return_url: successUrl.toString(),         // post-approval landing
  cancel_url: cancelUrl.toString(),          // user-clicked-cancel landing
},
```

**Reference:** jeffreys-skills.md `src/app/api/paypal/create-checkout/route.ts:570-586`.

---

## Polish Bar checks for B30

- [ ] `success_url` is a template literal preserving `{CHECKOUT_SESSION_ID}`.
- [ ] Lint rule pins the `URL.toString()` anti-pattern.
- [ ] `FOR UPDATE` on `users` row inside the checkout transaction.
- [ ] **The access check (`calculateHasIndividualAccess`) runs INSIDE the lock**, not before it.
- [ ] Cross-provider duplicate-sub guard probes the OTHER provider, not just the DB.
- [ ] Probe interface returns `{ existingSub, reusableCustomerId }` so one scan serves both block-and-reuse.
- [ ] Customer reuse via `customers.list({ email })` before create — pick OLDEST customer deterministically.
- [ ] Customer-id backfill into `users.customerId` happens on the same UPDATE as `pendingCheckoutSessionId`.
- [ ] Stripe idempotency key per (user, hour, operation).
- [ ] PayPal-Request-Id same scheme.
- [ ] `pending_checkout_*` columns updated atomically with the session creation.
- [ ] Pending-checkout TTL: 1h Stripe / 30m PayPal (asymmetric, by design).
- [ ] Stale-session TTL recovery clears the row + best-effort `expire`s the provider session.
- [ ] `expireStripeCheckoutSession` is a named helper (not inline `try/catch`) so its log line is searchable.
- [ ] In-flight detection returns the existing URL on second click.
- [ ] **Eager PayPal sub-id persistence** — `lastPaypalSubscriptionId` written between create and approval-URL parsing.
- [ ] **Created-PayPal-sub rollback** — `cancelPayPalSubscription` invoked on any post-create failure; single-shot guard prevents double-cancel.
- [ ] **PayPal approval URL allowlisting** — only `https://www.paypal.com/...` or `https://www.sandbox.paypal.com/...` accepted.
- [ ] Trial / discount policy is explicit and matches `BUSINESS` constants.
- [ ] Stripe `allow_promotion_codes: false` (or matches policy).
- [ ] PayPal `shipping_preference: 'NO_SHIPPING'` for digital goods.
- [ ] PayPal `application_context` includes `brand_name`, `locale`, `user_action: SUBSCRIBE_NOW`.
- [ ] `pending_checkout_session_id` partial UNIQUE index exists.
- [ ] Regression test for `{CHECKOUT_SESSION_ID}` preservation.
- [ ] Regression test for cross-provider guard (with both DB-active and provider-probe-active scenarios).
- [ ] Regression test for stale-session TTL recovery.
- [ ] Regression test for in-flight reuse (second click returns same URL).
- [ ] Regression test for TOCTOU: simulate concurrent webhook activation; lock holder must observe the activation.
- [ ] Regression test for PayPal approval URL allowlisting (rejects `evil.paypal.com.attacker.io`, `http://www.paypal.com`).

---

## Common B30 mistakes

- **Skipping the customer probe.** Creates a duplicate Stripe customer; the next webhook lands on a "new" customer ID and breaks downstream lookups.
- **Trusting `metadata.userId` as authoritative on the webhook side.** It's set in step 8 above and re-read in B40, but B40 must cross-check (Stripe Connect / org events) or validate (PayPal `custom_id` → `validatePayPalUserId`).
- **No `FOR UPDATE` on the `users` row.** Two concurrent clicks both pass the in-flight check; both create sessions; both update the row; one wins — and now the row points at one Stripe session while the other was paid by the user.
- **TTL recovery without expiring the provider session.** The user starts a new session, completes the OLD one (because the OLD URL was still bookmarked), and we get a `checkout.session.completed` for the wrong session. The race-B guard in B40 catches this, but the cleaner defense is also to call `sessions.expire()`.
- **Not collecting Adaptive Pricing eligibility per plan in PayPal.** If you sell internationally and don't enable Adaptive Pricing on the PayPal plan, conversion craters in non-USD markets.
- **Hardcoded `CHECKOUT_SUCCESS` route.** Read from `ROUTES`; centralization matters when you add a `&utm_source=checkout` later.
