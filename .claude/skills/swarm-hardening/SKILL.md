---
name: hardening-pipeline
model: opus
description: Run the full iterative hardening loop (multi-lens review, oracle consensus, fresh-eyes hardening, final correctness pass) on beads, plans, or code. Each round finds and fixes issues; loop converges when no CRITICAL/HIGH issues remain.
argument-hint: "<target: beads, plan file, or code path> [--max-rounds N] [--skip-oracle]"
---

# Hardening Pipeline

Orchestrate the full review-fix-validate-verify loop that takes artifacts from "draft" to "implementation-ready." Combines `/swarm-review` and `/swarm-oracle` into an iterative pipeline with convergence tracking.

## When to Use

- After creating beads from a plan (the full hardening treatment)
- Before starting implementation on critical features
- After architecture audits produce rewrites
- Any time "harden this" or "make this bulletproof" is requested

## Pipeline Stages

```
Draft Artifact
     |
     v
[Round 1] Multi-Lens Review (10 agents) --> Fix issues
     |
     v
[Round 2] Oracle Consensus (2x Pro) --> Fix corrections
     |
     v
[Round 3] Fresh-Eyes Hardening (8 agents) --> Fix + embed cross-cutting
     |
     v
[Round 4] Final Correctness Pass (10 agents) --> Verify all fixes
     |
     v
Hardened Artifact (ready for implementation)
```

Each round is optional and can be repeated. The pipeline exits when convergence criteria are met.

## Workflow

### Step 0: Baseline Snapshot

Before starting, capture the current state:

```bash
# For beads
br list --status open --json > {artifact_dir}/baseline-beads.json
# For plans
cp {plan_file} {artifact_dir}/baseline-plan.md
# For code
git stash create > {artifact_dir}/baseline-stash.txt || git rev-parse HEAD > {artifact_dir}/baseline-commit.txt
```

Create tracking file:

```bash
mkdir -p {artifact_dir}
echo "# Hardening Pipeline Log" > {artifact_dir}/hardening-log.md
echo "Target: {target}" >> {artifact_dir}/hardening-log.md
echo "Started: $(date -Iseconds)" >> {artifact_dir}/hardening-log.md
```

### Step 1: Multi-Lens Review

Run `/swarm-review` on the target. Use the full 10-lens set for first pass.

**Input:** Draft artifact
**Output:** `{artifact_dir}/round1-findings.json`

After agents complete:
1. Compile findings (deduplicated, sorted by severity)
2. Count: `CRITICAL: N, HIGH: N, MEDIUM: N, LOW: N`
3. Apply all CRITICAL and HIGH fixes
4. Log fixes to `hardening-log.md`

**Gate:** If zero CRITICAL/HIGH found, skip to Step 4 (final correctness).

### Step 2: Oracle Consensus

Run `/swarm-oracle` on the (now partially fixed) artifact.

**Focus the oracle on:**
- Decisions made during design (are they sound?)
- Fixes from Round 1 (did they introduce new issues?)
- Cross-cutting concerns (consistency, completeness)

**Input:** Artifact + Round 1 findings + applied fixes
**Output:** `{artifact_dir}/round2-oracle.md`

After oracles complete:
1. Extract corrections (unanimous and contested)
2. Apply unanimous corrections immediately
3. Present contested corrections for judgment (apply or reject with rationale)
4. Log all corrections and decisions to `hardening-log.md`

**Gate:** If oracle score is 9+ AND zero corrections, skip to Step 4.

### Step 3: Fresh-Eyes Hardening

Spawn 8 agents, each with a different hardening focus. These agents have NOT seen previous round findings — they review with fresh perspective.

| # | Focus | Instructions |
|---|-------|-------------|
| 1 | **Cross-cutting embedding** | Ensure cross-cutting requirements (logging, error handling, telemetry) are embedded in every bead/plan section that needs them, not just referenced from a central doc |
| 2 | **AC conversion** | Convert all acceptance criteria to Given/When/Then format; flag any that are untestable |
| 3 | **File path verification** | Verify every file path referenced actually exists in the codebase; fix incorrect paths |
| 4 | **Dependency validation** | Check all dependency chains for cycles, missing links, and incorrect ordering |
| 5 | **Scope splitting** | Identify beads/sections that are too large for atomic implementation; propose splits |
| 6 | **Terminology consistency** | Ensure consistent terminology throughout (no mixing "plate"/"device"/"sensor") |
| 7 | **Test coverage mapping** | Verify every AC has a corresponding test bead or test case; create missing test beads |
| 8 | **Integration seams** | Identify where separate beads/sections must integrate; verify interfaces match |

Agent prompt template:

