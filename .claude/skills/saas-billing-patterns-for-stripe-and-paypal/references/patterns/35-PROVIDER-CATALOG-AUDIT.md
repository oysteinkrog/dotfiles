# Bundle B35 — Provider Catalog Audit

> **Where this comes from.** § 4.7, § 4.7.1, § 4.2a of the source guide. Supports the verification-first protocol.

This bundle exists because **Zod can prove that an env var LOOKS like a Stripe price ID. It cannot prove the live Stripe object still matches the product.** A Dashboard click by a non-engineer can break invariants the code assumes are in force.

A world-class billing backend has a **read-only provider catalog audit** that runs:
- Before every launch (verify product policy is enforced).
- After every credential rotation (verify the new key sees the same world).
- After every billing-touching deploy (verify the deploy didn't accidentally subscribe new events).
- On a daily cron with alert-only output (catch silent Dashboard drift).

---

## The minimum live-check matrix

| Surface | What to verify |
|---------|----------------|
| **Stripe account** | Expected account ID; key mode (`sk_live_` vs `sk_test_`); country/currency; `charges_enabled`; `payouts_enabled`; account verified |
| **Stripe prices** | Each configured price is `active`, `livemode`, expected interval (monthly), expected currency (USD), expected amount (matches `BUSINESS`), expected `tax_behavior`, expected product |
| **Stripe Customer Portal** | Active/default/live config; payment-method-update enabled; cancellation `mode` and `proration_behavior` match refund policy; `subscription_update` and `promotion_codes` knobs match product policy |
| **Stripe invoice recovery** | Recent open invoices grouped by `attempt_count`, `next_payment_attempt`, `collection_method`, `auto_advance`, `automatic_tax.enabled`, `billing_reason` |
| **Stripe checkout sessions (sample)** | Recent sessions grouped by `mode`, `status`, `amount_total`, `currency`, `allow_promotion_codes`, `discounts`, `adaptive_pricing.enabled`, `automatic_tax.enabled`, `payment_method_types`, `payment_method_configuration_details`, URL host, metadata keys, TTL |
| **Stripe payment method configurations** | Active/default Payment Method Configuration rows; effective display state for `card`, `link`, wallets, BNPL, bank debits, Stripe-hosted PayPal; explicit allow/deny for every enabled method |
| **Stripe Payment Links** | Count all links; zero active subscription links unless deliberately supported; active links must match the same metadata, discount, tax, completion, recurring-price policy as app-created sessions |
| **Stripe discounts** | Coupons, promotion codes, customer discounts, subscription discounts, session discounts ABSENT unless product policy explicitly changes |
| **Stripe webhook endpoint** | URL, `status=enabled`, endpoint API version, `enabled_events` diffed against code's `HANDLED_STRIPE_EVENTS` |
| **PayPal OAuth** | Token can be minted for the explicit `PAYPAL_ENV`; never print the token |
| **PayPal plans** | Each configured plan is `ACTIVE`, monthly, USD, expected amount, expected product, expected `quantity_supported`, no unexpected trial or finite regular cycles |
| **PayPal dunning prefs** | `auto_bill_outstanding`, `setup_fee_failure_action`, `payment_failure_threshold`, no-setup-fee setting match explicit product policy |
| **PayPal webhook** | URL and event subscription list diffed against code's `HANDLED_PAYPAL_EVENTS` |

For a non-source-guide SaaS, do NOT cargo-cult the literal "monthly USD, no trials, no discounts, fixed tiers" checks. Replace those cells with the product's declared policy matrix: allowed currencies, intervals, trial cycles, coupon families, annual prices, sales-contract plans, region-specific prices, tax mode, self-service plan-change permissions.

**The reusable pattern is not the specific policy; it is proving that live provider state matches whatever policy the business has actually approved.**

---

## The audit must be bidirectional

For webhook events specifically, three states:

1. **`handled_but_not_subscribed`** — code has a branch, but the provider will never send that event. → Dead code; either subscribe in Dashboard or remove the branch.
2. **`subscribed_but_unhandled`** — provider will send the event, but code only logs / ignores it. → Silent miss; either add a handler with explicit decision or unsubscribe.
3. **`subscribed_and_handled`** — happy path.

Treat both 1 and 2 as deploy-blocking drift unless the mismatch is captured in an intentional decision table:

```ts
type ProviderEventDecision = "mutate" | "record_only" | "ignore_with_reason";

interface ProviderEventCoverageRow {
  provider: "stripe" | "paypal";
  eventType: string;
  subscribedInProvider: boolean;
  handledInCode: boolean;
  decision: ProviderEventDecision;
  reason?: string;
}
```

---

## History-based audit (in addition to endpoint-config)

Endpoint config tells you what *should* arrive. Recent provider history tells you what *actually did* arrive and in what schema version.

| Provider | Read-only history query | What to store in audit report |
|----------|-------------------------|-------------------------------|
| Stripe | `/v1/events` with bounded recent limit | counts by `type`, counts by `api_version`, `livemode`, `pending_webhooks` max, unexpected event types |
| Stripe | `/v1/balance_transactions` | counts by `type` and `reporting_category`, sample field-shape only, no customer payloads |
| PayPal | `/v1/notifications/webhooks-events` | counts by `event_type`, `resource_type`, `event_version`, `resource_version`, subscription failure events present or absent |
| PayPal | `/v1/reporting/transactions` | counts by `transaction_event_code`, fee-field presence, currency mix, balance-field presence |

**Counts only.** Never dump provider event bodies, transaction rows, payer names, emails, addresses, or subscription IDs into logs / PR comments / guide text. PayPal webhook + Transaction Search rows can include customer-level data.

**For PayPal webhook-history calls**, use second-precision UTC timestamps such as `2026-05-04T23:41:37Z`; the live API accepts that format reliably. Avoid local-time formatting and implicit time zones.

---

## The diagnostic loop (§ 4.7.1 — discipline)

Treat live provider diagnostics as a production engineering workflow with the same rigor as DB migrations.

1. **State the invariant first.** "no active recurring Payment Links"; "Stripe-hosted PayPal disabled because PayPal is a separate provider"; "all PayPal plans are active monthly USD with no trials"; "webhook subscriptions and handler branches are bidirectionally aligned."
2. **Run only read-only provider calls.** Stripe `list`/`retrieve` and PayPal `GET` are diagnostic-safe. Provider mutations (retry invoice, cancel sub, issue refund, patch plan, change webhook subscription) are INCIDENT actions and need a separate operator-approved runbook.
3. **Emit aggregate evidence, not rows.** Counts by status/type/currency, boolean field presence, key sets, small enumerations. NOT raw checkout sessions, webhook events, transactions, payer records, customer objects, HATEOAS URLs, tokens, subscription IDs.
4. **Compare provider state to code AND product policy.** Result answers "does production still match the intended contract?", not merely "did an API call succeed?"
5. **Record the evidence envelope.** Every artifact includes `checked_at`, `environment` (production/sandbox; never the secret), provider API version where available, SDK/CLI version if relevant, endpoint names queried, sample limits or full-pagination status, redaction policy used.

---

## Minimal artifact shape

```json
{
  "checked_at": "2026-05-05T00:07:46Z",
  "environment": "production",
  "scope": "read_only_provider_diagnostics",
  "redaction": "counts_only_no_customer_rows_no_tokens_no_urls",
  "stripe": {
    "checkout_sessions_sample": {
      "count": 100,
      "mode_counts": { "subscription": 100 },
      "payment_method_types_counts": { "card|link": 22, "card|klarna|link|cashapp|amazon_pay": 8 },
      "payment_link_present_count": 0,
      "adaptive_pricing_enabled_count": 100,
      "automatic_tax_enabled_count": 0,
      "allow_promotion_codes_true_count": 0,
      "discounts_present_count": 0
    },
    "webhook_endpoint": {
      "endpoint_api_version": "2025-12-15.clover",
      "enabled_events_count": 18,
      "subscribed_set_hash": "sha256:..."
    },
    "events_recent_sample": {
      "count": 100,
      "type_counts": { "customer.subscription.updated": 47, "invoice.paid": 23, ... },
      "api_version_counts": { "2025-12-15.clover": 100 }
    },
    "prices_audited": {
      "checked_count": 4,
      "active_count": 4,
      "currency_counts": { "usd": 4 },
      "interval_counts": { "month": 4 }
    }
  },
  "paypal": {
    "plans": {
      "checked_plan_count": 5,
      "status_counts": { "ACTIVE": 5 },
      "billing_cycles_count": { "1": 5 },
      "currency_counts": { "USD": 5 },
      "trial_cycles_count": { "0": 5 },
      "payment_failure_threshold_counts": { "3": 5 },
      "setup_fee_failure_action_counts": { "CANCEL": 1, "CONTINUE": 4 },
      "auto_bill_outstanding_counts": { "true": 5 }
    },
    "webhook": {
      "subscribed_events_count": 9,
      "subscribed_set_hash": "sha256:..."
    },
    "webhooks_events_recent": {
      "count": 82,
      "event_type_counts": {
        "PAYMENT.SALE.COMPLETED": 45,
        "BILLING.SUBSCRIPTION.PAYMENT.FAILED": 3,
        ...
      }
    }
  }
}
```

The artifact is THE audit. It's the evidence the next agent (or auditor) reads to confirm the system is in the expected state.

---

## Security rules for diagnostic runs (mandatory)

These are the same rules from VERIFICATION-FIRST.md, repeated here because B35 implementations forget them:

1. **Do not inspect secrets by printing them.** Never `cat`, `rg`, `grep`, `echo` `.env.local` in a shared transcript. Print only env var names, key modes (`live`/`test`), provider account IDs, boolean presence.

2. **Do not put secrets in shell arguments.** `curl -u client:secret`, `stripe ... --api-key sk_live_...`, copied OAuth tokens leak through shell history, process listings, terminal scrollback, agent logs. Prefer SDK calls or short-lived processes that build Authorization headers from `process.env` internally.

3. **Never print OAuth tokens or webhook signatures.**
   - PayPal: mint OAuth token inside the diagnostic process, reuse for that run, discard.
   - Stripe: use existing SDK client; do not dump `Stripe-Signature`, `whsec_`, Checkout URLs, Customer Portal URLs, session URLs.

4. **Redact IDs unless an ID IS the finding.** Counts and key sets are usually enough. If an incident requires a specific provider ID, store in restricted incident artifact.

5. **Collect error metadata WITHOUT payloads.** Stripe errors include `request_id`. PayPal includes `PayPal-Debug-Id`. Store with HTTP status + error category + endpoint + timestamp. NOT full request/response body unless PII-reviewed.

---

## Stripe-specific diagnostic patterns

- Stripe list endpoints default to bounded pages. Decide: **sample** (`limit=100`, recent only) or **complete sweep** (`autoPagingEach`/`autoPagingToArray` with explicit caps + rate-limit handling). Label the artifact accordingly. A sample finding is NOT a population proof.

- Keep three API-version surfaces separate: SDK client API version; webhook endpoint API version; each Event object's `api_version`. Diagnostic that proves only ONE of three can still miss schema drift.

- Use expansions sparingly. Expanding nested customers, subscriptions, invoices, payment methods, balance transactions, disputes turns a cheap counts-only audit into a slow PII-heavy dump. Prefer field presence, ID-prefix counts, targeted `retrieve` calls for already-identified anomalies.

- For Checkout audits, group by `mode`, `payment_method_types`, `payment_method_configuration_details` presence, `payment_link`, `allow_promotion_codes`, `discounts`, `automatic_tax`, `adaptive_pricing`, metadata keys, URL hosts, TTL.

- For Payment Links, list links AND list each link's line items to detect recurring prices. Link object alone isn't enough.

- For balance/settlement checks, prefer `type`, `reporting_category`, currency, fee-field presence, reconciliation totals. Don't dump charges, refunds, disputes, payouts.

---

## PayPal-specific diagnostic patterns

- Treat `PAYPAL_ENV` as first-class. Production: `https://api-m.paypal.com`. Sandbox: `https://api-m.sandbox.paypal.com`. Don't infer from client ID, webhook ID, hostname.

- Mint OAuth token ONCE per run with client credentials, then bounded `GET` calls. Token success proves credentials + environment alignment, but the token itself is never evidence to print.

- Use second-precision UTC timestamps for webhook-history windows: `2026-05-04T23:41:37Z`. Avoid clever local-time formatting; avoid implicit time zones.

- Plan audits must compare AMOUNTS, not just object presence. A `payment_preferences.setup_fee` object with `value="0"` is not a paid setup fee; store normalized cents amount (`USD:0`) and `setup_fee_failure_action` separately.

- Webhook + Transaction Search responses can include payer names, emails, addresses, subscription IDs, balance details. Aggregate by `event_type`, `resource_type`, `event_version`, `resource_version`, `transaction_event_code`, currency, fee-field presence, status. NOT logging resource bodies.

- Preserve `PayPal-Debug-Id` and HTTP status when a request fails. That's the provider-support breadcrumb; raw response body usually less useful and much riskier.

---

## Operationalization

Build a checked-in `provider-catalog-audit` command (or admin-only diagnostics endpoint) that uses:
- The app's existing env loader.
- The rate-limit / backoff policy.
- The logger redaction.
- The business constants (so audit knows what "expected" means).

Defaults:
- Read-only counts.
- Require explicit `--full-scan` for pagination beyond most recent page.
- Fail closed if it would print secrets or raw customer rows.

`scripts/provider-diagnostics.sh` is the cross-project skeleton.

---

## What § 4.2a adds — Stripe payment-method configuration

The May 5, 2026 production check showed why this gets its own attention:

The last 100 Stripe Checkout Sessions:
- All app-created subscription sessions (`payment_link=null`).
- All used a Payment Method Configuration.
- Showed dynamic method sets such as `card|link`, `card|link|amazon_pay`, `card|klarna|link|cashapp|amazon_pay`.

The live default Payment Method Configuration had: `card`, Link, Amazon Pay, Cash App, Klarna, Affirm enabled/available; Stripe-hosted PayPal off/unavailable.

Stripe had ZERO Payment Links, including zero active recurring Payment Links.

Why this matters:
- **"Stripe" no longer means "card-only"** once dynamic payment methods are active. Cash App, Klarna, Amazon Pay all show. Each has its own dispute / refund / dunning behavior.
- **"PayPal" can mean either** the separate PayPal Subscriptions integration OR PayPal as a Stripe payment method. If the product keeps PayPal as a separate rail, audit that Stripe-hosted PayPal stays OFF (or explicitly reclassify it as Stripe-originated revenue / dunning / refunds / disputes / support).
- **Payment Links are a bypass risk.** If they ever appear (Marketing creates one), treat active recurring links as a SECOND checkout surface that must satisfy the same `metadata.user_id`, pending-checkout lock, same-provider reuse probe, cross-provider probe, first-party return URL, no-discount/no-trial, tax, webhook-reconciliation contract as the app checkout route.

---

## Drift triggers (page someone)

| Drift | Severity |
|-------|----------|
| Subscribed event in Stripe Dashboard not in `HANDLED_STRIPE_EVENTS` | High (silent miss; potential entitlement bug) |
| Handler branch for an event not subscribed in Dashboard | Medium (dead code; remove or subscribe) |
| New active Stripe coupon not in BUSINESS allowlist | Critical (policy violation) |
| New PayPal trial cycle on a "no-trials" plan | Critical (policy violation) |
| Payment Method Configuration enabled a method without policy update | Medium (audit + decide) |
| Active Payment Link not in app allowlist | High (bypass risk) |
| Stripe-hosted PayPal turned ON when policy says separate provider | High (split entitlement / refund attribution) |
| Adaptive Pricing turned ON without `presentment_currency` audit | Medium (presentation mismatch) |
| Customer Portal `subscription_update` enabled when policy says no | Medium (customer can self-change plans) |
| Webhook endpoint API version diverged from `STRIPE_API_VERSION` | High (schema drift) |

Each of these gets a row in the daily audit's alert output.

---

## Polish Bar checks for B35

- [ ] `provider-catalog-audit` command exists and runs in CI nightly.
- [ ] Audit covers every row in the minimum live-check matrix.
- [ ] Audit is bidirectional for webhook event coverage.
- [ ] History-based audit (recent events / transactions distribution) runs daily.
- [ ] Artifact follows the evidence-envelope shape.
- [ ] Counts-only redaction enforced; CI test confirms no PII in audit output.
- [ ] Drift triggers fire alerts; runbook for each.
- [ ] Stripe-hosted PayPal explicitly OFF (or explicitly ON with documented reason).
- [ ] Adaptive Pricing audited if enabled.
- [ ] Payment Links audited (zero active recurring, OR each matches checkout contract).
- [ ] Customer Portal config audited.
- [ ] Per-PayPal-plan `payment_preferences` matrix in audit artifact.
- [ ] Diagnostic security rules followed (no secrets in shell args, no OAuth tokens printed, no raw customer rows).

---

## Common B35 mistakes

- **Auditing only that the API call succeeded.** "Stripe responded" ≠ "policy is in force." Compare to BUSINESS constants.
- **Sample audit treated as population proof.** A `limit=100` sample misses long-tail drift. Periodically run `--full-scan`.
- **Audit prints customer PII or tokens.** Counts-only is the rule.
- **Audit doesn't cover both endpoint config AND recent history.** A Dashboard-enabled event that hasn't fired yet is invisible to history; an event that fires from a different account is invisible to endpoint config.
- **Audit doesn't run in CI.** Manual quarterly audits miss daily drift.
- **Audit doesn't fail closed when redaction breaks.** A diagnostic that accidentally prints secrets is worse than no diagnostic.
- **No alert routing for drift.** Audit produces JSON nobody reads.
