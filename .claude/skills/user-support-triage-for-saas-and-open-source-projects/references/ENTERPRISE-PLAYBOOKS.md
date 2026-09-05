# Enterprise Playbooks — DPA, Security Questionnaires, And Custom MSAs

A consumer SaaS support pipeline and an enterprise-customer support pipeline are different jobs sharing some vocabulary. This file describes the enterprise-shape work the triage skill encounters: data processing addenda (DPAs), security questionnaires (SIG, CAIQ, custom), service-level agreements at contract scope, MSA negotiation support, vendor-of-record obligations, and the enterprise escalation rituals that don't exist in SMB.

> **Core insight:** when a customer is paying $50k+/year, the support function becomes a contract-execution function. The reply to a question like "do you support our SOC2-required encryption-at-rest" is not a customer-service answer — it is a *legal-and-security commitment* that travels into the customer's audit. Treating it as routine triage exposes both companies.

This file complements `EVIDENCE-CHAIN-OF-CUSTODY.md` (legal-hold), `runbooks/SECURITY-DISCLOSURE.md` (vulnerability inbound), and `MULTI-TIER-SUPPORT-ORG.md` (where enterprise often deserves its own tier). Treat enterprise tickets as the high-stakes tail of the long-tail strategy from `PARETO-AND-LONG-TAIL.md`.

---

## What "Enterprise" Means In Triage Context

Project-specific definitions in `05-policies.md`. Common signals:

| Signal | Likely enterprise |
|---|---|
| Annual contract via MSA + Order Form (not click-through TOS) | Yes |
| Has a named CSM / AE on the customer's side | Yes |
| ARR > project's enterprise threshold (often $25k-$100k+) | Yes |
| Has signed DPA with you | Likely |
| Multi-user account with role separation, SCIM, SSO | Likely |
| Operates under regulatory regime (HIPAA, FINRA, SOC2 audit, etc.) | Likely |
| Procurement / legal / security team on the buyer side | Yes |
| Custom contract terms (uptime SLA, custom data retention, custom audit rights) | Yes |
| Reseller / VAR-mediated relationship | Often special handling |

When two or more fire, the ticket is enterprise-shape; pipelines change.

---

## The Common Enterprise Inbounds

### 1. DPA (Data Processing Addendum) request

The customer's legal/privacy team sends: "please countersign our DPA." Or: "please send your DPA so our team can review."

```
[OPERATOR-LOCAL: 🏛 ENTERPRISE — DPA inbound]
1) DO NOT auto-handle. DPA is contractual.
2) Route to the project's DPA contact (legal counsel / GC / DPO).
3) If the project has a standard DPA: confirm version, send.
4) If the customer's DPA arrived for countersignature:
   - DO NOT countersign without counsel review
   - Check for non-standard clauses (cross-border transfer,
     audit rights, sub-processor disclosure, breach-notification
     timeline, GDPR Standard Contractual Clauses module selection)
   - Counsel proposes redlines
5) Track in the customer's account: "DPA in negotiation" status;
   block deal close / ARR-uplift on this if internal policy says so
6) Once executed: add to evidence repository per
   EVIDENCE-CHAIN-OF-CUSTODY.md
```

If the project doesn't yet have a standard DPA, that's a gap. `12-gap-dispositions.md` should flag it. Without a standard DPA, every customer requires custom counsel work; with one, most close in <1 week.

### 2. Security questionnaire

A customer's security team sends a multi-page document (CAIQ, SIG-Lite, CIS-AWS, custom). Or a TPRM (Third-Party Risk Management) portal invitation (OneTrust, Whistic, Vanta, Drata, SecurityScorecard).

```
[OPERATOR-LOCAL: 🏛 ENTERPRISE — Security questionnaire inbound]
1) DO NOT auto-handle. Each answer is a security commitment.
2) Identify the format:
   a) Standardised (CAIQ v4, SIG, ISO 27001 SoA-aligned) →
      project should have a master answer set; map question→answer
   b) Custom questionnaire → manual; counsel reviews unusual clauses
   c) TPRM portal → grant access to project's security lead;
      portal-specific workflow
3) Identify deal stage:
   - Pre-sales: route to AE + security lead; deal-blocking SLA
   - Renewal: same as pre-sales; renewal can be deal-blocking
   - Post-sale audit: route to security; less time-pressured
4) Track timeline; questionnaires are typically 5-15 business
   days expected turnaround
5) Maintain an evergreen "security posture" document mirroring
   the master answer set; questionnaires copy from there
```

The asymmetry: security questionnaires are 80% repetitive across customers. A maintained master answer set turns a 2-week effort into a 2-day effort. Without it, security becomes the support bottleneck. Worth the investment by year 2.

### 3. Custom MSA negotiation

The customer's legal team proposes redlines on the standard MSA. Routine for any enterprise sale.

