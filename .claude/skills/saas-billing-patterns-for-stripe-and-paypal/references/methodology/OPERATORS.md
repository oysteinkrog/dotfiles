# Operators — Cognitive Moves for Billing Code

Operators are the *moves*, not the rules. The Polish Bar tells you *what* a great billing change looks like; operators tell you *how* to produce it. Each card has:

- **Glyph + Name** — the shorthand you call it by during code review
- **Trigger** — when this operator fires
- **Question** — the literal sentence to ask the code in front of you
- **Failure modes** — what happens if you skip it (with a bead trail)
- **Prompt module** — paste-ready text for a subagent
- **Composes with** — operators that tend to apply to the same line

Operators deliberately overlap. A single line of webhook code typically deserves 3–4. Apply them in the order from the **Composition cheat-sheet** at the bottom.

---

## ⊙ PROVIDER-AUTHORITY

**Trigger:** any read or write of subscription state, invoice state, refund state, customer state.
**Question:** *"If the provider says X and our DB says Y right now, do we render X to the user, or do we lie with Y?"*
**Failure modes:**
- DB-only checks decide a user has access when the provider already cancelled them (refund leaked entitlement).
- DB-only checks decide a user has no access when the provider just charged them (failed activation, support ticket).
- Cached "MRR" reads keep claiming a healthy number after Stripe outage.
**Prompt module:**
> *"For each read of `subscription_status` in the bundle I'm reviewing, identify whether the renderer would still display a stale value if the provider had just changed state in the last 60 seconds. If yes, propose either (a) a verify-as-write call before render, or (b) a `provenance` chip that visibly degrades to `unavailable` when stale-confidence is low."*
**Composes with:** 🪟 PROVENANCE, 🔁 RECONCILIATION-BACKSTOP.
**Source:** `00-NORTH-STAR §1`, `60-STATE-AND-LIFECYCLE §verify-as-write`, `100-ANALYTICS §MRR snapshot`.

---

## ⊕ LAYERED-DEFENSE

**Trigger:** any single-guard branch ("if this fails, it should be safe because... ?").
**Question:** *"If this single guard silently fails, what's the next layer that catches it?"*
**Failure modes:**
- Webhook handler bug → no other writer → user stuck in past_due forever.
- Reconciliation cron stalled → no alarm → discovered by customer ticket.
- Email queue stuck → no failsafe → refund alert never lands → lawyer gets involved.
**Prompt module:**
> *"List every entitlement-affecting state change in the bundle. For each, name the live writer, the verify-as-write fallback, and the reconciliation cron. If any column is empty, mark the gap with severity = 'requires layered defense'."*
**Composes with:** ⊙ PROVIDER-AUTHORITY, 🔁 RECONCILIATION-BACKSTOP.
**Source:** `00-NORTH-STAR §3`, `90-RELIABILITY`.

---

## 🔒 IDEMPOTENT-WRITE

**Trigger:** any insert / update that could be triggered more than once for the same logical event.
**Question:** *"If the same provider event arrives twice, does the second arrival do nothing — or does it duplicate a side effect?"*
**Failure modes:**
- Stripe webhook retries 3 days → duplicate charge ledger entries → bookkeeping nightmare.
- PayPal webhook retried after partial-success → duplicate email sent → user confusion.
- Verify-as-write race vs. live webhook → two `subscriptions` rows for same external_id.
**Prompt module:**
> *"For every `INSERT` or `UPDATE` in the bundle, identify the dedup mechanism: (1) provider-side `Idempotency-Key` / `PayPal-Request-Id`; (2) DB-side UNIQUE constraint or partial UNIQUE index; (3) status-set `WHERE` guard on the UPDATE. If fewer than two of the three are present, propose adding the missing layers."*
**Composes with:** ⏱ STALE-EVENT-GATE, ⌖ HIJACK-CROSS-CHECK.
**Source:** `00-NORTH-STAR §4`, `40-WEBHOOKS §recordWebhookEvent`, `30-CHECKOUT §idempotency`.

---

## ⌖ HIJACK-CROSS-CHECK

