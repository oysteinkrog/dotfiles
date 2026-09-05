# Business Model Portability

> **Source:** § 37b of the source guide. The patterns in this skill are calibrated to a "no trial / no discount / monthly USD / fixed tiers" digital-subscription model. Most SaaS businesses legitimately need broader policies. This file maps the patterns onto the broader space.

The reusable principle is NOT "never have deals." It's **"every deal is modeled, observable, reversible, and explainable."**

---

## The portability matrix

| Source-guide policy | Not universal because... | If your SaaS wants the broader pattern |
|---------------------|--------------------------|--------------------------------------|
| No trials | Many PLG and sales-led products need try-before-buy, onboarding windows, paid pilots | Add explicit trial state, trial start/end timestamps, trial conversion events, no-card / card-up-front policy, trial-ending notifications |
| No discounts / coupons | Acquisition, retention, education, nonprofit, partner, win-back programs | Store discount/deal provenance, validate provider discount IDs, report gross/discount/net/tax/fee/MRR separately |
| No annual plans | B2B SaaS commonly sells annual or multi-year for cash flow + procurement | Add annual prices/plans, renewal reminders, term-based cancellation/refund rules, ARR/MRR normalization, deferred-revenue-aware reporting |
| Monthly USD only | International SaaS may need local presentment, settlement, VAT/GST, multi-currency coupons | Make currency, presentment currency, tax behavior, FX fees, support copy, refund currency explicit in the ledger |
| Fixed PayPal tiers | Some teams need quantity, volume, tiered, or usage-based billing | Treat PayPal `quantity_supported`, pricing model, revise semantics, buyer re-consent as a design change |
| No self-service plan changes in portal | Many products need upgrades / downgrades / quantity changes / coupon entry in self-service | Wire portal settings to the same policy matrix as in-app checkout; test prorations, coupon application, entitlement transitions |
| No recurring Payment Links | Marketing / sales teams may want hosted campaign links | Allow them only as another checkout surface with the same metadata, URL, tax, discount, trial, reconciliation contract |

---

## If you offer trials

Model trials as a distinct STATE, not as "paid, but amount happened to be zero."

### Schema additions

```sql
ALTER TABLE subscriptions
  ADD COLUMN trial_started_at         timestamptz,
  ADD COLUMN trial_ends_at            timestamptz,
  ADD COLUMN trial_source             text,           -- 'organic' | 'partner' | 'sales' | etc.
  ADD COLUMN trial_requires_payment_method  boolean NOT NULL DEFAULT false,
  ADD COLUMN trial_end_behavior       text,           -- 'auto_paid' | 'auto_pause' | 'auto_cancel' | 'require_action'
  ADD COLUMN converted_at             timestamptz,
  ADD COLUMN conversion_invoice_id    text,
  ADD COLUMN conversion_event_id      text;           -- payment_events.event_id

CREATE TYPE subscription_status_with_trial AS ENUM (
  'none', 'trialing', 'active', 'past_due', 'cancelled', 'paused_for_org'
);
```

### Code additions

```ts
// In pickBestSubscription priority:
const tier = (s) => {
  if (s.status === 'trialing') return 4;  // higher than past_due (because trials should always grant access)
  if (s.status === 'active') return 5;
  // ...
};

// In dunning gate:
if (sub.status === 'trialing') return; // dunning does NOT start until paid invoice is due

// In churn calc:
const churnReason = (s) => {
  if (s.status === 'cancelled' && s.converted_at === null) return 'trial_expired';
  if (s.status === 'cancelled' && s.converted_at) return 'paid_cancelled';
  // ...
};
```

### Stripe integration

For Stripe Checkout free trials:
```ts
{
  mode: 'subscription',
  line_items: [{ price: planPriceId, quantity: 1 }],
  subscription_data: {
    trial_period_days: BUSINESS.TRIAL_DAYS,
    // OR trial_end: <timestamp> for absolute end
  },
  // For no-card trials:
  payment_method_collection: 'if_required',
  // Required when payment_method_collection is if_required:
  subscription_data: {
    trial_period_days: BUSINESS.TRIAL_DAYS,
    trial_settings: {
      end_behavior: { missing_payment_method: 'cancel' }, // or 'pause'
    },
  },
}
```

Webhook events to handle (add to HANDLED_STRIPE_EVENTS):
- `customer.subscription.trial_will_end` (3 days before trial ends; immediately for shorter trials)
- `customer.subscription.updated` (trial → paid transition)
- `customer.subscription.paused` (no-card trial expired in pause mode)
- `invoice.created` (first paid invoice after trial)

