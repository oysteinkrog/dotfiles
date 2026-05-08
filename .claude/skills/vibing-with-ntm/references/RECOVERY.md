# Autonomous Recovery — Decision Tree & Error Taxonomy

<!-- TOC: Universal Flow | Error Taxonomy (CURSOR/QUOTA/ENTITY/SOURCE/REQUEST) | Stuck-Pane Ladder | Interactive Blockers | Saturated Context | build_slots | rch Sync | Mail Down | Coordinator Lies | Too-Broad Reservations | Bead Conflict | Incidents | Escalate To User -->

Every failure mode here is authorized for autonomous recovery. Do not ask the user — diagnose, act, and only surface if the documented escalation path fails.

## The Universal Recovery Flow

```
  ERROR / SYMPTOM
       │
       ▼
  1. Classify — what kind of failure (from the taxonomy below)?
       │
       ▼
  2. Probe — is the symptom real right now, or stale?
       │
       ▼
  3. Act — follow the per-class recipe (use --dry-run first when available)
       │
       ▼
  4. Verify — did it clear? Use --robot-is-working / --robot-health-oauth / git log
       │
       ▼
  5. Escalate (only after all documented steps fail)
```

Every recovery step is reversible or retryable. Never leave a half-restart or half-rotated account — always complete or explicitly roll back.

---

## Error Taxonomy

Mapped from `/dp/ntm/docs/robot-action-errors.md` and `robot-action-handoff-contract.md`.

### `CURSOR_*` — Event Stream Position Lost

**Symptom:** `CURSOR_EXPIRED`, `CURSOR_UNKNOWN`, empty `events.items[]` after a long wait.

**Cause:** Cursor is garbage-collected after ~1 hour. Orchestrator held it too long.

**Recovery:**

```bash
# Resync baseline and get fresh cursor
ntm --robot-snapshot  # new cursor in .cursor field
```

Do **not** try to reconstruct the missed events from logs — the snapshot is your new source of truth. Continue the loop from there.

### `QUOTA_*` — Provider Rate Limit

**Symptom:** `QUOTA_EXCEEDED`, or pane buffer shows "You've hit your limit · resets Xpm", or `--robot-is-working` returns `is_rate_limited: true`.

**CRITICAL:** The pane buffer message is **stale the moment it renders**. Always probe before trusting.

**Probe:**

```bash
# 1. Truth from the provider (not the pane)
ntm --robot-health-oauth=myproject | jq '.panes[] | {pane, provider, rate_limited, resets_at}'
ntm --robot-quota-status

# 2. Wake-ping the pane to check responsiveness
tmux send-keys -t myproject:0.4 "ping" Enter
sleep 5
ntm --robot-tail=myproject --lines=10 --panes=4
# If it pongs, the wall already lifted — dispatch work normally
```

**Recovery escalation:**

1. **Rotate account** (cod uses ChatGPT, cc uses Claude Max, gmi uses Gemini — different pools):

   ```bash
   ntm rotate myproject --all-limited                         # all rate-limited panes in one go
   ntm rotate myproject --pane=4 --account=jeff2718281@gmail.com
   ```

2. **Global CAAM switch** (when you know the next healthy account):

   ```bash
   ntm --robot-accounts-list --provider=claude | jq '.accounts[] | select(.healthy)'
   ntm --robot-switch-account=claude:jeff2718281
   ```

3. **Reset the pane entirely** (if rotate times out on a wedged CLI):

   ```bash
   ntm --robot-restart-pane=myproject --panes=4 --restart-prompt="$(cat marching_orders.txt)"
   ```

4. **Wait for the wall to drop** (use structured wait, not sleep):

   ```bash
   ntm --robot-wait=myproject --wait-until=rate_limited --timeout=30m
   # wakes when rate_limited becomes false
   ```

### `ENTITY_*` — Referenced Thing Is Missing

**Symptom:** `ENTITY_NOT_FOUND` on a session, pane, bead, or account reference.

**Common causes:**

- Session ended or was killed
- Bead was closed in another pane between your snapshot and act
- Account was disabled in CAAM

**Recovery:**

```bash
# Re-check existence and re-snapshot
ntm --robot-snapshot | jq ".sessions[] | select(.name == \"myproject\")"
br show <bead_id>  # confirm bead still exists
```