**Trigger:** any handler that uses provider-payload identifiers (`metadata.user_id`, PayPal `custom_id`, `subscription.id`) to address a row.
**Question:** *"If an attacker can construct a webhook payload that names the victim's row, what stops them from mutating it?"*
**Failure modes:**
- PayPal individual hijack: attacker creates subscription with `custom_id = victim_uuid` → free upgrade.
- PayPal team hijack: attacker mutates an arbitrary org's status by replaying a `subscription.id` they own.
- Stripe Connect / org events: attacker's account fires events at our endpoint → entitlement granted.
**Prompt module:**
> *"For every UPDATE on a billing-touching table, prove the WHERE clause includes BOTH a stable address (user_id / org_id) AND a provider-side cross-check (subscription_id / customer_id) that an attacker can't forge to match an arbitrary victim. For Stripe Connect / org event endpoints, also prove the originating account/context check is in place."*
**Composes with:** 🔒 IDEMPOTENT-WRITE, ⏱ STALE-EVENT-GATE.
**Source:** `50-SECURITY §validatePayPalUserId`, `§subscription_id WHERE`, `§account-mismatch`. Bead trail: `bd-2gxws`, `bd-08xvg.1`, SA-01.

---

## ⏱ STALE-EVENT-GATE

**Trigger:** any UPDATE on `subscriptions`, `organizations`, or any denormalized projection.
**Question:** *"If a webhook arrives with `event.created = T1` but our row was last updated by an event at `T2 > T1`, do we still apply the older event?"*
**Failure modes:**
- Late `subscription.cancelled` webhook overwrites a freshly-active subscription.
- `PAYMENT.SALE.DENIED` replayed weeks late revives `past_due` on a long-cancelled team.
- Reconciliation discovers drift months after the customer event and clobbers newer state.
**Prompt module:**
> *"List every UPDATE in the bundle that touches a status / period / cancelled-at field. Confirm the WHERE clause includes `last_event_at < new_event_at` (or the provider-specific equivalent). For any update that doesn't, propose the column + WHERE addition; if `last_event_at` doesn't exist on the table yet, that's a schema bead."*
**Composes with:** 🔒 IDEMPOTENT-WRITE, ⌖ HIJACK-CROSS-CHECK.
**Source:** `00-NORTH-STAR §12`, `50-SECURITY §replay-staleness`, `40-WEBHOOKS §canonical writer`.

---

## ⤴ 200-ON-ERROR

**Trigger:** any `try/catch` inside a webhook handler that runs AFTER `recordWebhookEvent` succeeded.
**Question:** *"If this `catch` block runs, do we still return 200 to the provider?"*
**Failure modes:**
- 500 → Stripe retries for 3 days → if a partial side-effect happened before the throw, it happens N times.
- 500 → PayPal retries up to 25 times in 3 days → same issue, plus eventual delivery-failed in dashboard.
- 500 → reconciliation cron is now competing with retry storms for the same row.
**Prompt module:**
> *"Identify every webhook handler in the bundle. For each, confirm: (1) signature failures and malformed JSON return 4xx; (2) `recordWebhookEvent` succeeded → 200 is the only outcome regardless of inner errors; (3) the inner catch logs `eventId` and writes nothing else. Flag any 500 / `throw` / `return NextResponse.json({...}, { status: 500 })` after `recordWebhookEvent`."*
**Composes with:** 🔁 RECONCILIATION-BACKSTOP, 🎚 PRIORITY-AWARE-QUEUE.
**Source:** `00-NORTH-STAR §5`, `40-WEBHOOKS §10`. Bead trail: `bd-1zzos`.

---

## ⛓ ANALYTICS-EXCLUSION

