# Delta Format Specification

Agents emit changes to research artifacts via fenced JSON delta blocks.

## Block Structure

```markdown
```json brenner-delta
{
  "operation": "ADD",
  "target_section": "hypothesis_slate",
  "payload": {
    "id": "H3",
    "statement": "Both mechanisms are wrong; the phenomenon is an artifact",
    "state": "proposed",
    "confidence": 0.15
  },
  "rationale": "Applying third-alternative injection per Brenner operator #3"
}
```
```

## Operations

| Operation | Behavior | Requires target_id |
|-----------|----------|-------------------|
| `ADD` | Insert new item into target section | No |
| `EDIT` | Modify existing item | Yes |
| `KILL` | Mark item as killed/dismissed | Yes |

## Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `operation` | `ADD` \| `EDIT` \| `KILL` | Delta type |
| `target_section` | string | One of 7 artifact sections |
| `payload` | object | Section-specific data |
| `rationale` | string | Why this change was made |

## Optional Fields

| Field | Type | When Required |
|-------|------|---------------|
| `target_id` | string | Required for EDIT and KILL |

## Valid Target Sections

1. `research_thread`
2. `hypothesis_slate`
3. `predictions_table`
4. `discriminative_tests`
5. `assumption_ledger`
6. `anomaly_register`
7. `adversarial_critique`

## Examples

### ADD a Hypothesis

```json brenner-delta
{
  "operation": "ADD",
  "target_section": "hypothesis_slate",
  "payload": {
    "id": "H2",
    "statement": "The gradient is established by morphogen diffusion",
    "state": "proposed",
    "confidence": 0.6
  },
  "rationale": "Alternative to receptor-mediated model"
}
```

### EDIT a Hypothesis State

```json brenner-delta
{
  "operation": "EDIT",
  "target_section": "hypothesis_slate",
  "target_id": "H1",
  "payload": {
    "state": "under_attack",
    "attack_source": "Anomaly A3 undermines key assumption"
  },
  "rationale": "New evidence contradicts prediction P1.2"
}
```

### KILL a Hypothesis

```json brenner-delta
{
  "operation": "KILL",
  "target_section": "hypothesis_slate",
  "target_id": "H1",
  "payload": {
    "kill_rationale": "Test T2 definitively falsified prediction P1.1",
    "evidence_link": "E5"
  },
  "rationale": "Exclusion via decisive experiment"
}
```

## Hypothesis State Machine

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

## Merge Algorithm

The `artifact-merge.ts` module:

1. Parse all deltas from Agent Mail thread
2. Sort by timestamp (stable ordering)
3. Apply sequentially to base artifact
4. Validate result against linting rules
5. Return merged artifact or conflict report
