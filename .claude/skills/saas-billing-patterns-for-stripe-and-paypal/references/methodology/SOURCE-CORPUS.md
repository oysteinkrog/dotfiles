# Source Corpus — Track A from operationalizing-expertise

This skill applies the [operationalizing-expertise](../../../operationalizing-expertise/SKILL.md) Track A workflow: **corpus + quote bank + triangulated kernel + operator library + validators**. The deliverables for that workflow already exist in this skill — this file documents WHERE.

---

## Why this matters

The source guide (`COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md`) is 6,800 lines drawn from ~700 commits, 339 closed beads, 57 cass session transcripts, 9 critical migrations, ~16 KLOC of service code, and 7 security-audit findings. That's a lot of evidence. Without an operationalized structure, the skill becomes "vibes referring vaguely to a guide."

The Track A discipline turns it into:
- **Corpus** — the primary sources, addressable by section.
- **Quote bank** — stable anchors with tags for fast retrieval.
- **Triangulated kernel** — the consensus invariants (the 16 north-star principles in `00-NORTH-STAR.md`).
- **Operator library** — composable cognitive moves (the 21 operators in `references/methodology/OPERATORS.md`).
- **Validators** — executable checks (the audit scripts in `scripts/`).

---

## Mapping this skill to Track A deliverables

| Track A deliverable | Where it lives in this skill |
|---------------------|------------------------------|
| `corpus/primary_sources/` | The master guide at `COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md`, plus referenced bead trail and cass transcripts. |
| `corpus/quote_bank/quote_bank.md` | This file, § Quote Bank below. |
| `corpus/specs/triangulated_kernel.md` | `references/patterns/00-NORTH-STAR.md` — the 16 north-star principles, marker-bounded as `<!-- BILLING_KERNEL_START v1.0 --> ... <!-- BILLING_KERNEL_END v1.0 -->`. |
| `corpus/specs/operator_library.md` | `references/methodology/OPERATORS.md` — 21 operators with triggers, failure modes, prompt modules. |
| `corpus/specs/session_kickoff*.md` | `references/methodology/AGENT-PROMPTS.md` and `KICKOFF-PROMPTS.md`. |
| `scripts/validate-corpus.py` | `scripts/verify-source-coverage.sh` (verifies every § maps to a bundle). |
| `scripts/validate-operators.py` | (TODO: a Polish-Bar checker that asserts every operator has trigger + failure-mode + prompt module sections). |
| `scripts/extract-kernel.py` | `scripts/extract-source-quotes.sh` (extracts kernel + quotes from the marked-up source). |

---

## Core invariants (must hold)

Per Track A, any expansion of this skill must respect:

- **Evidence-first.** Every rule in `references/patterns/` cites a source-guide section number (the `§ NN` notation in section headings).
- **Deterministic parsing.** The kernel block in `00-NORTH-STAR.md` is bounded by `<!-- BILLING_KERNEL_START v1.0 -->` / `<!-- BILLING_KERNEL_END v1.0 -->` so a script can extract it.
- **Triangulation.** The kernel is consensus-only (16 principles). Disputed points (e.g., should `BILLING.PLAN.UPDATED` be handled?) live in the bundle docs as "Common mistakes" / "Patterns rejected" sections, not in the kernel.
- **Operator cards must include triggers, failure modes, and prompt modules.** All 21 operators in OPERATORS.md follow this contract.
- **Validation gates required.** The Polish Bar (`POLISH-BAR.md`) is the gate; coverage matrix (`COVERAGE-MATRIX.md`) is the audit.
- **Provenance auditable.** Every pattern doc cites source-guide sections; bead IDs traceable via `BEAD-DICTIONARY.md`.
- **Join-key contract.** Workspace artifacts use the same `<bundle>` id (B10, B40, etc.) across phase artifacts; bead/issue IDs link tasks to fixes to tests to runbooks.

---

## Quote Bank

Tagged anchors from the source guide. Use these in:
- Bug reports (`> §1: "Provider is source of truth..."` is more authoritative than paraphrasing)
- Phase 7 fresh-eyes findings ("violates §29.6 Storing partial event payloads")
- Onboarding docs for new team members

Format: `[QUOTE_ID] (§N) tags: [tag1, tag2] — quote text — anchor: <bead/incident>`

