---
name: bead-quality
model: opus
description: Run the full bead quality pipeline — review, oracle validation, hardening, and final verification. Iteratively improves beads until they are implementation-ready with zero issues. Use after creating beads or when beads need quality improvement.
triggers:
  - "review beads"
  - "harden beads"
  - "bead quality"
  - "quality pipeline"
  - "validate beads"
argument-hint: "[<bead-ids>|--all|--epic <id>] [--skip-oracle] [--rounds <N>]"
---

# Bead Quality Pipeline Skill

Run the full review -> oracle -> harden -> verify cycle on beads until they are implementation-ready.

## When to Use

- After `/swarm-beads-create` creates initial beads
- When beads have been modified and need re-validation
- Before starting a swarm on a set of beads
- When oracle or review feedback needs to be applied

## Arguments

- Bead IDs: specific beads to review (e.g., `bd-abc bd-def`)
- `--all`: review all open beads
- `--epic <id>`: review all beads in an epic
- `--skip-oracle`: skip oracle consensus step (faster, less thorough)
- `--rounds <N>`: max hardening rounds (default: 3, converges earlier if clean)

## Pipeline Overview

```
Round 1: Multi-Lens Review (find issues) --> Fix
Round 2: Oracle Validation (challenge decisions) --> Fix
Round 3: Fresh-Eyes Hardening (embed cross-cut, convert ACs) --> Fix
Round 4: Final Correctness Pass (verify everything)
```

Each round finds fewer issues. Stop when a round finds zero issues (convergence).

---

## Round 1: Multi-Lens Review

Review each bead through 10 independent lenses. Each lens checks different failure modes.

### Review Checklist (10 Lenses)

| # | Lens | What to Check |
|---|------|---------------|
| 1 | **Correctness** | Do ACs match the plan? Are file paths real? Do enums/types exist? |
| 2 | **Self-Containment** | Can an agent implement this with ONLY the bead description + source code? |
| 3 | **Dependencies** | Are deps correct? Missing deps? Would executing out-of-order break anything? |
| 4 | **Test Coverage** | Does every AC have a corresponding test requirement? Are test beads linked? |
| 5 | **Spec Contradictions** | Do any beads contradict each other? Do ACs conflict with the plan? |
| 6 | **Cross-Cutting** | Are l10n, a11y, error handling, perf requirements embedded (not deferred)? |
| 7 | **Sizing** | Is the bead 1-3 files? Could it be split? Is it too granular? |
| 8 | **AC Format** | Are ALL acceptance criteria in Given/When/Then? No prose ACs? |
| 9 | **Edge Cases** | Are error states, empty states, boundary conditions covered? |
| 10 | **Implementability** | Are there enough implementation hints? Are API surfaces specified? |

### Running the Review

For each bead under review:

```bash
# Read the bead
br show <id>

# Verify file paths exist
# For each file in the bead's Files section:
test -f <path> || echo "MISSING: <path>"

# Check deps exist and are open
br dep tree <id>

# Cross-reference with plan
# Read the plan section referenced in bead's Context
```

### Issue Classification

| Severity | Meaning | Action |
|----------|---------|--------|
| **Blocking** | Bead cannot be implemented as-is | Must fix before proceeding |
| **Major** | Bead can be implemented but result will be wrong | Fix in this round |
| **Minor** | Cosmetic, clarification, nice-to-have | Fix if time permits |

Track issues:

```bash
br comments add <id> "[Review] Blocking: <description of issue>"
```

### Fixing Issues

After all lenses complete, compile issues and fix:

```bash
# Update bead description with fixes
br update <id> -d "$(cat <<'EOF'
<corrected full description>
EOF
)"

# Add missing deps
br dep add <child> <parent>

# Split oversized beads
br create "Split: <specific part>" -t task -p <priority> --parent <epic>
br dep add <new-id> <original-deps>
```

---

## Round 2: Oracle Consensus Validation

Use 2 oracle sessions to challenge bead decisions from opposing stances.

### Oracle Prompt Template

```
Evaluate these beads for implementation readiness.

BEADS:
<paste bead list with descriptions>

PLAN CONTEXT:
<paste relevant plan sections>

Evaluate on:
1. Are acceptance criteria specific enough to write automated tests?
2. Are there spec contradictions between beads?
3. Are cross-cutting requirements (l10n, a11y, error handling) embedded or deferred?
4. Are dependencies complete and correctly ordered?
5. Would an agent with NO context beyond the bead description produce correct code?

Rate overall readiness 1-10. List SPECIFIC blocking issues with bead IDs.
```

### Running Oracles

Use `/swarm-oracle-standalone` or the PAL MCP consensus tool:

```
mcp__pal__consensus(
  models: [
    {model: "gpt-5.4-pro", stance: "for", stance_prompt: "Argue beads ARE ready"},
    {model: "gpt-5.4-pro", stance: "against", stance_prompt: "Argue beads are NOT ready"}
  ],
  step: "<oracle prompt with beads>"
)
```

### Processing Oracle Findings

