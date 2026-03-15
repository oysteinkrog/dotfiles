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

**Critical analyses & extensions:**

| Source | Key Contribution | URL |
|--------|-----------------|-----|
| Martin Fowler / Birgitta Boeckeler | Three-pillar taxonomy (context, constraints, garbage collection); critique: missing functional correctness verification | [martinfowler.com](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html) |
| Can Boluk — "I Improved 15 LLMs" | Proved harness > model: 5-14 point improvement across 15 LLMs, ~20% token reduction, just by changing edit format | [blog.can.ac](https://blog.can.ac/2026/02/12/the-harness-problem/) |
| Codified Context (arXiv 2602.20478) | Three-tier memory architecture (hot/specialist/cold); 25% knowledge-to-code ratio; 108K LOC C# system | [arxiv.org](https://arxiv.org/abs/2602.20478) |
| Simon Willison — Agentic Engineering Patterns | Red/Green TDD for agents; pattern language for agent workflows | [simonwillison.net](https://simonwillison.net/guides/agentic-engineering-patterns/) |
| Anthropic — 2026 Agentic Coding Trends | 8 trends: role shift, multi-agent coordination, repository intelligence, papercut fixing | [anthropic resources](https://resources.anthropic.com/2026-agentic-coding-trends-report) |
| Karpathy + Lutke | "Context engineering" > "prompt engineering"; LLM=CPU, context window=RAM | [x.com/karpathy](https://x.com/karpathy/status/1937902205765607626) |
| LangChain | 52.8% -> 66.5% on TerminalBench 2.0 — Top 30 to Top 5 — only harness changed | [blog.langchain.com](https://blog.langchain.com/improving-deep-agents-with-harness-engineering/) |
| The Emerging Playbook (ignorance.ai) | Four practices: architecture as guardrails, tools as foundation, docs as active system, management pattern split | [ignorance.ai](https://www.ignorance.ai/p/the-emerging-harness-engineering) |
| Epsilla — 30/60/90 Day Roadmap | Days 1-30: docs + linting; 31-60: observability + acceptance tests; 61-90: entropy governance | [epsilla.com](https://www.epsilla.com/blogs/2026-03-12-harness-engineering) |
| Atlas Guardrails | Local-first guardrail: indexes repo, packs context, alerts on duplication/API breaks | [github.com](https://github.com/marcusgoll/atlas-guardrails) |
| Proliferate | Open-source background agent: cron-scheduled cleanup, Sentry triage, auto-PRs | [github.com](https://github.com/proliferate-ai/proliferate) |

## The Three Pillars

### Pillar 1: Context Engineering (weight: 35%)

"Anything the agent can't access in-context doesn't exist." — OpenAI

**What to evaluate:**

| Sub-area | Score 0-10 | What "10" looks like |
|----------|-----------|---------------------|
| Static context | | Versioned AGENTS.md/CLAUDE.md, design specs, architecture maps, execution plans, ADRs |
| Dynamic context | | Live observability (CI status, git state, Sentry, branch health, test impact maps) |
| Tiered documentation | | Progressive loading: quick-start -> rules -> domain knowledge -> specs |
| In-context accessibility | | Semantic search (qmd/RAG), MCP integrations, everything machine-readable |
| Three-tier memory | | Hot memory (constitution), specialist agents (domain experts), cold memory (on-demand specs) |

**Novel benchmark (Codified Context paper):** Knowledge-to-code ratio. A 108K LOC system needed 25K lines of context infrastructure (24.2%). Score proportionally.

### Pillar 2: Architectural Constraints (weight: 35%)

"Increasing trust required constraining the solution space." — Boeckeler/Fowler

| Sub-area | Score 0-10 | What "10" looks like |
|----------|-----------|---------------------|
| Dependency layering | | Enforced sequence with zero bypasses; ArchUnitNET/dependency-cruiser with no ignored tests |
| Deterministic linters as teaching tools | | Error messages include remediation guidance, examples, and principle links |
| LLM-based auditors | | Advisory LLM review on PRs for architectural intent, coupling, doc staleness |
| Structural tests & hooks | | Pre-commit hooks, banned API checks, architecture tests, localization CI |
| Red/Green TDD integration | | Agents required to write failing tests first, confirm failure, then implement (Willison pattern) |
| Constraint credibility | | Zero ignored/skipped tests, or explicit burn-down with owners and expiry dates |

**Key insight (Can Boluk):** Harness format matters more than model choice. Grok went 6.7% -> 68.3% with format change alone.

### Pillar 3: Entropy Management (weight: 30%)

"Entropy management is garbage collection for codebases." — Fowler

| Sub-area | Score 0-10 | What "10" looks like |
|----------|-----------|---------------------|
| Background cleanup agents | | Scheduled agents opening low-risk fix PRs (formatting, regions, log prefixes, deps) |
| Doc consistency verification | | CI verifying CLAUDE.md/PRINCIPLES.md stay synchronized with code reality |
| Constraint violation scanning | | Weekly sweeps: format drift, architecture, TODOs, vulns, duplication, secrets |
| Pattern enforcement | | Dependency drift analysis, ownership-aware rule trends, migration tooling |
| Functional correctness | | End-to-end behavioral tests, not just structural quality (Fowler critique) |

**30/60/90 Day Implementation Roadmap (Epsilla):**
- Days 1-30: Structured docs + custom linting
- Days 31-60: Agent observability + automated acceptance testing
- Days 61-90: Entropy governance + technical debt tracking

## How to Run the Evaluation

### Step 1: Inventory (you do this)

Read the repository's key files to understand current state:
- CLAUDE.md / AGENTS.md / .cursorrules (or equivalent)
- PRINCIPLES.md or similar rules files
- .editorconfig, Directory.Build.props (or equivalent build config)
- CI/CD workflows (.github/workflows/)
- Architecture test projects
- Pre-commit hooks
- Custom analyzers/linters

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
  findings: "<your inventory analysis>"
```

Include in the evaluation prompt:
1. Full inventory of context engineering assets
2. Full inventory of architectural constraints
3. Full inventory of entropy management mechanisms
4. Specific enforcement summary (X/Y rules mechanically enforced)

### Step 3: Synthesize Results

Present a consensus scorecard:

```
| Pillar                    | Model A | Model B | Model C | Consensus |
|---------------------------|---------|---------|---------|-----------|
| Context Engineering       |         |         |         |           |
| Architectural Constraints |         |         |         |           |
| Entropy Management        |         |         |         |           |
| **Overall**               |         |         |         |           |
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

| Metric | Source | What it measures |
|--------|--------|-----------------|
| Knowledge-to-code ratio | Codified Context paper | Lines of agent context / lines of code |
| Principles enforcement % | PRINCIPLES.md | Mechanically enforced / total principles |
| Architecture test health | ArchUnitNET/equiv | Active tests / (active + ignored + skipped) |
| Constraint credibility | All ignored tests | How many "known violations" exist |
| Entropy detection coverage | CI workflows | Scan types running weekly |
| Entropy remediation % | Background agents | Scans that auto-fix vs report-only |
| Tiered doc depth | Context inventory | Number of documentation tiers |

## Industry Benchmarks (2026)

| Organization | Harness Maturity | Notable Achievement |
|-------------|-----------------|---------------------|
| OpenAI (Codex) | Reference implementation | 1M LOC, 1,500 PRs, 5-month harness build |
| Stripe (Minions) | Production-scale | 1,000+ merged PRs/week from agents |
| LangChain | Benchmark-proven | +13.7 points on TerminalBench from harness alone |
| Can Boluk (oh-my-pi) | Open-source exemplar | +5-14 points across 15 models |

## What's New Beyond the Original Article

The community has extended OpenAI's framework in several directions:

1. **Three-tier memory** (Codified Context paper) — hot/specialist/cold is more scalable than single AGENTS.md
2. **Harness > model** (Can Boluk, LangChain) — empirically proven that harness optimization outperforms model upgrades
3. **Functional correctness gap** (Fowler/Boeckeler) — structural quality != behavioral correctness; need e2e tests
4. **Red/Green TDD** (Willison) — test-first development is ideal for agent workflows
5. **Context engineering as discipline** (Karpathy/Lutke) — "the delicate art of filling the context window with just the right information"
6. **Background cleanup agents** (Proliferate, Anthropic trends) — autonomous fix PRs, not just detection
7. **30/60/90 roadmap** (Epsilla) — phased adoption path for organizations
8. **Multi-agent coordination** (Anthropic trends) — 57% of orgs now deploy multi-step agent workflows
9. **Repository intelligence** (Anthropic trends) — AI understanding relationships and intent, not just code
10. **Knowledge-to-code ratio** (Codified Context) — expect ~25% overhead for agent context infrastructure
