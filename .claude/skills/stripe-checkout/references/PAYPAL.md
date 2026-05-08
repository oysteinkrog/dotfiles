# PayPal Integration

PayPal subscription integration for users who prefer PayPal wallet.

---

## Table of Contents

- [Setup](#setup)
- [Authentication](#authentication-helper)
- [Server-Side Flow](#option-a-server-side-api-flow)
- [JavaScript SDK Flow](#option-b-javascript-sdk-client-side)
- [Cancellation](#cancel-subscription)
- [Status Checking](#get-subscription-status)
- [Webhook Reliability](#webhook-reliability)
- [Multi-Currency](#multi-currency-plans)

---

## Setup

### 1. Create PayPal App

1. Go to [PayPal Developer Dashboard](https://developer.paypal.com/dashboard/applications)
2. Create app (sandbox for testing, live for production)
3. Note Client ID and Secret

### 2. Environment Variables

```bash
PAYPAL_CLIENT_ID=xxx
PAYPAL_CLIENT_SECRET=xxx
PAYPAL_API_URL=https://api-m.sandbox.paypal.com  # or api-m.paypal.com for live
PAYPAL_PLAN_ID=P-xxx  # created below
PAYPAL_WEBHOOK_ID=xxx  # from webhook setup
```

### 3. Create Product and Plan

```typescript
// One-time setup script
async function setupPayPalPlan() {
  const auth = await getPayPalAccessToken();

  // Create product
  const product = await fetch(`${PAYPAL_API_URL}/v1/catalogs/products`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${auth.access_token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      name: "Pro Subscription",
      description: "Full access to all features",
      type: "SERVICE",
      category: "SOFTWARE"
    })
  }).then(r => r.json());

  // Create plan
  const plan = await fetch(`${PAYPAL_API_URL}/v1/billing/plans`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${auth.access_token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      product_id: product.id,
      name: "Monthly Pro",
      description: "$20/month subscription",
      status: "ACTIVE",
      billing_cycles: [{
        frequency: { interval_unit: "MONTH", interval_count: 1 },
        tenure_type: "REGULAR",
        sequence: 1,
        total_cycles: 0,  // Infinite
        pricing_scheme: {
          fixed_price: { value: "20.00", currency_code: "USD" }
        }
      }],
      payment_preferences: {
        auto_bill_outstanding: true,
        payment_failure_threshold: 3  // Suspend after 3 failures
      }
    })
  }).then(r => r.json());

  console.log('Plan ID:', plan.id);  // Save as PAYPAL_PLAN_ID
}
```

### 4. Configure Webhooks

Dashboard → My Apps → Your App → Add webhook:
- URL: `https://yourapp.com/api/webhooks/paypal`
- Events:
  - `BILLING.SUBSCRIPTION.ACTIVATED`
  - `BILLING.SUBSCRIPTION.CANCELLED`
  - `BILLING.SUBSCRIPTION.SUSPENDED`
  - `PAYMENT.SALE.COMPLETED`

Copy Webhook ID to `PAYPAL_WEBHOOK_ID`.

---

## Authentication Helper

```typescript
// lib/paypal.ts
export async function getPayPalAccessToken() {
  const auth = Buffer.from(
    `${process.env.PAYPAL_CLIENT_ID}:${process.env.PAYPAL_CLIENT_SECRET}`
  ).toString('base64');

  const res = await fetch(`${process.env.PAYPAL_API_URL}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: 'grant_type=client_credentials'
  });

  return res.json();
}
```

---

## Option A: Server-Side API Flow

### Create Subscription

```typescript
// app/api/checkout/paypal/route.ts
export async function POST(req: Request) {
  const session = await getServerSession();
  if (!session?.user) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const auth = await getPayPalAccessToken();

  const subscription = await fetch(
    `${process.env.PAYPAL_API_URL}/v1/billing/subscriptions`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${auth.access_token}`,
        'Content-Type': 'application/json',
        'PayPal-Request-Id': `sub_${session.user.id}_${Date.now()}`  // Idempotency
      },
      body: JSON.stringify({
        plan_id: process.env.PAYPAL_PLAN_ID,
        subscriber: {
          name: { given_name: session.user.name?.split(' ')[0] || 'User' },
          email_address: session.user.email
        },
        application_context: {
          brand_name: "Your App Name",
          locale: "en-US",
          shipping_preference: "NO_SHIPPING",
          user_action: "SUBSCRIBE_NOW",
          return_url: `${process.env.APP_URL}/api/checkout/paypal/capture?user_id=${session.user.id}`,
          cancel_url: `${process.env.APP_URL}/pricing?payment=canceled`
        },
        custom_id: session.user.id  // Links to your user
      })
    }
  ).then(r => r.json());

  // Find the approval link
  const approveLink = subscription.links.find(
    (l: any) => l.rel === 'approve'
  );

  return Response.json({
    subscriptionId: subscription.id,
    approvalUrl: approveLink?.href
  });
}
```

### Capture After Approval

```typescript
// app/api/checkout/paypal/capture/route.ts
export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const subscriptionId = searchParams.get('subscription_id');
  const userId = searchParams.get('user_id');

  if (!subscriptionId || !userId) {
    return Response.redirect(`${process.env.APP_URL}/pricing?error=missing_params`);
  }

  const auth = await getPayPalAccessToken();

  // Get subscription details to confirm it's active
  const subscription = await fetch(
    `${process.env.PAYPAL_API_URL}/v1/billing/subscriptions/${subscriptionId}`,
    { headers: { 'Authorization': `Bearer ${auth.access_token}` } }
  ).then(r => r.json());

  if (subscription.status === 'ACTIVE') {
    // Save to database
    await db.subscriptions.upsert({
      where: { user_id: userId },
      create: {
        user_id: userId,
        provider: 'paypal',
        paypal_subscription_id: subscriptionId,
        status: 'active',
        current_period_end: new Date(subscription.billing_info.next_billing_time)
      },
      update: {
        paypal_subscription_id: subscriptionId,
        status: 'active',
        provider: 'paypal'
      }
    });

    await db.userProfiles.update({
      where: { user_id: userId },
      data: { is_active_subscriber: true }
    });

    return Response.redirect(`${process.env.APP_URL}/dashboard?payment=success`);
  }

  return Response.redirect(`${process.env.APP_URL}/pricing?error=subscription_not_active`);
}
```

---

## Option B: JavaScript SDK (Client-Side)

### HTML/JavaScript

```html
<!-- In your pricing page -->
<script src="https://www.paypal.com/sdk/js?client-id=YOUR_CLIENT_ID&vault=true&intent=subscription"></script>

<div id="paypal-button-container"></div>

<script>
paypal.Buttons({
  style: { layout: 'vertical', color: 'blue', shape: 'rect', label: 'subscribe' },

  createSubscription: function(data, actions) {
    return actions.subscription.create({
      plan_id: 'P-xxx'  // Your plan ID
    });
  },

  onApprove: async function(data, actions) {
    // Send to your backend to save
    const res = await fetch('/api/checkout/paypal/confirm', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ subscriptionId: data.subscriptionID })
    });

    if (res.ok) {
      window.location.href = '/dashboard?payment=success';
    }
  },

  onError: function(err) {
    console.error('PayPal error:', err);
    alert('Payment failed. Please try again.');
  }
}).render('#paypal-button-container');
</script>
```

### Backend Confirmation

```typescript
// app/api/checkout/paypal/confirm/route.ts
export async function POST(req: Request) {
  const session = await getServerSession();
  if (!session?.user) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { subscriptionId } = await req.json();
  const auth = await getPayPalAccessToken();

  // Verify subscription is actually active
  const subscription = await fetch(
    `${process.env.PAYPAL_API_URL}/v1/billing/subscriptions/${subscriptionId}`,
    { headers: { 'Authorization': `Bearer ${auth.access_token}` } }
  ).then(r => r.json());

  if (subscription.status !== 'ACTIVE') {
    return Response.json({ error: 'Subscription not active' }, { status: 400 });
  }

  // Save to database (same as capture route)
  await db.subscriptions.upsert({
    where: { user_id: session.user.id },
    // ... create/update data
  });

  return Response.json({ success: true });
}
```

---

## Cancel Subscription

### Stripe vs PayPal Cancellation

| Provider | Default Behavior | Access After Cancel |
|----------|------------------|---------------------|
| Stripe | `cancel_at_period_end=true` | Until period ends |
| PayPal | Immediate termination | Ends immediately |

### Honoring Paid Period

```typescript
// When PayPal subscription cancels
async function handlePayPalCancellation(subscription: any) {
  const sub = await db.subscription.findUnique({
    where: { paypalSubscriptionId: subscription.id }
  });

  // Don't revoke access immediately - let them use what they paid for
  await db.subscription.update({
    where: { id: sub.id },
    data: {
      status: 'canceled',
      canceledAt: new Date(),
      // Keep is_active_subscriber true until currentPeriodEnd
    }
  });

  // Schedule access revocation for period end
  await scheduleJob('revoke-access', {
    userId: sub.userId,
    runAt: sub.currentPeriodEnd
  });
}
```

### Cancel via API

```typescript
// app/api/subscriptions/cancel/paypal/route.ts
export async function POST(req: Request) {
  const session = await getServerSession();
  const subscription = await db.subscriptions.findUnique({
    where: { user_id: session.user.id }
  });

  if (!subscription?.paypal_subscription_id) {
    return Response.json({ error: 'No PayPal subscription' }, { status: 404 });
  }

  const auth = await getPayPalAccessToken();

  await fetch(
    `${process.env.PAYPAL_API_URL}/v1/billing/subscriptions/${subscription.paypal_subscription_id}/cancel`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${auth.access_token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ reason: "User requested cancellation" })
    }
  );

  // Update database
  await db.subscriptions.update({
    where: { user_id: session.user.id },
    data: { status: 'canceled' }
  });

  return Response.json({ success: true });
}
```

---

## Get Subscription Status

```typescript
export async function getPayPalSubscriptionStatus(subscriptionId: string) {
  const auth = await getPayPalAccessToken();

  const subscription = await fetch(
    `${process.env.PAYPAL_API_URL}/v1/billing/subscriptions/${subscriptionId}`,
    { headers: { 'Authorization': `Bearer ${auth.access_token}` } }
  ).then(r => r.json());

  return {
    status: subscription.status,  // ACTIVE, SUSPENDED, CANCELLED
    nextBillingTime: subscription.billing_info?.next_billing_time,
    lastPayment: subscription.billing_info?.last_payment
  };
}
```

### Status Values

| PayPal Status | Meaning |
|---------------|---------|
| `APPROVAL_PENDING` | User hasn't approved yet |
| `APPROVED` | Approved but not yet active |
| `ACTIVE` | Active and billing |
| `SUSPENDED` | Payment failures, can be reactivated |
| `CANCELLED` | Permanently cancelled |
| `EXPIRED` | Billing cycles completed |

---

## Webhook Reliability

PayPal webhooks can be less reliable than Stripe. Consider a daily sync:

```typescript
// Daily sync job (safety net)
async function syncPayPalSubscriptions() {
  const paypalSubs = await db.subscriptions.findMany({
    where: { provider: 'paypal', status: { in: ['active', 'past_due'] } }
  });

  for (const sub of paypalSubs) {
    const status = await getPayPalSubscriptionStatus(sub.paypal_subscription_id);

    const internalStatus = {
      'ACTIVE': 'active',
      'SUSPENDED': 'suspended',
      'CANCELLED': 'canceled'
    }[status.status];

    if (internalStatus && internalStatus !== sub.status) {
      await db.subscriptions.update({
        where: { id: sub.id },
        data: { status: internalStatus }
      });

      // Update user profile
      await db.userProfile.update({
        where: { userId: sub.userId },
        data: { isActiveSubscriber: internalStatus === 'active' }
      });
    }
  }
}
```

---

## Multi-Currency Plans

A PayPal plan is tied to ONE currency. For multi-currency:

```typescript
// Create separate plans per currency
const plans = {
  USD: 'P-USD-xxx',
  GBP: 'P-GBP-xxx',
  CAD: 'P-CAD-xxx',
  AUD: 'P-AUD-xxx'
};

// Select based on user preference/location
function getPlanForUser(user: User): string {
  const currency = user.preferredCurrency || detectCurrencyByCountry(user.country);
  return plans[currency] || plans.USD;
}

// Use in subscription creation
const subscription = await createPayPalSubscription({
  plan_id: getPlanForUser(user),
  // ...
});
```

---

## Testing

See [TESTING.md](TESTING.md) for complete testing guide.

### Quick Start

1. Use sandbox credentials from PayPal Developer Dashboard
2. Create sandbox buyer accounts for testing
3. Use ngrok to expose local server for webhooks
4. Test: subscribe → payment → webhook → cancel

```bash
# Expose local server
ngrok http 3000

# Update PayPal webhook URL to ngrok URL
```

---

## See Also

- [WEBHOOKS.md](WEBHOOKS.md) - PayPal webhook handling
- [DUNNING.md](DUNNING.md) - Failed payment recovery
- [DATABASE.md](DATABASE.md) - Storing PayPal data
- [TESTING.md](TESTING.md) - Sandbox testing
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Copy-paste patterns
