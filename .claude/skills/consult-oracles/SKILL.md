---
name: consult-oracles
description: Consult GPT-6 Astra (primary oracle and default reviewer, Codex CLI at effort medium, one bounded prompt) for expert second opinions. Add Fable only for security reviews or contested questions, or when Astra is unavailable. Use Opus when both fail. Gemini 4 Argon (via PAL) is the optional third oracle but is currently unavailable. Use for complex decisions, architecture choices, debugging hard problems, or when user says "consult oracles", "ask the experts", or wants a second opinion.
argument-hint: "[--effort low|medium|high|xhigh|max|ultra] <question>"
context: fork
---

# Consult Oracles Skill

Get expert analysis by consulting AI models. **GPT-6 Astra (`gpt-6-astra`, reached
through the Codex CLI at effort `medium`) is the primary oracle and the default
choice, used on its own.** Fable (a fresh subagent spawned with the `Agent` tool and
`model: "fable"`) is the secondary oracle: add it for security reviews and contested
calls (Astra's answer looks wrong, or two oracles disagree), or use it when Codex
fails. Opus is the last fallback when both fail.

Why Astra first (Oystein, 2026-10-24, widened to all reviews on 2026-10-28): the
three OpenAI accounts ended the week at about 26% to 31% with reset credits unused,
while four Claude accounts hit 100% and two more passed 90%.

Guard rails (from 2026-10-22 and 2026-10-24): high-effort Astra reviews on whole
repos used up all three OpenAI accounts in about 90 minutes, and a reading cap
written in the prompt did not hold. So Astra runs at `medium`, gets one bounded
prompt of about 60k tokens with the excerpts pasted in, runs from an empty directory
with its shell tools off, and at most 4 runs go at once. If any OpenAI account passes
70% of its week before its reset, go back to Fable first.

## Arguments

`$ARGUMENTS` may start with an effort flag. It applies only when Astra is consulted:

| Form | Meaning |
|------|---------|
| `--effort <level>` | Reasoning effort for the Astra call. Levels: `low`, `medium`, `high`, `xhigh`, `max`, `ultra`. |
| (no flag) | Default `medium`. |

The user may also say it in words ("consult oracles at high effort"). Treat that as
the flag. Strip the flag before using the rest as the question. Fable subagents have
no effort knob, so the flag does nothing on a Fable-only consultation. Use `high` only
for one high-stakes question, and say why.

## Oracle Hierarchy

| Oracle | How to reach | When to Use |
|--------|--------------|-------------|
| **GPT-6 Astra** (`gpt-6-astra`) | Codex CLI (see `/codex` skill): `codex exec -m gpt-6-astra -c model_reasoning_effort=<effort> "<question>" < /dev/null` | **Default: every oracle consultation, second opinion and PR, plan, bead or code review.** Effort `medium`, one bounded prompt (see Bounded Astra run). Not reachable via PAL. Pass the explicit tier ID; do not rely on the bare `gpt-6` alias |
| **Fable** | Fresh subagent via `Agent` tool with `model: "fable"` | Secondary oracle. Add it for security reviews and contested calls (Astra looks wrong, or two oracles disagree), or use it when Codex fails |
| Opus (fallback) | Fresh subagent via `Agent` tool with `model: "opus"` | Only when Fable and Astra both fail. Substitute oracle, flagged in the synthesis |
| `gpt-5.5-pro` | `mcp__pal__chat` | When PAL's structured flow (consensus, continuations) is wanted and a GPT view is needed |
| `gpt-5.6-sol` / `gpt-5.6-terra` | Codex CLI | Rarely; prior-generation GPT probe |
| **Gemini 4 Argon** (`gemini-4-argon`) | `mcp__pal__chat` with `model: "gemini-4-argon"` | Optional third oracle from Google. **Currently unavailable:** the AI Studio prepay credit ran out on 2026-10-21 and Oystein chose to leave it off. Do not rely on it |
| `gemini-3.1-pro-preview` | `mcp__pal__chat` | Only when the Argon call fails. Flag the substitution. Same credit, so also unavailable for now |

**Rules:**
1. Default to Astra for every oracle consultation and every review. One bounded Astra
   run at `medium` is the normal shape; no pairing is required. Run at most 4 Astra
   runs at once. Use `high` only for a high-stakes single question, and say why.
2. **Add Fable as a second oracle** for a security review, when Astra's answer looks
   wrong, when two oracles disagree, or when the user asks for a cross-provider
   opinion. Put the same self-contained question to both and compare. Disagreements
   between them are the signal.
3. **Astra availability fallback:** if the Codex call fails (Codex missing, path not
   trusted, auth error, rate limit, empty output after a real attempt), consult Fable
   instead and say so in the synthesis. If Fable also fails, fall back to an Opus
   subagent and say that too. Do not silently downgrade.
4. **Gemini 4 Argon** is the optional third oracle, a different provider with
   different training. It is currently unavailable (see the table), so do not plan a
   consultation around it. When it is back, add it for high-stakes decisions or when
   Fable and Astra disagree.
5. Anthropic (Fable, Opus), OpenAI (Astra through Codex) and Google (Gemini through
   PAL) are all approved providers, so proprietary code can go to any of these
   oracles without asking first. Any other provider reached through PAL still needs
   approval.
6. **Keep the cost rules.** Short briefs. Paste the needed excerpts in; do not let an
   oracle explore the repo. Review only the change delta. One review per
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

### Primary Consultation (GPT-6 Astra): the bounded run

Build one prompt file of about 60k tokens at most: the brief (see Question
Formulation), the diff, and the file excerpts Astra needs, pasted in with their paths
and line numbers. Then run it from an empty directory with the shell tools off, so
Astra answers from the prompt and cannot browse the tree:

```bash
mkdir -p /var/tmp/claude/<task>/astra-empty && cd /var/tmp/claude/<task>/astra-empty
codex exec -m gpt-6-astra -c model_reasoning_effort=<effort> \
  --disable shell_tool --disable unified_exec --skip-git-repo-check \
  -o <scratchpad>/oracle-astra.md - < <scratchpad>/astra-prompt.md 2>/dev/null
```

Command details that matter:

- `<effort>` comes from the `--effort` flag (default `medium`, see Arguments).
- `- < prompt.md` feeds the prompt on stdin. Without a stdin source `codex exec`
  blocks forever on "Reading additional input from stdin" and looks like a slow model.
- `--disable shell_tool --disable unified_exec` turns off file reading (probe-verified
  2026-10-24). A reading cap written in the prompt does not hold: on 2026-10-24
  reviewers told to stop at about 40 reads ran 100 to 756 each.
- `--skip-git-repo-check` is required outside a git repo root, which the empty
  directory is. Without it `codex exec` refuses to start.
- `2>/dev/null` drops Codex's stderr noise. Drop it only to debug a run that returned
  nothing.
- `-o <file>` captures the final message; read the file instead of parsing stdout.
  An empty file after exit 0 means the run failed: use the fallback.
- At most 4 Astra runs at once. Background them with Claude Code's own
  `run_in_background`, not `nohup ... &`.

An answer that cites no excerpt was given too little. Add the missing excerpt and
rerun; do not turn file reading back on. Follow the `/codex` skill for prompting
discipline and exec liveness pitfalls.

Effort guide (all six values verified against `gpt-6-astra` on 2026-09-04):

- `low`: a cheap sanity read only.
- `medium`: the default for every Astra run.
- `high`: a high-stakes single question, with the reason stated.
- `xhigh` / `max`: only when Oystein asks for it. A high-effort review used most of
  the OpenAI weekly room on 2026-10-22.
- `ultra`: fans out subagents and burns plan quota fast. Only when Oystein asks for
  it and the question splits into independent sub-analyses.

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

  <the same self-contained question, following the Question Formulation template
  below, with the files to read named>"
```

Name the files it should read; an open-ended "look around the repo" brief is slow
and expensive. If Fable also fails, run the same prompt on an Opus subagent
(`model: "opus"`) and flag it in the synthesis.

### Both Oracles (security review or contested call)

Run them in parallel: a single message with two tool calls.

```
Bash with:                             Agent with:
cd /var/tmp/claude/<task>/astra-empty  - subagent_type: "general-purpose"
codex exec -m gpt-6-astra \            - model: "fable"
  -c model_reasoning_effort=medium \   - prompt: "<same question>"
  --disable shell_tool \
  --disable unified_exec \
  --skip-git-repo-check \
  -o <scratchpad>/oracle-astra.md \
  - < <scratchpad>/astra-prompt.md 2>/dev/null
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

For the Astra run and the Fable subagent alike, the prompt must be fully
self-contained (both start with zero session context). For Astra, paste in the
excerpts it needs with paths and line numbers; for Fable, name the files to read.
State any decisions already made. For a review, give the change delta (the diff), not
the whole module.

## Handling Responses

### Astra Only (the normal case)

Trust Astra's response unless:
- The reasoning seems flawed or looks wrong
- Important constraints were missed
- The answer contradicts well-established patterns
- The answer cites none of the pasted excerpts
- The question is a security review, which gets a Fable cross-check

### Astra + Fable

When they agree, that convergence is strong evidence. Proceed.
When they disagree, do NOT silently pick one:
- Weigh concrete evidence (references, reproducible reasoning) over confidence
- Consider sending each oracle the other's argument for a rebuttal round
  (`codex exec resume <session-id> "<rebuttal>"` keeps Astra's context, and the
  session id is in the run header; `SendMessage` to the Fable subagent keeps its)
- Surface the disagreement to the user if the decision is high-stakes

### Synthesis Template (When Using Both)

```
## Oracle Consultation Results

### GPT-6 Astra Analysis (Primary: name the effort, e.g. at medium)
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
astra-prompt.md:
  "Independent expert oracle. Should we use WebSockets or SSE for our
   monitoring dashboard? Context: ~1000 concurrent users, 500ms update interval,
   must work through proxies. Excerpts below: src/dashboard/server.rs:1-180 and
   src/dashboard/client.ts:1-120. Provide assessment, recommendation, risks,
   alternatives."
Run it with the bounded command above at medium.
```

### Security Review (Astra + Fable)
```
User: /consult-oracles Is this token check in <file:lines> bypassable?

Single message, two parallel tool calls:
1. Bash   the bounded Astra run at medium, excerpts pasted in
2. Agent  (model: "fable") "<same question, with the files named>"
Then synthesize with the template above, naming "GPT-6 Astra at medium".
```

### Astra Answer Looks Wrong (add Fable)
```
Astra says a lock ordering change cannot deadlock, but its reasoning skips a path.
Send the same brief to Fable as a cross-provider check, then synthesize both.
Escalate Astra to high only for one high-stakes question, and say why.
```

## Safety Notes

- Proprietary code may go to Anthropic (Fable, Opus), OpenAI (Codex, and GPT models
  through PAL) and Google (Gemini models through PAL) without asking first. Any other
  provider reached through PAL needs approval. Without it, run the consultation on
  Astra or Fable and say why
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
