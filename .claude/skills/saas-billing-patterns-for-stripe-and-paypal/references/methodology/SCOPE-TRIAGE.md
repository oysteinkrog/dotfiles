# Scope Triage — Route by Customer Count + ARR + Complexity

The same skill serves a 5-customer pre-launch project AND a $50M ARR multi-product platform. The tier system ensures both get the right depth without overwhelming the former or under-serving the latter.

This is the billing equivalent of the wills skill's wealth-tier triage: it keeps the user from over-building or under-building.

---

## Wealth Tiers (primary axis: customer count + ARR)

| Tier | Customers | ARR | Typical risk profile |
|------|-----------|-----|----------------------|
| **T1 — Pre-launch** | 0 | $0 | Greenfield; the skill's core job is to land the foundation correctly so future tiers don't inherit tech debt. |
| **T2 — Early-stage** | 1–500 | <$100K | Friends-and-family + first paying customers. Single incident is a customer-trust catastrophe; defenses must be at production quality even at low volume. |
| **T3 — Growth** | 500–10K | $100K–$5M | Monthly incidents are statistically certain. Reliability machinery (B90), reporting backend (B100), and runbooks (B110) become load-bearing. |
| **T4 — Scale** | 10K–500K | $5M–$50M | Multi-team ownership; SOC2/ISO compliance pressure; cross-team coordination; the secret-custody matrix and drift guards become non-negotiable. |
| **T5 — Platform** | 500K+ | $50M+ | Multi-product, multi-provider, multi-region, multi-tax-jurisdiction. The full pattern library applies; verification-first is daily; auditor evidence packs are quarterly. |

---

## Complexity overlay (secondary axis)

Add +1 tier of complexity (not customer count, but depth needed) for each:

- Dual-provider (Stripe + PayPal) — most projects
- Team / org plans (B80) → +1
- Multi-currency / international presentment → +1
- Annual / sales-assisted contracts → +1
- Trials (free, card-up-front, no-card) → +1
- Discounts / coupons / promo codes / negotiated deals → +1
- Multi-product (separate billing per product) → +1
- Marketplace / Stripe Connect (per-seller payouts) → +1
- Stripe Tax / merchant-of-record platform (Paddle, Lemon Squeezy mid-stack) → +1
- Crypto / on-chain billing → +1
- Usage-based billing (metered) → +1
- Region-specific compliance (PSD2/SCA in EU, India RBI, China etc.) → +1
- Multi-language Customer Portal / dunning emails → +1
- Reseller / partner / affiliate billing → +1

A "T2 SaaS with dual-provider + team plans + trials" effectively gets T3 depth for those bundles, while staying T2 on reporting (no need for Monte Carlo runway projection until ARR justifies it).

**Don't blindly escalate.** Escalate only the relevant bundles; stay at base tier for the rest.

---

## Scope decision artifact

Every run starts by writing `.billing_workspace/phase0_scope_decision.md`.

```markdown
# Billing Scope Decision

Mode: <audit-only | audit-and-fix | harden-incident | add-feature | greenfield | migration | compliance-pass>
Base tier: <T1-T5>
Complexity overlays: <list>
Provider scope: <stripe-only | paypal-only | both>
Risk appetite: <production-paying-customers | pre-launch-pilot | internal-tool>

## Required bundles
- B00 ...

## Conditional bundles included
- B80 Teams — activated because <team/org plans requested>

## Conditional bundles skipped
- B115 Marketplace — n/a because no connected accounts, payouts, or sellers

## Not doing in this run
- Generic CI redesign
- General NTM setup
- Pricing-page marketing copy
```

The artifact is a guardrail, not paperwork. If the run expands later, update this file with the trigger. If a bundle is dormant, mark it `n/a`; do not silently delete the bundle from consideration.

---

## Conditional bundle activation criteria

Core bundles B00, B10, B20, B30, B40, B50, B60, B70, B90, B100, and B110 are tiered by the matrix below. Extended bundles stay dormant unless one of their triggers is present.

