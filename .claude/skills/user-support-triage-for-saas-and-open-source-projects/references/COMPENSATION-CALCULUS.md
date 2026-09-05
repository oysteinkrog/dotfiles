# Compensation Calculus — When To Refund, Credit, Upgrade, Or Decline

This file is the decision frame underneath the `🎁 GOODWILL` operator and the refund / billing runbooks. The decision *to compensate* is owner judgment; the decision *what shape* the compensation should take can be made much more consistent from a small number of inputs. This file standardizes that decision so every triage session reaches similar outcomes for similar cases.

> **Core insight:** compensation decisions are routinely made by gut feel, but the gut systematically over-pays for loud customers and under-pays for silent valuable ones. A simple decision frame removes most of the bias.

---

## The Five Compensation Currencies

| Currency | What it costs you | What it gives the customer | When it's right |
|---|---|---|---|
| **Refund (cash back)** | Direct revenue loss + Stripe/PayPal fee non-refundable + LTV impact | Their money back; ends the relationship cleanly | Customer paid for something they didn't get; or churn is already locked-in |
| **Credit / pre-paid balance** | Deferred revenue (cheap; expires) | Apology weight + reason to come back | Service issue, customer is staying; the harm was experiential not financial |
| **Plan upgrade (free month/year of higher tier)** | Differential revenue only; near-zero marginal cost | Tangible "you got something more" feel | Plan-tier was the implicit issue; or the bug was tier-blocking |
| **Service extension / renewal forgiveness** | Deferred revenue (cheap) | Time, which is what they often actually wanted | Annual customer who lost ~N days of service |
| **Goods (swag / partner-product / call with founder)** | One-off cost; high signal | "They cared enough to do something extra" | Strategic customer, public-trust risk, or symbolic apology weight needed |

**Default ranking** (cheapest-for-you, highest-signal-to-customer first):
1. Service extension
2. Plan upgrade
3. Credit
4. Refund
5. Goods (rare, intentional)

Most teams default to refund first because it's the obvious move; **credit is usually better** for both sides when the customer is staying.

---

## The Four-Dial Decision Frame

For any compensation decision, dial in four numbers, then read the action off the matrix.

### Dial 1: Harm

What did the customer actually lose?

| Level | Description | Examples |
|---|---|---|
| H1 | Inconvenience only | Slow page; needed to refresh; saw an outdated value |
| H2 | Time / effort | Needed to retry; had to find a workaround; wrote support |
| H3 | Money or data | Charged twice; lost a feature they paid for; settings reset |
| H4 | Reputation or downstream | Their customer / boss / regulator saw the problem |
| H5 | Material damage | Data loss they can't recover; locked out during a deadline; security incident |

### Dial 2: Fault

How clearly is it your fault?

| Level | Description |
|---|---|
| F1 | Customer error — clear |
| F2 | Customer + product (confusing UX, sharp edge) |
| F3 | Mostly product (a bug, but with a workaround they could have found) |
| F4 | Pure product fault — bug, regression, outage |
| F5 | Compounded — the bug *plus* a slow / wrong / missing support reply made it worse |

### Dial 3: Customer LTV

| Level | Profile |
|---|---|
| L1 | Free tier, no purchase intent |
| L2 | Trial / new paid (<3 months) |
| L3 | Steady paid customer (>3 months) |
| L4 | High-value (annual, top decile of plan, or strategic logo) |
| L5 | Champion: writes about you, refers others, public reference |

### Dial 4: Virality Risk

| Level | Description |
|---|---|
| V1 | No public surface; will not post |
| V2 | Has a public/social profile but little known audience reach |
| V3 | Active on relevant forums or communities (HN, industry Slack/Discord, LinkedIn, Reddit, GitHub, etc.) |
| V4 | Known voice in the project's market, niche-influential, partner-adjacent, or press-adjacent |
| V5 | Already public — they posted before / while writing in |

### The Read

Add the four dials. Match the sum to the action band.

| Sum | Band | Default action |
|---|---|---|
| 4-7 | Apology only | Specific apology + fix; no compensation |
| 8-11 | Goodwill | Specific apology + small credit/service extension within local policy (starter SaaS default: roughly $5-25 or 1 week-1 month) |
| 12-15 | Real compensation | Refund the specific harm + credit OR plan upgrade for 1-3 months |
| 16-18 | Heavy compensation | Full refund + extended credit + named owner follow-up |
| 19-20 | Save-the-relationship | Owner-led personal outreach + bespoke remedy + structural change visible to them |

The bands are starting points, not authority to spend. The owner and local policy always overrule, but having a default keeps related cases consistent (otherwise customer A who posts publicly gets $200 and customer B who emails the same complaint gets $20, and that ratio leaks).

---

## Concrete Worked Examples

**Case 1**: Free user, page loaded slow once, no public-trust risk.
- H1 + F2 + L1 + V1 = 5 → Apology only.
- "You're right, that page is slow on first load. We're working on it. Sorry for the wait."

**Case 2**: Steady paid user, charged twice on annual renewal, has no public surface.
- H3 + F4 + L3 + V1 = 11 → Goodwill.
- Refund the duplicate charge (that's not "compensation," that's owed money), plus a one-month credit for the inconvenience. Apology names the root cause.

