---
name: swarm-oracle-review
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
<!-- | "consult oracles" (quick question) | /consult-oracles | -->
<!-- | "validate design with pro oracles" | /swarm-oracle-review | -->
<!-- | "harden beads" | /swarm-oracle-review --target beads | -->
<!-- | "full feature pipeline" | /swarm-pipeline (includes oracle phases) | -->
<!-- | "review with 10 agents" | /swarm-agents type=review | -->

# Oracle Review Skill

> **Oracle and review policy (2026-10-28):** GPT-6 Astra runs every oracle session
> and every review lane. Each is one bounded Astra run at effort `medium`: one prompt
> of about 60k tokens with the diff and needed excerpts pasted in, run from an empty
> directory with the shell tools off (see `/consult-oracles`, Bounded Astra run). At
> most 4 Astra runs at once. Fable (fresh `Agent` subagent, `model: "fable"`) is the
> secondary oracle: add it for a security review or a contested call (Astra looks
> wrong, or two oracles disagree), and use it in place of Astra when Codex fails
> (auth error, rate limit, empty output). Opus is the last fallback, only when Astra
> and Fable both fail. Gemini 4 Argon is currently unavailable (AI Studio credit ran
> out 2026-10-21). Why: the OpenAI accounts ended last week at about 26% to 31% with
> reset credits unused, while four Claude accounts hit 100%. If any OpenAI account
> passes 70% of its week before its reset, go back to Fable first. Use `high` only for
> one high-stakes question, and say why. Lesson from 2026-10-22: high-effort Astra
> reviews on whole repos used up all three OpenAI accounts in about 90 minutes.

Two-part process: (1) oracle consensus validation with FOR/AGAINST stances,
then (2) iterative hardening loop until findings converge to near-zero.

## When to Use

- After design completion (validate UX + architecture)
- After implementation planning (validate feasibility + correctness)
- After bead creation (validate readiness + completeness)
- After architecture decisions (validate scope + approach)
- Any high-stakes decision needing external challenge

## When NOT to Use

- Quick questions or second opinions (use `/consult-oracles`)
- Code review (use `/swarm-review`)
- Simple validation that doesn't need adversarial challenge

## Part 1: Oracle Consensus Validation

### Setup

Run 2 concurrent oracle sessions:
- **Default tier:** two bounded Astra runs (`codex exec -m gpt-6-astra`, effort `medium`, `-o <scratchpad>/oracle-{for,against}.md`), one FOR stance, one AGAINST stance, made in a single message. See `/swarm-oracle` Step 2 for the exact command and prompts
- **Cross-provider check / Codex fallback:** two fresh Fable subagents (`Agent`, `model: "fable"`), one FOR, one AGAINST, spawned in a single message. Use them for security reviews or contested calls, and as the whole debate when Codex fails. Opus subagents only when Astra and Fable both fail
- **Alternate route:** PAL MCP `consensus` with 2x GPT-5.5-Pro (FOR + AGAINST) when the structured consensus flow is wanted
- **Cost rules:** give the oracles the change delta, not the whole artifact history, and validate each change once

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
Report only findings you can support with evidence. Zero findings in a category is a
valid answer; if you report zero, say why zero would be surprising.
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

**Step A: Review** (6 lenses via `/swarm-review`, each one bounded Astra run, at most 4 at once)
- Each run reviews with a different lens, given the artifact or diff pasted in
- Finds issues, inconsistencies, gaps
- Output: list of findings per lens
- Add a Fable run for the security lens only when the change is high-stakes

**Step B: Fix**
- Compile all findings
- Apply fixes (6-8 Sonnet agents for large artifacts; fix lanes stay on Claude)
- Each fix validated against the original plan/design

**Step C: Validate Fixes**
- Oracle round on the fixed artifact
- OR one bounded Astra review of just the changes
- Confirm fixes don't introduce new issues

### Convergence Signal

Track issues found per round, split by severity. Count only issues the reviewers
support with evidence, and never set a target count for a round.

| Signal | Action |
|--------|--------|
| Round finds CRITICAL or HIGH issues | Fix them, run another round |
| Round finds zero CRITICAL/HIGH, only MEDIUM/LOW | Fix what is worth fixing, then stop |
| Count of non-trivial issues rises round over round | Check whether fixes caused new problems; the artifact may need redesign |

Stop when a round finds zero CRITICAL/HIGH issues.

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
Phase 1: Oracle (2x Astra FOR/AGAINST; add 2x Fable if security or contested)
  -> Fix CRITICAL/HIGH findings
Phase 2: Lens Review (6 bounded Astra runs, multi-lens)
  -> Fix all findings
Phase 3: Oracle (2x Astra FOR/AGAINST) on fixes
  -> Verify fixes, find remaining issues
Phase 4: Agent Hardening (8 Sonnet, fresh eyes)
  -> Embed cross-cutting, convert ACs, split oversized
Phase 5: Final Correctness (4 Astra verifier runs, then 1 Astra oracle)
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
6. **Check the oracle route before launching.** For Astra, `codex` on PATH and logged in. Fable subagents need only the `Agent` tool. For the PAL route, PAL MCP running (agents silently fall back to self-analysis without it)