If the entity is really gone, pick a new target and continue. Do not retry the same operation.

### `SOURCE_*` — Data Source Degraded or Unavailable

**Symptom:** `--robot-snapshot` response has `source_health.<source>.status == "stale"` or `"unavailable"`.

Thresholds (from `/dp/ntm/docs/freshness-contract.md`):

| Source | Fresh | Stale | Critical / Unavailable |
| --- | --- | --- | --- |
| tmux | <5s | 5-30s | >30s or "no server running" |
| beads | <30s | 30-300s | >300s or daemon down |
| mail | <60s | 60-120s | >120s or MCP server 5xx |
| quota (caam) | <300s | 300-900s | >900s or auth failed |
| rch | <60s | 60-300s | >300s or ssh fail |

**Recovery decision rule:**

- **Fresh** → act normally.
- **Stale (below critical)** → act, but annotate. `ntm --robot-send=myproject --msg="NOTE: Beads data is ${stale_sec}s stale; use br list --json locally to confirm."`
- **Critical / Unavailable** → depending on source:
  - `tmux` down → cannot orchestrate. Restart tmux server; resume session.
  - `beads` daemon down → agents can still work; coordinator auto-assign disabled; manual `br update` still works.
  - `mail` down → **proceed without it**. Use `br update <bead> --assignee=<agent>` as soft coordination lock. Do NOT retry registration in a loop (common 4-hour block).
  - `quota` unreachable → conservative mode; don't rotate accounts until recovered.
  - `rch` down → route build/test via local `cargo/go/bun`; revisit rch with `--robot-diagnose`.

### `REQUEST_*` — Malformed Call

**Symptom:** `REQUEST_INVALID`, `REQUEST_SCHEMA_MISMATCH`.

**Cause:** Your command used deprecated flags or wrong types.

**Recovery:**

```bash
# Always query the registry to get the current shape
ntm --robot-help=<surface-name>
ntm --robot-schema=<response-type>
ntm --robot-capabilities | jq '.commands[] | select(.name=="<surface>")'
```

Deprecated → canonical flag mapping:

| Old | New |
| --- | --- |
| `--assign-beads=...` | `--beads=...` |
| `--assign-strategy=...` | `--strategy=...` |
| `ntm swarm ...` | `ntm spawn ...` |
| `ntm send --distribute` | `ntm --robot-bulk-assign=SESSION --strategy=dependency` |

---

## Stuck-Pane Escalation Ladder

Trigger: `--robot-health-restart-stuck` dry-run shows identical tail ≥3 ticks, no output growth, AND `git log --since="1 hour ago"` shows no new commits attributed to this pane.

Climb the ladder, don't skip steps. Each step has reversibility cost; stop when one works.

### Rung 1 — Wake ping (5 seconds, zero cost)

```bash
tmux send-keys -t myproject:0.5 "" Enter    # flush any pending paste buffer
sleep 3
ntm --robot-tail=myproject --lines=15 --panes=5
```

If tail advances, the pane was only idle — send real work.

### Rung 2 — Clear buffer + fresh prompt (20 seconds)

```bash
# Codex always needs this before a fresh send — TUI concatenates leftover buffer text
tmux send-keys -t myproject:0.5 Escape Escape Escape C-u
sleep 1
ntm --robot-send=myproject --panes=5 --msg="$(cat marching_orders.txt)"
```

### Rung 3 — Smart restart (60 seconds)

```bash
ntm --robot-smart-restart=myproject --panes=5 --prompt="$(cat marching_orders.txt)"
```

Smart restart re-checks activity and backs off if the pane started working mid-restart. Safe default.

### Rung 4 — Hard-kill smart restart (when graceful shutdown wedges on `/usage` or a confirm dialog)

```bash
ntm --robot-smart-restart=myproject --panes=5 --hard-kill --prompt="$(cat marching_orders.txt)"
```

### Rung 5 — Nuclear restart (tmux respawn-pane -k; bypasses CLI cooperation)

```bash
ntm --robot-restart-pane=myproject --panes=5 --restart-prompt="$(cat marching_orders.txt)"
# Or using a bead template:
ntm --robot-restart-pane=myproject --panes=5 --restart-bead=br-123
```

