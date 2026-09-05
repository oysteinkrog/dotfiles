# Bundle B120 — Compliance Evidence Pack

> **Where this comes from.** Track A from operationalizing-expertise + § 78a.6b + the source guide's secret custody patterns + extension for SOC2 / ISO / customer security questionnaires.

This is the bundle that turns "we have a billing system" into "we can prove it to an auditor." Required for `compliance-pass` mode; nice-to-have but valuable in T4+ tiers.

The methodology is in `references/methodology/COMPLIANCE-EVIDENCE.md`. THIS bundle is about the patterns that produce auditor-ready evidence.

---

## Pattern 1 — Continuous evidence over snapshot evidence

**Snapshot evidence** = "we ran the audit on May 5, 2026, here's the artifact."
**Continuous evidence** = "the audit runs daily, here are 365 artifacts; the auditor can pick any day."

Auditors prefer continuous because:
- They can verify any day, not just the day you prepared.
- They can see drift over time.
- They can spot-check rather than relying on your prepared artifact.

Wire the audit:

```yaml
# .github/workflows/billing-audit.yml
name: Billing Audit
on:
  schedule:
    - cron: '0 8 * * *'   # daily at 08:00 UTC
  workflow_dispatch:

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/provider-diagnostics.sh
        env:
          STRIPE_SECRET_KEY: ${{ secrets.STRIPE_SECRET_KEY_READ_ONLY }}
          PAYPAL_CLIENT_ID: ${{ secrets.PAYPAL_CLIENT_ID }}
          PAYPAL_CLIENT_SECRET: ${{ secrets.PAYPAL_CLIENT_SECRET_READ_ONLY }}
      - uses: actions/upload-artifact@v4
        with:
          name: billing-audit-${{ github.run_id }}
          path: .billing_workspace/provider_audit_log.md
          retention-days: 730   # 2 years for tax
```

Use a Stripe restricted API key with read-only scopes for the audit credential. Don't run audits with the unrestricted `sk_live_*`.

---

## Pattern 2 — Per-control evidence file

Don't write a single "audit report." Write one evidence file per control. Auditors verify one control at a time.

The methodology file (`references/methodology/COMPLIANCE-EVIDENCE.md`) defines the evidence pack structure. The bundle's job is making sure every evidence file has:

- Audit date.
- Source command (so auditor can re-run).
- Evidence envelope (checked_at, environment, scope, redaction, run_by).
- Findings (structured, not prose).
- Auditor-facing summary (≤3 sentences).
- Cross-reference (to source code + pattern bundle).

---

## Pattern 3 — Drift-guards as evidence

Every implicit invariant becomes a CI test. The TEST is the evidence. The auditor reads the test name + assertion + last-run result.

```ts
// __tests__/compliance/cronsThatMustExclude.test.ts
import { glob } from 'glob';
import { readFileSync } from 'node:fs';

const MUST_EXCLUDE: ReadonlyArray<string> = [
  'src/app/api/cron/dunning-reminders/route.ts',
  'src/app/api/cron/card-expiry-warning/route.ts',
  // ... every cron that reads users/subs
];

describe('compliance: every billing cron imports analytics/exclusions', () => {
  test.each(MUST_EXCLUDE)('cron %s imports analytics/exclusions', (cronPath) => {
    const content = readFileSync(cronPath, 'utf-8');
    expect(content, `${cronPath} does not import analytics/exclusions`)
      .toMatch(/from ['"][^'"]*analytics\/exclusions['"]/);
  });

  test('every cron file is in MUST_EXCLUDE or has explicit opt-out comment', () => {
    const allCrons = glob.sync('src/app/api/cron/**/route.ts');
    const missing = allCrons.filter(c => {
      if (MUST_EXCLUDE.includes(c)) return false;
      const content = readFileSync(c, 'utf-8');
      return !/\/\/\s*analytics-exclusions:\s*not-required/.test(content);
    });
    expect(missing, `crons missing exclusions: ${missing.join(', ')}`).toEqual([]);
  });
});
```

