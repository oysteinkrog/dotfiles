# Deceased User & Account Succession — When The Owner Is Gone

A small but consequential class of tickets: a family member or executor writes saying the account-holder died. Or a business operator writes that a co-founder/employee died and they need access. These tickets sit at the intersection of grief, identity verification, legal-document review, privacy obligations, and account ownership transfer. The skill is silent on this until you need it, at which point you really need it. This file is the protocol.

> **Core insight:** the legitimate path through a deceased-user request and the social-engineering path that abuses it look identical from the first email. The discipline of slow, document-anchored verification protects the dead user's privacy (and the company from liability) while still giving the bereaved family an actual path. Skipping the discipline harms both sides.

This file complements `runbooks/ACCOUNT-RECOVERY.md` (lost-access cases for the *account holder themselves*) and `EVIDENCE-CHAIN-OF-CUSTODY.md` (because these tickets often involve legal documents that go into permanent retention).

---

## The Five Common Inbounds

| Inbound | Sender | Want |
|---|---|---|
| **Family notifies of death** | Spouse, parent, child, executor | Cancel subscription; some access to data; sometimes deletion |
| **Family seeks data export** | Same | Photos, documents, work product, sentimental content |
| **Business partner needs ownership transfer** | Co-owner, cofounder, designated successor | Continue running the business; access shared resources |
| **Estate executor seeks legal access** | Lawyer with letters of administration / probate documents | Legal access per court order |
| **Memorialise / preserve the account** | Same family roles | Public profile becomes static memorial; no further changes |

Project-specific contexts add categories (a fertility tracking app may see "my partner died and I want our shared cycle history saved"; a freelancer-marketplace sees "the freelancer died and the client paid in escrow").

---

## The Core Tension

You owe duties to two parties:

1. **The deceased user**: their privacy persisted past death (in many jurisdictions, especially EU/EEA); their wishes (where documented) must be honored; their account is not a generic-purpose-token to hand over.
2. **The legitimate inheritor / executor / family member**: they need real, often time-sensitive access to handle estate matters, prevent fraud against the estate, or simply close out the deceased's affairs.

A "default open" policy violates duty 1; a "default closed" policy violates duty 2. The protocol exists to thread between.

---

## The Verification Discipline

Strictness should match what's at stake. Tiers:

### Tier A: Subscription cancellation; refund of unused period

Lowest stakes. Possible verification path:

- Death certificate (PDF / scan acceptable; no original)
- Sender's relationship to deceased (self-declared)
- Cancellation effective from death-of-record date
- Refund prorated to active payment method

A clean operational answer that doesn't require litigation-grade verification. Usually safe to handle within one ticket cycle.

### Tier B: Data export (sentimental content; not financial data)

Medium stakes. Verification:

- Death certificate
- Court document indicating sender's authority (executor letter, power-of-attorney persisting through death where applicable)
- OR: a notarised affidavit from the sender attesting to relationship + responsibility
- 30-day cool-down period before any export; published on the account if possible
- Notification sent to account email (in case account-holder was someone else than the deceased; catches misidentification)

This is where social-engineering attempts cluster. Patterns to watch:

- Death certificate that's been crudely photoshopped
- Sender's name doesn't match documents
- Documents from a different jurisdiction than sender claims
- Urgent timeline asserted ("deadline tomorrow")
- Refusal to wait the cool-down ("you're stopping me from grieving")

### Tier C: Account ownership transfer (full control; financial implications)

High stakes. Verification:

- Death certificate
- Probate / letters of administration / similar court document specifically naming the sender as authorised
- Signed declaration from sender accepting responsibility for the account
- 60-90 day cool-down (jurisdiction-dependent)
- Counsel review per `EVIDENCE-CHAIN-OF-CUSTODY.md`

This is rarely the right answer. Most platforms cannot legally hand over an account; they can only close it. If the sender insists on ownership transfer, that often means closure + new account with fresh data is the actual path.

### Tier D: Memorialisation

Some platforms support "frozen" account state — readable by friends, no further changes possible. Verification: same as Tier B. Mechanic: lock the account with a `memorialised: true` flag; no further sign-ins; profile reads "In memoriam" or similar.

---

## Special Categories

### Business co-owner needs access

Different from family. Verification:
- Corporate documents establishing co-ownership / successor authority
- Death certificate
- Board resolution / partnership agreement / operating-agreement clause invoked
- Cool-down period shorter (operational urgency higher)

Often the right path is "the company's continuity authority is established here; we'll work with that," not "the deceased's family decides." The deceased was an *agent* of the business; the business has its own continuity rights.

### Shared-account scenarios

The deceased was on a household / family / team plan. Other plan members survive. The plan continues; the deceased's seat is removed; their data may persist or be deleted per their pre-death preferences (if recorded) or the plan-admin's request.

### Pre-stated wishes

Some users specify post-death preferences (Apple's Legacy Contacts, Google's Inactive Account Manager, custom platform settings). These supersede family requests:

- If the deceased designated a Legacy Contact, that contact's request takes precedence
- If the deceased configured "delete after N years inactive," the timer is now running and family requests don't override
- Discover whether such a designation exists *before* engaging family on access

### Minor's account

