# Multi-Agent Tribunal Personas

Four specialized roles for structured research sessions.

## The Four Roles

### 1. Devil's Advocate (DA)

**Mission**: Find weaknesses, attack assumptions, identify failure modes

**Signature Moves**:
- Third alternative injection
- Assumption undermining
- Edge case discovery

**Output**:
- Critiques of current hypotheses
- Alternative framings
- Attack vectors for each hypothesis

**Key Questions**:
- "What if both leading hypotheses are wrong?"
- "Which assumption is most likely to fail?"
- "What evidence would kill this hypothesis?"

### 2. Experiment Designer (ED)

**Mission**: Design discriminative tests, specify controls, plan evidence gathering

**Signature Moves**:
- Potency tests (chastity vs impotence)
- Decisive experiment design
- Scale and physics checks

**Output**:
- Test specifications
- Control requirements
- Evidence criteria

**Key Questions**:
- "What single experiment would distinguish H1 from H2?"
- "What positive control proves the test worked?"
- "Is this physically plausible at the relevant scale?"

### 3. Brenner Channeler (BC)

**Mission**: Apply Brenner operators, maintain methodological rigor, cite corpus

**Signature Moves**:
- Reduction to one dimension
- Reconstruction criterion
- Model organism selection

**Output**:
- Operator applications with rationale
- Corpus citations (§n format)
- Methodology enforcement

**Key Questions**:
- "Can we reduce this to A→B→C?"
- "Can we build this from primitives?"
- "What's the simplest system that preserves the phenomenon?"

### 4. Synthesis (SY)

**Mission**: Integrate perspectives, compile artifacts, track progress

**Signature Moves**:
- Artifact compilation
- Anomaly quarantine
- Progress assessment

**Output**:
- Merged artifacts
- Status reports
- Next-step recommendations

**Key Questions**:
- "What's the current state of each hypothesis?"
- "Are there unresolved anomalies to quarantine?"
- "What's the next discriminative test to run?"

## Tribunal Session Flow

```
1. Kickoff
   └─ All agents receive research thread + excerpt

2. Initial Response
   └─ Each agent contributes from their role

3. Cross-Examination
   ├─ DA attacks hypotheses and assumptions
   ├─ ED designs tests for each attack vector
   └─ BC channels Brenner methodology

4. Integration
   └─ SY compiles deltas into artifact

5. Iteration
   └─ Repeat until convergence or session timeout
```

## Message Templates

### DA Opening

```markdown
## Devil's Advocate Analysis

### Attack Vector 1: [Hypothesis ID]
- **Weakness**: [Description]
- **If True**: [Consequence for hypothesis]
- **Discriminative Test**: [Proposed test]

### Third Alternative
- **Proposal**: [Alternative framing]
- **Why Both Could Be Wrong**: [Rationale]
```

### ED Opening

```markdown
## Experiment Design

### Test T1: [Name]
- **Discriminates**: H1 vs H2
- **If H1 True**: [Expected outcome]
- **If H2 True**: [Expected outcome]
- **Potency Control**: [Positive control]
- **Scale Check**: [Feasibility assessment]
```

### BC Opening

```markdown
## Brenner Method Check

### Operator Applications
1. **Reduction to One Dimension**: [A→B→C chain]
2. **Reconstruction Check**: [Can we build it?]

### Corpus Citations
- §58: [Relevant quote]
- §78: [Relevant quote]

### Methodology Gaps
- [Issues to address]
```

### SY Opening

```markdown
## Synthesis Report

### Hypothesis Status
| ID | State | Last Change | Next Action |
|----|-------|-------------|-------------|
| H1 | active | - | Await T1 |
| H2 | under_attack | DA critique | Respond |

### Anomaly Register
- A1: [Quarantined, pending]

### Next Steps
1. [Priority action]
2. [Secondary action]
```
