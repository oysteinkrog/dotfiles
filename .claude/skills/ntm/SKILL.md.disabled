---
name: ntm
description: >-
  NTM tool reference for multi-agent tmux orchestration. Use when spawning a
  swarm, sending marching orders / messages to panes, checking inbox, tending
  or restarting agents, running pipelines/controllers/serve, configuring
  safety/policy/approvals, reading robot-mode state, or debugging ntm errors
  like "project not found", "CASS detected", "rate_limited", or "unknown
  command".
---

<!-- TOC: Quick Start | Mental Model | Session Orchestration | Dispatch & Reusable Assets | Work Intelligence | Coordination | Safety | Robot Mode | Controller Agents | Serve API | Project Resolution | Gotchas | References | Related Skills -->

> **Scope:** this skill is the **NTM tool reference** — every verb, flag, schema, and integration point. For operator loops, marching orders, unstick ladders, swarm anti-patterns, and tending cadence, use the companion `vibing-with-ntm` skill.

# NTM — Named Tmux Manager

> **Core capability:** Turn `tmux` into a structured, recoverable multi-agent workspace.

> **Read the repo first.** If the target repository has `AGENTS.md` or `README.md`, read those before applying this skill. Repo-local instructions override generic NTM advice.

> **Discover, don't guess.** `ntm --robot-capabilities` returns the machine-readable API schema. `ntm --robot-docs=quickstart|commands|examples|exit-codes` returns focused docs. Use these before parsing human help text or trusting stale instructions.

> **Interactive vs automation:**
> - `ntm dashboard`, `ntm palette`, and other TUI surfaces are for humans. `ntm view` retiles the operator's tmux layout and returns nothing to you — never call it from automation.
> - For machine-readable automation, prefer `--robot-*`. Set `--robot-format=toon` (or `NTM_ROBOT_FORMAT=toon`) for a token-efficient structured format, and `--robot-verbosity=terse` when context is tight.
> - Non-interactive CLI commands such as `ntm send`, `ntm work triage`, `ntm locks list`, `ntm pipeline status`, and `ntm serve` are fine when they are the clearest tool.

> **Coordination and isolation:**
> - Agent Mail reservations are the default coordination primitive.
> - `--worktrees` and `ntm worktrees ...` are supported isolation tools when the repo policy allows them.
> - If a repo `AGENTS.md` prefers reservations-only or has worktree-specific rules, follow that repo.

## Quick Start

```bash
# Install / sanity check
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh?$(date +%s)" | bash -s -- --easy-mode
ntm deps -v

# Create or resolve a project
ntm quick myproject --template=go

# Launch a mixed swarm
ntm spawn myproject --cc=2 --cod=1 --gmi=1

# Dispatch work
ntm send myproject --cc "Map the auth layer and propose a refactor plan."

# Inspect the current work graph and system state
ntm work triage --format=markdown
ntm --robot-snapshot

# Discover the full surface without parsing --help output
ntm --robot-capabilities
ntm --robot-docs=commands
```

## Mental Model

NTM wraps tmux with structured metadata and durable state. Five concepts are worth internalizing:

