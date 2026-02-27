---
name: prd-start
description: "Generate a comprehensive plan/PRD for AI agent execution. Creates agent-operable plans with architecture, security, testing, and user stories that convert to beads. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
---

# Plan/PRD Generator

Create detailed, agent-operable plans optimized for AI agent execution. The goal is to "spend planning tokens to save implementation tokens."

---

## The Job

1. Receive a feature description from the user
2. Ask 3-5 essential clarifying questions (with lettered options) - one set at a time
3. **Always ask about quality gates** (what commands must pass)
4. After each answer, ask follow-up questions if needed (adaptive exploration)
5. Generate a comprehensive plan when you have enough context
6. Output the plan wrapped in `[PRD]...[/PRD]` markers
7. **Offer critique cycles** — ask if user wants refinement passes before finalizing

**Important:** Do NOT start implementing. Just create the plan.

---

## Step 1: Clarifying Questions (Iterative)

Ask questions one set at a time. Each answer should inform your next questions. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?
- **Integration:** How does it fit with existing features?
- **Quality Gates:** What commands must pass for each story? (REQUIRED)
- **Security/Privacy:** What's the threat model?
- **Performance:** Any latency/throughput/cost targets?

### Format Questions Like This:

```
1. What is the primary goal of this feature?
   A. Improve user onboarding experience
   B. Increase user retention
   C. Reduce support burden
   D. Other: [please specify]
```

This lets users respond with "1A, 2C" for quick iteration. Typically 2-4 rounds.

---

## Step 2: Plan Structure

Generate the plan with ALL of these sections. Great plans include all of them; good plans skip some.

### 1. Overview
Brief description of the feature and the problem it solves.

### 2. Goals
Specific, measurable, user-facing outcomes (bullet list).

### 3. Non-Goals (Out of Scope)
What this feature will NOT include. Critical for preventing scope creep and bikeshedding.

### 4. Quality Gates
**CRITICAL:** Commands that must pass for every user story.

```markdown
## Quality Gates
These commands must pass for every user story:
- `npm run build` - Build succeeds
- `npm test` - All tests pass
- `npm run lint` - Linting passes
```

### 5. Architecture
- Components, boundaries, invariants, data flow
- Data model / schemas (if applicable)
- Key technical decisions with rationale
- Failure modes and how they're handled

### 6. Security & Privacy Model
- Threat model (realistic attacker model + mitigations)
- Secrets handling (where they live, how injected, what never enters logs)
- Authentication/authorization approach

### 7. Performance Targets
- Concrete numbers (latency, throughput, memory, cost budgets)
- Instrumentation/measurement plan

### 8. User Stories
Each story needs:
- **Title:** Short descriptive name
- **Description:** "As a [user], I want [feature] so that [benefit]"
- **Acceptance Criteria:** Verifiable checklist of what "done" means

**Format:**
```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
```

**Sizing rule:** Each story must be completable in ONE agent session (~one context window). If you can't describe the change in 2-3 sentences, it's too big — split it.

**Ordering:** Schema/data first, then backend, then frontend, then integration/polish.

**Criteria quality:**
- "Works correctly" is BAD
- "Button shows confirmation dialog before deleting" is GOOD
- Do NOT include quality gate commands in individual stories

### 9. Story Dependencies
Explicit dependency graph showing which stories block which.

### 10. Testing Plan
- Unit tests: what to test, fixtures, mocking strategy
- Integration tests: component interactions
- E2E tests: critical user flows
- Logging requirements for failure reproduction

### 11. Operational Plan
- Deployment strategy (feature flags, migrations, rollback)
- Observability (structured logs, metrics, alerts)
- Error handling philosophy ("no silent failures")

### 12. Risk Register
Top risks + mitigations. What must be validated early (spikes/PoCs).

### 13. Success Metrics
How will success be measured? Concrete numbers.

### 14. Open Questions
Remaining questions or areas needing clarification.

---

## Writing for AI Agents

The plan will be executed by AI coding agents. Therefore:

- Be explicit and unambiguous — no vague advice
- User stories should be small (completable in one session)
- Acceptance criteria must be machine-verifiable where possible
- Include specific file paths if you know them
- Reference existing code patterns in the project
- Beads created from this plan should be **self-contained** — agents should not need to re-read the plan constantly

---

## Output Format

**CRITICAL:** Wrap the final plan in markers:

```
[PRD]
# PRD: Feature Name

## Overview
...
[/PRD]
```

---

## Post-Generation: Critique Cycles

After generating the plan, offer the user refinement:

> "Plan generated. Want me to run critique passes to improve it? Options:
> A. Single critique pass (I review and propose diff-based improvements)
> B. Oracle review (spawn 3 expert agents: PM, engineer, security)
> C. Skip — plan is good enough, proceed to beads conversion
> D. Other"

### Critique Pass Format
For each proposed change:
1. Detailed analysis and rationale
2. Git-diff style changes relative to the current plan

### Stop Condition
Stop critique cycles when improvements become incremental (only minor wording tweaks, no meaningful architectural/test/ops changes).

---

## Checklist

Before outputting the plan:

- [ ] Asked clarifying questions with lettered options
- [ ] Asked about quality gates (REQUIRED)
- [ ] Goals AND non-goals defined
- [ ] Architecture section with components, boundaries, data flow
- [ ] Security & privacy model included
- [ ] Performance targets with concrete numbers
- [ ] User stories are small and independently completable
- [ ] Story dependencies explicit
- [ ] Testing plan (unit + integration + e2e)
- [ ] Operational plan (deploy, observability, rollback)
- [ ] Risk register with mitigations
- [ ] Plan is wrapped in `[PRD]...[/PRD]` markers
- [ ] Offered critique cycles
