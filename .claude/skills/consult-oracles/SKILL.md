---
name: consult-oracles
description: Consult oracles for expert second opinions. Decision consults (design choices, tricky root causes, "which approach?", plans, research questions) ask two oracles in parallel by default, GPT-6.2 Astra (Codex CLI, effort medium, one bounded prompt) and Gemini 4 Neon (PAL on Vertex AI, capped at $250 a month), and Fable breaks ties when they disagree. Reviews (PR, security, bead or plan verify) stay Astra alone. Fable is the fallback when Astra or Neon is unavailable, then Opus. Gemini 4 Carbon is the rare fourth (ultra) oracle, only on request. Use for complex decisions, architecture choices, debugging hard problems, or when user says "consult oracles", "ask the experts", or wants a second opinion.
argument-hint: "[--effort low|medium|high|xhigh|max|ultra] <question>"
context: fork
---

# Consult Oracles Skill

Get expert analysis by consulting AI models. There are two default shapes:

- **Decision consults ask two oracles in parallel:** GPT-6.2 Astra
  (`gpt-6.2-astra`, Codex CLI at effort `medium`) and Gemini 4 Neon
  (`gemini-4-neon`, PAL on Vertex AI). Both get the same short, self-contained
  brief. A decision consult is a design choice, the root cause of a tricky bug, a
  "which approach?" question, a plan, a research question, or anything where a new
  idea or a second view matters.
- **Reviews use Astra alone:** PR review, security review, bead or plan polish
  verify. Add Neon to a review only when judging English text or a design matters:
  docs, user-facing text, plain-language reviews, plan or PRD reviews. Never add
  Neon to a security review.

Fable 5.2 (`claude-fable-5-2`, a fresh subagent spawned with the `Agent` tool and
`model: "fable"`, which resolves to 5.2) is the **tiebreaker**: consult it when
Astra and Neon disagree on something that matters. It is also the fallback when
Astra or Neon is unavailable. Opus is the last fallback.

Why two oracles (Oystein, 2026-11-23): the oracles are there to give a different
view, not only a stronger model. Astra and Neon come from different providers and
reason differently, so two of them find more than one. Fable is no longer added
just because a decision is high-stakes; it breaks ties.

Why Astra first (Oystein, 2026-10-24, widened to all reviews on 2026-10-28): the
three OpenAI accounts ended the week at about 26% to 31% with reset credits unused,
while four Claude accounts hit 100% and two more passed 90%.

Guard rails (from 2026-10-22 and 2026-10-24): high-effort Astra reviews on whole
repos used up all three OpenAI accounts in about 90 minutes, and a reading cap
written in the prompt did not hold. So Astra runs at `medium`, gets one bounded
prompt of about 60k tokens with the excerpts pasted in, runs from an empty directory
with its shell tools off, and at most 4 runs go at once. Go back to Fable first only
when every routable OpenAI account is past 70% of its week (Oystein, 2026-11-09: aiolos
fills one account before the next).

Neon budget (2026-11-23): Neon is paid per use on Vertex AI, about $0.20 for a
typical 40k-token call ($3 in and $15 out per 1M tokens). The "Gemini oracles
(Vertex AI)" budget is $250 a month. At the cap the `gemini-budget-stop` function
turns off billing and Neon calls fail; then use Astra plus Fable. Keep Neon briefs
bounded like Astra's (about 60k tokens at most, never a whole repo), and never call
Neon in a loop from an automated pipeline.

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
| **GPT-6.2 Astra** (`gpt-6.2-astra`) | Codex CLI, always the bounded command under "Bounded Astra run" (empty folder, `--disable shell_tool --disable unified_exec --disable code_mode_host`, prompt on stdin). A PreToolUse hook (`astra-guard.py`) blocks Astra with the shell tool on | **Default for every consult and every review.** In a decision consult it runs beside Neon; in a review it runs alone. Effort `medium`, one bounded prompt (see Bounded Astra run). Not reachable via PAL. Pass the explicit tier ID; do not rely on the bare `gpt-6` alias |
| **Fable 5.2** (`claude-fable-5-2`) | Fresh subagent via `Agent` tool with `model: "fable"` (the alias resolves to 5.2; checked 2026-11-09) | Tiebreaker when Astra and Neon disagree on something that matters. Fallback when Astra or Neon is unavailable |
| Opus (fallback) | Fresh subagent via `Agent` tool with `model: "opus"` | Only when Fable also fails. Substitute oracle, flagged in the synthesis |
| `gpt-5.5-pro` | `mcp__pal__chat` | When PAL's structured flow (consensus, continuations) is wanted and a GPT view is needed |
| `gpt-6.2-sol` / `gpt-6.1-terra` | Codex CLI | Rarely; a faster GPT probe (Sol for code, Terra for images and computer use) |
| **Gemini 4 Neon** (`gemini-4-neon`, released 2026-11-18) | `mcp__pal__chat` with `model: "gemini-4-neon"` | **Default second oracle in every decision consult**, run in parallel with Astra. In reviews only for English text or design (docs, user-facing text, plain-language, plan or PRD reviews), never for security. $3 in and $15 out per 1M tokens, capped at $250 a month. Runs through Vertex AI (see below) |
| **Gemini 4 Carbon** (`gemini-4-carbon`, released 2026-11-10) | `mcp__pal__chat` with `model: "gemini-4-carbon"` | Fourth oracle, the "ultra" option: Google's top Gemini 4 tier. Use it only when Oystein asks for it. $2 in and $10 out per 1M tokens, but long thinking at `max` makes each call large. Runs through Vertex AI |
| `gemini-4-argon` | `mcp__pal__chat` | Older Gemini 4 model. Only when a Neon or Carbon call fails on the model itself. Flag the substitution |

