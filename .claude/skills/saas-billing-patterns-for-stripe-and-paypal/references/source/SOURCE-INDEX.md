# Source Guide Index

The pattern bundles in `references/patterns/` are distillations of the master guide at `COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md`. This file maps each section of the source guide to the pattern bundle that owns it.

When in doubt during Phase 5 implementation, read the source-guide section directly — it has more incident detail and code-quote excerpts than the bundle distillations.

---

## Section → Bundle map

| Source § | Title | Bundle |
|----------|-------|--------|
| 1 | North-star principles | B00 |
| 2 | Architecture overview — the layered defenses | B00 |
| 3 | Schema design — the four load-bearing tables | B10 |
| 4 | Single-source-of-truth constants (env, pricing, API versions) | B20 |
| 5 | Provenance envelopes — never lie about freshness | B100 |
| 6 | Provider-symmetric checkout — the canonical sequence | B30 |
| 9 | Idempotency keys — Stripe vs. PayPal | B20, B30 |
| 10 | Webhook ingestion contract — the 5-step skeleton | B40 |
| 12 | `updateSubscriptionStatus` — the canonical writer | B40 |
| 13 | Webhook hijack defense — three layers | B50 |
| 14 | PayPal individual hijack: `validatePayPalUserId` | B50 |
| 15 | PayPal team hijack: `subscription_id` cross-check on every UPDATE | B50 |
| 16 | Replay-staleness gating with `last_event_at` | B50 |
| 17 | Reconcile cancelled-orgs guard (SA-03) | B50 |
| 18 | Rate limiter `FAIL_CLOSED_ENDPOINTS` (SA-06) | B50 |
| 19 | Admin retry path — age cutoff, regression guard, override audit (SA-13) | B50 |
| 20 | Synchronous cache invalidation on refund (SA-02) | B60, B100 |
| 21 | Suppress automatic replay after bookkeeping failure (SA-22) | B50 |
| 22 | Security event taxonomy | B50 |
| 23 | Abuse signal cooldowns | B50 |
| 24 | Subscription state model + aggregate projection | B60 |
| 25 | The `paused_for_org` status | B60 |
| 26 | Grace period — Edge-compatible single source | B60 |
| 27 | Verify-as-write — never trust the webhook alone | B40, B60 |
| 28 | Stale-checkout race guard (BILLING-M2) | B30, B60 |
| 29 | Cross-provider duplicate-sub guard (bd-1m86f) | B30 |
| 30 | Refund handling — the asymmetric strict path | B60 |
| 31 | PayPal partial-refund detection (Billing-H2) | B60 |
| 32 | Dunning ladder + suspension | B70 |
| 33 | Manual invoice retry with 4-guard overcharge defense | B70 |
| 34 | SCA / 3-D Secure routing in dunning | B70 |
| 35 | Team coverage suppression in dunning | B70 |
| 36 | Card-expiry pre-warning | B70 |
| 37 | Pre-charge upcoming-renewal notification | B70 |
| 37a | No-discount / no-trial provider controls | B70 |
| 37b | Product-policy portability | B70 |
| 38 | Customer Portal deep-links | B70 |
| 39 | Two-tier seat pricing model | B80 |
| 40 | Seat-aware checkout under advisory lock | B80 |
| 41 | Seat updates with proration asymmetry | B80 |
| 42 | Pause/resume — intent-then-act pattern (Billing-H4) | B80 |
| 43 | Team subscription state transitions | B80 |
| 44 | Team dunning ladder (compressed timeline) | B80 |
| 45 | Individual → team upgrade with orphan-cancel | B80 |
| 46 | Orphan-cancel queue (post-deletion ghost subs) | B90 |
| 47 | Webhook reconciliation core + per-event claim lease | B90 |
| 48 | Webhook-staleness alarm + terminal-stuck digest | B90 |
| 49 | Provider-authoritative reconciliation sweep | B90 |
| 50 | Daily billing integrity audit (the backstop) | B90 |
| 51 | Cron defenses — advisory locks, bounded scans, dry-run | B90 |
| 52 | Email queue priority + failsafe escalation | B90 |
| 53 | Test-fixture exclusion across analytics | B90, B100 |
| 54 | Admin events — analytics-aware activity feed | B90 |
| 55 | MRR snapshot — multi-layer cache + provenance | B100 |
| 56 | Canonical-only MRR — exclude fallback providers | B100 |
| 57 | Single-flight cache stampede protection | B100 |
| 58 | Canonical churn timestamp + replacement-coverage exclusion | B100 |
| 59 | Payment fees — blended effective rate | B100 |
| 60 | Net revenue + fee telemetry snapshot | B100 |
| 61 | Customer health scoring (composite 0-100) | B100 |
| 62 | Behavioral forecasting — driver-attributed churn probability | B100 |
| 63 | Monte Carlo runway projection | B100 |
| 64 | Reconciliation freshness telemetry (MOR-22B) | B100 |
| 65 | Refund & cancellation policy guardrails | B60 |
| 66 | The `PaymentError` taxonomy | B110, B20 |
| 67 | `PendingCheckoutSessionId` UNIQUE migration (BILLING-L2) | B10, B30 |
| 68 | Drizzle migration discipline | B110, B10 |
| 69 | Real-DB integration tests (no mocks for billing) | B110 |
| 70 | Drift-guard tests for analytics exclusions | B110 |
| 71 | The full Vercel cron schedule | B110 |
| 72 | Failure-mode catalog (38 incidents) | B110 |
| 73 | Patterns that were tried and rejected | B110 |
| 74 | Operational runbooks | B110 |
| 75 | Bead dictionary | B110 (Appendix B) |
| 76 | File map | B110 (Appendix A) |
| 77 | Battle-tested checklist — bringing this to a new SaaS (step-ordered) | B110 |
| 78 | The 9 most common ways this still goes wrong in production | B110 |
| 78a | Cross-references from security-audit-for-saas | B50, B55, B110 |
| 78a.1 | Stripe account/context verification (Connect/org destinations) | B50 |
| 78a.2 | Webhook source = "system" skips abuse cooldowns | B50 |
| 78a.3 | Stripe event coverage | B40 |
| 78a.4 | Webhook observability metrics + Prometheus alerts | B55 |
| 78a.5 | CSP for Stripe Elements / Checkout / Radar | B55 |
| 78a.6 | Credential rotation cadence | B55, B110 |
| 78a.6b | Secret custody hardening | B20, B110 |
| 78a.7 | Webhook timestamp tolerance window (defense-in-depth) | B55 |
| 78a.8 | Cross-provider webhook confusion (BL-42) | B55 |
| 78a.9 | Chargeback abuse process | B55 |
| 78a.10 | Nested side-effect idempotency | B55 |
| 78a.11 | Forward-looking world-class patterns | B55 |

