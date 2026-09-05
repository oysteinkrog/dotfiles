# COACH-MODE-GUIDED-LEARNING.md — Progressive Scaffolding for New Operators

<!-- TOC: Why coach mode | The 3 coaching levels | Auto-promotion criteria | Quality checkpoints | Concept explanations | The learn-by-doing inversion | Per-phase coach activity | Anti-patterns | Cross-references -->

A new operator confronting brennerbot's full methodology faces overwhelm: 15 operators, 9 hypothesis states, 14 evaluation criteria, 50+ lint rules. Conventional tutorials don't survive contact with a real session.

Brennerbot's **Coach Mode** inverts the model: **learn by doing with guardrails**. The system watches what the operator is doing, explains concepts when they become relevant, catches common mistakes before they compound. This mirrors how Brenner himself taught — through working examples, not lectures.

Mined from `/dp/brenner_bot/README.md § Coach Mode`.

---

## Why coach mode

Three failures of traditional tutorial-first onboarding:

1. **Pre-loaded knowledge fails to stick** — reading "what is a discriminative test" before doing one produces shallow understanding
2. **Errors compound silently** — new operator makes a methodology mistake at Phase 3; doesn't realize until Phase 7 audit fires
3. **No just-in-time guidance** — concept relevance only emerges at the moment of use; tutorials front-load context that's not yet needed

Three benefits of learn-by-doing-with-guardrails:

1. **Concept introduction at moment of use** — system explains "discriminative test" *when* operator is designing one
2. **Real-time error catching** — Phase 3 mistake gets corrected at Phase 3, not at Phase 7
3. **Brenner-modeled pedagogy** — the methodology being taught is the methodology being applied

---

## The 3 coaching levels

| Level | Explanation Verbosity | Confirmations | Auto-Pause |
|-------|----------------------|---------------|------------|
| `beginner` | Full explanations with examples + Brenner quotes | Required for major actions | Yes, at each phase |
| `intermediate` | Brief explanations; examples on request | Optional | Only at decision points |
| `advanced` | Tooltips only; no interruptions | Rare | Never |

Each level changes the agent-ergonomics of the entire session. A beginner-level session is operator-walked-through; an advanced-level session runs autonomously.

---

## Auto-promotion criteria

The system tracks per-operator progress and auto-promotes:

```typescript
interface LearningProgress {
  seenConcepts: Set<ConceptId>;       // concepts whose explanations were viewed
  sessionsCompleted: number;          // total sessions finished
  hypothesesFormulated: number;       // Hs created
  operatorsUsed: Set<string>;         // Brenner operators applied
  mistakesCaught: number;             // quality checkpoint failures
  checkpointsPassed: number;          // quality checkpoint successes
  firstSessionDate?: string;
  lastSessionDate?: string;
}
```

Promotion thresholds (tunable):

| Promotion | Trigger |
|-----------|---------|
| beginner → intermediate | ≥3 sessions completed AND ≥10 concepts seen AND mistake rate <30% |
| intermediate → advanced | ≥10 sessions completed AND ≥30 concepts seen AND ≥75% checkpoint pass rate |

The promotion is **bi-directional**: persistent failure at intermediate triggers demotion to beginner with a reset.

Per OPERATOR-CALIBRATION-LOG.md: coach-mode level is logged per session.

---

## Quality checkpoints

At critical moments (hypothesis formulation, test design, assumption logging), Coach Mode validates user input against Brenner-style quality criteria:

### Hypothesis quality checks

- **Statement length** — too short = too vague (heuristic: <40 chars)
- **Vague causal language** — "may", "could", "might" without mechanism specification
- **Missing mechanism** — claim without "because X, then Y" structure
- **Missing predictions** — H without `expected_evidence` field
- **Missing falsification conditions** — H without explicit `falsifier`
- **Unfalsifiable hedging** — "might possibly under some conditions"

Each check returns:

```typescript
interface CheckpointResult {
  severity: "error" | "warning" | "info";
  explanation: string;        // why this matters in Brenner context
  suggestion: string;         // specific improvement
}
```

### Test design checkpoints

- **Discriminative power** — does the test distinguish ≥2 Hs differently?
- **Potency check** — is positive control specified?
- **Cost calibration** — is the time/$ estimate present?
- **Forbidden pattern** — what observation refutes the H?

### Assumption checkpoints

- **Load-bearing identification** — is this assumption required for the H to hold?
- **Falsifier specification** — what observation breaks the assumption?
- **Scale-physics calculation** — for `type: scale_physics`, is calc present?

Per ARTIFACT-LINTER-RULES.md: checkpoint failures are forerunners of lint failures. Catching them at coach-time prevents lint-time errors.

---

## Concept explanations

Explanations are **keyed to specific concepts and phases**:

```typescript
type ConceptId =
  // Phases
  | "phase_intake"
  | "phase_sharpening"
  | "phase_level_split"
  | "phase_exclusion_test"
  | "phase_potency_check"
  // ... operators
  | "operator_⊘_level_split"
  | "operator_𝓛_recode"
  | "operator_✂_exclusion_test"
  // ... methodology
  | "third_alternative"
  | "forbidden_pattern"
  | "digital_handle"
  | "machine_language";
```

Each explanation includes:

```typescript
interface Explanation {
  brief: string;          // always-visible short explanation
  full: string;           // detailed explanation for beginners
  keyPoints: string[];    // bulleted takeaways
  brennerQuote?: string;  // relevant transcript quote
  example: string;        // concrete worked example
}
```

Example for `operator_⊘_level_split`:

```yaml
brief: "Separate program from interpreter; message from machine"
full: |
  When you're arguing about whether something is "regulation" or "structure", you may be conflating two different causal levels. ⊘ Level-Split is the discipline of separating them: the program (information) is different from the interpreter (mechanism); the message is different from the machine that reads it.
keyPoints:
  - Program ≠ interpreter (DNA ≠ ribosome)
  - Message ≠ machine
  - Specification ≠ execution
  - Type failures: chastity (won't) vs impotence (can't)
brennerQuote: "you could make a machine in which the instructions were separate from the machine" (§105)
example: |
  Bad: "The gene tells the cell to produce protein X"  (conflates program + interpreter)
  Good: "Gene G encodes the program; ribosome R interprets it; the protein is the execution result"
```

Per JARGON-DICTIONARY-PROGRESSIVE-DISCLOSURE.md: same progressive-disclosure pattern; coach mode pulls from this dictionary.

---

## The learn-by-doing inversion

Traditional model:
```
Read tutorial → Memorize concepts → Try to apply → Realize gaps → Re-read tutorial
```

Coach mode:
```
Start session → Try to act → System detects relevant concept → Just-in-time explanation →
Continue with new context → Quality check at decision point → Either pass (continue) or fail (correct)
```

The shift: the system **watches**, **detects**, **explains**, **corrects** in real time. Operator never reads ahead; concepts arrive when they matter.

Per Brenner's own pedagogy:
> Brenner himself taught—through conversation and working examples rather than lectures.

Coach mode is the technological embodiment of this teaching style.

---

## Per-phase coach activity

| Phase | Coach activity (beginner level) |
|-------|---------------------|
| 1 framing | Auto-pause; explain `phase_intake`, `falsifier`, `RT` concepts; checkpoint: question well-formed? |
| 2 bootstrap | Auto-pause; explain `roster`, `role_separated mode`, ntm panes |
| 3 hypothesis | Per-H quality checkpoint (vague language? mechanism? falsifier?); explain `third_alternative` if missing |
| 4 investigation | Per-EV checkpoint (anchor present? supports/refutes?); explain `digital_handle` |
| 5 cross-exam | Per-critique checkpoint (severity calibrated? evidence cited?) |
| 6 distillation | Explain `[synthesis]` marker; checkpoint: distillations triangulate? |
| 7 audit | Explain `audit-finding` severity; checkpoint: lint-clean? |
| 8 freeze | Explain RESUME.md format; checkpoint: all H states terminal? |
| 9 handback | Explain HANDBACK voice; checkpoint: ≤1 page? |
| 10 drift | Explain `DRIFT-CHECK.md` semantics; checkpoint: trajectory described? |

For intermediate: auto-pause only at decision points (Phase 5, 7, 9).
For advanced: tooltips only; no interruptions.

---

## Operator-coach integration

When `coach: beginner`, the dispatcher injects coach context into MOs:

```
MO-03a-propose dispatch (with coach: beginner):
  Standard MO content
  + COACH CONTEXT:
    - Concept being practiced: third_alternative
    - Previous mistakes: 2 (vague language at session N-1)
    - Reminder: cite §103 anchor for third-alternative grounding
    - Quality checkpoint will fire if: H without explicit falsifier OR H sounds like rephrasing
```

The pane sees the augmented prompt; produces output with the coaching guidance in mind.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip coach mode for "fast" T1 sessions | T1 is *exactly* where new operators should use it |
| Stay at beginner level after 10+ sessions | Auto-promotion exists; manual override should be rare |
| Disable checkpoints because "they slow me down" | Checkpoints prevent Phase 7 audit-finding generation; trade-off favors checkpoints |
| Use coach mode for autonomous robot mode | Robot mode + coach mode = contradictions (HITL pauses + autonomous progression) |
| Add custom concepts without dictionary entry | Per JARGON-DICTIONARY: every concept has 4-level explanation |
| Treat checkpoint failures as personal | Per OPERATOR-CALIBRATION-LOG.md: checkpoints are coaching, not evaluation |
| Skip coach mode for new domain | Even experienced operators benefit on new archetypes |

---

## Composition with brennerbot

Coach mode integrates with:

- **OPERATOR-CALIBRATION-LOG.md**: coaching level + progress tracked per-session
- **OPERATOR-ONBOARDING-CURRICULUM.md**: Week 1-4 fluency milestones map to coach levels
- **JARGON-DICTIONARY-PROGRESSIVE-DISCLOSURE.md**: concept explanations source from dictionary
- **ARTIFACT-LINTER-RULES.md**: checkpoint failures preview lint failures
- **EVALUATION-RUBRIC-14-CRITERIA.md**: quality checkpoints map to rubric criteria
- **SESSION-REPLAY-AND-REPRODUCIBILITY.md**: coaching events recorded in trace

---

## Cross-references

- [JARGON-DICTIONARY-PROGRESSIVE-DISCLOSURE.md](JARGON-DICTIONARY-PROGRESSIVE-DISCLOSURE.md) — concept explanation source
- [OPERATOR-ONBOARDING-CURRICULUM.md](OPERATOR-ONBOARDING-CURRICULUM.md) — Week 1-4 progression
- [OPERATOR-CALIBRATION-LOG.md](OPERATOR-CALIBRATION-LOG.md) — track coaching level per session
- [ARTIFACT-LINTER-RULES.md](ARTIFACT-LINTER-RULES.md) — checkpoint preview of lint
- [EVALUATION-RUBRIC-14-CRITERIA.md](EVALUATION-RUBRIC-14-CRITERIA.md) — quality criteria
- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — checkpoint at state transitions
- /dp/brenner_bot/README.md § Coach Mode — original source
