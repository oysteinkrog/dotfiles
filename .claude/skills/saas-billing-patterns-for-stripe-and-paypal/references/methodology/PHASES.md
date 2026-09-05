# Phase-by-Phase Playbook

Each phase has: **Goal**, **Inputs**, **Outputs**, **Subagent fanout**, **Exit criteria**, **Common failure modes**. The skill enforces the order; the modes (see [OPERATING-MODES.md](OPERATING-MODES.md)) decide which phases run and which are scoped.

All artifacts land in `.billing_workspace/` so they survive context compaction.

---

## Phase 0 — Inputs & confirmations

Already covered in `SKILL.md § Up-Front Confirmations`. Outputs:

- `.billing_workspace/phase0_mode.json` — `{ mode, providers, risk_appetite, branch_name, resume: bool }`
- `.billing_workspace/phase0_scope_decision.md` — mode, tier, included bundles, skipped bundles, and adjacent work explicitly not being done
- `.billing_workspace/phase0_skill_inventory.json` — from `scripts/check-skills.sh`
- `.billing_workspace/phase0_stack.json` — from `scripts/discover-stack.sh`

Scope decision template:

```markdown
# Billing Scope Decision

Mode:
Base tier:
Complexity overlays:
Provider scope:
Risk appetite:

## Required bundles
- <bundle> — <why required>

## Conditional bundles included
- <bundle> — triggered by <user ask / code evidence / live provider drift / incident>

## Conditional bundles skipped
- <bundle> — n/a because <reason>

## Not doing in this run
- <adjacent but out-of-scope work>
```

**Exit criteria.**
- The included/skipped bundle list is explicit.
- Every conditional bundle has either an activation trigger or `n/a` rationale.
- The user-facing plan matches the scope decision; no hidden NTM/git/CI/support expansion.

---

## Phase 1 — ARCHAEOLOGY

**Goal.** Build a reliable mental model of the project's existing billing surface (or confirm there is none, in greenfield).

**Inputs.** `phase0_stack.json`, the project root.

**Outputs.** One `phase1_archaeology_<bundle>.md` per bundle. Each file follows the template:

```markdown
# Bundle: <name>  (e.g., "B40 — Webhooks")

## Files in scope
- src/.../webhook/route.ts (148 LOC)
- src/lib/webhooks/inbound.ts (412 LOC)
- supabase/migrations/2025*.sql (3 files)

## Entry points
- POST /api/stripe/webhook  → handleStripeWebhook in route.ts:1
- POST /api/paypal/webhook  → handlePayPalWebhook in route.ts:1

## Key data structures
- payment_events (jsonb payload, UNIQUE provider+event_id) — yes
- subscriptions (last_event_at) — MISSING column
- recordWebhookEvent helper — present
- updateSubscriptionStatus canonical writer — partially present (see findings)

## Data flow (sketch)
[ASCII or short prose tracing event → handler → state mutation → side effects]

## Findings (raw, not yet scored)
- F1: webhook handler returns 500 on processing error (line X) — operator: ⤴ 200-ON-ERROR
- F2: no last_event_at column on subscriptions — operator: ⏱ STALE-EVENT-GATE
- F3: PayPal handler trusts metadata.user_id without cross-check — operator: ⌖ HIJACK-CROSS-CHECK
- ... (each finding names the operator that flags it)

## Open questions for Phase 2
- Does the customer have a `paypal_subscription_id` column on `organizations`?
- Is there an existing analytics-exclusion module?
```

**Subagent fanout.** One `subagents/archaeologist.md` per activated bundle (max ~6 in parallel; spawn more in waves). The bundle list comes from `phase0_scope_decision.md` and [`references/patterns/`](../patterns/), not a hard-coded core-only set.

**Exit criteria.**
- Every bundle has a `phase1_archaeology_<bundle>.md` (or is explicitly marked `n/a` in `phase1_index.md`).
- Every finding is tagged with the operator that flagged it (so Phase 2 can map findings → patterns deterministically).
- The main agent has read `phase1_index.md` (a one-page table of bundles + finding counts).

**Common failure modes.**
- Archaeologist reads the entire file instead of the entry points → context blowout. Use ripgrep first.
- Archaeologist hallucinates a function that doesn't exist. Always cite `file:line` for every finding.
- Archaeologist writes prose where they should write the structured table. Enforce the template.

---

## Phase 2 — COVERAGE

**Goal.** For every activated/in-scope pattern in [`references/patterns/`](../patterns/), classify the project's current state; skipped bundles still get an explicit `n/a` rationale from the scope decision.

