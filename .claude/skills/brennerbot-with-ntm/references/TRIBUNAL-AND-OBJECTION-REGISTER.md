# TRIBUNAL-AND-OBJECTION-REGISTER.md — Adversarial Review as Hard Gate

<!-- TOC: Why a tribunal | The objection register | Severity + action taxonomy | The hard gate: blocking session completion | Per-objection workflow | Critique target types | Brenner-quote-grounded critique | Detection: objections that are being avoided | Cross-session objection patterns | Anti-patterns | Cross-references -->

In brennerbot, adversarial review is not optional and not a "nice to have." It's a **formal tribunal system** with a **hard gate**: sessions cannot complete (Phase 8 freeze) while there are unresolved objections. Without this enforcement, sessions ship un-stress-tested verdicts.

This file specifies the tribunal mechanism, the objection register, severity calibration, action taxonomy, and the gate.

Mined from `/dp/brenner_bot/README.md § Tribunal System` and § Critique Management, plus pilot retrospective patterns.

---

## Why a tribunal

Conventional research review is "submit when ready" + reviewer comments. The brennerbot tribunal differs:

1. **Adversarial-by-default** — the Critic role's job is to attack, not to "balance" or "be fair"
2. **Resolution-required** — a critique can't be silently ignored; it must be `addressed`, `dismissed`, or `accepted`
3. **Block-until-clean** — sessions can't reach Phase 8 freeze with `active` critiques
4. **Auditable trail** — dismissed critiques must have a documented reason

The result: sessions whose verdicts ship have *survived adversarial review*, not just "the team felt good about it."

---

## The objection register

Every session has an `objection_register` — a section in the 7-section artifact (per ARTIFACT-7-SECTION-SCHEMA.md § 7 Adversarial Critique) plus a parallel set of `C-NNN` beads.

### Critique bead schema

```yaml
id: C-001
label: critique
target: H-002 | T-001 | A-003 | framing | methodology
attack: <one paragraph: the specific argument>
evidence: <citation: §n, EV-NNN, or [inference]>
severity: minor | moderate | serious | critical
status: active | addressed | dismissed | accepted
action: null | modified | dismissed | killed | accepted
response: <if addressed: what was done in response>
resolved_by: <agent identity that responded>
resolved_at: <ISO timestamp>
```

### Critique target types

A critique can target:

| Target type | What it attacks | Example |
|-------------|-----------------|---------|
| `H-NNN` | A specific hypothesis | "H1 confuses correlation with causation" |
| `T-NNN` | A specific discriminative test | "T2 lacks potency control" |
| `A-NNN` | A specific assumption | "A1's scale-physics calc uses wrong diffusion constant" |
| `framing` | The Phase 1 question of record | "Wrong level of description — should ask about information flow" |
| `methodology` | The session's process | "Adjudicator hasn't rotated; same pane scoring 3 debates" |

`framing` and `methodology` critiques are the highest-leverage because they invalidate downstream work. A `critical` framing critique often forces a Phase 1 reframe.

---

## Severity calibration

Per `/dp/brenner_bot/README.md § Critique Management`:

| Severity | When to use | Phase 8 freeze impact |
|----------|-------------|----------------------|
| `minor` | Style or polish issue | Doesn't block; logged |
| `moderate` | Reduces verdict confidence by ≤1 level | Doesn't block; HANDBACK § Caveats |
| `serious` | Reduces verdict confidence by ≥2 levels | **Blocks freeze unless resolved** |
| `critical` | Invalidates the verdict | **Blocks freeze; forces Phase 1 reframe or H-state revision** |

`serious` and `critical` are the **gate-blocking severities**. Operators MUST address them before freezing.

A common failure mode: operators use `moderate` for everything to avoid the gate. Per Phase 7 audit, calibrate severity:

- If the critique would change someone else's downstream decision → severity ≥ serious
- If the critique would invalidate the verdict → severity = critical
- "Doesn't change anything" → severity = minor

