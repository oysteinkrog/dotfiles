# Verification-First Protocol

Billing combines a lot of **evergreen method** with a lot of **volatile provider state**. The patterns change slowly. The provider does not — Stripe and PayPal evolve their APIs, event taxonomies, payment-method configurations, and Dashboard-controllable policies on a quarterly cadence. A single Dashboard click by a non-engineer can break an invariant the code thinks is in force.

This skill therefore behaves like the wills/tax skill: use the evergreen kernel from memory, but treat live provider state, current SDK shapes, and platform-controllable policies as **must-verify** items.

---

## Core Rule

**Do not give a live billing recommendation that depends on a volatile provider field, dashboard setting, SDK shape, or platform-controllable policy until it has been verified read-only against the live provider AND logged in `.billing_workspace/provider_audit_log.md`.**

Examples:

- ✅ **From memory:** "The webhook handler must return 200 once `recordWebhookEvent` succeeds."
- ❌ **Not from memory:** "Stripe currently sends `invoice.overdue` events for past_due subs after N days." (Catalog evolves; verify.)
- ✅ **From memory:** "PayPal `custom_id` is attacker-controllable; cross-check against stored payer_id."
- ❌ **Not from memory:** "PayPal Subscription `BILLING.SUBSCRIPTION.UPDATED` is currently active in the live webhook config." (Dashboard-mutable; verify.)

---

## Evergreen vs. Volatile

### Evergreen pattern knowledge (use from memory)

These are stable across SDK versions and Dashboard reorganizations; they're what this skill exists to teach.

- The 5-step webhook ingestion contract.
- Idempotency-key mechanics + DB-side dedup pattern.
- The 200-on-error principle.
- Stale-event ordering with `last_event_at`.
- Hijack defenses (PayPal `custom_id`, team `subscription_id` cross-check, Stripe Connect account check).
- Three-layer write paths + three-layer alarm paths.
- Intent-then-act for slow provider calls.
- Cron defenses (advisory locks, bounded scans, terminal-stuck digests).
- `paused_for_org` lifecycle; refund as terminal state; verify-as-write.
- Provenance envelopes; analytics exclusions; admin-event two-gate publishers.
- The Polish Bar dimensions.
- The operator library.

### Volatile provider state (must verify live)

These can drift between when the pattern was written and when you apply it. Verify against the live provider before finalizing.

| Item | Verify against | Frequency |
|------|----------------|-----------|
| Stripe API version (SDK + webhook endpoint + recent event distribution) | `stripe webhook_endpoints retrieve we_xxx` + `/v1/events` recent sample | Every audit + after any SDK upgrade |
| Stripe webhook endpoint `enabled_events` set | Stripe Dashboard webhook config / `webhook_endpoints retrieve` | Every audit |
| Stripe price IDs + product IDs + currency + amount + tax behavior | `prices.retrieve` for each `BUSINESS.STRIPE_PRICES` entry | Every audit |
| Stripe Customer Portal config (cancellation, prorations, plan updates, promo codes) | `billing_portal.configurations.list` | Every audit |
| Stripe Payment Method Configuration (which methods enabled per region) | `paymentMethodConfigurations.list` | Every audit |
| Stripe Payment Links (any active recurring links?) | `paymentLinks.list` then per-link `lineItems.list` | Every audit |
| Stripe coupons + promotion codes + subscription discounts | `coupons.list`, `promotionCodes.list`, sample `subscriptions.list` | Every audit + when policy changes |
| Stripe Adaptive Pricing (enabled? presentment_currency surfaces?) | Recent `checkout.sessions.list` sample `adaptive_pricing.enabled`, `presentment_details` | Every audit |
| PayPal plan details (active, monthly, USD, no trials, payment_failure_threshold, setup_fee_failure_action) | `/v1/billing/plans/{id}` per plan | Every audit |
| PayPal webhook subscription set | `/v1/notifications/webhooks/{id}` | Every audit |
| PayPal recent webhook event distribution | `/v1/notifications/webhooks-events` last N | Every audit |
| PayPal recent transactions (fee fields, currency mix, balance fields) | `/v1/reporting/transactions` last N | Quarterly |
| Vercel env scope (every billing secret production-only, sensitive-flagged, no NEXT_PUBLIC leaks) | `vercel env ls` + dashboard | Every audit + after team change |
| Supabase RLS policies on billing tables | `\\d+` per table + run as anon / authenticated / service_role | Every audit |