**Trigger:** any read that aggregates over users / subscriptions / orgs (admin dashboards, analytics, alerts, dunning, MRR, weekly digests, customer health scores).
**Question:** *"Does this read filter out synthetic test fixtures via the canonical `exclusions` module?"*
**Failure modes:**
- Test signups appear as "new subscribers" in admin events → leadership panic.
- Customer-facing email cron emails `you@example.test` → support ticket from real customers.
- MRR card includes test users → leadership decision off bad number.
- Drift: a new cron is added that doesn't import exclusions → caught only when a real customer asks why we emailed them about a test signup.
**Prompt module:**
> *"For every analytics read, admin event publisher, dunning select, and cron in the bundle, confirm it imports from `analytics/exclusions.ts` (or your project's canonical equivalent) and applies the predicate. Then confirm the cron / publisher is in the `cronsThatMustExclude` drift-guard list. If either is missing, propose the addition + the test."*
**Composes with:** 🪟 PROVENANCE, 🧪 PIN-THE-CONTRACT.
**Source:** `100-ANALYTICS §exclusions`, `110-OPERATIONS §drift-guard`. Bead trail: `bd-bfwcy.5` and the every-3-months recurrence pattern.

---

## 🪟 PROVENANCE

**Trigger:** any read from a cache, snapshot, materialized view, or external-call result that's displayed to a user or used in a downstream decision.
**Question:** *"Does this value carry `live | fallback | unavailable`, and does the renderer / downstream visibly degrade when not `live`?"*
**Failure modes:**
- Revenue tile shows last-known-good 0 during outage → looks like company died.
- Cached MRR served as authoritative for an investor report → number was 6 hours stale.
- Health score computed from `unavailable` feature → false negative on at-risk customer.
**Prompt module:**
> *"For every cache read in the bundle, identify whether the value is wrapped in a `provenance` envelope. If not, propose the wrapper. For every renderer / downstream consumer, confirm there's an `unavailable` branch — never silently render a fallback as if it were live."*
**Composes with:** ⊙ PROVIDER-AUTHORITY, 🔁 RECONCILIATION-BACKSTOP.
**Source:** `00-NORTH-STAR §1`, `100-ANALYTICS §MRR snapshot`, §single-flight, §reconciliation-freshness.

---

## 🗄 INTENT-THEN-ACT

**Trigger:** any code path that calls a slow / unreliable external service (Stripe, PayPal, Resend) inside a database transaction.
**Question:** *"Is the durable intent row written and committed BEFORE the slow provider call starts?"*
**Failure modes:**
- Pause/resume Stripe call inside DB tx → 80s–3min holding pool conn under bursts → pool exhaustion → outage.
- Refund call inside delete transaction → tx aborted by network blip → ghost subscription left.
- Long-running provider call → cron next tick discovers half-applied state and rolls forward incorrectly.
**Prompt module:**
> *"For each external provider call, identify whether it runs inside a DB transaction. If yes, propose the intent-then-act split: (1) INSERT a durable intent row + COMMIT; (2) call the provider; (3) UPDATE the intent row with the result outside the transaction; (4) reconciliation cron closes any divergence. The intent table is the durable record; reconciliation closes the loop."*
**Composes with:** ⊞ ADVISORY-LOCK, 🔁 RECONCILIATION-BACKSTOP.
**Source:** `00-NORTH-STAR §9`, `80-TEAMS §pause/resume`. Bead trail: `bd-yu9g9 / Billing-H4`.

---

## ⊞ ADVISORY-LOCK

**Trigger:** any cron handler.
**Question:** *"Does this cron use `pg_try_advisory_lock` with a `finally { conn.release() }`, and is the scan bounded?"*
**Failure modes:**
- Two cron isolates run concurrently → process the same `payment_events` row twice → duplicate side effect.
- Cron holds the reserved DB connection across a long batch → pool exhaustion.
- Unbounded scan when backlog grows → cron times out → backlog never drains.
**Prompt module:**
> *"For every cron route in the bundle, confirm: (1) the handler acquires `pg_try_advisory_lock(<unique_key>)` and bails out 200 if not acquired; (2) the reserved connection is released in `finally`; (3) the SELECT is bounded by `LIMIT N` matching the per-run wall-time budget; (4) the per-row retry cap is bounded; (5) there's a terminal-stuck digest for rows that exceed the retry cap."*
**Composes with:** 🗄 INTENT-THEN-ACT, 🎚 PRIORITY-AWARE-QUEUE.
**Source:** `00-NORTH-STAR §8`, `90-RELIABILITY §cron-defenses`.

---

## 🔁 RECONCILIATION-BACKSTOP