---

## Extension bundles (no direct source-guide section; derived patterns)

These bundles extend the source guide with patterns the source guide doesn't directly cover but that are essential for production billing systems.

| Bundle | Title | Reasoning for extension |
|--------|-------|--------------------------|
| B25 | Customer support integration | The source guide assumes engineering-direct response; real ops have a support tier |
| B45 | Admin operations surface | The source guide describes helpers; this bundle is the UI |
| B55 | Observability + defense-in-depth | Aggregates §78a.4-§78a.11 forward-looking patterns |
| B65 | Test data + fixtures | Source guide §69 mandates real-DB; this bundle is HOW |
| B75 | Tax + accounting | Source guide §59 covers fees; this bundle covers GAAP-aware |
| B85 | Usage-based billing | Source guide focuses on flat-rate; this bundle adds metered |
| B95 | Internationalization + multi-currency | Source guide §4.7 audits Adaptive Pricing; this bundle is the broader pattern |
| B105 | Performance + scale | Source guide §3 mentions indexes; this bundle is the scale playbook |
| B115 | Marketplace + Stripe Connect | Source guide §78a.1 mentions Connect; this bundle is the full implementation |
| B120 | Compliance evidence pack | Source guide §74 mentions compliance; this bundle is SOC2/ISO operationalization |
| B125 | Dispute defense | Source guide §78a.9 covers chargeback ban; this bundle is dispute-RESPONSE |
| B130 | Migration cutover patterns | Source guide doesn't cover provider-migration; this bundle is the playbook |
| B135 | Webhook forensics | Source guide §15 has the smoking-gun query; this bundle is the broader toolkit |
| B140 | Incident response patterns | Source guide §74 has runbooks; this bundle is the code-level helpers |
| B145 | Extended failure-mode catalog | Source guide §72 lists 38 incidents; this bundle organizes + extends |

---

## How to use this index

- During Phase 1 archaeology, this index is what tells the archaeologist which bundle to assign a finding to.
- During Phase 5 implementation, the implementer reads the bundle's pattern doc PLUS the source-guide section for the deeper context.
- During Phase 7 fresh-eyes, reviewers cross-reference findings to the source guide so they can cite the original incident.

The source guide IS the corpus. The bundles are the index. Don't lose the source guide; if you ever need to extend / fork this skill for a related domain, the source guide is what you re-distill.