- **Project** — resolved via `NTM_PROJECTS_BASE + <session>` (or `projects_base` config). Session name MUST equal the directory basename under that base, or agent-mail/beads/reservations register under a different key than NTM sees. This is the single most common source of cross-tool breakage.
- **Session name** — bare project (`myproject`) or labeled variant (`myproject--frontend`). `--` is the reserved label separator; project names cannot contain `--`. Labels must match `^[a-zA-Z0-9][a-zA-Z0-9_-]*$` and be ≤50 chars.
- **Pane** — a tmux pane typed as an agent (cc/cod/gmi/cursor/windsurf/aider/ollama) or the user pane (index 0 by default). `ntm send` defaults **exclude** the user pane; `--all` includes it; `-s/--skip-first` explicitly skips it.
- **Attention feed** — a monotonic event stream. `--robot-snapshot` bootstraps; `--robot-events --since-cursor=N` replays; `--robot-attention` blocks until new events. Cursors are per-server monotonic and **not portable across machines**; expired cursors return a `resync_command` ready to paste.
- **Robot mode** — every state-read has a `--robot-*` variant returning structured JSON or TOON. Prefer robot mode over TUIs in all automation; `ntm view`, `ntm dashboard`, `ntm palette` are operator-only and will return nothing useful to automation (and `ntm view` additionally retiles the human's layout).

## Session Orchestration

Use these for day-to-day session lifecycle management:

```bash
ntm spawn myproject --cc=3 --cod=2 --gmi=1
ntm spawn myproject --label frontend --cc=2
ntm spawn myproject --label backend --cc=2 --worktrees
ntm add myproject --cc=1
ntm add myproject --label frontend --cod=1
ntm list
ntm status myproject
ntm zoom myproject 3
ntm attach myproject
ntm dashboard myproject   # human only
ntm palette myproject     # human only
```

Useful spawn patterns:

```bash
ntm spawn myproject --prompt "Read AGENTS.md and start on ready work"
ntm spawn myproject -r full-stack                          # named recipe (see `ntm recipes list`)
ntm spawn myproject -t red-green                           # named workflow (see `ntm workflows list`)
ntm spawn myproject --persona=architect --persona=implementer:2
ntm spawn myproject --stagger-mode=smart --cc=6 --cod=4    # smart|fixed|none
ntm spawn myproject --no-user --cc=5 --cod=5               # no human-driver pane
```

Adjust a running swarm instead of re-spawning:

```bash
ntm scale myproject --cc=4                # grow/shrink one agent type
ntm rebalance myproject                   # even out agents by workload
ntm swarm plan                            # show what a spawn would do
ntm swarm status                          # cross-session swarm view
ntm swarm stop <pattern>                  # stop sessions by name pattern
ntm respawn myproject                     # recover dead agents in place
ntm adopt <tmux-session>                  # bring an existing tmux session under ntm
```

## Dispatch and Reusable Assets

High-leverage NTM usage is not just `spawn` plus `send`. The real power shows up when
you combine richer dispatch patterns with reusable session and prompt assets.

```bash
ntm send myproject --all "Checkpoint and summarize blockers."
ntm send myproject --pane=2 "Own the auth migration."
ntm send --project myproject "Sync to main and report conflicts."
ntm send myproject -c internal/auth/service.go "Review this subsystem"
ntm send myproject -t fix --var issue="nil pointer" --file internal/auth/service.go
ntm send myproject --smart --route=affinity "Take the auth follow-up"
ntm send myproject --distribute --dist-strategy=dependency

ntm recipes list
ntm recipes show full-stack
ntm workflows list
ntm workflows show red-green
ntm template list
ntm template show refactor
ntm session-templates list
ntm session-templates show refactor
```

User-level and project-level assets both matter. NTM can resolve configuration from
`~/.config/ntm/...` and project-local `.ntm/...` trees, so check the repo before
assuming defaults.

## Work Intelligence

NTM is no longer just a pane launcher. It has first-class work selection and assignment:

```bash
ntm work triage
ntm work triage --by-track
ntm work alerts
ntm work search "JWT auth"
ntm work impact internal/api/auth.go
ntm work next
ntm work graph

ntm assign myproject --auto --strategy=dependency
ntm assign myproject --beads=br-123,br-124 --agent=codex
```

Use `ntm work ...` when you want NTM to wrap `bv` and present work in operator-friendly form.
Use raw `bv --robot-*` when you specifically want the graph engine's native robot output.

## Coordination and Recovery

NTM now exposes the surrounding coordination stack directly:

```bash
# Mail (Agent Mail MCP, wrapped for CLI use)
ntm mail send myproject --all "Report blockers and current file focus."
ntm mail inbox myproject                      # or: ntm mail inbox myproject --json

# File reservations (advisory locks)
ntm locks list myproject --all-agents
ntm locks renew myproject --extend 30         # minutes
ntm locks force-release myproject 42 --note "agent inactive"

# Multi-agent coordinator
ntm coordinator status myproject              # alias: ntm coord status
ntm coordinator digest myproject
ntm coordinator conflicts myproject
ntm coordinator enable auto-assign            # background automation
ntm coordinator enable digest --interval=30m

# Durable session state
ntm checkpoint save myproject -m "before risky refactor"
ntm checkpoint list myproject
ntm checkpoint restore myproject              # latest; takes optional <id>
ntm checkpoint export myproject <id>          # portable archive
ntm checkpoint import <archive>

# Persisted timelines of agent state transitions
ntm timeline list
ntm timeline show <session-id>
ntm timeline stats

# Audit, conflict, history surfaces
ntm history search "authentication error"
ntm audit show myproject
ntm changes myproject                         # recent file changes attributed to agents
ntm conflicts myproject --since 6h            # top-level command; not a changes subcommand
ntm resume myproject                          # re-attach + context-inject after restart

# Handoff bundles for cross-machine or cross-session resumes
ntm handoff create myproject
ntm handoff list
ntm handoff show <path>
```

Isolation options:

```bash
# Coordination-first
ntm locks list myproject

# Isolation-first when policy allows it
ntm spawn myproject --cc=3 --worktrees
ntm worktrees list
ntm worktrees merge claude_1
```

## Safety and Approvals

NTM has built-in safety, policy, and approval surfaces. Use them instead of ad hoc shell habits:

```bash
ntm safety status
ntm safety check -- git reset --hard
ntm safety blocked --hours 24
ntm safety install

ntm policy show --all
ntm policy validate
ntm policy edit
ntm policy automation

ntm approve list
ntm approve show <token>
ntm approve <token>                         # approve by token (not bead/issue id)
ntm approve deny <token> --reason "wrong target branch"
ntm approve history
```

If the repo instructions require offloading builds or tests through another tool such as `rch`, obey the repo instructions.

## Canonical Robot Mode

Start with these:

```bash
ntm --robot-help
ntm --robot-capabilities                    # canonical machine-readable API schema
ntm --robot-docs=quickstart                 # also: commands, examples, exit-codes
ntm --robot-schema=all                      # JSON Schema for every robot response
ntm --robot-status
ntm --robot-snapshot
ntm --robot-plan
ntm --robot-dashboard
ntm --robot-markdown --md-compact
ntm --robot-terse
```

Format and verbosity knobs (token-budget friendly):

```bash
ntm --robot-snapshot --robot-format=toon        # toon is far more token-efficient than json
ntm --robot-snapshot --robot-verbosity=terse    # terse | default | debug
# Env fallbacks honored: NTM_ROBOT_FORMAT / NTM_OUTPUT_FORMAT / TOON_DEFAULT_FORMAT
```

Common task-specific robot surfaces:

```bash
ntm --robot-send=myproject --panes=2 --msg="Summarize blockers." --type=claude
ntm --robot-ack=myproject --timeout=30s
ntm --robot-tail=myproject --panes=2 --lines=50
ntm --robot-mail-check --mail-project=myproject --urgent-only
ntm --robot-cass-search="authentication error"
ntm --robot-beads-list --beads-status=open
ntm --robot-bead-claim=br-123 --bead-assignee=agent1
ntm --robot-bead-close=br-123 --bead-close-reason="Completed"
```

**Polite-probe-then-act** (preferred over raw interrupt):

```bash
ntm --robot-is-working=myproject --panes=2,3    # check first
ntm --robot-smart-restart=myproject --panes=2   # refuses if the pane is actively working
ntm --robot-probe=myproject --panes=2           # responsiveness probe
ntm --robot-diagnose=myproject                  # comprehensive health + recommendations
ntm --robot-context=myproject                   # context-window usage per agent
```

Event-driven tending instead of polling:

```bash
ntm --robot-wait=myproject --wait-until=attention --timeout=5m
ntm --robot-wait=myproject --wait-until=action_required,mail_ack_required
ntm --robot-events --since-cursor=42 --events-limit=50 --category=agent
```

Operator loop:

```text
1. Bootstrap with --robot-snapshot
2. Tend with --robot-attention or --robot-wait (blocks until an event)
3. Act with --robot-send / --robot-smart-restart / ntm send / ntm assign / ntm mail / ntm locks
4. Re-bootstrap with --robot-snapshot if the cursor expires
```

Prefer `--robot-*` when another agent or script needs structured output.

## Controller Agents

`ntm controller <session>` launches a coordinator agent in pane 1 whose job is to
watch the other agents, resolve conflicts, and drive the operator loop.

```bash
ntm controller myproject                      # default: Claude controller, coord prompt
ntm controller myproject --agent-type=cod     # cc|cod|gmi|cursor|windsurf|ws|aider|ollama
ntm controller myproject --prompt=ctrl.txt    # custom prompt template
ntm controller myproject --no-prompt          # launch agent, send no initial prompt
```

Custom prompts support template variables: `{{.Session}}`, `{{.AgentList}}`, `{{.ProjectDir}}`.

The built-in default prompt tells the controller to:

- Prefer `--robot-*` commands over interactive TUIs.
- Start with `ntm --robot-snapshot`, then block on `ntm --robot-attention --attention-session={{.Session}}`.
- Tail panes with `ntm --robot-tail={{.Session}} --panes=N --lines=50`.
- Check Agent Mail via `ntm mail inbox {{.Session}} --json` (not a `--mail-project=` flag).
- Use `ntm send {{.Session}} --pane N "message"` for single pane, `--panes=1,2` for many.
- Use `ntm --robot-interrupt={{.Session}} --panes=N` to interrupt without killing.
- **Never** call `ntm view` — it retiles the human operator's tmux layout and returns nothing.

## Serve API and Pipeline Surfaces

NTM also exposes local API and durable workflow surfaces:

```bash
ntm serve --port 7337
ntm openapi generate
ntm pipeline run .ntm/pipelines/review.yaml --session myproject
ntm pipeline status run-20241230-123456-abcd
ntm pipeline list
ntm pipeline resume run-20241230-123456-abcd
ntm pipeline cleanup --older=7d
```

Use `ntm serve` for long-lived local integrations. Use `--robot-*` for single-shot agent control.

## Project Resolution

`ntm spawn` needs a project directory that NTM can resolve.

```bash
ntm config get projects_base
ntm quick myproject --template=go

# Or point projects_base at an existing repo layout / create a symlink when needed
```

The session name usually matches the project directory name. Labels extend the session name as `project--label`.

## Gotchas (distilled from real agent sessions)

These are the NTM-specific trip-wires most commonly hit in practice. Each has a full entry in `TROUBLESHOOTING.md`; these are the one-liners.

1. **Project resolution** — `NTM_PROJECTS_BASE` + session name must equal the directory basename. Mismatch breaks agent-mail registration silently. If agent-mail and ntm "see different projects," fix this first.
2. **`ntm send` default skips the user pane** — so plain `ntm send myproject --cc "msg"` is safe; `ntm send myproject --all "msg"` hits the operator's zsh. Use `-s/--skip-first` if you want `--all` agents but no user pane.
3. **CASS dedup blocks sends** — default `--cass-check=true` with 0.7 similarity, 7-day lookback. If `ntm send` aborts with "similar past prompt," either add a rotating suffix (e.g. `"... pass 17 at 16:40"`) or pass `--no-cass-check`. In robot automation, `--robot-send` is non-interactive and never prompts.
4. **Label separator is literal `--`** — project names cannot contain `--`. `myproject--frontend` is the labeled variant; `my-project` is a valid project name; `my--project` is rejected.
5. **`send --cc=X` vs `spawn --cc=N:X`** — same flag name, different parsers. `send --cc=opus` filters *existing* panes by variant; `spawn --cc=2:opus` creates 2 new panes of model `opus`.
6. **`--route=affinity` is a send flag, not an assign strategy** — `assign --strategy=` accepts `balanced|speed|quality|dependency|round-robin` only.
7. **`--robot-pipeline=<id>` is *status*, not run** — to run, use `--robot-pipeline-run=<file>`. Conflating these is common.
8. **Pipeline state files accumulate forever** — `.ntm/pipelines/<run-id>.json` is never auto-pruned. Run `ntm pipeline cleanup --older=7d` periodically.
9. **Safety wrappers need PATH precedence** — `ntm safety install` drops `git`/`rm` wrappers at `~/.ntm/bin/` but does NOT modify `$PATH`. Confirm `~/.ntm/bin` is earlier in `$PATH` than `/usr/bin`.
10. **`bead_orphaned` is *deliberately* unsupported** — ntm refuses to infer abandonment from silence; explicit `bead abandon` mail messages would be required and don't exist yet. Don't try to wait on it.
11. **Cursors are per-server monotonic** — they are NOT portable across machines. Cross-machine continuity is via `checkpoint export`/`import` or `handoff`, not cursor shipping.
12. **`ntm approve` takes a token, not a bead id** — tokens are issued by the approval engine and returned with each approval request; beads ids like `br-123` will be rejected.
13. **`ntm changes` and `ntm conflicts` are separate top-level commands** — there is no `ntm changes conflicts` (use one or the other).

## Reference Index

Keep depth out of this file. Load these on demand for the operator-handbook-level detail.

| Topic | Reference |
| --- | --- |
| **`ntm send` deep reference** — agent-type selectors with variants, pane selectors, input sources, file context ranges, templates & vars, smart/route, distribute, batch, CASS dedup, prefix/suffix, dry-run, error modes | [SEND.md](references/SEND.md) |
| **`ntm spawn` deep reference** — agent counts & model variants, labels, worktrees, personas/recipes/workflows, stagger modes, session profiles, CASS context, assign pipeline, privacy, interactive wizard | [SPAWN.md](references/SPAWN.md) |
| **Work intelligence & assignment** — `ntm work *`, `ntm assign`, strategies, bv integration, robot wrappers | [WORK-AND-ASSIGN.md](references/WORK-AND-ASSIGN.md) |
| **Ensemble mode** — reasoning modes, presets, multi-agent debate sessions, `--robot-ensemble-*` surfaces | [ENSEMBLE.md](references/ENSEMBLE.md) |
| **Pipelines** — YAML schema v2.0, steps / conditionals / loops / retries, run IDs, resume & cancel, robot pipeline flags, legacy `exec` | [PIPELINES.md](references/PIPELINES.md) |
| **Serve API** — auth modes (`local`/`api_key`/`oidc`/`mtls`), OIDC/mTLS flags, REST v1 route map, OpenAPI endpoint, SSE streams | [SERVE.md](references/SERVE.md) |
| **Safety, Policy, Approvals** — `policy.yaml` schema, precedence, automation flags, approval tokens & TTL, SLB two-person, what `safety install` actually drops on disk | [SAFETY.md](references/SAFETY.md) |
| **Durability stack** — checkpoint vs timeline vs handoff vs resume vs rollback; export/import archives; cross-machine continuity | [DURABILITY.md](references/DURABILITY.md) |
| **Integration surfaces** — DCG, SLB, CAAM, RCH, RANO, mail, cass-from-ntm, quota, ru, giil, context-inject | [INTEGRATIONS.md](references/INTEGRATIONS.md) |
| **Environment variables** — every `NTM_*` + `TOON_*` + inherited vars with source citations | [ENV-VARS.md](references/ENV-VARS.md) |
| **Troubleshooting** — failure symptoms / root cause / fix, including projects_base, stale `ntm view`, `--mail-project` removal, cursor expiry | [TROUBLESHOOTING.md](references/TROUBLESHOOTING.md) |
| **Self-test / trigger phrases** — canonical phrasings the skill should activate on, mapped to first action | [SELF-TEST.md](references/SELF-TEST.md) |
| High-leverage command patterns, output capture, monitoring, reusable assets | [COMMANDS.md](references/COMMANDS.md) |
| Attention feed, robot output formats, wait conditions, mail/cass/bead robot flows, full `--robot-*` index | [ROBOT-MODE.md](references/ROBOT-MODE.md) |
| Human dashboard, palette, keybindings, and TUI implementation notes | [DASHBOARD.md](references/DASHBOARD.md) |
| Project resolution, `projects_base`, config paths, and project-local assets | [CONFIG.md](references/CONFIG.md) |

### Quick Search (grep hints)

When scanning the skill without loading every file, these literal strings are indexed:

```bash
# From the ntm skill root:
rg 'robot-' references/ROBOT-MODE.md          # every --robot-* flag with root.go line
rg '^###'  references/SEND.md                 # every send flag family
rg '^###'  references/SPAWN.md                # every spawn knob
rg 'Symptom' references/TROUBLESHOOTING.md    # all failure-mode entries
rg '^-'    references/SELF-TEST.md            # trigger phrases agents should match
rg '^| `'  references/ENV-VARS.md             # every NTM_* env var (leading table cell)
grep -l 'policy.yaml'  references/           # finds SAFETY.md
grep -l 'schema_version' references/          # finds PIPELINES.md
```

### Assets

Drop-in examples live under `assets/`:

- [`pipeline-example.yaml`](assets/pipeline-example.yaml) — a review pipeline with parallel step + retry
- [`policy-example.yaml`](assets/policy-example.yaml) — opinionated `~/.ntm/policy.yaml` starter
- [`envrc.example`](assets/envrc.example) — recommended `direnv`/shell env vars

## Related Skills

- **`vibing-with-ntm`** — the companion **operator / orchestration** skill: tending loops, marching-orders prompts, autonomous unstick recipes, anti-patterns, steady-state cadence. Use it whenever the question is "how do I run the swarm well?" rather than "what does NTM do?"
- `agent-mail` for inboxes, contact handshakes, and file reservations
- `br` for bead state changes and syncing
- `bv` for graph-aware task prioritization
- `cass` for prior-session retrieval
- `caam` for account rotation across providers (paired with `--robot-switch-account`)
- `dcg`, `slb` for destructive-command and two-person approval policy
