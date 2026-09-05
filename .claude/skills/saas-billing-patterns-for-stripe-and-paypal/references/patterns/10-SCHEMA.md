# Bundle B10 — Schema

> **Where this comes from.** § 3 of the source guide.

Four load-bearing tables, plus six supporting tables. Keep them separate; never collapse. The Drizzle examples below are paste-ready; Prisma + SQLAlchemy + ActiveRecord translations are at the bottom.

---

## Table 1 — `payment_events` (webhook ingestion log)

```sql
CREATE TABLE payment_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider      subscription_provider NOT NULL,  -- 'stripe' | 'paypal'
  event_id      text NOT NULL,        -- provider-side event id
  event_type    text NOT NULL,        -- e.g. 'invoice.payment_succeeded'
  payload       jsonb NOT NULL,       -- FULL event so reconciliation has
                                      -- everything (preserves event.created
                                      -- for ordering, custom metadata, etc.)
  user_id       uuid,                 -- ENRICHED later by updateSubscriptionStatus
  processed_at  timestamptz,          -- NULL until handler succeeds
  retry_count   int NOT NULL DEFAULT 0,
  last_error    text,
  reconciled_at timestamptz,          -- NULL if processed by live webhook;
                                      -- non-null if processed by cron retry
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payment_events_unique UNIQUE (provider, event_id)
);
CREATE INDEX payment_events_unprocessed_idx
  ON payment_events (created_at)
  WHERE processed_at IS NULL;
```

### Non-obvious choices and why

- **`payload jsonb NOT NULL`** — store the FULL event, not the parsed subset. Reconciliation needs `event.created` for ordering and any field a future handler might read. Disk is cheap; flexibility is not.
- **`UNIQUE (provider, event_id)`** — the only correct dedup key. Provider event IDs are stable; trying to derive a key from payload contents is fragile.
- **`user_id` is enriched after the fact** by `enrichPaymentEventUserId()` once the handler resolves the user. This unlocks per-user analytics without forcing the webhook to know the user before it reads payload.
- **`reconciled_at` is separate from `processed_at`** so dashboards can distinguish "happy-path live webhook" from "cron caught it." A non-zero reconciled rate is itself a signal worth watching.
- **The partial index** is the hot path for the reconciliation cron's `WHERE processed_at IS NULL` scan; without it, the cron does full-table scans as the table grows.

### Drizzle

```ts
export const paymentEvents = pgTable('payment_events', {
  id: uuid('id').primaryKey().defaultRandom(),
  provider: subscriptionProvider('provider').notNull(),
  eventId: text('event_id').notNull(),
  eventType: text('event_type').notNull(),
  payload: jsonb('payload').notNull(),
  userId: uuid('user_id'),
  processedAt: timestamp('processed_at', { withTimezone: true }),
  retryCount: integer('retry_count').notNull().default(0),
  lastError: text('last_error'),
  reconciledAt: timestamp('reconciled_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => ({
  uniqueProviderEvent: unique('payment_events_unique').on(t.provider, t.eventId),
  unprocessedIdx: index('payment_events_unprocessed_idx').on(t.createdAt).where(sql`processed_at IS NULL`),
}));
```

---

## Table 2 — `subscriptions` (one row per provider-side subscription)

```sql
CREATE TYPE subscription_status AS ENUM (
  'none',           -- no active relationship (post-refund, pre-checkout)
  'active',         -- paying
  'past_due',       -- payment failed, in grace
  'cancelled',      -- cancelled but currentPeriodEnd may be in future
  'paused_for_org'  -- individual sub paused because user joined a team plan
);
CREATE TYPE subscription_provider AS ENUM ('stripe', 'paypal', 'gratis');

CREATE TABLE subscriptions (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider              subscription_provider NOT NULL,
  external_id           text NOT NULL,    -- provider-side sub id
  plan_id               text,             -- BUSINESS.STRIPE_PRICES key — null for gratis/legacy
  status                subscription_status NOT NULL,
  current_period_start  timestamptz,
  current_period_end    timestamptz,
  cancelled_at          timestamptz,
  last_event_at         timestamptz,      -- authoritative provider timestamp
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, external_id)
);
```

### Non-obvious choices and why

