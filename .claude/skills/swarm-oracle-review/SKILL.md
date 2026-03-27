---
name: oracle-review
model: opus
description: Run iterative oracle + agent hardening loop on any artifact (designs, plans, beads, architecture) until findings converge to near-zero. Combines /swarm-oracle with /swarm-review in alternating rounds. Use for the full hardening cycle, not just a single oracle pass. For oracle-only, use /swarm-oracle. For bead-only hardening, use /swarm-beads-quality.
triggers:
  - "oracle review"
  - "hardening loop"
  - "iterate until converged"
  - "full review cycle"
argument-hint: "<target: design|plan|beads|architecture> [--rounds N]"
---

<!-- Decision table -->
<!-- | User says | Use | -->
<!-- |-----------|-----| -->
<!-- | "consult oracles" (quick question) | /swarm-oracle-standalone | -->
<!-- | "validate design with pro oracles" | /swarm-oracle-review | -->
<!-- | "harden beads" | /swarm-oracle-review --target beads | -->
<!-- | "full feature pipeline" | /swarm-pipeline (includes oracle phases) | -->
<!-- | "review with 10 agents" | /swarm-agents type=review | -->

# Oracle Review Skill

Two-part process: (1) oracle consensus validation with FOR/AGAINST stances,
then (2) iterative hardening loop until findings converge to near-zero.

## When to Use

- After design completion (validate UX + architecture)
- After implementation planning (validate feasibility + correctness)
- After bead creation (validate readiness + completeness)
- After architecture decisions (validate scope + approach)
- Any high-stakes decision needing external challenge

## When NOT to Use

- Quick questions or second opinions (use `/swarm-oracle-standalone`)
- Code review (use `/swarm-agents type=review`)
- Simple validation that doesn't need adversarial challenge

## Part 1: Oracle Consensus Validation

### Setup

Run 2 concurrent oracle sessions using PAL MCP `consensus` tool:
- **Model 1:** GPT-5.4-Pro with FOR stance
- **Model 2:** GPT-5.4-Pro with AGAINST stance

### Oracle Prompt Template

```
Evaluate the following [ARTIFACT_TYPE] for [FEATURE]:

[ARTIFACT CONTENT or reference to document]

Score 1-10 on:
1. Correctness — Are the technical decisions sound?
2. Completeness — Are there gaps or missing considerations?
3. Consistency — Do parts contradict each other?
4. Feasibility — Can this be implemented as specified?
5. Quality — Does this meet production standards?

For each issue found, provide:
- Severity: CRITICAL / HIGH / MEDIUM / LOW
- Location: Which section/bead/decision
- Problem: What is wrong
- Recommendation: Specific fix

Do NOT say "looks good" without specific evidence.
Produce at least 3 actionable findings per category.
```

### Interpreting Results

| Score | Meaning | Action |
|-------|---------|--------|
| 9-10 | Excellent | Proceed, apply minor findings |
| 7-8 | Good with issues | Fix all CRITICAL/HIGH, proceed |
| 5-6 | Significant problems | Fix all issues, re-validate |
| <5 | Fundamental issues | Redesign, then re-validate |

Both oracles typically converge on similar scores. If they diverge by >2 points,
investigate the disagreement — it usually reveals a genuine ambiguity.

### Apply Corrections

After each oracle round:
1. Compile all findings from both stances
2. Deduplicate (FOR and AGAINST often find same issues from different angles)
3. Prioritize: CRITICAL first, then HIGH
4. Apply fixes to the artifact
5. Document what changed and why

## Part 2: Iterative Hardening Loop

After oracle validation, run hardening rounds until convergence.

### Round Structure

Each round has 3 steps:

**Step A: Review** (10 Opus agents via `/swarm-agents type=review`)
- Each agent reviews with a different lens
- Finds issues, inconsistencies, gaps
- Output: list of findings per agent

**Step B: Fix**
- Compile all findings
- Apply fixes (6-8 Opus agents for large artifacts)
- Each fix validated against the original plan/design

**Step C: Validate Fixes**
- Oracle round on the fixed artifact
- OR agent review of just the changes
- Confirm fixes don't introduce new issues

### Convergence Signal

Track issues found per round:

| Round | Issues Found | Action |
|-------|-------------|--------|
| 1 | 15-20 | Expected — many first-pass issues |
| 2 | 8-12 | Good — deeper issues surfacing |
| 3 | 3-5 | Converging — mostly edge cases |
| 4 | 0-2 | Done — ready to ship |

Stop when a round finds <= 2 non-trivial issues. Typical: 3-4 rounds.

### Hardening Agent Prompt Template

```
You are hardening [ARTIFACT] for [FEATURE].
Round {N} of iterative review.

Previous rounds found and fixed:
[SUMMARY OF PRIOR FINDINGS]

Your lens: [SPECIFIC_LENS]

Review the artifact and:
1. Check that prior fixes are correctly applied
2. Find NEW issues not caught in earlier rounds
3. Verify cross-cutting concerns are embedded (not just referenced)
4. Check acceptance criteria are Given/When/Then format
5. Verify file paths exist and are correct
6. Ensure no bead is >3 files (split if needed)

For beads specifically:
- Each bead must be self-contained (implementable without reading other beads)
- Dependencies must form a DAG (no cycles)
- Test beads must reference specific test methods/classes
- Acceptance criteria must be machine-verifiable
```

## Target-Specific Guidance

### Design Validation
Oracle focus: UX soundness, information architecture, interaction model consistency,
accessibility, progressive disclosure balance, terminology.

### Plan Validation
Oracle focus: Feasibility, file-level correctness, dependency ordering, risk coverage,
test strategy completeness, migration safety.

### Bead Validation
Oracle focus: Self-containment, AC specificity, dependency DAG, file path accuracy,
test coverage, priority ordering, cross-cutting embedding.

### Architecture Validation
Oracle focus: Rewrite scope (not too much/little), backward compatibility, migration path,
performance impact, data integrity, rollback strategy.

## Full Hardening Pipeline Example

```
Phase 1: Oracle (2x GPT-5.4-Pro)
  -> Fix CRITICAL/HIGH findings
Phase 2: Agent Review (10 Opus, multi-lens)
  -> Fix all findings
Phase 3: Oracle (2x GPT-5.4-Pro) on fixes
  -> Verify fixes, find remaining issues
Phase 4: Agent Hardening (8 Opus, fresh eyes)
  -> Embed cross-cutting, convert ACs, split oversized
Phase 5: Final Correctness (10 Opus)
  -> Verify everything, fix last issues
  -> If <= 2 issues: DONE
  -> If > 2 issues: repeat from Phase 3
```

## Key Rules

1. **Always run both FOR and AGAINST** — single-stance misses adversarial findings
2. **Fix before re-validating** — never run a new round on unfixed artifacts
3. **Track convergence** — if issues aren't decreasing, the artifact needs redesign, not more rounds
4. **Validate fixes against plan** — hardening must not drift from the original design intent
5. **Oracle before agents, agents before oracle** — alternate perspectives for best coverage
6. **Verify PAL MCP is running** before launching oracle sessions (agents silently fall back to self-analysis without it)
