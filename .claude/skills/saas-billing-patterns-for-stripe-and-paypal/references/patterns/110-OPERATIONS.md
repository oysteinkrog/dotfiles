# Bundle B110 — Operations

> **Where this comes from.** § 65–§ 78, § 78a, Appendices A + B of the source guide.

This is the cross-cutting bundle that covers error taxonomy, migration discipline, integration testing, drift guards, the cron schedule, runbooks, the failure catalog, the rejected-patterns list, key custody, and, critically, the **greenfield step-ordered checklist** that orders the dependency chain for new builds.

This bundle is mostly used in Phase 10 (ops handoff) and `greenfield`/`compliance-pass` modes.

---

## The `PaymentError` taxonomy — § 66

```ts
// src/lib/payment/payment-error.ts
import { PaymentErrorCodes, type PaymentErrorCode } from '@/lib/constants/payment-error-codes';

export class PaymentError extends Error {
  readonly code: PaymentErrorCode;
  readonly metadata: Record<string, unknown>;
  readonly cause?: Error;

  constructor(code: PaymentErrorCode, message: string, metadata: Record<string, unknown> = {}, cause?: Error) {
    super(message);
    this.name = 'PaymentError';
    this.code = code;
    this.metadata = metadata;
    this.cause = cause;
  }

  static fromStripeError(err: Stripe.errors.StripeError): PaymentError {
    const map: Record<string, PaymentErrorCode> = {
      'card_declined': PaymentErrorCodes.CARD_DECLINED,
      'authentication_required': PaymentErrorCodes.AUTHENTICATION_REQUIRED,
      'insufficient_funds': PaymentErrorCodes.INSUFFICIENT_FUNDS,
      // ... etc
    };
    return new PaymentError(
      map[err.code ?? ''] ?? PaymentErrorCodes.UNKNOWN,
      err.message,
      { stripe_request_id: err.requestId, stripe_code: err.code, stripe_decline_code: err.decline_code },
      err,
    );
  }
}
```

Every catch block that handles a payment failure produces a `PaymentError` with a registered code. Dashboards / runbooks / dunning emails all key on `code`.

---

## `PendingCheckoutSessionId` UNIQUE migration (BILLING-L2) — § 67

Already shown in B10 / B30. The B110 angle is *migration safety* — adding a UNIQUE constraint on a populated column requires either a clean dataset or a forward-fix:

```sql
-- Migration 1: ensure no duplicates exist (run as a query first)
SELECT pending_checkout_session_id, count(*) FROM users
WHERE pending_checkout_session_id IS NOT NULL
GROUP BY pending_checkout_session_id HAVING count(*) > 1;
-- If non-empty: clean up before applying constraint

-- Migration 2: apply the partial UNIQUE
CREATE UNIQUE INDEX users_pending_checkout_session_idx
  ON users (pending_checkout_session_id)
  WHERE pending_checkout_session_id IS NOT NULL;
```

If you skip migration 1, migration 2 fails — and Postgres holds an ACCESS EXCLUSIVE lock for the duration of the failed CREATE, blocking writes.

---

## Drizzle migration discipline — § 68

(Adapt to your ORM; the principles are universal.)

1. **One thing per migration.** Don't mix schema + data + index changes.
2. **Backfill in a separate migration.** Add column NULL → backfill → add NOT NULL.
3. **Always read generated SQL.** Drizzle / Prisma generators sometimes do "drop and recreate" on enums; data loss.
4. **Stage in a Supabase / Neon branch first.** Always.
5. **Reversible by default.** Every migration has a documented rollback even if you don't expect to use it.
6. **Update `schema.ts` in the same commit.** Failure mode #4 of source: "A migration that doesn't update schema.ts" → runtime errors.
7. **Migration name encodes intent.** `20260423000700_individual_subscription_intents.sql` not `20260423000700_v2.sql`.

---

## Real-DB integration tests (no mocks for billing) — § 69

The hard rule: **mock-free billing tests**.

```ts
// __tests__/billing/webhook-replay.test.ts
import { setupTestDb, teardownTestDb } from './setup';
import { simulateStripeWebhook } from './helpers/stripe-webhook';

describe('webhook replay (bd-1zzos)', () => {
  let db;
  beforeEach(async () => { db = await setupTestDb(); });
  afterEach(async () => { await teardownTestDb(); });

  test('returns 200 + skipped_idempotent on second arrival', async () => {
    const event = stripeFixtureEvent('customer.subscription.updated');
    const r1 = await simulateStripeWebhook(event);
    expect(r1.status).toBe(200);
    expect(r1.body.outcome).toBe('processed');

    const r2 = await simulateStripeWebhook(event);
    expect(r2.status).toBe(200);
    expect(r2.body.outcome).toBe('skipped_idempotent');

    // Real DB confirms only one row in payment_events
    const rows = await db.query.paymentEvents.findMany({ where: eq(paymentEvents.eventId, event.id) });
    expect(rows.length).toBe(1);
  });
});
```

