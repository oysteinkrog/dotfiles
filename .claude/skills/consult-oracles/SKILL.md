---
name: consult-oracles
model: fable
description: Consult Fable (primary oracle) for expert second opinions; escalate to GPT-6 Astra (via Codex CLI, configurable reasoning effort) or GPT-5.5-Pro (via PAL) only for extremely important or complex tasks (always paired with Fable). Use for complex decisions, architecture choices, debugging hard problems, or when user says "consult oracles", "ask the experts", or wants a second opinion.
argument-hint: "[--effort low|medium|high|xhigh|max|ultra] <question>"
context: fork
---

# Consult Oracles Skill

Get expert analysis by consulting AI models. **Fable (claude-fable-5) is the primary
oracle and the default choice.** The GPT escalation tier (GPT-6 Astra via Codex CLI,
or GPT-5.5-Pro via PAL) is reserved for extremely important or extremely complex
tasks, and is never used alone: every GPT escalation is paired with a Fable
consultation on the same question.

## Arguments

`$ARGUMENTS` may start with an effort flag for the GPT side:

| Form | Meaning |
|------|---------|
| `--effort <level>` | Reasoning effort for the Astra call. Levels: `low`, `medium`, `high`, `xhigh`, `max`, `ultra`. |
| (no flag) | Default `xhigh`. |

The user may also say it in words ("consult oracles at max effort", "ultra effort").
Treat that as the flag. Strip the flag before using the rest as the question. The
effort only applies to the Codex call; Fable subagents have no effort knob.

## Oracle Hierarchy

| Oracle | How to reach | When to Use |
|--------|--------------|-------------|
| **Fable** (`claude-fable-5`) | Fresh subagent via `Agent` tool with `model: "fable"` | **Default: all oracle consultations (when available)** |
| Opus (fallback) | Fresh subagent via `Agent` tool with `model: "opus"` | Only when the Fable spawn fails. Substitute primary, flagged in the synthesis |
| **GPT-6 Astra** (`gpt-6-astra`) | Codex CLI (see `/codex` skill): `codex exec --sandbox read-only -m gpt-6-astra -c model_reasoning_effort=<effort> "<question>" < /dev/null` | **Preferred GPT escalation.** Extremely important or complex tasks ONLY, always alongside Fable. Not reachable via PAL. Pass the explicit tier ID; do not rely on the bare `gpt-6` alias |
| `gpt-5.5-pro` | `mcp__pal__chat` | Alternate GPT escalation when PAL's structured flow (consensus, continuations) is wanted, or Codex is unavailable. Same pairing rule |
| `gpt-5.6-sol` / `gpt-5.6-terra` | Codex CLI | Rarely; prior-generation GPT probe when the escalation tier is overkill but a GPT view is explicitly wanted |
| `gemini-3.1-pro-preview` | `mcp__pal__chat` | Cross-provider second opinion, bug hunting, deep code analysis |

**Rules:**
1. Default to Fable for every oracle consultation, whenever it is available.
2. **Fable availability fallback:** if the Fable spawn fails (model not accessible on
   the current plan/harness, permission error, or repeated spawn errors), fall back to
   an Opus subagent (`model: "opus"`) as the primary oracle. Say explicitly in your
   synthesis that Opus substituted for Fable. Do not silently downgrade, and do NOT
   treat Fable unavailability as a reason to jump straight to the GPT tier.
3. Escalate to the GPT tier (GPT-6 Astra preferred, GPT-5.5-Pro via PAL as
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

Fable is not available via PAL. Consult it by spawning a fresh subagent with a clean
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

### Premium Escalation (GPT-6 Astra + Fable, always paired)

For extremely important or complex tasks, run BOTH in parallel (single message,
two tool calls). **GPT-6 Astra via Codex CLI is the preferred GPT side** (PAL
tops out at gpt-5.5-pro; GPT-6 is only reachable through Codex):

```
Agent with:                          Bash with:
- subagent_type: "general-purpose"   codex exec --sandbox read-only \
- model: "fable"                       -m gpt-6-astra \
- prompt: "<oracle question>"          -c model_reasoning_effort=<effort> \
                                       -o <scratchpad>/oracle-astra.md \
                                       "<same question>" < /dev/null 2>/dev/null
```

Command details that matter:

- `<effort>` comes from the `--effort` flag (default `xhigh`, see Arguments).
- `< /dev/null` is required. Without a stdin source `codex exec` blocks forever on
  "Reading additional input from stdin" and looks like a slow model.
- `2>/dev/null` drops Codex's stderr noise (MCP transport errors, skill-load
  warnings, sandbox warnings on WSL1). Drop it only to debug a run that returned nothing.
- `-o <file>` captures the final message; read the file instead of parsing stdout.
- Run it from the repo root and make sure that path is trusted in
  `~/.codex/config.toml`; an untrusted worktree blocks on an invisible prompt.
