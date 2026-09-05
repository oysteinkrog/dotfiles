# PayPal API Reference Card — Billing Endpoints

> **Quick reference for PayPal endpoints relevant to billing.** PayPal's docs are dense and split across products; this card extracts what's actually needed.

PayPal's REST API is HTTP+JSON; no first-party SDK that compares to Stripe's. Use `fetch` directly or community SDKs.

---

## Authentication (OAuth2 client_credentials)

```ts
// Mint access token (cache it; ~9h TTL)
async function getPayPalAccessToken(): Promise<string> {
  const cached = await redis.get('paypal:access_token');
  if (cached) return cached;

  const response = await fetch(`${env.PAYPAL_API_BASE}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${Buffer.from(`${env.PAYPAL_CLIENT_ID}:${env.PAYPAL_CLIENT_SECRET}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  });
  const data = await response.json();
  await redis.set('paypal:access_token', data.access_token, { ex: data.expires_in - 300 });
  return data.access_token;
}

// API base
// Sandbox: https://api-m.sandbox.paypal.com
// Production: https://api-m.paypal.com
```

NEVER print the token. NEVER pass it in shell args.

---

## Plans (the equivalent of Stripe Prices)

```ts
// List plans
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/billing/plans?page_size=20&total_required=true&product_id=${productId}`,
  { headers: { Authorization: `Bearer ${token}` } },
);
const { plans } = await response.json();

// Retrieve a plan (full details)
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/billing/plans/${planId}`,
  { headers: { Authorization: `Bearer ${token}` } },
);

// Plans contain billing_cycles[] (TRIAL + REGULAR), payment_preferences,
// taxes; per § 37b portability + § 4.7 audit
```

### Per-plan audit fields

```
status                   = "ACTIVE" | "INACTIVE" | "CREATED"
billing_cycles[]
  tenure_type            = "TRIAL" | "REGULAR"
  sequence               = 1, 2, ...
  total_cycles           = 0 (infinite) or N
  pricing_scheme.fixed_price.value (string)
  pricing_scheme.fixed_price.currency_code
  frequency.interval_unit = "DAY" | "WEEK" | "MONTH" | "YEAR"
  frequency.interval_count
payment_preferences
  auto_bill_outstanding  (bool)
  setup_fee              {value, currency_code}
  setup_fee_failure_action = "CONTINUE" | "CANCEL"
  payment_failure_threshold (int)
quantity_supported       (bool)
taxes
  percentage             (string, optional)
  inclusive              (bool)
```

---

## Subscriptions

```ts
// Create
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/billing/subscriptions`,
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      'PayPal-Request-Id': buildPayPalRequestId(userId, 'create_subscription', planId),
    },
    body: JSON.stringify({
      plan_id: planId,
      custom_id: userId,  // attacker-controllable; cross-checked in B40 (validatePayPalUserId)
      application_context: {
        brand_name: env.APP_NAME,
        shipping_preference: 'NO_SHIPPING',
        user_action: 'SUBSCRIBE_NOW',
        return_url: `${env.APP_URL}/dashboard?from=checkout`,
        cancel_url: `${env.APP_URL}/pricing?from=cancel`,
      },
    }),
  }
);
const subscription = await response.json();
// Redirect user to: subscription.links.find(l => l.rel === 'approve').href
```

```ts
// Retrieve
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/billing/subscriptions/${subId}`,
  { headers: { Authorization: `Bearer ${token}` } },
);

// Cancel
await fetch(
  `${env.PAYPAL_API_BASE}/v1/billing/subscriptions/${subId}/cancel`,
  {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ reason: 'user_requested' }),
  }
);

// Suspend (pause)
await fetch(
  `${env.PAYPAL_API_BASE}/v1/billing/subscriptions/${subId}/suspend`,
  {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ reason: 'paused_for_org' }),
  }
);

// Activate (resume)
await fetch(
  `${env.PAYPAL_API_BASE}/v1/billing/subscriptions/${subId}/activate`,
  {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ reason: 'org_left' }),
  }
);

// Revise (change plan; quantity-based plans only)
await fetch(
  `${env.PAYPAL_API_BASE}/v1/billing/subscriptions/${subId}/revise`,
  {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ plan_id: newPlanId, quantity: '5' }),
  }
);
// Note: PayPal revise requires buyer re-consent for wallet subs
```

