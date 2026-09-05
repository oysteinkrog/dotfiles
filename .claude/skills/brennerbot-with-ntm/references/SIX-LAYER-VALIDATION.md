# SIX-LAYER-VALIDATION.md — Layered Validation Regime

<!-- TOC: Why six layers | Layer 1 invariants | Layer 2 convergence | Layer 3 marching-order | Layer 4 rotation | Layer 5 cross-session | Layer 6 external | Run order | Pre-Phase-8 mandatory check -->

Mirrors documentation-website's TESTING-DOCS.md six-layer regime. Each layer catches different classes of methodology failure. Together they form a defense-in-depth against silent corruption.

For T4+ sessions, all six layers are mandatory before Phase 8 freeze. For T3, layers 1-5 are mandatory; layer 6 (external) optional.

---

## Why six layers

A single validation pass can miss things. The Brenner method's defense-in-depth (per Opus distillation Part III "House of Cards") rests on independent constraints. We adopt the same: each layer checks something the others can't easily check.

```
Layer 1 (bead invariants)  ← scripts/audit-bead-invariants.sh
Layer 2 (convergence)      ← scripts/convergence-check.sh
Layer 3 (marching-order)   ← session-logs/dispatch-*.log review
Layer 4 (rotation rules)   ← scripts/check-rotation-rules.sh
Layer 5 (cross-session)    ← references/CROSS-SESSION-DRIFT-CATALOG.md
Layer 6 (external review)  ← human reviewer; T4+ only
```

A session that passes all six is methodologically sound. One that fails any is provisional pending fix.

---

## Layer 1 — Bead invariants

**What it catches:** structural violations (missing falsifier, missing refuted_by, scale_physics without calculation, etc.)

**Tool:** `scripts/audit-bead-invariants.sh --all`

**Frequency:** every Phase 4 round, every Phase 7 trio-round, mandatory before Phase 8 freeze.

**Exit criterion:** zero violations (or explicitly documented exceptions).

**Catch rate:** mechanical violations only. Doesn't catch semantic errors (e.g., a falsifier that's technically present but unfalsifiable in practice — that's Layer 4 territory via the falsifier-grader subagent).

---

## Layer 2 — Convergence

**What it catches:** premature exit (Phase 4 exits before kill_rate ≥ add_rate; Phase 7 exits with high audit findings open).

**Tool:** `scripts/convergence-check.sh --phase=<N>`

**Frequency:** end of each Phase 4 round, Phase 6 meta-synthesis pass, Phase 7 trio-round.

**Exit criterion:** convergence formula satisfied for the phase.

**Catch rate:** exit-gate violations. Doesn't catch "we converged but on the wrong answer" — that's Layer 3 + 6 territory.

---

## Layer 3 — Marching-order discipline

**What it catches:** ad-hoc dispatches that bypass calibrated templates; un-tracked operator decisions; freelance coordination breaking the methodology.

**Tool:** review `session-logs/dispatch-*.log` + `phase0_scope_decision.md` updates.

**Frequency:** at every phase exit; comprehensively at Phase 10.

**Exit criterion:**
- Every dispatch traces to a `MO-*.md` template (no free-write)
- Every roster change is recorded
- Every `phase_<N>_complete.flag` matches actual artifact state

**Catch rate:** discipline violations — operator drifting toward expedience. The Phase 10 drift auditor focuses heavily here.

**Manual check:**
```bash
# Count dispatches without a recognized MO template:
grep -r 'MO:' session-logs/dispatch-*.log | grep -vE 'MO-[a-z0-9-]+(\.md)?$' | wc -l
```

---

## Layer 4 — Rotation rules

**What it catches:** Adjudicator-twice-in-a-row, Adjudicator-as-champion, dominant-family bias, productive-ignorance pane corruption.

**Tool:** `scripts/check-rotation-rules.sh`

**Frequency:** at Phase 5 exit, at Phase 7 audit, mandatory before Phase 8 freeze.

**Exit criterion:** zero rotation-rule violations.

**Catch rate:** structural fairness violations. Falsifier-quality (semantic) is Layer 4-extension via `subagents/falsifier-grader.md`.

---

## Layer 5 — Cross-session learning

**What it catches:** persistent regressions (same drift verdict across many sessions), calibration drift (high-confidence Hs failing in subsequent sessions), methodology stagnation.

**Tool:** `references/CROSS-SESSION-DRIFT-CATALOG.md` + `references/OPERATOR-CALIBRATION-LOG.md` (per CROSS-SESSION-LEARNING.md), `scripts/drift-trend.sh`.

**Frequency:** at Phase 10 of every session; quarterly trend review.

**Exit criterion:** if persistent regressions surface, lessons must be committed to the skill repo (per CROSS-SESSION-LEARNING.md "Lesson commitment protocol").

**Catch rate:** systemic methodology issues that single-session validation misses. The operator catches their own blind spots.

**Indicators:**
- Same operator skipped at Phase 7 for ≥3 consecutive sessions → strengthen Phase 7 audit checklist
- Adjudicator family-bias detected in ≥2 sessions → roster-rebalance default
- Convergence-language false positives common → tighten convergence-check.sh thresholds

