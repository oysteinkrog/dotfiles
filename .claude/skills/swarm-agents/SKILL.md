---
name: swarm-agents
model: opus
description: Spin up a team of parallel Opus agents to research, design, review, plan, or create beads. Generic multi-agent orchestration for any task that benefits from parallel exploration. Use when user says "spin up N agents", "research swarm", "design swarm", "review with N agents", or "plan with agents".
triggers:
  - "spin up agents"
  - "research swarm"
  - "design swarm"
  - "review swarm"
  - "planning swarm"
  - "N agents to"
  - "team of agents"
argument-hint: "<type: research|design|review|planning|bead-creation> <topic> [--agents N]"
---

<!-- Decision table -->
<!-- | User says | Use | -->
<!-- |-----------|-----| -->
<!-- | "validate with oracles", "pro oracle review" | /swarm-oracle-review | -->
<!-- | "spin up 10 agents to research X" | /swarm-agents type=research | -->
<!-- | "redesign everything with 10 agents" | /swarm-agents type=design | -->
<!-- | "review plans with 10 agents" | /swarm-agents type=review | -->
<!-- | "20 agents for implementation planning" | /swarm-agents type=planning | -->
<!-- | "create beads from plan" | /swarm-agents type=bead-creation | -->
<!-- | "full feature pipeline" | /swarm-pipeline | -->

# Agent Swarm Skill

Orchestrate N parallel Opus agents for research, design, review, planning, or bead creation.
Each agent explores one facet independently; results are synthesized by the leader.

## When to Use

- Exploring a large codebase area from multiple angles
- Designing a feature with many interacting aspects
- Reviewing a plan/beads through multiple lenses
- Creating detailed implementation plans for complex features
- Creating beads from implementation plans

## When NOT to Use

- Simple targeted code search (use Grep/Glob)
- Single-aspect investigation (use Explore agent)
- Oracle consensus validation (use `/swarm-oracle-review`)
- Full end-to-end pipeline (use `/swarm-pipeline`)

## Swarm Types

### Research Swarm
**Purpose:** Map existing code and system landscape
**Typical size:** 10 agents
**Each agent:** Reads actual source code for one facet, documents findings

Recommended facets (pick N relevant ones):
```
- Core data model and persistence
- ViewModel layer and state management
- UI/XAML and user interaction
- Hardware/device integration
- Configuration and settings
- Error handling and edge cases
- Test coverage and gaps
- Related subsystem interactions
- User journey and workflow
- Performance and resource management
```

Second-pass facets (system landscape):
```
- User journeys and personas
- Settings/configuration architecture
- Readiness and validation pipelines
- Hardware discovery and lifecycle
- Data pipeline end-to-end
- Error/status/notification system
- Surrounding UI context
- Cognitive load and UX audit
- Platform/cross-cutting concerns
- Integration points
```

### Design Swarm
**Purpose:** Design all aspects of a solution
**Typical size:** 10 agents
**Each agent:** Designs one aspect, shares research context

Recommended aspects:
```
- Information hierarchy and layout
- Core interaction model
- Progressive disclosure
- Error/status/feedback system
- Setup/onboarding flow
- Data model and architecture
- Integration with existing UI
- Language and localization
- Accessibility
- ViewModel architecture
```

### Review Swarm
**Purpose:** Review plans/beads through multiple lenses
**Typical size:** 10 agents (technical) + 6 agents (general)
**Each agent:** Independently reviews with one lens

Technical lenses:
```
- Correctness (does it match design?)
- Conflict detection (contradictions?)
- Test coverage (all paths tested?)
- UX fidelity (matches design?)
- Safety and data integrity
- Performance and scalability
- Localization completeness
- Architecture compliance
- Accessibility
- Feasibility and risk
```

General review roles:
```
- User/customer perspective
- Tech lead perspective
- QA engineer perspective
- Conflict resolver (cross-plan contradictions)
- Bead structure advisor (sizing, deps, ACs)
- Executive summary (high-level assessment)
```

### Planning Swarm
**Purpose:** Create file-by-file implementation plans
**Typical size:** 20 agents
**Each agent:** Reads actual source files, produces line-level change specs

Agent allocation template:
```
- N agents: per-phase/per-epic plans (one per logical unit)
- 5 agents: cross-cutting (l10n, errors, testing, migration, perf)
- 3 agents: integration plans (how parts connect)
- 2 agents: risk assessment (failure modes, rollback)
```

### Bead Creation Swarm
**Purpose:** Convert implementation plans to actionable beads
**Typical size:** 6 agents
**Each agent:** Covers 1-2 epics, creates beads via `br` CLI

Each bead MUST have:
- Description with context
- Given/When/Then acceptance criteria
- Exact file paths to modify
- Test requirements
- Dependencies (use `br dep add`)
- Priority label (P0-P3)

## Orchestration Protocol

### Step 1: Define Facets