**Inputs.** All `phase1_archaeology_<bundle>.md` files; the pattern library.

**Outputs.** `.billing_workspace/phase2_coverage_matrix.md` with one row per pattern:

| Pattern (file §section) | Status | Evidence (file:line) | Operator | Notes |
|--------------------------|--------|----------------------|----------|-------|
| `40-WEBHOOKS § recordWebhookEvent` | present | `src/lib/webhooks/inbound.ts:42` | 🔒 | UNIQUE constraint exists, dedup correct |
| `40-WEBHOOKS § 200-on-error` | partial | `route.ts:88` | ⤴ | Stripe path correct; PayPal path returns 500 on inner throw |
| `50-SECURITY § validatePayPalUserId` | missing | — | ⌖ | No cross-check; metadata.user_id is trusted |
| `100-ANALYTICS § canonical exclusions` | n/a | — | — | Not yet building admin analytics |
| ... | ... | ... | ... | ... |

Status values: `present | partial | missing | n/a`. Use `partial` when the pattern exists but doesn't satisfy the Polish Bar's full check.

`scripts/generate-coverage-matrix.mjs` emits the skeleton with all patterns from the library; the agent fills in evidence + status from Phase 1's findings.

**Subagent fanout.** One `coverage-mapper.md` per bundle, in parallel. Each owns the rows for its bundle.

**Exit criteria.**
- Every pattern row has `present | partial | missing | n/a` and either `Evidence` or `Notes`.
- The matrix is committed to `.billing_workspace/`.
- The user has reviewed the matrix and confirmed scope (rare to skip; common to mark some patterns as n/a for `internal-tool` risk-appetite projects).

**Common failure modes.**
- Marking a pattern `present` because the function exists, when the function exists with a bug. The Polish Bar is the bar — partial is the correct status if any dimension fails.
- Forgetting `n/a` rows. Be explicit about scope; future-you reads this matrix and assumes silence = `missing`.

---

## Phase 3 — RISK

**Goal.** Score every `partial` and `missing` row by exploitability × customer-impact × blast-radius. Produce an executive summary that a non-engineer can read.

**Inputs.** `phase2_coverage_matrix.md`.

**Outputs.**
- `.billing_workspace/phase3_risk_scored_gaps.md` — every gap with score 0–9, severity label, fix-section reference.
- `.billing_workspace/phase3_executive_summary.md` — ≤2 pages: top 5 risks, business impact in dollars / hours / customer-trust units, recommended mode for next phase.

Scoring rubric (see [RISK-SCORING.md](RISK-SCORING.md) for the full table):

| Score | Label | When |
|-------|-------|------|
| 9 | Critical / Drop everything | Active hijack class with no defense, OR entitlement drift visible to paying customer |
| 7-8 | High | Defense missing for known incident class; one bug from customer-visible incident |
| 5-6 | Medium | Defense partially present; reduces but doesn't eliminate exposure |
| 3-4 | Low | Hygiene / consistency issue; no immediate customer impact |
| 1-2 | Trivial | Comment / naming / lint-class issue |

**Subagent fanout.** One `risk-scorer.md` for ALL gaps (not bundle-parallel — scoring needs the cross-bundle picture). The agent is given the matrix and outputs the scored gap list + executive summary.

**Exit criteria.**
- Every gap has a numeric score and a one-sentence justification.
- The executive summary opens with one sentence: *"This billing system has X critical, Y high, Z medium gaps; the dominant theme is <pattern-cluster>."*
- The user has confirmed the recommended next mode (or overridden it).

**Common failure modes.**
- Scoring everything as 5 → no signal. Force a distribution: rare 9s, several 7-8s, lots of 3-6s.
- Confusing "exists in the codebase" with "verifiably correct under attack." Test scenarios in your head: replay, hijack, race, partial-success, network partition, secret rotation.

---

## Phase 4 — PLAN

**Goal.** Convert risk-scored gaps into a beads-style task graph that respects schema-before-code and bundle dependencies.

**Inputs.** `phase3_risk_scored_gaps.md`.

**Outputs.**
- `.billing_workspace/phase4_implementation_plan.md` — task graph with explicit dependencies.
- (If `br` is installed) actual beads created via `br create`, dependencies via `br dep add`.

