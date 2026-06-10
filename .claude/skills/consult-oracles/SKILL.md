---
name: consult-oracles
model: fable
description: Consult Fable (primary oracle) for expert second opinions; escalate to GPT-5.5-Pro only for extremely important or complex tasks (always paired with Fable). Use for complex decisions, architecture choices, debugging hard problems, or when user says "consult oracles", "ask the experts", or wants a second opinion.
context: fork
---

# Consult Oracles Skill

Get expert analysis by consulting AI models. **Fable (claude-fable-5) is the primary
oracle and the default choice.** GPT-5.5-Pro is reserved for extremely important or
extremely complex tasks, and is never used alone — every GPT-Pro consultation is
paired with a Fable consultation on the same question.

## Oracle Hierarchy

| Oracle | How to reach | When to Use |
|--------|--------------|-------------|
| **Fable** (`claude-fable-5`) | Fresh subagent via `Agent` tool with `model: "fable"` | **Default — all oracle consultations** |
| `gpt-5.5-pro` | `mcp__pal__chat` | Extremely important or complex tasks ONLY — and always alongside Fable |
| `gpt-5.5` | `mcp__pal__chat` | Rarely; cheaper GPT probe when Pro is overkill but a GPT view is explicitly wanted |
| `gemini-3.1-pro-preview` | `mcp__pal__chat` | Cross-provider second opinion, bug hunting, deep code analysis |

**Rules:**
1. Default to Fable for every oracle consultation.
2. Escalate to GPT-5.5-Pro only when the task is extremely important (high-stakes,
   hard-to-reverse decisions) or extremely complex (Fable's answer is uncertain or
   the problem resisted a first Fable pass).
3. **Never consult GPT-Pro alone.** When GPT-Pro is used, ALWAYS also put the same
   question to Fable and compare. Disagreements between them are the signal.

## When to Use

- Complex architectural decisions
- Debugging difficult problems
- Performance optimization strategies
- Security analysis
- When user says "consult oracles", "ask the experts", "get expert opinion"
- When you need validation of your approach

## How to Consult

### Primary Consultation (Fable)

Fable is not available via PAL — consult it by spawning a fresh subagent with a clean
context. The fresh context is the point: it gives an independent read, not an echo of
the current session.

```
Agent with:
- subagent_type: "general-purpose"
- model: "fable"
- prompt: "You are acting as an independent expert oracle. Do not assume any
  prior context beyond what is in this prompt.

  <self-contained question, following the Question Formulation template below,
  including all relevant code/file paths so the agent can read them>"
```

The subagent can read the repo, so include file paths rather than pasting everything inline.

### Premium Escalation (GPT-5.5-Pro + Fable, always paired)

For extremely important or complex tasks, run BOTH in parallel (single message,
two tool calls):

```
Agent with:                          mcp__pal__chat with:
- subagent_type: "general-purpose"   - prompt: "<same question>"
- model: "fable"                     - model: "gpt-5.5-pro"
- prompt: "<oracle question>"        - working_directory_absolute_path: "<repo root>"
                                     - thinking_mode: "high"
```

Never fire the GPT-Pro call without the matching Fable call.

### Cross-Provider Second Opinion (Gemini)

Consult Gemini when you need a perspective from a different provider, the user requests
multiple perspectives, or the problem involves bug hunting / deep code analysis:

```
mcp__pal__chat with:
- prompt: "<the question/problem to analyze>"
- model: "gemini-3.1-pro-preview"
- working_directory_absolute_path: "<repository root>"
- thinking_mode: "max"
```

### Consensus (Multiple PAL Models)

When the user explicitly wants a structured multi-model debate, `mcp__pal__consensus`
works for the PAL-reachable models (GPT, Gemini). Fable still participates via its own
subagent; synthesize its answer together with the consensus output:

```
mcp__pal__consensus with:
- step: "<the question/problem to analyze>"
- models: [
    {"model": "gpt-5.5-pro", "stance": "neutral"},
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

For the Fable subagent, the prompt must be fully self-contained (it starts with zero
session context) — include repo root, relevant file paths, and any decisions already made.

## Handling Responses

### Fable Only (Primary)

Trust Fable's response unless:
- The reasoning seems flawed
- Important constraints were missed
- The answer contradicts well-established patterns
- The problem warrants paired escalation to GPT-5.5-Pro

### Fable + GPT-5.5-Pro (Paired Escalation)

When they agree, that convergence is strong evidence — proceed.
When they disagree, do NOT silently pick one:
- Weigh concrete evidence (references, reproducible reasoning) over confidence
- Consider sending each oracle the other's argument for a rebuttal round
- Surface the disagreement to the user if the decision is high-stakes

### Synthesis Template (When Using Both)

```
## Oracle Consultation Results

### Fable Analysis (Primary)
<summary of Fable response>

### GPT-5.5-Pro Analysis (Escalation)
<summary of GPT response>

### Decision
<recommendation, grounded in whichever reasoning held up>

<If the oracles disagreed>
Disagreement: Fable suggested <X>, GPT-5.5-Pro suggested <Y>.
Resolution: <which was chosen and the evidence that decided it>.
```

## Example Use Cases

### Architecture Decision (Primary — Fable)
```
Agent with:
- subagent_type: "general-purpose"
- model: "fable"
- prompt: "Independent expert oracle. Should we use WebSockets or SSE for our
  monitoring dashboard? Context: ~1000 concurrent users, 500ms update interval,
  must work through proxies. Repo: /c/work/<project>. Provide assessment,
  recommendation, risks, alternatives."
```

### Extremely Hard Problem (Paired — Fable + GPT-5.5-Pro)
```
Single message, two parallel tool calls:
1. Agent (model: "fable") — "Analyze this race condition in <file:lines>..."
2. mcp__pal__chat (model: "gpt-5.5-pro", thinking_mode: "high") — same question
Then synthesize with the template above.
```

### Bug Hunting (Cross-Provider — Gemini)
```
mcp__pal__chat with:
- prompt: "Find the bug causing <symptom> in <files>..."
- model: "gemini-3.1-pro-preview"
- thinking_mode: "max"
```

## Safety Notes

- Don't share sensitive/proprietary code without approval (PAL calls leave the machine;
  Fable subagents stay inside Claude Code)
- Verify recommendations against project constraints
- Document which recommendation was chosen and why
- GPT-Pro without a paired Fable consult is a policy violation — fix it before synthesizing

## Related Skills
- `/swarm-oracle` — FOR/AGAINST oracle consensus via PAL MCP (pipeline-integrated version)
- `/swarm-oracle-review` — Iterative oracle + agent hardening loop
- `/swarm-review` — Multi-lens review with 10 parallel agents (different from oracle consultation)
