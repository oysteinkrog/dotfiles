---
name: consult-oracles
model: fable
description: Consult Fable (primary oracle) for expert second opinions; escalate to GPT-5.6 Sol (via Codex CLI) or GPT-5.5-Pro (via PAL) only for extremely important or complex tasks (always paired with Fable). Use for complex decisions, architecture choices, debugging hard problems, or when user says "consult oracles", "ask the experts", or wants a second opinion.
context: fork
---

# Consult Oracles Skill

Get expert analysis by consulting AI models. **Fable (claude-fable-5) is the primary
oracle and the default choice.** The GPT escalation tier (GPT-5.6 Sol via Codex CLI,
or GPT-5.5-Pro via PAL) is reserved for extremely important or extremely complex
tasks, and is never used alone — every GPT escalation is paired with a Fable
consultation on the same question.

## Oracle Hierarchy

| Oracle | How to reach | When to Use |
|--------|--------------|-------------|
| **Fable** (`claude-fable-5`) | Fresh subagent via `Agent` tool with `model: "fable"` | **Default — all oracle consultations (when available)** |
| Opus (fallback) | Fresh subagent via `Agent` tool with `model: "opus"` | Only when the Fable spawn fails — substitute primary, flagged in the synthesis |
| **GPT-5.6 Sol** (`gpt-5.6-sol`) | Codex CLI (see `/codex` skill): `codex exec --sandbox read-only -m gpt-5.6-sol -c model_reasoning_effort=xhigh "<question>"` — `ultra` instead of `xhigh` for decomposable questions | **Preferred GPT escalation** — extremely important or complex tasks ONLY, always alongside Fable. NOT reachable via PAL; explicit tier ID required (bare `gpt-5.6` hangs) |
| `gpt-5.5-pro` | `mcp__pal__chat` | Alternate GPT escalation when PAL's structured flow (consensus, continuations) is wanted, or Codex is unavailable — same pairing rule |
| `gpt-5.6-terra` / `gpt-5.5` | Codex CLI / `mcp__pal__chat` | Rarely; cheaper GPT probe when the escalation tier is overkill but a GPT view is explicitly wanted |
| `gemini-3.1-pro-preview` | `mcp__pal__chat` | Cross-provider second opinion, bug hunting, deep code analysis |

**Rules:**
1. Default to Fable for every oracle consultation, whenever it is available.
2. **Fable availability fallback:** if the Fable spawn fails (model not accessible on
   the current plan/harness, permission error, or repeated spawn errors), fall back to
   an Opus subagent (`model: "opus"`) as the primary oracle. Say explicitly in your
   synthesis that Opus substituted for Fable — do not silently downgrade. Do NOT treat
   Fable unavailability as a reason to jump straight to GPT-Pro.
3. Escalate to the GPT tier (GPT-5.6 Sol preferred, GPT-5.5-Pro via PAL as
   alternate) only when the task is extremely important (high-stakes,
   hard-to-reverse decisions) or extremely complex (Fable's answer is uncertain or
   the problem resisted a first Fable pass).
4. **Never consult the GPT tier alone.** When it is used, ALWAYS also put the same
   question to Fable (or the Opus fallback) and compare. Disagreements between them
   are the signal.

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

### Premium Escalation (GPT + Fable, always paired)

For extremely important or complex tasks, run BOTH in parallel (single message,
two tool calls). **GPT-5.6 Sol via Codex CLI is the preferred GPT side** (PAL
tops out at gpt-5.5-pro; GPT-5.6 is only reachable through Codex):

```
Agent with:                          Bash with:
- subagent_type: "general-purpose"   codex exec --sandbox read-only \
- model: "fable"                       -m gpt-5.6-sol \
- prompt: "<oracle question>"          -c model_reasoning_effort=xhigh \
                                       -o <scratchpad>/oracle-gpt.md \
                                       "<same question>" 2>/dev/null
```

Follow the `/codex` skill for prompting discipline, exec liveness pitfalls, and
model details. Effort guide for the GPT side:

- `high` — hard-but-bounded questions.
- `xhigh` — the default for oracle escalations: genuinely contested questions.
- `max` — only when a prior `xhigh` round came back shallow.
- `ultra` (Sol Ultra, subagent fan-out) — only when the oracle question itself
  decomposes into parallel sub-analyses: multi-facet architecture reviews
  (correctness + security + ops in one question), evaluations spanning several
  independent subsystems, or "assess all N options" questions. For a single
  contested judgment call, `xhigh` beats `ultra` — fan-out adds breadth, not
  depth, and burns plan quota fast.

Fall back to `mcp__pal__chat` with `model: "gpt-5.5-pro"`, `thinking_mode: "high"`
when Codex is unavailable or you specifically want PAL's conversation
continuations / consensus flow.

Never fire the GPT escalation call without the matching Fable call.

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
- The problem warrants paired escalation to the GPT tier

### Fable + GPT (Paired Escalation)

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

### GPT Analysis (Escalation — name the model used, e.g. GPT-5.6 Sol)
<summary of GPT response>

### Decision
<recommendation, grounded in whichever reasoning held up>

<If the oracles disagreed>
Disagreement: Fable suggested <X>, GPT suggested <Y>.
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

### Extremely Hard Problem (Paired — Fable + GPT-5.6 Sol)
```
Single message, two parallel tool calls:
1. Agent (model: "fable") — "Analyze this race condition in <file:lines>..."
2. Bash — codex exec --sandbox read-only -m gpt-5.6-sol \
     -c model_reasoning_effort=xhigh "<same question>" 2>/dev/null
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
- A GPT-tier consult without a paired Fable consult is a policy violation — fix it before synthesizing
- Codex `codex exec` oracle calls and PAL calls both leave the machine (OpenAI API); Fable subagents stay inside Claude Code

## Related Skills
- `/swarm-oracle` — FOR/AGAINST oracle consensus via PAL MCP (pipeline-integrated version)
- `/swarm-oracle-review` — Iterative oracle + agent hardening loop
- `/swarm-review` — Multi-lens review with 10 parallel agents (different from oracle consultation)