- **Multiple subscription rows per user are normal.** A user can move from Stripe → PayPal, get refunded once and re-subscribe, etc. Never assume `user.subscriptions.length <= 1`. The "current" sub is computed by `pickBestSubscription()` from all rows.
- **`paused_for_org`** is its own status, NOT just "cancelled with metadata." Treating an org-paused individual sub as cancelled would (a) double-bill the user when they leave the org, and (b) break the resume flow. See § 25 of source guide and the `paused_for_org` migration.
- **`last_event_at`** is the single field that prevents stale-replay revival. Every UPDATE includes `WHERE last_event_at < new_event_at` so a delayed webhook can't move state backwards.
- **`status = 'none'` is distinct from no row at all.** A refunded user keeps their subscription row with `status = 'none'` and `current_period_end = now()` for audit; a never-subscribed user has zero rows.
- **`gratis` provider** for comp / freebie subs (employee accounts, charity grants). Keep them in the same table so `pickBestSubscription` works uniformly; mark them excluded from analytics.
- **`plan_id`** is the project-side plan identifier (a key into `BUSINESS.STRIPE_PRICES`), denormalized here so the dunning helper's amount-mismatch guard (`Math.abs(invoice.amount_due - expected) > 1`, see B70 §"Manual invoice retry") doesn't have to round-trip through Stripe to know what plan the sub belongs to. Nullable so legacy subs migrated in without a known plan don't block the schema.

---

## Table 3 — Denormalized `users` columns

```sql
ALTER TABLE users
  ADD COLUMN customer_id                    text,           -- Stripe cus_ or PayPal payer_id
  ADD COLUMN subscription_status            subscription_status NOT NULL DEFAULT 'none',
  ADD COLUMN subscription_provider          subscription_provider,
  ADD COLUMN pending_checkout_provider      text,
  ADD COLUMN pending_checkout_session_id    text,
  ADD COLUMN pending_checkout_url           text,
  ADD COLUMN pending_checkout_expires_at    timestamptz;

-- The partial UNIQUE that prevents two open checkouts at once globally:
CREATE UNIQUE INDEX users_pending_checkout_session_idx
  ON users (pending_checkout_session_id)
  WHERE pending_checkout_session_id IS NOT NULL;
```

The four `pending_checkout_*` columns are the lock surface for checkout initiation. They serve four jobs at once:

1. **In-flight detection** — second click on Subscribe returns the existing URL instead of creating another session.
2. **Stale-session detection** — webhook handler compares incoming `session.id` to the user's current `pendingCheckoutSessionId` (Race B in `detectStaleCheckoutRace`).
3. **TTL-based recovery** — `pendingCheckoutExpiresAt < now()` means the prior attempt is dead; clear it and proactively expire the Stripe session.
4. **Cross-provider conflict prevention** — `pendingCheckoutProvider` lets you block "Subscribe with Stripe" when PayPal is mid-flight.

The denormalized `subscription_status` on `users` is a cache, NOT the truth. It's rebuilt by `deriveAggregateBillingProjection()` (B60) every time a subscription row changes.

---

## Table 4 — `email_jobs` (durable email queue with priority)

```sql
CREATE TABLE email_jobs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type            text NOT NULL,             -- e.g. 'billing_refund_alert'
  recipient       text NOT NULL,
  payload         jsonb NOT NULL,
  status          text NOT NULL DEFAULT 'queued',  -- 'queued' | 'sent' | 'failed' | 'dlq'
  priority        smallint NOT NULL DEFAULT 100,   -- LOWER = more urgent
  retry_count     int NOT NULL DEFAULT 0,
  next_retry_at   timestamptz NOT NULL DEFAULT now(),
  last_error      text,
  sent_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- The priority queue index — matches the email-batch processor's ORDER BY:
CREATE INDEX email_jobs_priority_queue_idx
  ON email_jobs (priority, next_retry_at, created_at)
  WHERE status = 'queued';
```

**Why a priority column at all?** Without it, a 5000-row newsletter blast fills the queue and a refund alert sits behind it. Bead trail: `bd-bfwcy.5 / BILLING-M3` — a real customer "you charged me but never told me" complaint.

Priority bands (from `inferEmailJobPriority`):

