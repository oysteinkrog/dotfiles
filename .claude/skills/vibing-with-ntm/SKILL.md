---
name: vibing-with-ntm
description: >-
  Tend NTM agent swarms: orchestrator loop, marching orders, autonomous recovery of stuck or rate-limited panes, review-only mode, and work coordination via Agent Mail, Beads, and BV.
---

<!-- TOC: Decision Tree | Quick Start | The Attention-Feed Loop | Marching Orders | Swarm Loop | Operator Loop | Autonomous Unstick | Observability | Steady-State Cadence | Quality Loops | Coordination | Anti-Patterns | Troubleshooting | References | Related Skills -->

> **If you are tending a swarm right now:** jump to the [Orchestrator Decision Tree](#orchestrator-decision-tree) below. Drop into [Autonomous Unstick](#autonomous-unstick--dont-wait-for-the-human) for recovery recipes. Everything else is context.

## Orchestrator Decision Tree

Run one tick. Pick the FIRST branch whose condition fires.

```
Is CURSOR expired (or missing)?
  → ntm --robot-snapshot  (resync, get new cursor); continue next tick.

Is ANY pane rate_limited?  (check via --robot-health-oauth, NOT pane buffer text)
  → See OC-001 & OC-002 in references/OPERATOR-CARDS.md.
    Probe: tmux send-keys "ping" Enter; sleep 5; --robot-tail.
    Rotate: ntm rotate <session> --all-limited.
    Or switch: ntm --robot-switch-account=<provider>:<account>.

Is ANY pane stuck (identical tail ≥3 ticks, zero output growth)?
  → Climb the stuck-pane ladder (see OC-003 in OPERATOR-CARDS.md):
    wake-ping → C-u + send → smart-restart → hard-kill → restart-pane → add+kill.

Is there prose-without-commits? (pane is_working=true but git log 1h=0)
  → Dispatch OC-004 Ship-or-Surface prompt (see PROMPTS.md).

Is context >85% on any pane?
  → Dispatch handoff-then-restart (OC-009).

Is there a file-reservation conflict or coordinator-reported collision?
  → Force-release too-broad patterns (OC-008); mediate via bead status-flip (OC-015).

Does convergence triple-check hold?
  ( git log 1h=0 AND br ready=0 AND in-flight unchanged ≥2 ticks AND convergence language in every pane )
  → STOP. Do not nudge. Exit the loop; report final state.

Otherwise — one specific-terse nudge per genuinely-idle pane (OC-010). Then wait.
```

Every card (OC-###) and anti-pattern (AP-###) is documented with recipe, prompt module, and validator. See [OPERATOR-CARDS.md](references/OPERATOR-CARDS.md) and [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md).

# Vibing With NTM

> **Core flow:** understand the repo -> pick work intelligently -> coordinate explicitly -> keep agents moving -> review relentlessly.

> **Core insight:** every agent is fungible, but the swarm only works when work selection, reservations, mail, and operator tending all stay aligned.

> **Human vs agent surfaces:**
> - Humans can use `ntm dashboard`, `ntm palette`, `ntm view`, and other interactive surfaces.
> - Agents should avoid interactive TUIs and prefer `--robot-*` for structured state.
> - Non-interactive commands such as `ntm send`, `ntm work triage`, `ntm mail inbox`, `ntm locks list`, and `ntm assign` are still valid operator tools.

> **Isolation model:**
> - Default: Agent Mail file reservations plus clear bead ownership.
> - Optional: `--worktrees` when the repo policy allows it and branch/worktree isolation is useful.
> - Repo-local `AGENTS.md` always wins if it prefers or forbids a specific coordination model.

## Quick Start

```bash
# 1. Prerequisites
ntm deps -v
br ready
bv --robot-triage

# 2. Start a manageable swarm
ntm spawn myproject --cc=3 --cod=2 --gmi=1

# 3. Send marching orders
ntm send myproject --all "$(cat marching_orders.txt)"

# 4. Watch the swarm
ntm dashboard myproject
ntm --robot-snapshot
```

Scale up only when the operator loop is under control.

## Marching Orders

### Start-of-Session Prompt

Send a prompt like this to every agent at session start:

```text
Before doing anything else, read all of AGENTS.md and README.md and understand both. Then inspect the codebase enough to understand the project purpose, architecture, and the specific workflows that matter for the current repo.

Register with MCP Agent Mail if the repo expects it, introduce yourself to the other agents, and check for any existing messages or active coordination threads. If the repo uses Beads and BV, use them to find ready work and pick the next bead you can usefully advance now.

Do not get stuck in communication purgatory. Announce what you are taking on, reserve the relevant files or worktree scope, start doing real work, keep your bead status current, and reply promptly to important agent mail.

If the repo AGENTS.md has special rules for builds, tests, lints, or remote execution helpers such as rch, follow those rules exactly.
```

### Next-Bead Prompt (steady-state, no AGENTS.md re-read)

```text
Pick one open/claimed bead you can fully complete in under 60 minutes — prefer the top of `bv --robot-triage`. Claim it (br update <id> --status=in_progress), reserve the files you will edit, code the diff, verify, commit, close the bead, and move on. Do not file new review beads unless you find a real defect that blocks you. Do not write prose mental models or subsystem walkthroughs — ship the commit or surface an explicit blocker within one hour.
```

Drop the "Reread AGENTS.md" preamble from every steady-state nudge — it costs ~30s/tick per agent in context and gives zero value once the session is running. Keep it only for the first dispatch and for post-compaction resumption.

### Explicit domain assignment (critical for ≥3 agents in one workspace)

At session start, tell each pane what it owns so they don't collide:

```text
You are pane-N, owner of <crate/directory domain>. Do not edit outside your domain without reserving the files first and announcing in your dispatch prompt. Your ready-work search is scoped to issues tagged or pathed inside this domain.
```

For the fuller prompt bank — including code-review, post-compaction, exploration, commit-only, "stop prose ship commits", "close the backlog", terse steady-state nudges, and the autonomous-unstick operator prompts — read [PROMPTS.md](references/PROMPTS.md).

## The Swarm Loop

```text
1. Read repo instructions and current docs
2. Register / check Agent Mail if the repo uses it
3. Use bv --robot-triage or ntm work triage
4. Claim a bead and reserve files or a worktree scope
5. Implement
6. Self-review and fix obvious issues
7. Update bead status and coordination thread
8. Pick the next ready task
```

Key commands:

```bash
bv --robot-triage
bv --robot-next
ntm work triage
ntm work next
ntm assign myproject --auto --strategy=dependency
ntm mail inbox myproject
ntm locks list myproject --all-agents
```

## Operator Loop

For a human or orchestrator agent tending the swarm.

> **Before nudging anyone, check real pane state.** `ntm activity` / `ntm health` lag behind reality and have in the past shown everything as stale ("56 years ago"). Trust the newer `--robot-is-working` and `--robot-agent-health` surfaces instead. If an agent looks idle in one tool and busy in another, always believe the newer one.

### Each tick — truth first, nudges second

```bash
# 1. Real per-pane work state (working / idle / rate_limited / error / context_low)
ntm --robot-is-working=myproject

# 2. OAuth + quota + provider reality (catches false "resets 3pm" messages)
ntm --robot-health-oauth=myproject
ntm --robot-quota-status
ntm --robot-account-status

# 3. Agents stuck with no output for N minutes — auto-restart eligible
ntm --robot-health-restart-stuck=myproject --stuck-threshold=10m --dry-run

# 4. Coordination surfaces (file conflicts, collisions, digest)
ntm coordinator status myproject
ntm coordinator conflicts myproject
ntm coordinator digest myproject

# 5. Work graph reality
bv --robot-triage
br list --status in_progress --json | jq '.issues | length'
br list --status claimed --json  | jq '.issues | length'   # don't forget claimed
```

### Act — targeted, not broadcast

```bash
ntm --robot-send=myproject --msg="..." --type=cod          # non-interactive, avoids confirm prompts
ntm send myproject --pane=5 --no-cass-check "..."          # use --no-cass-check in loops (CASS dupe prompt blocks otherwise)
ntm --robot-smart-restart=myproject --panes=4,5 --prompt="..."  # check-then-restart, sends new prompt
ntm --robot-restart-pane=myproject --panes=4 --restart-bead=br-123  # nuclear: tmux respawn-pane -k + fresh prompt
ntm rotate myproject --all-limited                          # swap rate-limited CAAM accounts at once
ntm --robot-switch-account=claude:jeff2718281               # explicit CAAM account switch
ntm assign myproject --auto --strategy=dependency
```

### Useful operator surfaces

```bash
ntm --robot-snapshot
ntm --robot-attention --since-cursor=42
ntm --robot-markdown --md-compact
ntm --robot-terse
ntm --robot-mail-check --mail-project=myproject --urgent-only
ntm --robot-diagnose=myproject --diagnose-fix       # auto-fix where possible
ntm --robot-wait=myproject --wait-until=idle --timeout=10m
ntm --robot-wait=myproject --wait-until=rate_limited --timeout=30m   # wake when the wall drops
```

If the cursor expires, re-run `ntm --robot-snapshot` and continue.

## Autonomous Unstick — Don't Wait For The Human

The swarm's throughput collapses when the orchestrator waits for manual user intervention that it could resolve itself. The operator agent is authorized to take every unstick action below on its own.

### Rate limits are transient — probe, don't assume

A pane showing "resets 3pm (America/New_York)" does **not** mean the pane is dead now. That message is stale the moment it renders. Always probe:

```bash
# Truth from the provider, not from the pane buffer:
ntm --robot-health-oauth=myproject | jq '.panes[] | {pane, provider, rate_limited, resets_at}'

# Wake a pane from zsh/idle by sending a ping (bypasses ntm's confirm prompts):
tmux send-keys -t myproject:0.4 "ping" Enter
sleep 5
ntm --robot-tail=myproject --lines=10 --panes=4
```

If the pane ponged, the limit already lifted — dispatch work. If it is still rate-limited, try:

```bash
# 1. Rotate the CAAM account (cod uses ChatGPT subscription, cc uses Claude; different pools)
ntm rotate myproject --pane=4 --account=jeff2718281@gmail.com
ntm rotate myproject --all-limited       # do them all at once

# 2. Or switch globally if you know the next healthy account
ntm --robot-switch-account=claude:jeff2718281

# 3. Or wait — ntm will wake you when the wall drops
ntm --robot-wait=myproject --wait-until=rate_limited --timeout=30m
```

### Stuck panes (identical tail ≥3 ticks, no commits, no new bead churn)

Don't keep pasting nudges into a dead buffer. Escalate fast:

```bash
# Detect:
ntm --robot-health-restart-stuck=myproject --stuck-threshold=10m --dry-run

# Smart restart (checks activity, avoids trashing real work):
ntm --robot-smart-restart=myproject --panes=5 --prompt="$(cat marching_orders.txt)"

# If the CLI is wedged on /usage, /rate-limit-options, or a confirm dialog, the
# graceful path fails. Use --hard-kill or go straight to restart-pane:
ntm --robot-smart-restart=myproject --panes=5 --hard-kill --prompt="..."
ntm --robot-restart-pane=myproject --panes=5 --restart-prompt="..."
```

If `ntm rotate` times out on a wedged CLI, skip straight to `--robot-restart-pane`; it uses `tmux respawn-pane -k` directly and doesn't need CLI cooperation.

### Interactive blockers inside the pane (cc `/rate-limit-options`, codex `[Pasted text]`)

cc panes sometimes land on an interactive `/rate-limit-options` dialog with choices like "Stop and wait" or "Switch to extra usage." Codex panes sometimes stall with a `[Pasted text]` buffer waiting for Enter. Both are fully resolvable by the orchestrator:

```bash
# cc rate-limit-options: pick "Switch to extra usage" (option 2 on typical layout)
tmux send-keys -t myproject:0.2 "2" Enter

# codex pending paste buffer:
tmux send-keys -t myproject:0.5 "" Enter

# If the pane has trailing garbage from a prior partial send, clear first:
tmux send-keys -t myproject:0.5 Escape Escape Escape C-u
tmux send-keys -t myproject:0.5 "<your prompt>" Enter
```

Always `C-u` (clear-line) before sending a fresh prompt into codex — codex TUI frequently concatenates a new send onto leftover buffer text and corrupts both.

### Orchestrator send confirmation prompts

`ntm send` aborts with `Continue anyway? [y/N]` when CASS detects a similar past prompt. In an orchestrator loop this is a silent blocker. Two fixes:

```bash
# Per-call:
ntm send myproject --pane=5 --no-cass-check "..."

# Structural: use --robot-send, which is non-interactive by design:
ntm --robot-send=myproject --panes=5 --msg="..."
```

Never broadcast via `ntm send --all` without excluding the user pane (`-s` / `--skip-first`). Without exclusion, stray prompts land in zsh and show as `zsh: command not found: <truncated-prompt>`.

### Cod/codex approval purgatory

Codex without bypass perms stops every few seconds asking to approve trivial reads. Fix at the alias layer: launch codex with `--dangerously-bypass-approvals-and-sandbox` (the standard `cod` alias does this). If panes were spawned without it, respawn them via `ntm --robot-restart-pane` — that launches via the alias.

## Steady-State Cadence & Productivity Signals

The operator's core job once the swarm is humming is to keep agents moving without burning the whole context on monitoring. Pick a cadence and stick with it; don't sub-minute poll.

### Tick interval

- **4 min** when panes are compiling, restarting, or dispatch has just fired — watch for nucleation.
- **10–17 min** at steady state — this is the default.
- Back off to **30 min** when multiple panes are deep in real work and the last tick surfaced nothing new.
- Never go below 3 min — it just burns tokens without new information.

### What "productive" actually looks like — verify with git, not vibes

```bash
git -C /path/to/project log --since="1 hour ago" --oneline --format='%ar %an %h %s' | head -20
ps -eo comm | grep -cE '^(cargo|rustc|go|bun|node)$'     # actual build processes
ntm --robot-is-working=myproject | jq '[.panes[] | select(.is_working)] | length'
```

If `git log` shows zero commits across 2+ hours AND panes are reporting "already complete" / "no fixes needed," the swarm is out of work. Stop tending it — more nudges produce prose, not code.

### Close-the-backlog rotation

When `open + claimed + in_progress > 100`, dispatch the "Close the Backlog" prompt (see PROMPTS.md) and **block new review-bead creation** until the count drops below 100. Alternate close and review prompts at a ratio driven by backlog depth:

| Backlog depth | Close : Review |
| --- | --- |
| < 50 | 1 : 3 |
| 50–100 | 1 : 1 |
| > 100 | 3 : 1 |
| > 200 | close-only mode |

### Convergence termination

Auto-terminate the orchestrator loop when ALL of:

1. `git log --since="1 hour ago"` shows 0 commits attributed to swarm agents.
2. ≥2 consecutive ticks where every pane produced convergence language ("exemplary", "already complete", "no fixes needed", "ready to ship").
3. `br ready --json` returns 0 items AND `br list --status=in_progress,claimed` is empty or unchanged.

When all three hold, stop. Don't ask for more work — report and exit. Infinite nudging a converged swarm is the single biggest source of wasted tokens and user frustration.

## Quality Loops

### Self-Review Prompt

```text
Read over all of the code you just wrote and the existing code you modified with fresh eyes. Look for obvious bugs, regressions, unsafe assumptions, confusing logic, missing tests, and sloppy edge cases. Fix anything you find before you move on.
```

### Cross-Review Prompt

```text
Turn your attention to code written by the other agents and review it critically for bugs, regressions, reliability problems, security issues, and poor assumptions. Diagnose root causes, then fix what actually needs fixing.
```

### Exploration Prompt

```text
Randomly explore unfamiliar parts of the codebase, trace the real execution flow, understand how those pieces fit into the larger workflow, and then do a fresh-eyes pass for obvious bugs and bad assumptions. Fix what you can justify.
```

## Coordination Patterns

Default coordination stack:

```text
Beads decide what should happen.
Agent Mail records who is doing what.
File reservations or worktrees prevent collisions.
NTM gives the operator shared state, prompts, assignments, and recovery surfaces.
```

Helpful commands:

```bash
ntm mail send myproject --all "Report blockers and current file focus."
ntm locks renew myproject
ntm checkpoint save myproject -m "before risky merge"
ntm checkpoint list myproject
ntm worktrees list
ntm worktrees merge claude_1
```

## Swarm Anti-Patterns

### Communication Purgatory / Prose Over Code

Problem: agents keep writing subsystem walkthroughs, mental models, and "exemplary" self-reviews instead of shipping commits. The swarm looks busy; `git log --since="4 hours ago"` shows zero commits.

Fix: enforce a **ship-or-surface** SLA in every dispatch prompt — the agent must either commit a real diff or surface an explicit blocker within one hour. Use the "Stop Prose, Ship Commits" prompt from [PROMPTS.md](references/PROMPTS.md). If convergence language ("no fixes needed", "exemplary", "already complete") appears two rounds in a row and `git log` confirms zero commits, the swarm has run out of work — stop, don't nudge again.

### File Thrashing

Problem: multiple agents edit the same file or same logical area without coordination.

Fix: reserve files up front. Assign explicit **crate / directory domains** at session start — never leave agents to pick overlapping scopes. When collisions happen, explicitly pick a canonical owner and redirect everyone else. When repo policy allows, use worktrees for isolation-heavy efforts.

### Stale Bead State, Hidden "claimed" Backlog

Problem: work is done but bead status is wrong, or agents are tracking `open + in_progress` and silently missing `claimed` (which can hide 50-100 beads from reports).

Fix: always check all three statuses. `br list --status=open,in_progress,claimed --json | jq '.issues | length'`. Periodically run `bv --robot-triage`, `ntm work triage`, and `ntm coordinator digest` to keep the graph honest.

### Review-Bead Inflation

Problem: agents file new review beads every round but never close the backlog. Open beads grow unboundedly while the swarm feels "productive."

Fix: alternate **close-prompts** with **review-prompts**, weighted by backlog depth. When `len(open) + len(claimed) + len(in_progress) > 100`, dispatch the "Close the Backlog" prompt and block new review-bead creation. See [PROMPTS.md](references/PROMPTS.md).

### Broken Build Drift

Problem: one agent breaks the build and the rest keep coding blindly.

Fix: broadcast that the build is broken, stop duplicate speculative work, route one or two agents to repair the baseline. Obey repo rules for offloading heavy verification commands (such as `rch`).

### TUI Misuse

Problem: an agent tries to drive `ntm dashboard` or another interactive surface.

Fix: use `--robot-*` for structured state and keep the TUI for humans.

### Stuck-Pane Tolerance

Problem: orchestrator sees the same 70-line transcript for 30+ ticks, keeps pasting nudges, nothing lands because the CLI is wedged on `/usage`, `/rate-limit-options`, or a confirm dialog.

Fix: after **≤3 ticks** of identical tail and zero output growth, stop nudging and escalate:

1. `ntm --robot-health-restart-stuck=myproject --stuck-threshold=10m` — detects and surfaces stuck panes.
2. `ntm --robot-smart-restart --hard-kill --prompt="..."` — graceful-with-fallback.
3. `ntm --robot-restart-pane --restart-prompt="..."` — nuclear option, bypasses CLI cooperation entirely.

Always `C-u` / Escape × 3 the pane before sending fresh prompts into codex — codex TUI concatenates stray buffer text and corrupts new sends.

### False Rate-Limit-Dead Assumption

Problem: a pane shows "You've hit your limit · resets 3pm (America/New_York)" and the orchestrator treats it as dead for hours — but the wall lifted long ago.

Fix: probe every ~10 min instead of trusting the stale message. `tmux send-keys -t session:0.N "ping" Enter; sleep 5; ntm --robot-tail` — if it pongs, the limit already cleared. Or query reality: `ntm --robot-health-oauth=myproject` and `ntm --robot-quota-status`. See Autonomous Unstick for full recipe.

### Duplicate-Work Collisions

Problem: two agents claim the same bead or edit the same file because the dispatch prompt didn't include a dynamic avoid-list.

Fix: let the coordinator auto-assign, or compute the avoid-list dynamically each dispatch:

```bash
ntm coordinator enable auto-assign
ntm coordinator enable digest --interval=15m
ntm assign myproject --auto --strategy=dependency

# Manual avoid-list for hand-rolled dispatch:
avoid=$(br list --status=in_progress,claimed --json | jq -r '[.issues[].id] | join(",")')
ntm --robot-send=myproject --panes=3 --msg="Claim a bead NOT in {$avoid}..."
```

### Stale Activity Signal

Problem: `ntm activity` / `ntm health` report everything as "56 years stale," so the orchestrator thinks the swarm is dead when it is actually working.

Fix: use the newer `--robot-is-working`, `--robot-agent-health`, `--robot-diagnose` surfaces, which use live pane-buffer sampling instead of cached timestamps. If a tool's output is obviously wrong (timestamps from the epoch), switch tools rather than believing it.

### Saturated Context Drift

Problem: a cc pane has been running for 4–6 days, context is exhausted, work becomes circular planning instead of real code.

Fix: rotate saturated agents. `ntm --robot-restart-pane=myproject --panes=N --restart-bead=br-xxx` — a fresh pane on a clean quota is almost always higher-EV than babying a context-toasted one.

### Orchestrator Prompt Degradation

Problem: nudges shorten to "Next review." after many cycles, and the downstream work becomes equally shallow.

Fix: never shorten nudges below one concrete verb + one specific target. If you can't think of a specific target, stop nudging — the swarm is done. Terseness only works when it is specific-terse, not generic-terse.

### Missing Domain Assignment

Problem: N agents spawned, no domain split — all pick from the same triage list → duplicate work, collisions.

Fix: at session start, assign each pane an explicit **crate / directory domain** in its marching orders ("you own fcp-mesh, fcp-store, fcp-raptorq") AND enable coordinator auto-assign. Domain assignment is the single biggest productivity lever for wide workspaces.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `spawn` cannot resolve the project | Use `ntm quick`, check `ntm config get projects_base`, or make the repo discoverable from that base |
| No clear next work item | Run `bv --robot-triage`, `bv --robot-next`, or `ntm work triage` |
| Coordination feels chaotic | Check Agent Mail inboxes, lock state, and `ntm coordinator digest/conflicts` |
| Agents appear idle | Use `ntm --robot-is-working=myproject` and `ntm --robot-agent-health=myproject` — they are the authoritative live signals |
| Pane stuck identical ≥3 ticks | `ntm --robot-health-restart-stuck` → `ntm --robot-smart-restart --hard-kill` → `ntm --robot-restart-pane` |
| Pane showing "resets Xpm" rate-limit | Probe with `tmux send-keys ping Enter` + `ntm --robot-tail`. If still limited: `ntm rotate myproject --all-limited` or `ntm --robot-switch-account=claude:<account>` |
| cc pane on `/rate-limit-options` dialog | `tmux send-keys -t session:0.N "2" Enter` to pick "Switch to extra usage"; or rotate the account |
| codex pane on `[Pasted text]` limbo | `tmux send-keys -t session:0.N "" Enter` to flush the paste buffer |
| `ntm send` aborts with `Continue anyway?` | Pass `--no-cass-check`, or use `ntm --robot-send` (non-interactive) |
| Agent Mail server down | Proceed without it (see repo AGENTS.md); use `br update --assignee=...` as a soft coordination lock |
| `ntm activity` / `ntm health` show epoch / "56 years stale" | Use `--robot-is-working` / `--robot-agent-health` / `--robot-diagnose` instead |
| Cursor expired | Re-run `ntm --robot-snapshot` |
| Saturated-context cc (4+ days old, circular planning) | `ntm --robot-restart-pane --panes=N --restart-bead=br-xxx` on a fresh account |
| Beads look inconsistent | Use normal `br`/`bv` recovery commands for the repo; do not mutate `.beads` internals from habit |
| Duplicate-work collisions | Enable coordinator auto-assign; compute avoid-list from `br list --status=in_progress,claimed` at each dispatch |
| Swarm converges ("no fixes needed" × 2 rounds, zero new commits) | Stop. The backlog is exhausted; don't nudge further. |

## Review-Only Mode

When the swarm's job is audit rather than implement (post-refactor hardening, pre-release bug hunt, mixed-swarm quality layer), flip agents into **Review-Only Mode**. Same operator loop, different prompt sequence and coordination rules.

**Core cycle:** per round, per pane: `P1 (study) → P2 (explore+fresh-eyes) → P3 (cross-review) → P4 (continuation) → repeat P2-P4 ×2 more times`. End of round: kill + relaunch all reviewer panes. Exploits prompt caching within a round; resets context between rounds.

**Reviewer coordination rules** (enforce in marching orders):
- Do NOT register with MCP Agent Mail (avoids communication purgatory)
- Do NOT claim beads from bv / br (not implementers)
- DO read `git log` / `git diff` to find recent implementer activity
- DO run repo's tests/linters after every fix
- DO tag findings by severity: `[CRITICAL] / [HIGH] / [MEDIUM] / [LOW]`

**Mixed-swarm ratios** (implementer : reviewer):

| Swarm size | Implementer | Reviewer |
| --- | --- | --- |
| Small (6) | 5 | 1 |
| Medium (14) | 10 | 4 |
| Large (24) | 20 | 4 |

Reviewers scale sub-linearly — 4 covers most codebases; more produces redundant findings.

**Hot mode-switch:** flip a pane between implementer and reviewer mid-session via the MODE-SWITCH prompts in [PROMPTS.md](references/PROMPTS.md).

Full spec — spawn, dispatch cadence, quality rubric, kill-relaunch timing, anti-patterns, real-bug examples — lives in [REVIEW-MODE.md](references/REVIEW-MODE.md). For **Gemini-specific** tuning (Flash-fallback detection, `gemini-3.1-pro-preview` model lock, `~/.gemini/settings.json` config), use `/code-review-gemini-swarm-with-ntm` directly.

## Reference Index

| Topic | Reference |
| --- | --- |
| **135+ robot-mode surfaces with commands, lanes, categories, transport availability, deprecated flags** | [ROBOT-MODE.md](references/ROBOT-MODE.md) |
| **Error taxonomy + autonomous recovery decision tree** (cursor, quota, entity, source, request) | [RECOVERY.md](references/RECOVERY.md) |
| **Freshness, source health, attention state machine, three-observation rule** | [OBSERVABILITY.md](references/OBSERVABILITY.md) |
| **25 operationalized field-expertise cards** (trigger + recipe + prompt + validator) | [OPERATOR-CARDS.md](references/OPERATOR-CARDS.md) |
| **38 named anti-patterns** from real swarm sessions, each with a fix | [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md) |
| **/loop, CronCreate, shell cron, schedule** — when to use each; convergence-gated tick scripts | [CRON-AND-AUTOMATION.md](references/CRON-AND-AUTOMATION.md) |
| **Review-Only Mode** — phase cycle, mixed-swarm ratios, kill-relaunch rhythm, quality rubric, mode-switch prompts | [REVIEW-MODE.md](references/REVIEW-MODE.md) |
| Marching orders, review prompts, ship-or-surface, close-backlog, orchestrator diagnosis, autonomous unstick playbook | [PROMPTS.md](references/PROMPTS.md) |
| Spawn mixes, cadence, close/review ratio, convergence termination, domain assignment, agent-pool awareness, scope discipline | [PLAYBOOK.md](references/PLAYBOOK.md) |

### Lookup By Symptom

| What you see | Start here |
| --- | --- |
| "Agent isn't working" / tool shows stale epoch timestamps | ROBOT-MODE.md `--robot-is-working` + OBSERVABILITY.md "Three-Observation Rule" |
| Rate limit message, unsure if real | RECOVERY.md `QUOTA_*` + OC-001 in OPERATOR-CARDS.md |
| Pane stuck for 3+ ticks | OC-003 stuck-pane ladder + AP-13 |
| Prose-without-commits | OC-004 Ship-or-Surface + AP-32 |
| Agent Mail down | OC-007 + AP-19 |
| Coordinator digest reports "no conflicts" but conflicts exist | OC-019 + AP-23 |
| Too-broad file reservation blocks swarm | OC-008 + AP-20 |
| Need to reassign a bead owned by saturated pane | OC-015 + AP-21 |
| Need to automate the tick cadence | CRON-AND-AUTOMATION.md |
| Need the right robot-mode command | ROBOT-MODE.md registry query |
| Need to know when to stop | OC-016 Convergence Termination + OBSERVABILITY.md |
| Running an audit/review-only session or mixed impl+review | REVIEW-MODE.md (agent-agnostic) or `/code-review-gemini-swarm-with-ntm` (Gemini-specific) |

## Related Skills

This skill is deliberately **narrow**: it covers how to tend an NTM swarm through its operator loop, recovery recipes, and prompt library. For adjacent concerns, invoke these:

| Concern | Skill |
| --- | --- |
| Full NTM command catalog, spawn mixes, recipes, `ntm work ...` intelligence | `ntm` |
| MCP Agent Mail primitives: register, reserve, send, inbox, macros, handshakes | `agent-mail` |
| Bead state changes, dependencies, ready work | `br` |
| Graph-aware triage, critical path, priority misalignment | `bv` |
| Account management, rotation, CAAM quota | `caam` |
| Canonical multi-agent swarm flow with review loops | `multi-agent-swarm-workflow` |
| Dual-agent (cc+cod) per-repo flywheels | `flywheel-with-two-agents-per-repo` |
| Gemini 3.1 Pro review-only swarms with Flash fallback detection | `code-review-gemini-swarm-with-ntm` |
| Weighted bead-count swarm spawning | `open-beads-weighted-tmux-agent-sessions` |
| Agent fungibility (why the swarm treats panes as interchangeable) | `agent-fungibility-philosophy` |
| Multi-model reasoning ensembles (symbolic vs neural, fast vs deep) | `modes-of-reasoning-project-analysis` |
| Adversarial two-agent idea generation | `dueling-idea-wizards` |
| Recurring orchestrator ticks | `loop`, `schedule` |
| Automated pane-stuck detection via hooks | `cc-hooks` |
| Remote cargo/gcc/bun offload (for rch-related concerns) | `rch` |
| Past-session mining for prompts / decisions | `cass` |
| Cross-project pattern extraction | `cross-project-pattern-extraction` |
| Codifying this skill's methodology | `operationalizing-expertise` |
| Writing or editing Claude skills | `sw` |