### Rung 6 — Kill and replace (last resort)

```bash
# Only if the pane is fundamentally broken (e.g., context saturated after 4+ days)
ntm add myproject --cc=1       # add a fresh pane
ntm kill myproject --pane=5    # remove the broken one
```

---

## Interactive Pane Blockers (Resolve Without Human)

These are dialogs inside the agent CLI that appear to "freeze" a pane. Every one is resolvable by the orchestrator.

### cc `/rate-limit-options` dialog

```bash
# Options typically: 1=Stop and wait, 2=Switch to extra usage, 3=Switch to Team plan
tmux send-keys -t myproject:0.2 "2" Enter
```

### codex `[Pasted text]` limbo

```bash
tmux send-keys -t myproject:0.5 "" Enter   # empty line submit = release the paste
```

### codex buffer corruption after interrupt

```bash
# ALWAYS before sending fresh prompts into a codex pane that had any prior interrupt:
tmux send-keys -t myproject:0.5 Escape Escape Escape C-u
# Only then:
ntm --robot-send=myproject --panes=5 --msg="..."
```

### cc `/usage` dialog that stuck the session

```bash
tmux send-keys -t myproject:0.0 Escape Escape Escape q     # close /usage
sleep 1
tmux send-keys -t myproject:0.0 Enter                      # submit empty line
```

### Double Ctrl-C to exit a wedged CLI

Single Ctrl-C usually only cancels the current prompt line. Double Ctrl-C within ~1s exits the CLI:

```bash
tmux send-keys -t myproject:0.5 C-c
sleep 0.3
tmux send-keys -t myproject:0.5 C-c
# Then relaunch with the alias (preserves bypass-approvals flags):
tmux send-keys -t myproject:0.5 "cod" Enter               # or "cc" / "gmi"
```

---

## Saturated-Context Preemptive Recovery

Auto-compaction loses the crisp "what I just discovered" state. Don't wait for it.

**Trigger:** `ntm --robot-context=myproject | jq '.panes[] | select(.context_used_pct > 85)'`

**Action:**

```bash
# Give the pane a "checkpoint + hand off" prompt BEFORE the auto-compact fires:
ntm --robot-send=myproject --panes=5 --msg="Context at 15%. Write a 5-line handoff note to bead br-xxx with current state, open questions, and exact next step. Then stop."

# Wait for the handoff to land, then restart:
ntm --robot-wait=myproject --wait-until=idle --panes=5 --timeout=3m
ntm --robot-restart-pane=myproject --panes=5 --restart-bead=br-xxx
```

A fresh pane on a clean context picking up a bead-scoped handoff outperforms a 4-day-old pane every time.

---

## Stale `build_slots` Leases

**Symptom:** "build slots disabled" or operations blocked when `WORKTREES_ENABLED=0`.

**Cause:** Switching between worktree/non-worktree mode leaves 1-hour leases active.

**Recovery:**

```bash
# See active leases
ntm --robot-snapshot | jq '.build_slots.leases'

# Force-release a stale lease
ntm mail force-release-build-slot <lease_id> --note "stale after worktree mode switch"

# Or wait out the TTL (≤1 hour)
```

---

## `rch` File-Sync Gotcha

**Symptom:** Tests run against stale code on the remote worker; edits don't show up.

**Cause:** `rch exec` only syncs paths included in `transfer.extra_sync_dirs` config.

**Recovery:**

```bash
# Check the config
cat ~/.rch/config.toml | grep -A5 '^\[transfer\]'

# Add the directory you're editing if missing
# (edit ~/.rch/config.toml to add path to transfer.extra_sync_dirs)

# Or force a one-shot sync
rch sync --include-paths=<missing_dir>

# Or fall back to local build if rch is unhealthy
cargo test --lib
```

---

## MCP Agent Mail Down

**Symptom:** `send_message` / `file_reservation_paths` / `register_agent` all return "server unavailable" or time out.

**Do NOT:** retry registration in a loop — this is a 4-hour silent block.

**Do:**