| Type pattern | Priority |
|--------------|----------|
| `billing_refund_*`, `billing_dispute_*` | 0–10 (drop everything) |
| `billing_past_due`, `billing_dunning_*` | 20–40 |
| `auth_*` (password reset, verification) | 50 |
| `transactional_*` (receipts, confirmations) | 60–80 |
| `admin_ops_*` | 90 |
| `digest_weekly`, `newsletter` | 200 |

---

## Supporting tables

| Table | Purpose | Source bead |
|-------|---------|-------------|
| `email_dlq` | Dead-letter for jobs past MAX retries; failsafe sweep reads here | `bd-ja8c0` |
| `compliance_events` | Append-only audit log for system alerts (NOT polluted with `abuse_detected`) | `bd-bfwcy.3` |
| `orphan_subscription_cancels` | Retry queue for provider-side cancels that failed during user delete | `bd-bfwcy.6` |
| `individual_subscription_intents` | Pause/resume intent rows; reconciliation closes divergence | `bd-yu9g9` |
| `notifications` | In-app notification rows; email links back via `metadata.notificationId` | n/a |
| `abuse_signals` | Per-IP, per-route counters for hijack attempts, replay attempts, signature failures | bd-2gxws + SA-06 |

```sql
CREATE TABLE compliance_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type  text NOT NULL,                    -- 'system_alert_dedupe', 'webhook_event_rejected', etc.
  actor_type  text NOT NULL,                    -- 'system' | 'user' | 'admin' | 'webhook'
  actor_id    text,
  target_type text,                             -- 'subscription' | 'user' | 'organization'
  target_id   text,
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX compliance_events_lookup ON compliance_events (event_type, created_at DESC);

CREATE TABLE orphan_subscription_cancels (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider        subscription_provider NOT NULL,
  external_id     text NOT NULL,
  retry_count     int NOT NULL DEFAULT 0,
  next_retry_at   timestamptz NOT NULL DEFAULT now(),
  last_error      text,
  user_id         uuid,                          -- the deleted user; FK NULL on cascade
  created_at      timestamptz NOT NULL DEFAULT now(),
  resolved_at     timestamptz
);
CREATE INDEX orphan_cancels_due_idx
  ON orphan_subscription_cancels (next_retry_at)
  WHERE resolved_at IS NULL;

CREATE TABLE individual_subscription_intents (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  intent          text NOT NULL,                  -- 'pause' | 'resume'
  org_id          uuid,                           -- if org-driven
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  applied_at      timestamptz,                    -- NULL until provider call confirmed
  last_error      text
);
CREATE UNIQUE INDEX individual_intents_open_per_user_idx
  ON individual_subscription_intents (user_id)
  WHERE applied_at IS NULL;
```

The partial UNIQUE on `individual_subscription_intents` enforces "one OPEN intent per user" — the `bd-yu9g9` race condition that motivated the table.

---

## Organizations table (mirrors users for team plans)

```sql
ALTER TABLE organizations
  ADD COLUMN stripe_customer_id              text,
  ADD COLUMN paypal_subscription_id          text,
  ADD COLUMN paypal_last_event_at            timestamptz,
  ADD COLUMN pending_checkout_session_id     text,
  ADD COLUMN pending_checkout_provider       text,
  ADD COLUMN pending_checkout_url            text,
  ADD COLUMN pending_checkout_expires_at     timestamptz,
  ADD COLUMN pending_individual_sub_cancel_user_id   uuid,
  ADD COLUMN pending_individual_sub_cancel_attempts  int NOT NULL DEFAULT 0,
  ADD COLUMN pending_individual_sub_cancel_last_error text,
  ADD COLUMN pending_individual_sub_cancel_next_at   timestamptz,
  ADD COLUMN subscription_status             subscription_status NOT NULL DEFAULT 'none',
  ADD COLUMN subscription_status_changed_at  timestamptz,
  ADD COLUMN max_seats                       int NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX orgs_pending_checkout_session_idx
  ON organizations (pending_checkout_session_id)
  WHERE pending_checkout_session_id IS NOT NULL;
```

The `subscription_status_changed_at` field is what `canonicalSubscriptionCancellationTimestampSql` (B100) falls back to for historical-coverage analytics — it survives a later "go back to active" event that would clobber a naive `updated_at` ordering.