For each oracle finding:
1. Determine if it's valid (sometimes oracles flag non-issues)
2. Cross-reference against plan and code
3. If valid: fix the bead
4. If invalid: document why it was rejected

```bash
br comments add <id> "[Oracle] Finding: <issue>. Resolution: <fix or rejection rationale>"
```

---

## Round 3: Fresh-Eyes Hardening

Apply systematic transformations to ALL beads, regardless of review status.

### 3a: Given/When/Then Conversion

Find and convert any remaining prose ACs:

| Prose AC | Converted GWT |
|----------|---------------|
| "User can see X" | Given <setup>, When <navigation>, Then X is visible with <specific values> |
| "Error shown for Y" | Given <invalid state>, When <trigger>, Then error message "<exact text>" appears AND action is blocked |
| "Supports Z" | Given <Z precondition>, When <operation>, Then <Z-specific outcome with measurable assertion> |
| "Performance is acceptable" | Given <dataset size>, When <operation>, Then completes in <N>ms (measured via <method>) |

**Rules:**
- Given = specific values, not "some data" or "a user"
- When = single atomic action
- Then = machine-verifiable assertion (exact text, count, state, timing)
- Negative cases get their own GWT block

### 3b: Cross-Cutting Embedding

For EVERY bead, verify cross-cutting requirements are embedded, not deferred:

```markdown
## Cross-Cutting
- Localization: <specific resx keys and binding patterns, or "N/A — no user-facing text">
- Error handling: <specific exceptions, catch points, user messages, log calls>
- Accessibility: <specific AutomationId, keyboard nav, screen reader text>
- Performance: <specific constraint with measurement method, or "N/A">
- Security: <specific validation, sanitization, or "N/A">
```

If a bead says "see cross-cutting bead" or "handled elsewhere" — that is a FAILURE. Embed the specific requirements inline.

### 3c: Resx Key Specification

Any bead that adds/changes user-facing text MUST specify:

```markdown
## Localization Keys
| Key | English Value | Context |
|-----|---------------|---------|
| `Settings_Plate_Status_Online` | "Online" | Device status indicator |
| `Settings_Plate_Error_TooMany` | "Maximum {0} plates allowed" | Validation error, {0}=max count |
```

### 3d: Oversized Bead Splitting

Beads touching >3 files → split:

```bash
# Original: bd-xxx (touches 5 files)
# Split into:
br create "Part 1: Model changes" ... --parent <epic>
br create "Part 2: VM changes" ... --parent <epic>
br dep add <part2> <part1>
# Update original to reference splits, or close it
br close <original> --reason "Split into bd-yyy, bd-zzz"
```

---

## Round 4: Final Correctness Pass

Verify every bead one last time:

```bash
# Lint all beads
br lint

# Check for cycles
br dep cycles

# Verify ready beads are actually implementable
br ready
```

### Final Verification Checklist

For EACH bead:
- [ ] All file paths exist in the repo
- [ ] All referenced types/enums/classes exist in source code
- [ ] All ACs are in Given/When/Then format (zero prose)
- [ ] Cross-cutting section has specific values (not "TBD" or "see other bead")
- [ ] Dependencies are correct (no missing, no cycles)
- [ ] Test requirements are specific (file path, test count, what to assert)
- [ ] Bead touches <=3 files
- [ ] Description is self-contained (no external knowledge required)

### Counting Issues per Round

Track convergence:

```
Round 1 (Review):    16 issues found, 16 fixed
Round 2 (Oracle):     5 issues found, 5 fixed
Round 3 (Harden):     8 transformations applied
Round 4 (Verify):     0 issues → CONVERGED
```

If Round 4 finds issues, loop back to Round 1 with only the affected beads.

---

## Output Report

```markdown
## Bead Quality Report

### Pipeline Summary
| Round | Issues Found | Issues Fixed | Status |
|-------|-------------|-------------|--------|
| 1. Multi-Lens Review | N | N | Done |
| 2. Oracle Validation | N | N | Done |
| 3. Fresh-Eyes Hardening | N transformations | N applied | Done |
| 4. Final Correctness | 0 | - | CONVERGED |

### Bead Status
| Bead | Title | Status | Issues Fixed |
|------|-------|--------|-------------|
| bd-xxx | ... | Ready | 3 |
| bd-yyy | ... | Ready | 1 |

### Quality Metrics
- ACs in GWT format: 100% (N/N)
- Cross-cutting embedded: 100% (N/N)
- Self-containment: 100% (N/N)
- File count <=3: 100% (N/N)
- Dependency cycles: 0
- Oracle score: N/10

### Beads Ready for Implementation
<list of br ready output>
```

## Multi-Agent Execution

For large bead sets (>20), parallelize the review:

| Round | Agent Count | Strategy |
|-------|------------|----------|
| 1. Review | 10 | One agent per lens across all beads |
| 2. Oracle | 2 | FOR + AGAINST on full bead set |
| 3. Harden | 6-8 | One agent per epic |
| 4. Verify | 10 | One agent per epic + 2 cross-epic |

Use `ntm spawn` to orchestrate. Each agent commits fixes atomically after each bead.
