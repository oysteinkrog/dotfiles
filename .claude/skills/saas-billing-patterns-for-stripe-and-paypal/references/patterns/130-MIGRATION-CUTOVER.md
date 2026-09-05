# Bundle B130 — Migration Cutover Patterns

> **Where this comes from.** The migration mode in OPERATING-MODES.md + the cutover playbook in `references/methodology/MIGRATION-CUTOVER.md` + applied real-world cutover patterns.

This bundle is the code-level patterns for safely cutting over from one billing system to another. The methodology is in `MIGRATION-CUTOVER.md`; THIS bundle is the implementation patterns.

Used in `migration` mode + when adding a second provider to an existing system.

---

## Pattern 1 — Provider-symmetric canonical writer

The canonical writer (B40 § `updateSubscriptionStatus`) is provider-symmetric for a reason. Migration adds providers; the writer's contract stays the same.

When migrating from a single-provider system, the existing writer was probably implicitly Stripe-specific:

```ts
// Before migration:
async function updateSubscription(stripeSub: Stripe.Subscription) {
  await db.update(subscriptions).set({...}).where(eq(subscriptions.stripeId, stripeSub.id));
}
```

Migration step 1: refactor to provider-symmetric:

```ts
async function updateSubscriptionStatus(params: {
  provider: SubscriptionProvider;     // <-- now explicit
  externalSubscriptionId: string;     // <-- generic name
  customerId: string;                 // <-- generic name (Stripe cus_, PayPal payer_id)
  // ...
}): Promise<UpdateSubscriptionResult>;
```

Existing call sites become:

```ts
await updateSubscriptionStatus({
  provider: 'stripe',
  externalSubscriptionId: stripeSub.id,
  customerId: stripeSub.customer as string,
  ...
});
```

Drift-guard test: assert no remaining call site uses the old single-provider signature.

---

## Pattern 2 — Cross-provider duplicate-sub guard (mandatory)

The Tom Hunter pattern (B30 § `bd-1m86f`). When checkout starts, probe the OTHER provider before committing.

This is non-negotiable for dual-provider systems. Without it, a customer who's already paying via Stripe can start a PayPal checkout and end up with both.

```ts
async function hasActiveSubInOtherProvider(
  tx: TxLike,
  userId: string,
  newProvider: SubscriptionProvider,
): Promise<boolean> {
  // 1. DB check (fast, but webhooks can be stale)
  const dbSubs = await tx.query.subscriptions.findMany({
    where: and(
      eq(subscriptions.userId, userId),
      ne(subscriptions.provider, newProvider),
      inArray(subscriptions.status, ['active', 'past_due']),
    ),
  });
  if (dbSubs.length > 0) return true;

  // 2. Live probe to the OTHER provider
  if (newProvider === 'stripe') {
    const probe = await probePayPalForUser(userId);
    if (probe.hasLive) return true;
  } else {
    const probe = await probeStripeForUser(userId);
    if (probe.hasLive) return true;
  }

  return false;
}
```

The probe functions are themselves cached (5min TTL) to avoid hammering the OTHER provider on every checkout. But the cache MUST short-circuit when the user has an active session — there's no second chance.

---

## Pattern 3 — Migration tooling itself follows the pattern bundles

The migration tool that reads from old system and writes to new is itself a billing-touching component. Apply Polish Bar to it:

| Polish Bar dimension | How it applies to migration tooling |
|----------------------|-------------------------------------|
| 1 Provider-Authority | Migration tool reads from OLD provider; OLD provider is source of truth during dual-run. |
| 2 Layered-Defense | Migration tool retries on failure; an audit cron catches subs the tool missed. |
| 3 Idempotent-Writes | Migration tool can be re-run safely; UNIQUE on (`migrated_from_old_id`) prevents double-import. |
| 4 Hijack defense | Migration tool's input is from the OLD system, not user input; no hijack class. ✓ N/A. |
| 5 Stale-event ordering | If old system has a `last_event_at` equivalent, preserve it; new sub starts at the OLD sub's last event. |
| 6 200-on-error | If migration tool is webhook-driven (rare), 200-on-error applies. Otherwise N/A. |
| 7 Synchronous refund invalidation | If migration triggers a refund event, invalidate caches. |
| 8 Analytics exclusions | Migrated subs may need a new fixture for "imported" vs "organic"; preserve in analytics. |
| 9 Provenance | Migration creates a row with `provenance: migrated_from <old_system> at <timestamp>`. |
| 10 Cron defenses | Migration runs as a cron during dual-run; advisory lock + bounded scan apply. |
| 11 Secret custody | Old-system credentials managed identically to new-system credentials. |
| 12 Pin-the-contract | Every migration step has a regression test. |

