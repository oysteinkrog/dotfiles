# Bundle B95 — Internationalization & Multi-Currency

> **Where this comes from.** § 4.7 (Adaptive Pricing audit) + § 59 (multi-currency in settlement ledger) + B75 (FX gain/loss) + cross-reference with `/saas-customer-analytics`.

For SaaS selling across borders. Multi-currency is more than "let users pay in EUR" — it's tax, presentment, settlement FX, refund currency, support copy, payment-method availability, and PSD2/SCA compliance.

Skip if single-currency US-only. Essential for any product with > 20% international customers.

---

## Pattern 1 — The currency triangle

```
INTEGRATION currency  → What you settle in (typically USD if you're a US company)
                       → What appears in Stripe Balance Transactions

PRESENTMENT currency  → What the customer SEES at checkout
                       → What appears in their statement
                       → MAY differ from integration currency (Adaptive Pricing)

SETTLEMENT currency   → What hits your bank
                       → MAY differ from integration currency (Stripe converts at FX rate)
```

For a USD-integrated company with EUR-presentment customers paying via Stripe Adaptive Pricing:
- Customer sees: €18.99
- Stripe charges in: EUR
- Stripe converts to: USD (at Stripe's FX rate + 1% conversion fee)
- Your bank receives: ~$19.50 USD (after Stripe FX conversion)

This is THREE different numbers for ONE charge.

---

## Pattern 2 — Schema additions for multi-currency

```sql
-- Subscriptions can have a presentment currency that differs from the integration currency
ALTER TABLE subscriptions
  ADD COLUMN presentment_currency text,         -- 'EUR', 'GBP', 'JPY', etc.
  ADD COLUMN integration_currency text NOT NULL DEFAULT 'usd';

-- Settlement ledger already has presentment_currency + presentment_amount per B75

-- FX rate snapshot table for historical normalization
CREATE TABLE fx_rates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date        date NOT NULL,
  source_currency text NOT NULL,
  target_currency text NOT NULL,
  rate        numeric(20, 8) NOT NULL,
  source      text NOT NULL,                   -- 'stripe' | 'ecb' | 'oanda' | 'manual'
  fetched_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (date, source_currency, target_currency, source)
);
CREATE INDEX fx_rates_lookup_idx ON fx_rates (date, source_currency, target_currency);

-- BUSINESS constants per-currency
-- BUSINESS.STRIPE_PRICES = {
--   pro_monthly: { usd: 'price_xxx', eur: 'price_yyy', gbp: 'price_zzz' },
--   ...
-- }
```

---

## Pattern 3 — BUSINESS multi-currency constants

```ts
// src/lib/constants/business.ts
export const BUSINESS = {
  // Per-currency pricing
  STRIPE_PRICES: {
    pro_monthly: {
      usd: process.env.STRIPE_PRICE_PRO_MONTHLY_USD!,
      eur: process.env.STRIPE_PRICE_PRO_MONTHLY_EUR!,
      gbp: process.env.STRIPE_PRICE_PRO_MONTHLY_GBP!,
      jpy: process.env.STRIPE_PRICE_PRO_MONTHLY_JPY!,
    },
    team_3_seats: {
      usd: process.env.STRIPE_PRICE_TEAM_3_USD!,
      eur: process.env.STRIPE_PRICE_TEAM_3_EUR!,
      // ...
    },
  },

  // Display amounts (for UI consistency; provider is authoritative)
  PRICES_BY_CURRENCY: {
    pro_monthly: { usd: 19.00, eur: 18.99, gbp: 16.99, jpy: 2900 },
    team_3_seats: { usd: 50.00, eur: 49.99, gbp: 44.99, jpy: 7500 },
  },

  ALLOWED_PRESENTMENT_CURRENCIES: ['usd', 'eur', 'gbp', 'jpy', 'cad', 'aud'] as const,

  // Tax behavior per currency
  TAX_BEHAVIOR: {
    usd: 'exclusive',  // tax added at checkout
    eur: 'inclusive',  // tax baked in (EU norm)
    gbp: 'inclusive',
    jpy: 'inclusive',
  },
} as const;
```

The currency-keyed structure makes it explicit that `pro_monthly` is a SET of prices, not one price.

---

## Pattern 4 — Currency selection at checkout

```ts
// src/app/api/stripe/create-checkout/route.ts
async function POST(request: Request) {
  const userId = await requireUserId(request);
  const { planId, currency = detectCurrencyFromIp(request) } = await request.json();

  if (!BUSINESS.ALLOWED_PRESENTMENT_CURRENCIES.includes(currency)) {
    throw new HttpError(400, 'unsupported_currency');
  }

  const priceId = BUSINESS.STRIPE_PRICES[planId][currency];
  if (!priceId) {
    throw new HttpError(400, 'currency_not_available_for_plan');
  }

  // ... rest of checkout flow
  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    line_items: [{ price: priceId, quantity: 1 }],
    // currency MUST match the price
    // ...
  });
}
```

### IP-based detection (for default)

```ts
import { geolocation } from '@vercel/functions';

function detectCurrencyFromIp(request: Request): SupportedCurrency {
  const geo = geolocation(request);
  const country = geo.country?.toUpperCase();
  if (!country) return 'usd';

  const map: Record<string, SupportedCurrency> = {
    GB: 'gbp', UK: 'gbp',
    DE: 'eur', FR: 'eur', ES: 'eur', IT: 'eur', NL: 'eur',
    JP: 'jpy',
    CA: 'cad',
    AU: 'aud',
  };
  return map[country] ?? 'usd';
}
```

Customer can override at checkout (don't lock them to IP-detected currency).

---

## Pattern 5 — Stripe Adaptive Pricing

If you don't want to maintain per-currency price IDs, Stripe Adaptive Pricing converts on-the-fly:

```ts
// In Stripe Dashboard: enable Adaptive Pricing for the account
// Then in checkout:
const session = await stripe.checkout.sessions.create({
  mode: 'subscription',
  line_items: [{ price: USD_PRICE_ID, quantity: 1 }],
  // No currency override; Stripe auto-detects from customer location
  // The session's currency stays USD, but customer sees their local currency
});
```

After the customer pays:
- `session.amount_total` = USD amount.
- `session.currency` = 'usd'.
- `session.presentment_details.presentment_amount` = e.g., 1899 (cents in EUR).
- `session.presentment_details.presentment_currency` = 'eur'.

Per § 4.7: AUDIT this. Don't conclude `amount_total = 2000` means customer saw "$20.00 USD."

### Trade-offs

| Adaptive Pricing | Per-currency price IDs |
|------------------|------------------------|
| ✅ One price ID; no maintenance | ❌ N price IDs per plan |
| ✅ Stripe handles FX | ❌ You must price competitively per currency |
| ❌ Stripe takes FX margin (1%) | ✅ You control margin |
| ❌ Limited control over presentment amount | ✅ You set exact amount per currency |
| ❌ Refund currency math fuzzy | ✅ Refund currency is the price's currency |

Both are valid; pick based on your team's bandwidth.

---

## Pattern 6 — PayPal multi-currency

PayPal plans have a fixed currency at creation. Multi-currency = multiple plans:

```
BUSINESS.PAYPAL_PLANS = {
  pro_monthly: {
    usd: 'P-XYZ-USD',
    eur: 'P-XYZ-EUR',
    gbp: 'P-XYZ-GBP',
  },
}
```

PayPal does NOT have an Adaptive-Pricing equivalent. Plans-per-currency is the only option.

---

## Pattern 7 — Refund currency

Refunds must match charge currency:

```ts
// Refund in the same currency as the charge
const charge = await stripe.charges.retrieve(chargeId);
const refund = await stripe.refunds.create({
  charge: charge.id,
  amount: charge.amount,  // SAME currency as charge
});
```

If customer paid in EUR (presentment) but charge currency was USD (integration), refund is in USD. Customer's bank converts back to EUR; FX may have moved → customer gets slightly less / more than they paid.

Document this in your refund policy: "Refunds are issued in the original charge currency. Foreign exchange rate fluctuations may mean you receive a slightly different amount than you paid."

---

## Pattern 8 — Multi-currency MRR

The challenge: how do you sum subscriptions in different currencies?

Convert all to a base currency (typically USD) at a consistent FX rate. Two approaches:

**A. Snapshot-time FX (consistent within a snapshot):**
```sql
SELECT SUM(amount * fx.rate) AS mrr_usd
FROM (
  SELECT
    s.id,
    s.current_amount AS amount,
    COALESCE(s.presentment_currency, s.integration_currency) AS currency
  FROM subscriptions s WHERE status = 'active'
) sub
LEFT JOIN fx_rates fx
  ON fx.source_currency = sub.currency
 AND fx.target_currency = 'usd'
 AND fx.date = CURRENT_DATE
```

**B. Recognition-time FX (consistent across periods):**
Each `revenue_recognition` row stores the FX rate at recognition date. MRR is sum of those.

Approach B is more correct for trend analysis (FX swings don't appear as revenue swings). Approach A is faster.

---

## Pattern 9 — Customer-facing currency display

Show prices in the customer's currency, with the integration currency as backup:

```tsx
function PricingCard({ plan }: Props) {
  const userCurrency = useUserCurrency();  // from JWT or fetch
  const price = BUSINESS.PRICES_BY_CURRENCY[plan.id][userCurrency] ?? BUSINESS.PRICES_BY_CURRENCY[plan.id].usd;
  const symbol = currencySymbol(userCurrency);
  return <div>{symbol}{price.toFixed(2)} / month</div>;
}
```

For dunning emails, invoice receipts, and similar customer-facing communications: show the amount in the CURRENCY THE CUSTOMER WAS CHARGED IN.

---

## Pattern 10 — Tax compliance per region

| Region | Tax type | When required |
|--------|----------|---------------|
| US | Sales tax (state-by-state) | If selling in nexus states; thresholds per state (typically $100K or 200 transactions/year) |
| EU | VAT (MOSS / OSS) | If selling to EU customers; B2C requires registration; B2B requires reverse-charge |
| UK | VAT | Post-Brexit: separate UK VAT scheme |
| Canada | GST/HST/PST | Per-province |
| Australia | GST | If selling to AU customers |
| India | GST | Complex; consult tax advisor |
| Japan | Consumption tax | If selling to JP customers above threshold |

Stripe Tax handles US + EU + UK + AU + many others. For others (India, Brazil), often need a merchant-of-record platform.

Document your tax strategy in `docs/billing/tax-strategy.md` so future engineers don't have to re-derive.

---

## Pattern 11 — PSD2 / SCA compliance (EU)

European customers' card payments require Strong Customer Authentication (3DS). Per § 34, the SCA flow is:

1. `invoice.payment_action_required` webhook fires.
2. Customer-facing email points them at the SCA challenge URL.
3. Customer completes 3DS (Apple Pay / Google Pay / SMS / app).
4. Stripe processes; `invoice.paid` fires.

For European customers, treat SCA as the COMMON case, not the exception. UK still requires it post-Brexit.

For other regions:
- **India RBI**: similar SCA-like rules; Stripe handles via supported payment methods.
- **Brazil**: PIX requires opt-in; Stripe / merchant-of-record needed.
- **Japan**: alternative payment methods (Konbini, Bank Transfer, etc.).

---

## Pattern 12 — Per-region payment method enablement

Different regions need different payment methods:

| Region | Common payment methods beyond card |
|--------|-----------------------------------|
| EU | SEPA Direct Debit, iDEAL, Bancontact, EPS, P24, Sofort, Klarna |
| UK | BACS Direct Debit, Klarna |
| Brazil | Boleto, PIX |
| Japan | Konbini, Pay-easy, JCB |
| India | UPI, RuPay, PayTM |
| Mexico | OXXO |
| China | Alipay, WeChat Pay (limited Stripe support; consider local PSP) |

Stripe Payment Method Configurations (per § 4.2a) lets you enable per-region. AUDIT the active config matches the regions you sell to.

---

## Pattern 13 — Customer Portal i18n

Stripe Customer Portal has built-in i18n; configure the locale:

```ts
const session = await stripe.billingPortal.sessions.create({
  customer: user.stripeCustomerId,
  return_url: returnUrl,
  locale: user.locale,  // 'fr', 'de', 'es', 'ja', etc.
});
```

For PayPal: their portal i18n is auto-detected from browser; you don't control it.

---

## Pattern 14 — Dunning emails per locale

Generate dunning copy per locale:

```ts
// emails/dunning/payment_failed.{en,fr,de,es,ja}.tsx
function PaymentFailedEmail({ user, invoice, locale }: Props) {
  const t = getTranslations(locale);
  return <div>
    <h1>{t.dunning.title}</h1>
    <p>{t.dunning.body({ amount: invoice.amount_due, currency: invoice.currency })}</p>
    <Button href={invoice.hosted_invoice_url}>{t.dunning.cta}</Button>
  </div>;
}
```

Keep translations in a single file per locale; review with native speakers.

---

## Pattern 15 — Per-region compliance checklist

| Region | Compliance items |
|--------|------------------|
| EU | GDPR (data subject rights, lawful basis, DPA), VAT MOSS, PSD2 SCA, ePrivacy Directive |
| UK | UK GDPR, UK VAT, PSD2 (still applies post-Brexit) |
| US | CCPA/CPRA (California), state sales tax nexus, ECPA |
| Canada | PIPEDA, per-province sales tax |
| Brazil | LGPD, PIX |
| India | DPDP Act, RBI rules on recurring mandates |
| China | PIPL (very strict; often blocks SaaS expansion) |

This bundle doesn't cover the legal side; it covers what the BILLING SYSTEM needs to support compliance:
- Per-customer data export (GDPR DSR).
- Per-customer data deletion (GDPR + various).
- Audit trail for tax filings.
- Currency-correct receipts.

---

## Polish Bar checks for B95

- [ ] Currency triangle (integration / presentment / settlement) documented.
- [ ] Schema supports `presentment_currency` + `integration_currency` + FX rates.
- [ ] BUSINESS constants per-currency for prices + plans + tax behavior.
- [ ] Currency selection at checkout (IP-detected default + user override).
- [ ] Per-currency Stripe price IDs OR Adaptive Pricing (chosen explicitly).
- [ ] PayPal plans-per-currency.
- [ ] Refund policy clear about FX.
- [ ] Multi-currency MRR computed correctly (consistent FX rate per snapshot or recognition).
- [ ] Customer-facing currency display matches charge currency.
- [ ] Tax strategy documented per region.
- [ ] Per-region payment methods enabled in Payment Method Configuration.
- [ ] Customer Portal locale set per user.
- [ ] Dunning emails localized per locale.
- [ ] Per-region compliance checklist reviewed before launching new market.

---

## Common B95 mistakes

- **Hard-coded "USD" everywhere.** Doesn't break US-only; breaks first international customer.
- **Adaptive Pricing enabled but presentment_currency not audited.** Refund math uses wrong number.
- **Refund issued in customer's locale currency instead of charge currency.** Stripe rejects; manual reconciliation.
- **Multi-currency MRR sums numeric values without FX conversion.** Investor reports nonsense.
- **Tax not collected on EU sales.** Penalty + back-tax.
- **Customer Portal not localized.** EU customers complain.
- **Dunning email in English to JP customer.** Customer can't act on it; churns.
- **PayPal multi-currency assumed.** Each currency needs a separate plan; not auto.
- **No PSD2 / SCA support.** EU card payments fail; revenue drops 20-30% in EU.
- **Adaptive Pricing margin not factored into unit economics.** Stripe takes 1% FX; you're 1% less profitable than spreadsheet says.
