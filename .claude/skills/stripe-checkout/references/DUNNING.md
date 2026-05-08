# Dunning Strategy

Handling failed payments and maximizing subscription recovery.

---

## Table of Contents

- [Payment Failure Timeline](#payment-failure-timeline)
- [Stripe Configuration](#stripe-configuration)
- [PayPal Configuration](#paypal-configuration)
- [Email Notifications](#email-notifications)
- [Grace Period Strategy](#grace-period-strategy)
- [In-App Notifications](#in-app-notifications)
- [Monitoring and Alerts](#monitoring-and-alerts)
- [Recovery Tactics](#recovery-tactics)
- [Admin Dashboard](#admin-dashboard)
- [Future Considerations](#future-considerations)

---

## Payment Failure Timeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                     PAYMENT FAILURE TIMELINE                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Day 0: Payment fails                                              │
│          └── Stripe/PayPal: Auto-retry scheduled                   │
│          └── You: Status → past_due, send email                    │
│                                                                     │
│   Day 3: First retry                                                │
│          └── If success → Status → active                          │
│          └── If fail → Continue retries                            │
│                                                                     │
│   Day 7: Second retry                                               │
│          └── Same as above                                          │
│                                                                     │
│   Day 14: Third retry                                               │
│          └── Same as above                                          │
│                                                                     │
│   Day 21: Final retry (configurable)                                │
│          └── If fail → Subscription canceled                        │
│          └── Status → canceled, access revoked                     │
│                                                                     │
│   ═══════════════════════════════════════════════════════════════   │
│                                                                     │
│   GRACE PERIOD: User retains access during retry period             │
│   (Day 0 - Day 21 in this example)                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Quick Reference

| Status | Access | Action |
|--------|--------|--------|
| active | Full | None |
| past_due | Full (grace) | Show warning, wait for retries |
| canceled | Revoked | Send win-back email |
| suspended (PayPal) | Revoked | Prompt to update PayPal |

---

## Stripe Configuration

### Smart Retries

Stripe's Smart Retries use ML to optimize retry timing. Enable in Dashboard:

1. Go to **Billing → Subscriptions → Settings**
2. Enable **Smart Retries**
3. Configure retry schedule (or use Stripe's default)

### Recommended Settings

```
Retry schedule: Smart Retries (recommended)
  - Or custom: Day 3, Day 7, Day 14, Day 21

After all retries fail:
  ✓ Cancel the subscription (recommended)

Failed payment emails:
  ✓ Send emails for failed payments
  ✓ Send emails before subscription cancellation

Card update reminder:
  ✓ Send reminder before card expires
```

### Stripe Billing Portal

Users can update their payment method via the Customer Portal:

```typescript
// Let users fix their payment method
const portalSession = await stripe.billingPortal.sessions.create({
  customer: stripeCustomerId,
  return_url: `${APP_URL}/settings/billing`
});
// Redirect to portalSession.url
```

---

## PayPal Configuration

### Plan Settings

When creating the PayPal plan, set failure handling:

```typescript
const plan = await fetch(`${PAYPAL_API_URL}/v1/billing/plans`, {
  method: 'POST',
  headers: { /* ... */ },
  body: JSON.stringify({
    // ... plan details ...
    payment_preferences: {
      auto_bill_outstanding: true,  // Retry failed amounts
      payment_failure_threshold: 3   // Suspend after 3 failures
    }
  })
});
```

### PayPal Behavior

| Event | PayPal Action |
|-------|---------------|
| Payment fails | Retries on each billing cycle (monthly) |
| 3 consecutive failures | Subscription → SUSPENDED |
| User updates payment | You call activate API to resume |

### Reactivating Suspended PayPal Subscription

```typescript
// After user updates payment in PayPal
await fetch(
  `${PAYPAL_API_URL}/v1/billing/subscriptions/${subscriptionId}/activate`,
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      reason: "User updated payment method"
    })
  }
);
```

### Provider Comparison

| Provider | Auto-Retry | Config Location | Recovery Action |
|----------|------------|-----------------|-----------------|
| Stripe | Smart Retries | Billing Settings | Customer Portal |
| PayPal | Per billing cycle | Plan creation | PayPal account + API reactivate |

---

## Email Notifications

### Stripe Automatic Emails

Stripe can send these automatically (enable in Dashboard):

| Email | Trigger |
|-------|---------|
| Payment failed | Immediately after failure |
| Payment retry reminder | Before each retry |
| Subscription canceled | After final failure |

### Custom Emails (Optional)

For more control or PayPal notifications:

```typescript
// In webhook handler
async function handlePaymentFailed(subscription: any, provider: string) {
  const user = await getUserBySubscription(subscription.id);

  await sendEmail({
    to: user.email,
    template: 'payment-failed',
    data: {
      name: user.name,
      provider,
      updateUrl: provider === 'stripe'
        ? await getStripePortalUrl(subscription.customer)
        : 'https://www.paypal.com/myaccount/autopay'
    }
  });
}

async function handleSubscriptionCanceled(subscription: any) {
  const user = await getUserBySubscription(subscription.id);

  await sendEmail({
    to: user.email,
    template: 'subscription-canceled',
    data: {
      name: user.name,
      resubscribeUrl: `${APP_URL}/pricing`
    }
  });
}
```

### Email Templates

**Payment Failed:**
```
Subject: Action required: Update your payment method

Hi {{name}},

We couldn't process your payment for your subscription.

Please update your payment method to avoid interruption:
{{updateUrl}}

If you have questions, reply to this email.

Thanks,
The Team
```

**Subscription Canceled:**
```
Subject: Your subscription has been canceled

Hi {{name}},

After multiple payment attempts, we've had to cancel your subscription.

If you'd like to resubscribe, visit:
{{resubscribeUrl}}

We'd love to have you back!

Thanks,
The Team
```

---

## Grace Period Strategy

### Recommended Approach

```typescript
// In access control middleware
async function checkAccess(userId: string): Promise<boolean> {
  const sub = await db.subscription.findUnique({
    where: { userId }
  });

  if (!sub) return false;

  // Active: full access
  if (sub.status === 'active') return true;

  // Past due: grace period while retries happening
  if (sub.status === 'past_due') {
    // Option 1: Full grace period (Stripe is retrying)
    return true;

    // Option 2: Limited grace (e.g., 7 days)
    // const graceDays = 7;
    // const graceEnd = new Date(sub.currentPeriodEnd);
    // graceEnd.setDate(graceEnd.getDate() + graceDays);
    // return new Date() < graceEnd;
  }

  // Canceled or suspended: no access
  return false;
}
```

### Grace Period Options

| Option | Behavior | Best For |
|--------|----------|----------|
| Full grace | Access until final failure | Maximizing recovery |
| Limited grace (7 days) | Access for fixed period | Balancing access/urgency |
| No grace | Block immediately on failure | Strict enforcement |

---

## In-App Notifications

Show banner for past_due users:

```typescript
// components/BillingBanner.tsx
function BillingBanner({ subscription }) {
  if (subscription.status !== 'past_due') return null;

  return (
    <div className="bg-yellow-100 border-l-4 border-yellow-500 p-4">
      <p className="font-bold">Payment issue</p>
      <p>
        We couldn't process your last payment.
        <a href="/settings/billing" className="underline ml-1">
          Update payment method
        </a>
      </p>
    </div>
  );
}
```

---

## Monitoring and Alerts

### Key Metrics to Track

```typescript
// Daily metrics job
async function calculateDunningMetrics() {
  const now = new Date();
  const thirtyDaysAgo = new Date(now.setDate(now.getDate() - 30));

  const metrics = {
    // Current state
    activeSubscriptions: await db.subscription.count({
      where: { status: 'active' }
    }),
    pastDueSubscriptions: await db.subscription.count({
      where: { status: 'past_due' }
    }),

    // 30-day trends
    canceledDueToPayment: await db.subscriptionEvent.count({
      where: {
        eventType: 'canceled',
        reason: 'payment_failed',
        createdAt: { gte: thirtyDaysAgo }
      }
    }),
    recoveredFromPastDue: await db.subscriptionEvent.count({
      where: {
        eventType: 'recovered',
        createdAt: { gte: thirtyDaysAgo }
      }
    })
  };

  // Calculate recovery rate
  const failedAttempts = metrics.canceledDueToPayment +
                         metrics.recoveredFromPastDue;
  metrics.recoveryRate = failedAttempts > 0
    ? (metrics.recoveredFromPastDue / failedAttempts * 100).toFixed(1) + '%'
    : 'N/A';

  return metrics;
}
```

### Monitoring Checklist

- [ ] Track MRR (Monthly Recurring Revenue)
- [ ] Track churn rate (cancellations / total)
- [ ] Track recovery rate (recovered / failed payments)
- [ ] Alert on unusual spikes in failures
- [ ] Weekly review of past_due accounts

### Alert Triggers

| Alert | Threshold |
|-------|-----------|
| High past_due count | > 5% of active subscriptions |
| Low recovery rate | < 50% |
| Payment failure spike | > 2x normal rate |

---

## Recovery Tactics

### 1. Card Update Reminders

Before cards expire (Stripe can do this automatically):

```typescript
// Or custom implementation
async function sendExpiringCardReminders() {
  // Find subscriptions with cards expiring next month
  const expiringCards = await stripe.customers.list({
    limit: 100,
    // Filter by card expiration...
  });

  for (const customer of expiringCards.data) {
    await sendEmail({
      to: customer.email,
      template: 'card-expiring',
      data: {
        updateUrl: await getStripePortalUrl(customer.id)
      }
    });
  }
}
```

### 2. Multiple Payment Methods

Encourage users to add backup payment methods:

```typescript
// In billing settings
const setupIntent = await stripe.setupIntents.create({
  customer: customerId,
  payment_method_types: ['card']
});
// Use setupIntent.client_secret with Stripe Elements
```

### 3. Win-Back Campaigns

For canceled users (30 days after cancellation):

```typescript
async function sendWinBackEmails() {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const eligibleUsers = await db.subscription.findMany({
    where: {
      status: 'canceled',
      canceledAt: {
        gte: new Date(thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 1)),
        lte: thirtyDaysAgo
      }
    },
    include: { user: true }
  });

  for (const sub of eligibleUsers) {
    await sendEmail({
      to: sub.user.email,
      template: 'win-back',
      data: {
        name: sub.user.name,
        resubscribeUrl: `${APP_URL}/pricing`
        // Consider offering a discount...
      }
    });
  }
}
```

---

## Admin Dashboard

Build a simple admin view for subscription health:

```typescript
// app/admin/subscriptions/page.tsx
async function SubscriptionsDashboard() {
  const stats = await calculateDunningMetrics();

  const pastDueUsers = await db.subscription.findMany({
    where: { status: 'past_due' },
    include: { user: true },
    orderBy: { updatedAt: 'asc' }  // Oldest issues first
  });

  return (
    <div>
      <h1>Subscription Health</h1>

      {/* Key metrics */}
      <div className="grid grid-cols-4 gap-4">
        <Stat label="Active" value={stats.activeSubscriptions} />
        <Stat label="Past Due" value={stats.pastDueSubscriptions} />
        <Stat label="Recovery Rate" value={stats.recoveryRate} />
        <Stat label="Canceled (30d)" value={stats.canceledDueToPayment} />
      </div>

      {/* Users needing attention */}
      <h2>Past Due Subscriptions</h2>
      <table>
        {pastDueUsers.map(sub => (
          <tr key={sub.id}>
            <td>{sub.user.email}</td>
            <td>{sub.provider}</td>
            <td>{daysSince(sub.updatedAt)} days</td>
            <td>
              <button onClick={() => sendReminderEmail(sub.userId)}>
                Send Reminder
              </button>
            </td>
          </tr>
        ))}
      </table>
    </div>
  );
}
```

This lets you:
- Monitor overall subscription health
- Identify users stuck in past_due
- Manually intervene for high-value users

---

## Future Considerations

### Multi-Currency Pricing

```typescript
// Create prices for each currency
const prices = {
  USD: 'price_usd_xxx',
  GBP: 'price_gbp_xxx',
  CAD: 'price_cad_xxx',
  AUD: 'price_aud_xxx'
};

// Select based on user's country/preference
const priceId = prices[userCurrency] || prices.USD;
```

### Stripe Tax

For automated tax collection (especially UK VAT):

```typescript
const session = await stripe.checkout.sessions.create({
  // ...
  automatic_tax: { enabled: true }
});
```

### Alternative Providers

| Provider | Pros | Cons |
|----------|------|------|
| Paddle | Handles tax, MoR | Larger cut |
| Braintree | PayPal-owned, unified | Less features |
| Lemon Squeezy | Developer-friendly, handles tax | Newer |

Current Stripe + PayPal approach gives full control and customer ownership.

---

## See Also

- [STRIPE.md](STRIPE.md) - Stripe Dashboard settings
- [PAYPAL.md](PAYPAL.md) - PayPal plan configuration
- [WEBHOOKS.md](WEBHOOKS.md) - Handling failure events
- [DATABASE.md](DATABASE.md) - Subscription status tracking
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Copy-paste patterns