**Trigger:** any single-path write (live webhook only, verify-as-write only, cron only).
**Question:** *"If this single path silently drops the event, which other layer eventually fixes the state?"*
**Failure modes:**
- Live webhook only → silent loss → customer charged but inactive (Marco Fanti pattern).
- Verify-as-write only → user never opens the success URL → stuck.
- Cron only → cron broken → backlog grows invisibly.
**Prompt module:**
> *"For every entitlement-affecting state change, list the three layers (live writer, verify-as-write writer, reconciliation cron). For any column that's empty, propose the missing layer; for the integrity audit (daily backstop), confirm the bundle is in scope."*
**Composes with:** ⊙ PROVIDER-AUTHORITY, ⊕ LAYERED-DEFENSE, ⤴ 200-ON-ERROR.
**Source:** `00-NORTH-STAR §3`, `90-RELIABILITY §reconciliation`, §integrity-audit, §provider-authoritative-sweep.

---

## ⚖ HUMAN-IN-LOOP-REFUND

**Trigger:** any code path that proposes refunding, cancelling, or revoking access programmatically based on a heuristic.
**Question:** *"Is this irreversible action gated on a human approval, or are we trusting a heuristic to be right 100% of the time?"*
**Failure modes:**
- Auto-refund on duplicate detection → real customers occasionally have legitimate duplicates → relationship damage.
- Auto-cancel on "suspicious" subscription → false positive bans a legitimate paying customer.
- Auto-credit-back on dispute → encourages dispute fraud.
**Prompt module:**
> *"For every refund / cancel / revoke code path in the bundle, classify as: (a) deterministic (provider event arrived → mirror state, no judgment); (b) heuristic (we decided based on signals). Heuristic paths must produce an alert + queued triage row, never an automatic provider call. Propose the alert taxonomy + the operator runbook entry."*
**Composes with:** 🎚 PRIORITY-AWARE-QUEUE, 🔁 RECONCILIATION-BACKSTOP.
**Source:** `00-NORTH-STAR §6`. Bead trail: `bd-1m86f` initial auto-refund attempt and revert.

---

## 🔐 SECRET-CUSTODY

**Trigger:** any new env var, any place a secret is read, any change to deployment config, any place a webhook secret is rotated.
**Question:** *"Is this credential scoped, sensitive-flagged, environment-isolated, rotation-tracked, and absent from `NEXT_PUBLIC_*`?"*
**Failure modes:**
- `NEXT_PUBLIC_STRIPE_SECRET_KEY` → bundled into client JS → indexed by GitHub crawler.
- Live Stripe key in Preview deployments → preview branch fires real charges in test.
- Webhook secret never rotated → former employee retains the ability to forge events.
- Cron secret with the wrong scope → arbitrary unauth invocation.
**Prompt module:**
> *"List every secret the billing system uses. For each, confirm: (1) it's in production-only env; (2) marked sensitive in Vercel / equivalent; (3) absent from `NEXT_PUBLIC_*`; (4) has a documented rotation cadence; (5) custody is recorded (who can read it, who can rotate it). Build the secret-custody matrix in `phase10_secret_custody.md`."*
**Composes with:** ⌖ HIJACK-CROSS-CHECK, 🧪 PIN-THE-CONTRACT.
**Source:** `00-NORTH-STAR §11`, `20-CONSTANTS-AND-ENV §env`, `110-OPERATIONS §secret-custody`. Cross-ref: `78a.6b` of source guide.

---

## 🧪 PIN-THE-CONTRACT

**Trigger:** any bug fix, any new pattern, any subtle invariant.
**Question:** *"Is there a regression test mapped to a bead/incident name so the next person knows what they're giving up if they delete it?"*
**Failure modes:**
- Subtle invariant has no test → 6 months later someone deletes the apparently-redundant guard → incident reopens.
- Test exists but is named generically (`test_subscription_update_works`) → no signal about which contract it pins.
- Test only covers happy path → adversarial case (replay, hijack, race) is not pinned.
**Prompt module:**
> *"For every fix in this bundle, confirm a regression test exists with a name like `bd-<id>__<short_description>.test.ts`. If the test only covers the happy path, propose the adversarial counterpart (replay, hijack, race, partial-success). Add the test name to the per-bead acceptance-criteria section."*
**Composes with:** ⛓ ANALYTICS-EXCLUSION, 🔐 SECRET-CUSTODY, ⌖ HIJACK-CROSS-CHECK.
**Source:** `00-NORTH-STAR §15`, `110-OPERATIONS §integration-tests`, §drift-guards.