---

## Action taxonomy

When a critique transitions from `active` to a non-active state, the `action` field records what happened:

| Action | Meaning | Subsequent state |
|--------|---------|------------------|
| `modified` | The target was modified to address the critique | status = `addressed` |
| `dismissed` | The critique was rejected with a documented reason | status = `dismissed` |
| `accepted` | The critique was correct; the target was killed | status = `accepted`; target H-NNN/T-NNN may transition to `killed` |
| `null` | (Only when status = `active`) | status = `active` |

**Critical:** dismissing a critique requires `--reason`. "Disagree" without reason is rejected by the validator.

```bash
# Acceptable dismissal:
brenner critique dismiss C-001 --reason "Cited evidence is from non-comparable system (Drosophila vs vertebrate; cells differ in size by 3 orders of magnitude per ⊞ Scale-Check)"

# Rejected by validator:
brenner critique dismiss C-001 --reason "doesn't apply"  # too vague
```

---

## The hard gate: blocking session completion

Per `/dp/brenner_bot/README.md § Block session completion when unresolved objections remain`:

**Phase 8 freeze fails if any critique has:**
- `status: active` AND
- `severity: serious` OR `severity: critical`

The brennerbot doctor (per BRENNERBOT-DOCTOR-RUBRIC.md) Pillar 1 (Structural) checks:
```
✗ FAIL: 2 critiques active with severity ≥ serious; cannot freeze
   - C-003 (severity: critical, target: framing)
   - C-007 (severity: serious, target: H-002)
```

Operator options:
1. **Resolve** — engage the critic; modify the target; close the critique
2. **Dismiss with documented reason** — must be specific and citable
3. **Accept** — concede the critique; kill the target

Skipping the gate (e.g., manually editing critique status) generates an audit-finding bead at next Phase 7 audit. This is a high-severity finding because it's a systemic discipline failure.

---

## Per-objection workflow

When a critique is filed:

1. **Bead created** with `status: active`, `severity: <calibrated>`
2. **Mail thread opened**: `RS-...-CRITIQUE-C-NNN` (per AGENT-MAIL-CONVENTIONS.md)
3. **Target's owner notified** (the Investigator or Proposer who created H/T/A)
4. **Adversarial round begins** — debate per BRENNER-GAN-MECHANICS.md
5. **Resolution proposed** — modified / dismissed / accepted
6. **Adjudicator (rotated) approves resolution** — per Phase 5 protocol
7. **Critique status updated** — addressed / dismissed / accepted
8. **Side effects propagate** — if accepted, target H/T/A may transition to `killed` (per HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md)

Time budget: a critical critique typically consumes 15-45 min of operator time. Budget for it.

---

## Brenner-quote-grounded critique

Per `/dp/brenner_bot/README.md § Adversarial Pressure` (scoring dimension):

A high-quality critique cites a specific Brenner anchor (`§n`) or evidence pack reference (`EV-NNN`). Examples:

```
Severity: critical
Target: H-002
Attack: H-002 conflates regulation with structure (program vs interpreter — per §105 "you could make a machine in which the instructions were separate from the machine"). The hypothesis claims a regulatory mechanism but describes structural inheritance. ⊘ Level-Split required.
Evidence: §105, EV-007#E2 [verbatim showing structural inheritance pattern]
```

Per `/dp/brenner_bot/specs/evaluation_rubric_v0.1.md` Adversarial Critic criteria:

| Criterion | Multiplier | What it measures |
|-----------|-----------|--------------------|
| Scale Check Rigor | ×1.5 | "The imprisoned imagination" — physical-magnitude calculations |
| Anomaly Quarantine Discipline | ×1.5 | Don't let Occam's broom hide debt |
| Theory Kill Justification | ×1.5 | "When they go ugly, kill them" |
| Real Third Alternative | ×1.5 | Genuinely orthogonal, not "both could be wrong" filler |

