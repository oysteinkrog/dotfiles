---
name: consult-oracles
model: fable
description: Consult Fable (primary oracle, a fresh subagent with a short self-contained brief) for expert second opinions; add GPT-6 Astra (via Codex CLI, default effort medium) as a cross-provider check for high-stakes or contested questions, or when Fable is unavailable; Opus is the fallback when both fail. Gemini 4 Argon (via PAL) is the optional third oracle but is currently unavailable. Use for complex decisions, architecture choices, debugging hard problems, or when user says "consult oracles", "ask the experts", or wants a second opinion.
argument-hint: "[--effort low|medium|high|xhigh|max|ultra] <question>"
context: fork
---

# Consult Oracles Skill

Get expert analysis by consulting AI models. **Fable (a fresh subagent spawned with
the `Agent` tool and `model: "fable"`) is the primary oracle and the default choice,
used on its own.** GPT-6 Astra (`gpt-6-astra`, reached through the Codex CLI) is the
secondary oracle: add it for high-stakes or contested questions, as a cross-provider
check when Fable's answer looks uncertain, or use it when Fable is unavailable.

Why Fable first (Oystein, 2026-10-22): there are 16 Claude subscription accounts and
3 OpenAI accounts, so Claude has far more weekly room. On 2026-10-22 Astra used about
20 weekly points an hour (about 22M tokens in 90 minutes, mostly high-effort reviews)
and nearly used up all three OpenAI accounts until 10-26 to 10-28.

## Arguments

`$ARGUMENTS` may start with an effort flag. It applies only when Astra is consulted:

| Form | Meaning |
|------|---------|
| `--effort <level>` | Reasoning effort for the Astra call. Levels: `low`, `medium`, `high`, `xhigh`, `max`, `ultra`. |
| (no flag) | Default `medium`. |

The user may also say it in words ("consult oracles at high effort"). Treat that as
the flag. Strip the flag before using the rest as the question. Fable subagents have
no effort knob, so the flag does nothing on a Fable-only consultation. An effort flag
above `medium` is also a request to add Astra.

## Oracle Hierarchy

| Oracle | How to reach | When to Use |
|--------|--------------|-------------|
| **Fable** | Fresh subagent via `Agent` tool with `model: "fable"` | **Default: every oracle consultation, second opinion and review round.** Short, self-contained brief with a bounded reading list |
| **GPT-6 Astra** (`gpt-6-astra`) | Codex CLI (see `/codex` skill): `codex exec --sandbox read-only -m gpt-6-astra -c model_reasoning_effort=<effort> "<question>" < /dev/null` | Secondary oracle. Add it for high-stakes or contested questions, as a cross-provider check when Fable's answer looks uncertain, or use it when Fable is unavailable. Not reachable via PAL. Pass the explicit tier ID; do not rely on the bare `gpt-6` alias |
| Opus (fallback) | Fresh subagent via `Agent` tool with `model: "opus"` | Only when Fable and Astra both fail. Substitute oracle, flagged in the synthesis |
| `gpt-5.5-pro` | `mcp__pal__chat` | When PAL's structured flow (consensus, continuations) is wanted and a GPT view is needed |
| `gpt-5.6-sol` / `gpt-5.6-terra` | Codex CLI | Rarely; prior-generation GPT probe |
| **Gemini 4 Argon** (`gemini-4-argon`) | `mcp__pal__chat` with `model: "gemini-4-argon"` | Optional third oracle from Google. **Currently unavailable:** the AI Studio prepay credit ran out on 2026-10-21 and Oystein chose to leave it off. Do not rely on it |
| `gemini-3.1-pro-preview` | `mcp__pal__chat` | Only when the Argon call fails. Flag the substitution. Same credit, so also unavailable for now |

**Rules:**
1. Default to Fable for every oracle consultation. One Fable subagent with a short,
   self-contained brief is the normal shape of a consultation; no pairing is required.