**Rules:**
1. **Decision consults ask Astra and Neon in parallel**, with the same
   self-contained brief, in one message. If they agree, act. Run at most 4 Astra
   runs at once. Use Astra `high` only for one high-stakes question, and say why.
2. **Reviews use Astra alone**: one bounded run at `medium`. Add Neon only for
   reviews of English text or a design (docs, user-facing text, plain-language, plan
   or PRD reviews). Never add Neon to a security review.
3. **Fable breaks ties.** When Astra and Neon disagree on something that matters,
   send Fable the brief and both answers in one short consult. Fable is no longer
   added just because a call is high-stakes.
4. **Fallbacks:** if the Codex call fails (Codex missing, path not trusted, auth
   error, rate limit, empty output after a real attempt), or a Neon call fails
   (auth, budget cap reached, model error), consult Fable in its place and say so
   in the synthesis. If Fable also fails, use an Opus subagent and say that too. Do
   not silently downgrade. When every routable OpenAI account is past 70% of its
   week, Fable takes Astra's place.
5. **Gemini 4 Carbon** is the rare fourth ("ultra") oracle. Use it only when
   Oystein asks for it.
6. Anthropic (Fable, Opus), OpenAI (Astra through Codex) and Google (Gemini through
   PAL) are all approved providers, so proprietary code can go to any of these
   oracles without asking first. Any other provider reached through PAL still needs
   approval.
7. **Keep the cost rules.** Short briefs. Paste the needed excerpts in; do not let an
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

### Primary Consultation (GPT-6.2 Astra): the bounded run

Build one prompt file of about 60k tokens at most: the brief (see Question
Formulation), the diff, and the file excerpts Astra needs, pasted in with their paths
and line numbers. Then run it from an empty directory with the shell tools off, so
Astra answers from the prompt and cannot browse the tree:

```bash
mkdir -p /var/tmp/claude/<task>/astra-empty && cd /var/tmp/claude/<task>/astra-empty
codex exec -m gpt-6.2-astra -c model_reasoning_effort=<effort> \
  --disable shell_tool --disable unified_exec --disable code_mode_host \
  --skip-git-repo-check \
  -o <scratchpad>/oracle-astra.md - < <scratchpad>/astra-prompt.md 2>/dev/null
```

Command details that matter:

- `<effort>` comes from the `--effort` flag (default `medium`, see Arguments).
- `- < prompt.md` feeds the prompt on stdin. Without a stdin source `codex exec`
  blocks forever on "Reading additional input from stdin" and looks like a slow model.
- `--disable shell_tool --disable unified_exec --disable code_mode_host` turns off file
  reading. All three are needed: with only the first two, Astra still runs shell
  commands through the JavaScript tool (`tools.exec_command`). On 2026-10-30 one
  review that way made 12 such calls and read 433k (probe-verified that day). A reading cap written in the prompt does not hold: on 2026-10-24
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

Effort guide (`gpt-6.2-astra` accepted `low`, `medium`, `xhigh` and `max` on 2026-11-18 and
rejected `none` and `minimal`):

- `low`: a cheap sanity read only.
- `medium`: the default for every Astra run.
- `high`: a high-stakes single question, with the reason stated.
- `xhigh` / `max`: only when Oystein asks for it. A high-effort review used most of
  the OpenAI weekly room on 2026-10-22.
- `ultra`: fans out subagents and burns plan quota fast. Only when Oystein asks for
  it and the question splits into independent sub-analyses.

### Tiebreaker and Fallback Consultation (Fable)

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
  below, with the files to read named>

  <as tiebreaker: both oracle answers, labelled, and the point they disagree on>"
```

Name the files it should read; an open-ended "look around the repo" brief is slow
and expensive. If Fable also fails, run the same prompt on an Opus subagent
(`model: "opus"`) and flag it in the synthesis.

### Decision Consult (Astra and Neon in parallel)

Run them in parallel: a single message with two tool calls and the same brief.

```
Bash with:                             mcp__pal__chat with:
cd /var/tmp/claude/<task>/astra-empty  - prompt: "<same brief, same excerpts>"
codex exec -m gpt-6.2-astra \            - model: "gemini-4-neon"
  -c model_reasoning_effort=medium \   - working_directory_absolute_path:
  --disable shell_tool \                   "<repository root>"
  --disable unified_exec \             - thinking_mode: "max"
  --disable code_mode_host \
  --skip-git-repo-check \
  -o <scratchpad>/oracle-astra.md \
  - < <scratchpad>/astra-prompt.md 2>/dev/null
