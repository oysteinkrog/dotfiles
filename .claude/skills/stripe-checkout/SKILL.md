---
name: stripe-checkout
description: >-
  Integrate Stripe and PayPal subscriptions for SaaS apps. Use when implementing
  payment checkout, recurring billing, subscription management, or webhook handling
  for Next.js with Rust CLI companions.
---

# Stripe & PayPal Checkout for SaaS

> **Core Insight:** Database is the single source of truth. Both providers sync to one `subscriptions` table via webhooks.

## THE EXACT PROMPT

```
Implement [Stripe/PayPal/both] subscription checkout for a SaaS app:

1. Provider: [Stripe only / PayPal only / Both]
2. Price: $[amount]/[month|year]
3. Tech stack: [Next.js / etc] + [Prisma / Drizzle / raw SQL]
4. CLI companion: [Yes/No] - needs API key auth?
5. Regions: [US only / US,CA,UK,AU / Global]

Follow stripe-and-paypal-checkout-for-saas skill patterns.
```

## Decision Tree

```
What payment integration do you need?
│
├─ Cards + Apple/Google Pay only
│  └─ Use Stripe Checkout → [STRIPE.md](references/STRIPE.md)
│
├─ PayPal wallet only
│  └─ Use PayPal Subscriptions → [PAYPAL.md](references/PAYPAL.md)
│
├─ Both (recommended for max conversion)
│  │
│  ├─ Option A: Stripe handles PayPal
│  │  └─ Enable PayPal in Stripe Dashboard, single integration
│  │
│  └─ Option B: Separate integrations
│     └─ More control, unified DB as truth
│
└─ Need CLI authentication?
   └─ See [CLI-AUTH.md](references/CLI-AUTH.md)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PAYMENT FLOW                                │
├─────────────────────────────────────────────────────────────────────┤
│   User clicks "Subscribe"                                           │
│            │                                                        │
│            ├──► Stripe Checkout ──► Webhook ──► DB Update           │
│            │    (cards, Apple/Google Pay)                           │
│            │                                                        │
│            └──► PayPal Approval ──► Webhook ──► DB Update           │
│                 (wallet)                                            │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────┐       │
│   │  subscriptions table (SINGLE SOURCE OF TRUTH)          │       │
│   │  user_id | provider | status | current_period_end      │       │
│   └─────────────────────────────────────────────────────────┘       │
│                         │                                           │
│                         ▼                                           │
│   Access Control: RLS / middleware checks status = 'active'         │
│   Works for both Web App AND Rust CLI                               │
└─────────────────────────────────────────────────────────────────────┘
```

## Quick Start: Stripe Checkout

```typescript
// Create checkout session - Next.js API route
const session = await stripe.checkout.sessions.create({
  mode: 'subscription',
  payment_method_types: ['card'],
  line_items: [{ price: PRICE_ID, quantity: 1 }],
  customer_email: user.email,
  success_url: `${APP_URL}/dashboard?payment=success`,
  cancel_url: `${APP_URL}/pricing?payment=canceled`,
  metadata: { user_id: user.id }
});
// Redirect user to session.url
```

## Workflow Checklist

### Phase 1: Provider Setup
- [ ] Create Stripe Product + Price in Dashboard
- [ ] Create PayPal Product + Plan (if using)
- [ ] Configure webhook endpoints
- [ ] Store secrets in environment variables

### Phase 2: Database
- [ ] Create `subscriptions` table — [DATABASE.md](references/DATABASE.md)
- [ ] Add `is_active_subscriber` flag to user profiles
- [ ] Set up RLS policies for premium content

### Phase 3: Checkout
- [ ] Stripe Checkout flow — [STRIPE.md](references/STRIPE.md)
- [ ] PayPal subscription flow — [PAYPAL.md](references/PAYPAL.md)
- [ ] Success/cancel redirect handling

### Phase 4: Webhooks
- [ ] Stripe webhook with signature verification
- [ ] PayPal webhook with signature verification
- [ ] Idempotent event processing
- [ ] See [WEBHOOKS.md](references/WEBHOOKS.md)

### Phase 5: Access Control
- [ ] Web: RLS policies on premium tables
- [ ] CLI: Token validation + subscription check — [CLI-AUTH.md](references/CLI-AUTH.md)
- [ ] Grace period handling for failed payments

### Phase 6: Dunning
- [ ] Configure Stripe Smart Retries
- [ ] Set PayPal `payment_failure_threshold`
- [ ] Email notifications — [DUNNING.md](references/DUNNING.md)

## Critical Events

| Provider | Event | Action |
|----------|-------|--------|
| Stripe | `checkout.session.completed` | Create subscription, mark active |
| Stripe | `invoice.payment_failed` | Status → past_due, log |
| Stripe | `customer.subscription.deleted` | Mark inactive, revoke keys |
| PayPal | `BILLING.SUBSCRIPTION.ACTIVATED` | Mark active |
| PayPal | `BILLING.SUBSCRIPTION.CANCELLED` | Mark inactive |
| PayPal | `BILLING.SUBSCRIPTION.SUSPENDED` | Mark inactive (payment failures) |

## Status Mapping

```typescript
type SubscriptionStatus = 'active' | 'past_due' | 'canceled' | 'suspended';

// Stripe status → internal
const stripeMap = { active: 'active', past_due: 'past_due', canceled: 'canceled', unpaid: 'suspended' };

// PayPal status → internal
const paypalMap = { ACTIVE: 'active', SUSPENDED: 'suspended', CANCELLED: 'canceled' };
```

## Environment Variables

```bash
# Stripe
STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_PUBLISHABLE_KEY=pk_live_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
STRIPE_PRICE_ID=price_xxx

# PayPal
PAYPAL_CLIENT_ID=xxx
PAYPAL_CLIENT_SECRET=xxx
PAYPAL_API_URL=https://api-m.paypal.com  # or sandbox
PAYPAL_PLAN_ID=P-xxx
PAYPAL_WEBHOOK_ID=xxx
```

## Security Checklist

- [ ] NEVER store raw card numbers — use hosted checkout
- [ ] ALWAYS verify webhook signatures before processing
- [ ] Use HTTPS everywhere
- [ ] Short-lived JWT tokens (1hr) with DB subscription checks
- [ ] Revoke API keys when subscription expires
- [ ] Process webhooks idempotently

## References

| Topic | Reference |
|-------|-----------|
| **Quick copy-paste patterns** | [QUICK-REFERENCE.md](references/QUICK-REFERENCE.md) |
| Stripe integration | [STRIPE.md](references/STRIPE.md) |
| PayPal integration | [PAYPAL.md](references/PAYPAL.md) |
| Webhook handlers | [WEBHOOKS.md](references/WEBHOOKS.md) |
| Database schema & RLS | [DATABASE.md](references/DATABASE.md) |
| CLI authentication | [CLI-AUTH.md](references/CLI-AUTH.md) |
| Failed payment handling | [DUNNING.md](references/DUNNING.md) |
| Testing patterns | [TESTING.md](references/TESTING.md) |

## Validation

```bash
# After implementation, verify:
# 1. Test checkout flows in test mode
stripe listen --forward-to localhost:3000/api/webhooks/stripe
stripe trigger checkout.session.completed

# 2. Verify database updates correctly
# 3. Verify RLS blocks access when inactive
# 4. Test CLI behavior with expired subscription
```