```
You are a hardening agent with focus: **{FOCUS_NAME}**

## Your Task
{FOCUS_INSTRUCTIONS}

## Target
{ARTIFACT_SUMMARY}

## Rules
1. You have NOT seen previous review findings — review independently
2. For each issue: severity, location, issue, fix, evidence
3. Apply fixes directly where possible (for beads: use `br update`)
4. Report what you fixed and what needs manual attention
5. Do NOT re-review things outside your focus area
```

**Output:** `{artifact_dir}/round3-hardening.json`

After agents complete:
1. Compile changes made and issues flagged
2. Verify changes don't conflict with Round 1/2 fixes
3. Log to `hardening-log.md`

### Step 4: Final Correctness Pass

Spawn 10 agents for a final verification. Each agent verifies a slice of the artifact (e.g., one epic of beads, one section of a plan).

Agent prompt template:

```
You are a final correctness verifier. Your job is to verify, not find new issues.

## Your Slice
{SLICE_DESCRIPTION}

## Verify Each Item Against
1. All acceptance criteria are in Given/When/Then format
2. All file paths exist in codebase
3. All dependencies are correct and acyclic
4. No contradictions with other items
5. Cross-cutting requirements are embedded (not just referenced)
6. Scope is achievable in a single atomic commit

## Output
For each item, report: PASS or FAIL with reason.
Final count: X PASS, Y FAIL
```

**Output:** `{artifact_dir}/round4-verification.json`

**Convergence criterion:**
- 100% PASS rate: Pipeline complete
- Any FAIL: Fix and re-verify the failed items only (do not re-run full pipeline)

### Step 5: Summary Report

Write `{artifact_dir}/hardening-summary.md`:

```markdown
# Hardening Pipeline Summary

## Target
{what was hardened}

## Rounds Executed
| Round | Issues Found | Issues Fixed | Remaining |
|-------|-------------|-------------|-----------|
| 1. Multi-Lens Review | N | N | 0 |
| 2. Oracle Consensus | N corrections | N applied | 0 |
| 3. Fresh-Eyes Hardening | N | N | 0 |
| 4. Final Correctness | N fail | N fixed | 0 |

## Total Changes Made
- Beads modified: N
- Beads created: N
- Dependencies added: N
- ACs rewritten: N
- File paths corrected: N

## Final State
{artifact count} items, {pass rate}% verified, {oracle score}/10 oracle score
```

## Convergence Rules

The pipeline is designed to converge (each round finds fewer issues):

| Condition | Action |
|-----------|--------|
| Round 1 finds 0 CRITICAL/HIGH | Skip to Round 4 |
| Round 2 oracle score 9+ with 0 corrections | Skip to Round 4 |
| Round 4 is 100% PASS | Pipeline complete |
| Round 4 has failures after fix | Re-verify failed items only (max 2 retries) |
| 3+ full pipeline iterations with no convergence | Stop, escalate to user |

## Partial Runs

Skip stages with flags:

| Flag | Effect |
|------|--------|
| `--skip-oracle` | Skip Round 2 (faster, less validation) |
| `--skip-hardening` | Skip Round 3 (when cross-cutting is already embedded) |
| `--review-only` | Run Round 1 only, report findings without fixing |
| `--verify-only` | Run Round 4 only (after manual fixes) |
| `--max-rounds 2` | Cap total pipeline iterations |

## Architecture Audit Variant

When the target is existing code (not beads/plans), replace the standard lenses with architecture-focused agents:

| # | Agent Focus |
|---|-------------|
| 1 | Model layer quality (encapsulation, invariants, naming) |
| 2 | ViewModel layer quality (reactive patterns, dispose, commands) |
| 3 | Coupling analysis (circular deps, god classes, feature envy) |
| 4 | Error handling paths (exception types, recovery, logging) |
| 5 | Persistence patterns (UnitOfWork usage, lazy loading scope) |
| 6 | Business logic placement (in correct layer? duplicated?) |
| 7 | Test coverage (which code paths are untested?) |
| 8 | Thread safety (UI thread access, async patterns, locks) |
| 9 | Rewrite vs refactor decisions (for each class: keep/refactor/rewrite) |
| 10 | Bead gap analysis (what beads are missing to address findings?) |

Oracle validation for architecture audits should focus on rewrite scope (not too much, not too little) and two-track prioritization (data integrity first, architecture second).

## Example Invocations

```
/swarm-hardening .beads/                    # Full pipeline on all open beads
/swarm-hardening foundation/product/features/sensor-plate-implementation-plan.md
/swarm-hardening --skip-oracle bd-abc,bd-def,bd-ghi
/swarm-hardening --verify-only .beads/       # Just final correctness pass
/swarm-hardening --review-only src/motioncatalyst/ViewModel/Settings/  # Architecture audit mode
```
