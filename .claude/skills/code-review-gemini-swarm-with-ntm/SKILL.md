---
name: code-review-gemini-swarm-with-ntm
description: >-
  Gemini 3.1 Pro code review swarm via NTM. Use when "gemini review swarm",
  "code review with gemini", or multi-round code auditing with Gemini agents.
---

<!-- TOC: Overview | Arguments | Orchestration | Agent Lifecycle | Monitoring Cron | Prompt Bank | Flash Detection | Tracking Files | Anti-Patterns | Troubleshooting -->

# Code Review Gemini Swarm with NTM

> **Core flow:** Spawn N Gemini 3.1 Pro agents via NTM, run a three-phase review cycle per agent, repeat the explore+cross-review phases 3 times per agent to exploit prompt caching, then kill and relaunch for the next round. Monitor the swarm every 3 minutes via CronCreate.

> **Model policy:** ONLY use `gemini-3.1-pro-preview`. NEVER accept a downgrade to Flash. If Gemini offers to switch to Flash, that agent is done -- retire it immediately.

> **Role clarity:** In mixed swarms, Gemini agents are **review-only**. They explore, find bugs, and fix them -- they do NOT pick beads, claim work from bv, or do feature implementation. Claude/Codex handle implementation; Gemini audits their output.

## Arguments

Parse from the skill invocation text. Defaults:

| Argument | Default | Description |
|----------|---------|-------------|
| `--agents=N` or first bare number | 5 | Number of Gemini agents to spawn |
| `--rounds=N` or second bare number | 10 | Maximum rounds (kill/relaunch cycles) |

Examples: `/code-review-gemini-swarm-with-ntm`, `/code-review-gemini-swarm-with-ntm 8 5`, `/code-review-gemini-swarm-with-ntm --agents=3 --rounds=20`

## Prerequisites

This skill requires **NTM** (Named Tmux Manager) and **Gemini CLI** (`@google/gemini-cli`).

### Gemini CLI Setup

NTM launches Gemini agents using the `gemini` binary. To ensure the correct model and auto-approval mode, verify your NTM config (`~/.config/ntm/config.toml`) has:

```toml
[models]
default_gemini = "gemini-3.1-pro-preview"

[agents]
gemini = "gemini{{if .Model}} --model {{shellQuote .Model}}{{end}} --yolo"
```

Also configure `~/.gemini/settings.json` to prevent auto-routing to Flash:

```json
{
  "model": { "name": "gemini-3.1-pro-preview" },
  "general": { "plan": { "modelRouting": false } }
}
```

**If NTM is not installed:**
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh?$(date +%s)" | bash -s -- --easy-mode
```

**If Gemini CLI is not installed:**
```bash
npm install -g @google/gemini-cli
# or: bun install -g @google/gemini-cli
```

## Pre-Flight

1. Determine **PROJECT** from the current working directory basename.
2. Verify NTM: `ntm deps -v`
3. Check for existing session: `ntm list --json 2>/dev/null | grep -q "$PROJECT"`. If one exists, ask user whether to reuse or kill and recreate.

## Phase 0: Spawn the Swarm

```bash
ntm spawn $PROJECT \
  --gmi=$NUM_AGENTS:gemini-3.1-pro-preview \
  --no-user \
  --stagger-mode=smart