Stripe's newer Trial Offers (preview API + flexible billing mode) are separate from the legacy Checkout `trial_period_days`. As of source guide check: not usable with Checkout. If your SaaS uses direct Subscription APIs or Subscription Schedules, decide whether Trial Offers are mature for your reliability bar.

### PayPal integration

PayPal trials live in the plan's `billing_cycles` array as one or two `TRIAL` cycles before the single `REGULAR` cycle. They can be free or discounted.

This means PayPal trials are usually a PLAN-DESIGN decision, not a per-checkout flag like Stripe. Create separate plans for materially different trial cohorts:

```
BUSINESS.PAYPAL_PLANS = {
  pro_monthly: 'P-XXXX',
  pro_monthly_with_14d_trial: 'P-YYYY',
  pro_monthly_with_30d_trial: 'P-ZZZZ',
};
```

Keep plan IDs in an allowlist; audit `tenure_type`, `sequence`, `total_cycles`, `frequency`, `pricing_scheme` for every active plan. A support-created PayPal plan with an extra trial cycle is just as real as a code change — pin it in the provider-catalog audit.

### Trial-specific reporting

- `trial_count` — currently in trial.
- `trial_conversion_rate` — % of trials that converted in the last 30 days.
- `trial_expired_unconverted` — count of recent trial-expirations without conversion.
- `time_to_conversion` — median days from trial start to conversion (subdivides by trial_source).
- `trial_to_dunning` — trials that converted then immediately failed payment (signals fraud / fake-trial abuse).

---

## If you offer discounts, coupons, or negotiated deals

Do not make "amount paid was lower" the source of truth. Store an EXPLICIT deal record.

### Schema additions

```sql
CREATE TABLE deals (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Provider IDs
  stripe_coupon_id        text,
  stripe_promotion_code_id text,
  paypal_plan_id          text,           -- if discount is encoded as a separate PayPal plan
  -- Local fields
  deal_id                 text NOT NULL UNIQUE,    -- our slug
  source_channel          text NOT NULL,           -- 'organic' | 'partner' | 'sales' | 'referral' | 'win_back' | etc.
  approver                text,                    -- name or 'system'
  customer_scope          text,                    -- 'specific_user' | 'specific_org' | 'open' | 'partner_email_pattern'
  scope_data              jsonb,
  eligible_products       text[],
  percent_off             numeric,
  amount_off              numeric,
  amount_off_currency     text,
  duration                text NOT NULL,           -- 'once' | 'forever' | 'repeating'
  duration_in_months      int,
  redemption_limit        int,
  redeemed_count          int NOT NULL DEFAULT 0,
  starts_at               timestamptz NOT NULL DEFAULT now(),
  ends_at                 timestamptz,
  stacks_with_others      boolean NOT NULL DEFAULT false,
  applies_to              text[] NOT NULL DEFAULT array['first_invoice'],  -- 'first_invoice' | 'all_renewals' | 'upgrades_only' | 'add_ons'
  created_at              timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE deal_redemptions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_id         uuid NOT NULL REFERENCES deals(id),
  user_id         uuid NOT NULL REFERENCES users(id),
  org_id          uuid REFERENCES organizations(id),
  invoice_id      text,                            -- provider invoice
  realized_discount  numeric,                      -- actual discount amount applied
  redeemed_at     timestamptz NOT NULL DEFAULT now()
);
```

### Reporting additions

Billing analytics must preserve:
- `list_price` — sticker price.
- `gross_invoice_amount` — list × quantity × periods.
- `discount_amount` — sum of redemptions for this invoice.
- `net_collected` — what hit the bank account before fees.
- `tax` — collected.
- `provider_fee` — Stripe / PayPal fee.
- `refunds` — issued.
- `disputes` — chargebacks.
- `settlement_net` — final number from provider settlement.

Don't conflate these. "Net revenue" requires all six.

### Stripe integration

Stripe coupons + promotion codes:
- Coupon: `stripe.coupons.create({ percent_off: 20, duration: 'once' })`
- Promo code: `stripe.promotionCodes.create({ coupon: <coupon_id>, code: 'WELCOME20', max_redemptions: 100, expires_at: ... })`

