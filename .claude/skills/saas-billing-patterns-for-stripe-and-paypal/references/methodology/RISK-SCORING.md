# Risk Scoring Rubric

Phase 3 scores every `partial` or `missing` gap from the coverage matrix on a 1–9 scale. The score drives Phase 4 prioritization and the executive summary's "top 5 risks" framing.

The score combines three axes — **exploitability**, **customer impact**, and **blast radius** — into a single number, deliberately. The rubric below is calibrated against the source guide's incident catalog so scores are comparable across runs and across reviewers.

---

## The three axes

### Exploitability — how easy is this to trigger?

| Level | Description | Examples |
|-------|-------------|----------|
| 3 | An attacker without insider knowledge can trigger this in <1 day | PayPal `custom_id` hijack: anyone with a PayPal business account can craft a sub naming a victim UUID |
| 2 | Requires moderate effort or specific timing (race conditions) | Pause/resume pool exhaustion: requires concurrent burst load |
| 1 | Requires insider knowledge OR a rare provider failure mode | Reconcile-cancelled-orgs guard: requires a specific replay sequence + cancelled-status precondition |
| 0 | Hygiene / consistency only; no attack vector | Hard-coded API version; not exploitable directly but rots over time |

### Customer impact — what does the customer experience?

| Level | Description | Examples |
|-------|-------------|----------|
| 3 | Money lost / charged twice / access revoked wrongly | Tom Hunter triple-charge; PayPal partial refund stripping access |
| 2 | Visible disruption (wrong number, broken state, missed alert) | MRR card stale during outage; refund alert lost |
| 1 | Internal-only impact (operator confusion, dashboard lies) | Activity feed shows test signups as new subscribers |
| 0 | No customer-visible impact | Naming inconsistency; comment quality |

### Blast radius — how many customers / how much state?

