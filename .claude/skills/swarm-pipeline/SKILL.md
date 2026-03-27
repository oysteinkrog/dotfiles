---
name: feature-pipeline
model: opus
description: Playbook for large-scale AI-assisted feature development. Covers 5 meta-patterns (two-track prioritization, escalating agent teams, oracle integration, convergence detection, fresh-eyes principle) plus full pipeline phases. Use when orchestrating a major feature from UX problem through implementation-ready beads.
triggers:
  - "plan this properly"
  - "design this feature"
  - "feature pipeline"
  - "full design process"
  - "spin up agents and plan this"
  - "orchestrate feature design"
argument-hint: "<feature description or Jira issue>"
---

<!-- Decision table -->
<!-- | User says | Use | -->
<!-- |-----------|-----| -->
<!-- | "spin up 10 agents to research X" | /swarm-agents | -->
<!-- | "validate with oracles" | /swarm-oracle | -->
<!-- | "plan this properly", "do the full pipeline" | /swarm-pipeline | -->
<!-- | "create beads from plan" | /swarm-beads-create | -->
<!-- | "harden these beads" | /swarm-beads-quality | -->
<!-- | Small fix (1-3 files) | Just implement it | -->

# Feature Pipeline — Large-Scale AI-Assisted Development

Multi-phase pipeline: research → design → oracle → plan → review → beads → harden.
Proven at scale: ~160 Opus + 12 Pro oracles → 80 beads, 271 test cases, zero cycles.

This skill documents 5 meta-patterns that make the pipeline work, plus the full phase
structure. Sub-skills handle individual phases; this skill orchestrates the whole.

## When to Use

- Complex features touching 10+ files across multiple subsystems
- Critical product areas requiring high confidence
- UX or architecture uncertainty needs resolution before coding
- User wants thorough design before implementation

## When NOT to Use

- Simple bug fixes (just fix it)
- Single-file or well-scoped changes (use beads directly)
- Time-sensitive hotfixes
- Features already well-specified with clear file paths

## Scope Decision Tree

```
Feature scope?
├─ Small (1-3 files, clear fix) → Just implement it
├─ Medium (4-10 files, known pattern) → /swarm-beads-create + 6-agent team
└─ Large (10+ files, UX/arch uncertainty) → This playbook
    ├─ Uncertainty mostly in UX? → Start Phase 1
    ├─ UX clear, arch uncertain? → Start Phase 2
    └─ Both clear, just complex? → Start Phase 5
```

---

# META-PATTERNS

## Pattern 1: Two-Track Prioritization

Separate safety/correctness from feature work early. Label every bead after creation:

| Track | Priority | Ships | Content |
|-------|----------|-------|---------|
| A | P0/P1 | First | Data integrity, safety, correctness, bug fixes |
| B | P2 | Second | Architecture, UX improvements, new features |
| C | P3 | Last | Polish, terminology, nice-to-haves |

**When:** After Phase 8 (bead creation). Re-label during hardening as issues surface.
In the proven run, 28 beads were relabeled during hardening.

**Why:** Track A ships independently. If feature stalls, safety improvements are merged.
Track B depends on Track A foundations. Track C is droppable without regression.

**Prompt for labeling:**
```
Review each bead and assign a track:
- Track A (P0/P1): Fixes a bug, prevents data loss, ensures correctness?
- Track B (P2): Improves architecture or adds new UX capability?
- Track C (P3): Polish, terminology, nice-to-have?
If a bead spans tracks, SPLIT it. Data integrity always goes in Track A.
```

**Anti-pattern:** Treating all beads equally → safety fixes blocked by feature work →
entire branch un-mergeable until everything is done.

---

## Pattern 2: Escalating Agent Teams

Scale team size to match uncertainty and facet count, not raw complexity.

### Team Sizing Table

| Size | When | Role Pattern |
|------|------|-------------|
| 1 (Explore) | Targeted research on one subsystem | Single deep dive |
| 6 | Doc updates, bead creation/rewriting, applying known changes | 1-2 epics per agent |
| 8 | Foundry doc updates, bead hardening with specific fixes | 1 doc/fix-category per agent |
| 10 | Research, design, review, audit, final verification | 1 facet/lens per agent |
| 20 | Deep impl planning (only for large features, 10+ subsystems) | 10 phase + 5 cross-cut + 3 integration + 2 risk |

