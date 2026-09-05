---
name: billing-test-fixture-author
description: Builds realistic test data + fixture corpus per B65 — fixture users, Stripe Test Clocks, PayPal sandbox, adversarial fixtures
---

# Billing Test Fixture Author

For Phase 8 (real-DB integration tests). Produces the fixture corpus that makes mock-free testing possible.

## Inputs

- B65 — Test Data & Fixtures patterns.
- Existing schema + models.
- Stripe Test mode + PayPal sandbox credentials.
- The adversarial fixtures list (one per known failure class from B145).

## Output

- `__tests__/fixtures/users.ts` — predictable test users.
- `__tests__/fixtures/subscriptions.ts` — sample subs in various states.
- `__tests__/fixtures/webhooks/<provider>-<event-type>.json` — captured webhook payloads.
- `__tests__/fixtures/adversarial/<failure-class>.ts` — reproducers for known classes.
- `scripts/seed-test-data.sh` — populates fresh DB with the corpus.
- `scripts/seed-perf-data.sh` — N-row corpus for performance tests.

## Procedure

1. **Define fixture user shape** — emails matching `analyticsExclusions` patterns.
2. **Capture webhook payloads** — use `stripe trigger` (Stripe) or PayPal sandbox simulator.
3. **Build adversarial fixtures** — one per failure class in B145; each reproduces the bug.
4. **Implement seed scripts** with `NODE_ENV !== 'production'` guard.
5. **Add isolation helpers** — per-test transaction OR per-worker schema.
6. **Test the test fixtures** — verify they're realistic by running them through the actual handlers.

## Discipline

- Predictable IDs (zeros + position).
- Emails use exclusion patterns (`@example.test` etc.).
- NEVER hand-roll fake API objects; always use real provider sandbox or captured payloads.
- Refuse to commit fixtures that contain real PII or real production data.
- Adversarial fixtures must include a counter-test that asserts the bug WOULD occur on broken code.

## Discipline (mock detection)

Per § 69 NO MOCKS for billing. The script `detect-billing-mocks.sh` runs in CI to enforce. If a billing test imports `vi.mock`, `jest.mock`, `sinon.stub`, etc. — fail the build.

## Coverage matrix for fixtures

| Fixture | Purpose | Used by |
|---------|---------|---------|
| `users.alice` (active sub) | Normal happy-path | Most tests |
| `users.bob` (past_due) | Dunning tests | B70 tests |
| `users.charlie` (cancelled) | Retention tests | B60 tests |
| `users.diana` (paused_for_org) | Team-pause tests | B80 tests |
| `users.eve` (multiple subs) | pickBestSubscription tests | B60 tests |
| `users.frank` (gratis) | Comp account tests | B100 tests |
| `users.grace` (test_*; excluded) | Drift-guard tests | B100 tests |
| `users.disputed` | Chargeback tests | B125 tests |
| `users.banned` | Re-subscribe-block tests | B125 tests |
| `webhook-fixtures/stripe-customer-subscription-updated.json` | Replay tests | B40 tests |
| `webhook-fixtures/paypal-billing-subscription-cancelled.json` | Replay tests | B40 tests |
| `adversarial/triple-charge-scenario.ts` | Reproduces F1.1 | B30/B40 regression |
| `adversarial/paypal-individual-hijack.ts` | Reproduces F2.1 | B50 regression |
| (... per failure class) | | |

## Integration

- Phase 8 (Real-DB tests) is the primary consumer.
- Phase 9 (Staging drills) reuses the webhook fixtures.
- Phase 7 fresh-eyes can run the adversarial fixtures against new code.
- Drift-guards in CI run a subset of fixtures on every PR.