### Kernel quotes

```
[Q-001] (§1) tags: [provider-authority, provenance]
"Provider is source of truth. Stripe / PayPal are authoritative. Our DB is a fast cache of provider state. Whenever they disagree, the provider wins."
anchor: north-star-principle-1

[Q-002] (§1) tags: [webhooks, layered-defense]
"Webhooks are best-effort. Treat every webhook as 'may arrive, may be late, may never come, may be duplicated, may be replayed by an attacker.' Build for all five."
anchor: north-star-principle-2

[Q-003] (§1) tags: [layered-defense, three-paths]
"Three write paths (live webhook, verify-as-write, reconciliation cron) and three alarm paths (per-event admin alert, stale-pipeline alarm, email failsafe escalation) so any single failure mode is caught by the next layer — never by a customer support ticket."
anchor: north-star-principle-3

[Q-004] (§1) tags: [idempotency, multi-layer]
"Idempotency at every write boundary. Provider-side idempotency keys plus DB-side payment_events dedup plus partial-UNIQUE indexes plus WHERE status IN (...) guards on UPDATEs plus WHERE last_event_at < new_event_at for ordering."
anchor: north-star-principle-4

[Q-005] (§1) tags: [200-on-error, retry-storm]
"Always return 200 to the provider after authenticated event ingestion — even on processing errors. Once a trusted provider event has a payment_events row, returning 500 just causes 3-day retry storms with partial-success duplicates."
anchor: north-star-principle-5; bead: bd-1zzos

[Q-006] (§1) tags: [refund-policy, human-in-loop]
"Refund decisions belong to humans. No automated refund or auto-cancel of a suspicious subscription. Detect, alert, queue for triage."
anchor: north-star-principle-6

[Q-007] (§1) tags: [analytics-exclusions, drift-guard]
"Synthetic test fixtures must be excluded from every read (analytics, dunning, alerts, integrity audits, MRR, weekly premium digest). One canonical exclusions module."
anchor: north-star-principle-7

[Q-008] (§1) tags: [cron-defenses, advisory-lock]
"Every cron uses a Postgres advisory lock to prevent overlap across Vercel isolates. Bounded scans, bounded retries, terminal-stuck digests so unbounded retry queues don't spam forever. Reserved DB connection for the lock — don't hand it back to the pool while the lock is held."
anchor: north-star-principle-8

[Q-009] (§1) tags: [intent-then-act, pool-exhaustion]
"Pause/resume Stripe writes happen OUTSIDE the DB transaction. The intent row is the durable record; reconciliation closes any divergence."
anchor: north-star-principle-9; bead: bd-yu9g9 / Billing-H4

[Q-010] (§1) tags: [verify-as-write]
"The /api/checkout/verify endpoint can ALSO write subscription state if the webhook hasn't landed yet. The webhook is a backup, not the primary writer."
anchor: north-star-principle-10

[Q-011] (§1) tags: [secrets, custody]
"Secrets are part of the billing boundary. Stripe secret/restricted keys, Stripe webhook secrets, PayPal client secrets, Supabase secret/service-role keys, cron secrets, and ops alert tokens are not 'deployment details.' They are capabilities that can create charges, grant access, read provider payloads, or bypass RLS."
anchor: north-star-principle-11

[Q-012] (§1) tags: [stale-event-gate, ordering]
"last_event_at is the only correct ordering primitive. Don't use updatedAt: reconciliation discovers provider drift long after the actual customer event. Don't use the local clock: webhooks arrive out of order. The provider's own event timestamp is the single ground truth for sequencing — and it must be on the row, not the audit table."
anchor: north-star-principle-12

[Q-013] (§1) tags: [constants, single-source]
"Centralize every constant that touches money or state semantics: pricing in BUSINESS, Stripe API version + client in stripe-config.ts, routes in ROUTES, error codes in WebhookErrorCodes, feature flags in env.ts."
anchor: north-star-principle-13

[Q-014] (§1) tags: [type-derive, sdk-version]
"Type-derive against the SDK, never hard-code SDK strings. Pin the Stripe API version using a type derived from ConstructorParameters<typeof Stripe>[1]['apiVersion']."
anchor: north-star-principle-13b; bead: bd-vifc1

[Q-015] (§1) tags: [analytics-exclusions, two-gate]
"Exclude analytics-excluded users from EVERY publisher and EVERY read. The activity feed and the metric counters MUST agree."
anchor: north-star-principle-14

[Q-016] (§1) tags: [pin-the-contract, regression-test]
"For every billing-touching DB write, add a regression test that pins the contract. The test name should map to the bead ID. When you delete or rename the test, that's how the next person knows what they just gave up."
anchor: north-star-principle-15
```