```
[OPERATOR-LOCAL: 🏛 ENTERPRISE — MSA redlines inbound]
1) NEVER agent-led. Counsel + AE + sales-ops.
2) Triage role: route, track timeline, maintain context.
3) Common high-friction clauses:
   - Uptime SLA percentages (99.5 vs 99.9 vs 99.95 vs 99.99)
   - Service credits (prorated, capped, applied as)
   - Data residency (EU-only, US-only, multi-region)
   - Audit rights (frequency, scope, NDA)
   - Liability caps (1x annual fees vs 2x vs unlimited for IP/breach)
   - Indemnification scope (mutual, one-way, data breach carve-outs)
   - Termination convenience (with vs without cause; notice period)
4) Track every back-and-forth in evidence repository
5) Flag deal-blocking redlines to AE within 24h
```

For triage, the artefact discipline matters: every legal exchange goes to the per-customer evidence repo; nothing happens in Slack alone.

### 4. Custom SLA + uptime monitoring

Enterprise customers often negotiate uptime guarantees. Common shape:

| Tier | Uptime | Service credit if missed |
|---|---|---|
| Standard | 99.5% (~3.6h/month) | None / customer pays |
| Mid | 99.9% (~43m/month) | 5-10% of monthly fees per breach |
| High | 99.95% (~22m/month) | 25% of monthly fees per breach |
| Premium / regulated | 99.99% (~4m/month) | 50%+ of monthly fees per breach |

When an outage breaches the customer's SLA, the comms switch from generic outage messaging to credit-issuance:

```
[OPERATOR-LOCAL: 🏛 ENTERPRISE — Outage SLA breach]
1) Coordinate with Pipeline E (Outage), but layer:
2) For affected enterprise customers, calculate per-customer impact:
   - Their measured uptime for the period
   - Whether SLA threshold breached
   - Service credit owed per their contract
3) Proactive outreach (per PROACTIVE-SUPPORT.md) includes:
   - Specific impact to their account
   - Specific credit issued (don't wait for them to claim)
   - Postmortem timeline commitment
4) Issue credit to billing within the contract's window (often
   30 days from incident)
5) Track in `📈 OUTCOME` — these are high-cost incidents
```

Customers have audit rights on uptime claims. The discipline of "we issued a credit before they asked" is the difference between renewal-positive and renewal-question.

### 5. Custom data retention / deletion

Customer's legal-and-compliance team requires specific data retention:

- "All our data must be deleted within 30 days of subscription termination"
- "We need 7-year retention for these specific records (regulatory)"
- "Backups containing our data must be deleted within 60 days"
- "Audit logs of access to our data, available on request"

These often live in DPA addenda or custom MSA. Triage role:

```
[OPERATOR-LOCAL: 🏛 ENTERPRISE — Custom retention enforcement]
1) Verify in the customer's contract / DPA what retention applies
2) On termination:
   - Schedule deletion per timeline
   - Confirm to customer that deletion is scheduled with date
   - Confirm to customer when deletion completed
   - Provide certificate-of-deletion if contractually required
3) Distinguish soft-delete (recoverable) from hard-delete (gone)
4) Backups: if they're in scope, confirm backup-retention purge timing
5) Track in evidence repository for audit
```

Failing to honor a contracted retention obligation is a contract breach with quantifiable damages. This is one of the fastest paths to a regulator inquiry.

### 6. Sub-processor disclosure / change

Many DPAs require:
- Initial list of sub-processors
- Notification of new sub-processors with a window for objection (often 30 days)
- Customer's right to object to a specific sub-processor

When the project changes sub-processors:

```
[OPERATOR-LOCAL: 🏛 ENTERPRISE — Sub-processor change]
1) Maintain master sub-processor list (publicly or per-customer)
2) When change planned:
   - 30+ days advance notice to enterprise customers per their DPA
   - Notification format follows DPA spec (not generic blog post)
   - Track which customers acknowledged / objected
3) On objection:
   - Counsel-led negotiation
   - Worst case: termination clause activates
4) If silent acceptance assumed by DPA: document the notification date
```

### 7. SOC2 / ISO27001 / certification ask

"Do you have SOC2 Type II?" Increasingly common in enterprise sales. If yes: send report under NDA. If no: be honest about timeline; never claim certification you don't have.

```
[OPERATOR-LOCAL: 🏛 ENTERPRISE — Certification ask]
1) Project's stance documented in 05-policies.md:
   - Certifications held (with current valid period)
   - Certifications in progress (with target completion)
   - Certifications declined / not pursued
2) For "report under NDA" requests:
   - Verify NDA in place (or send standard NDA)
   - Send report via secure channel
   - Track who has the report (NDA tracking)
3) For "in progress" status:
   - Honest timeline; don't promise dates that won't hold
   - Note compensating controls in absence of certification
4) NEVER claim certification you don't have. Misrepresentation
   in a sales context is fraud.
```

---

## The Customer-Side Contacts

Enterprise customers have multiple buyer-side roles. Knowing which is asking shapes the reply:

| Role | What they're optimising for | What they want from you |
|---|---|---|
| End user | Solve their immediate problem | Same as any user |
| Admin | Account management, user provisioning | Operational answers |
| IT lead | Integration, SSO, compliance fit | Technical depth |
| Security lead | Risk reduction | Honest gap assessment |
| Procurement | Contract terms, vendor consolidation | Clear contract artefacts |
| Legal | Risk transfer, contract clarity | Counsel-cleared positions |
| Executive sponsor | Outcomes, business case | Business-impact framing |

The same underlying issue (e.g., "API rate limits hit") gets different framing for each. End user wants the rate-limit raised; IT lead wants the architecture rationalised; security lead wants the limits documented; legal wants to know if breach implications are a thing. Triage agents asking "who is this person, in what role" before drafting saves rounds of confusion.

---

## The Quarterly Business Review

Enterprise relationships often include a Quarterly Business Review (QBR). Support's role:

- Aggregate the quarter's tickets per customer
- Identify themes specific to that account
- Compute their actual uptime + SLA performance
- Compute their actual usage + headroom in plan
- Compute their support-ticket volume + theme distribution
- Surface to CSM for the QBR deck

This is *compounding work* per `PARETO-AND-LONG-TAIL.md` 70/20/10. A QBR-ready data dump is the output. Without it, CSMs build it manually each quarter, badly.

A useful template:

```
QBR Support Summary — [Customer] — [Q-X-YYYY]

Volume
- Tickets opened: N (vs Q-1: M)
- Tickets resolved: N
- Avg TTR: X hours (vs benchmark Y)

Themes
- Top 3 themes (with counts)
- Recurring themes from Q-1 still appearing

SLA & Reliability
- Account-level uptime: X.XX%
- SLA tier: 99.95%
- Service credits issued: $N (incidents: I-1, I-2)

Usage
- Active users: N (cap: M)
- API calls: N (cap: M)
- Storage: N (cap: M)
- Approaching any limits?

Support friction
- Cases that took >2 replies to resolve: N
- Cases escalated to L3: N
- Customer-effort score: X
- Open product tickets blocking customer: list

Recommendations
- Account growth signal: [...]
- Risk signal: [...]
```

---

## Procurement And Renewals

Enterprise renewals are predictably contentious. Patterns:

- 60-90 days pre-renewal: customer's procurement team starts engaging
- Common asks:
  - "Justify the price increase"
  - "We'd like to multi-year contract for a discount"
  - "We're considering competitor X; convince us"
  - "We're consolidating vendors; how does your roadmap align"
- Common pivots:
  - Custom DPA renegotiation
  - Custom MSA changes (often: lower liability cap)
  - Adding/removing usage tiers

Triage's role: ensure the customer's *support history* is positive going into renewal. This is downstream of every interaction in the prior year. The 🔁 LOOPBACK loop and ✓ CONFIRM discipline that protects against bad sends matters most for enterprise customers because each interaction is a renewal vote.

---

## The Anti-Patterns Specific To Enterprise

| Anti-pattern | Why it bites |
|---|---|
| Treating enterprise ticket like consumer ticket (template + close) | Mis-calibrated; enterprise expects depth |
| Promising terms in support that aren't in the contract | Creates contract claim out of customer-service exchange |
| Sending generic "we apologize for any inconvenience" to a CISO | Reads as not understanding their audit obligations |
| Routing security questionnaire to L1 | Wrong tier; answers carry security commitment |
| Auto-issuing credit beyond the contracted amount | Sets precedent; doesn't fix root cause |
| Forgetting they have an AE/CSM | Triage acts unilaterally; account team finds out from customer |
| Disclosing operational details that weren't asked for | Customer's security team flags them |
| Treating enterprise outage as a regular outage | Different SLA, different comms, different credit math |
| Slack-only legal exchanges | Discoverability nightmare; should be in evidence repo |

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🏛 ENTERPRISE operator | Switch to enterprise register and process |
| Pipeline AA (Enterprise DPA / Security questionnaire) | Dedicated pipeline |
| Pipeline E (Outage) | Layer enterprise SLA breach handling |
| Pipeline U (Compliance / regulator) | Often initiated via enterprise contracts |
| 05-policies.md | Project's enterprise threshold, named contacts, DPA/SLA defaults |
| MULTI-TIER-SUPPORT-ORG.md | Enterprise-tier separation |
| EVIDENCE-CHAIN-OF-CUSTODY.md | Enterprise legal exchange retention |

---

## Cross-References

- [EVIDENCE-CHAIN-OF-CUSTODY.md](EVIDENCE-CHAIN-OF-CUSTODY.md) — legal exchange retention
- [runbooks/SECURITY-DISCLOSURE.md](runbooks/SECURITY-DISCLOSURE.md) — security inbound
- [MULTI-TIER-SUPPORT-ORG.md](MULTI-TIER-SUPPORT-ORG.md) — enterprise tier
- [COMPENSATION-CALCULUS.md](COMPENSATION-CALCULUS.md) — service credit math
- [CRISIS-COMMS.md](CRISIS-COMMS.md) — enterprise outage comms
- [PARETO-AND-LONG-TAIL.md](PARETO-AND-LONG-TAIL.md) — long-tail investment
- [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md) — enterprise theme tracking