2. **Add Astra as a second oracle** when the decision is high-stakes or hard to
   reverse, when Fable's answer looks uncertain or shallow, when the question is
   contested, or when the user asks for a cross-provider opinion. Put the same
   self-contained question to both and compare. Disagreements between them are the
   signal. Astra runs at `medium` effort by default. Use `high` only for a high-stakes
   single question with a bounded file list.
3. **Fable availability fallback:** if the Fable spawn fails (model unavailable,
   empty result after a real attempt), consult Astra instead and say so in the
   synthesis. If Astra also fails (Codex missing, path not trusted, auth error, empty
   output), fall back to an Opus subagent and say that too. Do not silently downgrade.
4. **Gemini 4 Argon** is the optional third oracle, a different provider with
   different training. It is currently unavailable (see the table), so do not plan a
   consultation around it. When it is back, add it for high-stakes decisions or when
   Fable and Astra disagree.
5. Anthropic (Fable, Opus), OpenAI (Astra through Codex) and Google (Gemini through
   PAL) are all approved providers, so proprietary code can go to any of these
   oracles without asking first. Any other provider reached through PAL still needs
   approval.
6. **Keep the cost rules.** Short briefs. Bounded reading lists: name the files, do not
   let an oracle explore the whole repo. Review only the change delta. One review per
   change: a backport or cherry-pick with the same `git patch-id --stable` as an
   already reviewed commit gets no second review.

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
  including the relevant file paths so the agent can read them>"
```

The subagent can read the repo, so include file paths rather than pasting everything
inline. Name the files it should read; an open-ended "look around the repo" brief is
slow and expensive.

### Secondary Consultation (GPT-6 Astra)

```bash
codex exec --sandbox read-only \
  -m gpt-6-astra \
  -c model_reasoning_effort=<effort> \
  -o <scratchpad>/oracle-astra.md \
  "<self-contained question>" < /dev/null 2>/dev/null
```

Command details that matter:

- `<effort>` comes from the `--effort` flag (default `medium`, see Arguments).
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
discipline and exec liveness pitfalls. Give it a bounded reading list by name: Astra
let loose on a big repo can run long and return nothing.

Effort guide (all six values verified against `gpt-6-astra` on 2026-09-04):

- `low`: a cheap sanity read only.
- `medium`: the default for an Astra consultation.
- `high`: a high-stakes single question with a bounded file list.
- `xhigh` / `max`: only when Oystein asks for it. A high-effort review used most of
  the OpenAI weekly room on 2026-10-22.
- `ultra`: fans out subagents and burns plan quota fast. Only when Oystein asks for
  it and the question splits into independent sub-analyses.

### Both Oracles (high-stakes or contested)

Run them in parallel: a single message with two tool calls.

```
Agent with:                            Bash with:
- subagent_type: "general-purpose"     codex exec --sandbox read-only \
- model: "fable"                         -m gpt-6-astra \
- prompt: "<question>"                   -c model_reasoning_effort=<effort> \
                                         -o <scratchpad>/oracle-astra.md \
                                         "<same question>" < /dev/null 2>/dev/null