```bash
# 1. Confirm it's really down
ntm --robot-snapshot | jq '.source_health.mail'

# 2. Fall back to bead-assignee as soft lock
br update <bead_id> --status=in_progress --assignee=<agent_name>

# 3. Coordinate via bead comments, not mail
br show <bead_id>  # read others' progress notes
# update with progress via `br update --description-append="..."` or equivalent

# 4. Proceed. Mail is advisory, not required.
```

Return to mail once `source_health.mail.status == "fresh"` again. Back-propagate important coordination as mail messages at that time if needed.

---

## Coordinator Digest Swallowed Error

**Symptom:** `ntm coordinator digest myproject` reports "no conflicts" but real conflicts exist.

**Cause:** Known swallowed-error path in `/dp/ntm/internal/coordinator/digest.go`.

**Recovery:**

```bash
# Cross-check with a separate code path
ntm coordinator conflicts myproject

# Or run with verbose to surface internal errors
ntm coordinator digest myproject --verbose 2>&1 | grep -i "error\|warn"
```

When results differ, trust `conflicts` over `digest`.

---

## Too-Broad Reservations Blocking the Swarm

**Symptom:** Multiple agents report `FILE_RESERVATION_CONFLICT` on unrelated files.

**Cause:** Someone reserved `**/*.rs`, `**`, or `/absolute/path`.

**Detection:**

```bash
ntm locks list myproject --all-agents --json | jq '.reservations[] | select(.paths[] | test("^\\*\\*|^/|^\\*$"))'
```

**Recovery:**

```bash
# Force-release the over-broad lease
ntm locks force-release myproject <lease_id> --note "too-broad pattern blocking swarm"

# Message the owner to use narrower patterns
ntm --robot-send=myproject --panes=<owner_pane> --msg="Your reservation <pattern> is too broad. Re-reserve with specific file paths or narrow globs (e.g. crates/foo/src/bar.rs, not **/*.rs)."
```

---

## Bead Assignee Conflict Without Mail Ping-Pong

**Symptom:** You want to reassign a bead currently assigned to a saturated pane.

**Do NOT:** send a mail message asking permission — the saturated pane may be days from responding.

**Do:**

```bash
# 1. Flip status to open (releases the assignee gate)
br update <bead_id> --status=open

# 2. Reassign via coordinator
ntm assign myproject --auto --strategy=dependency

# 3. Or claim directly for a specific pane
ntm --robot-bead-claim=<bead_id> --bead-assignee=<agent>
```

---

## Incident Lifecycle (when alerts escalate)

From `/dp/ntm/docs/incident-taxonomy.md`. Alerts promote to incidents after crossing thresholds.

| Family | Promotion Trigger | Operator Response |
| --- | --- | --- |
| `agent.crash_loop` | 3+ crashes in 30 min | Restart pane; check env; reduce scope |
| `quota.exceeded` | Provider rate wall held ≥15 min | Rotate all affected panes; pause that provider type |
| `coordination.conflict_unresolved` | File conflict ≥15 min | Force-release one side; narrow reservation |
| `source.unavailable_critical` | Source degraded ≥15 min | Check underlying service; fall back (mail→bead-lock) |
| `session.saturated_ctx` | ≥2 panes with context >90% | Preemptive-restart; handoff to bead |

Query current incidents:

```bash
ntm --robot-snapshot | jq '.incidents[]'
```

Resolve explicitly once the root cause is fixed (keeps the operator log honest):

```bash
# Currently ntm does not expose direct incident close via robot mode;
# resolve via coordinator status once the underlying trigger clears
ntm coordinator status myproject
```

---

## When To Actually Escalate To The User

Only escalate after:

- Cursor resync failed twice
- Account rotation exhausted available accounts (`--robot-accounts-list` shows none healthy)
- Nuclear restart still produces the same symptom
- `source_health` critical for >30 min AND no progress on the underlying service

Escalation surface:

> "P4 stuck after 5 recovery attempts (wake-ping, smart-restart, hard-kill, restart-pane, account-rotation). Last tail: `<copy last 10 lines>`. Attempted accounts: `<list>`. Recommend: manual `tmux kill-session myproject && ntm spawn myproject ...` OR bind a new account to `caam`."

Never escalate with just "stuck" — always include what you tried, in what order, and what you think the next step should be.
