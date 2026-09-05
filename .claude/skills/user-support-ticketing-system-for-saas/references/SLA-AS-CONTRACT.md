# SLA As Contract — Pricing, Commitments, Service Credits

[SLA-ENGINE.md](SLA-ENGINE.md) describes the *technical* SLA: deadlines, status, breach computation. This file is the *commercial* layer — turning the technical SLA into pricing tiers, contractual commitments, service credits, and compliance reports that affect revenue.

When SLAs become contractual (not just internal targets), several things change: breach has financial consequences, customers get audit rights, and the system must produce defensible compliance reports.

## Three Levels Of SLA Maturity

| Level | What it is | Revenue impact |
|---|---|---|
| **Internal target** | Team aspirations; no customer commitment | Indirect (retention, NPS) |
| **Public commitment** | Marketing-page promise; goodwill remediation on breach | Soft (reputation) |
| **Contractual commitment** | Signed agreement; service credits or refunds on breach | Direct (revenue impact) |

Most teams start at Level 1 (the technical SLA from this skill). Level 2 happens when the marketing page makes a promise. Level 3 happens when a procurement process demands signed SLAs in the master service agreement (MSA).

## Service Credit Math

The most common contractual SLA structure: when monthly SLA delivery falls below threshold, customer gets a percentage credit on the next invoice.

```
Monthly SLA Compliance < 99.9%  → 5% credit
Monthly SLA Compliance < 99.5%  → 10% credit
Monthly SLA Compliance < 99.0%  → 25% credit
Monthly SLA Compliance < 95.0%  → 50% credit
```

(Numbers vary by contract; encode them in config, not code.)

### Compliance Calculation

```ts
async function computeMonthlySlaCompliance(orgId: string, month: string): Promise<{ compliancePct: number; creditPct: number; details: object }> {
  const range = monthBoundsUtc(month);
  const tickets = await listTicketsForOrgInRange(orgId, range);
  const totalCommitments = tickets.length;                       // # of tickets with SLA promise
  const breached = tickets.filter(t => t.slaStatus === "breached").length;
  const compliancePct = totalCommitments === 0 ? 100 : ((totalCommitments - breached) / totalCommitments) * 100;

  const config = await getSlaContractFor(orgId);
  const creditPct = config.creditTiers
    .sort((a, b) => a.threshold - b.threshold)
    .find(t => compliancePct < t.threshold)?.creditPct ?? 0;

  return { compliancePct: round(compliancePct, 2), creditPct, details: { totalCommitments, breached, range } };
}
```

Run monthly per-org; surface in `/admin/orgs/[orgId]/sla-report`.

### Schema For Contracts

```ts
export const slaContracts = pgTable("sla_contracts", {
  id: uuid().primaryKey().defaultRandom(),
  orgId: uuid().references(() => organizations.id, { onDelete: "cascade" }).notNull(),
  effectiveFrom: timestamp({ withTimezone: true }).notNull(),
  effectiveUntil: timestamp({ withTimezone: true }),

  // The SLA promises
  firstResponseHours: jsonb().notNull(),                          // { p0: 1, p1: 2, p2: 4, p3: 8 }
  resolutionHours: jsonb().notNull(),
  hoursModel: text().notNull(),                                    // 'wallclock' | 'business_hours'
  uptimePct: numeric(),                                            // optional uptime promise

  // The credit / refund mechanism
  creditTiers: jsonb().notNull(),                                  // [{ threshold: 99.9, creditPct: 5 }, ...]
  creditAppliedAs: text().notNull(),                               // 'invoice_credit' | 'refund' | 'extension'

  // Compliance reporting
  reportingCadence: text().notNull(),                              // 'monthly' | 'quarterly'
  reportingFormat: text().notNull(),                               // 'pdf' | 'csv' | 'api'

  contractDocumentUrl: text(),                                     // pointer to signed PDF
  signedAt: timestamp({ withTimezone: true }),
  signedBySupportLead: uuid().references(() => users.id),
  signedByCustomerName: text(),
}, t => [
  index("sla_contracts_org_idx").on(t.orgId, t.effectiveFrom),
]);
```

## Compliance Report Generation

Monthly cron generates per-org compliance reports:

