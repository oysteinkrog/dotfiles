# Case Studies — Right-Sizing Examples

> **For scope calibration.** Use this file to decide how much of the billing skill to load. These examples are intentionally compact; the detailed execution rules live in `PHASES.md`, `OPERATING-MODES.md`, and the pattern bundles.

These are synthesized from the patterns and failure modes the skill anticipates. They are not instructions to run every phase for every project.

---

## Quick Tier Scoping Examples

Quick scoping examples — what running this skill looks like at each tier. Use to right-size effort BEFORE Phase 0.

---

## T1 — Greenfield, 0 customers

- **Mode**: `greenfield`.
- **Bundles required**: B00, B10, B20, B30, B40, B50, B60, B70 (D0+D21 only), B90 (minimal: webhook-reconciliation + webhook-staleness), B100 (canonical MRR only), B110 (one runbook per cron).
- **Bundles to skip until later**: B25, B45, B65 advanced, B75, B80, B85, B95, B105, B115, B120, B125, B135, B140, B145.
- **Order**: walk the step-ordered checklist in `references/patterns/110-OPERATIONS.md § Battle-tested-checklist`.
- **Effort**: 12 ordered build steps; AI-agent runs collapse the wall-clock dramatically vs. solo human implementation.
- **Phase 7 fresh-eyes**: ≥2 rounds clean (mandatory; new code is most bug-prone).

## T2 — Early-stage, 1-500 customers, <$100K ARR

- **Mode**: `audit-and-fix` if billing exists; `harden-incident` if you just had one.
- **Bundles required**: T1 list + full B70 (dunning) + full B90 (orphan-cancel, integrity audit, provider-reconciliation) + B25 (support integration) + B125 (basic dispute handling).
- **Bundles to skip until later**: B75, B80, B85, B95, B105, B115, B120, B135, B140, B145.
- **Effort**: ~1-2 weeks per audit pass.

## T3 — Growth, 500-10K customers, $100K-$5M ARR

- **Mode**: `audit-and-fix` quarterly + `add-feature` per release.
- **Bundles required**: All T2 + full B100 (health, forecasting, runway) + full B110 + B45 (admin UI) + B65 (test fixtures) + B135 (forensics) + B140 (incident response patterns).
- **Add when applicable**: B80 (teams), B105 (perf as scale demands).
- **Effort**: ongoing; never "done."

## T4 — Scale, 10K-500K customers, $5M-$50M ARR

- **Mode**: `compliance-pass` annually + `audit-and-fix` quarterly + `migration` when expanding.
- **Bundles required**: ALL bundles (B00-B145).
- **Effort**: dedicated billing-team; continuous.

## T5 — Platform, 500K+ customers, $50M+ ARR

- **Mode**: continuous.
- **Bundles required**: ALL + product-specific extensions (your own catalog of failure classes added to B145).
- **Effort**: full-time billing platform team.

---

## Common scoping mistakes

- **T1 trying to build T4 features.** Skip B100 health scoring, B85 metered, B115 marketplace until you actually need them. Greenfield projects ship late when over-scoped.
- **T2 skipping B25 / B125.** First chargeback class is when these become customer-trust catastrophes. Add them BEFORE the first incident.
- **T3 skipping B105 (performance) until queries already slow.** Indexes added under incident pressure cause downtime.
- **T4 skipping B120 (compliance evidence) until auditor visits.** Continuous evidence gathering takes months to set up; can't do it in 2 weeks.

---

## Decision flow

```
Customer count + ARR → tier (per SCOPE-TRIAGE.md)
                        ↓
      Existing billing code? → mode (per OPERATING-MODES.md)
                        ↓
                 Required bundles per tier (above)
                        ↓
                Phase 0 → Phase 10 (per PHASES.md)
```

---

## Compact Run Snapshots

Use these as examples of what belongs in `phase0_scope_decision.md`.

### Snapshot A — T2 audit-and-fix after dispute spike

| Field | Decision |
|-------|----------|
| Context | 800 paying customers, Stripe-only, recent dispute spike |
| Mode | `audit-and-fix`, with `harden-incident` lens for disputes |
| Include | B10, B20, B30, B40, B50, B60, B70, B90, B100, B110, B125 |
| Skip | PayPal-specific rows, B80, B85, B95, B115, B120 unless evidence appears |
| Evidence gates | coverage matrix, risk-scored gaps, dispute regression tests, real-DB tests, provider sandbox drill |
| Scope warning | Do not launch a T4 swarm; Pair tier is enough unless the audit finds broad cross-bundle drift |

### Snapshot B — T4 compliance-pass

| Field | Decision |
|-------|----------|
| Context | 80K customers, $30M ARR, multi-currency, SOC2 window |
| Mode | `compliance-pass` |
| Include | all compliance-relevant bundles, especially B35, B55, B75, B95, B110, B120, B125 |
| Skip | new billing features and schema redesign not required for evidence |
| Evidence gates | secret custody, RLS audit, provider catalog proof, drift-guard list, per-control evidence pack |
| Scope warning | File feature bugs for the next `audit-and-fix`; do not destabilize the audit target |

### Snapshot C — T1 greenfield

| Field | Decision |
|-------|----------|
| Context | 0 customers, Stripe-only, first paid launch upcoming |
| Mode | `greenfield` |
| Include | B00, B10, B20, B30, B40, B50, B60, B70 minimal, B90 minimal, B100 canonical MRR, B110 minimal |
| Skip | B25, B45, B75, B80, B85, B95, B105, B115, B120, B125, B135, B140, B145 |
| Evidence gates | step-ordered build, two Phase 7 rounds, real-DB tests, Stripe Test mode lifecycle drill |
| Scope warning | Do not build T4 reporting, marketplace, or compliance evidence before the first customer |

### Snapshot D — T3 add-feature: team plans

| Field | Decision |
|-------|----------|
| Context | 5K customers, individual subscriptions exist, team plans requested |
| Mode | `add-feature` |
| Include | B10, B30, B40, B50, B60, B70, B80, B90, plus B100 only for team MRR projection |
| Skip | unrelated B75/B85/B95/B115/B120 unless the feature explicitly triggers them |
| Evidence gates | scoped archaeology, feature plan, team-hijack tests, pause/resume intent tests, real-DB integration |
| Scope warning | Escalate only touched bundles; do not turn team plans into a full billing audit unless Phase 1 finds broad drift |

---

## Cross-Example Lessons

1. Mode and tier decide the read set. Optional references are dormant until activated.
2. `phase0_scope_decision.md` is the durable guard against accidental expansion.
3. Phase 7 remains mandatory even for narrow work, but its scope follows the touched bundles.
4. CASS mining is most valuable for prior decisions and recurring billing bug classes, not generic session archaeology.
5. Swarm orchestration is a T4+ tool; smaller runs usually move faster with Solo, Pair, or Squad.
