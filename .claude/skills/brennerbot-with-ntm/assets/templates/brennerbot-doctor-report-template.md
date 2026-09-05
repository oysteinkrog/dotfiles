# Brennerbot Doctor Report

**Workspace:** <PATH>
**Session ID:** <RS-...>
**Date:** <ISO>
**Verdict:** 🟢 GREEN | 🟡 YELLOW | 🔴 RED
**Inspector:** scripts/brennerbot-doctor.sh | manual | operator-buddy subagent

---

## Summary

(2-3 sentences: overall workspace health, the worst pillar, and whether the workspace is safe to continue.)

---

## Per-pillar verdicts

| Pillar | Verdict | Worst check | Recovery priority |
|--------|---------|-------------|-------------------|
| 1. Structural | <emoji> <verdict> | <specific> | <high/med/low> |
| 2. Methodology | <emoji> <verdict> | <specific> | <high/med/low> |
| 3. Bead invariants | <emoji> <verdict> | <specific> | <high/med/low> |
| 4. Convergence | <emoji> <verdict> | <specific> | <high/med/low> |
| 5. Triangulation | <emoji> <verdict> | <specific> | <high/med/low> |
| 6. Cross-session | <emoji> <verdict> | <specific> | <high/med/low> |
| 7. Deliverability | <emoji> <verdict> | <specific> | <high/med/low> |

---

## Pillar 1 — Structural

(Per BRENNERBOT-DOCTOR-RUBRIC.md Pillar 1 checks.)

| Check | Result |
|-------|--------|
| `phase0_scope_decision.md` exists | <yes/no/empty> |
| Workspace is a git repo | <yes/no> |
| Phase flags sequential | <yes/no/gaps> |
| 6 required directories present | <count>/6 |
| `intake/question_of_record.md` with non-empty Falsifier | <yes/no/thin> |
| `RESUME.md` exists if Phase 8 done | <n/a or yes/no> |

**Verdict:** 🟢 / 🟡 / 🔴

**Issues found:**

- ...

**Recommended fixes:**

- ...

---

## Pillar 2 — Methodology

(Per BRENNERBOT-DOCTOR-RUBRIC.md Pillar 2 checks.)

| Check | Result |
|-------|--------|
| Phase 1 third-alternative present | <yes/no/n/a> |
| Phase 4 falsifier-firing per H per round | <full/partial/none> |
| Phase 5 cross-family champions | <%> |
| Phase 6 disagreement_register entries | <count> (need ≥3) |
| Phase 7 audit cross-family | <yes/no/n/a> |
| Phase 10 lessons committed | <count> |

**Verdict:** 🟢 / 🟡 / 🔴

**F-### codes triggered:** <list>

**Issues found:**

- ...

**Recommended fixes:**

- ...

---

## Pillar 3 — Bead invariants

(Per `scripts/audit-bead-invariants.sh --all`.)

| Check | Result |
|-------|--------|
| Every H has non-empty falsifier | <%> |
| Every refuted H has refuted_by | <%> |
| Every EV has verbatim quote with §-anchor | <%> |
| Every EV has W axes | <%> |
| Every audit-finding has severity tag | <%> |
| Every scale_physics assumption has calculation | <count> |
| Orphan beads | <count> |

**Verdict:** 🟢 / 🟡 / 🔴

**Specific violations:**

- <bead-id>: <which invariant violated>

**Recommended fixes:**

- <update X by ...>

---

## Pillar 4 — Convergence

(Per `scripts/convergence-check.sh`.)

| Phase | kill_rate | add_rate | Verdict |
|-------|-----------|----------|---------|
| 4 | <N> | <M> | <converged/not-converged> |
| 6 | n/a | <count of D entries> | <converged/not-converged> |
| 7 | <trio-rounds clean> | <findings count> | <converged/not-converged> |

**Whole-session convergence:** 🟢 / 🟡 / 🔴

---

## Pillar 5 — Triangulation

(Per `scripts/triangulation-coverage.sh`.)

| Check | Result |
|-------|--------|
| Distinct families in roster | <N> |
| Per-H investigation has ≥2 distinct families | <%> |
| Per-family distillations exist | <list> |
| Disagreement register cross-family | <count of pairs> |
| Audit panes ≠ synthesizer family | <yes/no> |

**Verdict:** 🟢 / 🟡 / 🔴

**Triangulation degradation:** <none / partial / collapsed>

---

## Pillar 6 — Cross-session

| Check | Result |
|-------|--------|
| Prior sessions on related topic identified | <yes/no/skipped> |
| Reconciliation (per RECONCILIATION-OF-PRIOR-SESSIONS.md) done | <yes/no/n/a> |
| Phase 10 drift-check verdict | <convergent/recoverable/regression/missing> |
| Lessons committed to references/ | <count> |

**Verdict:** 🟢 / 🟡 / 🔴

---

## Pillar 7 — Deliverability

| Check | Result |
|-------|--------|
| HANDBACK.md exists ≤80 lines | <yes/no/over> |
| HANDBACK has verdict on line 1-3 | <yes/no> |
| HANDBACK has cited evidence with W ≥ 0.7 | <count> |
| Open threads have next-action tags | <%> |
| Archetype-specific deliverable exists | <list> |
| RESUME.md hash-verifies | <yes/no/n/a> |

**Verdict:** 🟢 / 🟡 / 🔴

---

## Recovery sequencing

Per BRENNERBOT-DOCTOR-RUBRIC.md, recover pillars in this order:

1. **Pillar 1 (Structural)** — without structure, nothing else makes sense
2. **Pillar 3 (Bead invariants)** — corrupt beads downstream
3. **Pillar 5 (Triangulation)** — single-family blind spots
4. **Pillar 2 (Methodology)** — discipline drift
5. **Pillar 4 (Convergence)** — phase exits
6. **Pillar 6 (Cross-session)** — methodology evolution
7. **Pillar 7 (Deliverability)** — output polish

For this workspace, the recovery sequence is:

1. <specific>
2. <specific>
3. <specific>

Estimated effort: <hours>.
Estimated outcome if applied: 🟢 / 🟡.

---

## Resume guidance

(If verdict is 🟡 or recoverable 🔴.)

**Recommended re-entry phase:** <phase>
**Recommended initial dispatch:** <MO file>
**Compose with:** <skills>

(If verdict is hard 🔴.)

**Recommendation:** Do NOT continue this workspace. Options:
- Fresh-restart with corpus reuse (preserve `corpus/ingested/`)
- Hand off to a more experienced operator with this report
- Document and abandon (per AGENTS.md no-deletion: archive, don't delete)

---

## Cross-references

- [BRENNERBOT-DOCTOR-RUBRIC.md](../../references/BRENNERBOT-DOCTOR-RUBRIC.md) — the rubric this report instantiates
- [SIX-LAYER-VALIDATION.md](../../references/SIX-LAYER-VALIDATION.md) — pre-Phase-8 layer-1-5 sweep (overlaps with Pillars 1-5)
- [FAILURE-TABLE.md](../../references/FAILURE-TABLE.md) — F-### codes
- [STRESS-TEST-SCENARIOS.md](../../references/STRESS-TEST-SCENARIOS.md) — recovery scenarios
- [scripts/brennerbot-doctor.sh](../../scripts/brennerbot-doctor.sh) — automated rubric pass
- [/world-class-doctor-mode-for-cli-tools](/) — diagnostic tooling pattern source

---

## Sign-off

- [ ] Doctor pass run
- [ ] Operator reviewed report
- [ ] Recovery applied (or explicit "do not recover; abandon")
- [ ] Re-pass after recovery (if recovery applied)
