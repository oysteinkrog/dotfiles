# Compliance Evidence Pack

For `compliance-pass` mode. The auditor's question is "show me the control evidence." Your answer is the evidence pack.

This document defines what's in the pack, how to assemble it, and the per-control templates.

---

## What an evidence pack is

A directory `.billing_workspace/phase10_evidence_pack/` containing:

```
phase10_evidence_pack/
├── README.md                       # Index + audit-window dates + sign-off
├── controls_index.md               # Control → evidence file mapping
├── evidence/
│   ├── 01_stripe_account_state.md
│   ├── 02_stripe_webhook_coverage.md
│   ├── 03_stripe_price_audit.md
│   ├── 04_stripe_portal_config.md
│   ├── 05_stripe_payment_methods.md
│   ├── 06_stripe_payment_links.md
│   ├── 07_stripe_discounts.md
│   ├── 08_paypal_plans.md
│   ├── 09_paypal_webhook_coverage.md
│   ├── 10_paypal_recent_history.md
│   ├── 11_vercel_env_audit.md
│   ├── 12_supabase_rls_audit.md
│   ├── 13_secret_custody.md
│   ├── 14_drift_guards.md
│   ├── 15_runbooks_index.md
│   ├── 16_postmortems_index.md
│   ├── 17_integration_tests.md
│   ├── 18_oncall_doc.md
│   ├── 19_change_management.md
│   └── 20_rotation_log.md
├── known_issues/
│   └── <bead-id>__<short-description>.md   # one per known gap
└── attestations/
    ├── engineering_lead_signoff.md
    └── compliance_officer_signoff.md
```

The pack is delivered as a folder, not a single PDF. The auditor reviews per-evidence file.

---

## Mapping controls → evidence

