# Swarm

Start and manage a swarm of coding agents that implement beads from the issue tracker.

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
- `status` → delegate to `/swarm-status`

---

### A. Start a swarm session

#### 1. Pre-flight

```bash
# Check agent-mail
curl -sf http://127.0.0.1:8765/api/ > /dev/null 2>&1 && echo "agent-mail: OK" || echo "agent-mail: NOT RUNNING — start with 'am'"

# Show what's ready and the top pick
bv -robot-next 2>/dev/null | jq '{id, title, score, unblocks, reasons}'

# Show parallel execution tracks
bv -robot-plan 2>/dev/null | jq '{total_actionable: .plan.total_actionable, total_blocked: .plan.total_blocked, tracks: (.plan.tracks | length), highest_impact: .plan.summary}'
```

If agent-mail is not running, warn and suggest `am`.

#### 2. Choose a session name

Derive from the current directory name or let the user override:

```bash
SESSION_NAME="swarm-$(basename $(pwd))"
```

#### 3. Spawn session

Agent count from `$ARGUMENTS` or default 4:

```bash
ntm spawn $SESSION_NAME --cc=$AGENT_COUNT --no-user --stagger-mode=smart --no-cass-check
```

#### 4. Build the prompt template

Write to `/tmp/swarm-template.md`. This template is **project-agnostic** — agents use bv and br to understand their work, and read the project's CLAUDE.md for conventions.

```
## Setup

1. Read CLAUDE.md in the repo root. Follow ALL instructions there.
2. Get your full assignment:
   br show {BEAD_ID} --json 2>/dev/null
3. Read the description, acceptance_criteria, notes, and labels carefully.
4. Check what this bead relates to:
   bv -robot-related {BEAD_ID} 2>/dev/null | jq '.categories'

## Understand the bead

- Check the bead's labels, type, and description to understand what kind of work this is
- Check dependencies: br dep list {BEAD_ID} 2>/dev/null
- Check for file conflicts before editing:
  bv -robot-impact <files-you-plan-to-edit> 2>/dev/null
- For implementation beads, find and read existing code that this bead relates to

## Adapt your approach to what the bead asks for

- **Spikes/research** (labels include "spike", or title starts with "Spike:"):
  Research and document findings, don't build production code.
  Record findings: br update {BEAD_ID} --notes "## Findings\n..."

- **Implementation**: Read existing code for reference behavior before writing new code.
  Follow the language, framework, and architectural conventions already in the project.

- **Docs/CI/infra**: Follow existing repo conventions. Don't over-engineer.

The bead's description and the project's CLAUDE.md together tell you everything you need.

## Workflow

1. Read the bead fully (br show {BEAD_ID})
2. Read related existing code to understand context and conventions
3. Implement according to acceptance criteria
4. Run the project's standard checks (tests, linting, type-checking — whatever CLAUDE.md specifies)
5. Commit ONLY files you changed:
   git add <specific files>
   git commit -m "feat({BEAD_ID}): short description"
6. Close the bead: br close {BEAD_ID}
7. STOP. Do not start another bead. Wait for the next assignment.
```

#### 5. Start watch mode

```bash
ntm assign $SESSION_NAME --watch --strategy=dependency --stop-when-done \
  --template-file=/tmp/swarm-template.md --no-cass-check
```

#### 6. Report

Tell the user:
- Session name and agent count (agents share the working tree; agent-mail file reservations prevent conflicts)
- Watch mode active with dependency-first strategy
- Monitor: `ntm activity $SESSION_NAME --watch`
- Progress: `/swarm-status`
- Stop: `/swarm kill`

---

### B. Assign a single bead

#### 1. Read the bead

```bash
br show $BEAD_ID --json 2>/dev/null
bv -robot-related $BEAD_ID 2>/dev/null | jq '.categories'
```

If not found or already closed, tell the user. Check dependencies — warn if any blocker is still open.

#### 2. Find target session and idle pane

```bash
ntm list 2>/dev/null
ntm activity <session> 2>/dev/null
```

Pick the first idle (WAITING) pane. If no session is running, offer to spawn one.

#### 3. Build a self-contained prompt

Write `/tmp/bead-$BEAD_ID.md` using the same template from section A.4, but with the bead's details inlined (description, acceptance criteria, notes, labels, dependencies, related beads) so the agent doesn't need to look them up.

Also include file impact info if the bead description mentions specific files:
```bash
bv -robot-impact <files> 2>/dev/null
```

#### 4. Reset context and assign

```bash
ntm interrupt <session> 2>/dev/null
sleep 3
ntm send <session> --pane=<N> --file=/tmp/bead-$BEAD_ID.md --no-cass-check
```

#### 5. Report

Tell the user which pane got the bead and how to monitor it.

---

### C. Stop the swarm

```bash
# Find active session
ntm list 2>/dev/null
ntm kill <session> 2>/dev/null || true
echo "Swarm stopped."

# Show remaining work
bv -robot-next 2>/dev/null | jq '{id, title, unblocks}'
```

Report how many beads are still open/ready.