`setupTestDb` spins up a real Postgres branch (Supabase test DB / Neon dev branch / local Docker). `simulateStripeWebhook` POSTs the actual JSON to the actual route handler with a real signature.

### Why no mocks

Mocked tests pass while production fails. § 78 failure-mode #4 ("A migration that doesn't update schema.ts") is undetectable in mocks because the mock has the right column. § 78 failure-mode #2 ("WHERE clause that drops the subscription_id cross-check") is undetectable in mocks because the mock returns the row regardless. Real DB catches these.

### Test isolation

- Each test uses a fresh schema (or transaction-rollback isolation).
- Tests run sequentially (`--test-threads=1`) when they share state.
- Fixture data is loaded from per-test JSON files, not generated inline.

---

## Drift-guard tests for analytics exclusions — § 70

The most-broken pattern in any growing codebase: a new cron is added but doesn't import the canonical exclusions module. Then one day the cron emails real customers about test signups.

```ts
// __tests__/billing/drift-guard.test.ts
test('every billing cron imports analytics/exclusions', () => {
  const cronFiles = globSync('src/app/api/cron/**/route.ts');
  const cronsThatMustExclude = [
    'src/app/api/cron/dunning-reminders/route.ts',
    'src/app/api/cron/card-expiry-warning/route.ts',
    'src/app/api/cron/upcoming-renewal-notification/route.ts',
    'src/app/api/cron/billing-integrity-audit/route.ts',
    'src/app/api/cron/email-queue/route.ts',
    // ... every cron that reads users/subs
  ];
  // Assertion 1: every must-exclude cron actually exists
  for (const c of cronsThatMustExclude) {
    expect(existsSync(c), `cron file missing: ${c}`).toBe(true);
  }
  // Assertion 2: every must-exclude cron imports exclusions
  for (const c of cronsThatMustExclude) {
    const content = readFileSync(c, 'utf-8');
    expect(content, `${c} does not import analytics/exclusions`).toMatch(/from ['"][^'"]*analytics\/exclusions['"]/);
  }
  // Assertion 3: every cron in the directory is either in must-exclude or explicitly opted-out via a doc-comment
  const allCronFiles = globSync('src/app/api/cron/**/route.ts');
  for (const c of allCronFiles) {
    if (cronsThatMustExclude.includes(c)) continue;
    const content = readFileSync(c, 'utf-8');
    expect(content, `cron ${c} is not in cronsThatMustExclude AND has no opt-out comment`).toMatch(/\/\/ analytics-exclusions: not-required/);
  }
});
```

Other drift-guards to write:

- `WebhookErrorCodes-completeness` — every code emitted in handlers is in the registry.
- `BillingEnv-completeness` — every env var the billing system reads is in `env.ts`.
- `StripeApiVersion-singleSource` — only one place has the API version literal.
- `LastEventAtCoverage` — every UPDATE on subscriptions/orgs has the WHERE clause.
- `PaymentEventsPayloadIsJsonb` — schema asserts payload column type.

---

## The full Vercel cron schedule — § 71

```json
// vercel.json
{
  "crons": [
    { "path": "/api/cron/webhook-reconciliation", "schedule": "*/5 * * * *" },
    { "path": "/api/cron/webhook-staleness", "schedule": "*/5 * * * *" },
    { "path": "/api/cron/email-queue", "schedule": "* * * * *" },
    { "path": "/api/cron/dunning-reminders", "schedule": "0 9 * * *" },
    { "path": "/api/cron/card-expiry-warning", "schedule": "0 10 * * *" },
    { "path": "/api/cron/upcoming-renewal-notification", "schedule": "0 11 * * *" },
    { "path": "/api/cron/retry-orphan-sub-cancels", "schedule": "*/15 * * * *" },
    { "path": "/api/cron/retry-individual-sub-cancels", "schedule": "*/15 * * * *" },
    { "path": "/api/cron/provider-reconciliation", "schedule": "0 */6 * * *" },
    { "path": "/api/cron/billing-integrity-audit", "schedule": "0 8 * * *" },
    { "path": "/api/cron/subscription-projection-reconciliation", "schedule": "0 */2 * * *" }
  ]
}
```