```ts
async function generateMonthlyReports() {
  const orgs = await listOrgsWithActiveSlaContracts();
  for (const org of orgs) {
    const month = lastMonth();
    const compliance = await computeMonthlySlaCompliance(org.id, month);
    const report = await renderReport(org, compliance);
    await sendReportEmail(org.contractContacts, report);
    await archiveReport(org.id, month, report);

    if (compliance.creditPct > 0) {
      await issueServiceCredit({
        orgId: org.id,
        month,
        creditPct: compliance.creditPct,
        complianceFinding: compliance,
      });
    }
  }
}
```

### The Report Itself

```
ACME CORP — SLA COMPLIANCE REPORT
April 2026

Period: April 1 – April 30, 2026
Reporting Cadence: Monthly
Generated: May 1, 2026

═══════════════════════════════════════════
SUMMARY
═══════════════════════════════════════════
Tickets in period:                         87
SLA breaches:                               2
SLA compliance:                         97.7%
Tier threshold for credit:              99.0%
Credit issued:                          25.0%

═══════════════════════════════════════════
BREACH DETAILS
═══════════════════════════════════════════
Ticket #ABC12345  P1  filed Apr 12  responded Apr 14 (44.5h late)
  Reason: cron stalled during a vendor outage; root cause fixed Apr 13.
  Postmortem: link

Ticket #DEF67890  P0  filed Apr 19  responded Apr 19 (1.2h late)
  Reason: on-call engineer paged but missed escalation; coverage policy updated.
  Postmortem: link

═══════════════════════════════════════════
PER-PRIORITY BREAKDOWN
═══════════════════════════════════════════
Priority    Tickets   Compliance   Median Response   p95
P0                 1        0.0%             5.2h    5.2h
P1                 6       83.3%             1.8h    44.5h
P2                47      100.0%             3.4h    3.9h
P3                33      100.0%             7.1h    7.8h

═══════════════════════════════════════════
CREDIT APPLIED
═══════════════════════════════════════════
Per Master Service Agreement Section 4.2,
SLA compliance < 99.0% triggers a 25% credit
on the May 2026 invoice.

Credit amount: $1,250.00
To be applied to: Invoice INV-2026-05-XXX

═══════════════════════════════════════════
APPENDIX
═══════════════════════════════════════════
Methodology: All tickets created in the reporting
period are evaluated against their committed first-
response and resolution times per the contract dated
[date]. SLA pause windows for "awaiting customer"
status are excluded from breach calculation.

Audit trail: Available on request.
```

PDF + CSV. Both signed (server-side digital signature). Customer's procurement team gets exactly what they need for compliance.

## Audit Rights

Enterprise contracts often grant audit rights — customer can request raw ticket data backing the compliance report:

```ts
// /api/customer/sla-audit
// Returns the raw data underlying a compliance report
async function generateAuditPackage(orgId: string, month: string) {
  const range = monthBoundsUtc(month);
  const tickets = await listTicketsForOrgInRange(orgId, range);
  const auditEvents = await listAuditEventsForTickets(tickets.map(t => t.id));
  return {
    method: "Per-ticket SLA evaluation against contract",
    contractEffectiveAt: ...,
    range,
    tickets: tickets.map(toAuditShape),
    auditEvents: auditEvents.map(toAuditShape),
    schemaHash: hashOf(currentSchemaVersion()),
  };
}
```

The audit package is signed (HMAC + timestamp) so the customer can prove they received it unmodified. Permission-gated; rate-limited (1 per month per org).

## Service Credit Issuance

When a credit is owed:

```ts
async function issueServiceCredit(opts: { orgId: string; month: string; creditPct: number; complianceFinding: any }) {
  // 1. Create a credit memo in the billing system (Stripe / internal)
  const memo = await stripe.creditNotes.create({
    customer: getStripeCustomerId(opts.orgId),
    invoice: nextInvoiceFor(opts.orgId),
    amount: computeCreditAmount(opts.orgId, opts.creditPct),
    reason: `SLA compliance credit — ${opts.month}`,
    metadata: { slaComplianceMonth: opts.month, creditPct: opts.creditPct },
  });
  // 2. Audit row
  await db.insert(auditLog).values({
    actionType: "sla_credit_issued",
    entityType: "organization",
    entityId: opts.orgId,
    metadata: { month: opts.month, creditPct: opts.creditPct, stripeMemoId: memo.id, complianceFinding: opts.complianceFinding },
  });
  // 3. Notify customer
  await sendSlaCreditEmail(opts.orgId, memo);
}
```

