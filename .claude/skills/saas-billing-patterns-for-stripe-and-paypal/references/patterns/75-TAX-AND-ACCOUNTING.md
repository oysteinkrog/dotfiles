# Bundle B75 — Tax & Accounting

> **Where this comes from.** § 59 (settlement ledger ingestion) + § 78a.11 (tax + merchant-of-record boundaries) + B100 (analytics & reporting). Cross-reference with `/saas-customer-analytics`.

Real businesses need GAAP-aware reporting + tax compliance. The patterns here separate "money in" from "revenue recognized" from "entitlement granted" — three different facts.

Skip in T1 (greenfield can defer); essential by T3 (when finance team gets involved); non-optional by T4 (compliance audits).

---

## Pattern 1 — Three separate truths

```
┌──────────────────────────────────────────────────────────────────┐
│ ENTITLEMENT  → Does this user have access right now?              │
│   Source: subscriptions table + verify-as-write                   │
│   Time scale: real-time                                           │
│   Granularity: per-user / per-org                                 │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ CASH         → What money actually moved (gross/fee/net/refund)?  │
│   Source: settlement ledger (provider Balance Transactions)       │
│   Time scale: settlement-time (T+0 to T+3 days)                   │
│   Granularity: per-transaction                                    │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ REVENUE      → What revenue do we recognize this period?          │
│   Source: derived view from settlement ledger + GAAP rules       │
│   Time scale: monthly close                                       │
│   Granularity: per-customer + per-product per-period             │
└──────────────────────────────────────────────────────────────────┘
```

Mixing these is the most common accounting mistake. Examples:
- "MRR" includes annual subs as monthly equivalent (revenue) — NOT what was charged this month (cash).
- "ARR" is annualized future-recurring (revenue) — NOT what's in the bank.
- "Cash collected" = sum of charges this period (cash) — NOT revenue (subscription paid in advance is deferred).

---

## Pattern 2 — Settlement ledger schema

The immutable source of truth for cash. One row per provider settlement event.

```sql
CREATE TABLE settlement_ledger (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider            subscription_provider NOT NULL,
  provider_object_id  text NOT NULL,
  type                text NOT NULL,          -- 'charge' | 'refund' | 'fee' | 'dispute' | 'tax' | 'payout' | 'adjustment'
  reporting_category  text,                    -- Stripe's reporting_category
  gross_amount        numeric(20, 4) NOT NULL,
  fee_amount          numeric(20, 4) NOT NULL DEFAULT 0,
  tax_amount          numeric(20, 4) NOT NULL DEFAULT 0,
  net_amount          numeric(20, 4) NOT NULL,
  currency            text NOT NULL,
  presentment_currency text,                   -- if Adaptive Pricing
  presentment_amount  numeric(20, 4),
  customer_id         text,
  user_id             uuid,                    -- enriched
  invoice_id          text,
  subscription_id     text,
  occurred_at         timestamptz NOT NULL,    -- provider's timestamp
  available_on        timestamptz,             -- when funds become available (Stripe)
  recorded_at         timestamptz NOT NULL DEFAULT now(),
  -- Provenance
  ingested_via        text NOT NULL,           -- 'webhook' | 'cron_sweep' | 'manual'
  source_query_id     text,                    -- request_id from Stripe / debug_id from PayPal
  -- Idempotency: composite key per § 59 PayPal note
  CONSTRAINT settlement_ledger_unique
    UNIQUE (provider, provider_object_id, type, presentment_currency)
);

CREATE INDEX settlement_ledger_occurred_at_idx ON settlement_ledger (occurred_at);
CREATE INDEX settlement_ledger_user_id_idx ON settlement_ledger (user_id, occurred_at);
CREATE INDEX settlement_ledger_subscription_id_idx ON settlement_ledger (subscription_id, occurred_at);
CREATE INDEX settlement_ledger_currency_period_idx ON settlement_ledger (currency, occurred_at);
```

### Why composite UNIQUE on PayPal

Per § 59: PayPal's `transaction_id` can appear more than once in reporting (one balance-affecting row + one non-balance-affecting row). The composite key avoids false-positive duplicates while still rejecting true duplicates.

### Immutable

Settlement rows are NEVER updated. Corrections write a new row with `type = 'adjustment'` and a reference to the original. The old row stays for audit.

---

## Pattern 3 — Stripe Balance Transaction ingestion

Run as a cron sweep (every 6h):

