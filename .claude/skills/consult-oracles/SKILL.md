---
name: consult-oracles
model: fable
description: Consult GPT-6 Astra (primary oracle, via Codex CLI, configurable reasoning effort) for expert second opinions; add Fable as a secondary oracle for high-stakes or contested questions, and use it as the fallback when Codex is unavailable. Use for complex decisions, architecture choices, debugging hard problems, or when user says "consult oracles", "ask the experts", or wants a second opinion.
argument-hint: "[--effort low|medium|high|xhigh|max|ultra] <question>"
context: fork
---

# Consult Oracles Skill

Get expert analysis by consulting AI models. **GPT-6 Astra (`gpt-6-astra`, reached
through the Codex CLI) is the primary oracle and the default choice, used on its
own.** Fable is the secondary oracle: add it when the question is
high-stakes or the answer is contested, and use it as the fallback when Codex or
Astra is unavailable.

## Arguments

`$ARGUMENTS` may start with an effort flag for the Astra call:

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
| **GPT-6 Astra** (`gpt-6-astra`) | Codex CLI (see `/codex` skill): `codex exec --sandbox read-only -m gpt-6-astra -c model_reasoning_effort=<effort> "<question>" < /dev/null` | **Default: all oracle consultations.** Not reachable via PAL. Pass the explicit tier ID; do not rely on the bare `gpt-6` alias |
| **Fable** | Fresh subagent via `Agent` tool with `model: "fable"` | Secondary oracle. Add it for high-stakes or contested questions, when the user asks for a second opinion, or as the primary when Codex/Astra is unreachable |
| Opus (fallback) | Fresh subagent via `Agent` tool with `model: "opus"` | Only when Astra is unreachable and the Fable spawn also fails. Substitute oracle, flagged in the synthesis |
| `gpt-5.5-pro` | `mcp__pal__chat` | When PAL's structured flow (consensus, continuations) is wanted, or Codex is unavailable and a GPT view is still needed |
| `gpt-5.6-sol` / `gpt-5.6-terra` | Codex CLI | Rarely; prior-generation GPT probe |
| `gemini-3.1-pro-preview` | `mcp__pal__chat` | Cross-provider second opinion, bug hunting, deep code analysis |

**Rules:**
1. Default to Astra for every oracle consultation. One Astra call at the right effort
   is the normal shape of a consultation; no pairing is required.
2. **Add Fable as a second oracle** when the decision is high-stakes or hard to
   reverse, when Astra's answer looks uncertain or shallow, or when the user asks for
   a second opinion or multiple perspectives. Put the same self-contained question to
   both and compare. Disagreements between them are the signal.
3. **Astra availability fallback:** if the Codex call fails (Codex missing, path not
   trusted, auth error, empty output after a real attempt), fall back to a Fable
   subagent as the oracle and say so in the synthesis. If Fable also fails, fall back
   to an Opus subagent and say that too. Do not silently downgrade.
4. Sensitive or proprietary code needs approval before it goes to Astra, because the
   Codex call goes to OpenAI. Claude subagents (Fable, Opus) use the same approved
   Anthropic boundary as the session and need no extra approval. If approval is not
   available, run the consultation on Fable instead and note why.

## When to Use

- Complex architectural decisions
- Debugging difficult problems
- Performance optimization strategies
- Security analysis
- When user says "consult oracles", "ask the experts", "get expert opinion"
- When you need validation of your approach

## How to Consult

### Primary Consultation (GPT-6 Astra)

