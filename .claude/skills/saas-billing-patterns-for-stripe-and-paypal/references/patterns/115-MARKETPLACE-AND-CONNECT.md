# Bundle B115 — Marketplace & Stripe Connect

> **Where this comes from.** § 78a.1 (Stripe Connect account verification) + § 78a.8 (cross-provider webhook confusion) + cross-reference with the broader Stripe Connect docs. Plus the operational reality that marketplaces have unique attack surfaces.

For products that act as a marketplace (sellers + buyers) or process payments on behalf of other businesses (sub-merchants). Stripe Connect is the standard primitive; PayPal has a similar Marketplace product but with very different mechanics.

Skip if not a marketplace. Critical if you are.

---

## Pattern 1 — The three Connect account types

| Type | Onboarding | Liability | Stripe Dashboard access | When |
|------|------------|-----------|--------------------------|------|
| **Standard** | Stripe handles fully (Sellers create their own Stripe account; you connect via OAuth) | Stripe (mostly) | Yes | When sellers want to control their own Stripe account |
| **Express** | Hybrid: you collect basic info; Stripe handles ID verification + bank link | Shared | Limited | Most marketplaces (default) |
| **Custom** | You collect ALL info; you handle KYC; Stripe is invisible | You | None | Only for advanced platforms with compliance teams |

For most projects, Express is the right answer.

---

## Pattern 2 — Schema additions for Connect

```sql
-- Connected accounts (sellers / sub-merchants)
CREATE TABLE connected_accounts (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES users(id),
  stripe_account_id     text NOT NULL UNIQUE,        -- 'acct_xxx'
  account_type          text NOT NULL,               -- 'standard' | 'express' | 'custom'
  charges_enabled       boolean NOT NULL DEFAULT false,
  payouts_enabled       boolean NOT NULL DEFAULT false,
  details_submitted     boolean NOT NULL DEFAULT false,
  requirements_due      jsonb,                       -- Stripe's requirements.currently_due
  capabilities_active   jsonb,                       -- which capabilities are active
  default_currency      text,
  country               text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX connected_accounts_user_idx ON connected_accounts (user_id);

-- Marketplace transactions (buyer pays platform → platform pays seller minus fee)
CREATE TABLE marketplace_transactions (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_user_id         uuid NOT NULL REFERENCES users(id),
  seller_account_id     uuid NOT NULL REFERENCES connected_accounts(id),
  stripe_payment_intent_id text NOT NULL UNIQUE,
  stripe_transfer_id    text,                        -- to seller's account
  stripe_application_fee_id text,                    -- platform's cut
  gross_amount          numeric(20, 4) NOT NULL,
  application_fee_amount numeric(20, 4) NOT NULL,    -- platform's revenue
  seller_amount         numeric(20, 4) NOT NULL,     -- net to seller
  stripe_fee_amount     numeric(20, 4),               -- Stripe's processing fee (varies by Connect model)
  currency              text NOT NULL,
  status                text NOT NULL,               -- 'created' | 'succeeded' | 'refunded' | 'disputed'
  created_at            timestamptz NOT NULL DEFAULT now()
);
```

---

## Pattern 3 — Onboarding a Connect account

Express flow:

```ts
// /api/connect/onboard
async function POST(request: Request) {
  const userId = await requireUserId(request);

  // Create the Stripe account
  const account = await stripe.accounts.create({
    type: 'express',
    country: 'US',  // get from user
    email: user.email,
    capabilities: {
      card_payments: { requested: true },
      transfers: { requested: true },
    },
    metadata: { userId },
  });

  // Persist locally
  await db.insert(connectedAccounts).values({
    userId,
    stripeAccountId: account.id,
    accountType: 'express',
    chargesEnabled: account.charges_enabled,
    payoutsEnabled: account.payouts_enabled,
    detailsSubmitted: account.details_submitted,
  });

  // Generate onboarding link
  const accountLink = await stripe.accountLinks.create({
    account: account.id,
    refresh_url: `${env.APP_URL}/connect/refresh`,
    return_url: `${env.APP_URL}/connect/return`,
    type: 'account_onboarding',
  });

  return NextResponse.json({ url: accountLink.url });
}
```

The user is redirected to Stripe's onboarding flow; returns to your app; your `account.updated` webhook eventually fires when they're approved.

---

## Pattern 4 — Webhook account-mismatch check (per § 78a.1)

For Connect endpoints, every event has `event.account` indicating the connected account. The platform receives events for ALL connected accounts.

