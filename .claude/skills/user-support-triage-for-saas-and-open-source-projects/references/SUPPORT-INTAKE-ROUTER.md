# Support Intake Router

Use this during onboarding before the agent starts deciding policy, writing
templates, or trusting a ticketing provider's shape. It turns "support for this
project" into a bounded operating model that later triage sessions can load
without rediscovery.

## Contents

- [Complexity Bands](#complexity-bands)
- [Support Archetypes](#support-archetypes)
- [Intake Sequence](#intake-sequence)
- [Routers](#routers)
- [Output Mapping](#output-mapping)
- [Stop Conditions](#stop-conditions)
- [Source Discipline](#source-discipline)

The point is not to interrogate the owner with every possible question. The
point is to ask the smallest batch that classifies the support system, records
the source of each answer, and prevents agents from inventing missing business
rules.

## Complexity Bands

Pick the first band that fits. The band controls how much intake is required.

| Band | Use when | Required output |
|---|---|---|
| Simple | OSS repo, solo tool, low-volume SaaS, no refunds/security/privacy queue | channels, owner, no-send rule, basic templates |
| Standard | Paid SaaS, email/ticket queue, recurring bugs, billing/access issues | full support map, policies, adapter, voice, fire drills |
| Complex | Multiple plans, teams/orgs, webhooks/integrations, migrations, enterprise customers | segmentation, escalation owners, provider failure modes, metrics |
| Regulated / incident-heavy | Healthcare, finance, legal, education, safety, security reports, privacy requests, enterprise SLAs | evidence packs, legal/security handoff, strict audit trail, second opinion |

If in doubt, start one band higher for onboarding and one band lower for routine
triage. Onboarding mistakes create durable drift; routine over-processing slows
the queue.

## Support Archetypes

Support is not a synonym for SaaS tickets. Pick every archetype that applies;
the point is to adapt the same evidence/confirmation/adapter discipline to the
business shape in front of you.

| Archetype | Typical channels | Extra routing question | Common trap |
|---|---|---|---|
| SaaS / subscription | in-app tickets, email, billing portal, status page | Is entitlement/tier reliable? | Treating billing access as "just support" instead of auth + payment truth |
| OSS / maintainer-led | GitHub Issues/PRs/Discussions, Discord, Matrix, email | Is this user support, contribution, or maintainer governance? | Letting loud users capture maintainer time |
| Developer tool / API | GitHub, docs comments, SDK issues, community chat | Which version, endpoint, key scope, and deploy is affected? | Reproducing with the wrong version/account |
| Marketplace / ecommerce | storefront reviews, order support, returns, chargebacks, app reviews | Which platform/order id controls the truth? | Replying in public before preserving order/payment evidence |
| Mobile app | app-store reviews, crash reports, email, in-app feedback | Which build, OS, device, locale, and rollout cohort? | Assuming server logs explain client-only failures |
| Community / creator product | Discord/forum/social, Patreon/subscription, moderation queue | Is this support, moderation, or community governance? | Over-automating where tone and public norms matter |
| Internal tool / ops | employee tickets, Slack, service desk, incident queue | Which internal role owns the action and audit? | Skipping privacy/audit because "users are employees" |
| Regulated / high-assurance | secure inbox, compliance portal, counsel/security threads | Which policy/law/contract constrains the response? | Letting a helpful agent freelance legal, medical, financial, or safety advice |
| Agency / client services | shared inbox, PM tool, account manager, contract docs | What did the statement of work promise? | Solving outside scope without commercial approval |
| Education / minors | LMS/help desk, parent/student/admin channels | Whose identity and consent must be verified? | Exposing student/minor data in support artifacts |

Record the chosen archetypes in `00-intake.md`. If an archetype introduces
money, privacy, safety, minors, regulated advice, public reputation, or account
lockout, route one risk tier higher by default.

## Intake Sequence

Run these phases in order. Skip only when the answer is already documented in
the project support map with a fresh evidence anchor.

### 0. Load Existing Ground Truth

- Read `<project>/.claude/support-triage/README.md` if it exists.
- Read `_detection.json`, `02-channels.md`, `05-policies.md`, and `10-metrics.md`.
- Check the last Phase 6 outcome records for "map drift", "manual-only", and
  "policy-gap".
- Record whether this is first onboarding, refresh, migration, or incident mode.

### 1. Business And Ownership

Capture:

- support owner and backup owner;
- business type: SaaS, OSS, marketplace, agency, community, internal tool;
- support archetype(s) from the table above;
- support posture: founder-led, team-led, community-led, outsourced, automated;
- working hours and escalation hours;
- risk tolerance: conservative/manual, balanced, automation-friendly;
- customer segments that matter to support priority.

### 2. Channels And Providers

Map every inbound and outbound surface:

- in-app ticketing or contact form;
- email inboxes and aliases;
- GitHub Issues, Discussions, PRs;
- Discord, Slack, forum, Reddit, X, LinkedIn, community spaces;
- Zendesk, Intercom, Help Scout, Freshdesk, Front, Plain, Pylon, HubSpot,
  Salesforce, Gorgias, Zoho Desk, Linear, Jira, Notion, Airtable, spreadsheets;
- billing provider support hooks;
- app-store or marketplace reviews;
- security disclosure channels.

Do not assume "ticketing system" means "all support". Most real projects have
at least one manual channel that creates hidden SLA risk.

### 3. Policy Stack

Record only sourced policy. If the owner answers live, cite it as
`owner-answer:<YYYY-MM-DD>:<name-or-role>`.

Required policy categories:

- first response and resolution expectations;
- refunds, credits, chargebacks, cancellation saves;
- security disclosure and responsible disclosure;
- privacy requests and data deletion/export;
- hostile user, abuse, fraud, spam, and account locks;
- unsupported requests and feature requests;
- accessibility requests;
- enterprise/customer-success escalation;
- public incident communication;
- legal/regulatory threats.

### 4. Customer And Audience Segments

Support routing changes when the same symptom belongs to a different audience.
Capture:

- free, trial, paid individual, team, enterprise, lifetime, open-source user;
- admin, member, billing owner, developer/integrator, end user;
- contributor, maintainer, security researcher, journalist, partner;
- language/locale expectations;
- accessibility needs;
- VIPs or named accounts, if applicable.

Do not let segmentation become hidden discrimination. Segment only when it
changes policy, entitlement, SLA, tone, or escalation path.

### 5. Product And Architecture Dependencies

For support, the architecture summary should answer:

- auth and account recovery source of truth;
- billing/entitlement source of truth;
- email sending path and provider ids;
- deployment pipeline and how to prove a fix is live;
- logging and observability access;
- data retention and deletion systems;
- integrations/webhooks/OAuth apps likely to generate tickets;
- rate limits, quotas, abuse detection, and tier resolution;
- admin tools that can mutate customer state.

### 6. Historical Pattern Sample

Sample enough history to learn what repeats:

- last 30-90 days of tickets/issues, if available;
- last 10 refunds or billing disputes;
- last 10 bugs that became support tickets;
- last 5 hostile/legal/security/privacy cases, if any;
- zero-result KB searches and "this reply did not help" signals.

If history is unavailable, write `history-unavailable` with the reason and run
two extra fire drills before trusting the map.

### 7. Owner Decision Batch

Batch all unresolved decisions into one prompt. The owner should not receive ten
separate interruptions.

```text
SUPPORT INTAKE DECISIONS NEEDED

I found these policy gaps while mapping support. Please answer only the rows you
want codified now; I will mark the rest TBD-OWNER and keep them out of
automation.

1. Refund authority:
2. Security disclosure owner:
3. Paid-customer SLA:
4. Free-user SLA or best-effort stance:
5. Hostile-user escalation:
6. Privacy request owner and deadline:
7. Manual-only channels we should not automate yet:
8. Any customer segment that should page a human immediately:
```

## Routers

Use these routers to decide which references and runbooks to load. A router can
return multiple branches.

| Router | Question | Branches |
|---|---|---|
| Surface router | Where did the request enter? | GitHub, custom DB, third-party, email, social/community, manual |
| Risk router | What can go wrong if the reply/action is wrong? | routine, money, account access, data/privacy, security, legal, public incident |
| Lifecycle router | What stage is this support system in? | onboarding, routine triage, live escalation, post-incident, migration, policy refresh |
| Audience router | Who is affected? | free user, paid user, enterprise, maintainer, contributor, researcher, partner, admin |
| Provider router | Which external system controls truth or side effects? | auth, billing, email, observability, ticket provider, community platform, deployment |
| Compliance router | Does policy or law constrain response? | none known, privacy, security, financial, health/safety, education/minor, contract/SLA |
| Architecture router | Which system must be inspected before drafting? | auth, entitlement, data, integration, deploy, logs, queue, rate limit |
| History router | Is this isolated or recurring? | one-off, known recurring issue, new cluster, regression, silent failure |
| Value-loop router | What should this support evidence improve? | docs, product quality, onboarding, retention, pricing, abuse prevention, reliability, roadmap |

## Output Mapping

Write intake results into these project files:

| Finding | Project file |
|---|---|
| surfaces and providers | `02-channels.md` and `_detection.json` |
| architecture dependencies | `01-architecture.md` |
| owner-approved rules | `05-policies.md` |
| customer/audience segments | `03-decision-matrix.md` and `10-metrics.md` |
| recurring issues | `06-recurring-issues.md` |
| manual-only or blocked gaps | `12-gap-dispositions.md` |
| outbound wording | `04-templates/` and `08-voice.md` |
| high-risk paths | `11-runbooks/` |
| automation capabilities | `adapter-capabilities.json` and `scripts/list-open.sh` |

## Stop Conditions

Stop onboarding and ask for owner input when:

- a customer-facing send path exists but no confirmation gate can be enforced;
- a support channel exists but no one knows who owns it;
- refunds, privacy, security, or account locks are requested but policy is
  absent;
- the adapter can send or mutate but cannot prove the action happened;
- support data contains secrets or sensitive personal data that should not enter
  generic artifacts;
- a manual-only channel is high-volume or high-risk and has no review cadence.

## Source Discipline

Every durable rule needs a source:

- `owner-answer:<date>:<role>`;
- `ticket:<id>` or `issue:<url>`;
- `code:<path>:<line>`;
- `provider-doc:<url>:accessed-<date>`;
- `metric:<dashboard-or-query>:<date>`;
- `outcome:<file>`;
- `fire-drill:<file>`.

Owner memory is useful, but it is still a source to record, not a permission to
generalize forever. Add a review date for volatile policies.