---

## 📐 TYPE-DERIVE-NOT-HARD-CODE

**Trigger:** any string that mirrors an SDK / provider type (Stripe API version, plan ID, event type literal, status enum).
**Question:** *"Is this string derived from the SDK's types so a future SDK upgrade fails to compile rather than fails at runtime?"*
**Failure modes:**
- `apiVersion: "2024-06-20"` hardcoded in 13 places → upgrade rolls one place forward → drift.
- Plan ID literal in admin code drifts from the price ID in checkout code → sells the wrong product.
- Event type literal ("invoice.payment_succeeded") misspelled in one handler → silent miss.
**Prompt module:**
> *"For every Stripe / PayPal SDK string literal in the bundle, replace with a typed constant in `constants/` (or the project's equivalent). Use `ConstructorParameters<typeof Stripe>[1]['apiVersion']` for the API version. Single source of truth. Existing call sites import from there."*
**Composes with:** 🔐 SECRET-CUSTODY, 🪞 BIDIRECTIONAL-COVERAGE.
**Source:** `00-NORTH-STAR §13`, `20-CONSTANTS-AND-ENV §STRIPE_API_VERSION`. Bead trail: `bd-vifc1` removed 13 separate `new Stripe({ apiVersion: ... })` instances.

---

## 🎚 PRIORITY-AWARE-QUEUE

**Trigger:** any new email / notification / alert type added to the queue.
**Question:** *"Is the priority set explicitly in `inferEmailJobPriority` (or equivalent) so a low-priority email can't delay a high-priority one?"*
**Failure modes:**
- Newsletter delays a refund alert by hours → customer "you charged me but never told me."
- Ops alert sits behind 1000 weekly digests during a true incident.
- DLQ-recovery sweep sends summary at the same priority as the original event types it covers → confused operator.
**Prompt module:**
> *"For every new email/notification type added in this bundle, confirm an explicit branch in `inferEmailJobPriority` (or your project's equivalent). Refund / dispute / past-due > customer-facing transactional > admin ops alerts > digests > newsletter. Add the test name to the per-type integration test."*
**Composes with:** ⊞ ADVISORY-LOCK, 🔁 RECONCILIATION-BACKSTOP.
**Source:** `90-RELIABILITY §email-queue priority`. Bead trail: `bd-bfwcy.5 / BILLING-M3`.

---

## 🪞 BIDIRECTIONAL-COVERAGE

**Trigger:** any change to subscribed webhook events (provider dashboard) OR handled webhook events (in code).
**Question:** *"Is the set of events the provider sends us EQUAL to the set of events we handle? Are there events we receive but ignore? Events we expect but don't subscribe to?"*
**Failure modes:**
- Subscribed in dashboard, no handler in code → events accumulate in Stripe's logs while we silently miss state changes.
- Handled in code, not subscribed in dashboard → handler is dead code (worse: the team thinks the case is covered).
- Provider added a new event type for an existing capability → silently miss it.
**Prompt module:**
> *"Read the provider's current webhook endpoint config (Stripe Dashboard / PayPal app config). Build the matrix: subscribed × handled. For each cell, classify: ✓ covered, ✗ subscribed-but-unhandled, ✗ handled-but-unsubscribed. Then re-run against the provider's live event API version (not just the SDK version we pinned) — sometimes the dashboard endpoint has a different rendering version. Output `phaseX_event_coverage.md`."*
**Composes with:** 📐 TYPE-DERIVE-NOT-HARD-CODE, 🧪 PIN-THE-CONTRACT.
**Source:** `40-WEBHOOKS §coverage`, `110-OPERATIONS §provider-catalog-audit`, `78a.3` of source guide.

---

## 🕰 WEBHOOK-AGE-AS-SIGNAL

