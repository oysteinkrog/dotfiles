# Migration Cutover Playbook

For `migration` mode. Switching from one billing system to another is the highest-risk operation in this skill. Mistakes are visible to every paying customer at once.

---

## When this applies

- Migrating from a different provider (Lemon Squeezy / Paddle / Chargebee / Recurly / hand-rolled) to Stripe and/or PayPal.
- Adding a second provider to a single-provider system (e.g., Stripe-only → Stripe + PayPal).
- Splitting a monolithic billing service into per-product billing services.
- Migrating from per-seat-quantity to discrete-tier pricing (B80 § 39).
- Migrating from Stripe Pages Router (legacy) to Stripe Checkout Sessions (current).
- Migrating Stripe API version major upgrades (e.g., `2024-06-20` → `2025-12-15.clover`).

---

## Cutover stages

```
Stage 0: PLAN        define scope, dual-run window, rollback path
Stage 1: BUILD       implement target system fully (audit-and-fix on the new code)
Stage 2: STAGING     dry-run cutover in staging; exercise rollback
Stage 3: DUAL-RUN    new sign-ups go to new system; old subs continue on old
Stage 4: CUTOVER     migrate existing subs (canary first; then waves)
Stage 5: SUNSET      old system kept read-only; archive evidence
```

Each stage has a go/no-go gate; advance only after explicit user approval.

---

## Stage 0 — Plan

### Scope inventory

```markdown
## Migration scope brief
- Old system: <name + version>
- New system: <name + version>
- What stays the same: <e.g., user table, app code, customer-facing pricing>
- What must move: <subscription state, payment methods, invoices, refund history, MRR snapshots>
- Customer count to migrate: <N>
- Estimated $$ in flight: <ARR>
- Compliance impact: <SOC2 control re-verification needed?>
- Rollback impact: <if cutover fails, can we restore prior state? In what time window?>
```

### Dual-run window

The dual-run window is the period (≥2 weeks for paying-customer SaaS) where:
- New sign-ups go to the new system.
- Existing subs continue on the old system.
- Reconciliation runs across both.
- Reporting (MRR, churn) merges both views.

Without a dual-run window, you're betting your customers' trust on a flag-flip cutover. Don't.

### Rollback path

For each stage, define:
- What state must be preserved (DB snapshot? old-system access kept active?).
- How long the rollback window is (typically 30 days).
- Exact commands to roll back (test these in staging).
- Customer communication plan if rollback is invoked.

---

## Stage 1 — Build

Run `audit-and-fix` mode on the target system. Specifically:
- Implement EVERY pattern bundle for the new provider.
- Pay special attention to the cross-provider duplicate-sub guard (B30 §29) — both sides must check the OTHER provider.
- Implement reconciliation that covers BOTH old and new systems during dual-run.
- Implement migration-specific tooling: a script that reads from the old system and writes to the new system per-customer.

### The migration tooling

Three operations:

1. **`read-from-old <customer_id>`** — extract subscription state, payment method, invoice history, refund history.
2. **`mirror-to-new <customer_id>`** — create equivalent objects in the new system in DRAFT/PENDING state (don't activate yet).
3. **`activate-on-new <customer_id>`** — flip the customer to the new system; cancel the old system's sub at next renewal.

The migration tooling is its own bundle — if it has bugs, customers see them. Apply Polish Bar to the migration tooling itself.

---

## Stage 2 — Staging

### Cutover dry-run in staging

Reproduce production state in staging (anonymized):
- 10-20 representative customers (different plans, statuses, ages, refund histories).
- Run `read-from-old` → `mirror-to-new` → `activate-on-new` for each.
- Verify in the new system: subscription state matches; access uninterrupted; analytics consistent.

### Exercise the rollback

Don't just document the rollback path — RUN IT in staging:
- After cutover dry-run, invoke the rollback.
- Verify customers are back on the old system.
- Verify no data was lost.
- Verify support cases / refund records are intact.

If the rollback can't be exercised cleanly in staging, the cutover is not safe to attempt in production.

### Go/no-go gate for Stage 3

- [ ] Cutover dry-run successful for ≥10 representative customers.
- [ ] Rollback exercised successfully.
- [ ] No data loss.
- [ ] Reporting (MRR, churn) accurate on both sides.
- [ ] User approves moving to dual-run.

---

## Stage 3 — Dual-run window

### Routing

- **New sign-ups** → new system. Update checkout pages to default to new system.
- **Existing subs** → continue on old system. No change.
- **Reconciliation** → daily cron compares both systems' subscription counts; alerts on drift.
- **Reporting** → merged view; provenance flags which system each row comes from.

### Watch for

| Signal | Action |
|--------|--------|
| New sign-ups failing on new system | Pause new-system traffic; investigate; revert checkout to old until fixed |
| Old-system webhooks failing more often than baseline | Old system is decaying; accelerate cutover |
| Customer support tickets mentioning "I see two charges" | Stop everything; reconcile; don't proceed until customers are correct |
| MRR diverges from sum-of-systems | Reconciliation bug; pause new sign-ups until resolved |

### Duration

- Minimum: 2 weeks.
- Typical: 4-8 weeks.
- Maximum: 6 months (if you wait longer, re-evaluate; the old system may be decaying).

### Go/no-go gate for Stage 4

- [ ] Dual-run period has run ≥2 weeks without unrecoverable incidents.
- [ ] Reconciliation drift is consistently <0.1%.
- [ ] Customer support tickets related to billing are at baseline (not elevated).
- [ ] User approves canary cutover.

---

## Stage 4 — Cutover

### Canary first

Pick 1-3 customers who fit the profile of "would understand if there's a hiccup" (your team accounts; an internal beta customer who's signed up for migration testing).

Run the migration tooling for the canary:
- `read-from-old <customer_id>`
- `mirror-to-new <customer_id>` (in PENDING state)
- Verify mirror is correct.
- `activate-on-new <customer_id>`
- Verify customer access uninterrupted.
- Wait 24-48 hours.
- Verify next renewal cycle behaves correctly.

If canary succeeds: proceed to waves. If not: rollback canary; investigate; fix; re-attempt.

### Waves

Don't migrate all customers at once. Split into waves:
- Wave 1: 10% of customers (preferably oldest / most loyal first — they tolerate hiccups).
- Wave 2: next 30%.
- Wave 3: next 30%.
- Wave 4: remaining 30%.

Each wave separated by ≥48 hours. Between waves, monitor:
- Customer support ticket volume.
- Refund / dispute rate.
- Failed migration count.
- Reconciliation drift.

If any metric spikes: pause waves; investigate; fix.

### Customer communication

- 30 days before cutover: notify customers in advance with FAQ / status page.
- 7 days before each wave: per-customer email naming the date.
- Day of: transactional email confirming the migration with a link to verify their billing details.
- Day after: follow-up email with support contact if anything looks off.

---

## Stage 5 — Sunset

### Old system in read-only mode

Do not delete the old system immediately. Keep it for:
- 30 days minimum: in case rollback is needed for a recently-migrated customer.
- 90 days typical: for refund-window claims.
- 2 years for tax: invoice history, settlement evidence, dispute records.

The old system can be in fully-read-only mode (no new charges, no webhooks processed) but accessible for support.

### Evidence pack

For compliance:
- Snapshot the old system's state at cutover-time.
- Document the cutover date for each customer.
- Preserve refund history that pre-dates the new system.
- Update SOC2 evidence to reflect the new billing architecture.

### Decommission

After 2 years (or whatever your jurisdiction requires for billing record retention), decommission the old system:
- Export final state.
- Cancel old-system contracts.
- Remove old-system credentials from Vercel / Vault.
- Update runbooks to remove old-system references.
- Postmortem the migration project.

---

## Common cutover mistakes

- **Skipping the dual-run window.** Trying to cut over in one batch. Customers see double-charges, missed activations, broken portal links — all at once.
- **Migrating active subscriptions on the old billing cycle.** A sub renewing tomorrow shouldn't be migrated today; migrate at the next natural renewal boundary.
- **Not exercising the rollback in staging.** "We have a rollback documented" is not the same as "we have tested the rollback." Always test.
- **Customer communication that says "you don't need to do anything."** Even if true, customers want to verify. Give them a verification link.
- **Reconciliation that only covers the new system.** During dual-run, reconciliation must cover BOTH systems and detect drift between them.
- **Assuming the old system's webhook infrastructure will keep running.** It may decay. Add a monitor; alert on increased old-system webhook failure rate.
- **Not preserving refund history.** A customer who got a refund 3 months before migration will be confused if your support team can't see it. Migrate the refund history, not just current state.
- **Decommissioning the old system on cutover day.** No. 30-90 days minimum read-only window.

---

## Cutover runbook template

```markdown
# Cutover runbook: <project> <YYYY-MM-DD>

## Pre-cutover go/no-go
- [ ] Stage 2 staging dry-run successful: <link to artifact>
- [ ] Stage 2 rollback exercised: <link to artifact>
- [ ] Stage 3 dual-run window completed: <date range>
- [ ] Reconciliation drift <0.1%: <link to dashboard>
- [ ] Customer comms sent: <date>
- [ ] On-call paged for cutover window: <name>
- [ ] User approval obtained: <name + date>

## Cutover commands (canary)
1. `node scripts/migrate.js --customer <id> --dry-run`
2. <inspect output>
3. `node scripts/migrate.js --customer <id> --execute`
4. Verify in new system dashboard.
5. Verify customer's denormalized status.
6. Wait 24h before proceeding to waves.

## Cutover commands (waves)
1. `node scripts/migrate.js --wave 1 --execute --confirm`
2. Monitor: <list of dashboards / queries>
3. Wait 48h.
4. Repeat for wave 2, 3, 4.

## Rollback (per customer)
1. `node scripts/migrate.js --customer <id> --rollback`
2. Verify old system shows the customer as active.
3. Notify customer of rollback (if visible).

## Rollback (entire wave)
1. `node scripts/migrate.js --wave <N> --rollback --confirm`
2. Verify all customers back on old system.
3. Alert team.

## Communication during cutover
- Slack channel: #billing-cutover-<date>
- Status page: scheduled maintenance posted; updated per stage.
- Customer support: briefed; canned responses ready.

## Post-cutover verification
- Day 1: manual sample of 10 customers; verify new-system access correct.
- Day 7: reconciliation audit; verify no orphan rows in old system.
- Day 30: final report; user sign-off; plan sunset.
```

---

## Tooling references

- Stripe migration tooling (if migrating to Stripe from another provider): https://stripe.com/docs/billing/migration/migrate-subscriptions
- Stripe import tool: https://stripe.com/docs/billing/migration/migrating-prices-and-subscriptions
- PayPal migration: there's no first-party PayPal-Subscriptions import tool; you build the migration tooling yourself.

---

## When NOT to migrate

Sometimes the right answer is "don't migrate." Signals:
- The old system works fine; the migration is "we want to use the cooler tool."
- The new system is materially less mature than the old (e.g., the user's stack already supports Stripe well; switching to a new provider for one feature is unwise).
- The user can't articulate the customer-facing benefit.

If the user asks for migration but can't articulate the benefit, push back. A migration that creates customer churn is worse than a slightly-uglier old system.
