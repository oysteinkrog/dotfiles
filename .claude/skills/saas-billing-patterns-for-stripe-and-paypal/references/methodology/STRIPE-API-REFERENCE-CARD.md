# Stripe API Reference Card — Billing Endpoints

> **Quick reference for Stripe endpoints relevant to billing.** Skip the SDK docs maze; everything you'll commonly need.

---

## Customers

```ts
// Create
const customer = await stripe.customers.create({
  email: user.email,
  metadata: { userId: user.id },
});

// Retrieve
const customer = await stripe.customers.retrieve(customerId);

// Update
await stripe.customers.update(customerId, { metadata: { ... } });

// List by email (for customer reuse — B30 § Customer reuse)
const result = await stripe.customers.list({ email: user.email, limit: 1 });

// Delete (rare; usually you cancel subs instead)
await stripe.customers.del(customerId);
```

---

## Prices + Products

```ts
// List active prices for a product
const prices = await stripe.prices.list({ product: productId, active: true });

// Retrieve a price
const price = await stripe.prices.retrieve(priceId);

// Create (rare; usually via Dashboard)
await stripe.prices.create({
  product: productId,
  unit_amount: 1900,  // cents
  currency: 'usd',
  recurring: { interval: 'month' },
  tax_behavior: 'exclusive',
});
```

---

## Subscriptions

```ts
// Create directly (without Checkout)
const sub = await stripe.subscriptions.create({
  customer: customerId,
  items: [{ price: priceId, quantity: 1 }],
  payment_settings: {
    payment_method_options: { card: { request_three_d_secure: 'automatic' } },
    save_default_payment_method: 'on_subscription',
  },
  expand: ['latest_invoice.payment_intent'],
});

// Retrieve
const sub = await stripe.subscriptions.retrieve(subId, { expand: ['latest_invoice'] });

// Update (e.g., change plan, change quantity)
await stripe.subscriptions.update(subId, {
  items: [{ id: subItemId, price: newPriceId, quantity: 5 }],
  proration_behavior: 'always_invoice',  // OR 'none', 'create_prorations'
});

// Pause / Resume
await stripe.subscriptions.update(subId, {
  pause_collection: { behavior: 'void' },  // OR 'mark_uncollectible'
  metadata: { paused_for_org: orgId },
});
await stripe.subscriptions.update(subId, { pause_collection: '' });  // resume

// Cancel (immediate)
await stripe.subscriptions.cancel(subId, { invoice_now: false, prorate: false });

// Cancel at period end
await stripe.subscriptions.update(subId, { cancel_at_period_end: true });

// List (paginated)
for await (const sub of stripe.subscriptions.list({ status: 'active', limit: 100 })) {
  // ...
}
```

---

## Checkout Sessions

```ts
// Create
const session = await stripe.checkout.sessions.create({
  mode: 'subscription',
  customer: customerId,
  line_items: [{ price: priceId, quantity: 1 }],
  success_url: `${env.APP_URL}${ROUTES.CHECKOUT_SUCCESS}&session_id={CHECKOUT_SESSION_ID}`,
  // ☝ Template literal preserves the placeholder; URL.toString() would percent-encode (B30 § bd-lp3vu)
  cancel_url: `${env.APP_URL}${ROUTES.CHECKOUT_CANCEL}`,
  metadata: { userId, planId },
  allow_promotion_codes: false,  // explicit per BUSINESS policy
  subscription_data: { trial_period_days: undefined },
  client_reference_id: userId,  // for client-side identification
}, {
  idempotencyKey: buildStripeIdempotencyKey(userId, 'create_checkout', planId),
});

// Retrieve
const session = await stripe.checkout.sessions.retrieve(sessionId, {
  expand: ['line_items', 'subscription'],
});

// Expire (B30 § stale-session TTL recovery)
await stripe.checkout.sessions.expire(sessionId);

// List (rare)
const sessions = await stripe.checkout.sessions.list({ limit: 100 });
```

---

## Invoices