```bash
codex exec --sandbox read-only \
  -m gpt-6-astra \
  -c model_reasoning_effort=<effort> \
  -o <scratchpad>/oracle-astra.md \
  "<self-contained question>" < /dev/null 2>/dev/null
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
- Outside a git repo root, add `--skip-git-repo-check`. Without it `codex exec`
  refuses to start, even when the directory is trusted. This failed an oracle run
  on 2026-09-23.
- Put long questions in a prompt file and pass `-` (`codex exec ... - < q.md`)
  instead of a giant positional string.

Astra runs with `--sandbox read-only` and can read the repo, so include file paths
rather than pasting everything inline. Follow the `/codex` skill for prompting
discipline and exec liveness pitfalls.

Effort guide (all six values verified against `gpt-6-astra` on 2026-09-04):

- `low` / `medium`: only for a cheap sanity read; not an oracle consultation.
- `high`: hard-but-bounded questions.
- `xhigh`: the default for oracle consultations, genuinely contested questions.
- `max`: deepest single-task reasoning. Use when a prior `xhigh` round came back
  shallow, or the user asks for it.
- `ultra`: fans out subagents. Only when the oracle question itself decomposes
  into parallel sub-analyses: multi-facet architecture reviews (correctness +
  security + ops in one question), evaluations spanning several independent
  subsystems, or "assess all N options" questions. For a single contested
  judgment call, `xhigh` or `max` beats `ultra`: fan-out adds breadth, not
  depth, and burns plan quota fast.

### Secondary Consultation (Fable)

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

### Both Oracles (high-stakes or contested)

Run them in parallel: a single message with two tool calls.

```
Bash with:                             Agent with:
codex exec --sandbox read-only \       - subagent_type: "general-purpose"
  -m gpt-6-astra \                     - model: "fable"
  -c model_reasoning_effort=<effort> \ - prompt: "<same question>"
  -o <scratchpad>/oracle-astra.md \
  "<question>" < /dev/null 2>/dev/null
```

### Cross-Provider Second Opinion (Gemini)

Consult Gemini when you need a perspective from a third provider, the user requests
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
works for the PAL-reachable models (GPT-5.5, Gemini). Astra and Fable are not
PAL-reachable; run them with their own calls and synthesize all the answers together:

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

For the Astra call and the Fable subagent alike, the prompt must be fully
self-contained (both start with zero session context). Include repo root, relevant
file paths, and any decisions already made.

## Handling Responses

### Astra Only (the normal case)

Trust Astra's response unless:
- The reasoning seems flawed
- Important constraints were missed
- The answer contradicts well-established patterns
- The decision is high-stakes enough to warrant a Fable second opinion

### Astra + Fable

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

### GPT-6 Astra Analysis (Primary: name the effort, e.g. at xhigh)
<summary of Astra response>

### Fable Analysis (Secondary)
<summary of Fable response>

### Decision
<recommendation, grounded in whichever reasoning held up>

<If the oracles disagreed>
Disagreement: Astra suggested <X>, Fable suggested <Y>.
Resolution: <which was chosen and the evidence that decided it>.
```

## Example Use Cases

### Architecture Decision (Primary: Astra alone)
```
codex exec --sandbox read-only -m gpt-6-astra \
  -c model_reasoning_effort=xhigh -o <scratchpad>/oracle-astra.md \
  "Independent expert oracle. Should we use WebSockets or SSE for our
   monitoring dashboard? Context: ~1000 concurrent users, 500ms update interval,
   must work through proxies. Repo: /c/work/<project>. Provide assessment,
   recommendation, risks, alternatives." < /dev/null 2>/dev/null
```

### Extremely Hard Problem (Astra at max + Fable second opinion)
```
User: /consult-oracles --effort max Analyze this race condition in <file:lines>...

Single message, two parallel tool calls:
1. Bash  codex exec --sandbox read-only -m gpt-6-astra \
     -c model_reasoning_effort=max -o <scratchpad>/oracle-astra.md \
     "<question>" < /dev/null 2>/dev/null
2. Agent (model: "fable")  "<same question>"
Then synthesize with the template above, naming "GPT-6 Astra at max".
```

### Multi-Facet Review (Astra at ultra)
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

- Don't share sensitive/proprietary code without approval (Codex and PAL calls go
  to a non-Anthropic provider; Fable and Opus subagents use the same approved
  Anthropic boundary as the session). Without approval,
  run the consultation on Fable and say why
- Verify recommendations against project constraints
- Document which recommendation was chosen and why, including the Astra effort used
- Never report an oracle result you did not actually get. A failed Codex call means
  fall back and say so, not fill in the answer yourself

## Related Skills
- `/codex`: Codex CLI mechanics: prompting, models, exec liveness, sandbox rules
- `/swarm-oracle`: FOR/AGAINST oracle consensus (pipeline-integrated version)
- `/swarm-oracle-review`: Iterative oracle + agent hardening loop
- `/swarm-review`: Multi-lens review with 10 parallel agents (different from oracle consultation)
