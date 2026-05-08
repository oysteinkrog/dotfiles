# Advanced Features

## Prediction Lock System

Cryptographic pre-registration of predictions to prevent post-hoc rationalization.

### Workflow

```bash
# 1. Create prediction lock
brenner prediction lock create \
  --hypothesis H1 \
  --test T2 \
  --prediction "If H1 is true, we expect X > Y by at least 2σ"
# Returns: lock_id, sha256_hash, timestamp

# 2. After test execution, reveal and verify
brenner prediction lock reveal --lock-id LOCK-123

# 3. Record outcome
brenner prediction lock outcome \
  --lock-id LOCK-123 \
  --result "X > Y by 3.2σ" \
  --verdict CONFIRMED
```

### Properties

- **Immutable**: Once locked, prediction cannot be modified
- **Timestamped**: Proves prediction preceded observation
- **Hashable**: SHA-256 hash provides tamper evidence
- **Auditable**: All locks stored in git-versioned archive

---

## Hypothesis Arena

Competitive testing system that pits hypotheses against each other.

### Scoring Dimensions

1. **Boldness Score**: How much does this hypothesis risk?
2. **Discriminative Power**: How many tests uniquely distinguish it?
3. **Survival Score**: How many attacks has it survived?
4. **Parsimony Score**: How few assumptions does it require?

### Commands

```bash
# Enter hypotheses into arena
brenner arena enter --artifact artifact.md

# Run competition round
brenner arena round --artifact artifact.md

# Get leaderboard
brenner arena leaderboard --artifact artifact.md

# Eliminate hypothesis (with evidence)
brenner arena eliminate --hypothesis H2 --evidence E5
```

---

## Evidence Pack Management

Attach supporting evidence to hypotheses and tests.

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