```ts
// Retrieve
const invoice = await stripe.invoices.retrieve(invoiceId, { expand: ['subscription', 'charge'] });

// List for a subscription
const invoices = await stripe.invoices.list({ subscription: subId, limit: 100 });

// List upcoming (preview next invoice)
const upcoming = await stripe.invoices.retrieveUpcoming({ subscription: subId });

// Pay (manual retry; B70 § 4-guard manual retry)
const paid = await stripe.invoices.pay(invoiceId, undefined, {
  idempotencyKey: `invoice-retry-${invoiceId}-${attemptCount}-${ymd}`,
});

// Void (cancel + don't try to collect)
await stripe.invoices.voidInvoice(invoiceId);

// Mark uncollectible
await stripe.invoices.markUncollectible(invoiceId);

// Send (email customer)
await stripe.invoices.sendInvoice(invoiceId);
```

---

## Refunds

```ts
// Create
const refund = await stripe.refunds.create({
  charge: chargeId,
  reason: 'requested_by_customer',  // OR 'duplicate', 'fraudulent'
  metadata: { ticket: ticketId, authorizedBy: adminId },
});

// Partial refund
const refund = await stripe.refunds.create({
  charge: chargeId,
  amount: 500,  // 5.00 in the charge's currency
});

// For Connect: reverse transfer + refund application fee
const refund = await stripe.refunds.create({
  payment_intent: piId,
  reverse_transfer: true,
  refund_application_fee: true,
});

// Retrieve
const refund = await stripe.refunds.retrieve(refundId);
```

---

## Disputes

```ts
// Retrieve
const dispute = await stripe.disputes.retrieve(disputeId);

// List
const disputes = await stripe.disputes.list({ limit: 100 });

// Submit evidence (B125)
await stripe.disputes.update(disputeId, {
  evidence: {
    product_description: '...',
    customer_communication: '...',
    receipt: receiptUrl,
    customer_signature: '...',
    customer_purchase_ip: ip,
    access_activity_log: jsonString,
    cancellation_policy: tosUrl,
    refund_policy: refundPolicyUrl,
    uncategorized_text: narrative,
    // ... per dispute reason
  },
  submit: true,  // SUBMIT (not just stage)
});
```

---

## Webhooks

```ts
// Construct event from request body + signature
const event = stripe.webhooks.constructEvent(rawBody, signature, secret);

// List endpoints
const endpoints = await stripe.webhookEndpoints.list();

// Create endpoint (rare; usually Dashboard)
await stripe.webhookEndpoints.create({
  url: 'https://app.example.com/api/stripe/webhook',
  enabled_events: [...HANDLED_STRIPE_EVENTS],
  api_version: STRIPE_API_VERSION,
});
```

---

## Balance Transactions (settlement ledger source)

```ts
// List (paginated; the source of truth for cash)
for await (const tx of stripe.balanceTransactions.list({
  type: 'charge',
  created: { gte: Math.floor(Date.now() / 1000) - 7 * 86400 },
  limit: 100,
})) {
  // tx.amount, tx.fee, tx.net, tx.type, tx.reporting_category
  // ... ingest into settlement_ledger (B75 § Pattern 3)
}
```

---

## Test Clocks

```ts
// Create
const clock = await stripe.testHelpers.testClocks.create({
  frozen_time: Math.floor(Date.now() / 1000),
  name: 'integration-test-renewal',
});

// Create customer + subscription on the clock
const customer = await stripe.customers.create({ test_clock: clock.id, ... });

// Advance time
await stripe.testHelpers.testClocks.advance(clock.id, {
  frozen_time: Math.floor(Date.now() / 1000) + 31 * 86400,
});

// Wait for advance to complete (Stripe processes events)
async function waitForClockReady(clockId: string) {
  for (let i = 0; i < 60; i++) {
    const clock = await stripe.testHelpers.testClocks.retrieve(clockId);
    if (clock.status === 'ready') return;
    await sleep(1000);
  }
  throw new Error('Test clock did not advance in time');
}

// Cleanup
await stripe.testHelpers.testClocks.del(clock.id);
```

---

## Customer Portal

```ts
// Create config (typically Dashboard, but API works)
const config = await stripe.billingPortal.configurations.create({
  features: {
    payment_method_update: { enabled: true },
    subscription_cancel: {
      enabled: true,
      mode: 'at_period_end',
      proration_behavior: 'none',
    },
    subscription_update: {
      enabled: false,  // gate per BUSINESS policy
    },
    invoice_history: { enabled: true },
  },
  business_profile: {
    headline: 'Manage your subscription',
  },
});

// Mint a session
const portalSession = await stripe.billingPortal.sessions.create({
  customer: customerId,
  return_url: `${env.APP_URL}/account/billing`,
  flow_data: {
    type: 'payment_method_update',  // OR 'subscription_cancel', 'subscription_update'
  },
  locale: user.locale,
});
// Redirect user to portalSession.url
```

