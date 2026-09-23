---
name: harness-eval
model: opus
description: Evaluate a repository against the Harness Engineering framework (OpenAI, Feb 2026) with FOR/AGAINST oracle scoring (Astra via /swarm-oracle). Triggers on "harness eval", "harness engineering", "agent readiness", "evaluate harness", "score repo".
context: fork
---

# Harness Engineering Evaluation

Comprehensive multi-model evaluation of a repository against the **Harness Engineering** framework.

## References

Sources, industry benchmarks, other scoring frameworks and extensions to the original article are in [references/research.md](references/research.md).

## The Three Pillars

### Pillar 1: Context Engineering (weight: 35%)

"Anything the agent can't access in-context doesn't exist." — OpenAI

**What to evaluate:**

| Sub-area | Score 0-10 | What "10" looks like |
|----------|-----------|---------------------|
| Static context | | Versioned AGENTS.md/CLAUDE.md, design specs, architecture maps, execution plans, ADRs |
| Dynamic context | | Live observability (CI status, git state, Sentry, branch health, test impact maps) via MCP at **project level** |
| Tiered documentation | | Progressive loading: quick-start -> rules -> domain knowledge -> specs |
| In-context accessibility | | Semantic search (qmd/RAG), MCP integrations, everything machine-readable |
| Three-tier memory | | Hot memory (constitution), specialist agents (domain experts), cold memory (on-demand specs) |
| Context conciseness | | AGENTS.md/CLAUDE.md under 300 lines (ETH Zurich); progressive tiers handle overflow |

**Critical finding (ETH Zurich, arXiv 2602.11988):** More context is NOT better. LLM-generated context files **reduced** success by ~3% and increased costs 20%+. Human-written files improved success only ~4%. Under 300 lines recommended, ideally under 60. Score DOWN for bloated context files.

**Novel benchmark (Codified Context paper):** Knowledge-to-code ratio. When calculating, use consistent definitions. Include all docs/knowledge/tooling the harness relies on, not just files agents auto-load. A 108K LOC system needed 25K lines (24.2%). Compare apples-to-apples.

**Scoring trap — Dynamic context:** Distinguish user-level MCP integrations (Atlassian, Slack, GitHub in user settings) from project-level configurations (`.mcp.json`). Score based on what ships with the repo, not the developer's personal setup.

### Pillar 2: Architectural Constraints (weight: 35%)

"Increasing trust required constraining the solution space." — Boeckeler/Fowler

| Sub-area | Score 0-10 | What "10" looks like |
|----------|-----------|---------------------|
| Dependency layering | | Enforced sequence with zero bypasses; ArchUnitNET/dependency-cruiser with no ignored tests |
| Deterministic linters as teaching tools | | Error messages include remediation guidance, examples, and principle links (helpLinkUri) |
| LLM-based auditors | | Advisory LLM review on PRs for architectural intent, coupling, doc staleness |
| Structural tests & hooks | | Pre-commit hooks, banned API checks, architecture tests, localization CI |
| Red/Green TDD integration | | Agents required to write failing tests first, confirm failure, then implement (Willison pattern) |
| Constraint credibility | | Zero ignored/skipped tests, or explicit burn-down with owners and expiry dates |
| Executable guardrails | | ContextCov-style: constraints in AGENTS.md are AST-checkable, not just advisory |

**Scoring trap — TDD:** Having many tests is NOT TDD. Check for: coverage gates that block PRs, pre-commit hooks requiring test changes with code changes, test-first commit patterns (test commit before feature commit), TDD skills/workflows. Test-alongside (feature then test) scores 1-2/10; only enforced test-first scores 5+.

**Scoring trap — Enforcement levels:** Distinguish three tiers:
1. **Hard enforcement** (build error, CI failure, blocked merge) — full credit
2. **Soft enforcement** (weekly scan, advisory report, issue creation) — half credit
3. **Agent discipline** (documented but no mechanical check) — minimal credit

**Key insight (Can Boluk):** Harness format matters more than model choice. Grok went 6.7% -> 68.3% with format change alone.