`pending_individual_sub_cancel_*` is the team-side mirror of `orphan_subscription_cancels` for the individual→team upgrade orphan path (§ 45 of source guide).

---

## Migrations — the 9 that shaped this design

The source guide has nine load-bearing migrations. Order matters; some depend on previous Days' work.

| # | Migration | Adds | Bead |
|---|-----------|------|------|
| M1 | `payment_events` table + UNIQUE | the dedup boundary | bd-3m5v |
| M2 | `subscriptions` + `last_event_at` | the ordering primitive | bd-y2mp3 + d5cb654 |
| M3 | `subscription_status` ENUM + `paused_for_org` value | the lifecycle states | bd-yu9g9 |
| M4 | `pending_checkout_*` partial UNIQUE on users + orgs | the checkout race guard | BILLING-L2 |
| M5 | `email_jobs.priority` + `(priority, next_retry_at, created_at)` index | the priority queue | bd-bfwcy.5 |
| M6 | `compliance_events` table | the dedicated system-alert log | bd-bfwcy.3 |
| M7 | `orphan_subscription_cancels` table | the user-delete safety net | bd-bfwcy.6 |
| M8 | `individual_subscription_intents` + open-per-user partial UNIQUE | the pause/resume durable record | bd-yu9g9 |
| M9 | `subscription_status_changed_at` + `paypal_last_event_at` on organizations | the team-side ordering + cancellation-time canonicalization | bd-08xvg.3 + MOR-22B |

### Migration discipline (carry into B68)

- **One thing per migration.** Don't bundle "add column" + "rename column" + "data backfill" into one file. The 4-guard manual-retry overcharge defense (§ 33 of source) was discovered partly because a multi-purpose migration left intermediate state in production for weeks.
- **Backfill is a separate migration.** Schema migration M2-add-column → backfill migration M2.1-fill-column → schema migration M2.2-set-not-null. Three migrations, three reviewable diffs.
- **Drizzle / Prisma / SQLAlchemy generated migrations are starting points, not the final SQL.** Always read the generated SQL before applying. Drizzle in particular silently converts certain enum changes into "drop and recreate" sequences that lose data.
- **Stage migrations in a Supabase / Neon / staging branch** before applying to production. The 9-step list above all hit staging first; one was rolled back without anyone noticing because of this discipline.

Full per-migration playbook: see `110-OPERATIONS.md § Migration discipline`.

---

## Per-ORM translations

### Prisma

```prisma
model PaymentEvent {
  id            String              @id @default(uuid()) @db.Uuid
  provider      SubscriptionProvider
  eventId       String              @map("event_id")
  eventType     String              @map("event_type")
  payload       Json
  userId        String?             @map("user_id") @db.Uuid
  processedAt   DateTime?           @map("processed_at") @db.Timestamptz
  retryCount    Int                 @default(0) @map("retry_count")
  lastError     String?             @map("last_error")
  reconciledAt  DateTime?           @map("reconciled_at") @db.Timestamptz
  createdAt     DateTime            @default(now()) @map("created_at") @db.Timestamptz
  @@unique([provider, eventId], name: "payment_events_unique")
  @@index([createdAt], name: "payment_events_unprocessed_idx", map: "payment_events_unprocessed_idx")
  @@map("payment_events")
}

enum SubscriptionStatus {
  none
  active
  past_due
  cancelled
  paused_for_org
}

enum SubscriptionProvider {
  stripe
  paypal
  gratis
}
```

Prisma's partial-index support is limited; the `WHERE processed_at IS NULL` clause must be added in a raw migration:

```sql
-- after Prisma's generated migration:
DROP INDEX IF EXISTS payment_events_unprocessed_idx;
CREATE INDEX payment_events_unprocessed_idx
  ON payment_events (created_at)
  WHERE processed_at IS NULL;
```

Same for `pending_checkout_session_id` partial UNIQUE: raw SQL.

### SQLAlchemy (Python)

