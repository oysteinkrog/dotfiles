# Bundle B65 — Test Data & Fixtures

> **Where this comes from.** § 53 (test-fixture exclusion) + § 69 (real-DB integration tests) + cross-reference with `/testing-real-service-e2e-no-mocks` and `/testing-real-service-e2e-no-mocks`.

Real-DB integration tests need realistic test data. Hand-rolled fakes lie. Synthetic data + Stripe Test Clocks + PayPal sandbox produce signal that mirrors production.

---

## Pattern 1 — The fixture user pattern

Test users are real DB rows with predictable email patterns:

```sql
INSERT INTO users (id, email, created_at) VALUES
  -- Excluded from analytics via @example.test domain
  ('11111111-...', 'test_user_a@example.test', '2025-01-01'),
  ('22222222-...', 'test_user_b@example.test', '2025-01-01'),
  ('33333333-...', 'test_org_admin@example.test', '2025-01-01'),
  -- Org for team-plan tests
  -- ...
```

Predictable IDs (zeros + position) make tests easy to reason about. The `@example.test` domain triggers `analyticsExclusions.isExcluded` so these users never appear in MRR / health / dunning crons.

```ts
// __tests__/fixtures/users.ts
export const FIXTURE_USERS = {
  alice: { id: '11111111-1111-1111-1111-111111111111', email: 'test_alice@example.test' },
  bob:   { id: '22222222-2222-2222-2222-222222222222', email: 'test_bob@example.test' },
  // ...
};

export async function seedFixtureUsers(db: Db) {
  await db.insert(users).values(Object.values(FIXTURE_USERS)).onConflictDoNothing();
}
```

---

## Pattern 2 — Per-test transactional isolation

Use a transaction wrapper that ROLLBACKs after each test. No shared state between tests.

```ts
// __tests__/setup/db.ts
let testDb: NodePgDatabase<Schema>;

beforeAll(async () => {
  // Connect to a disposable Postgres branch
  testDb = drizzle(new Pool({ connectionString: env.TEST_DATABASE_URL }));
  await migrate(testDb, { migrationsFolder: './drizzle/migrations' });
});

beforeEach(async () => {
  await testDb.execute(sql`BEGIN`);
});
afterEach(async () => {
  await testDb.execute(sql`ROLLBACK`);
});
```

Trade-off: tests can't run truly in parallel (single transaction per connection). Use multiple test DB branches for parallelism (one per worker).

---

## Pattern 3 — Stripe Test Clocks — the canonical regression suite

Stripe Test Clocks let you advance time on a test customer to trigger renewal / failure / retry / cancellation events. Use for time-dependent scenarios.

```ts
// __tests__/billing/test-clocks/renewal.test.ts
import Stripe from 'stripe';
const stripe = new Stripe(env.STRIPE_TEST_SECRET_KEY, { apiVersion: '2025-12-15.clover' });

test('successful renewal updates currentPeriodEnd', async () => {
  // 1. Create test clock
  const clock = await stripe.testHelpers.testClocks.create({
    frozen_time: Math.floor(Date.now() / 1000),
    name: 'renewal-test',
  });

  // 2. Create customer + subscription on the clock
  const customer = await stripe.customers.create({
    email: 'test_renewal@example.test',
    test_clock: clock.id,
    payment_method: 'pm_card_visa',
    invoice_settings: { default_payment_method: 'pm_card_visa' },
  });
  const sub = await stripe.subscriptions.create({
    customer: customer.id,
    items: [{ price: env.STRIPE_PRICE_PRO_MONTHLY }],
  });

  // 3. Advance time past the renewal date
  await stripe.testHelpers.testClocks.advance(clock.id, {
    frozen_time: Math.floor(Date.now() / 1000) + 31 * 24 * 60 * 60,  // +31 days
  });

  // 4. Wait for clock to settle (Stripe processes events synchronously after advance)
  await waitForClockReady(clock.id);

  // 5. Verify our DB caught up
  const dbSub = await db.query.subscriptions.findFirst({
    where: eq(subscriptions.externalId, sub.id),
  });
  expect(dbSub.currentPeriodEnd.getTime()).toBeGreaterThan(Date.now() + 27 * 24 * 60 * 60 * 1000);

  // 6. Cleanup
  await stripe.testHelpers.testClocks.del(clock.id);
});
```