Plus `vercel.json` headers stanza requires `Authorization: Bearer $CRON_SECRET` for every cron route.

For non-Vercel hosts, see PROJECT-TYPES.md § Cron host adjustments.

---

## Failure-mode catalog (38 incidents) — § 72

The condensed table from the source guide, retitled for use during Phase 3 risk-scoring.

| Failure | Root cause | Fix | Caught by |
|---------|-----------|-----|-----------|
| Triple-charge | Webhook 3h late + DB-only checkout guard | Cross-provider probe + customer reuse + idempotency bucket + integrity audit | Customer ticket |
| PayPal team hijack | Trusted `custom_id` UUID without cross-check | `subscription_id` in WHERE clause | Code review (SA-01) |
| PayPal individual hijack | Trusted `custom_id` without payer_id check | `validatePayPalUserId` | Code review (`bd-2gxws`) |
| Stripe checkout `%7B` encoding | `URL.toString()` percent-encoded `{` | Template literal | Customer (Rahim) |
| Pause/resume pool exhaustion | Stripe API call inside DB tx | Intent table + post-tx Stripe call | Load test |
| Refund alert lost | Resend down + log-only signal | Failsafe sweep + OPS_FAILSAFE_EMAIL | Manual ops audit |
| Newsletter delayed refund alert | FIFO queue, no priority | `email_jobs.priority` | Customer support timing |
| GDPR delete left ghost sub | Insert orphan AFTER user delete | Insert orphan INSIDE delete tx | Customer ticket |
| Cancelled team revived | Reconcile branch missing `cancelled` guard | `!== "cancelled"` in if + SQL | Security audit (SA-03) |
| Stripe replay revived stale | Late webhook overwrote new state | `last_event_at` ordering check | Security audit |
| PayPal partial refund stripped | `sale.state` hint, not truth | Fetch parent payment | Customer support |
| Stripe `incomplete` checkout incorrectly active | `mapStripeStatus` fallthrough | Block `incomplete` at checkout entry + mapping | Multi-agent review |
| Webhook-reconciliation overlap | No advisory lock | `pg_try_advisory_lock` per cron | Production log noise |
| Per-row dunning email cycle bug | Dedup keyed on queued, not delivered | `wasEmailDeliveredSince` checks `status='sent'` AND `sent_at` | Customer ticket |
| Card-expiry off-by-one | Days rounded DOWN | Round UP | Test fixture catch |
| Refund webhook with no sub_id stripped 2 subs | Unscoped revoke | Throw on ambiguity, retry from cron | Incident drill |
| Revenue tile showed stale 0 during outage | Cache returned stale on fail | `provenance: "unavailable"` propagation | Code review |
| Synthetic fixtures spamming alerts | No exclusions in cron | Canonical exclusions module + drift-guard | Repeated incidents |

(See source guide § 72 for the remaining 20.)

---

## Patterns tried and rejected — § 73

| ✗ | Why it failed |
|---|---------------|
| Returning 500 from webhooks on processing error | 3-day Stripe retries with partial-success duplicates |
| Auto-refund on duplicate detection | Real customers occasionally have legit duplicates; relationship damage |
| Ad-hoc `sendEmail()` for billing alerts | Resend outage = lost alerts |
| Polluting `abuse_detected` for system alerts | Dashboards lie |
| One-shared `maybeFireTerminalStuckDigest` across crons | Different schemas; god-function risk |
| Storing partial event payloads | Future handler changes need re-fetch / backfill |
| Trusting `subscription.metadata.user_id` as authoritative | Attacker-controllable |
| Single retry counter shared across event types | High-failure-rate event maxes the counter for whole class |
| Hand-rolled compatibility shims for old webhook versions | Per AGENTS.md no shims; replaced with single resolver |
| Building MRR from a SQL view that joins live tables | Kills cache invalidation semantics |

---

## ADR system for billing decisions — `docs/adr/billing/`

Architecture Decision Records (ADRs) are the durable record of *why* a billing pattern was chosen. They live in version control next to the code, are numbered for stable referencing, and answer the "we tried X, why did we settle on Y" question that the failure-mode catalog can't.

The reason ADRs matter specifically for billing: alert thresholds, SLO targets, retry caps, grace-period lengths, and reconciliation cadences all encode *judgment calls*. Six months later, when a new engineer asks "why is the grace period 21 days and not 30?", the answer needs to be one click away from the code, not buried in a Slack thread.