```python
class PaymentEvent(Base):
    __tablename__ = "payment_events"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)
    provider = Column(Enum("stripe", "paypal", name="subscription_provider"), nullable=False)
    event_id = Column(Text, nullable=False)
    event_type = Column(Text, nullable=False)
    payload = Column(JSONB, nullable=False)
    user_id = Column(UUID(as_uuid=True))
    processed_at = Column(DateTime(timezone=True))
    retry_count = Column(Integer, nullable=False, default=0)
    last_error = Column(Text)
    reconciled_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    __table_args__ = (
        UniqueConstraint("provider", "event_id", name="payment_events_unique"),
        Index("payment_events_unprocessed_idx", "created_at",
              postgresql_where=text("processed_at IS NULL")),
    )
```

### ActiveRecord (Rails)

```ruby
class CreatePaymentEvents < ActiveRecord::Migration[7.1]
  def change
    create_enum :subscription_provider, %w[stripe paypal gratis]
    create_enum :subscription_status, %w[none active past_due cancelled paused_for_org]

    create_table :payment_events, id: :uuid do |t|
      t.column :provider, :subscription_provider, null: false
      t.text :event_id, null: false
      t.text :event_type, null: false
      t.jsonb :payload, null: false
      t.uuid :user_id
      t.timestamptz :processed_at
      t.integer :retry_count, null: false, default: 0
      t.text :last_error
      t.timestamptz :reconciled_at
      t.timestamps tz: true
    end

    add_index :payment_events, [:provider, :event_id], unique: true, name: "payment_events_unique"
    add_index :payment_events, :created_at, where: "processed_at IS NULL", name: "payment_events_unprocessed_idx"
  end
end
```

### Ecto (Phoenix)

```elixir
def change do
  execute "CREATE TYPE subscription_provider AS ENUM ('stripe', 'paypal', 'gratis')"
  execute "CREATE TYPE subscription_status AS ENUM ('none','active','past_due','cancelled','paused_for_org')"

  create table(:payment_events, primary_key: false) do
    add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    add :provider, :subscription_provider, null: false
    add :event_id, :text, null: false
    add :event_type, :text, null: false
    add :payload, :map, null: false
    add :user_id, :uuid
    add :processed_at, :utc_datetime_usec
    add :retry_count, :integer, null: false, default: 0
    add :last_error, :text
    add :reconciled_at, :utc_datetime_usec
    add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
  end

  create unique_index(:payment_events, [:provider, :event_id], name: :payment_events_unique)
  create index(:payment_events, [:inserted_at], where: "processed_at IS NULL", name: :payment_events_unprocessed_idx)
end
```

---

## Per-subscription advisory locks (`pg_advisory_xact_lock(hashtext(...))`)

The `WHERE last_event_at < new_event_at` clause on the `subscriptions` UPDATE handles the *single-row* race: with READ COMMITTED isolation, Postgres re-evaluates the WHERE at lock time, so two concurrent UPDATEs for the same row converge to "later event wins; earlier silently no-ops."

What that clause does NOT cover:

1. **Side effects beyond the row.** Both handlers may execute cache-invalidations, admin email sends, `compliance_events` writes, or `payment_events.user_id` enrichments before the UPDATE WHERE rejects one of them. The losing handler did all that work; the duplicate side effects are the bug.
2. **INSERT-or-UPDATE races.** The first webhook for a brand-new subscription INSERTs the row. A second concurrent event for the same external_id finds nothing to UPDATE, falls through to its own INSERT, and hits the UNIQUE constraint — the handler then has to disambiguate "did I race a peer or genuinely fail?"
3. **Multi-table coherence.** A single event touches `subscriptions`, `users` (denormalized projection), and `payment_events.user_id`. The advisory lock holds across all of them so a concurrent event sees the post-commit state of every table at once.

The fix: PostgreSQL transaction-scoped advisory locks keyed on a hash of the subscription identifier. Hold the lock for the duration of the transaction; concurrent transactions for the same key block until commit, so each handler sees the prior one's complete result before it computes its own.

```ts
// src/lib/billing/subscription-lock.ts
export async function withSubscriptionLock<T>(
  tx: PgTx,
  scope: { provider: SubscriptionProvider; externalId: string },
  fn: () => Promise<T>,
): Promise<T> {
  // Stable key: provider:externalId. hashtext() coerces to int8 inside Postgres
  // so the same subscription always hashes to the same lock id across processes.
  const lockKey = `${scope.provider}:${scope.externalId}`;
  await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${lockKey}))`);
  return await fn();
}