```

Paste the excerpts into the Neon prompt too, and do not ask Neon to read files, so
its input stays bounded like Astra's.

### Gemini 4 Neon and Carbon (PAL)

PAL sends Gemini calls through Vertex AI (Cloud project `gen-lang-client-0138044607`, billed after use) with Application Default Credentials. If a call fails with an auth or reauthentication error, ask Oystein to run `gcloud auth application-default login` (the old AI Studio key has no prepaid credit and returns 402; set up 2026-11-20).
Neon is the default second oracle in decision consults (see above). Use Carbon
(`model: "gemini-4-carbon"`) the same way, but only as the fourth oracle when
Oystein asks for it:

```
mcp__pal__chat with:
- prompt: "<the question/problem to analyze>"
- model: "gemini-4-neon"
- working_directory_absolute_path: "<repository root>"
- thinking_mode: "max"
```

Gemini 4 models read 1M tokens of input. Neon writes at most 64K tokens per reply, Carbon and Argon 32K (from the Gemini models API, 2026-11-20). For a long
review, ask for findings only, not rewritten files. If `mcp__pal__chat` is missing,
PAL is not registered in this session: run `claude mcp list` and see the PAL section
of the dotfiles README.

### Consensus (Multiple PAL Models)

When the user explicitly wants a structured multi-model debate, `mcp__pal__consensus`
works for the PAL-reachable models (GPT-5.5, Gemini 4 Neon and Carbon).
Fable and Astra are not PAL-reachable; run them with their own calls and synthesize
all the answers together:

```
mcp__pal__consensus with:
- step: "<the question/problem to analyze>"
- models: [
    {"model": "gpt-5.5-pro", "stance": "neutral"},
    {"model": "gemini-4-neon", "stance": "neutral"}
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

### Astra Alone (reviews)

Trust Astra's review unless:
- The reasoning seems flawed or looks wrong
- Important constraints were missed
- The answer contradicts well-established patterns
- The answer cites none of the pasted excerpts

If one of these holds, send the same brief to Fable as a cross-check.

### Astra + Neon (decision consults)

When they agree, that convergence is strong evidence. Act on it.
When they disagree on something that matters, do NOT silently pick one:
- Weigh concrete evidence (references, reproducible reasoning) over confidence
- Ask Fable to break the tie: one short consult with the brief, both answers and
  the point in dispute
- If Fable does not settle it, consider a rebuttal round
  (`codex exec resume <session-id> "<rebuttal>"` keeps Astra's context, and the
  session id is in the run header; PAL's `continuation_id` keeps Neon's), then take
  it to Oystein if they still disagree
- A difference in emphasis that does not change the decision is not a
  disagreement. Note it and act

### Synthesis Template (Decision Consult)

```
## Oracle Consultation Results

### GPT-6.2 Astra Analysis (name the effort, e.g. at medium)
<summary of Astra response>

### Gemini 4 Neon Analysis
<summary of Neon response>

### Fable Tiebreak (only if they disagreed)
<summary of Fable response>

### Decision
<recommendation, grounded in whichever reasoning held up>

<If the oracles disagreed>
Disagreement: Astra suggested <X>, Neon suggested <Y>.
Resolution: <which was chosen, Fable's view, and the evidence that decided it>.
```

## Example Use Cases

### Architecture Decision (Astra + Neon)
```
astra-prompt.md (the same text goes to Neon):
  "Independent expert oracle. Should we use WebSockets or SSE for our
   monitoring dashboard? Context: ~1000 concurrent users, 500ms update interval,
   must work through proxies. Excerpts below: src/dashboard/server.rs:1-180 and
   src/dashboard/client.ts:1-120. Provide assessment, recommendation, risks,
   alternatives."
Single message: the bounded Astra run at medium and mcp__pal__chat with
gemini-4-neon. If they disagree on the choice, ask Fable with both answers.
```

### Security Review (Astra alone)
```
User: /consult-oracles Is this token check in <file:lines> bypassable?

One bounded Astra run at medium, excerpts pasted in. No Neon.
If Astra's reasoning looks wrong, send the same brief to Fable as a cross-check.
```

### Astra and Neon Disagree
```
Astra says a lock ordering change cannot deadlock; Neon names a path that can.
Send Fable the brief, both answers and the disputed path. Act on the answer whose
reasoning holds up, and say which oracle Fable sided with.
```

## Safety Notes

- Proprietary code may go to Anthropic (Fable, Opus), OpenAI (Codex, and GPT models
  through PAL) and Google (Gemini models through PAL) without asking first. Any other
  provider reached through PAL needs approval. Without it, run the consultation on
  Astra, Neon or Fable and say why
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