---

## Webhooks

### Verify signature

```ts
async function verifyPayPalWebhookSignature(headers: Headers, body: string, webhookId: string): Promise<boolean> {
  const token = await getPayPalAccessToken();
  const response = await fetch(
    `${env.PAYPAL_API_BASE}/v1/notifications/verify-webhook-signature`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        auth_algo: headers.get('paypal-auth-algo'),
        cert_url: headers.get('paypal-cert-url'),
        transmission_id: headers.get('paypal-transmission-id'),
        transmission_sig: headers.get('paypal-transmission-sig'),
        transmission_time: headers.get('paypal-transmission-time'),
        webhook_id: webhookId,
        webhook_event: JSON.parse(body),
      }),
    }
  );
  const result = await response.json();
  return result.verification_status === 'SUCCESS';
}
```

Signature verification is a NETWORK CALL (unlike Stripe). Cache the access token. Return 503 (NOT 200) if verification call fails.

### Webhook event subscriptions

```ts
// List webhook subscriptions
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/notifications/webhooks/${webhookId}`,
  { headers: { Authorization: `Bearer ${token}` } },
);

// Update subscriptions
await fetch(
  `${env.PAYPAL_API_BASE}/v1/notifications/webhooks/${webhookId}`,
  {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify([
      { op: 'replace', path: '/event_types', value: HANDLED_PAYPAL_EVENTS.map(e => ({ name: e })) },
    ]),
  }
);

// List recent webhook events delivered (last 30 days; useful for forensics)
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/notifications/webhooks-events?` + new URLSearchParams({
    start_time: (new Date(Date.now() - 7 * 86400 * 1000)).toISOString().slice(0, 19) + 'Z',
    end_time: new Date().toISOString().slice(0, 19) + 'Z',
    page_size: '100',
  }),
  { headers: { Authorization: `Bearer ${token}` } },
);
```

Use second-precision timestamps: `2026-05-04T23:41:37Z` (per § 4.7).

---

## Webhook events (the ones to handle)

```ts
const HANDLED_PAYPAL_EVENTS = new Set([
  // Subscription lifecycle
  'BILLING.SUBSCRIPTION.CREATED',
  'BILLING.SUBSCRIPTION.ACTIVATED',
  'BILLING.SUBSCRIPTION.UPDATED',
  'BILLING.SUBSCRIPTION.CANCELLED',
  'BILLING.SUBSCRIPTION.SUSPENDED',
  'BILLING.SUBSCRIPTION.EXPIRED',
  'BILLING.SUBSCRIPTION.PAYMENT.FAILED',

  // Payment lifecycle (the actual money events)
  'PAYMENT.SALE.COMPLETED',
  'PAYMENT.SALE.DENIED',
  'PAYMENT.SALE.REFUNDED',
  'PAYMENT.SALE.REVERSED',

  // Disputes
  'CUSTOMER.DISPUTE.CREATED',
  'CUSTOMER.DISPUTE.UPDATED',
  'CUSTOMER.DISPUTE.RESOLVED',
]);
```

`BILLING.PLAN.UPDATED` is intentionally NOT handled (per § 29.8); it's a plan-config event, not entitlement.

---

## Refunds

```ts
// Refund a sale
await fetch(
  `${env.PAYPAL_API_BASE}/v1/payments/sale/${saleId}/refund`,
  {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      amount: { total: '5.00', currency: 'USD' },  // partial refund
      // OR omit amount for full refund
    }),
  }
);

// Get refund details
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/payments/refund/${refundId}`,
  { headers: { Authorization: `Bearer ${token}` } },
);
```

For partial refund detection (per Billing-H2 / B60):

```ts
// Fetch parent payment to compute cumulative refunded amount
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/payments/payment/${parentPaymentId}`,
  { headers: { Authorization: `Bearer ${token}` } },
);
const parent = await response.json();
// parent.transactions[0].related_resources contains all sales + refunds
```

---

## Disputes

```ts
// List disputes (B125)
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/customer/disputes?page_size=100`,
  { headers: { Authorization: `Bearer ${token}` } },
);