// Inside updateSubscriptionStatus:
return await db.transaction(async (tx) => {
  return await withSubscriptionLock(tx, { provider, externalId: externalSubscriptionId }, async () => {
    // All the UPDATE / INSERT logic runs while we hold the lock.
    // Concurrent webhooks for the same sub block here until commit.
  });
});
```

**Why `pg_advisory_xact_lock` and not `SELECT ... FOR UPDATE`:**

| Mechanism | Behavior | When to use |
|-----------|----------|-------------|
| `SELECT ... FOR UPDATE` | Locks an EXISTING row | The row already exists (e.g., users row in checkout) |
| `pg_advisory_xact_lock(key)` | Locks a logical key, regardless of row existence | The row may not exist yet (e.g., first webhook for a new sub creates the row) |

For subscriptions, the row may not exist at lock acquisition time (it's the first `customer.subscription.created` event). Advisory locks let you serialize on the *future* row identity.

**Key choices that matter:**

- **`hashtext()` is deterministic across processes**, unlike a JS `hash()` would be. Two webhooks landing on different worker pods produce the same lock id.
- **`xact_lock` (transaction-scoped)** auto-releases on commit/rollback. Manual `pg_advisory_lock` can leak if you forget `pg_advisory_unlock`.
- **Lock the smallest scope that covers the invariant.** Don't lock the user; lock the (provider, external_id). Two different subs for the same user can update concurrently with no harm.
- **Reserve a DB connection for the lock**. Don't hand the connection back to the pool while holding the lock — most pools (pgBouncer transaction mode) won't return the same connection to the next query.

PayPal payment-event lock has a wider key (the parent payment ID + the sale ID) because PayPal sends multiple events per payment that all touch the same sub:

```ts
// In handlePaymentSaleCompleted:
const lockKey = `paypal-payment:${payload.id}:${payload.resource.id}`;
await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${lockKey}))`);
```

**Reference:** jeffreys-skills.md `src/app/api/subscription/upgrade-to-team/route.ts` and `src/app/api/paypal/webhook/route.ts`.

---

## Refund-terminal `none` state — the absorbing state

`status = 'none'` is not just "no current sub" — it is the **terminal absorbing state** that locks a refunded user's row against stale-webhook revival. Once a row reaches `none`, no inbound event can transition it back to `active` / `past_due` / `cancelled` without explicit human or admin-flow intervention.

The guard lives in `updateSubscriptionStatus`:

```ts
// Inside updateSubscriptionStatus, after stale-event guard:
if (existingSubscription.status === "none") {
  // Terminal state. Only an admin-initiated reactivation flow may move out of this.
  // A late-arriving webhook (e.g., a payment_succeeded that crossed paths with
  // a refund event) is dropped here.
  if (input.adminContext?.allowReactivation !== true) {
    logger.warn({
      subscriptionId: externalSubscriptionId,
      attemptedStatus: status,
      currentStatus: existingSubscription.status,
    }, "Refusing to reactivate refund-terminal subscription via webhook");

    recordVerifyEvent({ tag: VERIFY_EVENT_TAGS.REFUND_TERMINAL_REVIVAL_BLOCKED });
    return {
      currentStatus: "none",
      previousStatus: "none",
      isNew: false,
      userId: existingSubscription.userId,
      blocked: true,
    };
  }
}
```

The `adminContext.allowReactivation` flag is set ONLY by:

1. The admin "reactivate refunded sub" action (writes a `compliance_events` audit row with `actor.userId = admin.id` BEFORE calling `updateSubscriptionStatus`).
2. The "user re-subscribes after refund" checkout flow, which creates a NEW `subscriptions` row with a different `external_id` rather than re-using the old one.

**Why this matters in practice:** the `<=` ordering guard catches stale events with *older* timestamps. The absorbing-state guard catches a different scenario — a *newer* event whose status would naively un-do the refund:

1. Customer requests refund mid-cycle. Stripe `charge.refunded` arrives at `event.created = 1000`. `revokeAccessOnRefund` sets the sub row to `status = none`, `last_event_at = 1000`.
2. **A refund on Stripe does NOT auto-cancel the subscription** — they are separate operations. The Stripe sub remains `status = active` server-side until you (or the customer) explicitly cancel it.
3. The next billing cycle hits before anyone cancels the sub. Stripe attempts to charge the still-`active` sub and emits `customer.subscription.updated` and/or `invoice.payment_failed` (since the customer's intent is "I'm done") at `event.created = 1100` — strictly later than the refund.
4. Without the absorbing-state guard: the canonical writer sees `1100 > 1000`, passes the `<=` ordering check, and flips status back to `active` or `past_due`. The customer who was just refunded gets re-billed and keeps access. Bug.
5. With the guard: terminal `none` is honored regardless of timestamp arithmetic. The correct admin flow (refund → also cancel the Stripe sub) becomes the only path that re-activates anything; a quiet renewal-driven revival is impossible.

The two layers (`<=` ordering + terminal-`none` absorbing state) cover orthogonal failure modes: ordering guards stale-replay; the absorbing state guards correct-ordering-but-stale-business-state.

---

## `verify_endpoint_events` — PII-free counter table for verify-endpoint observability

The `/api/checkout/verify` endpoint runs on every post-checkout return and is the second line of defense after webhooks. It needs metrics, but raw event logs would balloon storage and contain PII (session IDs, user IDs, SDK errors). The fix is a tag-counter table with a small fixed namespace of stable tags:

```sql
CREATE TABLE verify_endpoint_events (
  tag           text NOT NULL,                       -- one of VERIFY_EVENT_TAGS
  provider      text,                                -- 'stripe' | 'paypal' | NULL
  hour_bucket   timestamptz NOT NULL,                -- date_trunc('hour', now())
  count         integer NOT NULL DEFAULT 0,
  schema_version integer NOT NULL DEFAULT 1,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT verify_endpoint_events_tag_provider_hour_idx
    UNIQUE (tag, provider, hour_bucket)
);
CREATE INDEX verify_endpoint_events_recent_idx
  ON verify_endpoint_events (hour_bucket DESC);
```

The closed-namespace tag set (every emitter MUST use a constant from this object — adding a new tag is a code change reviewed in PR):

```ts
// src/lib/observability/record-verify-event.ts
export const VERIFY_EVENT_TAGS = {
  // happy paths
  CAN_ACCESS_PREMIUM_SHORT_CIRCUIT: "verify.canAccessPremium_short_circuit",
  ACTIVATED_FROM_VERIFY:            "verify.activated_from_verify",
  PAYPAL_ACTIVE_ACTIVATED:          "verify.paypal_active_activated",
  RESUBSCRIPTION_ACTIVATED:         "verify.resubscription_activated",

  // recoverable
  EXPAND_FAILED_FALLBACK:           "verify.expand_failed_fallback",
  POLL_EXHAUSTED:                   "verify.poll_exhausted",
  RATE_LIMITED:                     "verify.rate_limited",
  SESSION_SUBSCRIPTION_NULL:        "verify.session_subscription_null",

  // errors that page on-call
  WRITE_PATH_DB_ERROR:              "verify.write_path_db_error",
  STRIPE_API_FAILED:                "verify.stripe_api_failed",
  STRIPE_SESSION_USER_MISMATCH:     "verify.stripe_session_user_mismatch",
  PAYLOAD_INTEGRITY_VIOLATION:      "verify.payload_integrity_violation",
  REFUND_TERMINAL_REVIVAL_BLOCKED:  "verify.refund_terminal_revival_blocked",
  UNEXPECTED_DISCOUNT:              "verify.unexpected_discount",
  UNEXPECTED_TRIALING_STATE:        "verify.unexpected_trialing_state",
  // ... (~25 total)
} as const;

export type VerifyEventTag = typeof VERIFY_EVENT_TAGS[keyof typeof VERIFY_EVENT_TAGS];

export async function recordVerifyEvent(params: {
  tag: VerifyEventTag;
  provider?: "stripe" | "paypal";
}): Promise<void> {
  const hourBucket = new Date(Math.floor(Date.now() / 3_600_000) * 3_600_000);
  await db.insert(verifyEndpointEvents)
    .values({ tag: params.tag, provider: params.provider ?? null, hourBucket, count: 1 })
    .onConflictDoUpdate({
      target: [verifyEndpointEvents.tag, verifyEndpointEvents.provider, verifyEndpointEvents.hourBucket],
      set: { count: sql`${verifyEndpointEvents.count} + 1`, updatedAt: new Date() },
    });
}
```

**Why this design:**

- **Closed namespace** — adding a new tag is a code change. No string interpolation possible.
- **Hour-bucketed** — exactly one row per (tag, provider, hour). Storage stays bounded; the alerts cron's window queries are O(log n).
- **`onConflictDoUpdate` with `count + 1`** — atomic increment without a SELECT-then-UPDATE race.
- **No PII** — tag, provider, hour, count. Audit-friendly. No GDPR retention burden beyond the alerts horizon.
- **`schema_version` column** — when you add a new field to a tag's semantics (e.g., a 26th tag), you bump `schema_version` so downstream alert rules can branch on shape.

The `verify-endpoint-alerts` cron (B55) reads this table to fire pages when per-tag counts exceed thresholds. The `/admin/health/checkout-verification` page (B45) reads it for a live dashboard.

**Reference:** jeffreys-skills.md `src/lib/observability/record-verify-event.ts:40-82` and the verify_endpoint_events Drizzle schema in `src/lib/db/schema.ts`.

---

## Schema-level Polish Bar checks

Before marking B10 `present`:

- [ ] `payment_events` exists with UNIQUE (provider, event_id) constraint named `payment_events_unique`.
- [ ] `payment_events.payload` is JSONB (not TEXT) and stores the FULL event.
- [ ] `payment_events.user_id` is nullable (enriched after the fact).
- [ ] `payment_events_unprocessed_idx` partial index exists.
- [ ] `subscriptions.last_event_at` column exists.
- [ ] `subscriptions` UNIQUE (provider, external_id) exists.
- [ ] `subscription_status` enum includes `paused_for_org` (or it's marked `n/a` for B80).
- [ ] `subscription_status` enum includes `none` AND it is honored as a terminal absorbing state by the canonical writer.
- [ ] `withSubscriptionLock(tx, scope, fn)` helper exists; every state UPDATE in the canonical writer holds the lock.
- [ ] Lock keys use `pg_advisory_xact_lock(hashtext(...))` (not `SELECT FOR UPDATE` on a may-not-exist row).
- [ ] `verify_endpoint_events` table exists with closed-namespace tag column + `(tag, provider, hour_bucket)` UNIQUE.
- [ ] `recordVerifyEvent` uses `onConflictDoUpdate` with `count + 1` (atomic increment, no SELECT-then-UPDATE race).
- [ ] `users.pending_checkout_session_id` partial UNIQUE exists.
- [ ] `email_jobs.priority` column + `(priority, next_retry_at, created_at)` index exists.
- [ ] `compliance_events` table exists separately from `abuse_signals` (different concerns).
- [ ] `orphan_subscription_cancels` table exists with `WHERE resolved_at IS NULL` partial index.
- [ ] `individual_subscription_intents` has open-per-user partial UNIQUE (or B80 is `n/a`).
- [ ] Every migration is one-thing-only and reviewable as a single diff.

---

## Common schema mistakes

- **Storing `payment_events.payload` as TEXT** — silent failure when reconciliation tries to read a field that wasn't in the original parsed subset.
- **Missing the partial index on `processed_at IS NULL`** — reconciliation cron does full table scans as the table grows.
- **Storing both `subscription_id` and `customer_id` only on `users`** — works for individuals; breaks for teams. Always go through the `subscriptions` / `organizations` row, not the user denormalization.
- **Forgetting to make the enum extensible** — `paused_for_org` was added later; if you can't ALTER TYPE in your stack, you'll have to recreate. Plan for it from the start.
- **`user_id NOT NULL` on `payment_events`** — webhooks can't always resolve user before insert; enforce nullability and enrich.
- **Using `updated_at` instead of `last_event_at`** — see Operator ⏱ STALE-EVENT-GATE for why this is wrong.
- **Hand-editing production schema** — always go through migrations. The schema.ts / Prisma schema must match Postgres exactly; drift here is the failure mode catalog item #4 ("A migration that doesn't update schema.ts").
