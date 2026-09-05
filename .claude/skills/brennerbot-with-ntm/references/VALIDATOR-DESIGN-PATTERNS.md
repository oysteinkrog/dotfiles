# VALIDATOR-DESIGN-PATTERNS.md — Designing Mechanizable Validators

<!-- TOC: Why validators | Validator types | Mechanizable vs heuristic | Design checklist | Anti-pattern: subjective validators | Per-operator validators | Per-phase validators | Cross-cutting validators | Composition with audit | Calibration | Anti-patterns -->

Per /operationalizing-expertise stage 5: validators are the mechanizable checks that confirm an operator was correctly applied. Without validators, operator application is informal — operators say they applied ✂ Exclusion-Test, but no one verifies.

This file documents how to design validators that are mechanizable, calibrated, and useful for the audit / drift-check protocols.

---

## Why validators

A skill without validators is faith-based. The methodology promises X if applied correctly, but no one checks.

With validators:
- Every audit / drift-check has a concrete pass/fail
- Phase 7 audit becomes verifiable (not just consensus)
- Operator calibration improves (operators see specific failures)
- Cross-session learning compounds (which validators consistently fail?)

Brennerbot's `scripts/audit-bead-invariants.sh`, `scripts/check-rotation-rules.sh`, `scripts/disagreement-register-lint.sh`, `scripts/check-six-layer-validation.sh`, etc., are all validators.

---

## Validator types

### V1: Structural

Verify schema-level properties:
- Every H bead has a non-empty `falsifier` field
- Every refuted H has a `refuted_by` reference
- Every audit-finding has a severity tag

Mechanized via `audit-bead-invariants.sh`.

### V2: Quantitative

Verify metric-based properties:
- kill_rate ≥ add_rate (Phase 4 convergence)
- ≥3 substantive disagreement entries in disagreement_register (Phase 6)
- HANDBACK.md ≤80 lines (Phase 9)

Mechanized via `convergence-check.sh`, `disagreement-register-lint.sh`, etc.

### V3: Discipline

Verify procedural properties:
- Adjudicator rotation rule (no same Adjudicator twice in a row)
- Cross-family champion rule
- Audit pane diversity rule

Mechanized via `check-rotation-rules.sh`.

### V4: Behavioral

Verify pattern-of-application properties:
- Per-H ≥1 falsifier-firing investigation per Phase 4 round
- Per-EV verbatim quote ≥1 per claim
- Per-source class ≥ cadence-appropriate verification frequency

Mechanized via `check-anchor-density.sh`, `check-volatile-source-staleness.sh`.

### V5: Cross-session

Verify pattern-across-sessions properties:
- 3+ consecutive sessions with same drift verdict → flag
- Operator's high-confidence Hs failing in subsequent sessions → flag

Mechanized via `drift-trend.sh` and CROSS-SESSION-DRIFT-CATALOG.md.

---

## Mechanizable vs heuristic

A good validator is mechanizable: a script can decide pass/fail without operator judgment.

### ✓ Mechanizable

- "Every H has a non-empty `falsifier:` field" (script checks)
- "Phase 4 round N has kill_rate ≥ add_rate" (script computes)
- "Audit pane family ≠ synthesizer family" (script compares)

### ✗ Heuristic (not mechanizable)

- "The investigation was thorough" (subjective; needs operator judgment)
- "The hypothesis is well-formed" (subjective)
- "The argument is convincing" (subjective)

For heuristic concerns, use:
- Subagent grading (e.g., `subagents/falsifier-grader.md`) — applies a rubric
- Multi-pane consensus (per Phase 7 trio)
- Calibration tracking (per OPERATOR-CALIBRATION-LOG)

A validator that's heuristic is fine if explicit; just don't pretend it's mechanizable.

---

## Design checklist

When designing a validator:

1. **What property does it verify?** (single-sentence)
2. **What action triggers verification?** (per-bead-create, per-phase-exit, per-audit-round)
3. **What's the pass criterion?** (specific observable)
4. **What's the fail mode?** (if not pass, what specifically?)
5. **What's the recovery?** (per failure: which MO + which operator card)
6. **Mechanized via?** (script name + arguments)
7. **False-positive rate?** (how often does it fire when no real issue?)
8. **False-negative rate?** (how often does a real issue evade it?)