Based on the swarm type and topic, define N facets (one per agent).
Present facets to user for approval before spawning.

### Step 2: Prepare Shared Context

Gather context all agents need:
- Research summaries (for design/review swarms)
- Plan documents (for review/bead-creation swarms)
- Relevant foundry docs
- Key file paths

Write shared context to a temp file agents can read.

### Step 3: Spawn Agents

Use the built-in `Agent` tool. Send ONE message with N `Agent` tool calls so they run
concurrently. Each call has its own self-contained prompt (teammates don't share the
leader's context).

```
Agent({
  subagent_type: "general-purpose",
  name: "facet-<slug>",
  team_name: "<feature-or-task>",
  run_in_background: true,
  prompt: "You are researching [FACET] for [FEATURE].\n\nRead CLAUDE.md first, then:\n1. Read actual source code at [FILE_PATHS]\n2. Document findings per the template\n3. Return your findings as text in your final assistant message (do NOT write a report file — the leader persists it)"
})
```

**Subagents return findings as text; the leader persists them.** The harness blocks
subagent Write calls for report/findings files, so research/design/review agents cannot
write their own report file. Every such agent puts its findings in its **final assistant
message**, and the **leader** writes them to the shared directory (see Step 5). This means:

- Set `isolation: "worktree"` freely for these agents — their only output is the returned
  message (tool result), which survives the worktree being reaped.
- The leader synthesizes from each agent's returned message, then persists per-agent /
  per-round findings itself so there are durable artifacts across rounds.
- Code files written by execution-swarm teammates (`/swarm`) are unaffected — that block
  targets report-style files only. Execution swarms still commit code on the shared branch
  (no worktrees) per "Agent Swarm Rules" in CLAUDE.md.

The execution swarm (`/swarm`) is a different shape entirely — it MUST use shared
branch (same-branch, no worktrees) per "Agent Swarm Rules" in CLAUDE.md.

### Step 4: Monitor and Collect

Backgrounded teammates notify the leader when they finish. You can also:

```
TaskList                  # task progress
SendMessage({ to: "facet-<slug>", content: "status?" })   # ping a specific teammate
```

`SendMessage` is fine for artifact-swarm teammates (they survive between turns and
can answer follow-ups). Do NOT use it on execution-swarm teammates — those are
terminal by design.

Wait for all teammates to complete. Each teammate's findings arrive as the content of
its final message (returned as the `Agent` tool result). Persist them yourself: write
each agent's returned findings to the shared directory (e.g. `[OUTPUT_PATH]`) so there
are durable artifacts before you synthesize.

### Step 5: Synthesize

Read all N returned reports. Synthesize into a single cohesive document:
- Common findings across agents
- Contradictions or conflicts to resolve
- Key decisions and recommendations
- Gaps identified

Save synthesis to `foundation/product/features/` or appropriate location.

### Step 6: Present to User

Present synthesis. User decides next action:
- Another swarm round (deeper, different angle)
- Oracle validation (`/swarm-oracle-review`)
- Proceed to next pipeline phase
- Manual adjustments

## Agent Prompt Template

```
You are agent {N} in a {TYPE} swarm for [FEATURE].
Your assigned facet: [FACET]

## Context
[SHARED_CONTEXT — research summaries, plan refs, etc.]

## Instructions
1. Read CLAUDE.md in the project root
2. [TYPE-SPECIFIC INSTRUCTIONS]
3. Be thorough — read actual source code, not just file names
4. Return your report as text in your final assistant message (do NOT write a report
   file — the harness blocks that, and the leader persists your findings to [OUTPUT_PATH])

## Output Format
### Summary (3-5 sentences)
### Findings
### Recommendations
### Files Examined
### Issues/Risks
```

## Team Size Guidelines

| Task Complexity | Agents | Type |
|----------------|--------|------|
| Single subsystem research | 6 | Research |
| Full system research | 10 | Research |
| Multi-system landscape | 10 | Research |
| Feature design | 10 | Design |
| Plan review | 10+6 | Review |
| Implementation planning | 20 | Planning |
| Bead creation | 6 | Bead creation |
| Bead hardening | 8 | Review |
| Final correctness pass | 10 | Review |
| Doc updates | 6-8 | Varies |

## Key Rules

1. **Each agent reads actual code** — never just specs or summaries
2. **One facet per agent** — no overlap, clear boundaries
3. **Commit immediately** — each agent commits its output before moving on
4. **Synthesis is mandatory** — raw reports are not the deliverable
5. **User approves facets** before spawning agents
6. **Spawn all teammates in a single leader message** (one `Agent` call each, in the
   same response) so they run concurrently, not serially

## Related Skills
- `/swarm-exec` — Launch an implementation swarm (teammates execute beads autonomously, post-planning)
- `/swarm-exec-status` — Monitor running implementation swarm progress
- `/swarm-pipeline` — Full pipeline that orchestrates research→design→beads→implementation