```ts
// /api/cron/settlement-ledger-stripe-sweep
async function ingestStripeBalanceTransactions() {
  await acquireAdvisoryLock('settlement_stripe_sweep', async () => {
    let cursor = await getCursorValue('settlement_stripe_cursor');
    while (true) {
      const result = await stripe.balanceTransactions.list({
        limit: 100,
        starting_after: cursor,
        // Bound the query window to avoid double-processing
        created: { gte: Math.floor((Date.now() - 7 * 24 * 60 * 60 * 1000) / 1000) },
      });
      if (result.data.length === 0) break;

      for (const tx of result.data) {
        await db.insert(settlementLedger).values({
          provider: 'stripe',
          providerObjectId: tx.id,
          type: tx.type,                      // 'charge' | 'refund' | 'stripe_fee' | 'payout' | etc.
          reportingCategory: tx.reporting_category,
          grossAmount: tx.amount / 100,
          feeAmount: tx.fee / 100,
          netAmount: tx.net / 100,
          currency: tx.currency,
          customerId: extractStripeCustomer(tx),
          invoiceId: extractStripeInvoice(tx),
          subscriptionId: extractStripeSubscription(tx),
          occurredAt: new Date(tx.created * 1000),
          availableOn: tx.available_on ? new Date(tx.available_on * 1000) : null,
          ingestedVia: 'cron_sweep',
          sourceQueryId: tx.id,  // Stripe's id IS the request_id-equivalent
        }).onConflictDoNothing();
      }

      cursor = result.data[result.data.length - 1].id;
      if (!result.has_more) break;
    }
    await setCursorValue('settlement_stripe_cursor', cursor);
  });
}
```

---

## Pattern 4 — PayPal Transaction Search ingestion

Per § 59: 31-day window max + up to 3-hour lag + late updates.

