# Trauma-Informed Support — When A Ticket Is About More Than The Product

Most tickets are about a feature or a bill. A small fraction reveal a person in crisis: explicit self-harm references, references to abuse, threats of violence, descriptions of being controlled or stalked through your product. These tickets are **not** customer-service problems and **must not** be triaged as such. This file is the protocol.

> **Core insight:** the worst possible failure is treating a crisis disclosure as a routine ticket. The second-worst is freezing or deflecting because nobody told you what to do. This file gives you the structure to act competently and humanely without overstepping into clinical care you're not qualified to provide.

This file complements `runbooks/HOSTILE-USER.md` (which handles hostility *toward you*) and `EVIDENCE-CHAIN-OF-CUSTODY.md` (which handles legal/regulatory). Trauma-informed support sits *adjacent* — neither hostile nor strictly legal, but requiring its own discipline.

---

## The Crisis Categories

| Category | Common signals | First-action priority |
|---|---|---|
| **Self-harm / suicide reference** | "I can't go on", "ending it", explicit mentions of methods, "won't matter after tomorrow" | Crisis-resource handoff + warm acknowledgement; never the FAQ |
| **Domestic violence / abuse** | "My partner controls my account", "I can't change my password without him seeing", "they're tracking me" | Privacy-protective response + safety-prioritised path |
| **Stalking via product** | "Someone I haven't given access to is in my account", "they know things they shouldn't", real-name fear | Lock account first, ask later; no detail in the visible reply |
| **Active threat from third party** | "A user is threatening me through your platform", screenshots of threats | Trust-and-safety + preserve evidence; do not reply to the threatening user using customer's words |
| **Mention of minors at risk** | Disclosed CSAM, grooming, child endangerment | Mandatory legal reporting in most jurisdictions; counsel immediately |
| **Disclosed mental-health crisis (non-suicidal)** | Panic attacks, dissociation, severe distress mentioned | Acknowledge humanely; offer follow-up timing flexibility; never push refund decline now |
| **Disclosure of personal trauma incidental to ticket** | "Since my husband died...", "after the assault...", "during chemo..." | Calibrate apology weight up; do not extract; do not "use" the disclosure |

Project-specific context may add categories (e.g., a fertility app sees pregnancy-loss disclosures; a mental-health-adjacent app sees direct symptom disclosures more often). Onboarding should add a project's likely-categories to `05-policies.md`.

---

## What Triage Agents Should Do

```
[OPERATOR-LOCAL: Crisis Recognition]
On ANY inbound, scan for crisis signals (above table + project additions).

If detected:
1) STOP standard pipeline. Do NOT auto-classify, auto-tag, or
   draft-bundle this ticket alongside routine items.
2) Notify owner immediately (out-of-band: Slack ping with
   "[CRISIS-FLAG]" prefix; not embedded in the daily bundle).
3) Mark ticket lifecycle state as `crisis-hold`.
4) Write a *holding* internal note: "crisis-flag detected;
   awaiting owner / specialist; agent will not draft a substantive
   reply until cleared."
5) For self-harm/suicide signals SPECIFICALLY: ensure the customer
   sees the standard crisis-resource pointer immediately (within
   the SLA the project's policy specifies, often "within 1 hour").
   This is owner-approved canned text, NEVER agent-generated.
6) Suspend any automated reminders / nudges / SLA timers that
   would re-contact this customer until owner clears.
```

The agent's job in a crisis is **first-aid**: stop the bleeding (suspend automation), call for help (notify owner), and route to the right humans (specialist, counsel, T&S). It is *not* therapy. It is *not* triage in the normal sense.

---

## What Agents Must NEVER Do

| Don't | Why |
|---|---|
| Generate a "supportive" reply with the model's own words | High variance; can mis-handle suicidality; legally hazardous |
| Reply with "I'm sorry to hear" + product info | Centres the product; trivialises the disclosure |
| Refer the customer to "your local emergency number" generically | Unhelpful in a crisis; they don't need to look up a number |
| Ask follow-up questions to "understand better" | Can re-traumatise; not your role |
| Promise "we'll be there for you" | Boundary violation; you're a SaaS company, not a support network |
| Loop back later with "checking in" automation | Pings can compound distress |
| Keep the disclosure in normal ticket retention | Privacy / dignity; minimum-necessary retention applies |
| Use the disclosure as marketing or case study material — ever | Catastrophic dignity violation |
| Auto-decline a refund now because "policy" | Standard policy enforcement during a crisis disclosure compounds harm; pause for owner |

The pattern across all of these is the same: in a crisis, *do less, more carefully*, and route to humans qualified to respond.

---

## The Crisis-Resource Pointer (Owned, Approved, Not Improvised)

Project owners must pre-write the exact text that gets sent on suicide/self-harm signals. The agent never improvises. The text should:

1. Acknowledge the message landed and was read
2. Provide jurisdiction-aware crisis line(s) — 988 (US), 116 123 (UK Samaritans), Lifeline 13 11 14 (AU), etc. — owner-approved list per `05-policies.md`
3. Note that the agent / owner will follow up about the underlying ticket *separately* and after the customer has had time
4. Avoid platitudes ("things will get better"); avoid promises ("we're here for you"); be plain

A workable template (project-tunable):

