# Policies Per Category

The ticketing system codifies policy. The triage skill *operates* it. This file gives the policy templates that should live alongside the system — refund, escalation, SLA-by-tier, security disclosure timing, hostile-user response.

If your project doesn't have these documented yet, draft from these templates and have the owner sign off.

## Owner Sign-Off Preflight

Before implementation, ask the owner for one batch of decisions. Do not let the schema/API bake in unreviewed defaults.

| Decision | Why it affects code |
|---|---|
| Refund window + approver | Determines refund action visibility, audit fields, and whether agents can prepare-but-not-execute |
| Compensation authority | Determines whether the system can prepare credits/extensions/upgrades, and which actions are owner-only |
| SLA by tier and priority | Drives `slaDeadline`, cron cadence, escalation badges, and admin sort order |
| Security disclosure owner | Determines private routing, public-comment suppression, and severity timers |
| Data retention / DSAR stance | Determines soft-delete vs redact behavior for tickets/messages/audit logs |
| Hostile-user escalation | Determines lock/ban workflow, evidence retention, and who approves suspensions |
| Support channels | Determines widget/email/GitHub/third-party adapters and dedup rules |

Write the answers into the target project's `.claude/support-triage/05-policies.md`. The code can then reference policy constants knowing they were deliberate.

## Refund Policy (By Jurisdiction × Tier)

### Statutory minimums

These are non-negotiable; below them is illegal:

| Jurisdiction | Window | Conditions |
|---|---|---|
| EU (Consumer Rights Directive) | 14 days from purchase | Distance contracts; software performance must not have started without explicit consent |
| UK (CRA 2015) | 30 days for "not as described" | Plus 14 days statutory withdrawal for distance |
| California (Auto-Renewal Law) | Cancellation must be as easy as signup | Otherwise full refund of any auto-renewal |
| Australia (ACL) | "Reasonable time" for major failure | Cannot exclude with ToS |
| Canada (Consumer Protection Act) | Varies by province; typically 10 business days for unsolicited goods | |
| Most US states | No statutory window unless state-specific | But chargeback risk is real |

**Stripe / PayPal chargeback rules** override your ToS effectively — losing a chargeback dispute costs the original amount plus a fee plus reputation. Match or exceed statutory minimums.

### Project Default Policy

```
Standard refund window: 30 days from purchase.

Within window + reasonable cause (didn't work as described, unable to use,
defect): full refund, no questions.

Outside window: case-by-case discretion. Default: no refund. Escalate to
owner if customer cites:
  - Statutory right (EU/UK)
  - Defect we caused (server outage, data loss)
  - Mistake on our side (double-billed, wrong plan)

Tier-specific:
  - Free: refunds N/A (nothing paid)
  - Individual: 30-day window applies; goodwill outside window for
    non-statutory cases up to $50/year.
  - Enterprise: per the contract; default to "make whole."
```

### Decision Matrix

```
Situation                                    Action
─────────────────────────────────────────────────────
Within 30d, reasonable cause                Full refund
Within 30d, no clear cause                  Full refund (cheap retention)
Outside 30d, statutory rights apply         Full refund + cite the law
Outside 30d, defect we caused               Full refund + apology
Outside 30d, customer error / changed mind  Decline; offer credit
Chargeback already filed                    Don't dispute small ones (<$200)
                                            Investigate large ones; have proof
Repeated refund-then-rejoin pattern         Flag account; review by owner
```

### Refund-vs-Credit

When discretion applies, prefer **account credit** over refund:
- Keeps revenue on the books
- Customer might use it (often does)
- If they don't, it expires — net positive for you

Don't push credit if the customer specifically wants money back. That's a goodwill destroyer.

For harms that are not simple owed-money cases, use the triage skill's [COMPENSATION-CALCULUS.md](../../user-support-triage-for-saas-and-open-source-projects/references/COMPENSATION-CALCULUS.md) as the recommendation frame. The product should record the dials/band and approver, but it should not execute credits, refunds, plan upgrades, or extensions without a permissioned human action.