---

## Pattern 4 — Three-state migration column

Add a `migration_state` column on `subscriptions` to track per-row migration status:

```sql
ALTER TABLE subscriptions
  ADD COLUMN migration_state         text NOT NULL DEFAULT 'native',
  ADD COLUMN migrated_from_provider  text,
  ADD COLUMN migrated_from_external_id text,
  ADD COLUMN migration_completed_at  timestamptz;

CREATE INDEX subscriptions_migration_state_idx ON subscriptions (migration_state);
```

States:
- `native` — created in the new system from scratch (default).
- `pending_migration` — old-system sub exists; new-system mirror is being created.
- `dual_run` — both systems have an active sub for this customer (transitional).
- `migrated` — fully migrated; old system is read-only / cancelled at next renewal.

Constraints:
- During dual-run, exactly one sub per customer should be in `dual_run` (others `native`).
- Once a customer is `migrated`, no further state transitions are allowed.

---

## Pattern 5 — Dual-run reconciliation

A new cron runs during dual-run to detect drift between old and new systems:

```ts
// /api/cron/dual-run-reconciliation (every 1 hour during dual-run)
async function dualRunReconciliation() {
  await acquireAdvisoryLock('dual_run_reconciliation', async () => {
    // For each user with a sub in either system, verify state matches expected
    const candidates = await db.query.users.findMany({
      where: not(isNull(subscriptions.migrationState)),  // only migrated users
      with: { subscriptions: true },
    });

    for (const user of candidates) {
      const oldSub = user.subscriptions.find(s => s.migrationState === 'migrated' || s.migrationState === 'dual_run');
      const newSub = user.subscriptions.find(s => s.migrationState === 'native' || s.migrationState === 'dual_run');

      if (!oldSub || !newSub) continue;

      // Drift detection
      if (oldSub.status !== newSub.status) {
        await emitDriftAlert({ user, oldSub, newSub });
      }
      if (oldSub.currentPeriodEnd?.getTime() !== newSub.currentPeriodEnd?.getTime()) {
        await emitDriftAlert({ user, oldSub, newSub, drift: 'period_end_mismatch' });
      }
    }
  });
}
```

If drift exceeds threshold (e.g., 0.1%), pause new sign-ups; investigate; don't proceed to next migration wave.

---

## Pattern 6 — Customer-renewal-boundary migration

Don't migrate active subs in the middle of a billing cycle. Migrate at the next NATURAL renewal boundary:

```ts
async function findMigrationCandidates(): Promise<MigrationCandidate[]> {
  // Find subs whose old-system renewal is in the next 7 days
  const candidates = await db.query.subscriptions.findMany({
    where: and(
      eq(subscriptions.migrationState, 'pending_migration'),
      lt(subscriptions.currentPeriodEnd, addDays(new Date(), 7)),
      gt(subscriptions.currentPeriodEnd, new Date()),
    ),
  });
  return candidates;
}
```

For each candidate:
1. Wait for the old-system renewal to fire (or fail).
2. If renewal succeeds: cancel old-system sub at end of new period; create new-system sub starting at old period's end.
3. If renewal fails: standard dunning on OLD system; defer migration until customer updates payment.

This minimizes customer-facing surface area.

---

## Pattern 7 — Customer communication in migration

Email cadence (per customer):
- T-30d: "We're moving to a new billing system on <date>. Your account will switch at your next renewal. No action needed."
- T-7d: "Your account renewal on <date> will be processed by our new billing system."
- T-0 (renewal day): "Your subscription has been migrated. Verify your billing details at <link>."
- T+1d: "Migration complete. If anything looks off, reply to this email."

