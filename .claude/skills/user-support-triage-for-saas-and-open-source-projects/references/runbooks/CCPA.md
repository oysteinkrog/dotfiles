# Runbook: CCPA / CPRA + State Privacy Laws

US state privacy law equivalent of GDPR/DSAR. Different timelines, different verification requirements, different rights. Mishandling = AG fines + CA Privacy Protection Agency action.

## Trigger Conditions

- "I'm a California resident; please [delete / disclose / opt-out]"
- "Do not sell my personal information"
- "Do not share my personal information for cross-context behavioral advertising"
- A formal letter from CA Attorney General or CA Privacy Protection Agency
- Reference to CCPA / CPRA / Cal. Civ. Code § 1798
- A request via Global Privacy Control (GPC) browser signal

## Coverage Threshold

CCPA/CPRA applies to your business if **any** of:
- Annual gross revenue > $25M
- Buys/sells/shares PI of >100,000 CA consumers/households
- ≥50% of revenue from selling/sharing PI of CA consumers

If you're below all three, CCPA technically doesn't compel you. But: the workflow is good practice and complying voluntarily reduces friction if you cross thresholds later.

## The Five Rights (CPRA, in effect since Jan 2023)

| Right | What it means | Article |
|---|---|---|
| **Know** | Get categories + specific pieces of PI collected, sold, shared | § 1798.110, § 1798.115 |
| **Delete** | Erase PI you've collected | § 1798.105 |
| **Correct** | Correct inaccurate PI | § 1798.106 (CPRA addition) |
| **Opt-out of sale/sharing** | Don't sell/share PI for cross-context behavioral ads | § 1798.120, § 1798.135 |
| **Limit use of sensitive PI** | Restrict use of SSN, geolocation, biometrics, etc. | § 1798.121 (CPRA addition) |

## Time Window

**45 days from receipt**, extendable by another 45 days **with notice during the first 45**.

Compared to GDPR: similar but slightly more lenient (45 vs 30 days).

## Identity Verification

CCPA is more lenient than GDPR on verification. CA AG regs (§ 7062-7064):
- Match information already on file (name + email + last-4 of payment, etc.)
- For sensitive PI requests: verify with reasonable degree of certainty
- Don't require unnecessary info (no passport for a routine deletion)
- For known, authenticated user: account verification suffices

## "Do Not Sell / Do Not Share" Mechanics

If you sell or share PI (broadly defined — includes most ad-tech), CCPA requires:

1. **"Do Not Sell or Share My Personal Information"** link on every page (and homepage). Or use the alternative single Privacy Choices link.
2. Honor **Global Privacy Control (GPC)** browser signal automatically. If a request comes from a GPC-signaling browser, treat it as opt-out for that user.
3. Once opted out, can't "ask for opt-in" for 12 months.

If you DON'T sell/share PI: still must say so in your privacy policy.

## "Sale" Definition (Important)

CCPA's "sale" is broader than money-for-data:
- Sharing data with ad networks for retargeting → likely a sale
- Embedding 3rd-party trackers (Meta Pixel, Google Ads, TikTok Pixel) → likely sharing
- Selling email lists → obvious sale
- B2B SaaS: usually NOT a sale (your customer is the data subject's employer's contracting partner)

When in doubt: assume it's a sale and provide the opt-out.

## Other State Laws (Brief)

| State | Law | Effective | Threshold | Notable |
|---|---|---|---|---|
| **VA** | VCDPA | 2023 | 100k consumers OR 25k+ ≥50% revenue from sale | Opt-in for sensitive data |
| **CO** | CPA | 2023 | 100k consumers | Universal opt-out signal honored |
| **CT** | CTDPA | 2023 | 100k consumers | Similar to VA |
| **UT** | UCPA | 2023 | $25M revenue + 100k consumers | Narrower than CA |
| **TX** | TDPSA | 2024 | Any (but exemptions for small biz) | ⚠ aggressive AG |
| **OR** | OCPA | 2024 | 100k consumers | Honors GPC |
| **MT** | MCDPA | 2024 | 50k consumers | Smallest threshold of any state |
| **IA** | ICDPA | 2025 | 100k consumers | Opt-out for sale |
| **TN** | TIPA | 2025 | $25M revenue + 100k consumers | Similar to UT |
| **DE** | DPDPA | 2025 | 35k consumers | Smaller threshold |
| **NJ** | NJDPL | 2025 | 100k consumers | Honors GPC |
| **NH** | NHDPL | 2025 | 100k consumers | |
| **MN** | MCDPA | 2025 | 100k consumers | |
| **RI** | RIDPA | 2026 | 35k consumers | |
| **MD** | MODPA | 2025 | 35k consumers | One of the strictest |