| Level | Description | Examples |
|-------|-------------|----------|
| 3 | All customers OR all subscriptions OR every webhook event | Webhook handler returns 500 → retry storm affecting all events |
| 2 | A class of customers (one provider; one plan; one segment) | PayPal-only hijack class affects all PayPal customers |
| 1 | Bounded set (one cron's batch; one race window) | Stale checkout race affects only customers in mid-checkout when timing aligns |
| 0 | Single record at most | One user's denormalized cache one-time-stale |

---

## Combining into 1–9

```
score = exploitability + customer_impact + blast_radius   (max = 9)
```

Then map to severity:

| Score | Severity | SLA expectation |
|-------|----------|-----------------|
| 9 | Critical / Drop everything | Same-day fix; stop unrelated work |
| 7-8 | High | Fix this sprint; not blocked behind features |
| 5-6 | Medium | Fix this quarter; tracked with bead |
| 3-4 | Low | Hygiene; group with related cleanup |
| 1-2 | Trivial | Backlog or "next time we touch this file" |

---

## Calibration anchors (real incidents)

Use these to calibrate your scoring. If your gap feels worse than X but better than Y, score in between.

| Score | Anchor | Why |
|-------|--------|-----|
| 9 | Tom Hunter triple-charge (`bd-1m86f`) — 3-hour-late webhook + DB-only checkout guard caused customer to be charged 3x | E=2 (rare timing) + C=3 (money lost) + B=3 (could affect any customer) — wait, that's 8. Bumped to 9 because the customer impact was specifically dollar-loss, not just "broken state." (Anchor adjustment: when money is lost, +1.) |
| 9 | PayPal team hijack (SA-01 / `bd-08xvg.1`) | E=3 (anyone with PayPal account) + C=3 (free upgrade) + B=2 (one team at a time, but any team) — = 8, bumped to 9 because the attack is unattended |
| 8 | Marco Fanti silent webhook loss (`bd-1ug5i`) | E=1 (provider edge case) + C=3 (paid customer never activated) + B=3 (could affect any future event) = 7, bumped to 8 because the silent nature delayed detection by weeks |
| 8 | Synchronous cache invalidation missing on refund (SA-02) | E=2 (refund triggers it) + C=3 (refunded user retains paid features) + B=3 (every refund affected) = 8 |
| 7 | Stale-event ordering missing (no `last_event_at` WHERE) | E=2 (provider replay timing) + C=3 (state revival) + B=2 (per-event class) = 7 |
| 7 | Webhook handler returns 500 after `recordWebhookEvent` succeeds | E=1 (any handler bug) + C=3 (duplicate side effect) + B=3 (every event class) = 7 |
| 6 | Cron missing `pg_try_advisory_lock` on multi-isolate environment | E=2 (cron overlap) + C=2 (duplicate processing observable in admin) + B=2 (one cron's batch) = 6 |
| 6 | Email queue without priority column → newsletter delays refund alert | E=1 (timing-dependent) + C=2 (delayed customer alert) + B=3 (every alert that backs up) = 6 |
| 5 | Analytics-exclusion missing on a new admin event publisher | E=1 (every admin login) + C=1 (operator confusion) + B=3 (every test signup ever) = 5 |
| 5 | `STRIPE_API_VERSION` hardcoded in 3+ places | E=0 + C=2 (drift on next upgrade) + B=3 (everywhere it's hard-coded) = 5 |
| 4 | Cache read missing `provenance` envelope | E=0 + C=2 (stale number rendered) + B=2 (per-renderer) = 4 |
| 4 | Cron missing terminal-stuck digest | E=0 + C=1 (operator never sees stuck rows) + B=3 (one cron's stuck-set) = 4 |
| 3 | Email type added without explicit priority branch | E=0 + C=1 (mis-prioritized) + B=2 (one email type) = 3 |
| 3 | Drift-guard test missing for a present-but-implicit invariant | E=0 + C=0 + B=3 (regression risk on next refactor) = 3 |
| 2 | Function naming inconsistency across bundles | E=0 + C=0 + B=2 = 2 |
| 1 | Comment removed during refactor; replaced with worse comment | E=0 + C=0 + B=1 = 1 |

---

## Adjustments

These are explicit bumps / reductions that override the additive base.

- **+1 if money is involved.** Any gap that can cause an over- or under-charge gets a +1.
- **+1 if the attack is unattended.** Hijack classes that don't require the attacker to babysit deserve a bump (PayPal team hijack is 9, not 8).
- **+1 if the failure mode is silent.** Bugs that only surface as customer support tickets are worse than bugs that fire alarms (the silent-loss class).
- **−1 if there's an existing layer that catches it.** A `partial` finding in the live webhook layer is less severe if the verify-as-write path or reconciliation cron covers it.
- **−1 if the gap is greenfield (no production exposure yet).** A `missing` row in pre-launch code is less acute than a `partial` row in production code.

The adjustments stack but cap at score=9 and floor at score=1.

---

## Distribution sanity check

A good scored-gaps file has roughly this shape (proportions, not absolute counts):

| Severity | % of gaps |
|----------|-----------|
| Critical (9) | 0–5% |
| High (7-8) | 10–25% |
| Medium (5-6) | 35–50% |
| Low (3-4) | 25–40% |
| Trivial (1-2) | 5–15% |

If everything is 5, you didn't score; you marked. Re-score, leaning into the calibration anchors.

---

## Severity-to-mode pairings

The risk distribution should match the user's mode:

- **Predominantly Critical/High** → recommend `harden-incident` or move directly into `audit-and-fix` with the highest-severity gaps as the first PR.
- **Mostly Medium with a few High** → standard `audit-and-fix`.
- **Mostly Low/Trivial** → propose `add-feature` (the system is in good shape; the user's energy is better spent on a feature) OR `compliance-pass` if there's an external driver.
- **No Critical/High** in production code → strong signal the user can ship the risk-scored report and pick this up next quarter.

The executive summary should make this recommendation explicitly.

---

## Communicating to non-engineers

The executive summary translates scores into business language. Use this dictionary:

| Score | Phrase | Dollar/time framing |
|-------|--------|---------------------|
| 9 | "Critical — risks paying-customer trust or unauthorized charges" | "$X immediate exposure if exploited; <Y> hours to fix" |
| 7-8 | "High — known incident class without sufficient defense" | "Y customer-support hours per month if it bites; Z days to fix" |
| 5-6 | "Medium — defense partial; reduces but doesn't eliminate exposure" | "Slows incident response by N hours; one sprint to close" |
| 3-4 | "Low — operational hygiene" | "Affects audit / dashboard quality; group with related cleanup" |
| 1-2 | "Trivial — code quality" | "No business impact; address opportunistically" |

Avoid "we have N issues" without breakdown. "We have 3 critical and 12 high gaps, all in the webhook layer" is a story; "we have 64 issues" is noise.