```

Wait for agents to be ready:

```bash
ntm --robot-wait=$PROJECT --condition=idle --timeout=120
```

If spawn fails, check `ntm --robot-diagnose=$PROJECT` and report to user.

## Phase 1: Set Up the Monitoring Cron

Immediately after spawning, create a recurring 3-minute monitoring cron using `CronCreate`:

```
CronCreate(
  cron: "*/3 * * * *",
  recurring: true,
  prompt: "Check on the Gemini review swarm for project $PROJECT. Run: ntm --robot-is-working=$PROJECT and ntm --robot-tail=$PROJECT --lines=80 --type=gmi. Review the output critically -- read what the agents are actually finding and assess quality of their reviews. Report: (1) which agents are actively working vs idle vs rate-limited, (2) any Flash fallback detection (look for exact string 'Switched to fallback model' in tail output -- retire those agents immediately), (3) brief summary of what the agents are finding/fixing and whether their findings look substantive or superficial. If agents are idle and waiting for their next prompt, advance them to the next step per the orchestration loop. If all agents are rate-limited or retired, cancel this cron and report final results."
)
```

Save the returned job ID so it can be cancelled later via `CronDelete` when the swarm finishes.

This cron is the **heartbeat** of the orchestration. Every 3 minutes it fires while you are idle, you check swarm health, feed the next prompt to any agent that has become idle, and retire any agent that hit rate limits or offered Flash. **Critically review the agents' output** -- don't just check status, read what they're finding and assess whether it's real bugs vs noise.

## Phase 2: Orchestration Loop

For each round (1 to MAX_ROUNDS):

### Per-Agent Lifecycle Within a Round

Each agent goes through this sequence within a single round before being killed and relaunched:

```
Prompt 1 (once):  Study the project
Prompt 2 (x3):   Explore + review with fresh eyes
Prompt 3 (x3):   Cross-review other agents' code
Prompt 4 (between iterations): Short continuation nudge
```

That is: **1 study prompt, then 3 iterations of the explore+cross-review pair** = 7 core prompts per agent per round. Between iterations, use the short continuation prompt to nudge agents into new areas. This exploits prompt caching -- the agent already has the codebase context loaded.

Track each agent's position in this sequence (e.g., `agent_1: step=explore_2`, `agent_3: step=cross_review_1`).

#### Prompt 1: Study the Project (once per round)

Send to all Gemini agents at the start of each round:

```bash
ntm send $PROJECT --gmi "First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project."
```

Wait for idle, then advance to the explore+review cycle.

#### Prompt 2: Explore and Review (send 3 times per round)

```bash
ntm send $PROJECT --gmi "I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with \"fresh eyes\" to find any obvious bugs, problems, errors, issues, silly mistakes, etc. and then systematically and meticulously and intelligently correct them. Be sure to comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in the AGENTS.md file."
```

Wait for idle, then send the cross-review prompt.

#### Prompt 3: Cross-Review (send 3 times per round)

Always prefix with "Reread AGENTS.md so it is still fresh in your mind" -- this is critical because Gemini agents' context can drift after deep exploration:

```bash
ntm send $PROJECT --gmi "Reread AGENTS.md so it is still fresh in your mind. Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!"
```

Wait for idle. If this was iteration < 3, send the continuation nudge then go back to Prompt 2.

#### Prompt 4: Continuation Nudge (between iterations)

Use this shorter prompt between explore+cross-review cycles to push agents into unexplored territory:

```bash
ntm send $PROJECT --pane=N "Continue your code review. Explore more code files, trace execution flows, and look for bugs or issues. Be thorough and methodical."
```

This battle-tested continuation prompt is short, which helps with context budget, and the agent already has full codebase understanding.

### Advancing Agents via the Cron

The monitoring cron fires every 3 minutes. On each fire:

1. **Check agent states:** `ntm --robot-is-working=$PROJECT`
2. **For each idle agent:** determine where it is in the prompt sequence and send the next prompt. Use `ntm send $PROJECT --pane=N` to target specific agents.
3. **For rate-limited/Flash agents:** retire them (stop sending prompts, note in status).
4. **Critically review output:** Read the tail of what agents are producing. Are they finding real bugs? Doing useful refactors? Or just narrating code they read? If an agent is producing low-quality output, note it in the round summary.
5. **Report progress** to user concisely.

Agents advance asynchronously -- faster agents get their next prompt sooner. You do NOT need to wait for all agents to finish a step before advancing individual ones.

### End of Round: Kill and Relaunch

When ALL agents in the round have completed their 7-prompt sequence (or been retired):

1. **Capture output:**
   ```bash
   ntm --robot-tail=$PROJECT --lines=200 --type=gmi
   ```

2. **Check for clean reviews:** Scan output for indicators that no issues were found. If ALL active agents report clean on their last cross-review pass, stop early.

3. **Kill the session and relaunch** for the next round:
   ```bash
   ntm --robot-restart-pane=$PROJECT --type=gmi
   ```
   Wait for agents to be ready again, then start the next round from Prompt 1.

4. **Report round summary** to user: round number, agents active vs retired, key findings, quality assessment of the reviews.

## Gemini Tracking Files

Gemini agents naturally produce tracking and summary files during review sessions. These are valuable artifacts:

| File | Purpose |
|------|---------|
| `GEMINI_REVIEW_SUMMARY.md` | Per-agent review findings summary |
| `GEMINI_FIXES.md`, `GEMINI_FIXES_2.md`, etc. | Numbered fix logs across iterations |
| `GEMINI_FINAL_REPORT.md` | Consolidated final findings |
| `GEMINI_STATUS.md` | Agent's self-tracked progress |
| `FIXES_SUMMARY.md` | Cross-agent fix documentation |

**Do NOT instruct agents to delete these files.** If your project's AGENTS.md has a no-deletion rule (recommended), it will block this automatically. Gemini agents sometimes try to clean up their own tracking files -- be aware this is a known behavior.

When reviewing round output, check these files for structured findings that may not appear in the tail output.

## Termination Conditions

Stop the entire loop and cancel the monitoring cron (`CronDelete`) when ANY of:

- All rounds completed (hit MAX_ROUNDS)
- All agents are rate-limited or offering Flash (none left to work)
- All agents report clean reviews on the last cross-review of a round (convergence)

## After Completion

1. **Cancel the monitoring cron:** `CronDelete(id: $JOB_ID)`

2. **Capture final state:**
   ```bash
   ntm --robot-snapshot
   ntm --robot-tail=$PROJECT --lines=100 --type=gmi
   ```

3. **Check for tracking files** the agents may have written:
   ```bash
   ls -la GEMINI_*.md FIXES_SUMMARY.md SESSION_TODO.md 2>/dev/null
   ```
   Read and summarize any findings documented there.

4. **Report to user:**
   - How many rounds completed
   - How many agents hit rate limits / were retired
   - Whether reviews converged to clean
   - Summary of key findings/fixes across all rounds
   - Quality assessment: were the reviews substantive or superficial?

5. **Do NOT kill the session** -- leave for user inspection via `ntm view $PROJECT` or `ntm dashboard $PROJECT`.

## Rate Limit and Flash Detection

After each wait or on each cron fire, check:

```bash
ntm --robot-is-working=$PROJECT
ntm --robot-tail=$PROJECT --lines=50 --type=gmi
```

### Exact Flash Fallback Strings

Gemini emits these exact strings when hitting usage limits (from 10+ real sessions):

```
Switched to fallback model gemini-3-flash-preview
Switched to fallback model gemini-2.5-flash
```

Also scan for:
- `summary.rate_limited_count` > 0 in the is-working JSON
- `"state": "rate_limited"` or `"recommendation": "wait"` per pane

**If an agent shows any Flash fallback string:** retire it immediately. Track which panes are retired. Send prompts only to active panes via `--pane=N`.

**If ALL agents retired:** terminate the loop.

## Anti-Patterns (from real sessions)

### Gemini Tries to Delete Its Own Files
Gemini agents often try to delete `GEMINI_REVIEW_SUMMARY.md` when they create a "better" `GEMINI_FINAL_REPORT.md`. If your AGENTS.md has a no-deletion rule, it blocks this automatically. You'll see the agent reasoning about it in output. This is normal.

### Superficial Reviews After Many Iterations
After 2-3 explore passes on the same codebase, agents start narrating code rather than finding bugs. The continuation nudge prompt helps push them to new areas, but diminishing returns are real. This is why the skill kills and relaunches rather than sending infinite prompts to the same session.

### Context Drift on Cross-Review
Without the "Reread AGENTS.md" prefix, Gemini agents forget repo-specific rules during cross-review and may make changes that violate project conventions. Always include the prefix.

### Agent Stuck in "Communication Purgatory"
If Gemini is registered with Agent Mail, it sometimes gets trapped reading/writing messages instead of reviewing code. For review-only swarms, the agents should NOT register with Agent Mail or pick beads -- they are pure auditors.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `ntm spawn` fails to resolve project | Check `ntm config get projects_base`, ensure cwd is under it |
| Agents stuck, never idle | Increase `--timeout`, check `ntm --robot-diagnose=$PROJECT` |
| All agents immediately rate-limited | Gemini quota exhausted; wait or use different accounts |
| Flash fallback despite model lock | Check `~/.gemini/settings.json` has `modelRouting: false` and that `gemini` is launched with `--model gemini-3.1-pro-preview` (see Prerequisites) |
| Cron not firing | Verify cron was created: `CronList`. Cron only fires while REPL is idle |
| Agents producing low-quality reviews | Normal after 2-3 iterations on same codebase; this is why we kill/relaunch between rounds |
| NTM not installed | See Prerequisites section above |

## Reference Index

| Topic | Reference |
|-------|-----------|
| Full prompt bank with all variants, sequencing patterns, and situational overrides | [PROMPTS.md](references/PROMPTS.md) |
| Quality assessment rubric, real bug examples, operator decision tree, mixed swarm ratios | [OPERATIONS.md](references/OPERATIONS.md) |
