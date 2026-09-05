---
name: billing-chargeback-handler
description: Implements the chargeback abuse process per § 78a.9 / B55 — disputed_at + chargeback_count + billing_banned_at + access-gate
---

# Chargeback Handler

For § 78a.9 / B55. Implements the chargeback abuse pattern. Used during incidents where chargebacks spike or as part of `add-feature` mode adding chargeback handling.

## Inputs

- Existing webhook handler set.
- `users` schema (to add `disputed_at`, `chargeback_count`, `billing_banned_at`).
- Auth middleware / paywall check (to gate access).

## Output

- Schema migration adding 3 columns to `users` (and `organizations` if team plans).
- `handleStripeDispute` / `handlePayPalDispute` handlers.
- Auth middleware update to check `disputed_at`.
- Admin alert for every chargeback (priority 5 — critical).
- Regression tests pinning the contract.

## Procedure

### Schema migration

```sql
ALTER TABLE users
  ADD COLUMN disputed_at        timestamptz,
  ADD COLUMN chargeback_count   int NOT NULL DEFAULT 0,
  ADD COLUMN billing_banned_at  timestamptz;

CREATE INDEX users_disputed_at_idx ON users (disputed_at) WHERE disputed_at IS NOT NULL;
CREATE INDEX users_billing_banned_at_idx ON users (billing_banned_at) WHERE billing_banned_at IS NOT NULL;

-- Same on organizations if team plans:
ALTER TABLE organizations
  ADD COLUMN disputed_at        timestamptz,
  ADD COLUMN chargeback_count   int NOT NULL DEFAULT 0,
  ADD COLUMN billing_banned_at  timestamptz;
```

### Dispute handler (Stripe)

Per the code template in `references/patterns/55-OBSERVABILITY-AND-DEFENSE-IN-DEPTH.md § 78a.9`. Wraps:
1. Account lock (`disputed_at = now()`).
2. Increment `chargeback_count`.
3. Billing-ban after threshold (e.g., 2 lifetime chargebacks).
4. Critical admin alert (priority 5).

### Dispute resolution handler

- `charge.dispute.funds_reinstated` (we won) → CLEAR `disputed_at`. KEEP `chargeback_count`.
- `charge.dispute.funds_withdrawn` + `closed` (we lost) → KEEP `disputed_at`. Customer must contact support.

### Access gate

In auth middleware:
```ts
if (user.disputedAt !== null) return { hasAccess: false, reason: 'disputed' };
if (user.billingBannedAt !== null) return { hasAccess: false, reason: 'billing_banned', canResubscribe: false };
```

### PayPal equivalent

PayPal disputes are different events (`CUSTOMER.DISPUTE.CREATED`, `CUSTOMER.DISPUTE.UPDATED`, `CUSTOMER.DISPUTE.RESOLVED`). Wire equivalent handlers.

## Discipline

- `disputed_at` is a SEPARATE column, not derived from subscription state. Survives subscription churn.
- Lock is immediate (don't wait for dispute outcome).
- Threshold for ban is conservative (2 lifetime); too low ban legitimate customers.
- Admin alert is critical priority (5); chargebacks have a dispute-response deadline.
- Customer communication is handled by support, NOT automated email (avoids notifying actual fraudsters).

## Regression tests

```ts
test('charge.dispute.created locks the account', async () => {
  await simulateStripeWebhook(disputeCreatedEvent);
  const user = await getUser(userId);
  expect(user.disputedAt).not.toBeNull();
  expect(user.chargebackCount).toBe(1);
});

test('charge.dispute.funds_reinstated clears the lock', async () => {
  await simulateStripeWebhook(disputeReinstatedEvent);
  const user = await getUser(userId);
  expect(user.disputedAt).toBeNull();
  expect(user.chargebackCount).toBe(1);  // count remains
});

test('second chargeback billing-bans the account', async () => {
  await simulateStripeWebhook(firstDispute);
  await simulateStripeWebhook(secondDispute);
  const user = await getUser(userId);
  expect(user.billingBannedAt).not.toBeNull();
});

test('disputed user is denied premium access', async () => {
  await db.update(users).set({ disputedAt: new Date() }).where(eq(users.id, userId));
  const result = await checkUserAccess(userId);
  expect(result.hasAccess).toBe(false);
  expect(result.reason).toBe('disputed');
});
```

## Integration

- B55 (Observability & Defense-in-Depth) bundle owner.
- Phase 5 — implement during add-feature for chargeback handling.
- Phase 7 — review the access gate (easy to miss in middleware).
- Phase 8 — regression tests above.
- Phase 10 — runbook `docs/runbooks/chargeback.md` — dispute defense response process.