## Escalation Policy

```
Tier 1: Triage agent handles standalone
Tier 2: Triage agent + senior agent review
Tier 3: Owner approval required before sending

Auto-escalate to Tier 3:
  - Refund > $200
  - Security disclosures (any)
  - Legal language ("class action", "lawsuit", "regulator", "attorney")
  - Data loss (any size, any user)
  - Account suspension / ban
  - Press / blog post threat
  - GDPR DSAR / CCPA requests
  - Anything involving children's data (COPPA flag)
  - VIP customers (designated list)
```

Define `VIP customer` precisely: an enterprise tier? top-N by ARR? a public list maintained by the owner?

## SLA Policy (By Tier)

Already covered in main `SKILL.md` and `SLA-ENGINE.md`. The policy doc binds the company:

```
Free tier:       FRT 48h, MTTR 168h (best effort, business hours UTC)
Individual:      FRT  4h, MTTR  72h  (24/7 in P0 only)
Enterprise:      FRT  1h, MTTR  24h  (24/7 all priorities;
                                       weekend on-call rotation)

Holiday / out-of-office:
  - SLAs paused for free tier on documented holidays
  - SLAs continue for paid tiers; on-call must be available
  - Status page reflects holiday SLA changes 7 days in advance
```

## Security Disclosure Policy

```
Initial ack: 4 hours from receipt of valid disclosure.
Severity assessment: 24 hours.
Fix target:
  - CRITICAL (CVSS ≥ 9): 7 days
  - HIGH    (CVSS 7-8.9): 30 days
  - MEDIUM  (CVSS 4-6.9): 90 days
  - LOW     (CVSS < 4): 180 days

Public disclosure window: 90 days (Project Zero standard).

Reporter recognition:
  - Public CVE attribution if reporter consents
  - Hall of fame on /security/credits
  - Bug bounty: $50-$5000 by severity (if program established)
```

See triage skill `runbooks/SECURITY-DISCLOSURE.md` for the operational runbook.

## Hostile-User Policy

```
Level 1 (frustrated): respond with empathy, address root issue.
Level 2 (insulting language): formal, factual reply; do not match tone.
Level 3 (personal attacks / doxxing threats): standardized de-escalation
   message; flag to owner; preserve evidence.
Level 4 (physical threats / stalking): suspend account; consult counsel;
   document for police if needed.
Level 5 (organized brigading): public statement only via owner; do not engage
   individual instances; lock relevant tickets.
Level 6 (criminal activity): law enforcement; counsel; press freeze.

We will not:
  - Match insults
  - Send a hostile customer to public social media
  - Remove their data without their request (unless ToS violation
    procedurally requires)
  - Discuss the account publicly
```

See triage skill `runbooks/HOSTILE-USER.md`.

## Account Suspension Policy

```
Reasons we will suspend:
  - ToS violation (specific clause cited)
  - Confirmed fraud (chargeback abuse, identity theft)
  - Spam / abuse of other users on the platform
  - Threats of violence
  - Court order / law enforcement request
  - Repeated harassment of staff after warnings

Process:
  1. Document the reason with evidence
  2. Owner sign-off required (no triage-agent suspensions)
  3. Notify the customer with clause cited + appeal path
  4. If they appeal, review within 7 days
  5. Suspension can be reversed if appeal is upheld

We do NOT suspend for:
  - Critical feedback about the product
  - Public negative reviews
  - Refund disputes (use the refund policy instead)
  - Disagreement on policy
```

## Data Retention Policy

```
Active customer data: retained for the life of the account
Tickets: retained for 7 years after account closure (legal record)
Audit logs: retained for 7 years
Application logs (with PII): 90 days
Application logs (without PII): 1 year
Backups: 30 days rolling, 1 yearly snapshot

On account deletion (GDPR Article 17):
  - User data deleted within 30 days
  - PII in tickets replaced with [redacted-<date>]
  - Audit log entries: replaced with [redacted-<date>] per GDPR retention exemption
  - Backups: redacted on next backup cycle (max 30 days)

Special cases:
  - Active legal hold: retention extended; user notified
  - Outstanding balance: retain payment records 7 years per tax law
```