---

## Per-operator validators

Per OPERATORS.md, each of the 15 operators has a validator:

| Operator | Validator | Mechanized via |
|----------|-----------|----------------|
| ◊ Paradox-Hunt | Phase 1 question_of_record has non-empty Paradox section | `phase-readiness.sh --phase=1` |
| ⊘ Level-Split | At least 1 H has level-split origin | `audit-bead-invariants.sh --check=phase3_exit` |
| 𝓛 Recode | Synthesizers re-state claims; meta-synth has ≥1 recode | implicit; operator self-check |
| ≡ Invariant-Extract | Per-H invariants documented in description | bead schema |
| ✂ Exclusion-Test | ≥1 falsifier-firing attempt per H per Phase 4 round | `audit-bead-invariants.sh` |
| ⟂ Object-Transpose | Cross-domain imports documented | `phase0_scope_decision.md § cross_domain_imports` |
| ↑ Amplify | High-confidence Hs get more Phase 4 rounds | bead priority + round count |
| ⌂ Materialize | Hypotheticals → specific test cases | EV bead schema |
| 🔧 DIY | Replication for load-bearing claims | MO-academic-replication tracking |
| ⊞ Scale-Check | Each scale_physics assumption has calculation | bead `assumption_type:scale_physics` |
| 🤝 GAN | Cross-family champions in Phase 5 | `check-rotation-rules.sh` Rule 1+2 |
| ΔE Exception-Quarantine | Anomalies tracked in anomaly_register | bead label `anomaly` |
| † Theory-Kill | Adjudicator kill rate > 0% (per F-501 calibration) | session metric |
| ∿ Dephase | Phase 7 audit explicitly checks consensus capture | OC-008 OPERATOR-CARDS check |
| ⊙ Productive-Ignorance | One pane operates without corpus access | OC-005 file restriction |

---

## Per-phase validators

Per PHASES.md, each phase has exit gates:

### Phase 1
- question_of_record.md exists with non-empty Falsifier
- Q-001 bead created and closed
- corpus_index.md has ≥1 row

Validator: `phase-readiness.sh --phase=1`

### Phase 2
- All panes acknowledged onboarding (Agent Mail acks)
- Roster recorded in scope_decision

Validator: `wait-for-onboard-acks.sh`

### Phase 3
- ≥3 distinct Hs
- ≥1 with origin:third_alternative
- All Hs have falsifier field

Validator: `audit-bead-invariants.sh --check=phase3_exit`

### Phase 4
- kill_rate ≥ add_rate
- All active H have ≥1 supporting EV that survived attack

Validator: `convergence-check.sh --phase=4`

### Phase 5
- Every active H survived ≥1 adversarial debate
- Adjudicator rotation rule satisfied

Validator: `check-rotation-rules.sh`

### Phase 6
- Per-family distillation files exist
- meta_synthesis.md exists
- disagreement_register.md has ≥1 substantive entry per family pair

Validator: `disagreement-register-lint.sh`

### Phase 7
- Two consecutive trio-rounds clean
- ubs clean on deliverables

Validator: `convergence-check.sh --phase=7` + `run-ubs-on-deliverables.sh`

### Phase 8
- RESUME.md exists with required tokens
- git status clean
- ntm checkpoint exported

Validator: `dump-session-report.sh` + `resume-session.sh --dry-run`

### Phase 9
- HANDBACK.md exists ≤80 lines
- Listed unresolved-thread tags present

Validator: `audit-bead-invariants.sh --check=handback_open_thread_tags` + `wc -l`

### Phase 10
- DRIFT-CHECK.md exists
- ≥1 lesson committed

Validator: `phase-readiness.sh --phase=10`

---

## Cross-cutting validators

These verify properties not tied to a specific phase:

### V-Cross-1: Bead invariants (always)

Per BEADS-SCHEMA.md:
- Every H has falsifier
- Every EV has source + verbatim
- Every audit-finding has severity
- Every refuted H has refuted_by

Mechanized: `audit-bead-invariants.sh --all`

### V-Cross-2: Layout invariants (always)

