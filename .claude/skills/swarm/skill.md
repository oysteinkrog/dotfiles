# Swarm

Start and manage a swarm of coding agents that implement beads from the issue tracker.

## When to activate

Activate when the user says:
- "swarm" / "start swarm" / "launch swarm" / "run swarm"
- "assign bead X" / "run bead X"
- "start agents" / "spawn agents"

## Arguments

- `$ARGUMENTS` — optional flags/overrides, e.g. `4` (agent count), `bd-xxx` (single bead), `kill` (stop swarm)

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

# Show what's ready
echo "=== Ready beads ==="
br ready 2>/dev/null

# Show execution tracks
echo "=== Parallel tracks ==="
bv -robot-plan 2>/dev/null | jq '.plan.summary'
```

If agent-mail is not running, warn and suggest `am`.

#### 2. Spawn session

Agent count from `$ARGUMENTS` or default 4:

```bash
ntm spawn atlas-swarm --cc=$AGENT_COUNT --no-user --worktrees --stagger-mode=smart --no-cass-check
```

#### 3. Write the prompt template

Write to `/tmp/swarm-template.md`. This is the universal template — it reads the bead at runtime to determine behavior:

```
Read CLAUDE.md first — especially the "Rust Rewrite — Code Guidelines" section.

## Your Task

Run this to get your full assignment:
  br show {BEAD_ID} --json 2>/dev/null

Read the description, acceptance_criteria, notes, and labels carefully.

## Adapt to bead type

Check the bead's labels and adjust your approach:

**If labels include "spike" or title starts with "Spike:"**
- This is research/validation, not production code
- Create test code in rust/spikes/{BEAD_ID}/
- Document findings in bead notes: br update {BEAD_ID} --notes "## Findings\n..."
- If the spike FAILS, document what went wrong and suggest alternatives

**If labels include "frontend", "ws5", or "ws6" (and no "rust")**
- Work in packages/frontend/src/
- No Rust rules apply — use TypeScript/React conventions from the existing code
- Read the existing TS code to understand patterns before changing anything

**If labels include "docs", "ci", or "infra"**
- Follow the conventions already in the repo
- Don't add unnecessary complexity

**Otherwise (default: Rust implementation)**
- Read the existing TypeScript implementation in packages/backend/src/ for reference
- Runtime: asupersync (NOT tokio). Every async fn takes &Cx as first param.
- Return type: Outcome<T, E> for async, Result<T, E> for sync helpers
- Web framework: fastapi_rust (NOT axum)
- Database: frankensqlite (synchronous, wrap in spawn_blocking)
- NEVER import from tokio, reqwest, or hyper
- JSON API contract — match TS server response shapes EXACTLY:
  - enabled/auto_approve are integers (0/1), not booleans
  - tool_calls are JSON-as-string, not nested objects
  - Request bodies: camelCase. Responses: snake_case.
  - Some arrays wrapped: { items: [...] } not bare [...]
  - Dates: ISO 8601 strings
  - Errors: { error: "message" }
  - If golden file exists at rust/tests/golden/, match it exactly

## Workflow

1. Read the bead fully (br show {BEAD_ID})
2. Understand what the bead builds on (check its dependencies)
3. For Rust beads: read the corresponding TS files for reference behavior
4. Implement according to acceptance criteria
5. Run appropriate checks:
   - Rust: cargo check -p <crate> && cargo test -p <crate> && cargo clippy -p <crate> -- -D warnings
   - Frontend: npm test (from packages/frontend/)
   - Docs/CI: validate manually
6. Commit ONLY files you changed:
   git add <specific files>
   git commit -m "feat({BEAD_ID}): short description"
7. Close the bead:
   br close {BEAD_ID}
8. STOP. Do not start another bead. Wait for the next assignment.
```

#### 4. Start watch mode

```bash
ntm assign atlas-swarm --watch --strategy=dependency --stop-when-done \
  --template-file=/tmp/swarm-template.md --no-cass-check
```

#### 5. Report

Tell the user:
- Session `atlas-swarm` launched with N agents in worktree-isolated branches
- Watch mode active — beads assigned automatically by dependency priority
- Monitor: `ntm activity atlas-swarm --watch`
- Progress: `/swarm-status`
- Stop: `/swarm kill`

---

### B. Assign a single bead

#### 1. Read the bead

```bash
br show $BEAD_ID --json 2>/dev/null
```

If not found or already closed, tell the user. Check dependencies — warn if any blocker is still open.

#### 2. Find target session and idle pane

```bash
ntm list 2>/dev/null
ntm activity <session> 2>/dev/null
```

Pick the first idle (WAITING) pane.

#### 3. Build a self-contained prompt

Get bead details with `br show $BEAD_ID` and write `/tmp/bead-$BEAD_ID.md` using the same universal template from section A.3, but with the bead details inlined (description, acceptance criteria, notes, labels, dependencies) so the agent doesn't need to look them up.

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
ntm kill atlas-swarm 2>/dev/null || true
echo "Swarm stopped."
br ready 2>/dev/null | head -5
```

Report how many beads are still open/ready.