**Trigger:** any webhook timestamp, replay window, provider event `created`, or manually replayed event.
**Question:** *"Am I using the right clock for the decision I'm making?"*
**Failure modes:**
- Live webhook hard-rejects an old provider event by `event.created` even though the provider legitimately retried it today.
- Security code confuses Stripe-Signature delivery timestamp with event-object created time.
- Operators have no alert on very old live events, so provider delivery drift is invisible.
**Prompt module:**
> *"Find every place this bundle reads webhook timestamps. Classify each as: (1) signature delivery timestamp for HTTP replay defense; (2) provider event created time for ordering/stale-event gating; (3) event age for observability/operator escalation. Flag any live webhook path that hard-rejects solely by event-object age. Add metrics for old-event arrivals and reserve hard age cutoffs for explicit replay tooling."*
**Composes with:** ⏱ STALE-EVENT-GATE, ⤴ 200-ON-ERROR, 🪞 BIDIRECTIONAL-COVERAGE.
**Source:** `55-OBSERVABILITY-AND-DEFENSE-IN-DEPTH §78a.7`, quote `Q-043`.

---

## 🧩 SIDE-EFFECT-LEDGER

**Trigger:** any webhook, verify-as-write, or cron path that emits more than one side effect after the primary DB write.
**Question:** *"If the handler succeeds through side effect 2 of 5 and then throws, will retry duplicate 1-2 or finish 3-5?"*
**Failure modes:**
- Webhook row is idempotent, but admin event publish duplicates on retry.
- Welcome email sends twice after PayPal retry because the email side effect has no idempotency marker.
- Analytics ping succeeds before a later DB write fails, so retry double-counts conversion.
**Prompt module:**
> *"List every side effect emitted by this handler after the primary event row is recorded: admin event, email, queue job, analytics, support ticket, cache invalidation, webhook fanout. For each, identify an idempotency key and a persisted side-effect marker. If no marker exists, add one or move the side effect behind a durable outbox row."*
**Composes with:** 🔒 IDEMPOTENT-WRITE, ⤴ 200-ON-ERROR, 🎚 PRIORITY-AWARE-QUEUE.
**Source:** `55-OBSERVABILITY-AND-DEFENSE-IN-DEPTH §78a.10`, quote `Q-045`.

---

## 💵 SETTLEMENT-FACTS

**Trigger:** any revenue, fee, refund, dispute, tax, GL, churn, or MRR computation.
**Question:** *"Is this number derived from provider settlement objects, or from a convenient local proxy?"*
**Failure modes:**
- Fees computed from plan price instead of provider settlement data; promotions and currency conversion make the number wrong.
- Refund/dispute accounting misses adjustment rows because local invoices never saw them.
- MRR and GL disagree because they derive from different local tables.
**Prompt module:**
> *"For every money-facing metric in this bundle, trace its source table. If it derives from `subscriptions`, `invoices`, checkout metadata, or local plan constants, ask whether provider Balance Transactions / PayPal Transaction Search / settlement ledger is the correct source instead. Ensure settlement rows carry provider, object id, type, gross, fee, net, tax, currency, presentment currency, occurred_at, and uniqueness."*
**Composes with:** ⊙ PROVIDER-AUTHORITY, 🪟 PROVENANCE, ⛓ ANALYTICS-EXCLUSION.
**Source:** `75-TAX-AND-ACCOUNTING`, `55-OBSERVABILITY-AND-DEFENSE-IN-DEPTH §78a.11`, quote `Q-046`.

---

## 🧾 PAYLOAD-INTEGRITY

**Trigger:** checkout creation, checkout success, verify-as-write, portal return, provider metadata, or any route that grants access from request/provider payload fields.
**Question:** *"Which parts of this payload are claims, and which facts do we re-derive server-side before granting access?"*
**Failure modes:**
- Attacker crafts a low-amount checkout session with metadata naming a high-value plan.
- Success URL or return URL is trusted even though it was user-controlled or incorrectly encoded.
- Provider metadata says `user_id = victim`, and access is granted without cross-checking pending intent, authenticated user, amount, currency, provider account, and plan mapping.
**Prompt module:**
> *"For every checkout/verify path, build the payload-integrity checklist: authenticated user, pending intent row, provider account, provider customer, plan/price ID, amount, currency, return URL, metadata, and session status. Mark each as server-derived, provider-derived, or attacker-controllable claim. No entitlement grant may depend on an attacker-controllable claim without a server/provider cross-check."*
**Composes with:** ⌖ HIJACK-CROSS-CHECK, 🔒 IDEMPOTENT-WRITE, 📐 TYPE-DERIVE-NOT-HARD-CODE.
**Source:** `30-CHECKOUT`, `55-OBSERVABILITY-AND-DEFENSE-IN-DEPTH §78a.11`, quote `Q-047`.