### Hijack defense quotes

```
[Q-020] (§13) tags: [paypal-hijack, custom-id]
"The payload is attacker-controlled in PayPal's case, because subscription.custom_id is set by whoever creates the subscription. PayPal will sign an attacker-created subscription that names the victim's UUID."
anchor: hijack-payload-trust; bead: bd-2gxws, bd-08xvg.1

[Q-021] (§14) tags: [paypal-hijack, validatePayPalUserId, cross-provider-switch]
"The cross-provider switch branch (cus_ prefix) is not theoretical: legitimate users do switch providers. The defense-in-depth is checking for an EXISTING PayPal sub on the user — if they're switching cleanly, there's no other PayPal sub. If there IS one, the incoming webhook is suspicious."
anchor: validatePayPalUserId-cross-provider

[Q-022] (§15) tags: [team-hijack, subscription_id-WHERE]
"A 0-row UPDATE on the rejection paths is the desired outcome — silent no-op that cannot mutate the victim. The Activated path is asymmetric because the WHERE clause alone cannot express 'either NULL → match OR equals → match,' so it does an explicit SELECT FOR UPDATE + branch."
anchor: team-hijack-asymmetric-guard; bead: bd-08xvg.1 / SA-01
```

### Anti-pattern quotes (rejected)

```
[Q-030] (§29.1) tags: [rejected, 500-on-webhook, retry-storm]
"Stripe retries live webhook deliveries for up to 3 days. Every automatic retry runs your handler again — if a partial side effect happened before the throw, that side effect happens N times. Always 200; let the reconciliation cron handle retries off your own payment_events rows."
anchor: rejected-500-on-webhook

[Q-031] (§29.2) tags: [rejected, auto-refund, customer-relationship]
"Real customers occasionally have legitimate duplicates (a user gifted themselves a sub, then later subscribed properly). Auto-refunding would destroy customer relationships. Always queue + human triage."
anchor: rejected-auto-refund

[Q-032] (§29.5) tags: [rejected, dry-coupling, god-function]
"Tempting DRY but wrong. orphan_subscription_cancels and organizations.pending_individual_sub_cancel_* are different schemas; coupling them through one helper would ratchet toward a god-function. Copy-and-adapt is right here."
anchor: rejected-shared-helper

[Q-033] (§29.6) tags: [rejected, partial-payload, future-handler]
"payment_events.payload stores the FULL provider event. Storing a parsed subset means any future handler change requires a re-fetch from the provider or a backfill. Disk is cheap; flexibility is not."
anchor: rejected-partial-payload

[Q-034] (§29.7) tags: [rejected, trust-metadata, hijack]
"For PayPal custom_id AND Stripe metadata.user_id, treat as a hint that must be cross-checked, never authoritative. Both are settable by anyone who can reach the provider's API."
anchor: rejected-trust-metadata

[Q-035] (§29.10) tags: [rejected, sql-view-mrr, cache-invalidation]
"A view is convenient but kills cache invalidation semantics. Replaced with getCurrentMrrSnapshot() (5min cache + invalidation hooks on every subscription mutation)."
anchor: rejected-sql-view-mrr
```

### Operational discipline quotes