In Checkout:
- `discounts: [{ coupon: <coupon_id> }]` (apply coupon directly)
- OR `allow_promotion_codes: true` (let customer enter code)

Stripe limits: a Checkout Session supports up to ONE coupon or promotion code at a time. Validate this in your provider audit.

For subscriptions: a `duration: 'once'` coupon can disappear from the `subscription.discounts` array after the invoice finalizes. **Realized discount reporting must inspect invoices and line items**, not only the current Subscription object.

### PayPal integration

There is no Stripe-equivalent "coupon code at Checkout" control plane for PayPal Subscriptions. Common patterns:
- Separate discounted plans (`pro_monthly_partner_20pct = 'P-DISC1'`).
- Free / discounted `TRIAL` cycles (a "discount" disguised as a trial).
- Plan-level pricing changes (note: affects future cycles AND notifies existing subscribers — these are CONTRACT changes).
- App-side sales/deal approval flow that chooses a pre-approved plan ID.

For one-off negotiated terms: prefer a NEW explicit plan/contract path with a clear migration story over silently patching local entitlement or MRR.

### Abuse controls (mandatory)

- Rate-limit promotion-code attempts.
- Normalize email and domain identities (block referral-loop abuse).
- Decide whether codes are per-user, per-org, per-domain, per-payment-method.
- Block self-referral loops.
- Log support overrides.
- Alert on coupon stacking, expired-code acceptance, coupon use after cancellation, discounts applied to wrong product.
- Refund and dunning code uses the discounted invoice amount for collection / refund math.
- Entitlement still based on the approved plan, not "paid less means lower tier" unless the pricing model says so.

---

## If you sell annual plans or sales-assisted contracts

Annual / multi-year contracts change MORE than the displayed price.

### Schema additions

```sql
ALTER TABLE subscriptions
  ADD COLUMN billing_interval         text,            -- 'monthly' | 'quarterly' | 'annual' | 'biennial'
  ADD COLUMN contract_started_at      timestamptz,
  ADD COLUMN contract_ends_at         timestamptz,
  ADD COLUMN renewal_notice_at        timestamptz,    -- notify N days before
  ADD COLUMN auto_renewal_policy      text,           -- 'auto_renew' | 'manual_renew_required'
  ADD COLUMN cancellation_deadline    timestamptz,    -- per contract
  ADD COLUMN refundability            text,           -- 'pro_rata' | 'no_refund_after_N_days' | 'full_year_no_refund'
  ADD COLUMN invoice_collection_method text,          -- 'auto_charge' | 'send_invoice_NET_30'
  ADD COLUMN procurement_contact_email text,
  ADD COLUMN purchase_order_number    text,
  ADD COLUMN renewal_owner            text;            -- account-manager name
```

### Reporting additions

- **MRR** vs. **ARR**: normalize annual subs to MRR-equivalent (annual_amount / 12) BUT also report ARR as a separate column.
- **Cash collected** vs. **recognized revenue** vs. **booked ARR** vs. **entitlement period**: four different facts.
- **Deferred revenue**: an annual prepayment generates 12 months of deferred revenue that recognizes monthly (accounting requirement).

If your SaaS does not yet have GAAP-aware reporting, building it before annual plans launch is much cheaper than fixing reports retroactively.

### Stripe integration

Stripe annual prices: `recurring: { interval: 'year' }`.

Subscription Schedules can encode phased deals:
- "50% off for three months, then full price"
- Future upgrades / downgrades
- Backdated starts
- Contract ramps

Use Subscription Schedules instead of one-off local overrides — schedules are the source of truth that Stripe enforces.

### PayPal integration

PayPal supports `FIXED`, `QUANTITY`, `VOLUME`, `TIERED` subscription pricing models, plus plan-price updates. But:
- Plan-price updates affect future billing cycles.
- They have customer-notice semantics (PayPal notifies subscribers).
- Treat them as contract changes, not silent price updates.

### Cancellation rules

- **Mid-term upgrades**: invoice immediately + prorate? Start next cycle? Require buyer approval?
- **Mid-term downgrades**: refund pro-rata? Apply at next cycle? Block until renewal?
- **Cancellation before contract end**: pro-rata refund? Full forfeiture? Negotiated escape clause?

Write down the policy. Test it with Stripe Test Clocks (which advance time) and PayPal sandbox subs.

---

## If you sell internationally

Multi-currency / multi-tax / multi-language SaaS adds complexity throughout.

### Currency

