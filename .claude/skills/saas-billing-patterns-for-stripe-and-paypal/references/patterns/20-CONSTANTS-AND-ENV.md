# Bundle B20 — Constants & Env

> **Where this comes from.** § 4 of the source guide.

This bundle is what stops the codebase from rotting. Hard-coded duplicates of price IDs, API versions, error codes, and route strings produce silent drift. Centralized + type-derived constants produce compile-time errors when the world moves.

---

## The 5 constants modules

| Module | Owns | Why centralized |
|--------|------|-----------------|
| `BUSINESS` | Pricing, team tiers, plan IDs, trial / discount policy | Money math touches every cron, every checkout, every report |
| `STRIPE_API_VERSION` + `getStripeClient` | The Stripe SDK version + client factory | One version everywhere; type-derived; lazy client |
| `WebhookErrorCodes` + `PaymentErrorCode` | Every error code emitted by webhook + payment paths | Dashboards / alerts / runbooks parse these — must be a closed set |
| `ROUTES` | Every billing-relevant URL | success_url builder + portal redirect + cron auth checks all reference these |
| `env` (Zod-validated) | Every env var the billing system reads | Single import; production-refines; missing-var catches at import time |

---

## `BUSINESS` constants

```ts
// src/lib/constants/business.ts

export const BUSINESS = {
  // Plan price (server-side display value; provider keeps the source of truth)
  PRO_MONTHLY_USD: 19.00,

  // Stripe price IDs (one per env)
  STRIPE_PRICES: {
    pro_monthly: process.env.STRIPE_PRICE_PRO_MONTHLY!,
    team_3_seats: process.env.STRIPE_PRICE_TEAM_3_SEATS!,
    team_5_seats: process.env.STRIPE_PRICE_TEAM_5_SEATS!,
    team_10_seats: process.env.STRIPE_PRICE_TEAM_10_SEATS!,
  },

  // PayPal plan IDs (one per env)
  PAYPAL_PLANS: {
    pro_monthly: process.env.PAYPAL_PLAN_PRO_MONTHLY!,
    team_3_seats: process.env.PAYPAL_PLAN_TEAM_3_SEATS!,
    team_5_seats: process.env.PAYPAL_PLAN_TEAM_5_SEATS!,
    team_10_seats: process.env.PAYPAL_PLAN_TEAM_10_SEATS!,
  },

  // Team tiers — each row is a (seat_count, monthly_price)
  TEAM_TIERS: [
    { seats: 3, monthly_usd: 50.00 },
    { seats: 5, monthly_usd: 80.00 },
    { seats: 10, monthly_usd: 150.00 },
  ] as const,

  // Trial / discount policy — explicitly NO trial / NO discount
  // (See § 37a of source: many billing failures came from accidentally
  //  enabled trials in the Stripe Dashboard.)
  TRIAL_DAYS: 0,
  ALLOW_PROMO_CODES: false,

  // Grace period after first failed payment before suspension
  GRACE_PERIOD_DAYS: 21,

  // Refund policy window
  REFUND_WINDOW_DAYS: 14,
} as const;

export type PlanId = keyof typeof BUSINESS.STRIPE_PRICES;
```

### Why this is the entry point

Every cron, every checkout, every webhook handler reads from `BUSINESS`. If you find a price literal anywhere else, that's a B20 task.

---

## `STRIPE_API_VERSION` + `getStripeClient`

```ts
// src/lib/constants/stripe-config.ts
import Stripe from 'stripe';

// Type-derived: a future SDK upgrade that doesn't accept this version
// fails at compile time, not runtime.
export const STRIPE_API_VERSION =
  '2025-12-15.clover' satisfies ConstructorParameters<typeof Stripe>[1]['apiVersion'];

let _client: Stripe | null = null;

export function getStripeClient(): Stripe {
  if (!_client) {
    _client = new Stripe(process.env.STRIPE_SECRET_KEY!, {
      apiVersion: STRIPE_API_VERSION,
      // Optional: add app info for Stripe support
      appInfo: { name: process.env.APP_NAME ?? 'unknown', version: '1.0.0' },
      // Optional: typescript: true is the default with @types/stripe
    });
  }
  return _client;
}
```