### Scenarios that MUST be in the test-clock suite

| Scenario | What it pins |
|----------|--------------|
| Successful renewal | currentPeriodEnd advances; no email; access continues |
| Failed renewal → past_due | Status transitions to past_due; dunning email D0 fires |
| past_due → grace expiry → suspension | Day 21 cron suspends; access denied |
| past_due → payment recovery | Status returns to active; access restored |
| Subscription cancellation at period end | Status transitions to cancelled; access continues to currentPeriodEnd; then revoked |
| Pause + resume | Status transitions to paused_for_org; resume restores |
| Subscription upgrade mid-cycle | Proration calculated correctly; new amount on next invoice |
| Subscription downgrade mid-cycle | Takes effect at next cycle; no immediate refund |
| Trial → paid conversion | trial_will_end fires 3 days before; conversion updates status |
| Trial → expired without conversion | Status transitions per trial_end_behavior |

---

## Pattern 4 — PayPal sandbox testing

PayPal sandbox doesn't have time-clock equivalents. Use the sandbox webhook simulator + real subscription flows.

```ts
// __tests__/billing/paypal-sandbox/cancellation.test.ts
test('PayPal cancellation transitions DB sub to cancelled', async () => {
  // 1. Create sandbox sub via the create-checkout flow
  const { subscriptionId } = await createSandboxSubscription({
    user: FIXTURE_USERS.alice,
    plan: 'pro_monthly_sandbox',
  });

  // 2. Cancel via PayPal sandbox API (acting as the user)
  await fetch(`${env.PAYPAL_SANDBOX_API_BASE}/v1/billing/subscriptions/${subscriptionId}/cancel`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${await getSandboxToken()}` },
    body: JSON.stringify({ reason: 'user_requested' }),
  });

  // 3. Wait for webhook to arrive + process
  await waitForCondition(async () => {
    const sub = await db.query.subscriptions.findFirst({
      where: eq(subscriptions.externalId, subscriptionId),
    });
    return sub?.status === 'cancelled';
  }, { timeout: 30_000 });

  // 4. Verify DB state
  const dbSub = await db.query.subscriptions.findFirst({
    where: eq(subscriptions.externalId, subscriptionId),
  });
  expect(dbSub.status).toBe('cancelled');
  expect(dbSub.cancelledAt).not.toBeNull();
});
```

---

## Pattern 5 — Webhook fixture replay corpus

For deterministic regression testing, capture real webhook payloads from sandbox + replay against the route handler:

```ts
// __tests__/fixtures/webhooks/stripe-customer-subscription-updated.json
// (Captured via `stripe trigger customer.subscription.updated --add ...`)

// __tests__/billing/webhook-replay/stripe.test.ts
import fixture from './fixtures/webhooks/stripe-customer-subscription-updated.json';