---

## Primary Source Hierarchy

Use sources in this order:

1. **Live read-only API call against the provider's production environment** with proper redaction (counts only; no customer PII; no tokens).
2. **Provider Dashboard** screenshots when an API for the surface doesn't exist.
3. **Official provider documentation** for the field/event/parameter being audited.
4. **Provider SDK type definitions** for shape questions.
5. **This skill's pattern library** for evergreen invariants.

Avoid relying on:

- Stale assistant memory of provider behavior.
- Third-party tutorials more than 12 months old.
- Internal playbooks more than 6 months old without re-verification.
- "I read this in the Stripe docs" without a current URL.

---

## Mandatory Verification Triggers

Verify live whenever the audit/implementation depends on:

1. **Stripe API version** — pin in `STRIPE_API_VERSION`; verify endpoint `api_version`; verify recent event distribution `event.api_version`.
2. **Stripe webhook subscribed-events set** — diff against `HANDLED_STRIPE_EVENTS` in code; both directions (subscribed-but-unhandled = dead code; handled-but-unsubscribed = unreachable branch).
3. **Stripe price + product configuration** — every `BUSINESS.STRIPE_PRICES` ID is active, live, monthly (or expected interval), correct currency, correct amount, correct `tax_behavior`.
4. **Stripe Customer Portal** — features (subscription_cancel, subscription_update, payment_method_update, customer_update), proration_behavior, login_page settings.
5. **Stripe Payment Method Configuration** — which methods are enabled (card, link, wallets, BNPL, bank debits, Stripe-hosted PayPal); matches BUSINESS policy.
6. **Stripe Payment Links** — count of active links; for each, line items; recurring links must satisfy the same checkout contract (idempotency, metadata, etc.) or be flagged.
7. **Stripe Adaptive Pricing** — `adaptive_pricing.enabled` on recent sessions; if true, audit `presentment_currency` in payment events, support copy, refunds.
8. **Stripe coupons / promotion codes / subscription discounts** — must match `BUSINESS.ALLOW_PROMO_CODES` policy. Zero active = strict no-discount. Otherwise allowlisted.
9. **PayPal plan details** — every plan in `BUSINESS.PAYPAL_PLANS` is `ACTIVE`, monthly, USD (or expected currency), no unexpected trial cycles, expected `payment_failure_threshold`, expected `setup_fee_failure_action`, expected `quantity_supported`.
10. **PayPal webhook subscription set** — diff against `HANDLED_PAYPAL_EVENTS` in code.
11. **PayPal recent webhook event distribution** — what events ACTUALLY arrived in the last 30 days; ensure the handler set matches.
12. **PayPal `payment_preferences`** per plan — `auto_bill_outstanding`, `setup_fee_failure_action`, `payment_failure_threshold`, `setup_fee` amount.
13. **Vercel env audit** — every billing-secret env var: production-only, sensitive-flagged, no `NEXT_PUBLIC_` exposure, key prefix matches mode (`sk_live_` in production, `sk_test_` in preview/dev).
14. **Supabase RLS policies** — every billing-relevant table has explicit `TO authenticated` / `TO anon` policies (not `using (true)` on billing-adjacent tables); verified by running queries as anon, user-A, user-B, org-admin, service_role.
15. **Cron schedule** — `vercel.json` (or equivalent) matches the documented cadence; auth header configured.

---

## The Evidence Envelope

Every verification produces an artifact in `.billing_workspace/provider_audit_log.md`:

```markdown
## Verification: <name>
- checked_at: 2026-05-04T23:41:37Z
- environment: production
- scope: read_only_provider_diagnostics
- redaction: counts_only_no_customer_rows_no_tokens_no_urls
- provider: stripe
- finding:
  - <whatever the structured finding was — count by status, presence, etc.>
- comparison:
  - expected (per BUSINESS / pattern): <value>
  - actual (live provider): <value>
  - delta: ✓ match | ✗ drift (severity: <high|medium|low>)
- next_action: <if delta, file as Phase 4 task; else continue>
```

The artifact is the audit. If it's not in `.billing_workspace/provider_audit_log.md`, the verification didn't happen.

---

## Diagnostic Discipline (security rules)

These rules apply EVERY TIME a verification runs. Violations are P1 incidents.