### Pillar 3: Entropy Management (weight: 30%)

"Entropy management is garbage collection for codebases." — Fowler

| Sub-area | Score 0-10 | What "10" looks like |
|----------|-----------|---------------------|
| Background cleanup agents | | Scheduled agents opening low-risk fix PRs (formatting, regions, log prefixes, deps). Include dependency managers (Renovate/Dependabot). |
| Doc consistency verification | | CI verifying CLAUDE.md/PRINCIPLES.md stay synchronized with code reality |
| Constraint violation scanning | | Weekly sweeps: format drift, architecture, TODOs, vulns, duplication, secrets. With historical trending and ownership tracking. |
| Pattern enforcement | | Dependency drift analysis, ownership-aware rule trends, migration tooling |
| Functional correctness | | End-to-end behavioral tests on PR gate, not just structural quality (Fowler critique). Score DOWN if E2E is workflow_dispatch/manual only. |

**Scoring trap — Functional correctness:** E2E tests that exist but only run on-demand (workflow_dispatch) score 6-7/10 max. Only PR-blocking E2E deserves 8+. Check what percentage of test scenarios are actually enabled (disabled/commented scenarios reduce the score).

**30/60/90 Day Implementation Roadmap (Epsilla):**
- Days 1-30: Structured docs + custom linting
- Days 31-60: Agent observability + automated acceptance testing
- Days 61-90: Entropy governance + technical debt tracking

## How to Run the Evaluation

### Step 0: Deploy Verification Agents (10+ recommended)

Before scoring, deploy independent verification agents to audit specific dimensions. This prevents the scoring models from hallucinating capabilities that don't exist.

Recommended agent assignments:
1. **Architecture test audit** — count exact [Test]/[Ignore] methods, find all test files
2. **Principles enforcement audit** — verify each claimed enforcement mechanism exists in code
3. **CI workflow inventory** — list all workflows, triggers, blocking vs advisory
4. **Knowledge-to-code ratio** — calculate with consistent definitions (narrow/medium/broad)
5. **TDD enforcement audit** — check for coverage gates, test-first commit patterns, TDD skills
6. **Entropy management audit** — verify auto-fix, doc sync, scans, dependency managers
7. **Context engineering audit** — distinguish project-level vs user-level MCP, check memory tiers
8. **Linter/analyzer audit** — count rules, severity levels, verify custom analyzers
9. **Constraint credibility audit** — count NoWarn, pragma disable, [Ignore], [SuppressMessage]
10. **UI/E2E test audit** — find test projects, check triggers, count enabled vs disabled scenarios
11. **Web research** — latest framework developments, newer scoring models

### Step 1: Inventory (you do this, informed by agent findings)

Read the repository's key files to understand current state:
- CLAUDE.md / AGENTS.md / .cursorrules (or equivalent) — **count lines** (ETH Zurich: <300)
- PRINCIPLES.md or similar rules files — count principles, verify each enforcement claim
- .editorconfig, Directory.Build.props (or equivalent build config)
- CI/CD workflows (.github/workflows/) — categorize: PR-blocking vs scheduled vs on-demand
- Architecture test projects — count active vs ignored vs explicit tests
- Pre-commit hooks
- Custom analyzers/linters — count diagnostic IDs, verify helpLinkUri
- .mcp.json (project level) vs user-level MCP configs — distinguish clearly
- Dependency managers (Renovate, Dependabot)
- Memory files (.claude/memory/, agents/, etc.)

### Step 2: Oracle Scoring

Load `/swarm-oracle` and run its FOR/AGAINST debate on the scorecard. By default that is two GPT-6 Astra sessions through the Codex CLI:

- **FOR:** score generously and name the strengths.
- **AGAINST:** score critically and name the gaps.

Add the Fable FOR/AGAINST pair when the result is high-stakes (a score that will be shared or acted on) or when the two Astra scores differ by more than 2 points on any pillar. `/swarm-oracle` owns the invocation, the Fable fallback when Codex fails, and the approval rule for sending proprietary code off the machine.

