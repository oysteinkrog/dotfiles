# Billing Compliance Evidence Pack

> **Template.** Copy to `phase10_evidence_pack/README.md`. Fill in for each compliance review.

## Audit window
<YYYY-MM-DD> to <YYYY-MM-DD>

## Framework
<SOC2 Type 2 | ISO 27001:2022 | Customer security questionnaire | Combined>

## Pack contents
See `controls_index.md` for the control → evidence mapping.

```
phase10_evidence_pack/
├── README.md                          (this file)
├── controls_index.md                  (control → evidence mapping)
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
│   └── <bead-id>__<short-description>.md
└── attestations/
    ├── engineering_lead_signoff.md
    └── compliance_officer_signoff.md
```

## How to verify a control

1. Find the control in `controls_index.md`.
2. Open the linked evidence file(s).
3. The "Findings" section is the verification output; the "Cross-reference" section points to source code.
4. If you need to re-verify live, the "Source command" line gives the command (read-only; safe to re-run).

## Known issues
See `known_issues/` — gaps the engineering team is aware of with remediation plans. Each has:
- Risk classification (per `references/methodology/RISK-SCORING.md`).
- Affected control(s).
- Compensating control (if any).
- Remediation owner + target completion date.

## Sign-offs
- `attestations/engineering_lead_signoff.md` — Engineering Lead attestation.
- `attestations/compliance_officer_signoff.md` — Compliance Officer attestation.

## Contact
On-call escalation: see `evidence/18_oncall_doc.md`.

## How this pack was generated

This evidence pack is assembled by the `saas-billing-patterns-for-stripe-and-paypal` skill in `compliance-pass` mode. The pack:

- Is **continuously generated** — daily provider-catalog audit runs in CI; artifacts retained 2 years.
- Uses **read-only credentials** — Stripe restricted API key + PayPal app with read-only scopes.
- Applies **counts-only redaction** — no customer rows, no PII, no tokens, no full URLs.
- Has **drift-guards in CI** — every implicit invariant has a test.

For methodology, see `references/methodology/COMPLIANCE-EVIDENCE.md` in the skill.
