---
name: consult-oracles
model: opus
description: Consult GPT-5.4-Pro (smartest) and GPT-5.4 as expert oracles. Use for complex decisions, architecture choices, debugging hard problems, or when user says "consult oracles", "ask the experts", or wants a second opinion.
context: fork
---

# Consult Oracles Skill

Get expert analysis by consulting AI models. `gpt-5.4-pro` is the smartest oracle and the default choice.

## Available Models

| Model | Description | When to Use |
|-------|-------------|-------------|
| `gpt-5.4-pro` | **Smartest oracle** — smarter, more precise responses with advanced reasoning (1M ctx, 128K output) | **Default** — most questions |
| `gpt-5.4` | Most capable model for professional work with reasoning and computer use (1M ctx, 128K output) | When speed matters more than maximum precision |
| `gemini-3.1-pro-preview` | Best at finding bugs and deep analysis, advanced reasoning + thinking mode (1M ctx) | Second opinions, bug hunting, deep code analysis |

**Default:** Use `gpt-5.4-pro`. Fall back to `gpt-5.4` only when the user explicitly prefers speed over quality.

Consult Gemini when:
- You need a second opinion from a different provider
- The user requests multiple perspectives
- The problem involves finding bugs or requires deep code analysis

## When to Use

- Complex architectural decisions
- Debugging difficult problems
- Performance optimization strategies
- Security analysis
- When user says "consult oracles", "ask gpt5", "get expert opinion"
- When you need validation of your approach

## How to Consult

### Primary Consultation (GPT-5.4 with Max Thinking)

For most cases, consult GPT-5.4 with max thinking:

```
mcp__pal__chat with:
- prompt: "<the question/problem to analyze>"
- model: "gpt-5.4"
- working_directory_absolute_path: "<repository root>"
- thinking_mode: "max"
```

### Premium Consultation (GPT-5.4-Pro)

For the hardest problems requiring maximum precision:

```
mcp__pal__chat with:
- prompt: "<the question/problem to analyze>"
- model: "gpt-5.4-pro"
- working_directory_absolute_path: "<repository root>"
- thinking_mode: "high"
```

### With Second Opinion (Multiple Models)

When explicitly requested or needed, use consensus:

```
mcp__pal__consensus with:
- step: "<the question/problem to analyze>"
- models: [
    {"model": "gpt-5.4-pro", "stance": "neutral"},
    {"model": "gemini-3.1-pro-preview", "stance": "neutral"}
  ]
- step_number: 1
- total_steps: 3
- next_step_required: true
- findings: "<your initial analysis>"
```

## Question Formulation

For best results, structure your question:

```
Context: <brief background on the problem>

Current situation: <what's happening now>

Question: <specific question to answer>

Constraints:
- <constraint 1>
- <constraint 2>

Please analyze and provide:
1. Your assessment of the situation
2. Recommended approach
3. Potential risks or concerns
4. Alternative approaches to consider
```

## Handling Responses

### Single Model (Primary)

Trust GPT-5.4's response unless:
- The reasoning seems flawed
- Important constraints were missed
- The answer contradicts well-established patterns
- The problem warrants escalation to GPT-5.4-Pro

### Two Models (With Second Opinion)

When models disagree, prefer GPT-5.4-Pro unless:
- Gemini provides concrete evidence/references
- Gemini's reasoning is clearly more thorough
- The topic is in Gemini's strength area (very large context, multimodal)

### Synthesis Template (When Using Both)

```
## Oracle Consultation Results

### GPT-5.4-Pro Analysis (Primary)
<summary of GPT response>

### Gemini-3.1-Pro Analysis (Second Opinion)
<summary of Gemini response - if consulted>

### Decision
Based on GPT-5.4-Pro's analysis: <recommendation>

<If Gemini was consulted and disagreed>
Note: Gemini suggested <alternative>, but GPT-5.4-Pro's approach is preferred because <reasoning>.
```

## Example Use Cases

### Architecture Decision (Primary - GPT-5.4 Max Thinking)
```
mcp__pal__chat with:
- prompt: "Should we use WebSockets or SSE for our monitoring dashboard?
  Context: ~1000 concurrent users, 500ms update interval, must work through proxies"
- model: "gpt-5.4"
- thinking_mode: "max"
```

### Hard Problem (Premium - GPT-5.4-Pro)
```
mcp__pal__chat with:
- prompt: "Analyze this race condition..."
- model: "gpt-5.4-pro"
- thinking_mode: "high"
```

### Complex Debugging (With Second Opinion)
```
mcp__pal__consensus with models for both perspectives when:
- The bug is particularly elusive
- You want to validate a non-obvious hypothesis
- User explicitly asks for multiple expert opinions
```

## Models Available

| Model | Strengths | When to Use |
|-------|-----------|-------------|
| `gpt-5.4-pro` | Smartest — most precise reasoning, 1M ctx | **Default - most questions** |
| `gpt-5.4` | Most capable, professional work, reasoning + computer use, 1M ctx | When speed matters more |
| `gemini-3.1-pro-preview` | Best at finding bugs and deep analysis, 1M ctx | Bug hunting, deep analysis, second opinion |

## Safety Notes

- Don't share sensitive/proprietary code without approval
- Verify recommendations against project constraints
- Default to GPT-5.4 with max thinking for speed; escalate to GPT-5.4-Pro for precision
- Document which recommendation was chosen and why

## Related Skills
- `/swarm-oracle` — FOR/AGAINST oracle consensus via PAL MCP (pipeline-integrated version)
- `/swarm-oracle-review` — Iterative oracle + agent hardening loop
- `/swarm-review` — Multi-lens review with 10 parallel agents (different from oracle consultation)

