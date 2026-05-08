# Webhook Implementation

Secure webhook handlers for Stripe and PayPal subscription events.

---

## Table of Contents

- [Stripe Webhooks](#stripe-webhooks)
- [PayPal Webhooks](#paypal-webhooks)
- [Idempotency](#idempotency)
- [Dashboard Setup](#dashboard-setup)
- [Error Handling](#error-handling)
- [Monitoring](#monitoring)

---

## Stripe Webhooks

### Endpoint Setup

```typescript
// app/api/webhooks/stripe/route.ts
import Stripe from 'stripe';
import { headers } from 'next/headers';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

export async function POST(req: Request) {
  const body = await req.text();
  const signature = headers().get('stripe-signature')!;

  let event: Stripe.Event;

  // 1. Verify signature (CRITICAL - never skip)
  try {
    event = stripe.webhooks.constructEvent(
      body,
      signature,
      process.env.STRIPE_WEBHOOK_SECRET!
    );
  } catch (err) {
    console.error('Webhook signature verification failed:', err);
    return Response.json({ error: 'Invalid signature' }, { status: 400 });
  }

  // 2. Handle event (idempotently)
  try {
    await handleStripeEvent(event);
  } catch (err) {
    console.error('Webhook handler error:', err);
    // Return 200 anyway to prevent retries for app errors
  }

  return Response.json({ received: true });
}

async function handleStripeEvent(event: Stripe.Event) {
  switch (event.type) {
    case 'checkout.session.completed':
      await handleCheckoutComplete(event.data.object as Stripe.Checkout.Session);
      break;
    case 'invoice.payment_failed':
      await handlePaymentFailed(event.data.object as Stripe.Invoice);
      break;
    case 'customer.subscription.updated':
      await handleSubscriptionUpdated(event.data.object as Stripe.Subscription);
      break;
    case 'customer.subscription.deleted':
      await handleSubscriptionDeleted(event.data.object as Stripe.Subscription);
      break;
    default:
      console.log(`Unhandled event type: ${event.type}`);
  }
}
```

### Event Handlers

#### Checkout Complete

```typescript
async function handleCheckoutComplete(session: Stripe.Checkout.Session) {
  const userId = session.metadata?.user_id;
  if (!userId) {
    console.error('No user_id in checkout session metadata');
    return;
  }

  const subscription = await stripe.subscriptions.retrieve(
    session.subscription as string
  );

  await db.subscription.upsert({
    where: { userId },
    create: {
      userId,
      provider: 'stripe',
      stripeCustomerId: session.customer as string,
      stripeSubscriptionId: subscription.id,
      stripePriceId: subscription.items.data[0].price.id,
      status: 'active',
      currentPeriodStart: new Date(subscription.current_period_start * 1000),
      currentPeriodEnd: new Date(subscription.current_period_end * 1000)
    },
    update: {
      provider: 'stripe',
      stripeCustomerId: session.customer as string,
      stripeSubscriptionId: subscription.id,
      status: 'active',
      currentPeriodEnd: new Date(subscription.current_period_end * 1000)
    }
  });

  await db.userProfile.update({
    where: { userId },
    data: { isActiveSubscriber: true }
  });

  // Optional: Send welcome email
  await sendWelcomeEmail(userId);
}
```

#### Payment Failed

```typescript
async function handlePaymentFailed(invoice: Stripe.Invoice) {
  const subscriptionId = invoice.subscription as string;
  if (!subscriptionId) return;

  console.log(`Payment failed for subscription ${subscriptionId}`);

  await db.subscription.update({
    where: { stripeSubscriptionId: subscriptionId },
    data: { status: 'past_due' }
  });

  // Optional: Send notification email
  const sub = await db.subscription.findUnique({
    where: { stripeSubscriptionId: subscriptionId },
    include: { user: true }
  });

  if (sub) {
    await sendPaymentFailedEmail(sub.user.email);
  }
}
```

#### Subscription Updated

```typescript
async function handleSubscriptionUpdated(subscription: Stripe.Subscription) {
  const statusMap: Record<string, string> = {
    active: 'active',
    past_due: 'past_due',
    canceled: 'canceled',
    unpaid: 'suspended',
    incomplete: 'suspended',
    incomplete_expired: 'canceled',
    trialing: 'active',
    paused: 'suspended'
  };

  const status = statusMap[subscription.status] || 'suspended';

  await db.subscription.update({
    where: { stripeSubscriptionId: subscription.id },
    data: {
      status,
      currentPeriodEnd: new Date(subscription.current_period_end * 1000),
      cancelAtPeriodEnd: subscription.cancel_at_period_end,
      canceledAt: subscription.canceled_at
        ? new Date(subscription.canceled_at * 1000)
        : null
    }
  });

  // Sync user profile flag
  const sub = await db.subscription.findUnique({
    where: { stripeSubscriptionId: subscription.id }
  });

  if (sub) {
    await db.userProfile.update({
      where: { userId: sub.userId },
      data: { isActiveSubscriber: status === 'active' }
    });
  }
}
```

#### Subscription Deleted

```typescript
async function handleSubscriptionDeleted(subscription: Stripe.Subscription) {
  const sub = await db.subscription.findUnique({
    where: { stripeSubscriptionId: subscription.id }
  });

  if (!sub) return;

  await db.subscription.update({
    where: { stripeSubscriptionId: subscription.id },
    data: { status: 'canceled', canceledAt: new Date() }
  });

  await db.userProfile.update({
    where: { userId: sub.userId },
    data: { isActiveSubscriber: false }
  });

  // Revoke API keys
  await db.apiKey.updateMany({
    where: { userId: sub.userId, revokedAt: null },
    data: { revokedAt: new Date() }
  });
}
```

---

## PayPal Webhooks

### Endpoint Setup

```typescript
// app/api/webhooks/paypal/route.ts
export async function POST(req: Request) {
  const body = await req.text();
  const headers = Object.fromEntries(req.headers.entries());

  // 1. Verify webhook signature
  const isValid = await verifyPayPalWebhook(body, headers);
  if (!isValid) {
    console.error('PayPal webhook verification failed');
    return Response.json({ error: 'Invalid signature' }, { status: 400 });
  }

  const event = JSON.parse(body);

  // 2. Handle event
  try {
    await handlePayPalEvent(event);
  } catch (err) {
    console.error('PayPal webhook handler error:', err);
  }

  return Response.json({ received: true });
}
```

### Signature Verification

```typescript
async function verifyPayPalWebhook(
  body: string,
  headers: Record<string, string>
): Promise<boolean> {
  const auth = await getPayPalAccessToken();

  const verifyResponse = await fetch(
    `${process.env.PAYPAL_API_URL}/v1/notifications/verify-webhook-signature`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${auth.access_token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        auth_algo: headers['paypal-auth-algo'],
        cert_url: headers['paypal-cert-url'],
        transmission_id: headers['paypal-transmission-id'],
        transmission_sig: headers['paypal-transmission-sig'],
        transmission_time: headers['paypal-transmission-time'],
        webhook_id: process.env.PAYPAL_WEBHOOK_ID,
        webhook_event: JSON.parse(body)
      })
    }
  );

  const result = await verifyResponse.json();
  return result.verification_status === 'SUCCESS';
}
```

### Event Handlers

```typescript
async function handlePayPalEvent(event: any) {
  switch (event.event_type) {
    case 'BILLING.SUBSCRIPTION.ACTIVATED':
      await handlePayPalActivated(event.resource);
      break;
    case 'PAYMENT.SALE.COMPLETED':
      await handlePayPalPaymentCompleted(event.resource);
      break;
    case 'BILLING.SUBSCRIPTION.CANCELLED':
      await handlePayPalCancelled(event.resource);
      break;
    case 'BILLING.SUBSCRIPTION.SUSPENDED':
      await handlePayPalSuspended(event.resource);
      break;
    default:
      console.log(`Unhandled PayPal event: ${event.event_type}`);
  }
}
```

#### Subscription Activated

```typescript
async function handlePayPalActivated(subscription: any) {
  const userId = subscription.custom_id;

  if (!userId) {
    console.error('No custom_id in PayPal subscription');
    return;
  }

  await db.subscription.upsert({
    where: { userId },
    create: {
      userId,
      provider: 'paypal',
      paypalSubscriptionId: subscription.id,
      paypalPlanId: subscription.plan_id,
      status: 'active',
      currentPeriodStart: new Date(subscription.start_time),
      currentPeriodEnd: subscription.billing_info?.next_billing_time
        ? new Date(subscription.billing_info.next_billing_time)
        : null
    },
    update: {
      provider: 'paypal',
      paypalSubscriptionId: subscription.id,
      status: 'active'
    }
  });

  await db.userProfile.update({
    where: { userId },
    data: { isActiveSubscriber: true }
  });
}
```

#### Payment Completed

```typescript
async function handlePayPalPaymentCompleted(payment: any) {
  const subscriptionId = payment.billing_agreement_id;
  if (!subscriptionId) return;

  console.log(`PayPal payment completed: ${payment.id}`);

  const sub = await db.subscription.findUnique({
    where: { paypalSubscriptionId: subscriptionId }
  });

  if (sub) {
    // Extend period by 1 month
    const nextPeriodEnd = new Date();
    nextPeriodEnd.setMonth(nextPeriodEnd.getMonth() + 1);

    await db.subscription.update({
      where: { paypalSubscriptionId: subscriptionId },
      data: { status: 'active', currentPeriodEnd: nextPeriodEnd }
    });
  }
}
```

#### Subscription Cancelled/Suspended

```typescript
async function handlePayPalCancelled(subscription: any) {
  const sub = await db.subscription.findUnique({
    where: { paypalSubscriptionId: subscription.id }
  });

  if (!sub) return;

  await db.subscription.update({
    where: { paypalSubscriptionId: subscription.id },
    data: { status: 'canceled', canceledAt: new Date() }
  });

  await db.userProfile.update({
    where: { userId: sub.userId },
    data: { isActiveSubscriber: false }
  });

  await db.apiKey.updateMany({
    where: { userId: sub.userId, revokedAt: null },
    data: { revokedAt: new Date() }
  });
}

async function handlePayPalSuspended(subscription: any) {
  await db.subscription.update({
    where: { paypalSubscriptionId: subscription.id },
    data: { status: 'suspended' }
  });

  const sub = await db.subscription.findUnique({
    where: { paypalSubscriptionId: subscription.id }
  });

  if (sub) {
    await db.userProfile.update({
      where: { userId: sub.userId },
      data: { isActiveSubscriber: false }
    });

    await sendSubscriptionSuspendedEmail(sub.userId);
  }
}
```

---

## Idempotency

Both Stripe and PayPal may retry webhooks. Ensure handlers are idempotent:

### Processed Events Table

```sql
CREATE TABLE processed_webhook_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider TEXT NOT NULL,
  event_id TEXT NOT NULL,
  processed_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(provider, event_id)
);
```

### Check Before Processing

```typescript
async function isEventProcessed(
  provider: 'stripe' | 'paypal',
  eventId: string
): Promise<boolean> {
  const existing = await db.processedWebhookEvent.findUnique({
    where: { provider_eventId: { provider, eventId } }
  });
  return !!existing;
}

async function markEventProcessed(
  provider: 'stripe' | 'paypal',
  eventId: string
) {
  await db.processedWebhookEvent.create({
    data: { provider, eventId, processedAt: new Date() }
  });
}

// Usage
async function handleStripeEvent(event: Stripe.Event) {
  if (await isEventProcessed('stripe', event.id)) {
    console.log(`Event ${event.id} already processed, skipping`);
    return;
  }

  // ... handle event ...

  await markEventProcessed('stripe', event.id);
}
```

---

## Dashboard Setup

### Stripe

1. Go to **Developers → Webhooks**
2. Add endpoint: `https://yourapp.com/api/webhooks/stripe`
3. Select events:
   - `checkout.session.completed`
   - `invoice.payment_failed`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
4. Copy signing secret to `STRIPE_WEBHOOK_SECRET`

### PayPal

1. Go to **Developer Dashboard → My Apps → Your App**
2. Add webhook URL: `https://yourapp.com/api/webhooks/paypal`
3. Select events:
   - `BILLING.SUBSCRIPTION.ACTIVATED`
   - `BILLING.SUBSCRIPTION.CANCELLED`
   - `BILLING.SUBSCRIPTION.SUSPENDED`
   - `PAYMENT.SALE.COMPLETED`
4. Copy Webhook ID to `PAYPAL_WEBHOOK_ID`

---

## Error Handling

### Return 200 to Prevent Retries

```typescript
export async function POST(req: Request) {
  try {
    // ... verification and handling
  } catch (err) {
    // Log to monitoring service
    console.error('Webhook error:', err);

    // Return 200 for app errors - prevents infinite retries
    // Only return 4xx for signature errors
    return Response.json({ received: true, error: 'Processing error' });
  }
}
```

### Error Types

| Return Code | When to Use |
|-------------|-------------|
| 200 | Event processed successfully |
| 200 + error | App error (prevents retries) |
| 400 | Invalid signature |
| 500 | Never (causes retries) |

---

## Monitoring

### Key Alerts

- Failed signature verifications (potential attacks)
- Unhandled event types
- Handler errors
- High webhook latency (>30s)

### Logging Pattern

```typescript
async function handleStripeEvent(event: Stripe.Event) {
  const startTime = Date.now();

  console.log(`Processing ${event.type} (${event.id})`);

  try {
    // ... handle
    console.log(`Completed ${event.type} in ${Date.now() - startTime}ms`);
  } catch (err) {
    console.error(`Failed ${event.type}: ${err.message}`);
    throw err;
  }
}
```

---

## Testing

See [TESTING.md](TESTING.md) for complete testing guide.

### Quick Test

```bash
# Stripe CLI
stripe listen --forward-to localhost:3000/api/webhooks/stripe
stripe trigger checkout.session.completed

# PayPal (use ngrok)
ngrok http 3000
# Update PayPal webhook URL to ngrok URL
```

---

## See Also

- [STRIPE.md](STRIPE.md) - Stripe integration
- [PAYPAL.md](PAYPAL.md) - PayPal integration
- [DUNNING.md](DUNNING.md) - Payment failure handling
- [TESTING.md](TESTING.md) - Testing webhooks
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Copy-paste patterns