If the deceased is a minor:
- Parental access may be inherent (depending on jurisdiction)
- COPPA in the US has specific rules
- Often "show me everything" is the right answer; rare social-engineering target

### Deceased who used the platform under a pseudonym

The platform doesn't know "Jane Doe" died; it knows "@cooluser2024" hasn't logged in for 3 weeks. Family may not even know the platform exists. If they discover it: verify pseudonym ↔ deceased identity before engaging.

---

## The Reply Tone

These are grief-touching interactions. The reply tone is `CUSTOMER-PSYCHOLOGY.md`'s heavy-apology-spectrum, modulated for grief specifically:

- Acknowledge the loss specifically (not "we're sorry to hear this")
- Be honest about the timeline of what's possible
- Don't add commercial elements ("by the way, our family plan...")
- Don't reference urgency / SLA / business-day language unless relevant
- Sign with a real human name; not "the team"

A workable opening:

```
[Subject: Re: Account for [name of deceased]]

[Sender name] — I'm sorry for your loss. Whatever timeline is workable
for you is fine on our end.

To set expectations: [specific path forward, with tiered options if any]

For the verification step, you'll need to send: [documents, listed]

There's no rush. Reply when you're able and we'll move forward at
your pace.

— [Your name], [Role]
```

What's not there:
- Marketing footer
- "Rate this support interaction"
- "Did this resolve your question?"
- Auto-reminders if they don't reply

---

## What Documents Look Like (For Verification)

Brief reference for triage agents (counsel-jurisdiction-specific in detail):

- **Death certificate**: official document from civil registrar; in US, format varies by state; in EU, often a national format. Standard fields: deceased name, date of death, place, cause (sometimes redacted), informant.
- **Letters of administration / Letters testamentary**: court document appointing executor / administrator. Names the deceased and the appointed person explicitly. May have an expiration / re-issuance date.
- **Probate document**: court order finalising the estate.
- **Notarised affidavit**: sender's signed declaration witnessed by a notary.
- **Power of attorney**: usually expires at death; do not accept POAs as verification.

For high-stakes (Tier C) cases, counsel reviews documents for authenticity. For Tier A, the documents serve as good-faith evidence rather than forensic verification.

---

## Retention Of Disclosed Material

A death certificate is sensitive PII. The temptation is to keep it forever in the ticket; the right answer is:

- Hash the document; retain hash + receipt-of-document timestamp + verification result
- The document itself goes to a privileged retention bucket per `EVIDENCE-CHAIN-OF-CUSTODY.md`; not in clear-text ticket history
- Customer's other communications stay in normal ticket retention
- Internal note: "death certificate received and verified; document in privileged store"

Treat these documents like Tier-3 PII — minimum-necessary retention, restricted access.

---

## When To Refuse

You can refuse verification if:

- Documents look forged or implausible
- Sender's relationship can't be substantiated
- Pre-stated wishes contradict the request
- Jurisdiction or platform rules prohibit (e.g., COPPA constraints on minor's accounts)
- Counsel review (Tier C) returns negative

Refusal must be respectful and provide a path: "We can't proceed with the data export based on the documents provided. The path forward would require [specific document] / [legal counsel's involvement]. We're sorry not to be able to help directly."

Never simply ignore. Never escalate to investigative-tone questioning ("how do we know you're really their daughter?"). Either accept the documents or escalate to counsel.

---

## When This Becomes Press / Legal

A small fraction of these escalate:

- Family is unhappy with the timeline / restrictions; goes to local press
- Family pursues legal action ("you're holding our father's photos hostage")
- Regulator inquiry (rare but happens, especially in EU / California)
- Public outcry on social media

For all of these: switch to Pipeline T (Press) or Pipeline U (Regulator) per the existing playbook. The discipline above protects the company in audit; it does not protect against negative coverage. Coverage protection comes from *humanity* of the response, not just rigour.

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🪦 SUCCESSION operator | Recognise + route deceased-user inbounds |
| Pipeline AB (Estate / Succession) | Dedicated pipeline |
| 🏛 ENTERPRISE operator | When business-owner death triggers operational continuity |
| EVIDENCE-CHAIN-OF-CUSTODY.md | Document retention |
| 05-policies.md | Project's verification tier requirements |
| AI-AUTO-RESPONSE-GOVERNANCE.md §T3-T4 | Agent never auto-handles |
| TRAUMA-INFORMED-SUPPORT.md | Adjacent emotional handling |

---

## Cross-References

- [runbooks/ACCOUNT-RECOVERY.md](runbooks/ACCOUNT-RECOVERY.md) — adjacent recovery flow
- [TRAUMA-INFORMED-SUPPORT.md](TRAUMA-INFORMED-SUPPORT.md) — emotional handling patterns
- [EVIDENCE-CHAIN-OF-CUSTODY.md](EVIDENCE-CHAIN-OF-CUSTODY.md) — privileged retention
- [FRAUD-AND-ABUSE-DETECTION.md](FRAUD-AND-ABUSE-DETECTION.md) — social-engineering vector
- [POLICY-ELICITATION.md](POLICY-ELICITATION.md) — onboarding question for project's deceased-user policy
- [CUSTOMER-PSYCHOLOGY.md](CUSTOMER-PSYCHOLOGY.md) — apology calibration baseline