In practice: meet **CCPA + CPRA + GDPR** and you're 95% of the way to all of them. The differences are around (a) thresholds, (b) opt-out vs opt-in for sensitive data, (c) breach-notification timelines.

## Drafts

### CCPA-ACK

```
Thanks — we received your request on <DATE>. Under CCPA/CPRA, we'll
respond within 45 days. If your request is complex, we may extend by
another 45 days and will notify you before <DATE+45>.

To verify your identity: <reply from account email / last-4 of payment
method / for sensitive PI: a redacted government ID>.

Once verified, we'll proceed with: <Right to Know / Delete / Correct
/ Opt-out of Sale-or-Sharing / Limit Sensitive PI>.

You may also designate an authorized agent to act on your behalf. If
applicable, please send their written authorization with this request.
```

### CCPA-KNOW-FULFILLED

Same shape as GDPR access (see [GDPR-DSAR.md](GDPR-DSAR.md)) — provide a ZIP with one CSV per data category + a README.

### CCPA-DELETE-FULFILLED

Same shape as GDPR erasure (see [GDPR-DSAR.md](GDPR-DSAR.md)) but reference CCPA exemptions (§ 1798.105(d)):
- Complete the transaction the data was collected for
- Detect/protect against malicious activity
- Repair errors
- Free speech / CCPA-compliant research
- Legal compliance (tax, audit)

### CCPA-OPT-OUT-PROCESSED

```
Confirmed — your opt-out is active as of <DATE>:

- We will not sell your personal information
- We will not share your personal information for cross-context
  behavioral advertising
- Third-party trackers honoring opt-out signals (Meta, Google) have
  been notified

To resume sharing: visit <link>. You can opt back in at any time, but
we won't ask you to.

GPC: if your browser sends a Global Privacy Control signal, we'll
re-apply the opt-out automatically next time you visit, even if you
opt back in here.
```

### CCPA-AUTHORIZED-AGENT

```
Thanks. We received an authorized-agent request on behalf of <name>
on <DATE>.

To proceed, we need:
1. Written authorization from <name> showing they've given you
   permission to act on their behalf
2. Their identity verification (so we can confirm we're acting on the
   right person's data)

Once received, we'll process within 45 days.
```

## Fee Allowance

Unlike GDPR (which mostly forbids fees), CCPA allows a "reasonable fee" for repeated/excessive requests. **Don't use this** unless someone is genuinely abusing the system — a fee will trigger a CA AG complaint faster than complying again.

## Breach Notification

If a security incident exposes CA residents' PI (CIPPA / CCPA):
- Notify affected residents "in the most expedient time possible and without unreasonable delay"
- Notify CA AG if >500 CA residents affected
- Notification template at [California AG breach reporting](https://oag.ca.gov/privacy/databreach)

## Anti-Patterns

| Don't | Why |
|---|---|
| Use GDPR-strict verification on CCPA requests | "Excessive verification" itself violates CCPA |
| Refuse a request because you're "not sure if they're California" | If they say they are, treat them as CA-resident |
| Take fees for routine requests | Triggers AG attention |
| Ignore GPC signal | CPRA mandates honoring it; CA AG actively enforces |
| Delete sale opt-out after 12 months | Opt-out persists until user opts back in |
| Use a "deceptive" Privacy Choices link | Dark-patterns enforcement is active |

## Companion Refs

- [GDPR-DSAR.md](GDPR-DSAR.md) — EU/UK equivalent
- California AG: https://oag.ca.gov/privacy/ccpa
- CA Privacy Protection Agency: https://cppa.ca.gov/
- IAPP state privacy tracker: https://iapp.org/resources/article/us-state-privacy-legislation-tracker/