- Put long questions in a prompt file and pass `-` (`codex exec ... - < q.md`)
  instead of a giant positional string.

Follow the `/codex` skill for prompting discipline and exec liveness pitfalls.
Effort guide for the Astra side (all six values verified against `gpt-6-astra`
on 2026-09-04):

- `low` / `medium`: only for a cheap sanity read; not an oracle consultation.
- `high`: hard-but-bounded questions.
- `xhigh`: the default for oracle escalations, genuinely contested questions.
- `max`: deepest single-task reasoning. Use when a prior `xhigh` round came back
  shallow, or the user asks for it.
- `ultra`: fans out subagents. Only when the oracle question itself decomposes
  into parallel sub-analyses: multi-facet architecture reviews (correctness +
  security + ops in one question), evaluations spanning several independent
  subsystems, or "assess all N options" questions. For a single contested
  judgment call, `xhigh` or `max` beats `ultra`: fan-out adds breadth, not
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
works for the PAL-reachable models (GPT-5.5, Gemini). Fable still participates via its
own subagent; synthesize its answer together with the consensus output:

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

For the Fable subagent and the Astra call alike, the prompt must be fully
self-contained (both start with zero session context). Include repo root, relevant
file paths, and any decisions already made. Astra runs with `--sandbox read-only`
and can read the repo, so file paths work there too.

## Handling Responses

### Fable Only (Primary)

Trust Fable's response unless:
- The reasoning seems flawed
- Important constraints were missed
- The answer contradicts well-established patterns
- The problem warrants paired escalation to the GPT tier

### Fable + GPT (Paired Escalation)

When they agree, that convergence is strong evidence. Proceed.
When they disagree, do NOT silently pick one:
- Weigh concrete evidence (references, reproducible reasoning) over confidence
- Consider sending each oracle the other's argument for a rebuttal round
  (`codex exec resume <session-id> "<rebuttal>"` keeps Astra's context; the
  session id is in the run header)
- Surface the disagreement to the user if the decision is high-stakes

### Synthesis Template (When Using Both)

```
## Oracle Consultation Results

### Fable Analysis (Primary)
<summary of Fable response>

### GPT Analysis (Escalation: name the model and effort, e.g. GPT-6 Astra at xhigh)
<summary of GPT response>

### Decision
<recommendation, grounded in whichever reasoning held up>

<If the oracles disagreed>
Disagreement: Fable suggested <X>, GPT suggested <Y>.
Resolution: <which was chosen and the evidence that decided it>.
```

## Example Use Cases

### Architecture Decision (Primary: Fable)
```
Agent with:
- subagent_type: "general-purpose"
- model: "fable"
- prompt: "Independent expert oracle. Should we use WebSockets or SSE for our
  monitoring dashboard? Context: ~1000 concurrent users, 500ms update interval,
  must work through proxies. Repo: /c/work/<project>. Provide assessment,
  recommendation, risks, alternatives."
```

### Extremely Hard Problem (Paired: Fable + GPT-6 Astra)
```
User: /consult-oracles --effort max Analyze this race condition in <file:lines>...

Single message, two parallel tool calls:
1. Agent (model: "fable")  "Analyze this race condition in <file:lines>..."
2. Bash  codex exec --sandbox read-only -m gpt-6-astra \
     -c model_reasoning_effort=max -o <scratchpad>/oracle-astra.md \
     "<same question>" < /dev/null 2>/dev/null
Then synthesize with the template above, naming "GPT-6 Astra at max".
```

### Multi-Facet Review (Paired: Fable + Astra at ultra)
```
User: consult oracles at ultra effort on the proposed sync-service design:
      correctness, security and ops.
Same shape as above with -c model_reasoning_effort=ultra. Ultra is justified
because the question splits into three independent sub-analyses.
```

### Bug Hunting (Cross-Provider: Gemini)
```
mcp__pal__chat with:
- prompt: "Find the bug causing <symptom> in <files>..."
- model: "gemini-3.1-pro-preview"
- thinking_mode: "max"
```

## Safety Notes

- Don't share sensitive/proprietary code without approval (Codex and PAL calls
  leave the machine; Fable subagents stay inside Claude Code)
- Verify recommendations against project constraints
- Document which recommendation was chosen and why, including the Astra effort used
- A GPT-tier consult without a paired Fable consult is a policy violation. Fix it
  before synthesizing

## Related Skills
- `/codex`: Codex CLI mechanics: prompting, models, exec liveness, sandbox rules
- `/swarm-oracle`: FOR/AGAINST oracle consensus (pipeline-integrated version)
- `/swarm-oracle-review`: Iterative oracle + agent hardening loop
- `/swarm-review`: Multi-lens review with 10 parallel agents (different from oracle consultation)
