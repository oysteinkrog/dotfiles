# Router And Complexity Modes

Use this before choosing an exact prompt. The default skill assumes a Next.js +
Drizzle + Resend SaaS, but the underlying support system can be smaller,
larger, regulated, migrated, non-SaaS, internal-only, marketplace-shaped,
community-heavy, or ported to another stack.

## Complexity Modes

| Mode | Use when | Build shape |
|---|---|---|
| Minimal | low-volume product, no paid SLA, contact form replacement | tickets, messages, basic admin list, email, no enterprise overrides |
| Standard | paid SaaS with recurring support and basic SLAs | full default phased rollout |
| Enterprise | named accounts, contractual SLAs, customer success handoff | per-org tiers, escalation owners, artifact packs, dashboards |
| Regulated | privacy/legal/security/financial/health/safety constraints | strict audit, retention, legal/security handoff, second opinion |
| Migration | leaving or joining Zendesk/Intercom/Help Scout/etc. | id mapping, dual-run, import, rollback, provider portability |
| OSS-hybrid | GitHub/community plus paid support | GitHub fork plus in-app paid support, public/private boundary |
| Internal tool | employees or ops users, no external customers | permissions/audit still required; email may become internal notification |
| Marketplace / ecommerce | orders, refunds, chargebacks, reviews, platform ids | order/customer/platform id joins, return/refund audit, public-review workflow |
| Mobile app | app-store reviews, crash reports, in-app feedback | build/device/OS/locale fields, release cohort, review reply discipline |
| Community / creator | forum/chat/social support plus moderation | public/private split, moderation escalation, community norms |
| Agency / client services | support tied to contracts/SOW/account managers | contract scope, client owner, commercial approval path |

Do not overbuild. A minimal system still needs the hard invariants; it does not
need enterprise dashboards on day one.

## Support Archetype Router

Pick the archetype before picking tables. The same universal kernel applies,
but the evidence keys and side effects differ.

| Archetype | Requester identity | Evidence keys | Side effects needing explicit approval |
|---|---|---|---|
| SaaS/subscription | user/org/subscription | user id, org id, subscription id, invoice id | customer reply, refund, credit, plan override, account lock |
| OSS-hybrid | GitHub user plus optional paid account | issue/PR URL, maintainer decision, linked paid account | public close/comment, maintainer moderation, paid-support escalation |
| Developer tool/API | account, API key scope, version | SDK/CLI version, endpoint, request id, deploy SHA | quota changes, key rotation, public docs update |
| Marketplace/ecommerce | customer/order/platform account | order id, payment id, platform review URL, return status | refund/return, public review reply, seller/platform escalation |
| Mobile app | app account/device/store profile | app build, OS/device, crash id, rollout cohort, locale | app-store reply, beta rollback, account mutation |
| Community/creator | member handle/subscription | thread URL, moderation history, membership tier | moderation action, public reply, ban/mute, community announcement |
| Internal/ops | employee/service account | employee id, role, system ticket, audit trail | permission grant, data export, operational change |
| Regulated/high-assurance | verified person/entity | identity proof, policy citation, chain-of-custody artifact | legal/privacy/security/safety response, deletion/export, public statement |
| Agency/client services | client stakeholder | SOW/contract clause, account manager thread, approval record | out-of-scope work, credit, contract statement, executive escalation |

If the project spans archetypes, design the common state machine once and add
archetype-specific metadata/side-effect policies. Do not fork business logic per
channel.

## Stack Routers

| Router | Question | Next action |
|---|---|---|
| Framework | Is this Next.js App Router? | default prompts or `FRAMEWORK-PORTABILITY.md` |
| Data | Is Drizzle/Postgres the source of truth? | default schema or adapt with state-machine invariant |
| Auth | How do users/admins authenticate? | map ownership checks and permission keys first |
| Billing | Can tier/entitlement be derived reliably? | wire billing source before tier-aware SLA/rate limits |
| Email | Which provider sends customer-visible replies? | adapt `EMAIL.md` and provider id proof |
| Observability | Where can support verify symptoms and sends? | logs/metrics/traces in handoff |
| AI assist | Will model suggestions be shown? | add prompt-injection boundary and outcome tracking |
| Compliance | Do privacy/security/legal rules constrain support? | regulated mode and artifact packs |
| Migration | Is data moving from another support provider? | use migration reference before writing schema |
| Value loop | Which downstream system should support improve? | docs, onboarding, reliability, retention, pricing, abuse prevention, roadmap |

## "Do Not Build Yet" Branches

Stop and fix prerequisites before building if:

- the support archetype and requester identity source are not named;
- there is no reliable auth/ownership model for customer tickets;
- admin permission keys do not exist and cannot be added safely;
- billing tier is needed for SLA/rate limits but entitlement source is unknown;
- outbound email cannot be verified in a test environment;
- privacy/security policy is unknown but the system will handle those cases;
- the owner wants AI auto-replies without a confirmation gate;
- existing support provider data must migrate but no export/id mapping exists.

In those cases, write a prerequisite checklist and return to the exact prompt
after the blocker is resolved.

## Prompt Selection

| Situation | Prompt/reference |
|---|---|
| Build a sane default in-app system | Exact Prompt 1 |
| Existing partial system | Exact Prompt 2 + `AUDIT-PROMPT.md` |
| Need enterprise SLA | Exact Prompt 3 + `ENTERPRISE-TIER.md` |
| Non-Next.js stack | `FRAMEWORK-PORTABILITY.md` plus hard invariants |
| Provider replacement | `PROVIDER-PORTABILITY.md` and `MIGRATION-PER-PROVIDER.md` |
| High-risk domain | this file + `SUPPORT-SYSTEM-THREAT-MODEL.md` + `VALIDATION-GATES.md` |
| Triage handoff only | `HANDOFF-ARTIFACT-CONTRACT.md` |

## Mode Declaration

At the top of an implementation plan, write:

```markdown
## Support Ticketing Mode

- Mode: Standard
- Framework route: Next.js App Router default
- Data route: Drizzle/Postgres default
- Auth source: <file/provider>
- Billing tier source: <file/provider or not needed>
- Email provider: <provider>
- Compliance constraints: <none|privacy|security|...>
- Migration source: <none|provider>
- Support archetype(s): <SaaS|OSS-hybrid|marketplace|mobile|community|internal|regulated|agency>
- Value loop target: <docs|product|reliability|retention|abuse|roadmap|none-yet>
- Handoff target: `.claude/support-triage/`
```

This small declaration prevents later agents from mixing defaults from the
wrong project shape.