The auditor's question "how do you ensure all crons exclude test users?" is answered by "this test runs on every PR; it asserts the import; here's the last 365 days of green CI runs."

---

## Pattern 4 — Sanitized provider diagnostic dumps

For each compliance review, generate the provider-diagnostic artifact (counts only) and commit to the evidence pack:

```bash
./scripts/provider-diagnostics.sh > evidence/provider_state_$(date +%Y%m%d).md
git add evidence/provider_state_*.md
git commit -m "audit: provider state $(date +%Y-%m-%d)"
```

The artifact is structured per § 4.7.1's "evidence envelope" shape. It proves:
- The Stripe webhook endpoint is enabled.
- The Stripe API version matches `STRIPE_API_VERSION`.
- Every configured price is active live monthly USD.
- Customer Portal config matches policy.
- Payment Links count = 0 (or in allowlist).
- No active discount coupons (or in allowlist).
- PayPal plan details match BUSINESS.PAYPAL_PLANS.
- Webhook subscriptions match HANDLED_*_EVENTS sets.

---

## Pattern 5 — Postmortems linked to controls

For SOC2 CC7.3 ("Evaluate security events") and CC7.4 ("Respond to security events"), the evidence is your postmortems.

`evidence/16_postmortems_index.md`:

```markdown
# Postmortem Index

## P0/P1 Incidents (last 12 months)

| Date | Severity | Class | Postmortem | Action items closed |
|------|----------|-------|------------|---------------------|
| 2026-04-12 | P0 | Triple-charge (Tom Hunter) | docs/postmortems/2026-04-12-triple-charge.md | 5/5 |
| 2026-02-08 | P1 | PayPal silent webhook loss | docs/postmortems/2026-02-08-paypal-silent-loss.md | 3/3 |
| 2025-11-15 | P1 | Refund cache invalidation race | docs/postmortems/2025-11-15-refund-cache-race.md | 2/2 |

## Postmortem completion rate
- P0 incidents: 1/1 (100%)
- P1 incidents: 4/4 (100%)
- All action items: 17/19 (89%)

## Trend over time
[chart or paragraph showing incident count by quarter]

## Patterns identified
- Q1 2026: 2 incidents in webhook handlers; root cause was insufficient regression testing → added drift-guards in CI (closed Q2).
- Q4 2025: 1 incident in cache layer; root cause was implicit assumption about provenance → added Polish Bar dimension 9 enforcement (closed Q1 2026).
```

The auditor's question "how do you handle security incidents?" is answered by "we have postmortems for all P0/P1 incidents in the last 12 months; here's the index; pick one to verify."

---

## Pattern 6 — Change management evidence

For SOC2 CC8.1 ("Manage changes"), the evidence is your PR review process.

`evidence/19_change_management.md`:

```markdown
# Change Management Evidence

## Process
- All billing-touching changes go through PR review.
- ≥1 approver from billing team required.
- Phase 7 fresh-eyes ran for the last <N> billing PRs.
- Drift-guards block merge on regression.
- Provider-catalog audit runs nightly; alerts on Dashboard drift.
- Postmortems filed within 1 week of any P0/P1 incident.

## Recent billing PRs (last 30 days)
| PR | Title | Reviewer(s) | Drift-guards passed | Merged at |
|----|-------|-------------|---------------------|-----------|
| #142 | Add Stripe SCA routing | <names> | ✓ | 2026-04-30 |
| ... | ... | ... | ... | ... |

## Drift-guard CI logs (last 7 days)
- Total runs: <N>
- Pass rate: <%>
- Failed runs: <list with investigations>

## CODEOWNERS
[snippet of CODEOWNERS file showing billing-team approval requirements]
```

---

## Pattern 7 — Read-only audit credentials