```ts
// /api/stripe/connect-webhook/route.ts
async function POST(request: Request) {
  // ... signature verification (uses CONNECT webhook secret, different from platform webhook secret)

  const event = stripe.webhooks.constructEvent(body, signature, env.STRIPE_CONNECT_WEBHOOK_SECRET);

  // Validate event.account is one of OUR connected accounts
  const connectedAccount = await db.query.connectedAccounts.findFirst({
    where: eq(connectedAccounts.stripeAccountId, event.account!),
  });

  if (!connectedAccount) {
    // We don't recognize this account — possible misconfiguration or attack
    await trackAbuseSignal({
      signal: 'webhook_event_rejected',
      source: 'system',
      route: '/api/stripe/connect-webhook',
      metadata: { reason: 'unknown_connected_account', received_account: event.account },
    });
    logSecurityEvent({
      type: 'webhook_event_rejected',
      severity: 'critical',
      target: { type: 'stripe_event', id: event.id, secondaryId: event.account },
      details: { reason: 'unknown_connected_account' },
    });
    return NextResponse.json({ received: true, outcome: 'rejected_unknown_account' });
  }

  // ... record + dispatch per B40 5-step contract
}
```

---

## Pattern 5 — Charging on behalf of a connected account (Direct Charges)

```ts
// Buyer pays $100; $90 goes to seller; $10 application fee for the platform
const paymentIntent = await stripe.paymentIntents.create({
  amount: 10000,  // $100 in cents
  currency: 'usd',
  payment_method_types: ['card'],
  application_fee_amount: 1000,  // $10 platform fee
  transfer_data: {
    destination: connectedAccount.stripeAccountId,
  },
}, {
  stripeAccount: undefined,  // direct charge: payment lives on PLATFORM account
});
```

Or use Destination Charges (alternative shape):

```ts
const charge = await stripe.charges.create({
  amount: 10000,
  currency: 'usd',
  source: paymentMethodId,
  application_fee_amount: 1000,
  transfer_data: {
    destination: connectedAccount.stripeAccountId,
  },
});
```

Differences:
- **Direct Charges**: payment + fees on platform account; transfer to seller. Customer's statement says PLATFORM.
- **Destination Charges**: payment on platform; transfer to connected account. Same statement effect; different settlement model.
- **Charges on connected account** (`stripeAccount: 'acct_xxx'`): payment lives on connected account's books. Customer's statement says SELLER.

Each has tax / settlement / dispute implications. Pick one and document.

---

## Pattern 6 — Refunds on Connect transactions

Refunding a Connect transaction:

```ts
// Refund the payment AND reverse the application fee + transfer
await stripe.refunds.create({
  payment_intent: paymentIntentId,
  reverse_transfer: true,  // reverse the transfer back to platform
  refund_application_fee: true,  // refund the platform's fee back to buyer
});
```

If the seller's account doesn't have funds to cover the reversal:
- Stripe debits the platform account (you cover it).
- OR the refund fails (depending on settings).

Document the refund liability model with sellers in their TOS.

---

## Pattern 7 — Disputes on Connect

Disputes by default land on whichever account holds the charge:

- **Direct Charges**: dispute on platform account; platform pays.
- **Destination Charges**: dispute on platform; platform pays unless `on_behalf_of` set.
- **Charges on connected account**: dispute on connected account; seller pays.

Per B55 § 78a.9 chargeback process: lock the user (buyer) in your DB; for Connect, ALSO consider locking the seller if their dispute rate is high.

```sql
ALTER TABLE connected_accounts
  ADD COLUMN dispute_count int NOT NULL DEFAULT 0,
  ADD COLUMN seller_banned_at timestamptz;
```

Sellers above a dispute-rate threshold get banned (no further marketplace transactions).

---

## Pattern 8 — Payout schedule and timing

Connected accounts have payout schedules:

```ts
// Update an Express account's payout schedule
await stripe.accounts.update(connectedAccount.stripeAccountId, {
  settings: {
    payouts: {
      schedule: { interval: 'weekly', weekly_anchor: 'friday' },
    },
  },
});
```

Standard schedules: `daily | weekly | monthly | manual`.

For marketplace projects: payouts often manual (`schedule.interval = 'manual'`) so platform can hold funds for dispute periods.

---

## Pattern 9 — Fees: Connect's complexity

Stripe charges the platform AND the connected account differently per Connect model. Calculate the EFFECTIVE fee per transaction:

```ts
function calculateMarketplaceFee(transaction: MarketplaceTx) {
  // Stripe charges (platform) percentage + fixed
  const stripeProcessingFee = transaction.grossAmount * 0.029 + 0.30;
  // Stripe Connect fee for using Connect (platform pays)
  const connectFee = transaction.grossAmount * 0.0025;  // 0.25% if using Express; 0% Standard
  const totalStripeFee = stripeProcessingFee + connectFee;

  // Platform's gross revenue (application fee)
  const platformRevenue = transaction.applicationFeeAmount;
  // Platform's net revenue (after Stripe takes its cut from the application fee)
  const platformNet = platformRevenue - totalStripeFee;
  // Seller's payout
  const sellerPayout = transaction.grossAmount - transaction.applicationFeeAmount;

  return { stripeProcessingFee, connectFee, totalStripeFee, platformRevenue, platformNet, sellerPayout };
}
```