```

### Third Oracle (Gemini 4 Argon, currently unavailable)

Gemini 4 Argon is off since 2026-10-21 (AI Studio prepay credit used up; Oystein chose
to leave it off). Skip this section until he turns it back on. When it is available,
consult Argon for a third provider's view, when Fable and Astra disagree, or for bug
hunting and deep code analysis:

```
mcp__pal__chat with:
- prompt: "<the question/problem to analyze>"
- model: "gemini-4-argon"
- working_directory_absolute_path: "<repository root>"
- thinking_mode: "max"
```

Argon reads 1M tokens of input but writes at most 32K tokens per reply. For a long
review, ask for findings only, not rewritten files. If `mcp__pal__chat` is missing,
PAL is not registered in this session: run `claude mcp list` and see the PAL section
of the dotfiles README.

### Consensus (Multiple PAL Models)

When the user explicitly wants a structured multi-model debate, `mcp__pal__consensus`
works for the PAL-reachable models (GPT-5.5, and Gemini 4 Argon when it is back).
Fable and Astra are not PAL-reachable; run them with their own calls and synthesize
all the answers together:

```
mcp__pal__consensus with:
- step: "<the question/problem to analyze>"
- models: [
    {"model": "gpt-5.5-pro", "stance": "neutral"},
    {"model": "gemini-4-argon", "stance": "neutral"}
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
self-contained (both start with zero session context). Include repo root, the files to
read by name, and any decisions already made. For a review, give the change delta
(a commit range or diff), not the whole module.

## Handling Responses

### Fable Only (the normal case)

Trust Fable's response unless:
- The reasoning seems flawed
- Important constraints were missed
- The answer contradicts well-established patterns
- The answer is hedged or uncertain on a decision that matters
- The decision is high-stakes enough to warrant an Astra cross-provider check

### Fable + Astra

When they agree, that convergence is strong evidence. Proceed.
When they disagree, do NOT silently pick one:
- Weigh concrete evidence (references, reproducible reasoning) over confidence
- Consider sending each oracle the other's argument for a rebuttal round
  (`SendMessage` to the Fable subagent keeps its context;
  `codex exec resume <session-id> "<rebuttal>"` keeps Astra's, and the session id is
  in the run header)
- Surface the disagreement to the user if the decision is high-stakes

### Synthesis Template (When Using Both)

```
## Oracle Consultation Results

### Fable Analysis (Primary)
<summary of Fable response>

### GPT-6 Astra Analysis (Secondary: name the effort, e.g. at medium)
<summary of Astra response>

### Decision
<recommendation, grounded in whichever reasoning held up>

<If the oracles disagreed>
Disagreement: Fable suggested <X>, Astra suggested <Y>.
Resolution: <which was chosen and the evidence that decided it>.
```

## Example Use Cases

### Architecture Decision (Primary: Fable alone)
```
Agent (model: "fable"):
  "Independent expert oracle. Should we use WebSockets or SSE for our
   monitoring dashboard? Context: ~1000 concurrent users, 500ms update interval,
   must work through proxies. Repo: /c/work/<project>. Read only
   src/dashboard/server.rs and src/dashboard/client.ts. Provide assessment,
   recommendation, risks, alternatives."
```

### Extremely Hard Problem (Fable + Astra at high)
```
User: /consult-oracles --effort high Analyze this race condition in <file:lines>...

Single message, two parallel tool calls:
1. Agent (model: "fable")  "<question, with the bounded file list>"
2. Bash  codex exec --sandbox read-only -m gpt-6-astra \
     -c model_reasoning_effort=high -o <scratchpad>/oracle-astra.md \
     "<same question>" < /dev/null 2>/dev/null
Then synthesize with the template above, naming "GPT-6 Astra at high".
```

### Fable Answer Looks Uncertain (add Astra at medium)
```
Fable hedges on whether a lock ordering change can deadlock.
Send the same brief to Astra at medium effort as a cross-provider check, then
synthesize both. Escalate to high only if the question is high-stakes and the file
list is bounded.
```

## Safety Notes

- Proprietary code may go to Anthropic (Fable, Opus), OpenAI (Codex, and GPT models
  through PAL) and Google (Gemini models through PAL) without asking first. Any other
  provider reached through PAL needs approval. Without it, run the consultation on
  Fable and say why
- Verify recommendations against project constraints
- Document which recommendation was chosen and why, including which oracles ran and
  the Astra effort if Astra was used
- Never report an oracle result you did not actually get. A failed Fable spawn or
  Codex call means fall back and say so, not fill in the answer yourself

## Related Skills
- `/codex`: Codex CLI mechanics: prompting, models, exec liveness, sandbox rules
- `/swarm-oracle`: FOR/AGAINST oracle consensus (pipeline-integrated version)
- `/swarm-oracle-review`: Iterative oracle + agent hardening loop
- `/swarm-review`: Multi-lens review with 10 parallel agents (different from oracle consultation)
