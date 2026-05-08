# Quick Reference

Copy-paste ready patterns. Fill in brackets.

---

## Table of Contents

- [Environment Setup](#environment-setup)
- [Stripe Patterns](#stripe-patterns)
- [PayPal Patterns](#paypal-patterns)
- [Webhook Patterns](#webhook-patterns)
- [Database Patterns](#database-patterns)
- [Access Control](#access-control)
- [CLI Auth](#cli-auth)

---

## Environment Setup

### .env Template

```bash
# App
APP_URL=https://yourapp.com
DATABASE_URL=postgresql://...

# Stripe
STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_PUBLISHABLE_KEY=pk_live_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
STRIPE_PRICE_ID=price_xxx

# PayPal
PAYPAL_CLIENT_ID=xxx
PAYPAL_CLIENT_SECRET=xxx
PAYPAL_API_URL=https://api-m.paypal.com
PAYPAL_PLAN_ID=P-xxx
PAYPAL_WEBHOOK_ID=xxx

# Auth
JWT_SECRET=xxx
```

---

## Stripe Patterns

### Create Checkout Session

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
    line_items: [{ price: process.env.STRIPE_PRICE_ID, quantity: 1 }],
    customer_email: session.user.email,
    success_url: `${process.env.APP_URL}/dashboard?payment=success`,
    cancel_url: `${process.env.APP_URL}/pricing?payment=canceled`,
    metadata: { user_id: session.user.id },
    subscription_data: { metadata: { user_id: session.user.id } }
  });

  return Response.json({ url: checkoutSession.url });
}
```

### Customer Portal

```typescript
// app/api/billing/portal/route.ts
export async function POST(req: Request) {
  const session = await getServerSession();
  const subscription = await db.subscriptions.findUnique({
    where: { user_id: session.user.id }
  });

  if (!subscription?.stripe_customer_id) {
    return Response.json({ error: 'No subscription' }, { status: 404 });
  }

  const portalSession = await stripe.billingPortal.sessions.create({
    customer: subscription.stripe_customer_id,
    return_url: `${process.env.APP_URL}/settings/billing`
  });

  return Response.json({ url: portalSession.url });
}
```

### Stripe Webhook Handler

```typescript
// app/api/webhooks/stripe/route.ts
import Stripe from 'stripe';
import { headers } from 'next/headers';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

export async function POST(req: Request) {
  const body = await req.text();
  const signature = headers().get('stripe-signature')!;

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(
      body, signature, process.env.STRIPE_WEBHOOK_SECRET!
    );
  } catch (err) {
    return Response.json({ error: 'Invalid signature' }, { status: 400 });
  }

  switch (event.type) {
    case 'checkout.session.completed':
      await handleCheckoutComplete(event.data.object);
      break;
    case 'customer.subscription.deleted':
      await handleSubscriptionDeleted(event.data.object);
      break;
  }

  return Response.json({ received: true });
}
```

---

## PayPal Patterns

### Get Access Token

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
        'PayPal-Request-Id': `sub_${session.user.id}_${Date.now()}`
      },
      body: JSON.stringify({
        plan_id: process.env.PAYPAL_PLAN_ID,
        subscriber: {
          name: { given_name: session.user.name?.split(' ')[0] || 'User' },
          email_address: session.user.email
        },
        application_context: {
          brand_name: "Your App",
          shipping_preference: "NO_SHIPPING",
          user_action: "SUBSCRIBE_NOW",
          return_url: `${process.env.APP_URL}/api/checkout/paypal/capture?user_id=${session.user.id}`,
          cancel_url: `${process.env.APP_URL}/pricing?payment=canceled`
        },
        custom_id: session.user.id
      })
    }
  ).then(r => r.json());

  const approveLink = subscription.links.find((l: any) => l.rel === 'approve');
  return Response.json({ approvalUrl: approveLink?.href });
}
```

### PayPal Webhook Verification

```typescript
async function verifyPayPalWebhook(body: string, headers: Record<string, string>): Promise<boolean> {
  const auth = await getPayPalAccessToken();

  const res = await fetch(
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

  const result = await res.json();
  return result.verification_status === 'SUCCESS';
}
```

---

## Webhook Patterns

### Idempotency Guard

```typescript
async function isEventProcessed(provider: 'stripe' | 'paypal', eventId: string): Promise<boolean> {
  const existing = await db.processedWebhookEvent.findUnique({
    where: { provider_eventId: { provider, eventId } }
  });
  return !!existing;
}

async function markEventProcessed(provider: 'stripe' | 'paypal', eventId: string) {
  await db.processedWebhookEvent.create({
    data: { provider, eventId, processedAt: new Date() }
  });
}

// Usage
async function handleStripeEvent(event: Stripe.Event) {
  if (await isEventProcessed('stripe', event.id)) return;
  // ... handle event ...
  await markEventProcessed('stripe', event.id);
}
```

### Checkout Complete Handler

```typescript
async function handleCheckoutComplete(session: Stripe.Checkout.Session) {
  const userId = session.metadata?.user_id;
  if (!userId) return;

  const subscription = await stripe.subscriptions.retrieve(session.subscription as string);

  await db.subscription.upsert({
    where: { userId },
    create: {
      userId,
      provider: 'stripe',
      stripeCustomerId: session.customer as string,
      stripeSubscriptionId: subscription.id,
      status: 'active',
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
}
```

### Subscription Deleted Handler

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

## Database Patterns

### Subscriptions Table (SQL)

```sql
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('stripe', 'paypal')),

  -- Stripe (NULL if PayPal)
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT UNIQUE,
  stripe_price_id TEXT,

  -- PayPal (NULL if Stripe)
  paypal_subscription_id TEXT UNIQUE,
  paypal_plan_id TEXT,

  -- Unified
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'past_due', 'canceled', 'suspended')),
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  cancel_at_period_end BOOLEAN DEFAULT FALSE,
  canceled_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id)
);
```

### Prisma Schema

```prisma
model Subscription {
  id        String   @id @default(uuid())
  userId    String   @unique @map("user_id")
  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  provider  String

  stripeCustomerId     String?  @map("stripe_customer_id")
  stripeSubscriptionId String?  @unique @map("stripe_subscription_id")
  stripePriceId        String?  @map("stripe_price_id")

  paypalSubscriptionId String?  @unique @map("paypal_subscription_id")
  paypalPlanId         String?  @map("paypal_plan_id")

  status               String   @default("active")
  currentPeriodStart   DateTime? @map("current_period_start")
  currentPeriodEnd     DateTime? @map("current_period_end")
  cancelAtPeriodEnd    Boolean  @default(false) @map("cancel_at_period_end")
  canceledAt           DateTime? @map("canceled_at")

  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  @@map("subscriptions")
}
```

### RLS Policy (Supabase)

```sql
-- Premium content: active subscribers only
CREATE POLICY "active_subscribers_only"
ON premium_content FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM subscriptions
    WHERE subscriptions.user_id = auth.uid()
    AND subscriptions.status IN ('active', 'past_due')
  )
);
```

---

## Access Control

### Check Active Subscription

```typescript
async function isActiveSubscriber(userId: string): Promise<boolean> {
  const sub = await db.subscription.findUnique({
    where: { userId },
    select: { status: true, currentPeriodEnd: true }
  });

  if (!sub) return false;
  if (sub.status === 'active') return true;
  if (sub.status === 'past_due' && sub.currentPeriodEnd > new Date()) return true;
  return false;
}
```

### API Middleware

```typescript
export async function validateApiRequest(req: Request) {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return null;

  const token = authHeader.slice(7);
  const payload = await verifyAccessToken(token);
  if (!payload) return null;

  const isActive = await isActiveSubscriber(payload.userId);
  return { userId: payload.userId, isActive };
}

// Usage in API route
export async function GET(req: Request) {
  const auth = await validateApiRequest(req);
  if (!auth) return Response.json({ error: 'Unauthorized' }, { status: 401 });
  if (!auth.isActive) return Response.json({ error: 'Subscription required' }, { status: 402 });
  // ...
}
```

---

## CLI Auth

### Rust Token Storage (keyring)

```rust
use keyring::Entry;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct AuthTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: i64,
}

const SERVICE_NAME: &str = "your-cli";

pub fn store_tokens(tokens: &AuthTokens) -> Result<(), keyring::Error> {
    let entry = Entry::new(SERVICE_NAME, "auth_tokens")?;
    let json = serde_json::to_string(tokens).unwrap();
    entry.set_password(&json)
}

pub fn get_tokens() -> Result<Option<AuthTokens>, keyring::Error> {
    let entry = Entry::new(SERVICE_NAME, "auth_tokens")?;
    match entry.get_password() {
        Ok(json) => Ok(serde_json::from_str(&json).ok()),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e),
    }
}
```

### Rust API Client with 402 Handling

```rust
impl ApiClient {
    pub async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T, ApiError> {
        let token = ensure_valid_token().await?;

        let response = self.client
            .get(format!("{}{}", self.base_url, path))
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .await?;

        match response.status() {
            status if status.is_success() => Ok(response.json().await?),
            reqwest::StatusCode::UNAUTHORIZED => Err(ApiError::Unauthorized),
            reqwest::StatusCode::PAYMENT_REQUIRED => {
                Err(ApiError::SubscriptionRequired(
                    "Subscribe at https://yourapp.com/pricing"
                ))
            }
            _ => Err(ApiError::ServerError(response.status().as_u16()))
        }
    }
}
```

---

## Status Mapping

```typescript
// Stripe → Internal
const stripeStatusMap: Record<string, string> = {
  active: 'active',
  past_due: 'past_due',
  canceled: 'canceled',
  unpaid: 'suspended',
  incomplete: 'suspended',
  incomplete_expired: 'canceled',
  trialing: 'active',
  paused: 'suspended'
};

// PayPal → Internal
const paypalStatusMap: Record<string, string> = {
  ACTIVE: 'active',
  SUSPENDED: 'suspended',
  CANCELLED: 'canceled',
  APPROVAL_PENDING: 'suspended',
  APPROVED: 'active'
};
```

---

## Error Handling Template

```typescript
try {
  const session = await stripe.checkout.sessions.create({...});
  return Response.json({ url: session.url });
} catch (err) {
  if (err instanceof Stripe.errors.StripeError) {
    console.error('Stripe error:', err.message);
    return Response.json({ error: 'Payment service error' }, { status: 500 });
  }
  throw err;
}
```

---

## See Also

- [STRIPE.md](STRIPE.md) - Full Stripe integration
- [PAYPAL.md](PAYPAL.md) - Full PayPal integration
- [WEBHOOKS.md](WEBHOOKS.md) - Complete webhook handlers
- [DATABASE.md](DATABASE.md) - Full schema details
- [CLI-AUTH.md](CLI-AUTH.md) - Complete CLI auth flow
- [TESTING.md](TESTING.md) - Testing patterns