1. **Do NOT inspect secrets by printing them.** Never `cat`, `rg`, `grep`, `echo` `.env.local`, or `vercel env pull` output in a shared transcript. Print only:
   - Env var names (not values).
   - Key prefixes (`sk_live_*` → "live mode") with the rest redacted.
   - Boolean presence (`STRIPE_SECRET_KEY: present` not the value).

2. **Do NOT put secrets in shell arguments.** `curl -u client:secret`, `stripe ... --api-key sk_live_...`, copied OAuth tokens — all leak through shell history, process listings, terminal scrollback, agent transcripts.
   - Prefer SDK calls or short-lived processes that build Authorization headers from `process.env` internally.
   - Never `echo` an OAuth token to test it.

3. **Never print OAuth tokens, webhook signatures, or session URLs.**
   - For PayPal: mint OAuth token inside the diagnostic process, reuse for that run, discard.
   - For Stripe: use the existing SDK client; do not dump `Stripe-Signature`, `whsec_`, Checkout URLs, Customer Portal URLs, session URLs.

4. **Redact IDs unless the ID is the finding.** Counts and key sets are usually enough. If an incident requires a specific provider ID, store in a restricted incident artifact.

5. **Collect error metadata WITHOUT payloads.** Stripe errors include a `request_id` and request-log URL; PayPal responses include `PayPal-Debug-Id`. Store those + HTTP status + error category + endpoint + timestamp. Do NOT store the full request/response body unless it's gone through PII review.

6. **Counts-only by default.** A diagnostic run produces counts, key sets, boolean presence, small enumerations. Raw Checkout Sessions, webhook events, transactions, payer records, customer objects → forbidden in logs / PR comments / chat transcripts.

7. **Sample vs. full-scan must be labeled.** A `limit=100` recent-sample finding is NOT a population proof. Label the artifact with `sample_size: 100` or `full_scan: true (paginated)`.

---

## When verification fails

If the live provider state contradicts the pattern / BUSINESS constants:

| Severity | Example | Response |
|----------|---------|----------|
| Critical | Live `sk_live_*` key in Preview env; coupon active that should not exist; PayPal trial cycle on a "no-trials" plan | Block the deployment / fix immediately / file P0 incident |
| High | Webhook subscribed event not handled in code (and is entitlement-affecting) | File as Phase 4 task; deploy gate |
| Medium | Recent event distribution shows a new `event.api_version` not seen before | Investigate; may be Stripe rolling out new API version |
| Low | Customer Portal cancellation_reason copy differs from app copy | File for next Phase 4 round |

When in doubt: **do not finalize the recommendation**. Surface to the user.

---

## Verification cadence by mode

- **`audit-only` / `audit-and-fix`** — full verification at Phase 1; spot-checks after Phase 5.
- **`add-feature`** — verify only the surfaces the feature touches.
- **`greenfield`** — verify after Day 11 (operational discipline) and Day 12 (final pass).
- **`migration`** — full verification both old and new providers before cutover; daily during dual-run window.
- **`compliance-pass`** — full verification + evidence pack; verify is the deliverable.
- **`harden-incident`** — verify only the incident's blast radius; full verification at the end of `audit-and-fix`.

---

## Verification artifacts that go in the evidence pack

For `compliance-pass` mode, the verification log feeds `phase10_evidence_pack/`:

- `evidence/01_stripe_account_state.md` — account ID, key mode, charges_enabled, payouts_enabled.
- `evidence/02_stripe_webhook_coverage.md` — bidirectional matrix + decisions.
- `evidence/03_stripe_price_audit.md` — every price ID + audit fields.
- `evidence/04_stripe_portal_config.md` — full portal config per environment.
- `evidence/05_stripe_payment_methods.md` — Payment Method Configurations.
- `evidence/06_stripe_payment_links.md` — every active link + line items.
- `evidence/07_stripe_discounts.md` — coupons, promo codes, sub discounts.
- `evidence/08_paypal_plans.md` — every plan + payment_preferences.
- `evidence/09_paypal_webhook_coverage.md` — bidirectional matrix.
- `evidence/10_paypal_recent_history.md` — webhook + transaction distribution.
- `evidence/11_vercel_env_audit.md` — env scope + sensitive flag matrix.
- `evidence/12_supabase_rls_audit.md` — per-table policy + per-role probe.
- `evidence/13_secret_custody.md` — rotation log + custody.

Each file is a `.md` with the evidence envelope per finding.