### Why lazy

Building the Stripe client at import time would force every code path that imports the module to also have `STRIPE_SECRET_KEY` available. In a serverless world that means cold-start cost on every isolate. Lazy = one client per warm isolate.

### Why one version everywhere

The bd-vifc1 epic ripped out 13 separate `new Stripe({ apiVersion: "2025-12-15.clover" })` calls across the codebase. If you can find any other place that constructs a Stripe client, that's a B20 cleanup.

### Per-call API version override (rare)

Sometimes you need to call a Stripe endpoint at an older API version (e.g., to read a legacy invoice). Use `stripeAccount` / per-request override via `Stripe.RequestOptions`:

```ts
const stripe = getStripeClient();
const legacyInvoice = await stripe.invoices.retrieve(id, { apiVersion: '2024-04-10' as Stripe.LatestApiVersion });
```

This is the only legitimate place a non-canonical version literal exists. Comment it.

---

## `WebhookErrorCodes` + `PaymentErrorCode`

```ts
// src/lib/constants/webhook-error-codes.ts

export const WebhookErrorCodes = {
  STRIPE: {
    SIGNATURE_MISSING: 'stripe.signature.missing',
    SIGNATURE_INVALID: 'stripe.signature.invalid',
    PAYLOAD_INVALID: 'stripe.payload.invalid',
    DEDUP_SKIPPED: 'stripe.dedup.skipped',
    PROCESS_ERROR_ACKED: 'stripe.process.error_acknowledged',
    ACCOUNT_MISMATCH: 'stripe.account.mismatch',
    USER_NOT_RESOLVABLE: 'stripe.user.not_resolvable',
  },
  PAYPAL: {
    SIGNATURE_MISSING: 'paypal.signature.missing',
    SIGNATURE_INVALID: 'paypal.signature.invalid',
    USER_ID_MISMATCH: 'paypal.user_id.mismatch',
    SUBSCRIPTION_ID_MISSING: 'paypal.subscription_id.missing',
    PAYLOAD_INVALID: 'paypal.payload.invalid',
    DEDUP_SKIPPED: 'paypal.dedup.skipped',
    PROCESS_ERROR_ACKED: 'paypal.process.error_acknowledged',
    PARENT_PAYMENT_NOT_FOUND: 'paypal.parent_payment.not_found',
  },
} as const;

export type WebhookErrorCode =
  | typeof WebhookErrorCodes.STRIPE[keyof typeof WebhookErrorCodes.STRIPE]
  | typeof WebhookErrorCodes.PAYPAL[keyof typeof WebhookErrorCodes.PAYPAL];
```

```ts
// src/lib/constants/payment-error-codes.ts

export const PaymentErrorCodes = {
  CARD_DECLINED: 'card_declined',
  AUTHENTICATION_REQUIRED: 'authentication_required',  // SCA / 3DS
  INSUFFICIENT_FUNDS: 'insufficient_funds',
  EXPIRED_CARD: 'expired_card',
  INCORRECT_CVC: 'incorrect_cvc',
  PROCESSING_ERROR: 'processing_error',
  PROVIDER_OUTAGE: 'provider_outage',
  SUBSCRIPTION_NOT_FOUND: 'subscription_not_found',
  IDEMPOTENCY_KEY_REUSED: 'idempotency_key_reused',
  RATE_LIMITED: 'rate_limited',
  PRICE_MISMATCH: 'price_mismatch',
  PAYMENT_INTENT_REQUIRES_ACTION: 'payment_intent_requires_action',
  UNKNOWN: 'unknown',
} as const;

export type PaymentErrorCode = typeof PaymentErrorCodes[keyof typeof PaymentErrorCodes];
```

### Why a closed set

