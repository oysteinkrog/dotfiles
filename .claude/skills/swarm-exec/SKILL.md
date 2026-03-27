# Swarm

Start and manage a swarm of coding agents that implement beads from the issue tracker.

Each agent is autonomous and fungible: it gets assigned a bead, implements it, commits, and exits.
`ntm --auto-restart` respawns bare Claude Code with fresh context for the next assignment.

## ntm config requirements

The `[agents]` section in `~/.config/ntm/config.toml` must include:
- `--strict-mcp-config` — disables MCP servers (agents don't need them)
- `DISABLE_AUTOUPDATER=1` — prevents auto-update banner that breaks idle detection

```toml
[agents]
claude = "env ... DISABLE_AUTOUPDATER=1 claude --dangerously-skip-permissions --strict-mcp-config ..."
```

Verify before spawning:
```bash
grep -q 'strict-mcp-config' ~/.config/ntm/config.toml && grep -q 'DISABLE_AUTOUPDATER' ~/.config/ntm/config.toml && echo "Config: OK" || echo "WARNING: check [agents].claude in ~/.config/ntm/config.toml"
```

## When to activate

Activate when the user says:
- "swarm" / "start swarm" / "launch swarm" / "run swarm"
- "assign bead X" / "run bead X"
- "start agents" / "spawn agents"

## Arguments

- `$ARGUMENTS` — optional: agent count (e.g. `4`), bead ID (e.g. `bd-xxx`), or `kill`/`stop`/`status`

## Instructions

### Determine intent from arguments

- No arguments or a number → **start/spawn** a swarm session
- A bead ID (starts with `bd-`) → **assign that single bead** to an idle agent
- `kill` or `stop` → **stop** the active swarm session
- `status` → delegate to `/swarm-exec-status`

---

### A. Start a swarm session

#### 1. Pre-flight

```bash
# Verify ntm config
grep -q 'strict-mcp-config' ~/.config/ntm/config.toml && grep -q 'DISABLE_AUTOUPDATER' ~/.config/ntm/config.toml && echo "Config: OK" || echo "WARNING: check ntm config"

# Show what's ready
bv -robot-next 2>/dev/null | jq '{id, title, score, unblocks, reasons}'

# Show parallel execution tracks
bv -robot-plan 2>/dev/null | jq '{total_actionable: .plan.total_actionable, total_blocked: .plan.total_blocked, tracks: (.plan.tracks | length), highest_impact: .plan.summary}'
```

#### 2. Choose a session name

Session name must match the directory name under `projects_base` in ntm config:

```bash
SESSION_NAME="$(basename $(pwd))"
```

#### 3. Write the prompt template

Write to `/tmp/swarm-template.md`. Kept compact to preserve agent context budget.

```
Read CLAUDE.md in the repo root. Follow ALL instructions there.

## Your bead: {BEAD_ID} — {TITLE}

Claim it: br update {BEAD_ID} --status in_progress
Get details: br show {BEAD_ID} --json 2>/dev/null
Check related: bv -robot-related {BEAD_ID} 2>/dev/null | jq '.categories'

## Rules

1. **Read production code first.** Understand actual behavior before writing anything.
2. Match existing project conventions (see CLAUDE.md).
3. Test/file folders must mirror source structure.
4. Follow .editorconfig and analyzer rules.

## Steps

1. Read and understand related existing code thoroughly
2. Implement according to acceptance criteria
3. Commit IMMEDIATELY after writing files (before full test suite):
   git add <specific files>
   git commit -m "<area>({BEAD_ID}): short description"
4. Run project checks (tests, linting — see CLAUDE.md)
5. If checks fail, fix and amend: git add <files> && git commit --amend --no-edit
6. Close: br close {BEAD_ID}
7. Exit: /exit
```

Note: `<area>` follows project git conventions (e.g., `test/`, `model/`, `vm/`).
The `{BEAD_ID}` and `{TITLE}` placeholders are substituted by `ntm assign`.

#### 4. Bump max_restarts

Default is 3 — not enough for a full swarm:

```bash
grep -q '^\[resilience\]' ~/.config/ntm/config.toml 2>/dev/null || echo -e '\n[resilience]\nmax_restarts = 100' >> ~/.config/ntm/config.toml
```

#### 5. Spawn agents and start auto-assignment

Spawn with `--assign` to automatically start watch-mode assignment after agents are ready.
This is the **primary method** — no manual batch assignment needed.

```bash
ntm spawn $SESSION_NAME --cc=$AGENT_COUNT --no-user --auto-restart --stagger-mode=smart \
  --assign --strategy=dependency --stop-when-done \
  --template-file=/tmp/swarm-template.md --template=custom
```

If `--assign` is not supported or fails, fall back to spawning then starting watch mode separately:

```bash
# Step 1: Spawn
ntm spawn $SESSION_NAME --cc=$AGENT_COUNT --no-user --auto-restart --stagger-mode=smart

# Step 2: Wait for agents to reach WAITING state
sleep 15

# Step 3: Start watch-mode assignment in background
ntm assign $SESSION_NAME --watch --strategy=dependency --stop-when-done \
  --template-file=/tmp/swarm-template.md --template=custom --auto &
WATCH_PID=$!
echo "Watch-mode assignment running (pid: $WATCH_PID)"
```

Watch mode polls for idle agents and ready beads, matching them automatically.
Dependency strategy ensures beads are assigned in correct order (unblocked first).

**Manual override** — if watch mode misses an agent, force-assign directly:

```bash
ntm assign $SESSION_NAME --pane=N --beads=bd-XXX --force \
  --template-file=/tmp/swarm-template.md --template=custom --auto
```

#### 6. Monitor loop (if watch mode unavailable)

If `ntm assign --watch` is not available or not working, the skill operator (you) MUST
actively monitor and assign. Set up a cron job to check every 2 minutes:

```
Check agent states: ntm activity $SESSION_NAME
Check ready beads: br ready
For each idle agent + ready bead pair: ntm assign $SESSION_NAME --pane=N --beads=bd-XXX ...
Check for orphaned files: git status --short | grep '^??'
Close beads that have commits but weren't closed: br close bd-XXX
```

Do NOT leave agents sitting idle while beads are ready. The whole point of a swarm is
continuous work assignment.

#### Known issues

- **Orphaned files**: Agents may hit context limits before committing. Monitor `git status --short` after each batch.
- **Concurrent build locks**: Multiple agents building simultaneously → MSB3021. Use `--no-dependencies` in agent template.
- **Beads committed but not closed**: Agents sometimes commit then exit before running `br close`. Check `git log` for bead IDs and close manually.
- **Context not clearing**: `--auto-restart` may not fully clear context. Kill and respawn if agents seem confused.

#### 7. Report

Tell the user:
- Session name and agent count
- Whether watch-mode auto-assignment is active (pid if backgrounded)
- Monitor: `ntm activity $SESSION_NAME --watch`
- Progress: `/swarm-exec-status`
- Stop: `/swarm kill`

---

### B. Assign a single bead

#### 1. Read the bead

```bash
br show $BEAD_ID --json 2>/dev/null
bv -robot-related $BEAD_ID 2>/dev/null | jq '.categories'
```

If not found or already closed, tell the user. Warn if blockers are still open.

#### 2. Find target session and idle pane

```bash
ntm list 2>/dev/null
ntm activity <session> 2>/dev/null
```

Pick first idle (WAITING) pane. If no session running, offer to spawn one.

#### 3. Build a self-contained prompt

Write `/tmp/bead-$BEAD_ID.md` — same structure as template in A.3, but with bead details
inlined (description, acceptance criteria, notes, labels, related beads).

#### 4. Assign

```bash
ntm assign <session> --pane=<N> --beads=$BEAD_ID --template-file=/tmp/bead-$BEAD_ID.md --template=custom --auto --no-cass-check
```

---

### C. Stop the swarm

```bash
ntm list 2>/dev/null
ntm kill <session> 2>/dev/null || true
bv -robot-next 2>/dev/null | jq '{id, title, unblocks}'
```

Report how many beads are still open/ready.
