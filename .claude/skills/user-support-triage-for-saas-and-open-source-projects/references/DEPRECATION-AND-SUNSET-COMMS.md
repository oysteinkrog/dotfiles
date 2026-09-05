# Deprecation & Sunset Comms — Ending A Feature, Endpoint, Or Product

Every successful product accumulates things it no longer wants to support: an old API version, a feature that didn't get traction, a plan tier being consolidated, a whole product being shut down. Done well, deprecation is a partnership with the customer that ends in graceful migration. Done badly, it generates a churn cliff, an angry blog post on Hacker News, and a wave of legal complaints. This file is the playbook.

> **Core insight:** every deprecation is a *broken promise about reliability*, no matter how soft. Customers built things assuming you'd keep what you shipped. The discipline of deprecation is being honest about that, giving them enough time and tools to migrate, and absorbing the friction that follows. Skipping any of those three creates a brand-damage event.

This file complements `CRISIS-COMMS.md` (deprecations sometimes become press events) and `PROACTIVE-SUPPORT.md` (deprecation is a planned proactive-support effort at scale). It also informs Pipeline Z (Deprecation / EOL).

---

## The Deprecation Spectrum

| Severity | Example | Customer impact |
|---|---|---|
| **Soft deprecation** | "Use the new API endpoint when convenient" | None immediate; technical debt for them |
| **Hard deprecation** | "Old endpoint stops working on [date]" | Migration required by date |
| **Plan consolidation** | "Old free tier replaced; existing free users grandfathered" | Friction at next signup; no immediate impact |
| **Plan removal** | "Plan X discontinued; existing customers must move to Plan Y" | Migration; possible price change |
| **Feature removal** | "Feature F removed in next release" | Workflow breakage |
| **Sunset (whole product)** | "Product P shutting down [date]" | Existential for customer's dependency |
| **Acquisition / pivot** | "We were acquired; product changing" | Variable; often customer needs to leave |

Each requires different lead time, comms cadence, and migration support. The most common project failure: treating a hard-deprecation like a soft-one (insufficient notice) or a feature removal like a plan-consolidation (over-notification, customer fatigue).

---

## The Six Variables Of Good Deprecation

| Variable | Question | Default |
|---|---|---|
| **Lead time** | How long does customer have to migrate? | API: 12 months; feature: 6 months; plan: 3 months; sunset: 12-24 months |
| **Migration path** | What replaces the deprecated thing? | Always document; a "no" is OK if honest |
| **Migration tooling** | Can we migrate them, with their consent? | Yes wherever possible |
| **Cadence** | How often do we remind? | T-12mo, T-6mo, T-3mo, T-1mo, T-2wk, T-1wk, T-day-of |
| **Channel** | Where do reminders go? | Email + in-app banner + status page + API deprecation header |
| **Pricing during migration** | Cost during the migration window? | No new charges; honor existing pricing |

Project's specific defaults in `05-policies.md`. The above are starting points.

---

## The Lead-Time Math

For a paid SaaS API that customer code depends on:

| Lead time | Risk |
|---|---|
| **< 30 days** | Catastrophic; lawsuit-shape; press-event-shape |
| **30-90 days** | High friction; some customers can't make it; angry but legal |
| **3-6 months** | Acceptable for soft features; tight for embedded code |
| **6-12 months** | Industry standard for hard API deprecation |
| **> 12 months** | Generous; reduces noise but extends technical debt |

For a free / consumer feature: 3-6 months is generous. For an enterprise-contracted feature: contract obligations may *prohibit* deprecation without negotiation.

The asymmetry: too-short deprecation is permanent reputation damage; too-long deprecation is annoying but recoverable. Default long.

---

## The Comms Cadence

For a 6-month deprecation:

| When | What | Channel |
|---|---|---|
| T-6mo | Announcement; full migration guide | Blog + email to affected; in-app banner |
| T-3mo | Reminder + check on progress | Email + dashboard "you have N days left" |
| T-1mo | Urgent reminder; offer migration help | Email + escalating in-app |
| T-2wk | Final-warning email; specific account-level data on impact | Email; account banner |
| T-1wk | Last-chance email | Email |
| T-day-of | Removal happens; concurrent email confirming | Email |
| T+1d, T+1wk | Post-removal "removed; here's the path forward if you missed it" | Email |

Each touchpoint should:
- Name the deprecation specifically (not "changes coming")
- State the date
- Link to migration guide
- For account-level impact: cite their specific usage and what's at risk

---

## The Migration Guide

A single artifact that answers:

- What's being deprecated?
- When?
- What replaces it?
- Where can I see if I'm affected?
- How do I migrate (step-by-step, with code samples)?
- How long should migration take? (rough estimate)
- What if my use case isn't covered?
- Who do I contact if blocked?

The "what if my use case isn't covered" matters more than teams realise. Some customers have edge cases the migration didn't anticipate. The honest answer is "contact us; we'll work it out." Forcing them into an unsuitable replacement is what triggers angry blog posts.

---

## Account-Level Impact Reporting

For affected customers, the email should *say what's at risk for their specific account*:

| Generic | Specific (better) |
|---|---|
| "API v1 is being deprecated." | "API v1 is being deprecated. Your account made 12,453 v1 calls last week. Endpoints affected: /users, /sessions." |
| "Plan X is being phased out." | "You're on Plan X. Your usage in the last 30 days fits Plan Y; you'd save $40/mo." |
| "Feature F is being removed." | "You used Feature F 8 times this month. Replacement: Feature F'. The replacement does [X] but not [Y, which you used in 1 of 8 cases]." |

The specificity makes the migration *concrete* and signals that you actually thought about their case. Generic deprecation emails get ignored.

---

## Migration Tooling

The strongest deprecations include tooling that *does the work for the customer* with their consent:

- API: deprecation period during which both old and new endpoints work; SDK that auto-migrates; codemod for client code
- Feature: data migration script; "click here to migrate your settings"
- Plan: auto-recompute new plan from existing usage; offer one-click migration
- Sunset: data export tool; partner referral if a successor product exists

Without tooling, the burden falls on every customer individually. With tooling, the migration becomes "review and confirm" rather than "engineering project for your team."

---

## The Special Case: Enterprise Contracts

If you have enterprise contracts with deprecation-affecting customers, *contracts often prohibit unilateral deprecation* of features they paid for. Discipline:

```
[OPERATOR-LOCAL: ☠ EOL — Enterprise check]
1) Identify enterprise customers using the deprecated thing.
2) For each, review their contract:
   - Does it specifically reference the feature?
   - Does it have a "no material change without consent" clause?
   - Does it have a "feature removal triggers termination right" clause?
3) For contracts that prohibit unilateral removal:
   - Counsel-led negotiation BEFORE announcing publicly
   - Customer-specific deprecation schedule (often longer than public)
   - Possibly: keep feature for them past the public sunset
   - Possibly: feature-removal credit / discount
4) Public announcement should not contradict private agreements.
```

The pattern: announce externally only after enterprise customers know individually. Otherwise enterprise reads about it on your blog before AE called them, and the relationship damage is significant.

---

## The Sunset (Whole-Product Shutdown)

Hardest case. Patterns:

- **Lead time**: 12-24 months for paid; 6-12 for free
- **Refunds**: prorate generously; better than annoying paying customers on the way out
- **Data export**: must work; ideally several formats (CSV, JSON, Parquet)
- **Successor**: name a recommended alternative if there is one (open-source, partner, competitor — be honest about who covers their use case)
- **Open-source release**: when reasonable, open-source the code so customers can self-host
- **API key revocation**: predictable, last (after data export, after migration support)
- **Final email**: human; from a named founder/leader; thanks customers; explains why; provides path forward

A famous case-study format:

```
Subject: [Product] is shutting down on [date]

[Name from leadership] here. We're shutting down [Product] on [date].

Why: [honest one-paragraph]

What this means for you:
- Until [T-Xmo]: full functionality continues, including new sign-ups
  paused now
- [T-Xmo to T-1wk]: data-export tool available at [link]; we'll
  refund [X] of unused subscription
- After [date]: API keys revoked; data deleted within 30 days

We're recommending [alternative] for users who want to continue with
[similar use case]. We've prepared a migration script: [link].

For enterprise customers under contract: your account team will be in
touch directly about your specific timeline.

Thanks for using [Product]. Sincerely sorry to be ending this for the
people who built workflows around it.

— [Name]
```

What's not there: marketing language, "exciting new direction", false optimism about the team's other ventures.

---

## Open-Sourcing On The Way Out

When a project is shutting down a service, open-sourcing the code can be both a goodwill gesture and a customer-protective move:

- License clearly (MIT or Apache-2.0 if no third-party constraints)
- Include `runbooks` and operational docs, not just code
- Note unmaintained-after-date status in README
- Provide forking guidance ("if you fork, you need to provide your own [API keys, infrastructure, etc.]")
- Don't open-source if security-sensitive (auth code, encryption code, code with secrets in commit history)

This converts a shutdown from "loss for customers" to "graceful handover for customers willing to self-host." Reduces the press-damage and retains goodwill for future ventures.

---

## Common Mistakes

| Mistake | Why it bites |
|---|---|
| Deprecation announced via blog only | Customers don't read your blog; need direct email |
| Deprecation date in vague terms ("end of year") | Different timezone interpretations; pads anxiety |
| Migration guide assumes happy path | Real customers have edge cases; respect that |
| No tooling | Burden falls on every team individually |
| Final removal happens during business hours of one timezone | Wrecks customers in other zones |
| No after-removal recovery path | Customers who missed the deadline have no recourse |
| Enterprise customers learn from blog | Account team blindsided; relationship damage |
| Deprecation announced concurrently with new feature launch | Mixed signals; new feature buries the deprecation |
| Removed thing was an entire customer workflow | Should have been deprecated with much longer notice |
| "We've improved [thing] by removing it" framing | Insulting; honest "we're removing this" is better |

---

## When Deprecation Becomes A Press Event

Some deprecations always do. Predictably:

- API breaking changes affecting many embedded integrations
- Removing privacy protections customers depended on
- Pricing increases dressed as "plan consolidation"
- Reducing storage / quota for free users
- Killing the product an indie developer's business depends on

When this is foreseeable, plan crisis-comms ahead per `CRISIS-COMMS.md`:

- Holding statement ready
- Spokesperson identified
- Affected-customer DM list ready
- Press inquiry route through Pipeline T

---

## How This File Plugs In

| Used by | How |
|---|---|
| ☠ EOL operator | Deprecation classification + comms |
| Pipeline Z (Deprecation) | The dedicated pipeline |
| 🩹 PROACTIVE | Per-affected-account outreach |
| 🪧 BROADCAST | Public announcement timing |
| CRISIS-COMMS.md | When deprecation goes viral |
| ENTERPRISE-PLAYBOOKS.md | Contract-bound deprecation rules |
| 05-policies.md | Project's deprecation lead-time defaults |
| AI-AUTO-RESPONSE-GOVERNANCE.md §T4 | Deprecation comms never agent-led |

---

## Cross-References

- [CRISIS-COMMS.md](CRISIS-COMMS.md) — when deprecation becomes press event
- [PROACTIVE-SUPPORT.md](PROACTIVE-SUPPORT.md) — outreach mechanics
- [ENTERPRISE-PLAYBOOKS.md](ENTERPRISE-PLAYBOOKS.md) — contract obligations
- [COMPENSATION-CALCULUS.md](COMPENSATION-CALCULUS.md) — refund / credit math
- [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md) — post-deprecation retro
- [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md) — feedback during/after migration