---

## Composition cheat-sheet

When reviewing or implementing one bundle, apply operators in this order. The order is a *recommended pipeline*; you don't have to run every operator every time, but if one is skipped, write down why.

### For a webhook handler

1. ⤴ 200-ON-ERROR — top-level guarantee
2. 🔒 IDEMPOTENT-WRITE — `recordWebhookEvent` first
3. ⌖ HIJACK-CROSS-CHECK — payload-derived addresses must cross-check
4. ⏱ STALE-EVENT-GATE — every UPDATE includes the ordering clause
5. 🕰 WEBHOOK-AGE-AS-SIGNAL — use delivery timestamp, event timestamp, and age metric correctly
6. 🧩 SIDE-EFFECT-LEDGER — nested side effects have their own idempotency markers
7. 🔁 RECONCILIATION-BACKSTOP — what catches it if this throws?
8. 🪞 BIDIRECTIONAL-COVERAGE — is this event type even in our handled set?
9. 🧪 PIN-THE-CONTRACT — regression test named for the contract

### For a checkout flow

1. 🔒 IDEMPOTENT-WRITE — provider idempotency key + `pendingCheckoutSessionId` UNIQUE
2. ⌖ HIJACK-CROSS-CHECK — cross-provider duplicate-sub guard, account check
3. 🧾 PAYLOAD-INTEGRITY — metadata, amount, user, provider account, and return URL cross-check
4. 📐 TYPE-DERIVE-NOT-HARD-CODE — plan IDs, API version, success_url builder
5. 🔐 SECRET-CUSTODY — Stripe / PayPal secrets, environment scope
6. 🧪 PIN-THE-CONTRACT — race-guard test, encoding test

### For a cron

1. ⊞ ADVISORY-LOCK — try-lock, finally-release, bounded scan
2. ⛓ ANALYTICS-EXCLUSION — exclusions imported, drift-guard listed
3. 🗄 INTENT-THEN-ACT — provider call outside any DB tx
4. 🎚 PRIORITY-AWARE-QUEUE — email / notification priority explicit
5. 🔁 RECONCILIATION-BACKSTOP — what's the next layer?
6. 🪟 PROVENANCE — does it write a value with provenance?

### For an analytics read

1. ⛓ ANALYTICS-EXCLUSION — first
2. 💵 SETTLEMENT-FACTS — cash/fee/refund/dispute facts come from settlement data
3. 🪟 PROVENANCE — wrap the result
4. ⊙ PROVIDER-AUTHORITY — fall back to provider when stale
5. 🧪 PIN-THE-CONTRACT — drift-guard test for the exclusion list

### For a refund / cancel / revoke path

1. ⚖ HUMAN-IN-LOOP-REFUND — heuristics produce alerts, not actions
2. 🔒 IDEMPOTENT-WRITE — refund mirror is exactly-once
3. 💵 SETTLEMENT-FACTS — refund/dispute accounting derives from provider settlement objects
4. 🪟 PROVENANCE — synchronous cache invalidation
5. 🎚 PRIORITY-AWARE-QUEUE — refund/dispute alerts at top priority
6. 🧪 PIN-THE-CONTRACT — regression test per incident class

---

## Operator hygiene

- Don't invent new operators casually; the cost is everyone has to memorize them. If you genuinely need one, propose it as a PR to this file with bead trail and ≥3 examples from real code.
- A bug review that doesn't name operators tends to be vibes. *Naming* is what makes the review reproducible.
- Operators are for *agents*, not for code comments. Don't write `// ⊕ LAYERED-DEFENSE` in production code; that's noise. Use the names in PR descriptions, code review comments, and bead acceptance criteria.
