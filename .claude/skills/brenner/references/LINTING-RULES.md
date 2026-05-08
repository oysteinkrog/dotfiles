# Artifact Linting Rules (50+ Categories)

The artifact linting system enforces Brenner-style rigor.

## Commands

```bash
brenner artifact lint artifact.md                    # Full lint
brenner artifact lint artifact.md --categories HYP,TEST  # Specific categories
brenner artifact lint artifact.md --json             # JSON output for CI
brenner artifact nudge artifact.md                   # Get improvement suggestions
```

## Rule Categories

### Structural Integrity (STRUCT-*)

| Rule | Description |
|------|-------------|
| STRUCT-001 | All 7 required sections must be present |
| STRUCT-002 | Section order must match canonical schema |
| STRUCT-003 | No orphaned IDs (references must resolve) |
| STRUCT-004 | No duplicate IDs within sections |
| STRUCT-005 | Thread ID format must match convention |

### Hypothesis Hygiene (HYP-*)

| Rule | Description |
|------|-------------|
| HYP-001 | Minimum 2 hypotheses, maximum 5 |
| HYP-002 | Third alternative ("both wrong") must be present |
| HYP-003 | Each hypothesis must have unique ID |
| HYP-004 | State transitions must follow valid state machine |
| HYP-005 | Killed hypotheses must have kill rationale |
| HYP-006 | No hypothesis validated without discriminative test pass |
| HYP-007 | Hypotheses must be mutually exclusive or marked overlapping |

### Test Design (TEST-*)

| Rule | Description |
|------|-------------|
| TEST-001 | Each test must reference at least 2 hypotheses |
| TEST-002 | Tests must specify expected outcomes per hypothesis |
| TEST-003 | Potency controls required (chastity vs impotence) |
| TEST-004 | Tests must be ranked by discriminative power |
| TEST-005 | No test can be "passed" without linked evidence |

### Assumption Tracking (ASMP-*)

| Rule | Description |
|------|-------------|
| ASMP-001 | Each assumption must have scale/physics check status |
| ASMP-002 | Load-bearing assumptions must link to dependent hypotheses |
| ASMP-003 | Undermined assumptions must trigger hypothesis state change |
| ASMP-004 | No circular assumption dependencies |

### Citation Hygiene (CITE-*)

| Rule | Description |
|------|-------------|
| CITE-001 | All corpus references must use §n anchor format |
| CITE-002 | Section numbers must be valid (1-236) |
| CITE-003 | Quote attributions must match source sections |
| CITE-004 | No unsourced claims in hypothesis rationales |

### Anomaly Handling (ANOM-*)

| Rule | Description |
|------|-------------|
| ANOM-001 | Anomalies must be explicitly quarantined |
| ANOM-002 | Each anomaly must have hypothesis impact assessment |
| ANOM-003 | Dismissed anomalies require dismissal rationale |
| ANOM-004 | Anomaly count warnings at thresholds (>3, >5, >10) |

### Adversarial Critique (CRIT-*)

| Rule | Description |
|------|-------------|
| CRIT-001 | At least one framing-level critique required |
| CRIT-002 | Critiques must address "what would make this whole approach wrong" |
| CRIT-003 | Rebuttals must engage with critique substance |
| CRIT-004 | Unaddressed critiques must be explicitly acknowledged |

### Delta Format (DELTA-*)

| Rule | Description |
|------|-------------|
| DELTA-001 | Operation must be ADD, EDIT, or KILL |
| DELTA-002 | Target section must be valid section name |
| DELTA-003 | EDIT/KILL must specify target_id |
| DELTA-004 | ADD must not specify target_id |
| DELTA-005 | Rationale required for all operations |
| DELTA-006 | Payload must match target section schema |

### Meta Rules (META-*)

| Rule | Description |
|------|-------------|
| META-001 | Artifact must have valid thread_id |
| META-002 | Last-modified timestamp required |
| META-003 | Contributing agents must be listed |
| META-004 | Version must be semver format |