---

## Connect

```ts
// Create connected account (Express)
const account = await stripe.accounts.create({
  type: 'express',
  country: 'US',
  email: seller.email,
  capabilities: {
    card_payments: { requested: true },
    transfers: { requested: true },
  },
});

// Generate onboarding link
const link = await stripe.accountLinks.create({
  account: account.id,
  refresh_url: `${env.APP_URL}/connect/refresh`,
  return_url: `${env.APP_URL}/connect/return`,
  type: 'account_onboarding',
});

// Charge on behalf of (Direct Charges)
const pi = await stripe.paymentIntents.create({
  amount: 10000, currency: 'usd',
  application_fee_amount: 1000,
  transfer_data: { destination: account.id },
});

// Connect events have event.account
// Verify against allowlist (per § 78a.1)
```

---

## Payment Method Configurations (per § 4.2a)

```ts
// List active configurations
const configs = await stripe.paymentMethodConfigurations.list({ active: true });

// Retrieve default
const config = configs.data.find(c => c.is_default);
// Inspect: config.card.display_preference, config.link.display_preference, config.paypal.display_preference, etc.
```

---

## Payment Links

```ts
// List active (per § 4.7 audit)
const links = await stripe.paymentLinks.list({ active: true });

// Per-link line items (to detect recurring)
for (const link of links.data) {
  const lineItems = await stripe.paymentLinks.listLineItems(link.id);
  const isRecurring = lineItems.data.some(li => li.price?.recurring);
  // Audit if isRecurring: per § 4.7, active recurring Payment Links are bypass risk
}
```

---

## Common Stripe error codes

| Code | Meaning | Action |
|------|---------|--------|
| `resource_missing` | Object doesn't exist | Don't error; user-friendly fallback |
| `card_declined` | Card declined by issuer | Per dunning ladder |
| `authentication_required` | SCA / 3DS required | Per B70 § SCA routing |
| `idempotency_key_in_use` | Duplicate idempotency key in use | Sleep + retry |
| `rate_limit` | API rate limited | Backoff + retry |
| `api_connection_error` | Network issue | Retry |
| `api_error` | Stripe internal | Retry; log if persistent |
| `invalid_request_error` | Bug in our code | Don't retry; fix code |
| `parameter_unknown` | API version mismatch | Pin STRIPE_API_VERSION |

---

## Pagination patterns

```ts
// auto-pagination (recommended for full sweep)
for await (const item of stripe.subscriptions.list({ status: 'active' })) {
  // process
}

// Manual pagination (recommended for bounded sample)
const result = await stripe.subscriptions.list({ status: 'active', limit: 100 });
const items = result.data;
let cursor = result.data[result.data.length - 1]?.id;
// next page:
const next = await stripe.subscriptions.list({ status: 'active', limit: 100, starting_after: cursor });
```

For audits (per B35), prefer manual + bound to recent data; auto-pagination can run forever.

---

## API version pinning (per § 4.2)

```ts
// src/lib/constants/stripe-config.ts
import Stripe from 'stripe';

export const STRIPE_API_VERSION =
  '2025-12-15.clover' satisfies ConstructorParameters<typeof Stripe>[1]['apiVersion'];

let _client: Stripe | null = null;
export function getStripeClient(): Stripe {
  if (!_client) {
    _client = new Stripe(env.STRIPE_SECRET_KEY, {
      apiVersion: STRIPE_API_VERSION,
      appInfo: { name: env.APP_NAME, version: '1.0.0' },
    });
  }
  return _client;
}
```

The `satisfies` ensures TypeScript compiles only if Stripe's SDK accepts that API version.

---

## Reference

- [Stripe API Docs](https://docs.stripe.com/api)
- [Stripe Webhook Events](https://docs.stripe.com/api/events/types)
- [Stripe Test Clocks](https://docs.stripe.com/billing/testing/test-clocks)
- [Stripe Connect](https://docs.stripe.com/connect)
- [Stripe Tax](https://docs.stripe.com/tax)
- [Stripe Customer Portal](https://docs.stripe.com/customer-management/integrate-customer-portal)
- [Stripe Adaptive Pricing](https://docs.stripe.com/payments/currencies/localize-prices/adaptive-pricing)