Don't use `sk_live_*` for audits. Create a Stripe restricted API key with read-only scopes for the audit cron:

```
Stripe Dashboard → API keys → Create restricted key
Permissions:
  - Charges: read
  - Customers: read
  - Subscriptions: read
  - Invoices: read
  - Disputes: read
  - Coupons: read
  - Promotion Codes: read
  - Payment Methods: read
  - Payment Method Configurations: read
  - Payment Links: read
  - Prices: read
  - Products: read
  - Webhook Endpoints: read
  - Events: read
  - Balance Transactions: read
  - Customer Portal Configurations: read
  - Subscription Schedules: read
  Everything else: no access
```

Store as `STRIPE_AUDIT_KEY` (separate from `STRIPE_SECRET_KEY`). Use only for `provider-diagnostics.sh`.

For PayPal: create a separate sandbox + production app for audits with the minimum required scopes.

---

## Pattern 8 — Evidence retention

For SOC2 / tax compliance:
- Postmortems: 7 years.
- Audit artifacts: 2 years (rolling).
- Settlement ledger: 7 years (tax requirement).
- Refund records: 7 years (tax + dispute defense).
- Customer support tickets touching billing: 3 years.
- Webhook payload archive: 1 year (this is `payment_events.payload`).

Build retention into your archival policy. Don't accidentally delete evidence you'll need for the next audit.

---

## Pattern 9 — Auditor-facing index

The index file is the entry point. Auditors typically navigate `controls_index.md` first, then click through to specific evidence files.

`controls_index.md` example sections:

```markdown
## SOC2 Type 2 — TSC mapping
[per-CC table]

## ISO 27001:2022 — Annex A mapping
[per-control table]

## Customer security questionnaire mapping
[per-question table; questions like "do you have a documented incident response process?" → evidence/15_runbooks_index.md + evidence/16_postmortems_index.md]
```

---

## Pattern 10 — Sanitized public-facing evidence (optional)

Some companies publish a public trust center (e.g., Vanta, Drata, SecureFrame, Trust.run). The bundle's evidence pack feeds into that.

For public-facing material:
- ALWAYS counts-only (no customer rows).
- ALWAYS env-redacted (no real account IDs / email domains).
- Sign-offs by company leadership.
- Refresh quarterly.

If your trust center is automated (Vanta integration etc.), wire the audit script's output to feed it.

---

## Polish Bar checks for B120

- [ ] Daily provider-catalog audit runs in CI; artifacts retained 2 years.
- [ ] Per-control evidence files in `evidence/` directory; one per control.
- [ ] Drift-guards in CI for every implicit invariant.
- [ ] Postmortem index up to date; completion rate ≥95%.
- [ ] Change-management process documented + recent PRs listed.
- [ ] Read-only audit credentials separate from runtime credentials.
- [ ] Evidence retention policy documented + enforced.
- [ ] Auditor-facing index file (`controls_index.md`) per framework.
- [ ] Sign-off attestations from engineering lead + compliance officer.
- [ ] Known-issues list with remediation plans.

---

## Common B120 mistakes

- **Single big "audit report" instead of per-control files.** Auditor can't verify one control without reading the whole thing.
- **Snapshot evidence only.** Auditor questions "what about between snapshots?" — no answer.
- **Drift-guards exist but never actually fail.** Test the drift-guards by intentionally breaking the invariant in a throwaway commit.
- **Audit credentials = runtime credentials.** Read-only audit key would fail closed if someone tried to mutate via it; runtime key gives unnecessary attack surface.
- **No retention policy.** Evidence deleted before auditor needs it.
- **Sanitized evidence isn't actually sanitized.** Counts-only redaction has gaps; PII leaks. Test the sanitizer.
- **Postmortems not linked to controls.** Auditor asks "show me incident response evidence"; you point to scattered docs.
- **Sign-offs are pro-forma.** Engineering lead signs without reading. Sign-offs are legal commitments; treat them as such.
