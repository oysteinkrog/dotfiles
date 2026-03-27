---
name: multi-lens-review
model: opus
description: Run 10 parallel review agents, each with a different quality lens (correctness, safety, perf, a11y, etc.), against plans, beads, code, or architecture decisions. Use when a thorough multi-perspective review is needed before shipping.
argument-hint: "<target: plan file, bead list, or code path> [--lenses L1,L2,...] [--team-size N]"
---

# Multi-Lens Review

Spawn N parallel agents (default 10), each assigned a distinct review lens, to independently review a target artifact. Compile findings into a single issues list with severity and actionable fixes.

## When to Use

- Before finalizing implementation plans
- After creating or rewriting beads
- Before major architecture decisions ship
- After code changes that touch cross-cutting concerns
- Any time "review this thoroughly" is requested

## Review Lenses

Default set of 10 lenses. Override with `--lenses` to select a subset or customize.

| # | Lens | Focus | Key Questions |
|---|------|-------|---------------|
| 1 | **Correctness** | Logic, specs, ACs | Does implementation match spec? Are ACs testable and complete? |
| 2 | **Safety** | Data integrity, error handling | Can data be corrupted? Are failure modes handled? Race conditions? |
| 3 | **Performance** | Hot paths, allocations, O(n) | Any unnecessary allocations? O(n^2) where O(n) suffices? UI thread blocking? |
| 4 | **Accessibility** | Screen readers, keyboard nav, contrast | Can every action be done by keyboard? Are ARIA labels present? |
| 5 | **Localization** | Strings, RTL, formatting | Are all user-visible strings in resx? Any hardcoded formats (dates, numbers)? |
| 6 | **Testability** | Coverage, test design, mocking | Are ACs expressed as Given/When/Then? Can this be tested without hardware? |
| 7 | **Dependencies** | Coupling, circular refs, ordering | Are dependency chains correct? Any cycles? Missing blocked-by links? |
| 8 | **UX Consistency** | Patterns, terminology, flow | Does this match existing UX patterns? Consistent terminology? Progressive disclosure? |
| 9 | **Security** | Input validation, secrets, permissions | Any injection vectors? Secrets in logs? Proper authz checks? |
| 10 | **Feasibility** | Scope, risk, unknowns | Is this achievable in one bead? Are there hidden unknowns? What could go wrong? |

### Alternate Lens Sets

For **general review** (plans, docs, decisions), replace lenses 3-5 with:

| # | Lens | Focus |
|---|------|-------|
| 3 | **Completeness** | Missing cases, edge conditions, gaps in coverage |
| 4 | **Conflict** | Contradictions between sections, specs, or existing code |
| 5 | **Clarity** | Ambiguous language, vague ACs, undefined terms |

## Workflow

### Step 1: Identify Target

Determine what is being reviewed:
- **Plan file(s):** Read the plan document(s)
- **Beads:** `br list --status open --json` or specific bead IDs
- **Code:** File paths or git diff range
- **Architecture decision:** PDR YAML or design doc

### Step 2: Prepare Shared Context

Create a context summary that all agents receive:

```
REVIEW TARGET: <what is being reviewed>
TARGET TYPE: <plan | beads | code | architecture>
CONTEXT FILES: <list of files agents should read>
CONSTRAINTS: <any known constraints or requirements>
```

### Step 3: Spawn Review Agents

For each lens, spawn an agent with this prompt template:

```
You are a review agent with the **{LENS_NAME}** lens.

## Your Review Focus
{LENS_DESCRIPTION}

## Key Questions to Answer
{LENS_QUESTIONS}

## Target
{SHARED_CONTEXT}

## Instructions
1. Read all target files and context
2. Review ONLY through your assigned lens — do not duplicate other lenses
3. For each issue found, report:
   - **Severity:** CRITICAL | HIGH | MEDIUM | LOW
   - **Location:** File path + line/section or bead ID
   - **Issue:** What is wrong
   - **Fix:** Specific actionable fix (not just "consider doing X")
   - **Evidence:** Quote or reference supporting the finding
4. If you find ZERO issues through your lens, state that explicitly with reasoning
5. Do NOT pad findings — false positives waste time

## Output Format
Return a JSON array:
[
  {
    "lens": "{LENS_NAME}",
    "severity": "HIGH",
    "location": "path/to/file:42 or bead bd-xyz",
    "issue": "Description of the problem",
    "fix": "Specific fix to apply",
    "evidence": "Supporting quote or reference"
  }
]
```

Use `ntm spawn --cc=N` or Claude Code subagents depending on orchestration context.

### Step 4: Compile Findings

After all agents complete:

1. **Collect** all issue arrays into one list
2. **Deduplicate** — merge issues found by multiple lenses (note: multi-lens agreement raises confidence)
3. **Sort** by severity (CRITICAL first)
4. **Cross-validate** — flag any issue where two lenses contradict each other
5. **Write** compiled findings to `{artifact_dir}/review-findings.json` and a human-readable `review-findings.md`

### Step 5: Apply Fixes

For each CRITICAL and HIGH issue:
1. Apply the suggested fix
2. If fix conflicts with another finding, flag for manual resolution
3. Track which findings were addressed

For MEDIUM and LOW: present to user for triage.

### Step 6: Convergence Check

Review is complete when:
- All CRITICAL issues are resolved
- All HIGH issues are resolved or explicitly deferred with rationale
- No two lenses have unresolved contradictions
- Fixes have not introduced new CRITICAL/HIGH issues (spot-check)

If fixes are extensive, consider running a second pass (reduced team: 4-6 agents, focused on lenses that found the most issues).

## Team Size Guidance

| Target Size | Recommended Team | Rationale |
|-------------|-----------------|-----------|
| 1-5 beads or small plan | 6 agents | Full coverage overkill for small targets |
| 6-20 beads or medium plan | 10 agents (default) | Standard coverage |
| 20+ beads or large plan | 10 + second pass | First pass finds bulk, second pass catches interactions |
| Code review (<500 LOC) | 6 agents | Focus on correctness, safety, perf, tests |
| Code review (>500 LOC) | 10 agents | Full lens set |

## Example Invocations

```
/swarm-review foundation/product/features/sensor-plate-implementation-plan.md
/swarm-review --lenses correctness,safety,deps bd-abc,bd-def,bd-ghi
/swarm-review --team-size 6 src/motioncatalyst/ViewModel/Settings/
```