**Scaling rule:** Match team to facet count. If you can name 10 distinct facets, use 10.
If only 6, use 6. Never pad with redundant roles — produces duplicate findings.

### Escalation Through the Pipeline

```
Phase 1:  10 agents (map code)
Phase 2:  10 agents (map landscape — same size, different abstraction)
Phase 3:  10 agents (design — same size, now proposing solutions)
Phase 4:   8+2 (doc updates + oracle validation)
Phase 5:  20 agents (maximum — deepest planning, most facets)
Phase 6:  10 agents (review — one lens each)
Phase 7:   6 agents (general review — broader roles)
Phase 8:   6 agents (bead creation — 1-2 epics each)
Phase 9:  10→2→8→10 (hardening — VARIES per round)
```

**Key insight:** Team size VARIES by phase. 20 is the planning maximum, not the default.
Review rounds use 10 (one per lens). Creation/application uses 6-8.

### Spawning

```bash
ntm spawn --cc=N --no-cass-check
```

Each agent prompt MUST include:
1. Explicit file paths to read (actual source, not specs)
2. Structured output format expected
3. Git commit instructions (per CLAUDE.md swarm rules)
4. What NOT to do (e.g., "Do NOT propose solutions" for researchers)

---

## Pattern 3: Oracle Integration

Use Pro oracles (GPT-5.4-Pro via `/swarm-oracle`) for adversarial review at
decision points. Oracles challenge assumptions; agents cover breadth.

### Oracles vs More Opus Agents

| Need | Use | Why |
|------|-----|-----|
| Broader coverage of known concerns | More Opus | Parallel breadth |
| Challenge assumptions, find blind spots | Pro oracles | Adversarial depth |
| Design tradeoff decisions | Pro oracles | FOR/AGAINST surfaces tension |
| Spec/bead correctness | Opus first, then oracles | Opus catches obvious; oracles catch subtle |
| Rewrite scope validation | Pro oracles | Prevents over/under-scoping |
| File-by-file impl details | Opus | Oracles too expensive for mechanical work |

### Oracle Session Structure

ALWAYS use FOR + AGAINST stances. Never two neutrals (produces bland agreement).

Use `/swarm-oracle` which wraps the PAL consensus tool:
```python
mcp__pal__consensus(
  step="Evaluate: [SPECIFIC QUESTION]",
  models=[
    {"model": "gpt-5.4-pro", "stance": "for",
     "stance_prompt": "Argue this approach is sound and sufficient."},
    {"model": "gpt-5.4-pro", "stance": "against",
     "stance_prompt": "Argue this approach has critical gaps or flaws."}
  ],
  relevant_files=[...],
  ...
)
```

### Oracle Placement

| After Phase | Focus | Expected Findings |
|-------------|-------|-------------------|
| 3 (Design) | UX soundness + arch feasibility | 3-5 critical corrections |
| 5 (Impl Plan) | Spec completeness + conflicts | 2-4 blocking issues |
| 8 (Bead Creation) | Bead readiness + cross-cutting | 3-5 spec contradictions |
| 10 (Arch Audit) | Rewrite scope validation | Scope adjustment (usually narrowing) |

**Expected scores:** 7-9/10 on first pass. Below 7 = fundamental rethink needed.
Above 9 = suspicious (verify oracle actually challenged the work).

**CRITICAL pre-flight:** Verify PAL MCP is running before oracle phases. Agents silently
fall back to self-analysis if PAL is down, producing worthless "oracle validated" results.

---

## Pattern 4: Convergence Detection

Track issue count per review round. Each round MUST find fewer than the previous.

| Round | Type | Expected Issues | Character |
|-------|------|----------------|-----------|
| 1 | Opus review (10) | 15-25 | Logic, structure, missing pieces |
| 2 | Oracle (2 Pro) | 3-7 | Deeper: spec contradictions, arch gaps |
| 3 | Fresh-eyes (8) | 5-10 | Format, completeness, cross-cutting |
| 4 | Final (10) | 0-5 | Minor: paths, typos, deps |