Dashboards and runbooks parse these strings. A new in-line error string ("PayPal sub not found maybe") doesn't show up in alert dedup, doesn't get color-coded in the dashboard, and breaks the on-call runbook's grep. Force the set to be closed; force a new code to require a registry change.

### Drift-guard test

```ts
// __tests__/webhook-error-codes-completeness.test.ts
import { readFileSync } from 'node:fs';
import { glob } from 'node:fs';
import { WebhookErrorCodes } from '../src/lib/constants/webhook-error-codes';

test('every code emitted in handlers is registered', () => {
  const allCodes = new Set([
    ...Object.values(WebhookErrorCodes.STRIPE),
    ...Object.values(WebhookErrorCodes.PAYPAL),
  ]);
  // Walk webhook handlers; grep for `code:` strings; assert each is in allCodes.
});
```

---

## `ROUTES`

```ts
// src/lib/constants/routes.ts

export const ROUTES = {
  // Public
  HOME: '/',
  LOGIN: '/login',
  PRICING: '/pricing',
  DASHBOARD: '/dashboard',

  // Billing flows
  CHECKOUT_SUCCESS: '/dashboard?from=checkout',
  CHECKOUT_CANCEL: '/pricing?from=checkout_cancel',

  // API (used internally for cross-module references and cron auth)
  API: {
    STRIPE_WEBHOOK: '/api/stripe/webhook',
    PAYPAL_WEBHOOK: '/api/paypal/webhook',
    STRIPE_CHECKOUT: '/api/stripe/create-checkout',
    PAYPAL_CHECKOUT: '/api/paypal/create-checkout',
    CHECKOUT_VERIFY: '/api/checkout/verify',
    BILLING_PORTAL: '/api/billing/portal',
    CRON: {
      WEBHOOK_RECONCILIATION: '/api/cron/webhook-reconciliation',
      WEBHOOK_STALENESS: '/api/cron/webhook-staleness',
      DUNNING_REMINDERS: '/api/cron/dunning-reminders',
      CARD_EXPIRY_WARNING: '/api/cron/card-expiry-warning',
      UPCOMING_RENEWAL: '/api/cron/upcoming-renewal-notification',
      ORPHAN_SUB_CANCELS: '/api/cron/retry-orphan-sub-cancels',
      INDIVIDUAL_SUB_CANCELS: '/api/cron/retry-individual-sub-cancels',
      EMAIL_QUEUE: '/api/cron/email-queue',
      PROVIDER_RECONCILIATION: '/api/cron/provider-reconciliation',
      INTEGRITY_AUDIT: '/api/cron/billing-integrity-audit',
      SUBSCRIPTION_PROJECTION: '/api/cron/subscription-projection-reconciliation',
    },
  },
} as const;
```

### Why centralize routes

The Stripe checkout `success_url` is a real bug class (`bd-lp3vu`):

```ts
// WRONG — URL.toString() percent-encodes the {} so Stripe never substitutes
const url = new URL('/dashboard', baseUrl);
url.searchParams.set('session_id', '{CHECKOUT_SESSION_ID}');
const success_url = url.toString();   // → ?session_id=%7BCHECKOUT_SESSION_ID%7D

// CORRECT — template literal preserves the placeholder for Stripe to replace
const success_url = `${baseUrl}${ROUTES.CHECKOUT_SUCCESS}&session_id={CHECKOUT_SESSION_ID}`;
```

A type-safe `success_url` builder lives in B30 (`30-CHECKOUT.md`). The B20 part is just owning the route string.

---

## `env.ts` — Zod-validated env loader