test('replay Stripe customer.subscription.updated', async () => {
  const body = JSON.stringify(fixture);
  const signature = createTestSignature(body, env.STRIPE_WEBHOOK_SECRET);

  const res = await POST('/api/stripe/webhook', { body, headers: { 'stripe-signature': signature } });
  expect(res.status).toBe(200);

  // Verify DB state after the event
  // ...
});
```

`createTestSignature` constructs a valid Stripe signature using the actual webhook secret + the actual SDK signing algorithm (don't bypass signature verification — that defeats the test).

---

## Pattern 6 — Adversarial fixture corpus

For each known failure class, a fixture that REPRODUCES the bug:

```
fixtures/adversarial/
├── triple-charge-tom-hunter.ts        → Reproduces bd-1m86f
├── paypal-individual-hijack.ts        → Reproduces bd-2gxws
├── paypal-team-hijack.ts              → Reproduces bd-08xvg.1
├── stale-event-replay-revival.ts      → Reproduces last_event_at miss
├── refund-without-cache-invalidation.ts → Reproduces SA-02
├── webhook-500-on-error.ts            → Reproduces 200-on-error miss
├── checkout-session-id-percent-encoded.ts → Reproduces bd-lp3vu
├── cron-no-advisory-lock.ts           → Reproduces pool exhaustion
├── orphan-sub-after-user-delete.ts    → Reproduces bd-bfwcy.6
├── pause-resume-pool-exhaustion.ts    → Reproduces bd-yu9g9
├── newsletter-blocks-refund-alert.ts  → Reproduces bd-bfwcy.5
└── analytics-exclusion-missing.ts     → Reproduces test-signup-as-new-subscriber
```

Each fixture has a counterpart test that:
1. Sets up the conditions for the bug.
2. Verifies the bug WOULD occur on the broken code (against a `__tests__/broken/` snapshot — kept for reference).
3. Verifies the fix prevents it.

This is the regression suite that PINS each pattern in `references/patterns/`.

---

## Pattern 7 — Test-fixture exclusion in production

Per § 53, the `analytics/exclusions.ts` module includes patterns that match fixture data:

```ts
// src/lib/analytics/exclusions.ts
const EXCLUDED_DOMAINS = ['example.test', 'example.com', 'test.local', 'mailinator.com'];
const EXCLUDED_EMAIL_PREFIXES = ['test_', 'qa_', 'ci_', 'fixture_'];
const EXCLUDED_USER_IDS = [
  // Production-specific test users you've seeded
  '11111111-1111-1111-1111-111111111111',  // alice
  '22222222-2222-2222-2222-222222222222',  // bob
  // ...
];
```

The test fixture INSERT runs against production-shaped DB; production code FILTERS via this module. Drift-guard test ensures every cron / publisher imports it.

The composite SQL helper:

```ts
export function buildAnalyticsIncludedUserCondition() {
  return and(
    not(inArray(users.id, EXCLUDED_USER_IDS)),
    not(or(...EXCLUDED_EMAIL_PREFIXES.map(p => sql`u.email LIKE ${p + '%'}`))),
    not(or(...EXCLUDED_DOMAINS.map(d => sql`u.email LIKE ${'%@' + d}`))),
  );
}

export function buildPaymentEventPayloadNotTestSubscriptionCondition() {
  // Payment events whose subscription_id is associated with a test user
  return sql`NOT EXISTS (
    SELECT 1 FROM subscriptions s
    JOIN users u ON u.id = s.user_id
    WHERE s.external_id = COALESCE(
      payment_events.payload->'data'->'object'->>'subscription',
      payment_events.payload->'resource'->>'id'
    )
    AND u.id IN (${EXCLUDED_USER_IDS.map(...)})
  )`;
}
```

---

## Pattern 8 — Test data seeding script

For greenfield: a script that populates a fresh DB with the standard fixture corpus.

```bash
#!/usr/bin/env bash
# scripts/seed-test-data.sh

set -euo pipefail

if [[ "$NODE_ENV" == "production" ]]; then
  echo "REFUSING to seed test data in production." >&2
  exit 1
fi

psql "$DATABASE_URL" <<'EOF'
TRUNCATE users, subscriptions, organizations, organization_members,
         payment_events, email_jobs, compliance_events
CASCADE;

-- Seed fixture users
INSERT INTO users (id, email, customer_id, subscription_status) VALUES
  ('11111111-1111-1111-1111-111111111111', 'test_alice@example.test', 'cus_test_alice', 'active'),
  ('22222222-2222-2222-2222-222222222222', 'test_bob@example.test', 'cus_test_bob', 'active'),
  -- ... etc
;

-- Seed fixture subscriptions
INSERT INTO subscriptions (...) VALUES (...);

-- Seed sample payment events (for reconciliation tests)
INSERT INTO payment_events (...) VALUES (...);
EOF