```
[CRISIS-RESOURCE TEMPLATE — owner-approved; agent inserts verbatim]

Got your message. I want to make sure you have a number to call if
you're in immediate danger. In the [country/region], that's [number].
[Optional: another option if available — text line, online chat].

I'll come back to the [thing the original ticket was about] once
you're in a better place to deal with it. There's no rush from our
side, and the [account / refund / whatever] is on hold until you
write back.

Take care.
```

Notice what's NOT there: no marketing footer, no "rate this conversation", no signature block with social links. The reply has one job.

---

## Domestic Violence / Coercive Control Patterns

Distinct from suicidality, but equally important. Common patterns in support tickets:

- "My partner has my password and I can't change it without him seeing"
- "I want to delete my account so my abuser can't see it" (and the deletion mustn't notify them)
- "Someone is using my email to access this account; I never logged in but they know my recovery questions"
- "Can you not send any emails to my account for the next month, no notifications, no anything"

For each, the *quiet path* matters more than the standard path:

| Standard reply | Quiet-path reply |
|---|---|
| "We'll send a password reset to your email" | "I've manually issued a one-time recovery code; reply to me directly with it; we won't send anything to your email" |
| "We'll need to verify your identity via the registered email" | "Tell me 3 specific account details only you'd know; I'll verify against those without sending email" |
| "Account deletion takes effect in 30 days; you'll receive a confirmation email" | "Account deletion can be immediate; do you want any export first; do you want any confirmation email at all" |
| "We've notified the team about your concern" | (no notification, no shared comment, no Slack mention; owner-only DM) |

The principle: a DV-survivor's safety is *more important* than your standard process. Own this in `05-policies.md` with named owner approval ahead of time, so the agent can deviate from standard process without re-elicitation.

---

## Mandatory Reporting

Some categories trigger mandatory reporting in the operator's jurisdiction:

| Category | Common reporting requirement |
|---|---|
| Disclosed CSAM | NCMEC (US) within 24h; equivalent in EU/UK/AU |
| Imminent threat against an identifiable person | Many jurisdictions require law-enforcement notification |
| Active child endangerment | CPS / equivalent; mandated for many platforms |
| Trafficking indicators | Polaris / equivalent; varies |

The triage agent does NOT make these reports. The agent flags, the owner + counsel decide. `05-policies.md` records the project's reporting obligations and named decision-makers. Failing to report is a separate harm; over-reporting (without basis) is also harm. Counsel arbitrates.

---

## Aftermath: Returning To The Original Ticket

Once the crisis is cleared (customer responded; specialist engaged; situation stabilised), the original ticket may still need handling. Approach:

1. **Wait for the customer's signal.** Don't push.
2. **Recap quietly.** "When you're ready, the original question was about [thing]. No rush; just so you know it's not lost."
3. **Calibrate compensation up.** A customer who disclosed during a billing dispute is a different case from a customer who didn't; the COMPENSATION-CALCULUS dial for "Fault" stays the same but you may bypass strict policy on "Harm" and "LTV" given the context. Owner-approved.
4. **Do not retain the disclosure in clear text in the ticket history.** A short internal note saying "crisis-handled per policy; details sealed" suffices for audit. The disclosure itself moves to a privileged record per `EVIDENCE-CHAIN-OF-CUSTODY.md`.
5. **No follow-up survey.** The customer should not be asked to "rate this support interaction".

---

## Agent Self-Care

This belongs in support skills more than it usually appears. A human triage agent reading 100 tickets a day will eventually read disclosures of suicide, abuse, death, terminal illness. Patterns that protect:

- **The disclosure isn't yours to carry.** Read, route, log, move on. You are not the customer's therapist or confidant.
- **Pair work on hard cases.** Two agents reviewing a hard ticket together is materially better than one alone.
- **Limits on consecutive hard cases.** Project policy: after a crisis-flagged ticket, the agent does at least 30 minutes of routine work or takes a break before the next.
- **Externalised support.** Project funds an EAP / therapist hotline for support staff; this is workplace standard.

For agentic-only triage (no human triagers), the equivalent is governance: the AI agent does not need self-care, but the *owner* who is reading the crisis-flagged ticket needs the same protection. Don't pile multiple in one bundle for one human to absorb.

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🛟 RESCUE operator | Crisis recognition + handoff |
| ⛔ RED-FLAGS operator | Self-harm / violence routing |
| Pipeline W (Crisis / Safety inbound) | The dedicated pipeline |
| 05-policies.md | Project-specific crisis-resource numbers, reporting obligations, named owners |
| 12-gap-dispositions.md | Crisis categories not yet addressed are explicit gaps |
| AI-AUTO-RESPONSE-GOVERNANCE.md | T4 — agent never freelancing crisis text |

---

## Cross-References

- [runbooks/HOSTILE-USER.md](runbooks/HOSTILE-USER.md) — hostility-toward-you cases
- [EVIDENCE-CHAIN-OF-CUSTODY.md](EVIDENCE-CHAIN-OF-CUSTODY.md) — privileged retention
- [AI-AUTO-RESPONSE-GOVERNANCE.md](AI-AUTO-RESPONSE-GOVERNANCE.md) §T4
- [CUSTOMER-PSYCHOLOGY.md](CUSTOMER-PSYCHOLOGY.md) — apology calibration
- [POLICY-ELICITATION.md](POLICY-ELICITATION.md) — onboarding question for project's crisis policy
