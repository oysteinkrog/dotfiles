# Proactive Support — Reaching Out Before The Customer Reaches You

Reactive triage handles the customers who write. Proactive support handles the customers who *should have written but didn't*. The silent affected cohort is often much larger than the reporting cohort (see `CUSTOMER-PSYCHOLOGY.md §The Silent Cohort`). Reaching them turns a contained-but-unreported issue into a trust deposit, and prevents the slow-burn churn that happens when affected users decide your product is "kind of unreliable" without ever telling you.

> **Core insight:** the highest-CSAT support reply is one the customer didn't ask for. Proactive outreach inverts the trust math: instead of having to make up for a problem the customer noticed, you're showing up before they did. Done well, it produces the strongest deposits in the trust ledger.

---

## The Three Trigger Classes

| Class | Trigger | Cohort size | Latency target |
|---|---|---|---|
| **Incident-driven** | Logged event of customer-affecting issue | Defined by the bug's blast radius | Within 4-24h of fix |
| **Pattern-driven** | VoC theme cluster suggests cohort experiencing same friction | Defined by ticket-fingerprint match | Within 1-7 days of theme detection |
| **Behavior-driven** | Customer behaviour signals impending churn or activation failure | Defined by analytics rules | Within 1-3 days of behaviour shift |

Each requires different intent, channel, and tone.

---

## Incident-Driven Outreach

The most common case: a bug shipped, X customers were affected, the bug is fixed. Question: should you proactively tell the rest?

### Decision matrix

| Were they harmed? | Did they notice? | Outreach? |
|---|---|---|
| Yes | Yes (filed ticket) | Already in your queue; reply normally |
| Yes | Yes but didn't file | **Outreach yes** — they noticed and decided you weren't worth telling |
| Yes | No (lurking risk) | **Outreach yes** — they would have noticed eventually |
| No (false positive in logs) | Doesn't matter | **No** — outreach risks creating concern from nothing |
| Unsure if harmed | — | Run analysis; default no, but document |

The high-leverage row is the second: customers who *noticed* and *didn't tell you*. Industry data suggests this is ~70% of affected users on consumer SaaS. They are your near-future churners; they are also the most receptive to a well-timed outreach.

### Sample incident-driven outreach

```
Subject: Quick note about something we noticed on your account

Hey [name],

Between [date] and [date], a bug in our [thing] caused [specific
effect] for accounts in [bucket]. Yours was one of them.

Specifically what happened: [one paragraph, plain language]
Your data: [specific to their account — affected rows / time / etc.]
Our fix: [one paragraph; what changed; why it can't recur]
Compensation: [if applicable; per COMPENSATION-CALCULUS.md band]

If you noticed this and have already worked around it, the workaround
isn't necessary anymore — feel free to remove it. If you didn't
notice, you can ignore this; everything is back to expected behaviour.

If anything looks wrong now or in the next week, reply directly —
this email goes to a real person.

— [name], [role]
```

### What to avoid

- Vague disclosures: "we recently had a brief issue affecting some users." If you can't say what, when, and who specifically, don't send.
- Marketing-flavoured framing: "as part of our ongoing commitment to transparency..." This reads as performance, not communication.
- Hiding the lede: the first paragraph must say what happened. Bury it and customers feel handled.
- Asking *them* to verify: "please check your account for any anomalies." Their job is to use the product; your job is to verify. Tell them what you already verified.

---

## Pattern-Driven Outreach

The VoC loop ([VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md)) detects a theme accelerating before it becomes an outage. Pattern-driven outreach reaches the cohort *before* their tickets land.

### Common patterns and outreach shape

| Theme | Cohort detection | Outreach |
|---|---|---|
| onboarding.first-import-fails | Cohort: signed up <7d ago, 0 imports completed | "Saw you got partway through; what's blocking?" |
| billing.proration-confusing | Cohort: changed plan in last 30d, opened invoice page | "Want to walk through your prorated invoice with you?" |
| integrations.webhook-misconfig | Cohort: configured webhook, no successful delivery in 7d | "Your webhook hasn't fired since [date]; here's how to test" |
| feature.export-timeout | Cohort: started export > 3 times last week, none completed | "Exports are slow on accounts your size; here's a workaround until we ship the fix" |
| auth.sso-misconfig | Cohort: Enterprise plan, SSO IDP set, login failures in audit | "We see your SSO is still pointing at [old IdP]; happy to help migrate" |

**Important**: pattern-driven outreach is *not* "automated upsell." It is identifying customers struggling with the *current* purchase and helping them. Done correctly it improves retention; done as a sales pretext it generates immediate distrust.

### The cohort-detection ethics check

Before any pattern-driven outreach goes out, the agent (and owner) should be able to answer:

- *Why this cohort?* The signal must be specific to the friction, not "users who haven't responded to our last 3 emails."
- *Why now?* Timing must connect to the friction, not to a marketing calendar.
- *What's the help offer?* There has to be a real, concrete offer (a step, a workaround, a fix). "Here's some content" is not help.
- *What's the unsubscribe path?* Mandatory; one-click; honored immediately.

If any answer is unclear, do not send. The cohort isn't ready and the outreach will read as marketing.

---

## Behavior-Driven Outreach

Behavioural signals are stronger predictors of churn than support signals — the customer who silently stops logging in is much more at risk than the one who files a support ticket. The triage skill is *adjacent* to behavioral outreach (the data lives in product analytics, not the support adapter), but should know how to coordinate when behavioral systems trigger a customer-touch.

### Common behavioural triggers