**Case 3**: Annual high-value account, 3-hour outage during their product launch, they posted to LinkedIn.
- H4 + F4 + L4 + V3 = 15 → Real compensation.
- Refund prorated for 3 hours doesn't cut it. Offer 1 month credit + 30-min call with engineering lead + a named single-point-of-contact for next 90 days. Public reply on LinkedIn from owner: short, owns the failure, no excuses, names the fix.

**Case 4**: Hobbyist OSS user with a small CLI install, lost local config because of a regression.
- H3 + F4 + L1 + V2 = 10 → Goodwill.
- For OSS, the "compensation" is non-monetary: shipping the fix fast, naming them in release notes, offering to co-author a post. That signals more than a coupon would.

**Case 5**: Champion customer, security disclosure they sent privately and you handled badly.
- H4 + F5 + L5 + V4 = 18 → Heavy compensation.
- Public credit (with consent) + bug bounty even if your program normally doesn't pay this class + structural change in disclosure handling + personal apology from owner + invitation into private security mailing list / advisory.

---

## What NOT To Compensate

These cases look compensable but aren't:

- **A demand without harm.** "Give me a refund or I'll post about you." Harm = 0; fault = 0. Decline; document. Pretend the threat didn't happen — answer the underlying question if any.
- **Repeat of the same incident with the same customer.** First time: real apology + compensation. Second time on the same root cause: deeper apology plus structural fix visible to them. Fresh compensation may still be right for material harm, but never let repeat credits replace the fix.
- **Outage that was within SLA.** SLA terms are a contract. Honour them; don't automatically over-pay outside them or you erode the SLA. You may still compensate when the customer's actual harm exceeds the contractual math.
- **Cases where the customer asks for a specific dollar number.** Negotiate to *non-cash* equivalent if at all possible. Dollar anchors corrupt later cases.

---

## The "Was This Avoidable?" Multiplier

If a fix-cause review (`POST-INCIDENT-RETRO.md`) shows the incident was *avoidable* — known root cause, prior similar incident, ignored alert — bump the band up one. The customer effectively paid for an avoidable failure; the multiplier acknowledges that.

If the incident was *novel and rare* — unprecedented, low-frequency root cause, well-handled response — keep the band where it is. Customers reward calm response to novel problems.

---

## Compensation Templates

These slot into the project's `04-templates/`. They are written in neutral voice; project-specific voice ([VOICE-CALIBRATION.md](VOICE-CALIBRATION.md)) overrides them.

**Owner-approval boundary:** every template below is a draft. Refunds, credits, plan changes, service extensions, public credits, and gifts are customer-visible or account-visible side effects and still require `✓ CONFIRM` plus the project's approval policy before execution.

### Refund + apology (band 12-15)

> You're right — your $X charge ran twice on [date]. That was on us; [one-sentence root cause]. Refund of $X is in flight (transaction ref [TXN]; should hit your card in 2-3 business days). I've also added [credit / month] to your account for the time this took.
>
> If the refund doesn't appear by [date+5 business days], reply here and I'll chase the payment processor directly.

### Credit instead of refund (band 8-11)

> Quick update: I've added [N months / $Y] of credit to your account, applied to next renewal. Mostly because the [specific issue] should not have taken three replies to sort out, and that's on us, not you. Your account page should reflect it within an hour. No action needed.

### Service extension (band 8-11, common for outages)

> [date] outage cost you about [duration] of service. We've extended your subscription by [duration + 50% buffer] at no charge — your renewal date is now [new date]. The postmortem is at [link]; the structural change is [one sentence].

### Plan upgrade (band 12-15, when bug was tier-blocking)

> The [feature] you needed was on the [higher] plan but the [tier] you're on shouldn't have hit [bug] in the first place. I've upgraded you to [higher] for [3 months] at no charge. After that, if it's not pulling its weight for you, I'll downgrade you back. No second opt-in required.

### Heavy compensation (band 16+)

> [Customer name] — [Owner name] here. Three replies and the issue still isn't resolved cleanly. That's on me, not on the team you've been writing to. Here's what I'm doing:
>
> 1. Full refund for [specific scope] is in process now ($X; [TXN]).
> 2. Your renewal next month is on the house; I'll credit it directly.
> 3. I'm setting up a 30-minute call with [engineer name] for [next 3 weekdays]; they're the one who can actually un-stick the [integration] and walk you through what we're changing so this can't recur.
> 4. I'd like to send a short postmortem when it's written (~5 days). You don't need to read it; it's just so you know we tracked it back to a real cause and not a vague "we improved monitoring".
>
> Apologies — I should have been on this on day one.

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🎁 GOODWILL operator | Decision frame |
| ⚖ DECIDE operator | Compensation column on refund / billing rows of the project decision matrix |
| `runbooks/REFUND.md` | Imports the band table |
| `runbooks/BILLING-DEEP.md` | Imports the band table |
| 📈 OUTCOME records | Compensation decisions logged with band + dials so cohorts are auditable |
| `05-policies.md` | Project-specific overrides (e.g., "we never offer >1 month free") |

---

## Cross-References

- [CUSTOMER-PSYCHOLOGY.md](CUSTOMER-PSYCHOLOGY.md) §"Anchoring & Concession Mechanics"
- [DECISION-MATRIX.md](DECISION-MATRIX.md)
- [runbooks/REFUND.md](runbooks/REFUND.md)
- [runbooks/BILLING-DEEP.md](runbooks/BILLING-DEEP.md)
- [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md) — the avoidability multiplier source