echo "Test data seeded."
```

---

## Pattern 9 — Test isolation per worker

For parallel test execution, each worker gets its own DB schema:

```ts
// __tests__/setup/parallel.ts
const workerId = process.env.JEST_WORKER_ID || '0';
const SCHEMA = `test_w${workerId}`;

beforeAll(async () => {
  await pool.query(`CREATE SCHEMA IF NOT EXISTS ${SCHEMA}`);
  await pool.query(`SET search_path TO ${SCHEMA}, public`);
  await migrate(testDb, { migrationsFolder: './drizzle/migrations' });
});

afterAll(async () => {
  await pool.query(`DROP SCHEMA ${SCHEMA} CASCADE`);
});
```

Each worker reads + writes ONLY its own schema. Real concurrency without test-data collisions.

---

## Pattern 10 — Fixture data for performance tests

For B105 (performance & scale): seed N representative subscriptions to test query performance at scale.

```bash
# scripts/seed-perf-data.sh — seed 10K subscriptions
node -e "
  const N = 10_000;
  for (let i = 0; i < N; i++) {
    await db.insert(users).values({ email: 'perf_test_' + i + '@example.test', ... });
    await db.insert(subscriptions).values({ ..., status: i % 100 < 90 ? 'active' : 'past_due' });
  }
  console.log('Seeded ' + N + ' rows.');
"
```

Then run analytics queries (MRR snapshot, churn calc, customer health) and verify they complete in < 5 seconds. If not, add indexes.

---

## Pattern 11 — Replay corpus from production-sanitized data

For debugging real incidents: a corpus of webhook payloads captured from production with PII redacted.

```bash
# scripts/sanitize-webhook-payload.mjs
# Reads a payment_events.payload from production-DB-snapshot,
# replaces PII fields with deterministic hashes,
# writes to fixtures/replay-corpus/
```

The replay corpus is what fresh agents use during incident response: "this is the exact payload that caused incident X; now write the fix."

---

## Pattern 12 — Mock detection script

The hard rule (§ 69): NO MOCKS for billing. Detect violations:

```bash
# scripts/detect-billing-mocks.sh
# Greps billing test files for forbidden patterns
rg -l 'jest\.mock\(|vi\.mock\(|sinon\.stub\(|@jest/globals.*mock' __tests__/billing/ \
  | while read f; do
      echo "VIOLATION: $f uses mocks for billing tests"
    done
```

Wire into CI; fail PR if any new mock is introduced in billing tests.

---

## Polish Bar checks for B65

- [ ] Fixture user IDs predictable (zeros + position).
- [ ] Fixture emails use `@example.test` (or equivalent).
- [ ] Per-test transactional isolation (or per-worker schema).
- [ ] Stripe Test Clocks for every time-dependent scenario.
- [ ] PayPal sandbox tests for every PayPal-side scenario.
- [ ] Webhook fixture replay corpus committed.
- [ ] Adversarial fixture per known failure class; pinned regression test.
- [ ] Production-shaped exclusion module imported by every analytics read.
- [ ] Mock-detection script in CI; fails on `jest.mock(...)` in billing tests.
- [ ] Test data seeding script with `NODE_ENV !== 'production'` guard.
- [ ] Test isolation supports parallel execution.
- [ ] Performance fixtures + scale tests run nightly.

---

## Common B65 mistakes

- **Hand-rolled `mockStripeApi(...)` in billing tests.** Mock passes; production fails. Refuse.
- **Test fixture emails without exclusion.** Test signups appear in MRR tile; leadership panic.
- **Tests share state across tests.** Order-dependent failures; flaky CI.
- **Test Clock created but never deleted.** Stripe sandbox accumulates clocks; eventually rate-limited.
- **Webhook fixture without proper signature.** Test passes via signature-bypass; production handler that requires signature would reject.
- **No adversarial fixtures.** Tests cover happy path; regression on known classes goes undetected.
- **Performance tests not run nightly.** Query plan changes silently regress; production incident first.
- **Test data seeding script runs against production.** Catastrophic. Always `NODE_ENV` guard.