---

## Layer 6 — External review

**What it catches:** blind spots invisible from inside the methodology; expert critique of the artifact's substance.

**Tool:** human reviewer external to the session.

**Frequency:** T4+ sessions; T5 mandatory; T1-T3 optional.

**Exit criterion:** reviewer signs off on the HANDBACK / DECISION-MEMO / DRIFT-CHECK before user acts.

**Catch rate:** Things the operator + skill couldn't detect. The most expensive validation but the most thorough.

**Reviewer pool:**
- Subject-matter expert (domain content)
- Methodology expert (Brenner-method rigor)
- Skeptic / adversary (would attack the conclusion)

For T5, ≥2 independent reviewers.

---

## Run order

Layers can run in parallel (1, 2, 4) but should be re-checked after each phase exit:

```
After Phase 3 → Layer 1, Layer 2 (Phase 3 invariants), Layer 4 (rotation pre-debate)
After Phase 4 round → Layer 1, Layer 2 (kill_rate), Layer 4 (Phase 4 rotation)
After Phase 5 → Layer 1, Layer 4 (Adjudicator), Layer 3 (debate dispatch logs)
After Phase 6 → Layer 1, Layer 2 (meta-synth), Layer 4 (meta family)
After Phase 7 → Layer 1, Layer 2 (audit clean), Layer 3 (audit dispatch logs), Layer 4
Pre Phase 8  → Layer 1, 2, 3, 4, 5 ALL must pass
Pre Phase 9  → Layers 1-5 verified
Phase 10    → Layer 5 update; Layer 6 (T4+) handoff
```

---

## Pre-Phase-8 mandatory check

The Layer 1-5 sweep is the gate to Phase 8 freeze. All must pass; otherwise Phase 8 cannot start. Run via `scripts/check-six-layer-validation.sh`:

```bash
./scripts/check-six-layer-validation.sh --workspace=<WORKSPACE>
```

Output:

```
Layer 1 (bead invariants): PASS / FAIL — N violations
Layer 2 (convergence):     PASS / FAIL
Layer 3 (marching-order):  PASS / FAIL — N free-writes detected
Layer 4 (rotation rules):  PASS / FAIL — N violations
Layer 5 (cross-session):   PASS / WARN — N persistent regressions
Layer 6 (external review): N/A (T1-T3) | PENDING (T4+) | PASS / FAIL
Verdict: READY FOR PHASE 8 / BLOCKED
```

---

## Per-tier strictness

| Tier | Layer 1 | Layer 2 | Layer 3 | Layer 4 | Layer 5 | Layer 6 |
|------|---------|---------|---------|---------|---------|---------|
| T1 | mandatory | recommended | optional | optional | skip | skip |
| T2 | mandatory | mandatory | mandatory | recommended | recommended | skip |
| T3 | mandatory | mandatory | mandatory | mandatory | mandatory | optional |
| T4 | mandatory | mandatory | mandatory | mandatory | mandatory | mandatory |
| T5 | mandatory | mandatory | mandatory | mandatory | mandatory | mandatory + ≥2 reviewers |

---

## Layer-specific failure recovery

### Layer 1 fails

Bead invariants violated. Don't proceed. Fix the violations (typically: missing falsifier, missing refuted_by). Re-run.

### Layer 2 fails

Convergence not reached. Either run another round (Phase 4/6/7) OR escalate to operator (hard-cap reached). See WALL-TIME-BUDGET.md "Hard breach" protocol.

### Layer 3 fails

Free-write dispatches detected. Per Phase 10 drift, document in DRIFT-CHECK.md and consider the session methodologically degraded. May require re-running the affected phase with proper template-based dispatches.

### Layer 4 fails

Rotation rule violation (e.g., F-501 adjudicator-bias, F-502 family-bias). Run `MO-roster-rebalance.md`. May require re-adjudicating affected debates with proper rotation.

### Layer 5 fails

Persistent regression detected (e.g., same drift verdict 3x in a row). Update references/ per CROSS-SESSION-LEARNING.md lesson protocol. Doesn't block current session but should block the NEXT session's start until lessons are applied.

### Layer 6 fails

External reviewer rejects. Address the reviewer's specific findings before acting on the recommendation. May require Phase 4-7 reopen.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Run only Layer 1; skip the rest | Misses semantic + procedural violations |
| Run all layers but treat each as independent gate (any fail = abort) | Pragmatic recovery is sometimes appropriate; document the override |
| Skip Layer 5 because "it's just record-keeping" | Layer 5 is how the methodology evolves; skipping caps quality |
| Skip Layer 6 for T4+ to save time | The external review is the most thorough; T4+ skipping it is methodologically reckless |
| Re-run Layer 1 after every bead update | Burns time; run at phase exits |
| Trust Layer 6 reviewer without giving them the methodology context | Reviewer doesn't know what to look for; brief them per HANDOFF rubric |

---

## Operator self-discipline

The six layers exist because operators sometimes drift. Pre-launch the layers as a checklist; treat as non-optional for T3+. The tradeoff between methodology rigor and wall-time is real, but at T3+ the rigor compounds.
