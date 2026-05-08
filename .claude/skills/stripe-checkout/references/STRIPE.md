# Stripe Integration

Complete Stripe Checkout integration for SaaS subscriptions.

---

## Table of Contents

- [Why Stripe Checkout?](#why-stripe-checkout)
- [Setup](#setup)
- [Checkout Session](#checkout-session)
- [Customer Portal](#customer-portal)
- [PayPal via Stripe](#paypal-via-stripe-optional)
- [Existing Customers](#handling-existing-customers)
- [Region Validation](#region-validation)
- [Proration](#proration-and-plan-changes)
- [Error Handling](#error-handling)
- [Idempotency](#idempotency)

---

## Why Stripe Checkout?

Using Stripe's hosted Checkout provides:

| Feature | Benefit |
|---------|---------|
| PCI Compliance | Stripe handles card data, you never touch it |
| 3D Secure | Automatic authentication when required by banks |
| Apple Pay / Google Pay | Enabled by default |
| Card Storage | Tokenized securely for recurring billing |
| Localized UI | Translated to user's language automatically |

You handle results via webhooks without building your own payment form.

---

## Setup

### 1. Create Product and Price

**Dashboard (recommended):**
1. Go to Products → Add Product
2. Set name, description
3. Add price: $20, Recurring, Monthly
4. Copy the Price ID

**Or via API:**

```typescript
// One-time setup script
const product = await stripe.products.create({
  name: "Pro Subscription",
  description: "Full access to all features"
});

const price = await stripe.prices.create({
  product: product.id,
  unit_amount: 2000,  // $20.00 in cents
  currency: 'usd',
  recurring: { interval: 'month' }
});
// Save price.id as STRIPE_PRICE_ID
```

### 2. Environment Variables

```bash
STRIPE_SECRET_KEY=sk_live_xxx        # or sk_test_xxx for testing
STRIPE_PUBLISHABLE_KEY=pk_live_xxx   # for client-side
STRIPE_WEBHOOK_SECRET=whsec_xxx      # from webhook setup
STRIPE_PRICE_ID=price_xxx            # your price ID
```

### 3. Configure Webhooks

Dashboard → Developers → Webhooks → Add endpoint:
- URL: `https://yourapp.com/api/webhooks/stripe`
- Events:
  - `checkout.session.completed`
  - `invoice.payment_failed`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`

Copy signing secret to `STRIPE_WEBHOOK_SECRET`.

---

## Checkout Session

### Create Session (API Route)

```typescript
// app/api/checkout/stripe/route.ts
import Stripe from 'stripe';
import { getServerSession } from 'next-auth';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

export async function POST(req: Request) {
  const session = await getServerSession();
  if (!session?.user) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const checkoutSession = await stripe.checkout.sessions.create({
    mode: 'subscription',
    payment_method_types: ['card'],
    line_items: [{
      price: process.env.STRIPE_PRICE_ID,
      quantity: 1
    }],
    customer_email: session.user.email,
    success_url: `${process.env.APP_URL}/dashboard?payment=success&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${process.env.APP_URL}/pricing?payment=canceled`,
    metadata: {
      user_id: session.user.id  // Critical: links payment to your user
    },
    subscription_data: {
      metadata: {
        user_id: session.user.id  // Also on subscription for webhook access
      }
    },
    // Optional settings
    locale: 'en',  // Force English
    billing_address_collection: 'required'  // For region validation
  });

  return Response.json({ url: checkoutSession.url });
}
```

### Client-Side Redirect

```typescript
// components/SubscribeButton.tsx
async function handleSubscribe() {
  setLoading(true);
  const res = await fetch('/api/checkout/stripe', { method: 'POST' });
  const { url, error } = await res.json();

  if (error) {
    toast.error(error);
    setLoading(false);
    return;
  }

  window.location.href = url;
}
```

---

## Customer Portal

Let users manage payment methods and cancel:

```typescript
// app/api/billing/portal/route.ts
export async function POST(req: Request) {
  const session = await getServerSession();
  if (!session?.user) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const subscription = await db.subscriptions.findUnique({
    where: { user_id: session.user.id }
  });

  if (!subscription?.stripe_customer_id) {
    return Response.json({ error: 'No subscription found' }, { status: 404 });
  }

  const portalSession = await stripe.billingPortal.sessions.create({
    customer: subscription.stripe_customer_id,
    return_url: `${process.env.APP_URL}/settings/billing`
  });

  return Response.json({ url: portalSession.url });
}
```

**Portal Configuration:**

Dashboard → Settings → Billing → Customer portal:
- Enable subscription cancellation
- Enable payment method updates
- Customize branding

---

## PayPal via Stripe (Optional)

If PayPal is enabled in your Stripe account, you can offer it without separate PayPal API integration:

```typescript
const checkoutSession = await stripe.checkout.sessions.create({
  mode: 'subscription',
  payment_method_types: ['card', 'paypal'],  // Add PayPal
  // ... rest same as above
});
```

**Check availability:** Dashboard → Settings → Payment methods

This lets Stripe handle PayPal billing - single integration, unified reporting.

---

## Handling Existing Customers

If user already has a Stripe customer ID (from previous subscription):

```typescript
const checkoutSession = await stripe.checkout.sessions.create({
  mode: 'subscription',
  customer: existingStripeCustomerId,  // Reuse existing customer
  // Don't use customer_email when using customer
  line_items: [{ price: process.env.STRIPE_PRICE_ID, quantity: 1 }],
  // ... rest of config
});
```

This preserves their saved payment methods and billing history.

---

## Region Validation

If restricting to specific countries (US/CA/UK/AU), validate after checkout:

```typescript
// In checkout.session.completed webhook handler
async function handleCheckoutComplete(session: Stripe.Checkout.Session) {
  const allowedCountries = ['US', 'CA', 'GB', 'AU'];

  // Get customer's country from payment method
  const paymentMethod = await stripe.paymentMethods.retrieve(
    session.payment_method as string
  );
  const country = paymentMethod.billing_details?.address?.country;

  if (country && !allowedCountries.includes(country)) {
    // Cancel and refund
    await stripe.subscriptions.cancel(session.subscription as string);
    await stripe.refunds.create({
      payment_intent: session.payment_intent as string,
      reason: 'requested_by_customer'
    });

    // Notify user
    await sendEmail({
      to: session.customer_email,
      template: 'region-not-supported',
      data: { country }
    });

    return;
  }

  // Proceed with normal activation...
}
```

**Alternative:** State limitations on pricing page and accept anyone who subscribes.

---

## Proration and Plan Changes

For a single plan, proration isn't needed. For multiple tiers:

### Upgrade/Downgrade

```typescript
// Get current subscription item
const subscription = await stripe.subscriptions.retrieve(subscriptionId);
const itemId = subscription.items.data[0].id;

// Change to new price
await stripe.subscriptions.update(subscriptionId, {
  items: [{
    id: itemId,
    price: newPriceId
  }],
  proration_behavior: 'create_prorations'  // or 'none'
});
```

### Proration Behavior Options

| Option | Behavior |
|--------|----------|
| `create_prorations` | Credit for unused time, charge for new |
| `none` | No proration, new price at next renewal |
| `always_invoice` | Invoice immediately |

---

## Error Handling

```typescript
try {
  const session = await stripe.checkout.sessions.create({...});
  return Response.json({ url: session.url });
} catch (err) {
  if (err instanceof Stripe.errors.StripeError) {
    console.error('Stripe error:', err.message);

    // Map to user-friendly messages
    const message = err.type === 'StripeCardError'
      ? 'Card declined. Please try another payment method.'
      : 'Payment service error. Please try again.';

    return Response.json({ error: message }, { status: 500 });
  }
  throw err;
}
```

### Error Types

| Type | Cause |
|------|-------|
| `StripeCardError` | Card declined |
| `StripeRateLimitError` | Too many requests |
| `StripeInvalidRequestError` | Invalid parameters |
| `StripeAPIError` | Stripe server issue |
| `StripeAuthenticationError` | Invalid API key |

---

## Idempotency

For critical operations, use idempotency keys:

```typescript
const session = await stripe.checkout.sessions.create(
  {
    mode: 'subscription',
    // ...
  },
  {
    idempotencyKey: `checkout_${userId}_${Date.now()}`
  }
);
```

This prevents duplicate charges if the request is retried.

---

## Testing

See [TESTING.md](TESTING.md) for complete testing guide.

### Quick Start

```bash
# Install CLI
brew install stripe/stripe-cli/stripe

# Login
stripe login

# Forward webhooks
stripe listen --forward-to localhost:3000/api/webhooks/stripe

# Trigger events
stripe trigger checkout.session.completed
```

### Test Cards

| Card | Result |
|------|--------|
| `4242 4242 4242 4242` | Success |
| `4000 0000 0000 0002` | Declined |
| `4000 0000 0000 3220` | 3DS required |

---

## See Also

- [WEBHOOKS.md](WEBHOOKS.md) - Stripe webhook handling
- [DUNNING.md](DUNNING.md) - Failed payment recovery
- [DATABASE.md](DATABASE.md) - Storing Stripe data
- [TESTING.md](TESTING.md) - Test cards and CLI
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Copy-paste patterns
