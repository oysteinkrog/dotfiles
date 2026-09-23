# Harness Engineering: Research Background

Background reading for the harness-eval skill. The skill itself does not need this file to run an evaluation. Use it for sources, benchmarks and other scoring frameworks.

### Origin & Key References

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

### Industry Benchmarks (2026)

| Organization | Harness Maturity | Notable Achievement |
|-------------|-----------------|---------------------|
| OpenAI (Codex) | Reference implementation | 1M LOC, 1,500 PRs, 5-month harness build |
| Stripe (Minions) | Production-scale | 1,300+ merged PRs/week; one-shot design; 6-layer harness |
| LangChain | Benchmark-proven | +13.7 points on TerminalBench from harness alone |
| Can Boluk (oh-my-pi) | Open-source exemplar | +5-14 points across 15 models |
| Typical enterprise | 2-4/10 | AGENTS.md + basic CI only |

### Alternative Scoring Frameworks

The three-pillar model is the foundational framing but has been extended:

| Framework | Pillars | Criteria | Differentiator |
|-----------|---------|----------|---------------|
| OpenAI Three Pillars (this eval) | 3 | ~18 sub-areas | Original; most widely referenced |
| Factory.ai Agent Readiness | 8 | 60+ binary | Most comprehensive; automated remediation PRs |
| OpenAI Agent Legibility Scorecard | 7 | Letter grades | Most practical; includes Decision Records |
| ContextCov | 3 enforcement domains | 46K+ checks | Most rigorous; AST-checkable constraints |
| agent-ready.org | 9 | 5 maturity levels | Free open-source Factory.ai clone |

### What's New Beyond the Original Article

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