```ts
// /api/cron/settlement-ledger-paypal-sweep
async function ingestPayPalTransactions() {
  await acquireAdvisoryLock('settlement_paypal_sweep', async () => {
    // Run overlapping windows for late updates
    const lastSweepEnd = await getCursorValue('settlement_paypal_last_sweep_end');
    const now = new Date();
    const windowStart = lastSweepEnd
      ? new Date(lastSweepEnd.getTime() - 24 * 60 * 60 * 1000)  // overlap 24h for late updates
      : new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    // PayPal's max window is 31 days
    const windowEnd = new Date(Math.min(
      now.getTime(),
      windowStart.getTime() + 31 * 24 * 60 * 60 * 1000,
    ));

    const token = await getPayPalAccessToken();
    let pageId = 1;
    while (true) {
      const params = new URLSearchParams({
        start_date: windowStart.toISOString().slice(0, 19) + 'Z',
        end_date: windowEnd.toISOString().slice(0, 19) + 'Z',
        fields: 'transaction_info',  // counts-only-ish; no PII
        page_size: '500',
        page: String(pageId),
        balance_affecting_records_only: 'Y',
      });
      const response = await fetch(`${env.PAYPAL_API_BASE}/v1/reporting/transactions?${params}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = await response.json();
      if (!data.transaction_details || data.transaction_details.length === 0) break;

      for (const txDetail of data.transaction_details) {
        const tx = txDetail.transaction_info;
        await db.insert(settlementLedger).values({
          provider: 'paypal',
          providerObjectId: tx.transaction_id,
          type: mapPayPalEventCode(tx.transaction_event_code),
          grossAmount: parseFloat(tx.transaction_amount.value),
          feeAmount: tx.fee_amount ? parseFloat(tx.fee_amount.value) : 0,
          netAmount: parseFloat(tx.transaction_amount.value)
                   - (tx.fee_amount ? parseFloat(tx.fee_amount.value) : 0),
          currency: tx.transaction_amount.currency_code,
          subscriptionId: tx.paypal_reference_id_type === 'SUB'
                          ? tx.paypal_reference_id : null,
          occurredAt: new Date(tx.transaction_initiation_date),
          ingestedVia: 'cron_sweep',
          sourceQueryId: tx.transaction_id,
        }).onConflictDoUpdate({
          target: [settlementLedger.provider, settlementLedger.providerObjectId,
                   settlementLedger.type, settlementLedger.presentmentCurrency],
          set: {
            // Update if PayPal's `transaction_updated_date` is newer
            recordedAt: new Date(),
          },
        });
      }
      pageId++;
    }

    await setCursorValue('settlement_paypal_last_sweep_end', windowEnd);
  });
}
```

---

## Pattern 5 — Stripe Tax integration

If the SaaS is in jurisdictions requiring tax collection (US states with sales tax, EU VAT, etc.):

```ts
// In Stripe Checkout Session creation:
{
  mode: 'subscription',
  // ...
  automatic_tax: { enabled: true },
  customer_update: {
    address: 'auto',  // collect billing address; Stripe Tax uses it
  },
  tax_id_collection: { enabled: true },  // for B2B (allows VAT ID entry)
}
```

Then on webhook events, the tax is in `invoice.tax` and `invoice.tax_amounts[]`. Store in `settlement_ledger.tax_amount`.

### What Stripe Tax handles vs what you handle

| Stripe handles | You handle |
|----------------|------------|
| Tax-rate determination per jurisdiction | Telling Stripe which products are taxable |
| Tax line on invoice | Recognition of tax as liability (not revenue) on your books |
| VAT MOSS / OSS aggregation | Filing your return (Stripe gives you the data) |
| Customer-facing tax display | Customer-facing copy explaining the tax line |

---

## Pattern 6 — Merchant-of-record platforms (Paddle / Lemon Squeezy)

For products selling globally without tax-compliance overhead:

- The MoR platform becomes the legal seller.
- Their billing system mirrors your billing system; you mirror their state.
- Your settlement_ledger ingests from THEIR API, not directly from Stripe.
- You don't compute tax; the MoR handles it.

Trade-offs:
- ✅ No global tax compliance.
- ✅ Single integration for many regions.
- ❌ Higher fee (typically 5-8% vs 3% for direct Stripe).
- ❌ Less control over checkout UX.
- ❌ Harder to switch off later.

The patterns here all apply: the MoR is the provider; their webhooks need 200-on-error; their event types need bidirectional coverage; etc.

---

## Pattern 7 — Deferred revenue recognition (GAAP)

Annual subscriptions paid in advance: cash arrives Day 0; revenue is recognized 1/12 per month.

```sql
CREATE TABLE revenue_recognition (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES users(id),
  subscription_id   text,
  invoice_id        text,
  recognition_date  date NOT NULL,           -- the period this is recognized in
  amount_recognized numeric(20, 4) NOT NULL,
  amount_deferred   numeric(20, 4) NOT NULL DEFAULT 0,
  currency          text NOT NULL,
  source_settlement_id uuid REFERENCES settlement_ledger(id),
  recognized_via    text NOT NULL,           -- 'monthly_close' | 'manual_adjustment'
  recorded_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX revenue_recognition_period_idx ON revenue_recognition (recognition_date);
```

A monthly close cron generates these rows from settlement_ledger:

```ts
// /api/cron/monthly-close (run on 1st of each month for prior month)
async function runMonthlyClose(periodEnd: Date) {
  await acquireAdvisoryLock(`monthly_close_${periodEnd.toISOString()}`, async () => {
    const periodStart = startOfMonth(periodEnd);

    // For each settlement that's a charge, recognize the appropriate fraction
    const charges = await db.query.settlementLedger.findMany({
      where: and(
        eq(settlementLedger.type, 'charge'),
        gte(settlementLedger.occurredAt, periodStart),
        lt(settlementLedger.occurredAt, addMonths(periodStart, 1)),
      ),
    });

    for (const charge of charges) {
      const sub = await getSubscriptionForSettlement(charge);
      const subInterval = sub.interval;  // 'month' | 'year'

      if (subInterval === 'month') {
        // Recognize fully in current period
        await db.insert(revenueRecognition).values({
          userId: charge.userId,
          subscriptionId: charge.subscriptionId,
          recognitionDate: periodEnd,
          amountRecognized: charge.netAmount,
          currency: charge.currency,
          sourceSettlementId: charge.id,
          recognizedVia: 'monthly_close',
        });
      } else if (subInterval === 'year') {
        // Recognize 1/12 in each of the next 12 months
        for (let i = 0; i < 12; i++) {
          await db.insert(revenueRecognition).values({
            userId: charge.userId,
            subscriptionId: charge.subscriptionId,
            recognitionDate: addMonths(periodStart, i),
            amountRecognized: charge.netAmount / 12,
            currency: charge.currency,
            sourceSettlementId: charge.id,
            recognizedVia: 'monthly_close',
          });
        }
      }
    }
  });
}
```

---

## Pattern 8 — The deferred revenue balance

For balance sheet reporting:

```sql
-- Deferred revenue at any point in time
SELECT
  SUM(amount_deferred) - SUM(amount_recognized) AS deferred_revenue_balance,
  currency
FROM revenue_recognition
WHERE recognition_date > $1  -- the date you're asking about
GROUP BY currency;
```

This is a real number that goes on the balance sheet as a liability. Don't conflate with cash.

---

## Pattern 9 — Net revenue snapshot

For period reporting:

```sql
-- Net revenue for a period
SELECT
  SUM(amount_recognized) AS recognized_revenue,
  currency
FROM revenue_recognition
WHERE recognition_date >= $1 AND recognition_date < $2
GROUP BY currency;

-- Cash collected for a period (different number)
SELECT
  SUM(net_amount) AS cash_collected,
  currency
FROM settlement_ledger
WHERE type = 'charge'
  AND occurred_at >= $1 AND occurred_at < $2
GROUP BY currency;

-- Tax collected for a period (liability)
SELECT
  SUM(tax_amount) AS tax_collected,
  currency
FROM settlement_ledger
WHERE occurred_at >= $1 AND occurred_at < $2
GROUP BY currency;

-- Refunds issued for a period
SELECT
  SUM(gross_amount) AS refunds_issued,
  currency
FROM settlement_ledger
WHERE type = 'refund'
  AND occurred_at >= $1 AND occurred_at < $2
GROUP BY currency;
```

These four numbers don't equal each other. They're four different facts.

---

## Pattern 10 — Audit-ready financial dashboard

The CFO / accountant view should expose:

- Recognized revenue by period.
- Cash collected by period.
- Deferred revenue balance.
- Tax collected (as liability) + tax remitted (when filed).
- Refunds + chargebacks by period.
- Effective fee rate (from B100 § 59).
- Currency mix (presentment vs settlement).

Each tile cites its source query (so an auditor can re-run).

---

## Pattern 11 — Integration with general ledger / accounting software

For companies using Xero / QuickBooks / NetSuite:

1. Settlement_ledger is the authoritative cash record.
2. Daily / weekly export job pushes to the GL.
3. Reconcile bank statement → settlement_ledger → GL monthly.
4. Tax remittance triggered from `tax_collected` totals.

The export format depends on the GL:
- Xero: CSV import OR API.
- QuickBooks: Online API.
- NetSuite: SuiteScript API.

---

## Pattern 12 — Per-currency challenges

If selling internationally:

- **FX gain/loss**: charge in EUR, settle in USD; the FX rate moves between charge and settlement. The difference is FX gain/loss.
- **Stripe Adaptive Pricing**: the customer sees EUR; you settle USD; tax is in EUR. Three currencies in one transaction.
- **Multi-currency MRR**: report MRR in USD-equivalent at FX rate of recognition date (not settlement date — be consistent).

```sql
-- Multi-currency MRR with FX normalization
SELECT
  SUM(amount_recognized * fx_rate_to_usd) AS mrr_usd_equivalent,
  recognition_date
FROM revenue_recognition rr
LEFT JOIN fx_rates fx ON fx.currency = rr.currency AND fx.date = rr.recognition_date
GROUP BY recognition_date
ORDER BY recognition_date DESC;
```

---

## Polish Bar checks for B75

- [ ] `settlement_ledger` schema with composite UNIQUE.
- [ ] Stripe Balance Transaction ingestion cron with cursor pagination.
- [ ] PayPal Transaction Search ingestion cron with overlap window.
- [ ] Stripe Tax integration (if applicable) — automatic_tax + customer_update.
- [ ] Merchant-of-record decision documented (use one or build in-house).
- [ ] `revenue_recognition` schema for GAAP.
- [ ] Monthly close cron generates recognition rows.
- [ ] Deferred revenue balance computable.
- [ ] Net revenue + cash collected + tax + refunds reportable per period.
- [ ] CFO / accountant dashboard with cited source queries.
- [ ] GL integration (if applicable) — Xero / QuickBooks / NetSuite.
- [ ] FX rate handling for multi-currency.
- [ ] Settlement_ledger rows immutable; corrections via `type = 'adjustment'`.
- [ ] Drift-guard: settlement_ledger row count matches Stripe Balance Transactions count for last 30 days (within tolerance).

---

## Common B75 mistakes

- **MRR == cash collected.** Conflates revenue and cash; misleads finance.
- **Tax stored on revenue line.** Tax is a liability; recognizing it as revenue overstates revenue.
- **FX rate at settlement date used for MRR.** MRR should be at recognition rate to be consistent across periods.
- **Settlement_ledger updated in place.** Corrections lose audit trail. Use adjustment rows.
- **PayPal transaction_id used as primary key.** Per § 59, can collide. Use composite key.
- **Stripe Tax enabled but not exposed in customer-facing copy.** Customer surprised at checkout.
- **Annual sub charged Day 0; recognized fully Day 0.** Wrong; should defer 11/12.
- **No monthly close cron.** Revenue recognition manual; finance team frustrated.
- **GL export drifts from settlement_ledger.** Reconciliation chaos.
- **No FX gain/loss tracking.** International revenue understates / overstates.