Each compliance framework has its own control numbering. The pack supports:
- SOC2 Type 2 (Trust Service Criteria CC1-CC9, A1, C1, P1)
- ISO 27001:2022 (Annex A controls)
- PCI DSS (where applicable; most billing-skill projects don't touch card data directly because of Stripe Checkout)

`controls_index.md` is the per-framework mapping table:

```markdown
## SOC2 Type 2 — Trust Service Criteria mapping

| TSC | Control description | Evidence file(s) |
|-----|---------------------|------------------|
| CC6.1 | Logical access security | evidence/11_vercel_env_audit.md, evidence/12_supabase_rls_audit.md |
| CC6.2 | Manage credentials | evidence/13_secret_custody.md, evidence/20_rotation_log.md |
| CC6.6 | Authorization | evidence/12_supabase_rls_audit.md |
| CC6.7 | Restrict information transmission | evidence/04_stripe_portal_config.md, evidence/11_vercel_env_audit.md |
| CC6.8 | Protect against unauthorized software | evidence/19_change_management.md |
| CC7.1 | Detect security events | evidence/14_drift_guards.md, evidence/15_runbooks_index.md |
| CC7.2 | Monitor system performance | evidence/14_drift_guards.md |
| CC7.3 | Evaluate security events | evidence/16_postmortems_index.md |
| CC7.4 | Respond to security events | evidence/15_runbooks_index.md, evidence/16_postmortems_index.md |
| CC7.5 | Recover from identified events | evidence/15_runbooks_index.md, evidence/16_postmortems_index.md |
| CC8.1 | Manage changes | evidence/19_change_management.md |
| A1.2 | Availability — recovery & continuity | evidence/15_runbooks_index.md |
| C1.1 | Confidentiality — identify confidential info | evidence/12_supabase_rls_audit.md |
| C1.2 | Confidentiality — protect during transmission | evidence/11_vercel_env_audit.md |

## ISO 27001:2022 mapping
[similar table for ISO control families]
```

---

## Per-evidence file templates

Each evidence file is a structured `.md` with the **evidence envelope** (per VERIFICATION-FIRST.md) plus an auditor-facing summary.

### Template: `01_stripe_account_state.md`

```markdown
# Evidence: Stripe Account State

## Audit date
2026-MM-DD

## Source
Read-only Stripe API call from production environment.

## Evidence envelope
- checked_at: 2026-MM-DD HH:MM:SS UTC
- environment: production
- scope: read_only
- redaction: account_id_partial; no balance values; no transaction details
- tool: scripts/provider-diagnostics.sh --provider=stripe --check=account
- run_by: <engineer-name>

## Findings

### Account identity
- Account ID prefix: acct_xxx... (last 4 only: ...wxyz)
- Account country: US
- Account default currency: usd
- Charges enabled: true
- Payouts enabled: true
- Email associated: <support-email-domain-only>
- Created at: 2024-...

### Account capabilities
- card_payments: active
- transfers: active
- treasury: not_requested
- ...

### Account verification status
- verified: true
- representative information complete: true
- business profile complete: true
- ...

## Auditor-facing summary
This Stripe account is the production account, fully verified, with charges and payouts enabled. The account ID is pinned to env var STRIPE_ACCOUNT_ID and verified by the webhook handler's account-mismatch check (see evidence/02_stripe_webhook_coverage.md).

## Cross-reference
- BUSINESS constants: src/lib/constants/business.ts (account ID NOT hardcoded; read from env)
- Webhook handler account check: src/app/api/stripe/webhook/route.ts:44
- Drift-guard test: src/__tests__/billing/account-mismatch.test.ts
```

### Template: `02_stripe_webhook_coverage.md`

```markdown
# Evidence: Stripe Webhook Coverage

## Audit date
2026-MM-DD

## Source
Read-only Stripe API call (`webhook_endpoints.list`) + code grep of HANDLED_STRIPE_EVENTS set.

## Evidence envelope
- checked_at: 2026-MM-DD HH:MM:SS UTC
- environment: production
- scope: read_only
- redaction: endpoint URL hostname only; no full URLs; no signing secrets
- tool: scripts/audit-stripe-event-coverage.sh

## Findings

### Webhook endpoints configured
| Endpoint | Status | API version | enabled_events count |
|----------|--------|-------------|----------------------|
| https://<host>/api/stripe/webhook | enabled | 2025-12-15.clover | 18 |

### Event coverage matrix (subscribed × handled)

| Event type | Subscribed in Stripe | Handled in code | Decision | Reason |
|------------|---------------------|-----------------|----------|--------|
| customer.subscription.created | ✓ | ✓ | mutate | Activation flow |
| customer.subscription.updated | ✓ | ✓ | mutate | Status transitions |
| customer.subscription.deleted | ✓ | ✓ | mutate | Cancellation flow |
| invoice.paid | ✓ | ✓ | mutate | Renewal recognition |
| invoice.payment_failed | ✓ | ✓ | mutate | Dunning entry |
| invoice.payment_action_required | ✓ | ✓ | mutate | SCA routing |
| charge.refunded | ✓ | ✓ | mutate | Access revocation |
| charge.dispute.created | ✓ | ✓ | mutate | Account lock |
| customer.subscription.trial_will_end | ✗ | ✗ | n/a | No trials in product |
| ... | ... | ... | ... | ... |

### Drift detection
Drift-guard test pins this matrix: src/__tests__/billing/event-coverage-drift.test.ts
Last run: <timestamp>; result: PASS.

## Auditor-facing summary
Webhook coverage is bidirectionally aligned: every event subscribed has a handler decision (mutate / record_only / ignore_with_reason); every handler branch is reachable via a subscribed event. A drift-guard test prevents future drift.

## Cross-reference
- HANDLED_STRIPE_EVENTS set: src/lib/webhooks/stripe-events.ts
- Webhook handler: src/app/api/stripe/webhook/route.ts
- Pattern reference: references/patterns/40-WEBHOOKS.md § Bidirectional event coverage
```

### Template: `13_secret_custody.md`

```markdown
# Evidence: Secret Custody Matrix

## Audit date
2026-MM-DD

## Custody table
[per-secret rows; see 110-OPERATIONS.md § Secret custody matrix template]

## Rotation log (last 12 months)
| Secret | Rotation date | Reason | Rotated by | Verified by |
|--------|---------------|--------|------------|-------------|
| STRIPE_SECRET_KEY | 2026-04-15 | Quarterly cadence | <name> | <name> |
| STRIPE_WEBHOOK_SECRET | 2026-01-12 | Annual + endpoint URL change | <name> | <name> |
| ... | ... | ... | ... | ... |

## Compromise procedure
[link to runbook docs/runbooks/secret-rotation.md]

## Drift-guards
- secret-custody-completeness.test.ts: every billing env var listed in src/env.ts has a matrix row.
- secret-custody-rotation-cadence.test.ts: each secret's `last_rotated` field is within its documented cadence.
```

### Template: `14_drift_guards.md`

```markdown
# Evidence: Drift-Guard Tests

## Drift-guards in CI

| Test name | What it pins | Pattern reference | Last result |
|-----------|--------------|-------------------|-------------|
| cronsThatMustExclude.test.ts | Every cron imports analytics/exclusions | 100-ANALYTICS § exclusions | PASS |
| WebhookErrorCodes-completeness.test.ts | Every error code emitted is in registry | 20-CONSTANTS-AND-ENV § Error codes | PASS |
| BillingEnv-completeness.test.ts | Every env var read is in env.ts schema | 20-CONSTANTS-AND-ENV § env.ts | PASS |
| StripeApiVersion-singleSource.test.ts | API version literal exists in exactly one place | 20-CONSTANTS-AND-ENV § STRIPE_API_VERSION | PASS |
| LastEventAtCoverage.test.ts | Every UPDATE on subscriptions/orgs has WHERE last_event_at | 50-SECURITY § replay-staleness | PASS |
| PaymentEventsPayloadIsJsonb.test.ts | Schema asserts payload column type | 10-SCHEMA § payment_events | PASS |
| StripeEventCoverage-drift.test.ts | HANDLED_STRIPE_EVENTS matches Dashboard config | 40-WEBHOOKS § bidirectional | PASS |
| RLS-policies-present.test.ts | Every billing table has RLS policies | 50-SECURITY § Supabase RLS | PASS |
| ... | ... | ... | ... |

## Coverage of Polish Bar dimensions
| Polish Bar dimension | Drift-guard? | Test name |
|----------------------|--------------|-----------|
| 1 Provider-Authority | partial | provenance-coverage.test.ts |
| 2 Layered-Defense | n/a | (architectural; not asserted by single test) |
| 3 Idempotent-Writes | ✓ | recordWebhookEvent-dedup.test.ts |
| 4 Hijack defense | ✓ | hijack-defense-coverage.test.ts |
| 5 Stale-event ordering | ✓ | LastEventAtCoverage.test.ts |
| 6 200-on-error | ✓ | webhook-200-on-error.test.ts |
| 7 Synchronous refund invalidation | ✓ | refund-cache-invalidation.test.ts |
| 8 Analytics exclusions | ✓ | cronsThatMustExclude.test.ts |
| 9 Provenance | ✓ | provenance-coverage.test.ts |
| 10 Cron defenses | ✓ | cron-advisory-lock.test.ts |
| 11 Secret custody | ✓ | secret-custody-completeness.test.ts |
| 12 Pin-the-contract | n/a | (every test is a pin; no meta-test) |
| 13 Type-derive | ✓ | StripeApiVersion-singleSource.test.ts |
| 14 Priority-aware queue | ✓ | email-priority-coverage.test.ts |
| 15 Bidirectional coverage | ✓ | StripeEventCoverage-drift.test.ts |
```

### Template: `19_change_management.md`

```markdown
# Evidence: Change Management

## Process
- All billing-touching changes go through PR review (≥1 approver from billing team).
- Phase 7 fresh-eyes ran for the last <N> billing PRs; results in `.billing_workspace/phase7_*` history.
- Drift-guards block merge on regression.
- Provider-catalog audit runs nightly; alerts on Dashboard drift.
- Postmortems filed within 1 week of any P0/P1 incident.

## Recent billing PRs (last 30 days)
| PR | Title | Reviewer(s) | Drift-guards passed | Merged at |
|----|-------|-------------|----------------------|-----------|
| #142 | Add Stripe SCA routing | <names> | ✓ | 2026-04-30 |
| ... | ... | ... | ... | ... |

## Drift-guard CI logs (last 7 days)
[summary statistics: how many runs, pass rate, any failed runs investigated]

## Postmortem completion rate
- P0 incidents in last 12 months: 1; postmortem filed: 1; action items closed: 5/5.
- P1 incidents in last 12 months: 4; postmortems filed: 4; action items closed: 17/19.
```

---

## Known issues

For gaps that ARE NOT closed in the evidence pack (the user knows about them but can't fix in time for the audit), document each in `known_issues/<bead-id>__<short>.md`:

```markdown
# Known Issue: <short>

## Bead / issue ID
bd-...

## Description
<what the gap is>

## Risk classification
- Score (per RISK-SCORING.md): <1-9>
- Affected control(s): <SOC2 CC.x.x; ISO A.x.x.x>
- Compensating control: <if any>

## Remediation plan
- Owner: <name>
- Target completion: <date>
- Status: <open | in_progress | scheduled>

## Acceptance criteria for closure
[what evidence will replace this known-issue entry]
```

The auditor sees these and asks about remediation. Honesty here is better than a defective evidence file.

---

## Sign-off attestations

Two minimum:

```markdown
# attestations/engineering_lead_signoff.md

I, <name>, Engineering Lead at <company>, attest that:

1. The evidence pack assembled at .billing_workspace/phase10_evidence_pack/
   accurately reflects the state of the billing system as of <YYYY-MM-DD>.
2. All drift-guard tests listed in evidence/14_drift_guards.md were passing
   on the last CI run before this attestation.
3. All known issues listed in known_issues/ are tracked with owners and
   target completion dates.
4. No material gaps exist beyond those documented as known issues.

Signed: <name>
Date: <YYYY-MM-DD>
```

```markdown
# attestations/compliance_officer_signoff.md

[similar; from the compliance officer / auditor liaison]
```

---

## Auditor-facing README

`phase10_evidence_pack/README.md`:

```markdown
# Billing Compliance Evidence Pack

## Audit window
<YYYY-MM-DD> to <YYYY-MM-DD>

## Framework
SOC2 Type 2 [or whatever applies]

## Pack contents
See controls_index.md for the control → evidence mapping.

## How to verify a control
1. Find the control in controls_index.md.
2. Open the linked evidence file(s).
3. The "Findings" section is the verification output; the "Cross-reference" section points to the source code.
4. If you need to re-verify live, the "Source" / "Source command" line gives the command (read-only; safe to re-run).

## Known issues
See known_issues/ — gaps the engineering team is aware of with remediation plans.

## Sign-offs
- attestations/engineering_lead_signoff.md
- attestations/compliance_officer_signoff.md

## Contact
[on-call escalation; see evidence/18_oncall_doc.md]
```

---

## Compliance-pass discipline

- **No new features.** Auditor needs a stable target.
- **No new schema columns.** Same.
- **Read-only verification only.** No DB / provider mutations during the audit window.
- **All evidence is reproducible.** The "Source command" line lets the auditor re-run live.
- **Counts-only redaction.** Same as VERIFICATION-FIRST.md.
- **Honest known-issues list.** Better than papered-over evidence.
- **Sign-offs are real.** The engineering lead's signature carries legal weight.

---

## What to do when the auditor asks for something not in the pack

The pack should anticipate ~80% of auditor questions. The remaining 20%:

- If the question is a simple verification: produce a short ad-hoc evidence file in `evidence/ad_hoc/<question-slug>.md` using the same envelope.
- If the question reveals a gap not in `known_issues/`: file a new known-issue + remediation plan; show the auditor the pack-update.
- If the question requires source code reading: walk the auditor through the relevant Polish Bar dimension + pattern bundle. Use `references/patterns/...` as the pedagogical material.

Never make up an answer to satisfy an auditor. "I don't know; I'll verify and get back to you within 24h" is the right response.