```ts
// src/env.ts
import { z } from 'zod';

// Production refines: in production, certain keys MUST be present and
// in expected formats. In development, they can be optional.
const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']),

  // Database
  DATABASE_URL: z.string().url(),
  DIRECT_URL: z.string().url().optional(),  // for migrations

  // Stripe
  STRIPE_SECRET_KEY: z.string().startsWith('sk_'),
  STRIPE_WEBHOOK_SECRET: z.string().startsWith('whsec_'),
  STRIPE_PUBLISHABLE_KEY: z.string().startsWith('pk_'),  // OK to expose
  STRIPE_ACCOUNT_ID: z.string().startsWith('acct_').optional(),
  STRIPE_PRICE_PRO_MONTHLY: z.string().startsWith('price_'),
  STRIPE_PRICE_TEAM_3_SEATS: z.string().startsWith('price_'),
  STRIPE_PRICE_TEAM_5_SEATS: z.string().startsWith('price_'),
  STRIPE_PRICE_TEAM_10_SEATS: z.string().startsWith('price_'),

  // PayPal
  PAYPAL_CLIENT_ID: z.string(),
  PAYPAL_CLIENT_SECRET: z.string(),
  PAYPAL_WEBHOOK_ID: z.string(),
  PAYPAL_PLAN_PRO_MONTHLY: z.string().startsWith('P-'),
  PAYPAL_PLAN_TEAM_3_SEATS: z.string().startsWith('P-'),
  PAYPAL_PLAN_TEAM_5_SEATS: z.string().startsWith('P-'),
  PAYPAL_PLAN_TEAM_10_SEATS: z.string().startsWith('P-'),
  PAYPAL_API_BASE: z.string().url(),  // 'https://api-m.sandbox.paypal.com' or 'https://api-m.paypal.com'

  // Cron + alert tokens
  CRON_SECRET: z.string().min(32),
  ADMIN_EMAIL: z.string().email(),
  OPS_FAILSAFE_EMAIL: z.string().email(),  // MUST be different inbox from ADMIN_EMAIL

  // Email provider
  RESEND_API_KEY: z.string().startsWith('re_'),

  // Caches
  UPSTASH_REDIS_REST_URL: z.string().url().optional(),
  UPSTASH_REDIS_REST_TOKEN: z.string().optional(),

  // Feature flags
  FF_VERIFY_AS_WRITE_ENABLED: z.coerce.boolean().default(false),
  FF_INDIVIDUAL_SUB_INTENTS_ENABLED: z.coerce.boolean().default(false),
  FF_TEAM_PLANS_ENABLED: z.coerce.boolean().default(false),
}).superRefine((env, ctx) => {
  // Production refines
  if (env.NODE_ENV === 'production') {
    if (env.STRIPE_SECRET_KEY.startsWith('sk_test_')) {
      ctx.addIssue({ code: 'custom', message: 'STRIPE_SECRET_KEY is a test key in production' });
    }
    if (env.PAYPAL_API_BASE.includes('sandbox')) {
      ctx.addIssue({ code: 'custom', message: 'PAYPAL_API_BASE is sandbox in production' });
    }
    if (env.ADMIN_EMAIL === env.OPS_FAILSAFE_EMAIL) {
      ctx.addIssue({ code: 'custom', message: 'OPS_FAILSAFE_EMAIL must be a different inbox from ADMIN_EMAIL' });
    }
  }
});

export const env = envSchema.parse(process.env);
```

### Why production-refines

The Resend-down + ADMIN_EMAIL eats-alert chain (`bd-ja8c0`) was caught in part because `OPS_FAILSAFE_EMAIL` is required to be a different inbox in production. Other production-refines worth adding:

- `STRIPE_WEBHOOK_SECRET` is `whsec_*`, not `whsec_test_*` in production.
- `PAYPAL_API_BASE` is the live URL in production.
- Live Stripe `STRIPE_PRICE_*` IDs match the live environment (the test environment uses different price IDs; if you got it wrong, you can't subscribe at all).

---

## `.env*` discipline (B20 + B110 secret custody overlap)

- **`.env.local`** — checked into `.gitignore`, your dev-only test keys.
- **`.env.example`** — checked in, ALL keys present with placeholder values; serves as the contract.
- **`.env.production`** — never on disk in git; managed via Vercel / CD platform.
- **No live keys in `.env.development`** — production keys in development = developer accidentally hitting live during testing.

Verification:

```bash
# Find env files in git that shouldn't be there
git ls-files | rg "\.env(\.|\b)" | rg -v "\.example"

# Find live-looking keys in any committed file
git grep "sk_live_\|whsec_[a-z0-9]{20}\|re_[a-z0-9]{16}\|EAA[A-Za-z0-9]{20}"
```

---

## Idempotency keys (the B20 surface for B30/B40)

The constants for idempotency-key construction live in B20. The actual call sites live in B30 (checkout) and B40 (webhook).

### Stripe — user-hour-bucketed

```ts
// src/lib/constants/idempotency.ts

import { createHash } from 'node:crypto';

/**
 * Stripe idempotency key for checkout / subscription creation.
 *
 * Bucketed per (user, hour) so:
 *  - Multiple clicks within the same hour return the same Stripe session.
 *  - A click an hour later is a fresh session (state may have changed).
 */
export function buildStripeIdempotencyKey(
  userId: string,
  operation: string,           // 'create_checkout' | 'create_subscription' | etc.
  ...subjects: string[]        // optional disambiguators (e.g., price ID)
): string {
  const hourBucket = Math.floor(Date.now() / (60 * 60 * 1000));
  const subject = [operation, userId, hourBucket, ...subjects].join('|');
  return createHash('sha256').update(subject).digest('hex').slice(0, 64);
}
```

### PayPal — subject-opaque (different scheme, same purpose)

```ts
/**
 * PayPal-Request-Id for create-subscription idempotency.
 *
 * PayPal's idempotency key is independent of any payload field; we hash
 * a stable subject (user + operation + hour bucket) so retries collapse.
 */
export function buildPayPalRequestId(
  userId: string,
  operation: string,
  ...subjects: string[]
): string {
  const hourBucket = Math.floor(Date.now() / (60 * 60 * 1000));
  const subject = [operation, userId, hourBucket, ...subjects].join('|');
  // PayPal accepts up to 79 chars; we use a UUIDv5-esque scheme via hash + format
  const hash = createHash('sha256').update(subject).digest('hex');
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`;
}
```

---

## Polish Bar checks for B20

- [ ] `BUSINESS` constants module exists; no plan price / plan ID literals outside it.
- [ ] `STRIPE_API_VERSION` is type-derived; only one literal in the codebase (`grep -r '"20\d{2}-\d{2}-\d{2}'` returns just one hit).
- [ ] `getStripeClient` is the only constructor of `new Stripe(...)`.
- [ ] `WebhookErrorCodes` registry exists; drift-guard test pins completeness.
- [ ] `PaymentErrorCodes` registry exists.
- [ ] `ROUTES` covers every billing-relevant URL.
- [ ] `env.ts` uses Zod with production-refines.
- [ ] `OPS_FAILSAFE_EMAIL` is a different inbox from `ADMIN_EMAIL` in production.
- [ ] `.env*` discipline: no live keys in repo; `.env.example` documents the shape.
- [ ] No `NEXT_PUBLIC_*` env var names anything secret.
- [ ] Idempotency-key builders are centralized; no inline `crypto.randomUUID()` for dedup.

---

## Common B20 mistakes

- **`new Stripe(secret, { apiVersion: '...' })` in handler files** — duplicates the API version literal. Replace with `getStripeClient()`.
- **Hard-coded price ID in admin retry path** — drifts from checkout. Read from `BUSINESS`.
- **Inline error code string in webhook handler** — `code: 'paypal_user_id_mismatch'` should be `code: WebhookErrorCodes.PAYPAL.USER_ID_MISMATCH`.
- **`process.env.STRIPE_SECRET_KEY!` scattered across the codebase** — read from validated `env`, not `process.env`. The `!` non-null assertion swallows the missing-key error you should be catching at startup.
- **`OPS_FAILSAFE_EMAIL = ADMIN_EMAIL` in env** — the failsafe entire purpose is bypassing whatever's eating alerts; if both go to the same inbox, you've defeated the design. The production-refine catches this.
- **`success_url` built with `URL.toString()`** — encodes the `{CHECKOUT_SESSION_ID}` placeholder. Use a template literal builder.
