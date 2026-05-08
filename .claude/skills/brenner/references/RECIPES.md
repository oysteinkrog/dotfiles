# Workflow Recipes

> **Priority:** Build excerpts first. Corpus context grounds everything.

---

## Recipe Index

| Recipe | When |
|--------|------|
| [Session Bootstrap](#session-bootstrap) | Start of every brenner session |
| [Corpus Mining](#corpus-mining) | Find relevant Brenner quotes |
| [Hypothesis Management](#hypothesis-management) | Add, attack, kill hypotheses |
| [Third Alternative Injection](#third-alternative-injection) | Force "both wrong" framing |
| [Test Design](#test-design) | Create discriminative experiments |
| [Artifact Compilation](#artifact-compilation) | Merge deltas into artifact |
| [Tribunal Session](#tribunal-session) | Multi-agent research workflow |
| [Evidence Pack](#evidence-pack) | Attach supporting evidence |

---

## Session Bootstrap

**Always start here:**

```bash
# 1. Health check
brenner doctor --skip-ntm --skip-cass --skip-cm --json

# 2. Check Agent Mail
brenner mail health

# 3. List available agents
brenner mail agents --project-key "$PWD"
```

---

## Corpus Mining

**Goal:** Find relevant Brenner quotes to ground research.

```bash
# Search by concept
brenner corpus search "model organism"
brenner corpus search "reduction to one dimension"
brenner corpus search "exclusion"

# Search for specific operators
brenner corpus search "third alternative"
brenner corpus search "chastity impotence"
brenner corpus search "reconstruction"

# Build excerpt from found sections
brenner excerpt build --sections 58,78,161 > excerpt.md
```

### High-Value Sections

| Section | Topic |
|---------|-------|
| §12-§25 | Model organism selection |
| §58-§65 | Reduction to one dimension |
| §78-§85 | Third alternative injection |
| §120-§130 | Reconstruction criterion |
| §161-§170 | Exclusion over confirmation |

---

## Hypothesis Management

**Goal:** Maintain 2-5 hypotheses with proper state transitions.

### Add Hypothesis

```json brenner-delta
{
  "operation": "ADD",
  "target_section": "hypothesis_slate",
  "payload": {
    "id": "H2",
    "statement": "The gradient is established by diffusion",
    "state": "proposed",
    "confidence": 0.6
  },
  "rationale": "Alternative to receptor-mediated model"
}
```

### Attack Hypothesis

```json brenner-delta
{
  "operation": "EDIT",
  "target_section": "hypothesis_slate",
  "target_id": "H1",
  "payload": {
    "state": "under_attack",
    "attack_source": "Anomaly A3"
  },
  "rationale": "New evidence contradicts prediction P1.2"
}
```

### Kill Hypothesis

```json brenner-delta
{
  "operation": "KILL",
  "target_section": "hypothesis_slate",
  "target_id": "H1",
  "payload": {
    "kill_rationale": "Test T2 falsified P1.1",
    "evidence_link": "E5"
  },
  "rationale": "Exclusion via decisive experiment"
}
```

### Hypothesis State Machine

```
draft → proposed → active
                    ↓
        ┌──────────┼──────────┐
        ↓          ↓          ↓
  under_attack  assumption   refined
        │       undermined      │
        └──────────┼───────────┘
                   ↓
           ┌───────┼───────┐
           ↓       ↓       ↓
        killed  validated  dormant
```

---

## Third Alternative Injection

**Goal:** Always include "both could be wrong" hypothesis.

### The Pattern

When you have H1 vs H2, always add H3:

```json brenner-delta
{
  "operation": "ADD",
  "target_section": "hypothesis_slate",
  "payload": {
    "id": "H3",
    "statement": "Both H1 and H2 are wrong; the phenomenon is an artifact of measurement",
    "state": "proposed",
    "is_third_alternative": true,
    "confidence": 0.15
  },
  "rationale": "Third-alternative injection per Brenner: 'You've forgotten there's a third alternative. What's that? Both could be wrong.'"
}
```

### Why It Matters

- Prevents false dichotomy trap
- Forces consideration of completely different framings
- Often the most productive hypothesis

---

## Test Design

**Goal:** Create discriminative tests with potency controls.

### Test Template

```json brenner-delta
{
  "operation": "ADD",
  "target_section": "discriminative_tests",
  "payload": {
    "id": "T1",
    "name": "Gradient perturbation test",
    "discriminates": ["H1", "H2"],
    "predictions": {
      "H1": "Signal increases >2x",
      "H2": "Signal unchanged"
    },
    "potency_control": {
      "description": "Positive control: known gradient perturbation",
      "expected": "Signal increases 3x"
    },
    "discriminative_power": 0.85
  },
  "rationale": "High discriminative power between H1 and H2"
}
```

### Potency Control Requirements (TEST-003)

Every test needs:
1. **Chastity control** — Prove negative results are meaningful
2. **Impotence check** — Detect broken experiments

```markdown
If control fails → Test is uninformative (impotent)
If control passes + negative result → Meaningful exclusion (chaste)
```

---

## Artifact Compilation

**Goal:** Merge agent deltas into validated artifact.

```bash
# 1. Check session status
brenner session status --thread-id RS-YYYYMMDD-SLUG

# 2. Compile deltas
brenner session compile --thread-id RS-YYYYMMDD-SLUG

# 3. Lint result
brenner artifact lint artifact.md

# 4. Get improvement suggestions
brenner artifact nudge artifact.md

# 5. Fix issues, re-lint
brenner artifact lint artifact.md --json
```

### Common Lint Failures

| Rule | Fix |
|------|-----|
| HYP-002 | Add third alternative hypothesis |
| TEST-003 | Add potency control to test |
| CITE-001 | Use §n format for corpus references |
| STRUCT-001 | Add missing artifact sections |

---

## Tribunal Session

**Goal:** Multi-agent research with specialized roles.

### Spawn Tribunal

```bash
# Start session with all four roles
brenner session start \
  --project-key "$PWD" \
  --sender Coordinator \
  --to "DevilsAdvocate,ExperimentDesigner,BrennerChanneler,Synthesis" \
  --thread-id RS-$(date +%Y%m%d)-tribunal \
  --excerpt-file excerpt.md \
  --question "Research question" \
  --mode tribunal
```

### Role Responsibilities

| Role | Focus | Output |
|------|-------|--------|
| Devil's Advocate | Attack hypotheses | Critiques, alternatives |
| Experiment Designer | Design tests | Test specs, controls |
| Brenner Channeler | Apply operators | Citations, method checks |
| Synthesis | Integrate | Merged artifacts |

### Session Flow

```
1. Kickoff → All receive thread + excerpt
2. Initial → Each contributes from role
3. Cross-exam → DA attacks, ED tests, BC checks
4. Integration → SY compiles deltas
5. Iterate → Until convergence
```

---

## Evidence Pack

**Goal:** Attach supporting evidence to hypotheses and tests.

```bash
# Initialize evidence pack
brenner evidence init --thread-id RS-YYYYMMDD-SLUG

# Add evidence
brenner evidence add \
  --file results.csv \
  --description "Gradient measurements" \
  --supports H1 \
  --thread-id RS-YYYYMMDD-SLUG

# List evidence
brenner evidence list --thread-id RS-YYYYMMDD-SLUG

# Render evidence pack
brenner evidence render --thread-id RS-YYYYMMDD-SLUG > evidence.md
```

---

## Full Example Session

```bash
# 1. Bootstrap
brenner doctor --skip-ntm --skip-cass --skip-cm
brenner mail health

# 2. Mine corpus
brenner corpus search "cell fate determination"
# Found sections: 45, 78, 92, 161

# 3. Build excerpt
brenner excerpt build --sections 45,78,92,161 > excerpt.md

# 4. Start session
brenner session start \
  --project-key "$PWD" \
  --sender GreenCastle \
  --to BlueLake \
  --thread-id RS-20260119-cell-fate \
  --excerpt-file excerpt.md \
  --question "How do cells determine their developmental fate?"

# 5. Monitor
brenner session status --thread-id RS-20260119-cell-fate

# 6. Compile
brenner session compile --thread-id RS-20260119-cell-fate

# 7. Validate
brenner artifact lint artifact.md
brenner artifact nudge artifact.md
```
