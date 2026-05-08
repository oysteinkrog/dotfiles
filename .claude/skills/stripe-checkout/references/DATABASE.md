# Database Schema

Single source of truth for subscription state across Stripe and PayPal.

---

## Table of Contents

- [Core Tables](#core-tables)
- [User Profiles Extension](#user-profiles-extension)
- [API Keys Table](#api-keys-table-for-cli)
- [Row-Level Security](#row-level-security-supabase)
- [Prisma Schema](#prisma-schema)
- [Common Queries](#common-queries)
- [Migrations](#migrations)
- [Audit Log](#audit-log-optional)

---

## Core Tables

### Subscriptions Table

```sql
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Provider identification (only one will be set)
  provider TEXT NOT NULL CHECK (provider IN ('stripe', 'paypal')),

  -- Stripe fields (NULL if PayPal subscription)
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  stripe_price_id TEXT,

  -- PayPal fields (NULL if Stripe subscription)
  paypal_subscription_id TEXT,
  paypal_plan_id TEXT,

  -- Unified status
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'past_due', 'canceled', 'suspended')),

  -- Billing period
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,

  -- Cancellation
  cancel_at_period_end BOOLEAN DEFAULT FALSE,
  canceled_at TIMESTAMPTZ,

  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Constraints
  UNIQUE(user_id),  -- One subscription per user
  UNIQUE(stripe_subscription_id),
  UNIQUE(paypal_subscription_id)
);

CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_subscriptions_provider ON subscriptions(provider);
```

### Status Values

| Status | Meaning | Access |
|--------|---------|--------|
| `active` | Subscription is current | Full access |
| `past_due` | Payment failed, retrying | Grace period |
| `canceled` | Subscription ended | No access |
| `suspended` | PayPal payment failure | No access |

---

## User Profiles Extension

Add quick-access flag for subscription status.

**Why duplicate the flag?** Checking a boolean on the user record is faster for RLS policies than joining the subscriptions table on every query. The flag is synced via trigger or webhook handler.

```sql
ALTER TABLE user_profiles ADD COLUMN is_active_subscriber BOOLEAN DEFAULT FALSE;

-- Trigger to keep in sync (optional, can also update manually)
CREATE OR REPLACE FUNCTION sync_subscriber_flag()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE user_profiles
  SET is_active_subscriber = (NEW.status = 'active')
  WHERE user_id = NEW.user_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER subscription_status_change
AFTER INSERT OR UPDATE OF status ON subscriptions
FOR EACH ROW EXECUTE FUNCTION sync_subscriber_flag();
```

---

## API Keys Table (for CLI)

```sql
CREATE TABLE api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key_hash TEXT NOT NULL,  -- Store hashed, not plaintext
  name TEXT,
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(key_hash)
);

CREATE INDEX idx_api_keys_user ON api_keys(user_id);
CREATE INDEX idx_api_keys_hash ON api_keys(key_hash) WHERE revoked_at IS NULL;
```

### API Key Security

| Principle | Implementation |
|-----------|----------------|
| Store hash only | Never store plaintext keys |
| Show once | Return raw key only on creation |
| Revoke on cancel | Disable keys when subscription ends |
| Track usage | Update last_used_at on each call |

---

## Row-Level Security (Supabase)

### Enable RLS

```sql
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE premium_content ENABLE ROW LEVEL SECURITY;
```

### Subscription Access Policy

```sql
-- Users can only see their own subscription
CREATE POLICY "users_own_subscription"
ON subscriptions FOR ALL
USING (auth.uid() = user_id);
```

### Premium Content Gating

```sql
-- Only active subscribers can access premium content
CREATE POLICY "active_subscribers_only"
ON premium_content FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM subscriptions
    WHERE subscriptions.user_id = auth.uid()
    AND subscriptions.status = 'active'
  )
);

-- Alternative using the user_profiles flag (faster)
CREATE POLICY "active_subscribers_only_v2"
ON premium_content FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM user_profiles
    WHERE user_profiles.user_id = auth.uid()
    AND user_profiles.is_active_subscriber = TRUE
  )
);
```

### Grace Period Policy

Allow access during `past_due` status (Stripe is still retrying):

```sql
CREATE POLICY "active_or_grace_period"
ON premium_content FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM subscriptions
    WHERE subscriptions.user_id = auth.uid()
    AND subscriptions.status IN ('active', 'past_due')
    AND (
      subscriptions.current_period_end IS NULL
      OR subscriptions.current_period_end > NOW()
    )
  )
);
```

### RLS Policy Comparison

| Policy | Performance | Grace Period |
|--------|-------------|--------------|
| Join subscriptions | Slower | Flexible |
| Use user_profiles flag | Faster | None (flag is binary) |
| Hybrid approach | Medium | Flexible |

---

## Prisma Schema

```prisma
model Subscription {
  id        String   @id @default(uuid())
  userId    String   @unique @map("user_id")
  user      User     @relation(fields: [userId], references: [id], onDelete: Cascade)

  provider  String   // 'stripe' | 'paypal'

  // Stripe
  stripeCustomerId     String?  @map("stripe_customer_id")
  stripeSubscriptionId String?  @unique @map("stripe_subscription_id")
  stripePriceId        String?  @map("stripe_price_id")

  // PayPal
  paypalSubscriptionId String?  @unique @map("paypal_subscription_id")
  paypalPlanId         String?  @map("paypal_plan_id")

  // Status
  status               String   @default("active")
  currentPeriodStart   DateTime? @map("current_period_start")
  currentPeriodEnd     DateTime? @map("current_period_end")
  cancelAtPeriodEnd    Boolean  @default(false) @map("cancel_at_period_end")
  canceledAt           DateTime? @map("canceled_at")

  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  @@map("subscriptions")
  @@index([status])
}

model ApiKey {
  id        String    @id @default(uuid())
  userId    String    @map("user_id")
  user      User      @relation(fields: [userId], references: [id], onDelete: Cascade)
  keyHash   String    @unique @map("key_hash")
  name      String?
  lastUsedAt DateTime? @map("last_used_at")
  revokedAt DateTime? @map("revoked_at")
  createdAt DateTime  @default(now()) @map("created_at")

  @@map("api_keys")
  @@index([userId])
}
```

---

## Common Queries

### Check Subscription Status

```typescript
async function isActiveSubscriber(userId: string): Promise<boolean> {
  const sub = await db.subscription.findUnique({
    where: { userId },
    select: { status: true, currentPeriodEnd: true }
  });

  if (!sub) return false;

  // Active or in grace period
  if (sub.status === 'active') return true;
  if (sub.status === 'past_due' && sub.currentPeriodEnd > new Date()) return true;

  return false;
}
```

### Get Full Subscription Details

```typescript
async function getSubscriptionDetails(userId: string) {
  return db.subscription.findUnique({
    where: { userId },
    select: {
      provider: true,
      status: true,
      currentPeriodEnd: true,
      cancelAtPeriodEnd: true,
      stripeCustomerId: true,
      paypalSubscriptionId: true
    }
  });
}
```

### Update from Webhook

```typescript
async function handleSubscriptionUpdate(
  provider: 'stripe' | 'paypal',
  subscriptionId: string,
  updates: Partial<Subscription>
) {
  const where = provider === 'stripe'
    ? { stripeSubscriptionId: subscriptionId }
    : { paypalSubscriptionId: subscriptionId };

  await db.subscription.update({
    where,
    data: {
      ...updates,
      updatedAt: new Date()
    }
  });

  // Also update user profile flag if status changed
  if (updates.status) {
    const sub = await db.subscription.findFirst({ where });
    if (sub) {
      await db.userProfile.update({
        where: { userId: sub.userId },
        data: { isActiveSubscriber: updates.status === 'active' }
      });
    }
  }
}
```

### Revoke API Keys on Subscription End

```typescript
async function revokeUserApiKeys(userId: string) {
  await db.apiKey.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() }
  });
}
```

---

## Migrations

### Initial Migration

```sql
-- migrations/001_subscriptions.sql
CREATE TABLE subscriptions (
  -- ... (schema above)
);

ALTER TABLE user_profiles
ADD COLUMN is_active_subscriber BOOLEAN DEFAULT FALSE;

CREATE TABLE api_keys (
  -- ... (schema above)
);
```

### Adding Indexes

```sql
-- migrations/002_subscription_indexes.sql
CREATE INDEX CONCURRENTLY idx_subscriptions_period_end
ON subscriptions(current_period_end)
WHERE status IN ('active', 'past_due');
```

### Useful Indexes

| Index | Purpose |
|-------|---------|
| `idx_subscriptions_status` | Filter by status |
| `idx_subscriptions_provider` | Filter by provider |
| `idx_subscriptions_period_end` | Find expiring subscriptions |
| `idx_api_keys_hash` | Fast key lookup |

---

## Audit Log (Optional)

Track subscription changes for debugging:

```sql
CREATE TABLE subscription_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id UUID REFERENCES subscriptions(id),
  event_type TEXT NOT NULL,  -- 'created', 'updated', 'canceled', 'payment_failed'
  provider TEXT NOT NULL,
  provider_event_id TEXT,  -- Stripe/PayPal event ID
  old_status TEXT,
  new_status TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Event Types

| Event Type | Trigger |
|------------|---------|
| `created` | New subscription |
| `updated` | Status or period change |
| `canceled` | Subscription ended |
| `payment_failed` | Invoice payment failed |
| `recovered` | Moved from past_due to active |

---

## See Also

- [WEBHOOKS.md](WEBHOOKS.md) - Updating database from webhooks
- [CLI-AUTH.md](CLI-AUTH.md) - API key management
- [DUNNING.md](DUNNING.md) - Status tracking for recovery
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Copy-paste patterns

