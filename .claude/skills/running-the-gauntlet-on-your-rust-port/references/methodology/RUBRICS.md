# Scoring Rubrics

Every Phase-12 candidate (remediation) is scored on one of these rubrics depending on its pillar. Same shape — six fixed dimensions — so the runner-up table is comparable across pillars.

## Universal rubric (all pillars)

Score each dimension 1-5; sum gives the candidate's score. ≥20 (out of 30) is the minimum acceptance bar.

| Dimension | 1 | 3 | 5 |
|---|---|---|---|
| **Correctness margin** | reduces correctness; some oracle tests would fail | preserves correctness; oracle pass-rate unchanged | strictly improves; new oracle tests now pass |
| **Performance delta** | regresses (≤5% within noise) | neutral within `cv_pct` band | net positive, attributable to a frame ≥0.1% MT8 self-time |
| **Diff blast radius** | touches >2k lines across >5 crates | touches 500-2k lines across 2-5 crates | touches <500 lines, 1 crate, with clear seam |
| **Reviewability** | reviewer needs >2h | reviewer needs 30m-2h | reviewer needs <30m; obvious from the diff |
| **Maintainability** | adds tech debt (TODOs / shims / "FIXME later") | neutral | reduces tech debt (removes a workaround / consolidates) |
| **Parity preservation** | changes behavior (would break oracle) | preserves behavior; bench-level identical | preserves behavior + adds a regression test that pins the preservation |

Cross-link: [`methodology/OPERATORS.md § ⊕ ISOMORPHIC-REWRITE`](OPERATORS.md).

## Perf-pillar additional gate

In addition to the universal rubric, perf candidates must pass:

**Impact × Confidence / Effort ≥ 2.0**

Per `/extreme-software-optimization` skill. Where:
- **Impact** = expected speedup × workload weight in the primary-score (5 = >50% improvement on a high-weight workload; 1 = <5% on a low-weight workload).
- **Confidence** = profile-attribution strength (5 = top-1 frame at >1% self-time with reproduce-rate >95%; 1 = "probably faster" with no profile).
- **Effort** = engineer-hours to implement + review + ship (1 = <1h; 5 = >40h).

Plus the **profile-first contract** (no candidate without an EV-scored card + one-lever scope + proof pack). See [`pattern:150-PROFILE-FIRST-CARD`](../patterns/150-PROFILE-FIRST-CARD.md).

## Conformance-pillar additional gate

**Conformal lower-bound monotonicity**: the proposed fix must raise the lower bound on the parity score **without lowering any per-category bound**. If a fix raises overall but lowers category-X, it's a Phase-12 reject (or requires a structured dated waiver per `subagents/waiver-author.md`).

Cross-link: [`methodology/CONFORMAL-RATCHET.md`](CONFORMAL-RATCHET.md).

## Surface-pillar additional gate

**`partial → full` requirement**: surface candidates must convert at least one FeatureUniverse entry from `Partial` to `Passing` **without regressing others**. Adding new features (going from `Missing` to `Partial`) is fine but must come with a coverage-debt accounting.

Cross-link: [`pattern:105-FEATURE-UNIVERSE`](../patterns/105-FEATURE-UNIVERSE.md).

## Worked example — perf candidate scoring

Candidate: `try_execute_hot_opcode IsNull promotion` (FrankenSQLite session 2026-04-23).

| Dimension | Score | Reasoning |
|---|---|---|
| Correctness margin | 5 | strictly preserves; new prop test added |
| Performance delta | 5 | +27.5% on IsNull-heavy WHERE workloads, MT8 self-time 1.2% closed |
| Diff blast radius | 5 | 12 lines, 1 file (`crates/fsqlite-vdbe/src/engine.rs`) |
| Reviewability | 5 | trivial — just adds an arm to `try_execute_hot_opcode` |
| Maintainability | 4 | adds one branch; minor coupling growth |
| Parity preservation | 5 | regression test `bd-XXX_isnull_promotion.rs` added |
| **Universal sum** | **29/30** | **above 20 bar** |
| Impact × Conf / Effort | 5 × 5 / 1 = 25 | **above 2.0 perf gate** |

**Verdict: APPLY.**

Runner-ups (recorded in `<workspace>/phase12_remediation_isnull_promotion.md § Runners-up`):
- Devirtualize IsNull at the trait-object level: rejected (4 universal, blast radius 3, would require refactoring TransactionKind dispatch — Effort 5 → EV = 5×3/5 = 3).
- Inline IsNull constant-fold at parse time: rejected (universal 5/30 missing parity-preservation evidence — no regression test possible at parse layer).

## Worked example — conformance candidate scoring

Candidate: `add Predicate metamorphic transform for IN-with-NULL-list rewrite`.

| Dimension | Score | Reasoning |
|---|---|---|
| Correctness margin | 5 | adds new oracle coverage; finds 2 prior-unseen divergences |
| Performance delta | 3 | neutral — corpus expansion, no perf impact |
| Diff blast radius | 4 | 80 lines, 1 file (metamorphic.rs); + per-class entries |
| Reviewability | 4 | adds a new TransformFamily entry; straightforward |
| Maintainability | 5 | follows the established 4-family pattern |
| Parity preservation | 5 | bumps conformal lower bound by +0.003 |
| **Universal sum** | **26/30** | **above 20** |
| Conformal monotonicity | ✓ | lower bound up; no per-category bound down |

**Verdict: APPLY.**

## Worked example — surface candidate scoring

Candidate: `promote PRAGMA introspection F-SQL-095 from Partial to Passing by implementing pragma_list pragma_table_info ...`.

| Dimension | Score | Reasoning |
|---|---|---|
| Correctness margin | 5 | strictly improves; new oracle coverage for 14 PRAGMAs |
| Performance delta | 3 | neutral — PRAGMA paths are cold |
| Diff blast radius | 3 | ~600 lines across 3 files (parser + dispatch + tests) |
| Reviewability | 3 | needs reviewer familiar with PRAGMA dispatch table |
| Maintainability | 4 | follows established dispatch pattern |
| Parity preservation | 5 | adds 14 new oracle tests |
| **Universal sum** | **23/30** | **above 20** |
| `partial → full` | ✓ | F-SQL-095 PRAGMA-introspection family lifts from Partial to Passing |

**Verdict: APPLY.**

---

Adding a new dimension to the universal rubric requires consensus across cc_1/cc_2/cc_3 lanes and a corresponding update to `[methodology/POLISH-BAR.md]` (if the rubric becomes a gate, not just a score).