The migration tool generates these emails (priority 60 — transactional). Don't bury them behind newsletters.

---

## Pattern 8 — Old-system read-only mode

After all customers are migrated:
1. Disable webhook delivery from the old system.
2. Cancel ALL active subs in the old system (they should have all been transitioned by then).
3. Snapshot the old system's state for compliance.
4. Old-system credentials remain in env vars for read-only access (refund history, dispute defense).
5. Document the old-system access pattern in a runbook.

```sql
-- A few months later:
ALTER TABLE subscriptions
  ADD COLUMN old_system_read_only_only boolean NOT NULL DEFAULT false;

-- Migration is complete: mark all migrated rows as old-system-readonly
UPDATE subscriptions
SET old_system_read_only_only = true
WHERE migration_state = 'migrated' AND migration_completed_at < now() - INTERVAL '60 days';
```

---

## Pattern 9 — Rollback drill (mandatory)

In Stage 2 of the cutover playbook, EXERCISE the rollback. The drill:

```
1. Run the cutover for 3 staging customers.
2. Wait 24h.
3. Invoke rollback script.
4. Verify: customers are back on old system; no data loss; refund history intact.
5. Document the rollback runbook with the EXACT commands used.
```

If you can't roll back cleanly in staging, you cannot safely cut over in production. Stop. Investigate. Re-test.

The rollback script:

```ts
// scripts/migrate.ts --rollback --customer <id>
async function rollback(customerId: string) {
  await db.transaction(async (tx) => {
    const subs = await tx.query.subscriptions.findMany({
      where: and(eq(subscriptions.userId, customerId), inArray(subscriptions.migrationState, ['migrated', 'dual_run'])),
    });

    for (const sub of subs) {
      // 1. Re-activate old-system sub
      await reactivateOldSystemSub(sub.migratedFromExternalId);

      // 2. Cancel new-system sub
      await cancelNewSystemSub(sub.externalId);

      // 3. Update local state
      await tx.update(subscriptions)
        .set({ migrationState: 'native', migratedFromExternalId: null })
        .where(eq(subscriptions.id, sub.id));
    }
  });
}
```

---

## Pattern 10 — Migration-specific dashboards

During dual-run, surface:
- Total customers in `pending_migration` / `dual_run` / `migrated`.
- Drift count (per `dual-run-reconciliation` cron).
- Per-wave success rate.
- Per-wave customer-support ticket volume (compared to baseline).
- Old-system webhook health (failure rate; if it's spiking, accelerate).

These feed go/no-go decisions for the next wave.

---

## Polish Bar checks for B130

- [ ] Canonical writer is provider-symmetric.
- [ ] Cross-provider duplicate-sub guard implemented.
- [ ] Migration tool follows the pattern bundles (Polish Bar applies to it).
- [ ] `migration_state` column + indexes on `subscriptions`.
- [ ] Dual-run reconciliation cron runs hourly during dual-run.
- [ ] Migration happens at customer-renewal boundary, not arbitrarily.
- [ ] Customer communication cadence respects priority queue.
- [ ] Old-system read-only mode after migration.
- [ ] Rollback drill exercised in staging.
- [ ] Migration-specific dashboards surface dual-run state.
- [ ] Postmortem template ready for cutover incidents.

---

## Common B130 mistakes

- **Migrating active subs mid-cycle.** Customer paid for a month they don't get; or the old system tries to renew while the new system is also renewing. Customer-renewal-boundary is the rule.
- **No dual-run window.** Flag-flip cutover; customer churn certain.
- **Migration tool not reviewed under Polish Bar.** It IS billing code; treat it as such.
- **Rollback documented but not exercised.** Documentation isn't reality.
- **Old-system credentials revoked too soon.** Need them for refund history / dispute defense.
- **No drift detection during dual-run.** Old and new diverge; nobody notices until customer complains.
- **Customer communication buried behind newsletter priority.** Lower customer adoption + more support tickets.
- **No per-wave kill switch.** First wave reveals a bug; you have to wait for the entire wave to complete before you can pause.
