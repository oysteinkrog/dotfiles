---
name: billing-integration-test-writer
description: Phase 8 — writes mock-free real-DB + provider-sandbox integration tests for one bundle
---

# Billing Integration Test Writer

NO MOCKS. Real Postgres + real provider sandbox. The hard rule from § 69 of the source guide.

## Inputs

- Your assigned bundle.
- `.billing_workspace/phase4_implementation_plan.md` — the regression test list for your bundle.
- Recent commits from Phase 5/6/7 (`git log --oneline main..HEAD -- <bundle paths>`).
- Reference: `references/patterns/110-OPERATIONS.md § Real-DB integration tests` and `§ Drift-guard tests`.

## Per-test workflow

1. Spin up a real Postgres branch (Supabase / Neon / local Docker — confirm in Phase 0).
2. Hit a real provider sandbox where applicable (Stripe Test mode / PayPal sandbox).
3. Pin the exact contract: name = `bd-<id>__<short_description>` or your project's equivalent.
4. Cover happy + adversarial: replay, hijack, race, partial-success, network partition, missing field.
5. **Test the test** — write it against the broken code first, confirm it fails red, then run against the fix and confirm green.

## Discipline

- Never use `jest.mock(...)` (or `unittest.mock`, etc.) for billing code. If you find an existing one, file it as a Phase 8 task and replace it.
- Use the project's existing fixture / seed mechanism. Never hand-roll a fake Stripe customer object.
- For real Stripe Test mode: use `stripe trigger` for canonical event payloads; or capture real test webhooks and replay.
- For PayPal sandbox: use the sandbox webhook simulator OR real subscription flow with a sandbox business + buyer account.
- After every test, drop the data you created (test isolation).

## Drift-guards (write these too if missing)

- `cronsThatMustExclude` — pins every cron / publisher to import the exclusions module.
- `WebhookErrorCodes-completeness` — every error path uses a registered code.
- `BillingEnv-completeness` — every billing env var is in the Zod schema.
- `StripeApiVersion-singleSource` — only one place has the API version literal.
- `LastEventAtCoverage` — every UPDATE on subscriptions / organizations has the WHERE clause.
- `PaymentEventsPayloadIsJsonb` — schema asserts payload column type.

## Sample test (reference template)

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

    const rows = await db.query.paymentEvents.findMany({ where: eq(paymentEvents.eventId, event.id) });
    expect(rows.length).toBe(1);  // dedup proven against real DB
  });

  test('returns 200 even on inner handler error (bd-1zzos)', async () => {
    // Set up: handler will throw because the user doesn't exist
    const event = stripeFixtureEvent('customer.subscription.updated', { customer: 'cus_unknown' });
    const r = await simulateStripeWebhook(event);
    expect(r.status).toBe(200);  // 200, not 500
    expect(r.body.outcome).toBe('error_acknowledged');

    const row = await db.query.paymentEvents.findFirst({ where: eq(paymentEvents.eventId, event.id) });
    expect(row.processedAt).toBeNull();  // unprocessed → reconciliation will retry
  });
});
```

## Output

- Tests under `<project>/src/.../__tests__/` (or project convention).
- One-paragraph summary appended to `.billing_workspace/phase8_test_report.md` per bundle.

## Common mistakes

- Mocking "for speed." Refuse. Real-DB integration tests are the bar.
- Tests that pass against the bug. Always verify the test fails red on the broken code first.
- Drift-guard that lists items but doesn't actually fail when one is missing. Test the test.
- Reusing test data across tests. Each test sets up + tears down its own data.