// Retrieve a dispute
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/customer/disputes/${disputeId}`,
  { headers: { Authorization: `Bearer ${token}` } },
);

// Provide evidence
await fetch(
  `${env.PAYPAL_API_BASE}/v1/customer/disputes/${disputeId}/provide-evidence`,
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      // multipart/form-data; PayPal expects evidence + supporting files
    },
    body: formData,
  }
);
```

PayPal disputes are LESS API-friendly than Stripe; the Dashboard is often easier for evidence submission.

---

## Transaction Search (settlement ledger source)

```ts
// Per B75 § Pattern 4
// Max 31-day window; up to 3-hour lag
const response = await fetch(
  `${env.PAYPAL_API_BASE}/v1/reporting/transactions?` + new URLSearchParams({
    start_date: '2026-04-01T00:00:00Z',
    end_date: '2026-04-30T23:59:59Z',
    fields: 'transaction_info',  // counts-only-ish
    balance_affecting_records_only: 'Y',
    page_size: '500',
    page: '1',
  }),
  { headers: { Authorization: `Bearer ${token}` } },
);
```

Use `fields=transaction_info` for low-PII finance jobs; escalate to `fields=all` only in tightly controlled server-side reconciliation (because `payer_info` includes names, emails, addresses).

---

## Adaptive Pricing equivalent

PayPal does NOT have an equivalent to Stripe Adaptive Pricing. For multi-currency: separate plans per currency (per B95 § Pattern 6).

---

## Per-PayPal-plan currency

```ts
BUSINESS.PAYPAL_PLANS = {
  pro_monthly: {
    usd: 'P-XYZ-USD',
    eur: 'P-XYZ-EUR',
    gbp: 'P-XYZ-GBP',
  },
  team_3_seats: {
    usd: 'P-TEAM3-USD',
    eur: 'P-TEAM3-EUR',
  },
};
```

---

## Common PayPal error / response patterns

| HTTP | Meaning | Action |
|------|---------|--------|
| 200/201/204 | Success | Continue |
| 401 | Token expired / invalid | Refresh access token + retry once |
| 403 | Resource permission denied | Don't retry; check credentials |
| 404 | Resource missing | Don't retry; user-friendly fallback |
| 422 | Validation error | Don't retry; fix request shape |
| 429 | Rate limited | Backoff + retry |
| 500+ | PayPal internal | Backoff + retry; alert if persistent |

Always preserve `PayPal-Debug-Id` header from response — it's the support breadcrumb.

---

## Pagination

PayPal endpoints use `page` + `page_size` (NOT cursor-based like Stripe).

```ts
let page = 1;
while (true) {
  const response = await fetch(`...?page=${page}&page_size=100`);
  const data = await response.json();
  if (!data.items || data.items.length === 0) break;
  processItems(data.items);
  page++;
}
```

For Transaction Search: also use `start_date` + `end_date` to bound; PayPal has 31-day max window.

---

## Sandbox specifics

- API base: `https://api-m.sandbox.paypal.com`.
- Sandbox business + buyer accounts created via PayPal Developer Dashboard.
- Webhook simulator: PayPal Dashboard → Notifications → Webhooks → Simulate Event.
- No equivalent to Stripe Test Clocks; tests must wait real time OR replay webhook payloads.

---

## CSP additions for PayPal SDK

If rendering the PayPal Smart Buttons / Payments SDK (per § 78a.5):

```
script-src https://www.paypal.com/sdk/js https://www.paypal.com/...
frame-src https://www.paypal.com https://www.sandbox.paypal.com
img-src https://*.paypalobjects.com
connect-src https://*.paypal.com
```

Pure-redirect PayPal flows don't need CSP additions.

---

## Reference

- [PayPal Subscriptions API](https://developer.paypal.com/docs/api/subscriptions/v1/)
- [PayPal Plans API](https://developer.paypal.com/docs/subscriptions/customize/pricing-plans/)
- [PayPal Webhooks API](https://developer.paypal.com/docs/api/webhooks/v1/)
- [PayPal Webhook Event Types](https://developer.paypal.com/api/rest/webhooks/event-names/)
- [PayPal Transaction Search](https://developer.paypal.com/docs/api/transaction-search/v1/)
- [PayPal Disputes API](https://developer.paypal.com/docs/api/customer-disputes/v1/)
- [PayPal Marketplaces & Platforms](https://developer.paypal.com/docs/multiparty/)
