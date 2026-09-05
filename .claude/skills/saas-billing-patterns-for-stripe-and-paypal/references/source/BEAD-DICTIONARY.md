# Bead Dictionary

Carried from Appendix B of the source guide. These bead IDs are the project-specific tracking for the source guide's project (`/data/projects/jeffreys-skills.md`). Your project's beads will have different IDs — these are useful as **trace anchors** when reading the source guide and as **naming conventions** for regression tests.

When you write a regression test for a hijack defense, name it after the source bead:

```ts
test('bd-08xvg.1__paypal_team_hijack_subscription_id_cross_check', async () => { ... });
```

Even though `bd-08xvg.1` doesn't exist in YOUR project's beads, the name carries the trace. Future-you (or a fresh-eyes reviewer) can grep the source guide for `bd-08xvg.1` to find the full incident detail.

---

## Top-level epics

| Bead | Title | Status |
|------|-------|--------|
| `bd-yqo1` | EPIC: Payment Integration (Stripe + PayPal) | closed |
| `bd-14kyb` | EPIC: PayPal Payment Integration Fix & Reliability | closed |
| `bd-1qk87` | SUB-EPIC: Payment & Subscription Flow Improvements | closed |
| `bd-3m5v` | Webhook reconciliation cron (originator) | closed |
| `bd-yu9g9` | Billing-H4 hold pause/resume Stripe writes outside tx | closed |
| `bd-hbfat` | Billing-H2 fetch parent payment for partial refund | closed |
| `bd-ja8c0` | Billing-H1 out-of-band escalation when email queue fails | closed |
| `bd-2ddl3` | Payment Fee Tracking Service | closed |
| `bd-y2mp3` | Verify subscription in DB after checkout success URL | closed |
| `bd-mhox6.2.2.2` | MOR-22B reconciliation freshness telemetry | closed |

---

## Critical incidents

| Bead | Title | Severity at time |
|------|-------|------------------|
| `bd-1m86f` | P0 Triple-charge incident (Tom Hunter) | Critical |
| `bd-1ug5i` | Marco Fanti silent webhook loss | High |
| `bd-08xvg.1` | SA-01 PayPal team webhook subscription hijack | Critical |
| `bd-08xvg.3` | SA-03 Exclude cancelled orgs from reconcile revival | High |
| `bd-2gxws` | PayPal individual webhook custom_id hijack | Critical |
| `bd-1zzos` | Stripe webhook 200-on-error to stop retry storms | High |
| `bd-lp3vu` | Bullet-proof billing flows: post-Rahim hardening pass | open |
| `bd-lp3vu.1` | Stripe success_url URL-encoding fix | open |
| `bd-lp3vu.1.1` | Static lint rule + type-safe success_url builder | open |
| `bd-lp3vu.2.1` | Stripe verify-as-write activation | open |
| `bd-lp3vu.3.1` | Recent-checkout reconciliation cron (5-min SLO) | open |
| `bd-lp3vu.3.2` | Webhook delivery health monitor | open |
| `bd-vifc1` | Centralize STRIPE_API_VERSION across 13 instances | closed |

---

## Medium-severity bundle

| Bead | Title | Status |
|------|-------|--------|
| `bd-bfwcy` | Bundle of 8 medium review findings (parent) | open |
| `bd-bfwcy.3` | BILLING-M1 dedicated compliance event for system alerts | closed |
| `bd-bfwcy.4` | BILLING-M2 stale-checkout race guard | closed |
| `bd-bfwcy.5` | BILLING-M3 priority queue for email_jobs | closed |
| `bd-bfwcy.6` | BILLING-M5 orphan-cancel rows inside delete tx | closed |
| `bd-bfwcy.7` | BILLING-M5b bound retry-individual-sub-cancels | closed |

---

## Security audit findings

| Finding | Bead | Title |
|---------|------|-------|
| SA-01 | `bd-08xvg.1` | PayPal team webhook subscription hijack |
| SA-02 | (inline) | Synchronous cache invalidation on refund |
| SA-03 | `bd-08xvg.3` | Exclude cancelled orgs from reconcile revival |
| SA-06 | (inline) | Rate limiter `FAIL_CLOSED_ENDPOINTS` |
| SA-13 | (inline) | Admin retry path overrides + audit |
| SA-17 | (inline) | Hijack defense regression suite |
| SA-22 | (inline) | Suppress automatic replay after bookkeeping failure |

---

## Naming convention for YOUR project's regression tests

Pattern: `<your-project-bead-id>__<short_description>` OR (if you want the source-guide trace) `<source-bead-id>__<short_description>`.

Examples:
- `acme-billing-22__triple_charge_cross_provider_guard.test.ts`
- `bd-1m86f__triple_charge_cross_provider_guard.test.ts`  (using source-guide ID for trace)
- `bd-08xvg.1__paypal_team_hijack_subscription_id_cross_check.test.ts`
- `bd-bfwcy.5__priority_queue_refund_before_newsletter.test.ts`

Either works; what matters is that the test name is greppable and tells future-you what contract is pinned.

---

## When to file a new bead vs. reuse a name

- **New bead** when your project encounters a NEW failure mode not covered by the source guide. Document it; pin a regression test; add to your project's failure-mode catalog.
- **Reuse the source-guide name** when your project hits the SAME failure mode the source guide covered. The test name carries the trace; readers can find the original detail.
- **Augment** when your project's incident is a variation. Naming: `bd-1m86f-acme-variant__quadruple_charge_with_marketplace.test.ts`. Cite both the source and your project's variant.