Verify against Stripe Balance Transactions for ground truth. The DEFAULTS in the source guide for fees (§ 59) DON'T account for Connect overhead.

---

## Pattern 10 — Tax on Connect

For US: Connect transactions need 1099-K (annual tax report) for sellers exceeding thresholds. Stripe Connect provides:

- 1099-K generation for sellers (Express).
- Tax form delivery.
- Backup withholding if seller hasn't provided W-9.

Configure in Stripe Dashboard → Connect → 1099 settings.

For VAT (EU sellers): Connect doesn't auto-handle. Either use Stripe Tax (extra cost) or merchant-of-record platform.

---

## Pattern 11 — Connected account capability monitoring

Capabilities can become "unavailable" if Stripe's KYC fails:

```ts
// /api/cron/check-connect-capabilities (daily)
async function checkConnectCapabilities() {
  const accounts = await db.query.connectedAccounts.findMany();
  for (const account of accounts) {
    const fresh = await stripe.accounts.retrieve(account.stripeAccountId);

    if (!fresh.charges_enabled || !fresh.payouts_enabled) {
      // Account in trouble; notify seller
      await createEmailJob({
        type: 'connect_capability_warning',
        recipient: seller.email,
        payload: {
          requirements: fresh.requirements?.currently_due,
          deadline: fresh.requirements?.current_deadline,
        },
        priority: 30,
      });
    }

    // Update local cache
    await db.update(connectedAccounts).set({
      chargesEnabled: fresh.charges_enabled,
      payoutsEnabled: fresh.payouts_enabled,
      requirementsDue: fresh.requirements?.currently_due ?? [],
      capabilitiesActive: fresh.capabilities,
      updatedAt: new Date(),
    }).where(eq(connectedAccounts.id, account.id));
  }
}
```

---

## Pattern 12 — PayPal Marketplace equivalent

PayPal has Marketplace + Platforms (formerly known as PayPal for Marketplaces):

- Sub-merchants register via PayPal's flow.
- Charges go to platform; partial split to sub-merchant.
- Different webhook events than direct PayPal Subscriptions.

This is significantly less mature than Stripe Connect; most marketplaces start with Stripe Connect and only add PayPal later (or skip).

---

## Pattern 13 — Connect-specific failure modes

| Failure | Class | Pattern |
|---------|-------|---------|
| Connected account's bank rejects payout | High; locks platform liquidity | Auto-retry; fall back to manual payout |
| Account's KYC expires (annual) | Medium; charges_enabled flips false | Capability monitor cron + email warning |
| Disputed transaction; insufficient seller funds | High; platform debits | Reserve funds; require seller deposit |
| Seller chargeback rate spikes | High; potential fraud | Dispute-rate monitor + auto-ban above threshold |
| Cross-provider event confusion (Connect events to platform endpoint) | Medium; per § 78a.8 | Provider-specific webhook routes; never share |
| `event.account` missing on a Connect event | Critical; possible attack | Reject with `webhook_event_rejected` |
| Refund larger than seller's balance | Medium; depends on Stripe model | Pre-check seller balance OR accept platform liability |

---

## Polish Bar checks for B115

- [ ] `connected_accounts` schema with capability state tracking.
- [ ] `marketplace_transactions` schema with fee/seller/platform breakdown.
- [ ] Connect onboarding flow uses Express by default.
- [ ] Connect webhook endpoint separate from platform webhook.
- [ ] Account-mismatch check on every Connect webhook (per § 78a.1).
- [ ] Fee model documented (Direct / Destination / On Connected Account).
- [ ] Refund flow handles `reverse_transfer` + `refund_application_fee`.
- [ ] Dispute liability model documented.
- [ ] Payout schedule explicit per seller.
- [ ] Effective fee calculation includes Connect overhead.
- [ ] Tax form (1099-K) generation enabled.
- [ ] Capability monitoring cron + seller notifications.
- [ ] Seller dispute-rate ban policy.

---

## Common B115 mistakes

- **Using platform webhook endpoint for Connect events.** Confusion; potential cross-account attacks.
- **Missing account-mismatch check.** Attacker fires events from their Connect account → platform processes → entitlement granted.
- **Fee calculation ignores Connect overhead.** Margin smaller than expected.
- **Refund doesn't reverse transfer.** Seller keeps the money; buyer refunded by platform.
- **Payout schedule too aggressive.** No reserve for disputes; platform debits.
- **No capability monitoring.** Sellers' accounts disable; no notification; transactions fail silently.
- **No 1099-K for US sellers.** Tax compliance violation.
- **Chargebacks land on platform without being attributed to seller.** Platform absorbs costs.
- **Cross-provider event confusion.** Stripe Connect event payload sent to PayPal endpoint.
- **Onboarding flow doesn't store `accountId` until after KYC.** Race: `account.updated` arrives before onboard returns; lookup fails.