| Bundle | Activate when | Keep dormant when |
|--------|---------------|-------------------|
| B25 Customer support | support tickets, payment-contact workflows, refund/dispute triage, or T2+ paying customers | pre-launch with no support workflow |
| B35 Provider catalog audit | live Stripe/PayPal Dashboard state can drift, event coverage must be verified, or T3+ | greenfield without provider accounts yet |
| B45 Admin operations | admin/operator billing actions exist or are requested | no admin billing surface |
| B55 Observability/defense-in-depth | production webhooks, alerts, CSP, chargebacks, nested side effects, or T3+ | local-only prototype |
| B65 Test data/fixtures | real-DB/provider sandbox tests need deterministic users, clocks, or adversarial cases | no tests being added in this run |
| B75 Tax/accounting | tax, settlement ledger, GL, deferred revenue, multi-currency fees, refunds/disputes reporting | simple domestic subscription cache |
| B80 Teams | org/team seats, shared entitlement, team checkout, pause/resume, individual-to-team upgrade | individual subscriptions only |
| B85 Usage-based billing | metered, tiered, usage credits, hybrid plans, overage limits | flat recurring subscriptions |
| B95 Internationalization | multi-currency, regional payment methods, PSD2/SCA, per-region tax/presentment | one currency, one market |
| B105 Performance/scale | slow billing reads, webhook throughput, N+1 risk, large tables, T3+ volume | small dataset and no perf symptom |
| B115 Marketplace/Connect | connected accounts, sellers, payouts, fee splits, platform disputes | platform sells only its own subscription |
| B120 Compliance evidence | SOC2/ISO/security questionnaire, audit window, customer security review | no compliance audience in this run |
| B125 Dispute defense | chargebacks, disputes, friendly-fraud patterns, evidence automation | no disputes and no support/dispute ask |
| B130 Migration cutover | provider migration, dual-run, rollback drill, old-provider mapping | no provider replacement/addition |
| B135 Webhook forensics | incident reconstruction, event timeline, replay, smoking-gun query | no incident or historical forensic ask |
| B140 Incident response | active/recent production billing incident, containment, kill switches, postmortem | routine feature or greenfield run |
| B145 Extended failure catalog | onboarding, audit taxonomy, broad incident triage, recurring unknowns | narrow implementation with known failure class |

Use this table as an inclusion gate. When in doubt, include the smallest artifact that answers the billing question and record the uncertainty in `phase0_scope_decision.md`.

---

## Tier 1 — Pre-launch (greenfield)

**Profile.** Founder + 0–2 engineers. No paying customers yet. Stripe / PayPal accounts may not even exist.

**Mode default.** `greenfield`. Walk the step-ordered build in `references/patterns/110-OPERATIONS.md § Battle-tested-checklist`.

**Bundles required:** B00, B10, B20, B30, B40, B50, B60, B90 (minimal — just `webhook-reconciliation` + `webhook-staleness`). B70 dunning at minimum (D0 + D21). B100 minimum (canonical MRR; no health/forecasting yet). B110 minimum (one runbook per cron).

**Skip at this tier:** B80 unless team-plan launches from the start. Full B100 (health scoring, Monte Carlo). B110 compliance evidence pack.

**Polish Bar focus:** every Polish Bar dimension green BEFORE the first paying customer. The first paying customer is when the rules go from theoretical to load-bearing.

**Scope shape:** all 12 build steps in dependency order; AI-agent runs collapse the wall-clock dramatically vs. solo human implementation.

---

## Tier 2 — Early-stage (1–500 customers, <$100K ARR)

**Profile.** Real customers, real money, but small enough that the founder still reads every Stripe email. First incident is imminent (or just happened).

**Mode default.** `audit-and-fix` if billing already exists; `harden-incident` if you just had one.

**Bundles required:** All of T1 plus full B70 (dunning ladder + SCA + card-expiry) and B90 (full reliability machinery: orphan-cancel, integrity-audit, provider-reconciliation).

**Polish Bar focus:** add Dimensions 6 (200-on-error), 7 (synchronous refund invalidation), 8 (analytics exclusions), 10 (cron defenses) — all become customer-visible if missing.

**Verification cadence:** quarterly full audit; spot-check after every billing-touching merge.

**Typical scope:** 5–15 Phase 4 tasks; 1–2 weeks of work.

---

## Tier 3 — Growth (500–10K customers, $100K–$5M ARR)

**Profile.** Multi-engineer team. Monthly incidents (some customer-visible, most caught by alarms). Pressure to add features (teams, annual plans, trials) starts here. First "we should consider SOC2" conversation happens.

**Mode default.** Mix of `audit-and-fix` (quarterly) + `add-feature` (per release).

**Bundles required:** All of T2 plus full B100 (health scoring, behavioral forecasting, Monte Carlo), full B110 (every runbook, secret-custody matrix, drift-guards in CI), B80 if teams added.