Per WORKSPACE-LAYOUT.md:
- Required directories exist
- Corpus content-hashes recorded
- intake/question_of_record.md exists

Mechanized: `audit-bead-invariants.sh --check=layout`

### V-Cross-3: Six-layer validation (pre-Phase-8)

Per SIX-LAYER-VALIDATION.md:
- Layer 1-5 all pass

Mechanized: `check-six-layer-validation.sh`

### V-Cross-4: Anchor density (per EV)

Per CRITIQUE-CRAFT.md:
- Per-EV ≥1 verbatim quote
- Per-EV ≥1 source citation

Mechanized: `check-anchor-density.sh`

### V-Cross-5: Volatile source staleness

Per VERIFICATION-FIRST.md:
- Live sources re-verified per cadence
- Versioned sources verified per release

Mechanized: `check-volatile-source-staleness.sh`

---

## Composition with audit

Validators feed Phase 7 audit:

1. Phase 7 trio-round 1 dispatched
2. Audit panes run validators (`audit-bead-invariants.sh`, `check-rotation-rules.sh`, etc.)
3. Failed validators surface as audit-findings
4. Audit-findings get severity per CRITIQUE-CRAFT.md
5. Operator addresses findings before next round
6. Trio-round 2 re-runs validators; verifies fixes

Per OC-022 (OPERATOR-CARDS.md): Phase 7 trio MUST run all V-Cross validators before declaring audit converged.

---

## Calibration

A validator's quality is measured by:

### Recall (true positive rate)

How often does the validator catch a real issue?

Track via cross-session: when a session later turns out to have had a methodology issue, was it caught by validators? If not, that's a recall gap.

### Precision (false positive rate)

How often does the validator fire when no real issue exists?

Track via operator override frequency: if operators consistently override validator warnings, the validator may be too aggressive.

### Cost

Time + tokens to run the validator. Validators that run on every tick must be cheap; validators that run on Phase exit can be expensive.

### Calibration loop

Per Phase 10 drift, evaluate:
- Validators that fired but were overridden → tighten or sunset
- Issues that escaped all validators → add new validator for that pattern
- Validators with high false-positive rate → adjust thresholds

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Heuristic validator dressed as mechanical | Operators trust it; misses real issues |
| Validator that requires operator judgment to interpret | Defeats the point; should be subagent if judgment-heavy |
| Validator that fires on EVERY session | Useless signal; recalibrate threshold |
| Validator that NEVER fires | Either methodology is perfect (unlikely) or threshold too lax |
| Validator without recovery path | Operator sees failure; doesn't know what to do |
| Multiple overlapping validators that catch same issue | Wasted effort; consolidate |
| Validator that takes >5min to run on every Phase exit | Too expensive; move to per-Phase-exit only |

---

## When to invent a new validator

A new validator is justified when:

1. ≥3 sessions surfaced a methodology issue not caught by existing validators
2. The issue has a mechanizable signature (not requiring judgment)
3. The recovery is well-defined

Process:
1. Document the issue in EXTENDED-FAILURE-CATALOG.md as a new F-### code
2. Design the validator (per "design checklist" above)
3. Implement as new script in `scripts/`
4. Reference from SIX-LAYER-VALIDATION.md if cross-cutting
5. Test on next session; track precision and recall
6. Promote to canonical after 3+ sessions of stable use

---

## Subagent-mediated validation

Some validators require judgment that a script can't do but a fresh agent can. These use subagents:

- `subagents/falsifier-grader.md` — grades H falsifiers on 5-dimension rubric
- `subagents/evidence-grader.md` — grades EVs (Tier-5 subagent if added)
- `subagents/drift-auditor.md` — assesses drift verdict
- `subagents/reconciler.md` — reconciles cross-session conflicts

These are validators that require judgment; the subagent applies a rubric and produces a structured grade.

---

## Cross-references

- OPERATORS.md (the operators that validators verify)
- BEADS-SCHEMA.md (structural invariants)
- SIX-LAYER-VALIDATION.md (the validation regime)
- CRITIQUE-CRAFT.md (severity calibration)
- /operationalizing-expertise (Track-A stage 5)
- scripts/ (the mechanized validators)
- subagents/ (the judgment-mediated validators)