### Folder layout

```
docs/adr/billing/
├── README.md                                    # index + how to write a new ADR
├── 0000-template.md                             # the template every new ADR copies
├── 0001-verify-as-write-strategy.md
├── 0002-reconciliation-tier-strategy.md
├── 0003-webhook-canonical-id.md
├── 0004-feature-flag-via-intelligence-flags.md
├── 0005-append-only-subscriptions.md
├── 0006-welcome-email-templates.md
├── 0007-rate-limit-and-botid-defense.md
├── 0008-cassette-replay-testing.md
├── 0009-payload-integrity-validator.md
└── 0010-slo-targets.md
```

### The template

```markdown
# ADR-NNNN: <title>

## Status
<Proposed | Accepted | Deprecated | Superseded by ADR-MMMM>

## Context
What problem does this decision solve? What constraints apply?
Reference the bead/incident/feature request that motivated it.

## Decision
The chosen approach, in 1-3 paragraphs.

## Consequences
Pro:
- ...

Con:
- ...

Neutral:
- ...

## Alternatives considered
What other approaches we looked at and why we rejected them.

## Related
- ADRs that this supersedes / is superseded by
- Beads / incidents that drove this
- Code paths most affected
```

### The 10 load-bearing ADRs (mirroring jeffreys-skills.md)

The codebase has ten numbered ADRs (plus the `0000-template.md` and `README.md`) that every new engineer should be able to reference by number:

| # | Title | What it pins |
|---|-------|--------------|
| 0001 | Verify-as-write strategy | The verify endpoint can write subscription state when webhook hasn't landed; webhook is backup. (B40) |
| 0002 | Reconciliation tier strategy | Three reconciliation tiers (per-event, per-sub provider, daily integrity audit). (B90) |
| 0003 | Webhook canonical id | The (provider, event_id) pair is the dedup key — never derived from payload. (B40) |
| 0004 | Feature flag via intelligence flags | Billing rollouts gated via the `intelligence_flags` table, NOT env vars. |
| 0005 | Append-only subscriptions | `subscriptions` rows are append-only; we never DELETE. The `none` status is the absorbing state. (B10) |
| 0006 | Welcome email templates | Templates live in code, not the DB. (B70) |
| 0007 | Rate limit and BotID defense | Stripe Radar + per-user/IP rate limiter; FAIL_CLOSED endpoints listed. (B50) |
| 0008 | Cassette replay testing | Tests use recorded Stripe API cassettes for CI; replay-only in CI to avoid external dependency. (B65) |
| 0009 | Payload integrity validator | `validatePaymentEventIntegrity` is mandatory for activation; never trust event contents on signature alone. (B40) |
| 0010 | SLO targets P0–P5 | The numerical targets the `slo-snapshot` cron measures against. (B55) |

### When to write a new ADR

Write one when you make a billing decision that:

- **Encodes a judgment call** (a number, a threshold, a cadence) that future-you will second-guess.
- **Rejects a tempting alternative** (e.g., "we considered using Stripe's Smart Retries solely; here's why we layer our own retry on top").
- **Sets a contract** that other code depends on (e.g., "the `<=` in the stale-event guard is load-bearing — change requires ADR amendment").
- **Documents an incident response** that became permanent (e.g., "after bd-08xvg.1 we added Layer 4; here's why we kept it forever").

### When to amend instead of supersede

If the underlying decision is stable but the *numbers* shifted (e.g., grace period bumped from 21 to 28 days), amend the existing ADR with a "Revision history" section. Supersede only when the *strategy* changed (e.g., abandoning verify-as-write for a webhook-only approach).

### Linking ADRs from code

Reference ADRs by number in code comments where the decision lives:

```ts
// SLO targets pinned in ADR-0010 (docs/adr/billing/0010-slo-targets.md)
const SLO_TARGETS = {
  P1_p50_seconds: 2,
  P1_p95_seconds: 30,
  P1_p99_seconds: 300,
} as const;
```

The link is one click from the source for any reader; reviewers in PRs see the ADR reference and know to read it before approving a change to the constant.

**Reference:** jeffreys-skills.md `docs/adr/billing/` (10 numbered ADRs + `0000-template.md` + `README.md`).

---

## Operational runbooks — § 74

Every cron, every alarm, every metric needs a runbook in `<project>/docs/runbooks/`. The Phase 10 subagent (`runbook-writer.md`) writes these. Mandatory runbooks:

- `webhook-staleness-alarm.md`
- `paypal-hijack-attempt.md`
- `triple-charge-incident.md`
- `mrr-snapshot-unavailable.md`
- `email-failsafe-alert.md`
- `cron-lock-stuck.md`
- `provider-outage.md`
- `secret-rotation.md`
- `manual-invoice-retry.md`
- `dispute-handling.md`
- `customer-deletion-with-active-sub.md`
- `subscription-projection-drift.md`

Format: see [AGENT-PROMPTS.md § Phase 10 — Runbook writer](../methodology/AGENT-PROMPTS.md#phase-10--runbook-writer).

---

## Bead dictionary — Appendix B

The traceability layer: every fix maps to a bead/incident name. Use the bead ID in commit messages, test names, and runbook references.

Top-level beads referenced throughout this skill (carried from source guide):

| Bead | Title |
|------|-------|
| `bd-yqo1` | EPIC: Payment Integration (Stripe + PayPal) |
| `bd-14kyb` | EPIC: PayPal Payment Integration Fix & Reliability |
| `bd-1m86f` | P0 Triple-charge incident (Tom Hunter) |
| `bd-1ug5i` | Marco Fanti silent webhook loss |
| `bd-08xvg.1` | SA-01 PayPal team webhook subscription hijack |
| `bd-08xvg.3` | SA-03 Exclude cancelled orgs from reconcile revival |
| `bd-2gxws` | PayPal individual webhook custom_id hijack |
| `bd-1zzos` | Stripe webhook 200-on-error to stop retry storms |
| `bd-yu9g9` | Billing-H4 hold pause/resume Stripe writes outside tx |
| `bd-hbfat` | Billing-H2 fetch parent payment for partial refund |
| `bd-ja8c0` | Billing-H1 out-of-band escalation when email queue fails |
| `bd-bfwcy.3` | BILLING-M1 dedicated compliance event for system alerts |
| `bd-bfwcy.4` | BILLING-M2 stale-checkout race guard |
| `bd-bfwcy.5` | BILLING-M3 priority queue for email_jobs |
| `bd-bfwcy.6` | BILLING-M5 orphan-cancel rows inside delete tx |
| `bd-lp3vu` | Bullet-proof billing flows |
| `bd-vifc1` | Centralize STRIPE_API_VERSION |
| `bd-mhox6.2.2.2` | MOR-22B reconciliation freshness telemetry |

Your project's beads will have different IDs; the principle is the trace.

---

## Secret custody matrix — § 78a.6b

The `.billing_workspace/phase10_secret_custody.md` template:

```markdown
# Secret Custody Matrix

| Secret | Used by | Storage | Sensitive flag | Production-only? | Rotation cadence | Last rotated | Custody (who can read/rotate) |
|--------|---------|---------|----------------|------------------|------------------|--------------|-------------------------------|
| STRIPE_SECRET_KEY | webhook + checkout + admin | Vercel env | ✓ | ✓ | quarterly | 2026-04-15 | engineering-leads |
| STRIPE_WEBHOOK_SECRET | webhook handler | Vercel env | ✓ | ✓ | annual + on-demand | 2026-01-12 | engineering-leads |
| STRIPE_PUBLISHABLE_KEY | client (NEXT_PUBLIC) | Vercel env | — | ✓ | n/a (public) | n/a | n/a |
| PAYPAL_CLIENT_ID | server | Vercel env | ✓ | ✓ | annual | 2026-02-08 | engineering-leads |
| PAYPAL_CLIENT_SECRET | server | Vercel env | ✓ | ✓ | annual | 2026-02-08 | engineering-leads |
| PAYPAL_WEBHOOK_ID | webhook handler | Vercel env | ✓ | ✓ | annual | 2026-02-08 | engineering-leads |
| SUPABASE_SERVICE_ROLE_KEY | webhook + cron | Vercel env | ✓ | ✓ | annual | 2026-03-01 | engineering-leads |
| CRON_SECRET | cron auth | Vercel env | ✓ | ✓ | quarterly | 2026-04-15 | engineering-leads |
| RESEND_API_KEY | email queue | Vercel env | ✓ | ✓ | annual | 2026-01-30 | engineering-leads |
| OPS_FAILSAFE_EMAIL_RESEND_KEY | failsafe send | Vercel env (separate Resend acct) | ✓ | ✓ | annual | 2026-01-30 | engineering-leads |

## Rotation procedure (each secret)
1. Generate new value via provider Dashboard.
2. Update Vercel env (Production scope only).
3. Trigger redeploy.
4. Verify webhook still receives events (Stripe Dashboard "Test webhook" button).
5. Update this file's `Last rotated` cell.
6. After 24h-confirmation, revoke old value.

## Compromise procedure (if any secret leaks)
1. Rotate immediately (skip cadence).
2. Audit logs for unauthorized use during exposure window.
3. Notify engineering-leads + on-call.
4. Update `compliance_events` with `secret_rotated` event.
```

---

## Battle-tested checklist — bringing this to a new SaaS — § 77 (THE STEP-ORDERED BUILD)

This is the entry point for `greenfield` mode. Each item maps to the bundle that explains it. **Order is not optional** — many later Steps literally won't compile or work without earlier Steps.

### Step 1 — single-source constants and minimal contracts (B10 + B20)
- [ ] `BUSINESS` constants (pricing, team tiers, subscription)
- [ ] `STRIPE_API_VERSION` + `getStripeClient()` (type-derived, lazy)
- [ ] `WebhookErrorCodes` + `PaymentErrorCode` registries
- [ ] `ROUTES` constant
- [ ] `env.ts` with Zod prefix-validation + production refines
- [ ] Drizzle/Prisma/etc. schema with `subscription_status` enum, `subscription_provider` enum
- [ ] `payment_events` table with UNIQUE (provider, event_id)
- [ ] `subscriptions` table with `last_event_at` from the start

### Step 2 — webhook ingestion (5-stage contract for both providers) (B40)
- [ ] Stripe handler with signature verification + 200-on-error
- [ ] PayPal handler with API-side verification
- [ ] Bidirectional provider-event coverage audit: subscribed vs handled
- [ ] `recordWebhookEvent()` — INSERT-on-conflict 23505 dedup
- [ ] `markEventProcessed()`
- [ ] `updateSubscriptionStatus()` — single canonical writer
- [ ] `revokeAccessOnRefund()` — strict path
- [ ] All UPDATEs include `WHERE last_event_at < new_event_at`

### Step 3 — checkout (B30)
- [ ] `pendingCheckoutSessionId` columns + UNIQUE index
- [ ] `FOR UPDATE` checkout transaction
- [ ] Template-literal `success_url` + lint rule
- [ ] Checkout payload contract for explicit trial/discount/deal policy
- [ ] `customers.list({email})` reuse for Stripe
- [ ] User-hour-bucketed Stripe `Idempotency-Key`
- [ ] Subject-opaque PayPal-Request-Id
- [ ] Cross-provider probe in checkout

### Step 4 — security (B50)
- [ ] `validatePayPalUserId()`
- [ ] `subscription_id` cross-check on every team-org UPDATE
- [ ] `last_event_at` replay-staleness guard
- [ ] Reconcile cancelled-orgs guard
- [ ] `FAIL_CLOSED_ENDPOINTS` for billing + auth + webhooks
- [ ] Synchronous cache invalidation on refund with 2s timeout
- [ ] `logSecurityEvent` taxonomy
- [ ] `.env*` ignored except templates/examples; no secrets in git
- [ ] Supabase RLS policies and app-layer filters verified

### Step 5 — reliability machinery (B90)
- [ ] Webhook reconciliation cron + per-event claim lease
- [ ] Webhook-staleness alarm
- [ ] Email queue with priority column
- [ ] OPS_FAILSAFE_EMAIL escalation
- [ ] Daily integrity audit
- [ ] Provider-authoritative reconciliation sweep every 6h

### Step 6 — dunning + grace (B70 + B60)
- [ ] `GRACE_PERIOD_DAYS = 21` Edge-compatible module
- [ ] `DUNNING_STAGES = { 0, 7, 14, 21 }` individual ladder
- [ ] `TEAM_DUNNING_STAGES = { 0, 3, 7, 30 }` compressed team ladder
- [ ] `wasEmailDeliveredSince` cycle-aware dedup
- [ ] Manual invoice retry with 4-guard overcharge defense
- [ ] SCA / 3-D Secure routing
- [ ] Team coverage suppression in dunning

### Step 7 — orphan-cancel queues (B80 + B90)
- [ ] `orphan_subscription_cancels` table
- [ ] `organizations.pending_individual_sub_cancel_*` columns
- [ ] Both retry crons with bounded retries + terminal digest
- [ ] Persist orphan rows INSIDE delete tx

### Step 8 — pause/resume (B80)
- [ ] `paused_for_org` enum value
- [ ] `individual_subscription_intents` table
- [ ] Intent-then-act helpers (`recordPauseIntent`, `markIntentApplied`)
- [ ] FF_INDIVIDUAL_SUB_INTENTS_ENABLED feature flag

### Step 9 — proactive emails (B70)
- [ ] Card-expiry pre-warning cron + service
- [ ] Upcoming-renewal pre-charge cron + service
- [ ] In-app past-due banner with one-click portal
- [ ] Customer Portal deep-link helper

### Step 10 — reporting backend (B100)
- [ ] MRR snapshot with cache + provenance
- [ ] Single-flight cache wrapper
- [ ] Canonical churn timestamp + replacement-coverage exclusion
- [ ] Payment fees blended rate
- [ ] Settlement ledger ingestion from Stripe Balance Transactions and PayPal Transaction Search
- [ ] Stripe invoice-level recovery ledger keyed by invoice ID
- [ ] Customer health composite scoring
- [ ] Behavioral forecasting + intervention engine
- [ ] Monte Carlo runway projection
- [ ] Reconciliation freshness telemetry

### Step 11 — operational discipline (B110)
- [ ] `analytics/exclusions.ts` with composite SQL helpers
- [ ] Drift-guard test pinning every cron's exclusion imports
- [ ] Secret inventory and custody matrix
- [ ] Vercel env audit proving live billing secrets are production-scoped, sensitive, absent from Preview/Development
- [ ] Vault or equivalent secret-manager plan
- [ ] Read-only provider catalog audit (Stripe prices, PayPal plans, webhook endpoint events)
- [ ] Trial/discount/deal provider audit
- [ ] Stripe payment-method configuration audit
- [ ] Stripe Payment Links audit
- [ ] Provider API diagnostics command
- [ ] Stripe Customer Portal policy audit
- [ ] Per-plan PayPal payment-preferences matrix
- [ ] Real-DB integration tests for billing
- [ ] PayPal hijack runbook
- [ ] Three-status alarm channels: per-event + stale-pipeline + email failsafe

### Step 12 — final pass
- [ ] Walk through every state transition and pin a unit test
- [ ] Audit every `try/catch` in webhook handlers — ensure 200 return
- [ ] Audit every cron — advisory lock + bounded scan + dry-run
- [ ] Audit every UPDATE on `subscriptions` — `last_event_at` guard
- [ ] Audit every UPDATE on team-org table — `subscription_id` cross-check
- [ ] Audit every read in admin dashboard — analytics-exclusion clause
- [ ] Audit every email queue insert — priority inferred or set explicitly
- [ ] Audit every cache write — provenance check (don't cache fallback)

When all 12 Steps are checked off, you have the equivalent of what the source guide's project shipped.

---

## The 9 most common ways this still goes wrong in production — § 78

After all the defenses, these are the failure modes that survive. Monitor for them in week 1 of production.

1. **A cron missing from the analytics-exclusions drift guard.** Detection: customer ticket within 24h.
2. **A WHERE clause on `organizations` that drops `subscription_id` cross-check.** Same hijack class as `bd-08xvg.1`.
3. **A new post-ingest `try/catch` in a webhook handler that doesn't return 200.** Provider retries trigger storm.
4. **A migration that doesn't update `schema.ts`.** Drizzle queries fail at runtime.
5. **A cache read that doesn't check `provenance`.** Renders stale or misleading number.
6. **A new admin event publisher that bypasses analytics-exclusion.** Activity feed shows test signups.
7. **A Stripe SDK upgrade that subtly changes a field shape.** Use real-DB integration tests; pin `STRIPE_API_VERSION`.
8. **An advisory lock used in a cron that doesn't `release()` the reserved connection.** Pool exhaustion.
9. **A new email type that doesn't get the right priority.** Newsletter delays a refund alert.

The pattern: failures that survive defense are at the BOUNDARIES between systems (cron + DB, schema + code, cache + render). Code review that walks the boundaries catches most of them.

---

## File map (cited throughout this skill)

| Path | What it owns |
|------|-------------|
| `src/app/api/stripe/webhook/handler.ts` | Stripe webhook contract + per-event handlers |
| `src/app/api/paypal/webhook/route.ts` | PayPal webhook contract + per-event handlers |
| `src/app/api/stripe/create-checkout/route.ts` | Stripe checkout entry + cross-provider guards |
| `src/app/api/teams/paypal-checkout/route.ts` | PayPal team checkout entry |
| `src/lib/webhooks/inbound.ts` | `recordWebhookEvent`, `markEventProcessed`, `updateSubscriptionStatus`, `revokeAccessOnRefund` |
| `src/lib/webhooks/reconcile.ts` | Webhook reconciliation core (per-event claim, retry, alert) |
| `src/lib/services/subscription.ts` | `pickBestSubscription`, `deriveAggregateBillingProjection`, grace logic |
| `src/lib/services/dunning.ts` | Dunning ladder, email queue, SCA routing |
| `src/lib/services/team-billing.ts` | Team plans, pause/resume, seat counting |
| `src/lib/services/individual-sub-intents.ts` | Pause/resume intent table operations |
| `src/lib/services/stale-checkout.ts` | `detectStaleCheckoutRace`, `queueStaleCheckoutAlert` |
| `src/lib/services/grace-period.ts` | Edge-compatible grace period predicate |
| `src/lib/services/financial-projections.ts` | MRR snapshot cache, fees, projections |
| `src/lib/services/payment-fees.ts` | Stripe + PayPal fee modeling |
| `src/lib/billing/provider-reconcile.ts` | Provider-authoritative full sweep |
| `src/lib/billing/probe-stripe-individual.ts` / `probe-stripe-team.ts` | Cross-customer Stripe probes |
| `src/lib/paypal/client.ts` | PayPal OAuth2 client + `getPayPalParentPayment` |
| `src/lib/paypal/validation.ts` | `validatePayPalUserId`, `resolvePayPalSubscriptionOwner` |
| `src/lib/paypal/idempotency.ts` | `buildPayPalCreateSubscriptionRequestId` |
| `src/lib/payment/stripe-utils.ts` | `mapStripeStatus`, `getSubscriptionPeriod`, `getInvoiceSubscriptionId` |
| `src/lib/payment/stripe-invoice-retry.ts` | `retryLatestStripeInvoice` with 4-guard overcharge defense |
| `src/lib/payment/stripe-card-expiry.ts` | Default-card inspection helper |
| `src/lib/payment/stripe-portal-session.ts` | Customer Portal deep-link minting |
| `src/lib/email/retry.ts` | `createEmailJob`, `inferEmailJobPriority`, retry queue |
| `src/lib/email/dlq.ts` | DLQ writer + reader |
| `src/lib/analytics/exclusions.ts` | Synthetic-fixture predicates |
| `src/lib/events/admin-event-publishers.ts` | Live-overlay publishers (gated) |
| `src/app/api/cron/*/route.ts` | Per-cron handlers |

Your project's paths will differ; this is the canonical layout to translate.

---

## Polish Bar checks for B110

- [ ] Every cron has a runbook in `docs/runbooks/`.
- [ ] Secret-custody matrix exists at `phase10_secret_custody.md`.
- [ ] Drift-guards in CI: exclusions, webhook codes, env completeness, API version single-source, last_event_at coverage.
- [ ] Failure-mode catalog mapped to project-specific incidents.
- [ ] Bead/issue trail traceable from runbook → fix → test.
- [ ] `vercel.json` (or equivalent) has the full cron schedule with auth.
- [ ] Real-DB integration tests for every Polish Bar dimension.
- [ ] `BillingPolicyAudit-trial-discount-deal.test.ts` confirms BUSINESS policy matches provider state.
- [ ] Compliance evidence pack template exists for `compliance-pass` mode.
- [ ] On-call doc names escalation paths.
- [ ] **`docs/adr/billing/` folder exists** with README, 0000-template, and at least the ADRs covering verify-as-write, reconciliation tiers, payload integrity, SLO targets.
- [ ] **Every numerical billing constant** (SLO target, retry cap, grace days, dunning stage day) references its ADR by number in a code comment.
- [ ] ADR status field is one of: `Proposed | Accepted | Deprecated | Superseded by ADR-NNNN`.
- [ ] PR template includes "Does this change require a new ADR or amend an existing one?" checkbox.

---

## Common B110 mistakes

- **Runbook says "investigate" without the SQL / curl commands.** Operator under pressure can't find the right query.
- **Secret rotation cadence documented but no last-rotated date.** Audit can't prove rotation actually happened.
- **Drift-guard lists items but doesn't FAIL when one is missing.** Test the test.
- **Step order skipped because "we'll add MRR first to show leadership."** Re-do later when reporting depends on schema columns that don't exist.
- **Provider catalog audit done once, then forgotten.** Re-run quarterly; Stripe / PayPal evolve.
- **Compliance evidence pack written for the auditor, not for the future you who'll re-do it next year.** Make it self-explanatory.