| Surface | Field | Note |
|---------|-------|------|
| Stripe Checkout | `currency: 'usd'` | Integration currency |
| Stripe Adaptive Pricing | `presentment_currency` | What customer sees |
| Stripe webhook | `event.data.object.currency` | Always integration currency |
| Stripe webhook | `event.data.object.presentment_details` | If Adaptive Pricing |
| PayPal | per-plan `value.currency_code` | Plan currency |

If Adaptive Pricing is enabled: customer may see "€18,99" while the API sees `amount_total=2000` USD. Don't conclude amount_total = "$20.00 USD" without checking presentment.

### Tax

Stripe Tax integration:
- `automatic_tax: { enabled: true }` on Checkout / subscription.
- Stripe calculates tax based on customer address / billing.
- Webhook events include `tax` lines on invoices.
- BUT entitlement code must NOT infer "paid" from tax-inclusive totals — store tax separately.

Merchant-of-record platforms (Paddle, Lemon Squeezy):
- They handle tax for you.
- They become the legal seller; your billing system mirrors their state.
- Don't try to ALSO compute tax — single source of truth.

### Refund currency

- Stripe: refund must match charge currency.
- If customer paid in EUR (presentment) but charge currency was USD (integration), refund is in USD; the customer's EUR-to-USD FX may have moved.
- Document refund-FX policy in your TOS (typically "refund of the original USD amount; FX gain/loss on customer").

---

## Audit changes when broader policies are enabled

Once a SaaS supports trials / deals / annual / multi-currency, the audit target changes from "zero discounts and zero trials" to **"only approved discounts and trials."**

The audit artifact must include:

1. **Product policy matrix.** Which trial / deal / plan / interval / currency patterns are allowed, for which products, cohorts, and environments.
2. **Provider catalog.** Stripe coupons, promotion codes, prices, schedules, portal settings, Payment Links, Checkout flags. PayPal plan billing cycles, pricing schemes, quantity settings, payment preferences, taxes.
3. **Recent-history sample.** Checkout sessions, subscriptions, invoices, refunds, balance transactions, PayPal webhook events, PayPal transaction rows grouped by provider object ID + policy category.
4. **Local ledger.** gross/list price, provider discount, local deal record, net revenue, tax, fee, refund, dispute, entitlement period.
5. **Exception list.** Support overrides, grandfathered customers, sales contracts, partner deals, migration cohorts with expiry dates and owners.

The same architecture still applies: **app constants are useful, provider objects are authoritative, webhooks are event sources, reconciliation is the backstop.**

---

## What stays the same

Regardless of business model:

- The 5-step webhook contract.
- 200-on-error.
- `last_event_at` ordering.
- `recordWebhookEvent` dedup.
- Cross-provider duplicate-sub guard.
- Hijack defenses.
- Cron defenses.
- Synchronous cache invalidation on refund.
- Analytics exclusions.
- Provenance envelopes.
- Three-write-path / three-alarm-path architecture.
- The Polish Bar (every dimension still applies).

What changes is the **content** of constants (`BUSINESS`), the **schema** (extra columns for trials / contracts / multi-currency), the **handler set** (more events to handle), and the **reporting** (more dimensions to slice by).

---

## Pattern bundles affected

| Bundle | What changes when broader policies enabled |
|--------|---------------------------------------------|
| B10 — Schema | More columns: trial_*, contract_*, deals + deal_redemptions tables, currency / presentment_currency |
| B20 — Constants | BUSINESS.TRIAL_DAYS > 0; BUSINESS.ALLOW_PROMO_CODES = true; BUSINESS.PAYPAL_PLANS includes trial / discount variants; multi-currency price IDs |
| B30 — Checkout | trial_period_days passed; allow_promotion_codes: true; presentment currency support; per-region price ID picker |
| B40 — Webhooks | More events handled (trial_will_end, deferred_payment, etc.); contract-renewal events |
| B60 — State | New `trialing` status; trial-end-behavior handling; contract-end handling |
| B70 — Dunning | Trial → paid conversion path; contract renewal reminders; coupon-aware dunning |
| B80 — Teams | Per-tier trials; per-tier annual plans |
| B100 — Analytics | trial_conversion_rate; ARR vs MRR; deferred revenue; per-currency MRR |
| B110 — Operations | Discount catalog audit; trial catalog audit; multi-currency tax audit |

For each bundle: revisit Phase 4 task list when adding a new policy. The pattern still applies; the parameters change.