## Communication Channels Policy

```
Where customers can reach us:
  - In-app SupportWidget (preferred, all tiers)
  - support@ email (all tiers)
  - GitHub Issues (OSS components only, public)
  - X/Twitter DMs (acknowledge only; route to ticket)
  - Twitter public mentions (engage publicly only on incidents;
    otherwise route to DM)
  - LinkedIn (route to email; do not engage)
  - Phone (Enterprise only, scheduled)

Where we will not:
  - Personal email of staff
  - Personal X/Twitter / LinkedIn / Discord of staff
  - Comment sections on third-party blogs about us
```

## Privacy / DSR Policy

Article 15 (access), 16 (rectification), 17 (erasure), 20 (portability), 21 (objection):

```
Article 15 (access):  fulfilled within 30 days. ID-verified by ToS account email + magic-link.
Article 16 (rectify): fulfilled within 30 days. Self-serve preferred (account settings).
Article 17 (erase):   fulfilled within 30 days. Exceptions: legal-hold, tax-records, audit.
Article 20 (export):  fulfilled within 30 days. JSON or CSV; covered fields documented.
Article 21 (object):  fulfilled within 30 days for processing on legitimate-interest basis.

Verification: requestor must verify control of the email used at account
creation. Magic link sent to that email; clicking proves control.

Free service for the first request per year per user. Subsequent requests
within 12 months may be charged a reasonable admin fee under Article 12(5).
```

See triage skill `runbooks/GDPR-DSAR.md`.

## Contractor / Sub-processor Policy

If you use sub-processors (Resend, Stripe, OpenAI, AWS, Vercel, Postgres-host):
- Maintain a public list at `/legal/sub-processors`
- Notify customers 30 days before adding a new one (per GDPR)
- DPA in place for each
- Right to object: customer may terminate if a new sub-processor is added

## Changes To Policy

```
We may update these policies. When we do:
  - Material changes: 30 days advance notice via email + product banner
  - Non-material changes: changelog only
  - Customer's continued use after the effective date constitutes acceptance
  - For active enterprise contracts: changes do not apply mid-term unless
    legally required

Changelog kept at /legal/policies-changelog.
```

## Reading And Operationalizing This

The triage skill consumes this file (or its analogue in `<project>/.claude/support-triage/05-policies.md`). Every policy decision in triage cites the relevant clause:

```
"Per our refund policy (statutory window for EU residents): full refund issued."
```

Without these documented, every refund / escalation / suspension is invented on the spot and inconsistent. Document once, consume forever.

## Templates To Render

The system needs forms / pages built for:
- `/legal/privacy` — privacy policy
- `/legal/terms` — terms of service
- `/legal/refund` — refund policy
- `/legal/sub-processors` — DPA list
- `/legal/security` — security policy + responsible-disclosure (also `.well-known/security.txt`)
- `/legal/dpa-template` — for enterprise (downloadable)
- `/legal/dsar` — DSAR submission form

Each is an MDX page. Versioned. The footer of every customer-facing email links to these.

## Companion Refs

- [SLA-ENGINE.md](SLA-ENGINE.md) — SLA computation
- [ENTERPRISE-TIER.md](ENTERPRISE-TIER.md) — per-org overrides
- [SECURITY.md](SECURITY.md) — auth, audit, rate-limit
- [COMPENSATION-CALCULUS.md](../../user-support-triage-for-saas-and-open-source-projects/references/COMPENSATION-CALCULUS.md) — refund/credit/upgrade recommendation frame
- `/user-support-triage-for-saas-and-open-source-projects` — runbooks/REFUND.md, GDPR-DSAR.md, HOSTILE-USER.md, SECURITY-DISCLOSURE.md
- `/wills-and-estate-planning-skill` — adjacent for legal-doc patterns
