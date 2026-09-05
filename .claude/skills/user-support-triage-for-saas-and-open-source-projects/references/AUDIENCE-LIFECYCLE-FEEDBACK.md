# Audience, Lifecycle, And Feedback Loop

Support triage is not one workflow. The right move depends on who is affected,
where the support system is in its lifecycle, and what the last few sessions
taught the project. Use this reference to keep the skill useful across SaaS,
open source, communities, agencies, internal tools, and enterprise products.

## Contents

- [Audience Router](#audience-router)
- [Lifecycle Modes](#lifecycle-modes)
- [Response Intent Types](#response-intent-types)
- [Feedback Signals To Capture](#feedback-signals-to-capture)
- [Product Accretion Loop](#product-accretion-loop)
- [Owner Review Cadence](#owner-review-cadence)

## Audience Router

| Audience | What they need | Triage emphasis |
|---|---|---|
| End user | Fast recovery, plain-language status, no implementation trivia | reproduce exact path, give concrete next step |
| Billing owner | Money/account clarity, invoice/subscription proof | entitlement, provider ids, refund policy |
| Team/org admin | Member impact, permissions, data ownership | org-scoped checks, audit logs, admin path |
| Developer/integrator | API/webhook/OAuth specifics, versions, payloads | exact request/response evidence, version pin |
| Enterprise/customer success | SLA, named escalation, continuity | owner escalation, artifact pack, status cadence |
| OSS user | Repro, workaround, issue labels, contribution path | minimal template, public thread hygiene |
| Maintainer/contributor | Design intent, review criteria, merge path | issue/PR policy, roadmap fit |
| Security researcher | Private acknowledgement, embargo, severity path | security runbook, no public detail |
| Journalist/public observer | Accurate statement, no speculation | owner-approved public comms only |
| Legal/regulatory actor | Preserve evidence, stop casual replies | legal/security handoff |

If the audience is mixed, write for the highest-risk reader but keep the action
usable for the person currently blocked.

## Lifecycle Modes

| Mode | Trigger | Primary output |
|---|---|---|
| Onboard | No current support map or a new major surface | complete support intake and adapter |
| Routine triage | Existing map, normal queue | classify, draft, owner-confirm, act, verify |
| Live escalation | User is waiting now or business owner is relaying chat | narrow evidence, short drafts, rapid verification |
| Incident | Multiple affected users or public status impact | one incident thread, cohorting, status cadence |
| Post-incident | Hotfix shipped or queue stabilized | retro, KB update, test/backlog items |
| Policy refresh | owner rules changed or `TBD-OWNER` blocks automation | batched decisions, policy update, fire drill |
| Provider migration | ticketing/email/billing/auth provider changed | dual-run proof, id mapping, handoff artifacts |
| Product-feedback review | many feature/how-to tickets recur | cluster, decide product/docs/backlog action |

## Response Intent Types

Choose the intent before drafting. This keeps answers from becoming generic
"support voice" regardless of the actual user need.

| Intent | Use when | Draft shape |
|---|---|---|
| How-to | User is blocked and needs steps | concise numbered steps, expected result, fallback |
| Explanation | User needs to understand why something happened | cause, scope, status, what changed |
| Reference | User asks policy/limits/API behavior | exact policy/limit, link/source, caveats |
| Transaction | Refund, cancellation, account change, data export | evidence, approval, action confirmation |
| Apology | Confirmed project failure affected user | acknowledge impact, fix status, concrete remedy |
| Decline | Unsupported request, abuse, out-of-policy refund | clear boundary, alternative if any, no debate |
| Escalation | Owner/security/legal must decide | no public speculation, private handoff |

The response intent can differ from the ticket category. Example: a billing
ticket may need "how-to" if the user cannot find an invoice, or "transaction" if
the agent is executing a refund.

## Feedback Signals To Capture

Every support session should produce at least one learning signal, even when no
code changes.

| Signal | Where to record | Promotion threshold |
|---|---|---|
| Repeated same question | `09-knowledge-base.md` | 3+ in 30 days or high-value customer |
| User reply says answer did not help | outcome record | immediate template review |
| Zero-result KB search | `09-knowledge-base.md` | 2+ similar searches |
| Same root cause across channels | `06-recurring-issues.md` | 2+ open items or one severe |
| Owner rewrites same draft pattern | `08-voice.md` | 2+ rewrites |
| Manual-only channel creates missed SLA | `12-gap-dispositions.md` | any SLA breach |
| Policy ambiguity blocks action | `05-policies.md` | immediate owner batch |
| Ticket fix required code change | backlog/bead/issue | every confirmed bug |
| AI suggestion accepted/edited/rejected | outcome record | every AI-assisted draft if enabled |
| Customer churn/cancellation mention | metrics/outcome | every occurrence |

## Product Accretion Loop

After Phase 6, decide where the learning belongs:

| Learning type | Promote to |
|---|---|
| repeated confusion | docs/KB article or in-product copy |
| repeated bug | regression test + backlog item |
| repeated refund reason | pricing/onboarding/product analytics |
| repeated account recovery failure | auth UX and recovery runbook |
| repeated integration issue | SDK docs, webhook diagnostics, examples |
| repeated hostile pattern | abuse policy and moderation tooling |
| repeated manual work | adapter capability or internal admin tool |
| repeated high-risk ambiguity | policy elicitation and owner approval rule |

The skill becomes accretive only when support outcomes change the product,
documentation, templates, policies, and future triage behavior.

## Owner Review Cadence

Add a review cadence to the project map:

- weekly while onboarding or after launch;
- monthly for active paid support;
- after every incident;
- after a provider migration;
- whenever a high-risk policy gets marked `TBD-OWNER`;
- at least every six months for dormant projects.

The review asks:

1. Which support topics grew?
2. Which templates caused confusion?
3. Which policy gaps blocked agents?
4. Which manual channel created hidden work?
5. Which product/docs changes would prevent the next 10 tickets?
6. Which automation should remain manual because the blast radius is too high?