Pass your verified inventory analysis as the evaluation input. Use the agent findings, not assumptions.

Include in the evaluation prompt:
1. Full inventory of context engineering assets (with line counts and project-level vs user-level distinction)
2. Full inventory of architectural constraints (hard/soft/discipline breakdown)
3. Full inventory of entropy management mechanisms (auto-fix vs report-only)
4. Specific enforcement summary (X/Y rules hard-enforced, Y/Z soft-enforced)
5. Verified test counts (active/ignored/disabled with percentages)

### Step 3: Synthesize Results

Present a consensus scorecard with sub-area detail:

```
| Pillar                    | Astra FOR | Astra AGAINST | Fable (if run) | Consensus |
|---------------------------|-----------|---------------|----------------|-----------|
| Context Engineering       |           |               |                |           |
|   Static context          |           |               |                |           |
|   Dynamic context         |           |               |                |           |
|   Tiered documentation    |           |               |                |           |
|   In-context accessibility|           |               |                |           |
|   Three-tier memory       |           |               |                |           |
|   Context conciseness     |           |               |                |           |
| Architectural Constraints |           |               |                |           |
|   Dependency layering     |           |               |                |           |
|   Deterministic linters   |           |               |                |           |
|   LLM-based auditors      |           |               |                |           |
|   Structural tests & hooks|           |               |                |           |
|   Red/Green TDD           |           |               |                |           |
|   Constraint credibility  |           |               |                |           |
|   Executable guardrails   |           |               |                |           |
| Entropy Management        |           |               |                |           |
|   Background cleanup      |           |               |                |           |
|   Doc consistency         |           |               |                |           |
|   Constraint scanning     |           |               |                |           |
|   Pattern enforcement     |           |               |                |           |
|   Functional correctness  |           |               |                |           |
| **Weighted Overall**      |           |               |                |           |
```

### Step 4: Gap Analysis

For each gap identified by 2+ models, provide:
1. **What's missing** — specific capability gap
2. **Why it matters** — reference to framework pillar
3. **How to fix** — concrete implementation suggestion
4. **Effort estimate** — low/medium/high
5. **Impact** — score improvement expected

### Step 5: Maturity Bar Chart

```
                    Current     Target (full harness)
Context Engineering  ████████░░  ██████████
Arch Constraints     ███████░░░  ██████████
Entropy Management   █████░░░░░  ██████████
```

## Key Metrics to Report

| Metric | Source | What it measures | Scoring traps |
|--------|--------|-----------------|---------------|
| Knowledge-to-code ratio | Codified Context paper | Lines of agent context / lines of code | Use consistent definition; narrow (auto-loaded only) vs broad (all docs) |
| Context file size | ETH Zurich study | Lines in AGENTS.md/CLAUDE.md | <60 ideal, <300 acceptable, >300 penalize |
| Principles enforcement % | PRINCIPLES.md | Hard-enforced / total principles | Distinguish hard (build error) vs soft (scan) vs discipline |
| Architecture test health | ArchUnitNET/equiv | Active tests / total tests | Count ALL [Test] methods; include [Ignore] and [Explicit] separately |
| Constraint credibility | Ignored + suppressed | [Ignore] + NoWarn + pragma disable + SuppressMessage | Check if violations have dated remediation plans |
| TDD enforcement level | CI + hooks + skills | Enforced test-first gates | Test-alongside ≠ TDD; check commit order patterns |
| Entropy detection coverage | CI workflows | Scan types running weekly | Count dimensions; check if trending/ownership tracked |
| Entropy remediation % | Background agents | Scans that auto-fix vs report-only | Include dependency managers (Renovate/Dependabot) |
| Tiered doc depth | Context inventory | Number of documentation tiers | Verify tiers are independently loadable, not monolithic |
| E2E test enablement | Test projects | Enabled scenarios / total scenarios | Disabled/commented scenarios reduce functional correctness |
| Project-level MCP count | .mcp.json | MCP servers configured per-project | User-level MCPs don't count for project scoring |