Customer gets an email: "Per your SLA agreement, we've applied a 25% credit to your next invoice for April's missed compliance. Thanks for your patience while we addressed the underlying issues."

Idempotent: the unique constraint on `(orgId, month, "sla_credit")` prevents double-credits.

## Sales-Material Credibility

Public SLAs become marketing assets when backed by a real compliance dashboard. Reference [CREATIVITY-AND-INNOVATION.md](CREATIVITY-AND-INNOVATION.md) Innovation 14 — the pricing page literally shows:

```
ENTERPRISE TIER
4-hour first response, 24/7
─────────────────────────────
Last 90 days delivered:
  Median: 1.2h
  p95: 3.4h
  Compliance: 99.7%

[Live data, refreshed hourly]
```

This is contractually-credible because the same numbers feed customer compliance reports. The website can't lie about something the customer audits monthly.

## Procurement-Ready Documentation

Enterprise procurement teams ask for:

1. **SOC 2 / ISO 27001** evidence — the SLA audit trail is part of this
2. **Sample compliance reports** — give them a redacted real one, not a marketing template
3. **Mean Time To Detect (MTTD) / Mean Time To Respond (MTTR)** numbers
4. **Escalation matrix** with named contacts
5. **Disaster recovery / business continuity** plans

The support system contributes the first three; ops contributes the rest.

## Per-Customer SLA Customization

Some enterprise customers negotiate custom SLAs (1-hour P0 instead of standard 2). Wire:

```ts
async function getEffectiveSlaConfig(orgId: string | null, priority: TicketPriority): Promise<SlaConfig> {
  if (orgId) {
    const contract = await getActiveContractFor(orgId);
    if (contract) return contract.firstResponseHours;
  }
  return DEFAULT_SLA_CONFIG[isEnterprise ? "enterprise" : "individual"];
}
```

Per-org override is the most common shape. Document the negotiated contract in `slaContracts` so it's discoverable.

## Customer-Visible SLA Dashboard

Every SLA-covered customer gets a dashboard:

```
/account/sla
─────────────────
Your SLA: Enterprise (4hr first response)
This month: 12 tickets, 11 within SLA (91.7%)
Last month: 100% compliance, $0 credit issued

[View detailed report]  [Audit raw data]  [Download PDF]
```

Self-service > monthly email. Reduces support questions about SLA status by ~80%.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Marketing SLA tighter than contract SLA | Customer sees marketing, signs contract, breach math differs; argument |
| Credit issued by manual process | Inconsistent; missed credits = breach of contract |
| Compliance report generated on-demand at customer request | Slow; customer thinks you're hiding the number |
| No audit-package endpoint | Procurement loses faith |
| SLA pause for `awaiting_customer` not documented in contract | Customer disputes the calculation |
| Credit amount disputable | Use the same compliance math the customer can replicate |
| No methodology section in compliance report | Looks like marketing, not audit |
| Customer-tier SLA hardcoded | Custom enterprise contracts can't be modeled |
| Compliance dashboard shows different numbers than report | Trust collapse |
| Retroactive SLA changes without contract amendment | Sales / legal exposure |

## Wire Points Checklist

- [ ] `slaContracts` table with effective dates + credit tiers + reporting cadence
- [ ] Per-org SLA override in `getEffectiveSlaConfig`
- [ ] Monthly compliance computation cron
- [ ] Compliance report generator (PDF + CSV) with methodology section
- [ ] Service credit issuance with idempotency on `(orgId, month)`
- [ ] Customer-visible self-service SLA dashboard at `/account/sla`
- [ ] Audit package endpoint (rate-limited, permission-gated)
- [ ] Pricing page shows live compliance numbers (per-tier)
- [ ] Same numbers fed customer-facing dashboard, audit package, and pricing page
- [ ] SLA contract changes require amendment; no retroactive change
- [ ] Stripe credit memo integration with audit trail
- [ ] Email notification when credit issued
- [ ] Test: tier breach → expected credit issued + emailed within 5 minutes of reporting cadence
- [ ] Test: audit package signature verifies