```
[Q-040] (§51) tags: [cron-defenses, finally-release]
"pg_try_advisory_lock (non-blocking) so a stuck overlap doesn't queue a backlog. A dedicated reserved connection so the lock doesn't get dropped when the pool returns the connection. Per-cron (ns, key) so different crons don't serialize against each other."
anchor: cron-advisory-lock

[Q-041] (§52) tags: [email-priority, refund-alert, newsletter]
"Without it, a 5000-row newsletter blast fills the queue and a refund alert sits behind it."
anchor: email-priority-q-rationale; bead: bd-bfwcy.5 / BILLING-M3

[Q-042] (§78a.6b) tags: [secret-custody, vercel-env, NEXT_PUBLIC]
"Keep NEXT_PUBLIC_* strictly publishable. If a variable can create charges, read customer data, mint provider tokens, bypass RLS, or trigger a cron, its name must never start with NEXT_PUBLIC_."
anchor: vercel-env-publishable-rule

[Q-043] (§78a.7) tags: [webhooks, replay, timestamp-tolerance]
"Stripe's signature timestamp and the provider event object's created time are different clocks. Use signature timestamp tolerance to reject old HTTP deliveries; use event age as observability and operator workflow, not as a live hard reject."
anchor: webhook-age-as-signal

[Q-044] (§78a.8) tags: [cross-provider-webhook, route-boundary, source-confusion]
"A generic webhook endpoint is a footgun. Each provider/source needs its own route, verifier, event namespace, and provider-tagged idempotency key."
anchor: cross-provider-webhook-confusion

[Q-045] (§78a.10) tags: [idempotency, nested-side-effect, partial-success]
"The provider event can be idempotent while its nested side effects are not. Track admin-event publish, welcome email, analytics ping, and every other side effect independently so retries finish missing work instead of duplicating completed work."
anchor: nested-side-effect-idempotency

[Q-046] (§78a.11) tags: [settlement-ledger, accounting, provider-facts]
"Economic facts come from provider settlement objects, not from subscription rows or local invoices. MRR, churn, fees, refunds, disputes, and GL export are derivable views over the settlement ledger."
anchor: settlement-ledger-economic-source

[Q-047] (§78a.11) tags: [checkout, payload-integrity, metadata]
"Checkout metadata is a claim, not proof. The success/verify path must re-derive user, plan, amount, currency, provider account, and return URL server-side before granting access."
anchor: checkout-payload-integrity

[Q-048] (§78a.11) tags: [test-clocks, regression-gates, provider-drill]
"Test clocks and provider replay drills are not optional demos; they are the regression gate for renewal, dunning, cancellation, refund, SCA, and late-event behavior."
anchor: provider-clock-regression-gate
```

---

## Triangulated Kernel (marker-bounded)

The kernel is in `references/patterns/00-NORTH-STAR.md` between markers:

```
<!-- BILLING_KERNEL_START v1.0 -->
[the 16 north-star principles, paragraph form]
<!-- BILLING_KERNEL_END v1.0 -->
```

A future script (`scripts/extract-source-quotes.sh`) can extract this block deterministically.

The kernel is consensus-only. Disputed points live in pattern bundles' "Common mistakes" / "Patterns rejected" sections.

---

## How to extend the corpus

When adding a new pattern from a billing incident in YOUR project:

1. Add the source quote (the bead acceptance criteria, the postmortem one-liner) to `Quote Bank` above with a new `[Q-NNN]` ID.
2. If the pattern fits an existing bundle, add a section there with a citation (`§ <Q-NNN>`).
3. If the pattern is genuinely new (not derivable from the kernel), propose extending the kernel (PR review).
4. If the pattern requires a new operator (a cognitive move not yet in OPERATORS.md), propose adding it with the trigger + failure-mode + prompt-module structure.
5. Add the regression test that pins the contract (named after the bead).
6. Run `scripts/verify-source-coverage.sh` to confirm the new section is wired into the coverage matrix.

---

## Validators

The validation regime — the Track A "validation gates":

| Validator | Script | What it checks |
|-----------|--------|----------------|
| Coverage | `scripts/verify-source-coverage.sh` | Every § of the source guide maps to at least one bundle pattern. |
| Operator integrity | (TODO `scripts/validate-operators.py`) | Every operator card has trigger + failure-mode + prompt-module + composes-with. |
| Quote bank integrity | (TODO `scripts/validate-quote-bank.py`) | Every quote has a stable ID, a § anchor, ≥1 tag. |
| Polish Bar | `references/methodology/POLISH-BAR.md` | Every Polish Bar dimension has verification queries + a per-bundle applicability matrix. |
| Drift-guards | `references/patterns/110-OPERATIONS.md § Drift-guard tests` | Every implicit invariant has a CI test. |

Failing any validator blocks a release / acceptance of a Phase 5 implementation.