| Signal | Window | Outreach class |
|---|---|---|
| Last login > 14d for paid customer | 14d | Friendly check-in (not aggressive) |
| Stopped using a previously-active feature | 7d | "How are things going?" with referenced feature |
| Plan downgrade attempt | Same-day | Save-the-customer flow (not the triage agent's territory; coordinate with retention) |
| Support reply rated negative (CSAT 1-2) | Same-day | Owner-led follow-up |
| Crashes / errors > N in last hour | Real-time | Automated reach-out with the affected feature mentioned |
| Sandbox-only usage for >30d (no production traffic) | 30d | Activation-friction check |

These are usually owned by retention / customer success, not support triage. The triage skill's job is to *coordinate* — when an outreach is going out, support needs to know so any inbound response gets routed correctly. When the outreach receives a reply that triggers triage, the original outreach context must travel with the ticket.

`05-policies.md` should record which behavioural triggers exist and who owns them.

---

## Channel Selection

For the same outreach intent, the channel changes the meaning:

| Channel | When | Tone |
|---|---|---|
| **Email from named sender** | Most outreach | Direct, personal |
| **In-app banner / message** | Active session, low-stakes | Light, contextual |
| **In-app modal** | High-stakes (data exposure, billing) | Demands acknowledgement |
| **Status page banner** | Active mass incident | Public, reassuring |
| **Phone call** | Enterprise, high-stakes only | High-touch |
| **DM via Twitter / Slack** | If that's the customer's primary channel for you | Same register as their inbound DMs |
| **Public post** | Mass-event acknowledgement | One-to-many, restraint |

The wrong channel poisons the right intent: a billing-error proactive email feels right; the same in a phone call feels alarming. A security-fix outreach in an in-app banner feels minimising; the same as a personal email feels appropriate.

For incident-driven outreach with a customer cohort >50, batch-email-from-named-sender is almost always the right answer.

---

## The Silent-Cohort Inventory

A useful onboarding output: enumerate the most common silent cohorts the project has, before they become incidents. Sample for a SaaS project:

```
SILENT COHORTS — known categories that often go unreported

1. Onboarding stalled cohort
   Detection: signed up >3d ago, did not complete first activation step
   Pattern: high-intent at signup; lose patience without help
   Outreach default: friendly check-in offering specific help

2. Power-user-blocked cohort
   Detection: account has used X feature regularly, then stopped (no churn yet)
   Pattern: hit a limit / bug; worked around or paused; will quietly downgrade
   Outreach default: ask what's blocking

3. Trial-decline-late-stage cohort
   Detection: trial ending in 3-7d; product usage trending down
   Pattern: trial conversion rate drops sharply if not contacted
   Outreach default: short, useful tip + offer to extend trial if needed

4. Webhook-or-integration-broken cohort
   Detection: integration configured and previously firing; no fires in 14d
   Pattern: silent failure; customer doesn't know it's broken
   Outreach default: technical alert with reproduction steps

5. Plan-overage cohort
   Detection: usage approaching plan limits in current period
   Pattern: surprise overage at month-end damages trust
   Outreach default: 80%-of-limit warning with upgrade option (no pressure)
```

This becomes a section in `<project>/.claude/support-triage/02-channels.md` and is reviewed quarterly.

---

## Measuring Proactive Outreach

Two metrics matter, in tension with each other:

- **Reach rate**: of an outreach cohort, what fraction read / clicked / replied? Choose local targets by channel and customer segment; low response means the cohort, message, or timing is wrong.
- **Reverse-CSAT**: of customers who *received* an outreach, what fraction filed a NEW ticket because of it (vs because of the original problem)? (target near zero)

The second metric protects against over-outreach. If a campaign drives a lot of *new* tickets ("I got this email and don't understand"), the campaign itself is the problem.

Less obvious metric: **silent-cohort retention delta** — does the cohort that received outreach have higher 30-day / 90-day retention vs. a held-out control? This is the truest measure of value but requires statistical discipline (random hold-out, not opt-in).

---

## Anti-Patterns

| Anti-pattern | Why it fails |
|---|---|
| Generic outreach to broad list | Reads as marketing; depletes outreach goodwill |
| Outreach without a real fix or help offer | Customer interprets as fishing |
| Outreach right after sending a billing-related email | Feels like sales pursuit |
| Outreach that asks them to verify our work | Pushes our work onto them |
| Outreach signed by "The [Project] Team" | Feels canned; named sender outperforms |
| Multiple proactive emails to same customer in 30d | Crosses from helpful into annoying |
| Outreach disguised as support reply | Customers spot it; trust withdrawal |

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🩹 PROACTIVE operator | Cohort detection + outreach scaffolding |
| 🪧 BROADCAST operator | Mass-event public outreach (shared mechanic, public surface) |
| Pipeline P (proactive customer outreach) | Standard incident-driven outreach |
| 02-channels.md | Silent-cohort inventory |
| 05-policies.md | Behavioural-trigger ownership |
| METRICS-AND-DASHBOARDS.md | Reach rate / reverse-CSAT / retention delta |

---

## Cross-References

- [CUSTOMER-PSYCHOLOGY.md](CUSTOMER-PSYCHOLOGY.md) §"The Silent Cohort"
- [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md) — pattern detection
- [DEFLECTION-AND-SELF-SERVICE.md](DEFLECTION-AND-SELF-SERVICE.md) — proactive deflection by improving the product
- [STATUS-PAGE.md](STATUS-PAGE.md) — public mass-event channel
- [COMPENSATION-CALCULUS.md](COMPENSATION-CALCULUS.md) — incident-driven compensation
- [CRISIS-COMMS.md](CRISIS-COMMS.md) — when proactive outreach turns into press handling