Critiques without anchors get scored down. Per Phase 7 audit + EVALUATION-RUBRIC-14-CRITERIA.md.

---

## Detection: objections that are being avoided

Sometimes panes generate critiques that are *too soft to gate*. Detection signs:

- All critiques are `severity: minor` (suspicious — adversarial role isn't biting)
- Critiques are filed and immediately dismissed by the same pane (no adversarial round)
- Critiques target only `methodology` (avoiding hypothesis-level attacks)
- High `addressed` rate without target modification (rubber-stamping)

Per Phase 7 audit:

```
DETECTION: 15 critiques filed; 14 dismissed; 1 active (severity: minor); 0 modifications to any target.
DIAGNOSIS: F-501 (no kills) + F-403 (rubber-stamp adversarial review)
```

Mitigation: rotate Adversarial Critic role; mandate ≥1 critique with severity ≥ serious per active H (per OC-022 in OPERATOR-CARDS.md).

---

## Cross-session objection patterns

Per CROSS-SESSION-LEARNING.md, certain critique patterns recur:

| Pattern | What it means | Action |
|---------|---------------|--------|
| Same operator's H consistently attracts `framing` critiques | Phase 1 framing weakness | Coach via OPERATOR-CALIBRATION-LOG.md D-Cal-3 |
| Same archetype generates `scale_physics` critiques | Domain-specific gap | Update ARCHETYPE-START-PACKS.md per archetype |
| Critiques cluster around specific operators (e.g., always ⊘ Level-Split) | Operator under-trained | Re-run OPERATOR-ONBOARDING-CURRICULUM Week 2 |

Cross-session aggregation (per BRENNERBOT-AT-SCALE.md) makes these patterns actionable.

---

## Composition with brennerbot phases

| Phase | Tribunal activity |
|-------|---------------------|
| 3 | Critique slate begins (during proposer round) |
| 4 | Devil's-Advocate files initial critiques per H |
| 5 | Cross-examination produces high-severity critiques |
| 6 | Distillations note unresolved critiques |
| 7 | Audit checks: are any critical critiques unresolved? |
| **8** | **Gate**: cannot freeze with serious+ critiques active |
| 9 | HANDBACK § Caveats lists dismissed-but-noted critiques |

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip critique-bead filing for "obvious" issues | The audit trail breaks; future cross-session aggregation loses signal |
| File critique without `severity` | Validator rejects |
| `dismissed` without specific `reason` | Validator rejects |
| Same pane writes critique AND adjudicates resolution | Conflict of interest; per F-502 adjudicator bias |
| `severity: minor` for everything | Bypasses the gate (per F-705-class) |
| Resolve critiques in batch ("all addressed") | Each critique needs individual resolution |
| Skip the hard gate at Phase 8 | High-severity audit-finding at next Phase 7 |
| Treat `framing` critique as low-severity | Framing critiques are usually highest-leverage |
| Allow critique bead to stay `active` between sessions | Either resolve or carry to next session's intake |

---

## Cross-references

- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — kill_reason linked to critique acceptance
- [BRENNER-GAN-MECHANICS.md](BRENNER-GAN-MECHANICS.md) — adversarial round protocol
- [CRITIQUE-CRAFT.md](CRITIQUE-CRAFT.md) — how to write good critiques
- [BRENNERBOT-DOCTOR-RUBRIC.md](BRENNERBOT-DOCTOR-RUBRIC.md) — Pillar 1 gate enforcement
- [EVALUATION-RUBRIC-14-CRITERIA.md](EVALUATION-RUBRIC-14-CRITERIA.md) — adversarial critic criteria
- [PHASES.md](PHASES.md) — Phase 5 + Phase 8 gates
- [BEADS-SCHEMA.md](BEADS-SCHEMA.md) — `C-NNN` critique bead schema
- /dp/brenner_bot/README.md § Tribunal System, § Critique Management — original source
- /dp/brenner_bot/specs/evaluation_rubric_v0.1.md — adversarial critic scoring
