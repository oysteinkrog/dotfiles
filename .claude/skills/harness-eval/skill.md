---
name: harness-eval
model: opus
description: Evaluate a repository against the Harness Engineering framework (OpenAI, Feb 2026) with multi-model consensus scoring. Triggers on "harness eval", "harness engineering", "agent readiness", "evaluate harness", "score repo".
context: fork
---

# Harness Engineering Evaluation

Comprehensive multi-model evaluation of a repository against the **Harness Engineering** framework.

## Origin & Key References

**Primary article:** [OpenAI — Harness Engineering: Leveraging Codex in an Agent-First World](https://openai.com/index/harness-engineering/) (Feb 2026)
- OpenAI built a harness over 5 months; agents produced ~1M lines via ~1,500 automated PRs with zero manual code
- Named by Mitchell Hashimoto (HashiCorp); formalized by OpenAI days later
- See also: [Unlocking the Codex Harness](https://openai.com/index/unlocking-the-codex-harness/)

**Critical analyses & extensions:**

| Source | Key Contribution | URL |
|--------|-----------------|-----|
| Martin Fowler / Birgitta Boeckeler | Three-pillar taxonomy (context, constraints, garbage collection); critique: missing functional correctness verification | [martinfowler.com](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html) |
| Can Boluk — "I Improved 15 LLMs" | Proved harness > model: 5-14 point improvement across 15 LLMs, ~20% token reduction, just by changing edit format | [blog.can.ac](https://blog.can.ac/2026/02/12/the-harness-problem/) |
| Codified Context (arXiv 2602.20478) | Three-tier memory architecture (hot/specialist/cold); 25% knowledge-to-code ratio; 108K LOC C# system | [arxiv.org](https://arxiv.org/abs/2602.20478) |
| ETH Zurich (arXiv 2602.11988) | **AGENTS.md can hurt**: LLM-generated context reduced success ~3%; recommends <300 lines (ideally <60) | [arxiv.org](https://arxiv.org/html/2602.11988v1) |
| ContextCov (arXiv 2603.00822) | Transforms passive AGENTS.md into executable guardrails via AST analysis; 46K+ checks from 723 repos | [arxiv.org](https://arxiv.org/abs/2603.00822) |
| OpenDev (arXiv 2603.05344) | Four-level hierarchy (Sessions>Agents>Workflows>LLM Bindings); lazy tool discovery; adaptive context compaction | [arxiv.org](https://arxiv.org/abs/2603.05344) |
| Simon Willison — Agentic Engineering Patterns | Red/Green TDD for agents; pattern language for agent workflows | [simonwillison.net](https://simonwillison.net/guides/agentic-engineering-patterns/) |
| Anthropic — Effective Harnesses | Progressive disclosure via Skills; cross-session state via progress files; short-burst agents | [anthropic.com](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) |
| Anthropic — 2026 Agentic Coding Trends | 8 trends: role shift, multi-agent coordination, repository intelligence, papercut fixing | [anthropic resources](https://resources.anthropic.com/2026-agentic-coding-trends-report) |
| Karpathy + Lutke | "Context engineering" > "prompt engineering"; LLM=CPU, context window=RAM | [x.com/karpathy](https://x.com/karpathy/status/1937902205765607626) |
| LangChain | 52.8% -> 66.5% on TerminalBench 2.0 — Top 30 to Top 5 — only harness changed | [blog.langchain.com](https://blog.langchain.com/improving-deep-agents-with-harness-engineering/) |
| Stripe Minions | 1,300+ merged PRs/week; one-shot design; 6-layer harness; tool curation (~15 from 400+) | [stripe.dev](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents) |
| Factory.ai Agent Readiness | 8-pillar, 5-level maturity model; 60+ binary criteria; automated remediation PRs | [factory.ai](https://factory.ai/news/agent-readiness) |
| OpenAI Agent Legibility Scorecard | 7 metrics: Bootstrap, Entrypoints, Validation, Lint Gates, Repo Map, Docs, Decision Records | [startuphub.ai](https://www.startuphub.ai/ai-news/artificial-intelligence/2026/openai-codex-the-future-of-agent-engineering) |
| The Emerging Playbook (ignorance.ai) | Four practices: architecture as guardrails, tools as foundation, docs as active system, management pattern split | [ignorance.ai](https://www.ignorance.ai/p/the-emerging-harness-engineering) |
| Epsilla — 30/60/90 Day Roadmap | Days 1-30: docs + linting; 31-60: observability + acceptance tests; 61-90: entropy governance | [epsilla.com](https://www.epsilla.com/blogs/2026-03-12-harness-engineering) |
| HumanLayer | Claude Code system prompt has ~50 instructions; CLAUDE.md should be minimal (<60 lines ideal) | [humanlayer.dev](https://www.humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents) |
| agent-ready.org | Free Factory-compatible 9 Pillars / 5 Levels scanner (open source) | [agent-ready.org](https://agent-ready.org/) |
| Atlas Guardrails | Local-first guardrail: indexes repo, packs context, alerts on duplication/API breaks | [github.com](https://github.com/marcusgoll/atlas-guardrails) |
| Proliferate | Open-source background agent: cron-scheduled cleanup, Sentry triage, auto-PRs | [github.com](https://github.com/proliferate-ai/proliferate) |

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

### Step 2: Multi-Model Consensus Scoring

Use `mcp__pal__consensus` with three models in different stances:

```
mcp__pal__consensus:
  step: "Evaluate this repository against OpenAI's Harness Engineering framework..."
  models:
    - model: "gpt-5.4-pro"
      stance: "for"
      stance_prompt: "Score generously, highlight strengths"
    - model: "gemini-3.1-pro-preview"
      stance: "against"
      stance_prompt: "Score critically, emphasize gaps"
    - model: "gpt-5.4"
      stance: "neutral"
      stance_prompt: "Balanced assessment"
  step_number: 1
  total_steps: 4
  next_step_required: true
  findings: "<your verified inventory analysis — use agent findings, not assumptions>"
```

Include in the evaluation prompt:
1. Full inventory of context engineering assets (with line counts and project-level vs user-level distinction)
2. Full inventory of architectural constraints (hard/soft/discipline breakdown)
3. Full inventory of entropy management mechanisms (auto-fix vs report-only)
4. Specific enforcement summary (X/Y rules hard-enforced, Y/Z soft-enforced)
5. Verified test counts (active/ignored/disabled with percentages)

### Step 3: Synthesize Results

Present a consensus scorecard with sub-area detail:

```
| Pillar                    | Model A | Model B | Model C | Consensus |
|---------------------------|---------|---------|---------|-----------|
| Context Engineering       |         |         |         |           |
|   Static context          |         |         |         |           |
|   Dynamic context         |         |         |         |           |
|   Tiered documentation    |         |         |         |           |
|   In-context accessibility|         |         |         |           |
|   Three-tier memory       |         |         |         |           |
|   Context conciseness     |         |         |         |           |
| Architectural Constraints |         |         |         |           |
|   Dependency layering     |         |         |         |           |
|   Deterministic linters   |         |         |         |           |
|   LLM-based auditors      |         |         |         |           |
|   Structural tests & hooks|         |         |         |           |
|   Red/Green TDD           |         |         |         |           |
|   Constraint credibility  |         |         |         |           |
|   Executable guardrails   |         |         |         |           |
| Entropy Management        |         |         |         |           |
|   Background cleanup      |         |         |         |           |
|   Doc consistency         |         |         |         |           |
|   Constraint scanning     |         |         |         |           |
|   Pattern enforcement     |         |         |         |           |
|   Functional correctness  |         |         |         |           |
| **Weighted Overall**      |         |         |         |           |
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

## Industry Benchmarks (2026)

| Organization | Harness Maturity | Notable Achievement |
|-------------|-----------------|---------------------|
| OpenAI (Codex) | Reference implementation | 1M LOC, 1,500 PRs, 5-month harness build |
| Stripe (Minions) | Production-scale | 1,300+ merged PRs/week; one-shot design; 6-layer harness |
| LangChain | Benchmark-proven | +13.7 points on TerminalBench from harness alone |
| Can Boluk (oh-my-pi) | Open-source exemplar | +5-14 points across 15 models |
| Typical enterprise | 2-4/10 | AGENTS.md + basic CI only |

## Alternative Scoring Frameworks

The three-pillar model is the foundational framing but has been extended:

| Framework | Pillars | Criteria | Differentiator |
|-----------|---------|----------|---------------|
| OpenAI Three Pillars (this eval) | 3 | ~18 sub-areas | Original; most widely referenced |
| Factory.ai Agent Readiness | 8 | 60+ binary | Most comprehensive; automated remediation PRs |
| OpenAI Agent Legibility Scorecard | 7 | Letter grades | Most practical; includes Decision Records |
| ContextCov | 3 enforcement domains | 46K+ checks | Most rigorous; AST-checkable constraints |
| agent-ready.org | 9 | 5 maturity levels | Free open-source Factory.ai clone |

## What's New Beyond the Original Article

The community has extended OpenAI's framework in several directions:

1. **Context can hurt** (ETH Zurich) — LLM-generated context files reduced success rates; under 300 lines recommended
2. **Executable guardrails** (ContextCov) — passive AGENTS.md transformed into AST-checkable constraints via Tree-sitter
3. **Three-tier memory** (Codified Context paper) — hot/specialist/cold is more scalable than single AGENTS.md
4. **Harness > model** (Can Boluk, LangChain) — empirically proven that harness optimization outperforms model upgrades
5. **Functional correctness gap** (Fowler/Boeckeler) — structural quality != behavioral correctness; need e2e tests
6. **Red/Green TDD** (Willison) — test-first development is ideal for agent workflows; test-alongside is not TDD
7. **One-shot design** (Stripe Minions) — single LLM call with assembled context beats multi-turn chains (95%^5 = 77%)
8. **Tool curation** (Stripe Minions) — select ~15 relevant tools from 400+; too many tools causes "token paralysis"
9. **Progressive disclosure** (Anthropic) — skills loaded on-demand, not all at once; short-burst agents (5 min each)
10. **Context engineering as discipline** (Karpathy/Lutke) — "the delicate art of filling the context window with just the right information"
11. **Background cleanup agents** (Proliferate, Anthropic trends) — autonomous fix PRs, not just detection
12. **30/60/90 roadmap** (Epsilla) — phased adoption path for organizations
13. **Multi-agent coordination** (Anthropic trends) — 57% of orgs now deploy multi-step agent workflows
14. **Architecture drift detection** (ArchCodex, SonarQube) — continuous architectural constraint verification; zero-drift rates improved 17% -> 70%
15. **Doom-loop detection** (LangChain) — detect and break repeated ineffective edit cycles
16. **Knowledge-to-code ratio** (Codified Context) — expect ~25% overhead for agent context infrastructure
17. **8-pillar maturity model** (Factory.ai) — 60+ binary criteria across Style, Docs, DevEnv, Security, and 4 more
