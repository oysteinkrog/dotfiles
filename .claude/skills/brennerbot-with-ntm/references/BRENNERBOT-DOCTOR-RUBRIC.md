# BRENNERBOT-DOCTOR-RUBRIC.md — Diagnosing a Brennerbot Workspace

<!-- TOC: Why a doctor rubric | The 7-pillar health rubric | Pillar 1: structural | Pillar 2: methodology | Pillar 3: bead invariants | Pillar 4: convergence | Pillar 5: triangulation | Pillar 6: cross-session | Pillar 7: deliverability | Severity scoring | Composing the doctor pass | When to declare workspace unhealthy | Recovery sequencing -->

Per `/world-class-doctor-mode-for-cli-tools` patterns. Sometimes you inherit a brennerbot workspace mid-flight (a colleague hands you their work; a session crashed; you're recovering). Before resuming, you need a triage rubric: is this workspace healthy enough to continue, salvageable, or requiring restart?

This file is the rubric. Run via `scripts/brennerbot-doctor.sh` (Tier-6 if added). Read this before manually inspecting a workspace.

---

## Why a doctor rubric

Without one:

- Operators silently inherit broken workspaces and propagate the breakage
- Cross-operator handoffs (per /vibing-with-ntm Phase 7 review-only) lose state
- Resume sessions skip latent issues that bite mid-Phase-4

With one:

- Inherited workspaces get a green/yellow/red verdict in <5 minutes
- Healing recommendations are specific: "fix Pillar 3 first; then re-enter Decision Tree at Phase X"
- Cross-operator handoffs include the doctor report

---

## The 7-pillar health rubric

```
Pillar 1: Structural          Layout, files exist, idempotent re-entry possible
Pillar 2: Methodology         Operator algebra applied; no AP-* anti-patterns
Pillar 3: Bead invariants    Schema-correct beads with mandatory fields
Pillar 4: Convergence         Phase-by-phase exit gates (when applicable)
Pillar 5: Triangulation       Cross-family coverage; not single-family-collapsed
Pillar 6: Cross-session       Reconciliation done; no orphaned drift
Pillar 7: Deliverability      Will produce a useful HANDBACK if continued
```

Each pillar has 3-7 checks. Each check rates green / yellow / red. Pillar verdict = worst check.

Workspace verdict: green if all 7 green; yellow if any yellow; red if any red.

---

## Pillar 1: Structural

| Check | Green | Yellow | Red |
|-------|-------|--------|-----|
| Workspace contains `.brenner_workspace/phase0_scope_decision.md` | exists | exists but truncated | missing |
| Workspace is a git repo | `.git` exists, ≥1 commit | `.git` exists, 0 commits | not a git repo |
| Phase flags (`.brenner_workspace/phase_N_complete.flag`) present in order | sequential 1..N | gaps (e.g., 1, 3, 4) | random / missing |
| `corpus/`, `intake/`, `evidence/`, `distillations/`, `deliverables/`, `session-logs/` directories exist | all 6 | 4-5 of 6 | <4 of 6 |
| `intake/question_of_record.md` exists | yes | exists but Falsifier section empty | missing |
| RESUME.md exists if Phase 8 done | yes | exists but stale hashes | missing despite phase_8_complete.flag |

**Detection script (Tier-6):**

```bash
./scripts/brennerbot-doctor.sh --pillar=1 --workspace=.
```

**Common red causes:** crashed bootstrap; manual workspace creation skipping bootstrap-session.sh; stash that lost the directories.

**Recovery:** if minor (1-2 yellow): operator can rebootstrap with `--idempotent` flag. If red: workspace likely corrupt; recommend fresh-restart with corpus reuse.

---

## Pillar 2: Methodology

| Check | Green | Yellow | Red |
|-------|-------|--------|-----|
| Phase 1 has third-alternative H | ≥1 origin:third_alternative | 0; explicit reason | 0; no reason |
| Phase 4 had ≥1 falsifier-firing attempt per H per round | yes (per audit-bead-invariants) | partial (≤50%) | none |
| Phase 5 cross-family champions | ≥80% of debates | 50-80% | <50% (F-504) |
| Phase 6 disagreement_register has ≥(N choose 2) entries | yes | partial | empty (F-603) |
| Phase 7 audit done by cross-family panes | yes | partial (single family) | not done (F-705) |
| Phase 10 lessons committed to references/ | ≥1 | 0; documented as "no lessons surfaced" | 0; skipped |

**Detection script:**

```bash
./scripts/brennerbot-doctor.sh --pillar=2 --workspace=.
# Internally calls: audit-bead-invariants.sh + check-rotation-rules.sh
```

**Common red causes:** time-pressured operator skipping discipline; ⊙ pane corruption (per S11); same-family roster.

**Recovery:** see specific F-### codes in FAILURE-TABLE.md. Often requires re-running affected phase, which may put session over wall-time budget.

---

## Pillar 3: Bead invariants

Run `audit-bead-invariants.sh --all` for the full check. Failures = red.

Specific invariants:

| Check | Green | Yellow | Red |
|-------|-------|--------|-----|
| Every H has non-empty `falsifier:` field | 100% | <100% | <50% |
| Every refuted H has `refuted_by:` reference | 100% | <100% | <50% |
| Every EV has verbatim quote with §-anchor | 100% | <100% | <50% |
| Every EV has W axes (per EVIDENCE-WEIGHTING-TAXONOMY.md) | 100% | <100%; missing W_composite | <50% |
| Every audit-finding has severity tag | 100% | <100% | <50% |
| Every assumption with type:scale_physics has explicit calculation | 100% | <100% | none |
| No orphan beads (no parent reference where required) | 0 orphans | 1-2 | ≥3 |

**Detection script:**

```bash
./scripts/brennerbot-doctor.sh --pillar=3 --workspace=.
# Internally: audit-bead-invariants.sh --all
```

**Common red causes:** panes filing beads without using MO templates; manual `br create` calls without schema; corrupted bead state per `/fixing-beads-problems`.

**Recovery:** mass-update beads to add missing fields. For severe corruption, escalate to `/fixing-beads-problems`.

---

## Pillar 4: Convergence

| Check | Green | Yellow | Red |
|-------|-------|--------|-----|
| Phase 4 converged (kill_rate ≥ add_rate) | yes, ≥2 rounds | yes, only last round | no, but session "complete" |
| Phase 6 disagreement register stabilized | ≥2 consecutive trivial passes | 1 pass | unclear |
| Phase 7 trio-rounds clean | ≥2 consecutive | 1 | 0 |
| Whole-session convergence (per SKILL.md spec) | ≥2 trio-rounds clean + 0 in_progress beads | partial | session "complete" but in_progress beads remain |

**Detection script:**

```bash
./scripts/brennerbot-doctor.sh --pillar=4 --workspace=.
# Internally: convergence-check.sh --phase=4, --phase=6, --phase=7
```

**Common red causes:** time-pressure exit; operator declared "complete" before formula satisfied.

**Recovery:** re-enter the affected phase; run the missing rounds. May exceed wall-time budget — operator must decide.

---

## Pillar 5: Triangulation

| Check | Green | Yellow | Red |
|-------|-------|--------|-----|
| Roster has ≥3 distinct model families | yes | 2 | 1 (Solo) |
| Per-H investigation has ≥2 distinct family panes | ≥80% | 50-80% | <50% |
| Per-family distillations exist (cc, cod, gmi) | all 3 | 2 of 3 | 1 of 3 |
| Disagreement register has cross-family substantive entries | ≥1 per pair | partial | none (F-601 silent averaging) |
| Audit panes from different families than synthesizers | yes | 1 same-family | all same-family (F-705) |

**Detection script:**

```bash
./scripts/brennerbot-doctor.sh --pillar=5 --workspace=.
# Internally: triangulation-coverage.sh + list-distinct-model-families.sh
```

**Common red causes:** quota-staircase (DL-7) collapsed roster mid-session; planned Pair tier (acceptable for T2); single-family corner case.

**Recovery:** if mid-session collapse: spawn fresh family panes; redo affected per-family distillation. If planned Pair: accept and document in HANDBACK as triangulation-degraded caveat.

---

## Pillar 6: Cross-session

| Check | Green | Yellow | Red |
|-------|-------|--------|-----|
| Prior sessions on related topic identified | searched via /cass + /flywheel; documented | not searched | searched but ignored |
| Prior verdicts reconciled if conflicting | RECONCILIATION-MEMO.md exists | not reconciled but documented | conflicting verdicts silent |
| Phase 10 lessons reviewed against CROSS-SESSION-DRIFT-CATALOG.md | reviewed | not reviewed | catalog not maintained |
| If recurring incident: matched to INCIDENT-PATTERN-CATALOG.md | matched | not matched | catalog not maintained |

**Detection:** read `analyses/cross-session-impact.md` if exists.

**Common red causes:** operator skips Phase 10; treats each session as isolated.

**Recovery:** retroactively run `subagents/reconciler.md` for any conflicting prior session; commit RECONCILIATION-MEMO.md.

---

## Pillar 7: Deliverability

| Check | Green | Yellow | Red |
|-------|-------|--------|-----|
| HANDBACK.md exists and ≤80 lines | yes | exists but >80 lines | missing despite phase_9_complete.flag |
| HANDBACK has verdict on line 1-3 | yes | buried in section | no clear verdict |
| HANDBACK has cited evidence with W ≥ 0.7 | ≥3 EVs cited | 1-2 | 0 (vibes-based) |
| Listed unresolved threads have next-action tags | 100% | partial | none |
| DECISION-MEMO.md or other archetype-specific deliverable exists | yes | exists but template-incomplete | missing |
| RESUME.md hash-verifies via dry-run | yes | hashes drift but recoverable | hash mismatch (corrupt) |

**Detection script:**

```bash
./scripts/brennerbot-doctor.sh --pillar=7 --workspace=.
# Internally: phase-readiness.sh --phase=9 + resume-session.sh --dry-run
```

**Common red causes:** rushed Phase 9; HANDBACK inflation (>80 lines); voice failure (per HANDBACK-VOICE-GUIDE.md anti-patterns).

**Recovery:** apply MO-deliverable-rejection.md (R1-R8 categories); re-produce HANDBACK.

---

## Severity scoring

For each pillar:

| Verdict | Meaning |
|---------|---------|
| **🟢 GREEN** | All checks green. Pillar is healthy. |
| **🟡 YELLOW** | At least one yellow check. Pillar is impaired but salvageable. |
| **🔴 RED** | At least one red check. Pillar requires intervention before continuing. |

Workspace verdict = WORST pillar verdict. So one red pillar → red workspace.

---

## Composing the doctor pass

Full doctor pass:

```bash
./scripts/brennerbot-doctor.sh --workspace=. --all-pillars > deliverables/DOCTOR-REPORT.md
```

Output format (Tier-6):

```markdown
# Brennerbot Doctor Report

**Workspace:** /home/ubuntu/brennerbot_sessions/storage-eval
**Verdict:** YELLOW
**Date:** 2026-05-12T16:23:00Z

## Pillar verdicts

| Pillar | Verdict | Worst check |
|--------|---------|-------------|
| 1. Structural | 🟢 | (all green) |
| 2. Methodology | 🟡 | Phase 7 audit single-family (yellow) |
| 3. Bead invariants | 🟢 | (all green) |
| 4. Convergence | 🟢 | (all green) |
| 5. Triangulation | 🟡 | Audit panes single-family |
| 6. Cross-session | 🟢 | (all green) |
| 7. Deliverability | 🟡 | HANDBACK 87 lines (>80) |

## Recommendations

1. Pillar 2/5: rerun Phase 7 audit with cross-family roster
2. Pillar 7: compress HANDBACK to ≤80 lines per HANDBACK-VOICE-GUIDE.md tightening table

## Resume guidance

- Recommended re-entry: Phase 7 trio-round 2 with fresh-eyes-from-cod pane
- Estimated effort: 30-45 min additional
- Outcome if applied: GREEN verdict
```

---

## When to declare workspace unhealthy

🔴 **RED** verdict means **don't continue without recovery**. Specifically:

- Pillar 1 RED: workspace corrupt; cannot reliably continue
- Pillar 2 RED: methodology violation that invalidates outputs (e.g., F-501, F-705)
- Pillar 3 RED: bead state corrupt; downstream analysis unreliable
- Pillar 4 RED: phase declared complete without convergence; verdict unsound
- Pillar 5 RED: triangulation collapsed to single family; F-602 dominance
- Pillar 6 RED: cross-session conflict ignored; user may act on stale verdict
- Pillar 7 RED: missing deliverable; no actionable output

**Don't paper over reds.** Either recover or restart.

🟡 **YELLOW** = continue with caveats. Document in HANDBACK.

🟢 **GREEN** = continue normally.

---

## Recovery sequencing

When multiple pillars are yellow/red, recover in this order:

1. **Pillar 1 (Structural)** — without structure, nothing else makes sense
2. **Pillar 3 (Bead invariants)** — corrupt beads downstream
3. **Pillar 5 (Triangulation)** — single-family blind spots
4. **Pillar 2 (Methodology)** — discipline drift
5. **Pillar 4 (Convergence)** — phase exits
6. **Pillar 6 (Cross-session)** — methodology evolution
7. **Pillar 7 (Deliverability)** — output polish

Recovery often cascades: fixing Pillar 3 may resolve Pillar 4 automatically (correct beads → correct convergence).

---

## When to escalate

If 3+ pillars red OR Pillar 1 red:

1. Don't try to fix in-flight; emergency-stop the session
2. Run a `subagents/reconciler.md` against any related prior workspaces
3. Consider fresh-restart with corpus reuse (don't re-pin sources; reuse existing `.hash` records)
4. Document in `analyses/doctor-recovery-log.md` for cross-session learning

---

## Composition with adjacent skills

- `/world-class-doctor-mode-for-cli-tools` — pattern source for the doctor rubric concept
- `/fixing-beads-problems` — Pillar 3 RED recovery
- `/vibing-with-ntm` — Pillar 5 quota-staircase recovery (DL-7)
- `subagents/reconciler.md` — Pillar 6 cross-session recovery

---

## Cross-references

- [SIX-LAYER-VALIDATION.md](SIX-LAYER-VALIDATION.md) — overlaps with Pillars 1-5; six-layer is pre-Phase-8; this rubric is anytime
- [STRESS-TEST-SCENARIOS.md](STRESS-TEST-SCENARIOS.md) — pre-bootstrap mental rehearsal (S1-S15)
- [DEADLOCK-PATTERNS-MULTI-PANE.md](DEADLOCK-PATTERNS-MULTI-PANE.md) — DL-1..10 specific deadlocks
- [FAILURE-TABLE.md](FAILURE-TABLE.md) — F-### codes underlying the red checks
- [scripts/brennerbot-doctor.sh](../scripts/brennerbot-doctor.sh) — automation (Tier-6)
- [/world-class-doctor-mode-for-cli-tools](../../world-class-doctor-mode-for-cli-tools/SKILL.md) — concept source