### Stop Condition

Round finds < 3 issues AND zero logic/correctness issues → Done.

### Divergence Signal

If Round N finds MORE issues than Round N-1:
1. Check if Round N-1 fixes introduced new problems
2. Check if review scope expanded (new facets discovered)
3. If neither → run oracle session to identify root cause

### Tracking Template

```markdown
## Convergence Log
| Round | Agents | Issues Found | Logic Issues | Stop? |
|-------|--------|-------------|-------------|-------|
| 1 | 10 Opus | 25 | 8 | No |
| 2 | 2 Pro | 5 | 3 | No |
| 3 | 8 Opus (fresh) | 10 | 1 | No |
| 4 | 10 Opus | 3 | 0 | YES |
```

**Why this matters:** Without tracking, you run review rounds "until it feels right."
Convergence tracking gives an objective stop signal.

---

## Pattern 5: Fresh-Eyes Principle

After 2+ review rounds, bring in agents who have NOT seen prior work.

### Why Fresh Eyes Work

Agents that reviewed earlier rounds develop blind spots:
- Accept previously-approved patterns without re-examining
- Habituate to naming inconsistencies
- Assume cross-cutting requirements were embedded (they weren't)
- Skip prose ACs that should be Given/When/Then

### How to Implement

Spawn a NEW team. Do NOT include prior review outputs. Give them ONLY:
1. Current state of beads/plan (the artifact, not its history)
2. Original requirements/constraints
3. A review checklist

```
You are reviewing [BEADS/PLAN] with fresh eyes.
You have NOT seen prior reviews. Do not assume anything was already checked.

Requirements: [ORIGINAL REQUIREMENTS]

Review for:
1. Are acceptance criteria testable (Given/When/Then, not prose)?
2. Are cross-cutting requirements embedded in EACH bead individually?
   (l10n keys, error handling, a11y, logging)
3. Are file paths and class names correct? (verify against actual source)
4. Are dependencies complete and acyclic?
5. Is each bead self-contained for a single agent to implement (1-3 files)?
6. Do any beads have contradictory specifications?

Fix every issue you find. Do NOT assume prior reviewers caught anything.
```

### When in the Pipeline

Fresh-eyes is Round 3 of the hardening loop (Phase 9):
1. Round 1: Opus review (agents familiar with the plan)
2. Round 2: Oracle validation (Pro, adversarial)
3. **Round 3: Fresh-eyes hardening (NEW agents, no history)**
4. Round 4: Final correctness (can reuse Round 1 agents)

---

# PIPELINE PHASES (Detailed)

## Phase 1: Research — Code Building Blocks
**Team:** 10 Opus via `/swarm-agents` | **Goal:** Map existing code

Prompt per agent (assign one facet):
```
You are researching [FACET] for the [FEATURE] feature.
Read actual source at [FILE PATHS].
Document: what exists, what works, what's broken, interfaces/extension points.
Do NOT propose solutions — just map the territory.
```

Facets: data model, VM layer, UI/XAML, hardware, config, errors, tests,
subsystem interactions, user journeys, performance.

**Output:** Synthesize 10 reports into one research summary.

## Phase 2: Research — System Landscape
**Team:** 10 Opus | **Goal:** Map surrounding architecture + user needs

Same structure as Phase 1 but one abstraction level up. Facets: user journeys,
settings arch, readiness, hardware discovery, data pipeline, error system,
surrounding UI, cognitive load, platform concerns, external integrations.

**Output:** Landscape document → `foundation/product/features/`.

## Phase 3: Holistic Design
**Team:** 10 Opus | **Goal:** Design every aspect to world-class quality

Each agent designs one aspect, sharing research from Phases 1-2:
info hierarchy, interaction model, progressive disclosure, error/status,
wizard flow, data model, integration, terminology, a11y, VM architecture.

**Output:** Synthesize designs into plan → `foundation/product/features/`.

## Phase 4: Oracle Validation
**Use:** `/swarm-oracle` | **Team:** 2 GPT-5.4-Pro (FOR + AGAINST)

Two rounds: (1) UX + interaction design, (2) architecture + data model.
Apply corrections before proceeding.

Optionally: 8 Opus agents update foundry docs with design decisions.

## Phase 5: Deep Implementation Planning
**Team:** 20 Opus | **Goal:** File-by-file change specifications

Allocation: 10 per-phase + 5 cross-cutting + 3 integration + 2 risk.
Each agent reads actual source files they reference.

**Output:** 20 implementation plan documents.

## Phase 6: Multi-Lens Review
**Use:** `/swarm-review` | **Team:** 10 Opus

Lenses: correctness, conflicts, test coverage, UX fidelity, safety,
performance, localization, architecture, accessibility, feasibility.

**Output:** Compiled findings → fix all issues.

## Phase 7: General Review
**Team:** 6 Opus | **Roles:** User POV, tech lead, QA, conflict resolver,
bead advisor, executive summary.

## Phase 8: Bead Creation
**Use:** `/swarm-beads-create` | **Team:** 6 Opus (1-2 epics each)

Each bead: description, Given/When/Then ACs, file paths, test reqs, deps, priority.
Use `br create` + `br dep add`. Target 1-3 files per bead.

## Phase 9: Bead Hardening Loop
**Use:** `/swarm-beads-quality` or `/swarm-hardening`

Four rounds with convergence tracking (see Pattern 4):
1. 10 Opus: per-epic + deps + tests + self-containment
2. 2 Pro: oracle challenge on readiness
3. 8 Opus: **fresh eyes** (see Pattern 5) — fix specs, embed cross-cutting, GWT
4. 10 Opus: final correctness

## Phase 10: Architecture Audit (Optional)
**Team:** 10 Opus | Read actual source, decide: rewrite | refactor | keep.
Creates new beads for gaps found. Oracle validates rewrite scope.

## Phase 11: Apply + Two-Track Labeling
Apply audit findings → 6 Opus rewrite beads → 2 Pro oracle validate scope.
Apply two-track labels (Pattern 1) to all beads.

## Phase 12: Final Correctness
**Team:** 10 Opus | Verify every bead. Fix remaining issues.

---

# PROMPT TEMPLATES BY ROLE

### Researcher (Phases 1-2)
```
You are researching [FACET] for [FEATURE].
Read: [FILE PATHS — actual source, not specs]
Map: existing code, API surface, state, edge cases.
Output: structured report with file:line references.
Do NOT propose solutions.
```

### Designer (Phase 3)
```
You are designing [ASPECT] for [FEATURE].
Context: [PLAN] | Research: [PHASE 1-2 OUTPUTS]
Optimize: UX quality + code quality + maintainability.
Output: concrete design with rationale for every decision.
Include: component hierarchy, data flow, state transitions, error states.
```

### Implementation Planner (Phase 5)
```
You are planning [PHASE/CROSS-CUT] for [FEATURE].
Plan: [PLAN] | Design: [DESIGN]
Read actual source files. Include file:line in output.
Output: file-by-file change spec. New files, modified files, deleted files.
```

### Reviewer — Multi-Lens (Phase 6)
```
You are reviewing [ARTIFACT] through the [LENS] lens.
For each issue: severity (blocking/major/minor), location, proposed fix.
Do NOT rubber-stamp. If zero issues, explain why that's surprising.
```

### Bead Creator (Phase 8)
```
You are creating beads for [EPIC].
Plan: [IMPL PLAN] | Reviews: [FINDINGS]
Each bead: title, description, Given/When/Then ACs, file paths (verified),
test reqs, deps, priority. Use br create + br dep add.
Target: 1-3 files per bead. Split if larger.
After: br sync --flush-only && git add .beads/ && git commit
```

### Auditor (Phase 10)
```
You are auditing [SUBSYSTEM] source code.
Read actual source at [FILE PATHS].
For each class: rewrite | refactor | keep. Justify with evidence.
Identify: bugs, design flaws, missing error handling, coupling.
Output: decisions + rationale + new beads needed.
```

---

# ANTI-PATTERNS

| # | Anti-Pattern | Fix |
|---|-------------|-----|
| 1 | Agents design from specs, not code | Every prompt includes file paths to read |
| 2 | Oracle without PAL verification | Pre-flight check before oracle phases |
| 3 | Redundant reviewer roles | Assign distinct lenses, zero overlap |
| 4 | Stale context in fresh-eyes round | Only current state + original reqs, no history |
| 5 | Beads before oracle validation | Oracle after design, before beads |
| 6 | No convergence tracking | Track issue count per round, stop at < 3 |
| 7 | Monolithic beads (5+ files) | Split to 1-3 files during creation |
| 8 | All beads same priority | Two-track labeling after Phase 8 |
| 9 | Agents don't commit | Explicit commit instructions in every prompt |
| 10 | Over-scaling teams | Match team size to facet count, 20 is max not default |

---

# EXECUTION CHECKLIST

Between every phase, pause and present findings. User decides: proceed, repeat, skip, abort.
Never auto-advance without confirmation.

```
[ ] Phase 1-2: Research (10+10 agents) → research summary
[ ] Phase 3: Design (10 agents) → design doc
[ ] Phase 4: Oracle (2 Pro FOR/AGAINST) → corrections applied
[ ] Phase 5: Impl Planning (20 agents) → 20 plan docs
[ ] Phase 6-7: Review (10+6 agents) → findings fixed
[ ] Phase 8: Bead Creation (6 agents) → beads with ACs
[ ] Phase 9: Hardening (10→2→8→10, track convergence) → hardened beads
[ ] Phase 10-11: Audit + Apply + Oracle + Two-Track → final beads
[ ] Phase 12: Final Correctness (10 agents) → ship-ready backlog
```

## Proven Metrics

| Metric | Value |
|--------|-------|
| Total Opus agents | ~160 |
| Pro oracle sessions | 12 |
| Final beads | 80 |
| Test cases | 271 |
| Dependency cycles | 0 |
| Oracle findings verified | 20/20 |
| Convergence (issues/round) | 25 → 7 → 10 → 5 |
| Beads relabeled (two-track) | 28 |

## Cost Estimate

| Phase | Agents | Model |
|-------|--------|-------|
| Research (2 rounds) | 20 | Opus |
| Design | 10 | Opus |
| Oracle (2 rounds) | 4 | GPT-5.4-Pro |
| Planning | 20 | Opus |
| Review (2 rounds) | 16 | Opus |
| Bead creation | 6 | Opus |
| Hardening (4 rounds) | 30 | Opus |
| Oracle (2 rounds) | 4 | GPT-5.4-Pro |
| Final pass | 10 | Opus |
| **Total** | **~120** | |

## Artifacts

```
foundation/product/features/
  {feature}-research.md           # Phase 1-2
  {feature}-design.md             # Phase 3
  {feature}-implementation-plan.md  # Phase 5
  {feature}-review-findings.md    # Phase 6-7
.beads/                           # Phase 8-12
```

## Complete Swarm Skill Family

| Skill | Phase | Purpose |
|-------|-------|---------|
| `/swarm-prd` | Pre-pipeline | Generate PRD from feature description |
| `/swarm-pipeline` | Orchestrator | Full research→design→beads pipeline |
| `/swarm-agents` | Any phase | Spin up N parallel research/design/review agents |
| `/swarm-review` | Review | 10-lens multi-perspective review |
| `/swarm-oracle` | Validation | FOR/AGAINST Pro oracle consensus |
| `/swarm-oracle-review` | Validation | Combined oracle + hardening loop |
| `/swarm-hardening` | Quality | 4-round iterative hardening |
| `/swarm-beads-create` | Bead creation | Convert plans to beads (multi-agent) |
| `/swarm-beads-quality` | Bead QA | Review + oracle + harden beads |
| `/swarm-beads-rewrite` | Bead maintenance | Apply audit findings to beads |
| `/swarm-beads-polish` | Bead QA (light) | Single-agent bead review |
| `/swarm-beads-quick` | Bead creation (light) | Single-agent PRD→beads |
| `/swarm-exec` | Implementation | ntm-based agent swarm executing beads |
| `/swarm-exec-status` | Monitoring | Check implementation swarm progress |
| `/swarm-oracle-standalone` | Any time | Standalone oracle consultation |
