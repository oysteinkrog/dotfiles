# Testing Patterns

Complete testing guide for Stripe and PayPal subscription flows.

---

## Table of Contents

- [Stripe Testing](#stripe-testing)
- [PayPal Testing](#paypal-testing)
- [Webhook Testing](#webhook-testing)
- [Database Testing](#database-testing)
- [CLI Testing](#cli-testing)
- [End-to-End Checklist](#end-to-end-checklist)

---

## Stripe Testing

### Setup Stripe CLI

```bash
# Install
brew install stripe/stripe-cli/stripe

# Login
stripe login

# Forward webhooks to local dev
stripe listen --forward-to localhost:3000/api/webhooks/stripe

# Note the webhook signing secret it prints - use for STRIPE_WEBHOOK_SECRET
```

### Trigger Test Events

```bash
# Successful checkout
stripe trigger checkout.session.completed

# Payment failure
stripe trigger invoice.payment_failed

# Subscription canceled
stripe trigger customer.subscription.deleted

# Subscription updated
stripe trigger customer.subscription.updated

# Card will expire soon
stripe trigger customer.source.expiring
```

### Test Cards

| Card Number | Scenario |
|-------------|----------|
| `4242 4242 4242 4242` | Success |
| `4000 0000 0000 0002` | Card declined |
| `4000 0000 0000 3220` | 3D Secure required |
| `4000 0000 0000 9995` | Insufficient funds |
| `4000 0000 0000 0341` | Card attached but will fail on charge |
| `4000 0025 0000 3155` | Requires authentication (3DS) |

### Test with Specific Regions

```bash
# Use test cards for specific countries
4000 0000 0000 0077  # US
4000 0082 6000 0000  # UK
4000 0003 6000 0006  # AU
4000 0012 4000 0000  # CA
```

### Testing Webhooks Locally

```bash
# Terminal 1: Start your dev server
npm run dev

# Terminal 2: Forward webhooks
stripe listen --forward-to localhost:3000/api/webhooks/stripe

# Terminal 3: Trigger events
stripe trigger checkout.session.completed
```

### Verify Webhook Received

```typescript
// Add logging in your webhook handler
export async function POST(req: Request) {
  console.log('Stripe webhook received');

  const body = await req.text();
  const signature = headers().get('stripe-signature')!;

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(body, signature, process.env.STRIPE_WEBHOOK_SECRET!);
    console.log(`Event type: ${event.type}`);
  } catch (err) {
    console.error('Signature verification failed:', err);
    return Response.json({ error: 'Invalid signature' }, { status: 400 });
  }

  // Handle event...
  console.log(`Handled: ${event.type}`);
  return Response.json({ received: true });
}
```

---

## PayPal Testing

### Sandbox Setup

1. Go to [PayPal Developer Dashboard](https://developer.paypal.com/dashboard/applications)
2. Create sandbox app
3. Note Client ID and Secret
4. Set `PAYPAL_API_URL=https://api-m.sandbox.paypal.com`

### Create Sandbox Accounts

Dashboard → Sandbox → Accounts:
- **Business account** - receives payments (your app)
- **Personal account** - makes payments (test buyer)

### Test Credentials

Default sandbox buyer:
- Email: `sb-xxx@personal.example.com` (shown in dashboard)
- Password: Usually shown or you can set it

### Testing Flow

```bash
# 1. Start dev server
npm run dev

# 2. Expose for PayPal webhooks (required for callbacks)
ngrok http 3000

# 3. Update PayPal webhook URL to ngrok URL
# In PayPal Dashboard → Your App → Webhooks → Add webhook
# URL: https://your-ngrok-url.ngrok.io/api/webhooks/paypal

# 4. Create subscription via your checkout flow
# 5. Login with sandbox personal account
# 6. Approve subscription
# 7. Verify webhook received
```

### PayPal Test Scenarios

```typescript
// Test subscription creation
const subscription = await createPayPalSubscription(testUserId);
console.log('Subscription ID:', subscription.id);
console.log('Approval URL:', subscription.approvalUrl);

// Test subscription status check
const status = await getPayPalSubscriptionStatus(subscriptionId);
console.log('Status:', status);  // ACTIVE, SUSPENDED, CANCELLED

// Test cancellation
await cancelPayPalSubscription(subscriptionId);
```

### Debug PayPal API Calls

```typescript
// Add logging wrapper
async function paypalFetch(url: string, options: RequestInit) {
  console.log(`PayPal API: ${options.method} ${url}`);
  const response = await fetch(url, options);
  const data = await response.json();

  if (!response.ok) {
    console.error('PayPal error:', JSON.stringify(data, null, 2));
  } else {
    console.log('PayPal response:', JSON.stringify(data, null, 2));
  }

  return data;
}
```

---

## Webhook Testing

### Signature Verification Test

```typescript
// Test that invalid signatures are rejected
describe('Stripe webhook', () => {
  it('rejects invalid signature', async () => {
    const response = await fetch('/api/webhooks/stripe', {
      method: 'POST',
      headers: {
        'stripe-signature': 'invalid'
      },
      body: JSON.stringify({ type: 'test' })
    });

    expect(response.status).toBe(400);
  });
});
```

### Idempotency Test

```typescript
// Test that duplicate events are handled gracefully
describe('webhook idempotency', () => {
  it('handles duplicate events', async () => {
    const eventId = 'evt_test_123';

    // First call
    await handleStripeEvent({ id: eventId, type: 'checkout.session.completed', ... });

    // Second call (duplicate)
    await handleStripeEvent({ id: eventId, type: 'checkout.session.completed', ... });

    // Should only process once
    const records = await db.subscription.findMany({ where: { /* ... */ } });
    expect(records.length).toBe(1);
  });
});
```

### Mock Webhook Events

```typescript
// fixtures/stripe-events.ts
export const checkoutCompletedEvent = {
  id: 'evt_test_checkout_completed',
  type: 'checkout.session.completed',
  data: {
    object: {
      id: 'cs_test_xxx',
      customer: 'cus_test_xxx',
      subscription: 'sub_test_xxx',
      metadata: { user_id: 'test-user-id' }
    }
  }
};

export const subscriptionDeletedEvent = {
  id: 'evt_test_subscription_deleted',
  type: 'customer.subscription.deleted',
  data: {
    object: {
      id: 'sub_test_xxx',
      customer: 'cus_test_xxx',
      status: 'canceled'
    }
  }
};
```

---

## Database Testing

### Verify Subscription Created

```sql
-- After checkout completion
SELECT * FROM subscriptions WHERE user_id = 'test-user-id';

-- Expected:
-- provider: 'stripe'
-- status: 'active'
-- stripe_subscription_id: 'sub_xxx'
-- current_period_end: (future date)
```

### Verify User Profile Updated

```sql
-- Check subscriber flag
SELECT is_active_subscriber FROM user_profiles WHERE user_id = 'test-user-id';

-- Should be: true
```

### Test RLS Policies

```sql
-- As authenticated user (active subscriber)
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub": "active-user-id"}';

SELECT COUNT(*) FROM premium_content;  -- Should return rows

-- As unauthenticated or inactive user
SET LOCAL request.jwt.claims TO '{"sub": "inactive-user-id"}';

SELECT COUNT(*) FROM premium_content;  -- Should return 0
```

### Test Grace Period

```typescript
// Set subscription to past_due
await db.subscription.update({
  where: { userId: testUserId },
  data: {
    status: 'past_due',
    currentPeriodEnd: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)  // 7 days from now
  }
});

// Verify still has access
const hasAccess = await isActiveSubscriber(testUserId);
expect(hasAccess).toBe(true);

// Set period end to past
await db.subscription.update({
  where: { userId: testUserId },
  data: { currentPeriodEnd: new Date(Date.now() - 1000) }
});

// Verify no access
const hasAccessNow = await isActiveSubscriber(testUserId);
expect(hasAccessNow).toBe(false);
```

---

## CLI Testing

### Test Login Flow

```bash
# Clear any existing tokens
your-cli logout

# Login (opens browser)
your-cli login

# Verify login
your-cli account
# Should show email and subscription status
```

### Test Subscription Check

```bash
# With active subscription
your-cli sync
# Should succeed

# Simulate expired subscription (in DB)
# Then:
your-cli sync
# Should show "Subscription required" message
```

### Test Token Refresh

```typescript
// Set token to expire soon
const tokens = getTokens();
tokens.expires_at = Math.floor(Date.now() / 1000) + 60;  // Expires in 1 minute
storeTokens(tokens);

// Make API call - should trigger refresh
const result = await client.get('/api/v1/data');

// Verify new token stored
const newTokens = getTokens();
expect(newTokens.expires_at).toBeGreaterThan(tokens.expires_at);
```

### Test Revoked Access

```bash
# In database, set subscription to canceled and revoke API keys
# Then:
your-cli sync
# Should fail with 402 or 401

your-cli account
# Should show subscription inactive
```

---

## End-to-End Checklist

### Pre-Launch Testing

- [ ] **Stripe test mode**
  - [ ] Create checkout session
  - [ ] Complete checkout with test card
  - [ ] Verify webhook received
  - [ ] Verify database updated
  - [ ] Verify user can access premium content
  - [ ] Cancel subscription
  - [ ] Verify access revoked

- [ ] **PayPal sandbox** (if using)
  - [ ] Create subscription
  - [ ] Complete approval flow
  - [ ] Verify webhook received
  - [ ] Verify database updated
  - [ ] Cancel subscription
  - [ ] Verify access revoked

- [ ] **Payment failures**
  - [ ] Trigger payment failure (use declining test card)
  - [ ] Verify status becomes past_due
  - [ ] Verify grace period works
  - [ ] Verify final cancellation works

- [ ] **CLI** (if applicable)
  - [ ] Login flow works
  - [ ] Token refresh works
  - [ ] 402 handling works
  - [ ] Logout clears tokens

### Go-Live Checklist

- [ ] Switch to live API keys
- [ ] Update webhook URLs to production
- [ ] Verify webhook signing secrets updated
- [ ] Create production product/price in Stripe
- [ ] Create production plan in PayPal
- [ ] Test with real card (small amount, refund immediately)
- [ ] Monitor first real transactions

---

## Debugging Tips

### Stripe Dashboard

- **Logs**: Dashboard → Developers → Logs
- **Webhooks**: Dashboard → Developers → Webhooks → (endpoint) → Recent deliveries
- **Events**: Dashboard → Developers → Events

### PayPal Dashboard

- **Transactions**: Dashboard → Activity → All Transactions
- **Webhooks**: My Apps → (app) → Webhooks → Event types
- **Sandbox**: Use sandbox dashboard for testing

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Webhook 400 | Invalid signature | Check `WEBHOOK_SECRET` env var |
| No webhook received | Wrong endpoint URL | Verify URL in provider dashboard |
| Subscription not created | Missing `user_id` in metadata | Add to checkout session creation |
| RLS blocking | Policy not matching | Check `auth.uid()` matches user_id |
| CLI 402 | Subscription inactive | Check subscription status in DB |

---

## See Also

- [STRIPE.md](STRIPE.md) - Stripe test cards and CLI
- [PAYPAL.md](PAYPAL.md) - PayPal sandbox setup
- [WEBHOOKS.md](WEBHOOKS.md) - Webhook handler debugging
- [CLI-AUTH.md](CLI-AUTH.md) - CLI auth testing