Task graph rules:
- **Schema-before-code.** Any task that adds a column / table must precede tasks that reference it.
- **Constants-before-handlers.** `STRIPE_API_VERSION`, `BUSINESS`, `WebhookErrorCodes`, `ROUTES` go in before code that imports them.
- **Idempotency-before-state.** `recordWebhookEvent` must work before `updateSubscriptionStatus` is correct.
- **Reconciliation cron only after live writers exist** — otherwise the cron has nothing to reconcile against.
- **Drift-guards last.** Add the test that pins the contract after the contract is in place.
- **Scope-decision respect.** Do not create tasks for skipped bundles unless the plan documents the new trigger and updates `phase0_scope_decision.md`.

**Subagent fanout.** One `planner.md`. The plan is small enough that parallelism doesn't help; the dependency graph needs a unified view.

**Exit criteria.**
- Every gap with score ≥3 has a task; trivial gaps either have a task or are explicitly deferred.
- The graph has no cycles (`br dep validate` if available).
- The user has approved the order (especially any "we'll do X before Y" trade-offs).

**Common failure modes.**
- Bundling "schema migration + 200 lines of handler code" into one task. Split.
- Forgetting the regression test as its own dependent task on the fix it pins.
- Letting `greenfield` mode skip Step 1 (constants + schema) and start with Step 5 (a cron). Re-read the step-ordered build.
- Planning every optional bundle because it exists in the reference index. Re-open `phase0_scope_decision.md` and remove tasks without an activation trigger.

---

## Phase 5 — IMPLEMENT

**Goal.** Land the actual code changes. Same agent that did Phase 1's archaeology owns Phase 5's implementation for that bundle (continuity of context).

**Inputs.** `phase4_implementation_plan.md`, the source pattern files.

**Outputs.**
- A new branch (named in `phase0_mode.json`).
- Per-bundle commits with messages naming the bead/issue.
- For each task: code + test + (if a new pattern) drift-guard.

**Subagent fanout.** One `section-implementer.md` per bundle, in parallel. Coordination via [MCP Agent Mail](../../../agent-mail/SKILL.md) file reservations on cross-bundle files (`schema.ts`, `analytics/exclusions.ts`, `env.ts`, `stripe-config.ts`, `WebhookErrorCodes`).

For each task the implementer:
1. Reads the pattern file's relevant section.
2. Reads existing code at the file:line cited in the coverage matrix.
3. Makes the smallest change that satisfies the Polish Bar dimension.
4. Writes / updates the regression test (Pin-The-Contract operator).
5. Runs the project's test suite + linters before committing.

**Repeat-until-quiet.** Run a second pass per bundle that re-reads the Polish Bar and asks *"are all dimensions green now?"*. Continue until a pass produces only trivial edits.

**Exit criteria.**
- Every task in `phase4_implementation_plan.md` is closed.
- Per-bundle Polish Bar dimensions are all green or marked `n/a` with justification.
- `tsc --noEmit` (or equivalent) is clean.
- Project test suite is green.

**Common failure modes.**
- Implementer drifts beyond the task scope ("while I'm here, let me also refactor..."). Per AGENTS.md, *don't add features beyond what the task requires*.
- Implementer changes the contract without updating the test → Phase 8 will catch but Phase 7 should catch first.
- Implementer touches a file another bundle's implementer is editing without a file reservation → merge conflict. Always check Agent Mail reservations first.
- Implementer imports generic tooling guidance into the billing run. Generic NTM, git, CI, support, or onboarding changes belong only when the scope decision activated that reference.

---

## Phase 6 — HARMONIZE

**Goal.** Cross-bundle consistency. The implementers worked in parallel; harmonization is where we ensure the seams are clean.

**Inputs.** All Phase 5 commits.

**Outputs.**
- `.billing_workspace/phase6_harmonization_diff.md` — list of cross-cutting changes.
- Code changes in commit(s) explicitly named `harmonize: <theme>`.

Themes to harmonize (in order):

1. **Idempotency.** All UPDATE WHERE clauses include the right ordering + ownership guards.
2. **Env / constants.** Single source of truth for `STRIPE_API_VERSION`, `BUSINESS`, `WebhookErrorCodes`, `ROUTES`. No hard-coded literals duplicated across bundles.
3. **Exclusions.** Every cron / publisher / reader imports from one canonical `exclusions.ts`. Drift-guard list updated.
4. **Provenance.** Every cache value carries `live | fallback | unavailable`. Renderers handle `unavailable`.
5. **Error codes / event taxonomy.** Single registry; no in-line strings.
6. **Secret custody.** Inventory; rotation cadence; sensitive flags; production-only scope.
7. **Types.** No `any` in billing code; status enums match across bundles; Drizzle / Prisma schema matches Postgres exactly.