**Polish Bar focus:** Dimensions 9 (provenance), 11 (secret custody), 14 (priority queue), 15 (bidirectional coverage). The "operational hygiene" dimensions — they don't break the system but they make incidents recoverable.

**Verification cadence:** monthly + after every Stripe/PayPal Dashboard change.

**Typical scope:** continuous — never a "done" state, always one or two open Phase 4 tasks.

---

## Tier 4 — Scale (10K–500K customers, $5M–$50M ARR)

**Profile.** Dedicated billing team or platform team. SOC2 / ISO compliance is required (not optional). Auditor visits quarterly. Multi-product or multi-region complications likely.

**Mode default.** `compliance-pass` annually; `audit-and-fix` quarterly; `add-feature` per release; `migration` when expanding to a new provider/region.

**Bundles required:** ALL bundles. Plus extended bundles:
- B35 — Provider catalog audit (continuous)
- B55 — Observability and defense-in-depth (CSP, Prometheus alerts, chargeback abuse process, nested side-effect idempotency)
- B120 — Compliance evidence pack
- B140 — Incident response framework

**Polish Bar focus:** every dimension green; drift-guards in CI for every invariant; multi-model triangulation in Phase 7; verification-first protocol mandatory.

**Verification cadence:** weekly partial audit; full audit at quarter end + before SOC2 audit window.

---

## Tier 5 — Platform (500K+ customers, $50M+ ARR)

**Profile.** Multi-product platform. Internal billing service consumed by other product teams. May be a merchant-of-record for sub-merchants (Stripe Connect). Multi-region multi-tax-jurisdiction. The billing system IS the product, in the sense that any incident is a CEO-visible event.

**Mode default.** Continuous everything. Mode is irrelevant; the team operates the full pipeline as a service.

**Bundles required:** ALL bundles, all extended bundles, plus product-specific extensions (marketplace splits, sub-merchant onboarding, per-region tax engines, etc.).

**Polish Bar focus:** every dimension verified continuously by drift-guards in CI; Phase 7 fresh-eyes runs nightly; provider catalog audit is hourly (cron) with auto-alert on drift.

**Special considerations:**
- Multi-team coordination via Agent Mail + beads is non-optional.
- Triangulation is daily (Claude + Codex + Gemini on every PR touching billing).
- Customer-impact thresholds for incidents are PR-board-level (a $10K refund is "small"; the bar for a Sev1 is much higher than at T3).
- Provider relationship management (Stripe Account Manager, PayPal Account Manager) is a real responsibility.

---

## Routing the user

```
1. Confirm customer count + ARR + complexity overlay.
2. Compute base tier from the matrix above.
3. Adjust only the relevant bundles for applicable complexity overlays (+1 depth per applicable item, capped at T5).
4. Pick mode default for that tier.
5. Apply the conditional bundle activation table.
6. Write `phase0_scope_decision.md` with required, included, skipped, and not-doing lists.
7. Show the user the recommended bundle list + skip list + verification cadence.
8. Let the user override (often "we're T2 but we want T4 reporting because investor pressure").
```

---

## Common confusions

- **"We're T1 because we just launched."** Check ARR. If you have any paying customers, you're T2. The first paying customer changes the rules.
- **"We're T5 because we're publicly traded."** Public + paying customers ≠ scale. A 5K-customer public company is still T3. Use the customer count.
- **"We don't need T4 reliability; we'll add it later."** The reliability machinery (B90) is what catches your first 100 incidents before customers see them. Adding it after the first 100 incidents means you've already paid the customer-trust cost.
- **"We need T5 from the start because we're going to be huge."** No. Greenfield projects that try to build T5 systems before they have T5 problems ship slowly and rarely end up with the right architecture for actual T5 load. Stick to the tier you actually are; refactor up the tiers as you grow.

---

## Tier-to-mode quick reference

| Tier | Default modes | Typical Phase-loop coverage |
|------|---------------|------------------------------|
| T1 | greenfield | All 10 phases through the step-ordered build |
| T2 | audit-and-fix; harden-incident on demand | All 10 phases |
| T3 | audit-and-fix quarterly; add-feature per release | All 10 phases per audit; scoped per feature |
| T4 | compliance-pass annually; audit-and-fix quarterly; migration when expanding | All 10 + 9.5 cutover for migrations |
| T5 | continuous (mode is implicit) | Full pipeline as a service |