**Subagent fanout.** One `harmonizer.md` per theme, in waves (themes 1-3 in parallel; then 4-7 in parallel after waves 1-3 commit). Use Agent Mail reservations heavily — multiple themes will edit `schema.ts`, `env.ts`, `WebhookErrorCodes`.

**Exit criteria.**
- All seven themes have produced either a `harmonize: <theme>` commit OR a documented `no changes needed` note.
- `tsc --noEmit` clean; build clean; tests green.

**Repeat-until-quiet.** A second harmonization pass: skim every theme; if any pass produces non-trivial edits, run the next harmonization wave too.

**Common failure modes.**
- Harmonizer "consolidates" by widening a function's contract. Don't make `updateSubscriptionStatus` accept arbitrary metadata; force callers to be explicit.
- Harmonizer breaks a per-bundle nuance to make things "consistent." Some asymmetries are real (the team subscription handlers' Activated-vs-Cancelled WHERE clauses are asymmetric on purpose). Read the source pattern's "Why" section before flattening.

---

## Phase 7 — FRESH EYES

**Goal.** Adversarial, multi-pass review. Bugs introduced in Phase 5/6 are most likely caught here.

**Inputs.** All committed code on the branch.

**Outputs.**
- `.billing_workspace/phase7_round_<n>.md` per round.
- Code fixes for everything found.
- (Multi-model triangulation if available) `.billing_workspace/phase7_triangulation_<round>.md` cross-reference.

**Subagent fanout.** Three subagents per round, in parallel:
1. **`fresh-eyes.md` Round A — your-own-code lens.** *"Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs..."* (verbatim).
2. **`fresh-eyes.md` Round B — random-walk lens.** *"Sort of randomly explore the code files in this project, choosing code files to deeply investigate and trace their functionality and execution flows..."* (verbatim).
3. **`security-reviewer.md` Round C — adversarial-security lens.** *"Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits..."* (verbatim).

If `multi-model-triangulation` is installed, additionally fan out to Codex + Gemini per round (see [TRIANGULATION.md](TRIANGULATION.md)). Reconcile disagreements explicitly: if 2/3 models flag a bug and 1 doesn't, the consensus wins UNLESS the dissenter cites a counter-example.

**Repeat-until-quiet.** Run the three reviews until **two consecutive rounds** produce only trivial edits. Then run `ubs <changed-files>` (if available) and project linters; fix everything they flag.

**Exit criteria.**
- Two consecutive review rounds produced only trivial edits.
- `ubs` exit 0 (if available).
- Project linters clean.
- All fixes have regression tests (re-running Phase 8 must stay green).

**Common failure modes.**
- Stopping after one clean round. Two rounds is the gate; three is fine, one is not.
- Single-model review when multi-model is available. Independent reads catch different classes of bug.
- Letting "trivial edit" creep cover real fixes. If you're not sure if it's trivial, it isn't.

---

## Phase 8 — REAL-DB TESTS

**Goal.** Pin every contract with a real-database integration test. No mocks for billing code (per `§69` of source guide).

**Inputs.** All Phase 6/7 commits, the test surface from `phase4_implementation_plan.md`.

**Outputs.**
- New / updated tests under `<project>/src/.../__tests__/` (or the project's convention).
- `.billing_workspace/phase8_test_report.md` summarizing per-bundle coverage of the Polish Bar dimensions.
- Drift-guard test wired in CI: `cronsThatMustExclude`, `WebhookErrorCodes-completeness`, `BillingEnv-completeness`, etc.

**Subagent fanout.** One `integration-test-writer.md` per bundle. Each owns the regression-test gap from its bundle's coverage matrix.

For each test:
- Spin up a real Postgres (Supabase branch / Neon branch / local Docker — confirm in Phase 0).
- Hit a real provider sandbox (Stripe Test mode / PayPal sandbox).
- Pin the exact contract: name = `bd-<id>__<short_description>` or equivalent.
- Cover happy + adversarial (replay, hijack, race, partial-success, network partition).

**Exit criteria.**
- Every Polish Bar dimension has at least one test pinning it.
- Every fix from Phase 7 has a regression test.
- Test suite green; CI passing on the branch.
- Drift-guard test catches a synthetic violation (verify by intentionally breaking the import in a throwaway commit, confirming red, then reverting).

**Common failure modes.**
- Mocking "for speed." Refuse. Real-DB integration tests are the bar.
- Tests that pass against the bug. Always run the test against the broken code first to confirm it fails red, then fix and confirm green.
- Drift-guard that lists items but doesn't actually fail when one is missing. Test the test.

---

## Phase 9 — STAGING DRILL

**Goal.** End-to-end webhook drills against real Stripe Test mode + PayPal sandbox. Catches integration issues that real-DB tests can't.

**Inputs.** Phase 8 green; staging environment with real provider sandbox creds.

**Outputs.**
- `.billing_workspace/phase9_drill_report.md` — per-scenario pass/fail.
- Any code fixes for what the drills uncover.

Drill scenarios (minimum):
- Happy-path checkout (both providers).
- Stripe webhook replay (resend the same event from Stripe Dashboard) → confirm idempotent.
- PayPal sandbox subscription cancellation → confirm correct downstream state.
- Network partition: pause webhooks for 10 min, resume → confirm reconciliation cron drains and `last_event_at` ordering holds.
- Hijack drill: craft a PayPal subscription with `custom_id = <victim>` → confirm rejected with `paypal_user_id_mismatch` abuse signal.
- Refund drill: issue a Stripe refund → confirm synchronous cache invalidation, access revoked within 2s.
- Email failsafe drill: temporarily break Resend creds → confirm OPS_FAILSAFE_EMAIL fires.
- Cron lock drill: trigger the same cron twice in rapid succession → confirm second invocation acquires no lock and returns 200 cleanly.

**Subagent fanout.** One `staging-verifier.md` per scenario, parallel. The verifier triggers the scenario (via Stripe Dashboard / PayPal sandbox API / manual cron invoke) and asserts state.

**Exit criteria.**
- All minimum scenarios pass.
- Any failure has a regression test added in Phase 8 + a fix.
- For `migration` mode, the cutover dry-run is also green (see Phase 9.5).

### Phase 9.5 — Cutover (migration mode only)

If mode is `migration`, run a cutover dry-run against staging:
1. Dual-run window: new sign-ups go to new provider; old subs continue on old.
2. Verify both can be reconciled in the same `subscriptions` query.
3. Switch one canary subscription via the provider's migration tooling.
4. Verify access is uninterrupted and analytics are unconfused.
5. Document rollback path (NOT theoretical — actually exercise it in staging).

---

## Phase 10 — OPS HANDOFF

**Goal.** Make the system supportable. Without runbooks and a secret-custody matrix, every page becomes a re-discovery exercise.

**Inputs.** All committed work.

**Outputs.**
- `<project>/docs/runbooks/` — one file per scenario:
  - `webhook-staleness-alarm.md`
  - `paypal-hijack-attempt.md`
  - `triple-charge-incident.md`
  - `mrr-snapshot-unavailable.md`
  - `email-failsafe-alert.md`
  - `cron-lock-stuck.md`
  - `provider-outage.md`
  - `secret-rotation.md`
- `.billing_workspace/phase10_secret_custody.md` — every billing-touching credential with custody, scope, rotation cadence, last rotation, alerting.
- `.billing_workspace/phase10_oncall_doc.md` — escalation paths, who-to-page, on-call calendar reference.
- For `compliance-pass` mode: `.billing_workspace/phase10_evidence_pack/` mapping each control → evidence file.

**Subagent fanout.** One `runbook-writer.md` per runbook (parallel).

**Exit criteria.**
- Every alarm / metric / cron has a runbook.
- Secret-custody matrix is complete and reviewed by the user.
- For `compliance-pass`: every control has an evidence file.
- The user has acknowledged the on-call doc.

**Common failure modes.**
- Runbook that says "investigate" without telling you which queries to run. Always include the actual SQL / curl commands.
- Secret-custody matrix without rotation evidence. Custody without rotation history is a liability.
- Skipping the failure-mode catalog (`110-OPERATIONS § failure-mode-catalog`). Read it; some of the listed modes apply to your project even if they haven't bitten yet.

---

## Cross-phase rules

- **Every phase commits its workspace artifacts to `.billing_workspace/`** so the next phase / a resumed run can pick up where you left off.
- **Use Agent Mail file reservations** for any file touched by more than one bundle's agents (especially in Phase 5/6).
- **Every fix has a test.** No exceptions, even for "trivial" fixes. Phase 7 will find untested fixes; Phase 8 will catch them officially.
- **Mode-aware exit gates.** A `compliance-pass` doesn't need Phase 9 staging drills, but it does need Phase 10's evidence pack. Don't import the wrong gates.
- **Resume-safety.** Every artifact must be re-readable on a fresh agent. Use absolute file references (`src/foo.ts:42`), not "the function we just edited."
