# Operator Cards — Operationalized Field Expertise

<!-- TOC: OC-001 Ping Before Rotate | OC-002 Rotate By Pool | OC-003 Three-Ticks Escalation | OC-004 Prose Is Not Progress | OC-005 Track claimed | OC-006 Explicit Domain | OC-007 Mail Down Fallback | OC-008 Broad Reservations | OC-009 Pre-empt Compaction | OC-010 Specific-Terse | OC-011 Saturated Replacement | OC-012 Source Health First | OC-013 --skip-first | OC-014 Double Ctrl-C | OC-015 Bead Status Flip | OC-016 Convergence Termination | OC-017 Palette Edit-Before-Send | OC-018 rch Sync Config | OC-019 Coordinator Can Lie | OC-020 Narrow Scope | OC-021 Macro Start-Session | OC-022 Cron The Loop | OC-023 Pre-Dispatch Hygiene | OC-024 Handoff Notes | OC-025 Done = Push + Close -->

Each card codifies one lesson from real multi-agent swarm operation across many projects. Structure follows the `operationalizing-expertise` methodology: **trigger → failure mode → recipe → prompt module → validator**.

Cite these cards by ID in swarm post-mortems. Future-you will recognize patterns faster.

---

## OC-001 — Ping Before You Rotate

**Trigger.** A pane shows "You've hit your limit · resets 3pm". Orchestrator about to rotate or restart.

**Failure mode (observed).** Agents trust the message, wait hours, miss the fact that the wall lifted long ago.

**Recipe.**

```bash
tmux send-keys -t <session>:0.<pane> "ping" Enter
sleep 5
ntm --robot-tail=<session> --lines=10 --panes=<pane>
# If it pongs, the wall already cleared — dispatch real work
# If still silent, consult --robot-health-oauth before rotating
```

**Prompt module (to send if pane was alive):**

```text
Welcome back. Identify as agent '<name>' for this swarm. Run bv --robot-triage | jq '.recommendations[:3]', claim one, reserve the files, code it. No prose; ship a commit or surface a blocker within 60 min.
```

**Validator.**

```bash
# Succeeded if:
#   - Pane tail advanced after ping
#   - OR --robot-is-working.is_rate_limited = false
#   - AND pane committed to git within 1 hour
```

---

## OC-002 — Rotate By Pool, Not By Pane

**Trigger.** Multiple panes hit rate limits, but not all providers are out.

**Failure mode.** Operator rotates every pane mechanically; burns working accounts, hits the same wall again.

**Recipe.**

```bash
# Check pool health per provider
ntm --robot-health-oauth=<session> | jq '.panes | group_by(.provider) | map({provider: .[0].provider, any_rate_limited: any(.rate_limited)})'

# Only rotate panes whose pool is depleted
ntm rotate <session> --all-limited
# Or surgical, if you know which provider is out:
ntm --robot-switch-account=claude:<healthy_account>
```

**Decision matrix.**

| Provider | Pool | Agents drawing from it |
| --- | --- | --- |
| Anthropic | Claude Max subscription | `cc` |
| OpenAI | ChatGPT Pro subscription | `cod` |
| Google | Gemini Ultra | `gmi` |

**Prompt module (to send after rotation):**

```text
Your pane was rotated to a fresh account (~full quota). Resume from the bead you were on; its assignee/reservations still hold. If your last output was mid-commit, `git status` to reconcile before continuing.
```

**Validator.** `ntm --robot-accounts-list --provider=<p>` shows ≥1 healthy account remaining; swarm productivity recovers within 2 ticks.

---

## OC-003 — Three Ticks, Then Escalate

**Trigger.** Pane tail looks identical across three consecutive orchestrator ticks. Output length unchanged.

**Failure mode.** Operator pastes nudge #4, #5, #6 into a dead buffer while believing work is happening.

**Recipe (strict escalation ladder — do not skip rungs):**

```
Rung 1 (tick N):    Wake ping (tmux send-keys "" Enter)
Rung 2 (tick N+1):  C-u + re-send marching orders via --robot-send
Rung 3 (tick N+2):  --robot-smart-restart
Rung 4 (tick N+3):  --robot-smart-restart --hard-kill
Rung 5 (tick N+4):  --robot-restart-pane (tmux respawn-pane -k)
Rung 6 (tick N+5):  ntm add + ntm kill (replace the pane)
```

**Rule:** Never stay on the same rung for two ticks. Either it worked → new activity is visible, or climb.

**Validator.**

```bash
ntm --robot-health-restart-stuck=<session> --stuck-threshold=10m --dry-run | jq '.stuck_panes | length'
# Should decrease monotonically as you climb the ladder
```

---

## OC-004 — Prose Is Not Progress

**Trigger.** Pane is actively generating tokens (`is_working=true`) but `git log --since="1 hour ago"` attributed to that pane shows 0 new commits.

**Failure mode.** The "swarm is productive" illusion — panes narrate mental models, exemplary self-reviews, subsystem walkthroughs. Zero code lands.

**Recipe.**

```bash
# Immediately dispatch the Ship-or-Surface prompt (see PROMPTS.md)
ntm --robot-send=<session> --panes=<pane> --msg="$(cat prompts/ship_or_surface.txt)"

# If another tick passes with no commit, move to stuck-pane escalation
```

**Prompt module.** Ship-or-Surface (see PROMPTS.md for full text):

```text
STOP writing prose. Pick ONE open bead under 60 min. Claim, reserve, code the diff, run the repo's verify command, commit, close. Do not file new review beads until backlog < 100. If you cannot commit within 60 min, write a 3-line blocker note and move on.
```

**Validator.** At least one new commit attributed to this pane within 90 min of the prompt landing.

---

## OC-005 — Track `claimed`, Not Just `open + in_progress`

**Trigger.** Orchestrator reports backlog of N items but the bead database shows N+50 because `claimed` was missed.

**Failure mode.** Operator decides the swarm has "no work" and winds down, while 50 claimed beads sit orphaned on saturated panes.

**Recipe.**

```bash
# Always check all three active statuses
br list --status=open,claimed,in_progress --json | jq '.issues | length'

# Separate them for triage
br list --status=claimed --json | jq '.issues[] | {id, assignee, updated_at}'
```

**Prompt module (to free a stale claim):**

```text
Bead <id> is claimed by <assignee> but has not progressed in >2h. Flip to open and reassign:
  br update <id> --status=open
  ntm --robot-bead-claim=<id> --bead-assignee=<new_agent>
Do not mail-ping the old assignee — the pane may be days from responding.
```

**Validator.** `br list --status=claimed | jq '[.issues[] | select(.updated_at < (now - 7200))] | length'` → 0.

---

## OC-006 — Explicit Domain, Zero Collisions

**Trigger.** Spawning ≥3 agents in a multi-crate/multi-directory workspace.

**Failure mode.** Two agents claim overlapping beads; edits collide; both re-work because commits cross-wire.

**Recipe (at spawn, before any work):**

```bash
ntm spawn <session> --cc=N --cod=M --gmi=P

# Assign explicit domains — do this IN the marching orders, not as a note
ntm --robot-send=<session> --panes=1 --msg="Pane 1 cc: OWN crates/foo. Do not edit outside your domain without reserving first."
ntm --robot-send=<session> --panes=2 --msg="Pane 2 cod: OWN crates/bar and tests/bar/. ..."
# ... one dispatch per pane

# Enable coordinator auto-assign to catch any drift
ntm coordinator enable auto-assign
ntm coordinator enable digest --interval=15m
```

**Prompt module (domain assignment):**

```text
You are pane <N> (<cc|cod|gmi>). Your crate/directory domain is <scope>. Do not edit outside this domain without reserving the files AND announcing cross-domain work in your commit message. Ready-work search is scoped to issues labeled or pathed inside your domain. If none ready, surface and stop — don't silently pick up work outside your domain.
```

**Validator.** `ntm coordinator conflicts <session>` returns 0 file-overlap conflicts per tick.

---

## OC-007 — Agent Mail Down Is Not Agent Mail Blocked

**Trigger.** `send_message` / `file_reservation_paths` return "server unavailable" or time out.

**Failure mode.** Agents retry `register_agent` in a loop for hours. Zero code lands.

**Recipe.**

```bash
# Confirm real unavailability (not just your pane)
ntm --robot-snapshot | jq '.source_health.mail'

# Fall back to bead-assignee as soft coordination lock
br update <bead_id> --status=in_progress --assignee=<agent_name>

# Coordinate via bead descriptions (free-text; everyone can read)
br update <bead_id> --description-append="<progress note>"

# Do NOT retry registration in a loop
```

**Prompt module (to send when mail is down):**

```text
Agent Mail server is unavailable (source_health.mail.status = "unavailable"). Do NOT retry registration. Coordinate via br update --assignee=<name> as soft lock, br description for progress notes. Proceed with work; mail will reconcile when service returns.
```

**Validator.** Commits continue to land (git log), even while mail is down. `ps -ef | grep mcp-agent-mail` is not required to be running for work to progress.

---

## OC-008 — Broad Reservations Are Sabotage

**Trigger.** `ntm --robot-snapshot | jq '.reservations[] | select(.paths[] | test("^\\*\\*|^/|^\\*$"))'` returns entries.

**Failure mode.** One agent reserves `**/*.rs` or `**`; the whole swarm blocks on every file.

**Recipe.**

```bash
# Detect
ntm locks list <session> --all-agents --json | jq '.reservations[] | select(.paths[] | test("^\\*\\*|^/|^\\*$"))'

# Force-release
ntm locks force-release <session> <lease_id> --note "too-broad pattern"

# Educate (one-shot prompt)
ntm --robot-send=<session> --panes=<owner_pane> --msg="Your reservation '<pattern>' was too broad and blocked others. Re-reserve specific paths (e.g. crates/foo/src/bar.rs). Patterns like **/*.ext or leading-/ are never acceptable."
```

**Validator.** No reservations match the too-broad pattern test.

---

## OC-009 — Pre-empt Compaction, Don't Survive It

**Trigger.** `ntm --robot-context=<session> | jq '.panes[] | select(.context_used_pct > 85)'` returns entries.

**Failure mode.** Auto-compact at ≤10% summarizes the crisp "what I just discovered" state into vague bullets; next prompt fetches nothing useful.

**Recipe.**

```bash
# 1. Tell the saturated pane to write a concrete handoff BEFORE compaction
ntm --robot-send=<session> --panes=<pane> --msg="Context at ${pct}%. Immediately: write a 5-line handoff note to bead <id> — current state, one open question, exact next step. Do not do any new work."

# 2. Wait for the handoff to land
ntm --robot-wait=<session> --wait-until=idle --panes=<pane> --timeout=3m

# 3. Restart the pane with fresh context on that bead
ntm --robot-restart-pane=<session> --panes=<pane> --restart-bead=<id>
```

**Validator.** New pane's first commit continues the thread set in the handoff note.

---

## OC-010 — Specific-Terse, Not Generic-Terse

**Trigger.** You've been sending short nudges ("Next review.", "Keep going.", "Continue.") for several ticks.

**Failure mode.** Prompt degradation. Downstream work becomes proportionally shallow; reviews go from finding bugs to rubber-stamping.

**Recipe.** Every nudge must include:

1. **Specific verb** — "Claim and ship bead br-xxx" not "keep working"
2. **Specific target** — the bead ID, file path, or test name
3. **Specific exit condition** — the commit SHA or blocker note

If you cannot name a specific target in one sentence, **stop nudging** — the swarm is done or needs a different scope.

**Prompt module.**

```text
Next bead: <id or 2-sentence problem>. Claim. Reserve <file-pattern>. Code the diff. Run <repo's verify command>. Commit. Close. Report back only with the commit SHA or a concrete blocker.
```

**Validator.** Commits per hour per pane; target ≥1 for active panes.

---

## OC-011 — Saturated Context Replacement Over Rehabilitation

**Trigger.** A cc pane has been running ≥4 days. Work is circular; suggestions recycle earlier ideas.

**Failure mode.** Operator keeps "helping" the saturated pane with more hints. Every hint consumes more of its remaining context.

**Recipe.**

```bash
# Check age
tmux list-panes -t <session> -F '#{pane_index} #{pane_start_time}'

# If pane age > 4 days OR context_used_pct > 90:
ntm --robot-restart-pane=<session> --panes=<pane> --restart-bead=<id>

# Preserve in-flight work by naming the bead the pane was on
```

**Validator.** Fresh pane produces a useful commit on the assigned bead within 30 min.

---

## OC-012 — Source-Health Before Acting

**Trigger.** About to make a state-changing action based on `--robot-snapshot` data.

**Failure mode.** Acting on stale `beads` or `mail` data → wrong bead claimed, wrong assignment, wasted cycle.

**Recipe.**

```bash
# Before any state-changing action, check source_health
SNAP=$(ntm --robot-snapshot)
echo "$SNAP" | jq '.source_health | to_entries[] | {source: .key, status: .value.status, freshness_sec: .value.freshness_sec}'

# If source is stale (beyond its tier's threshold):
#   beads: re-run `br list --json` locally
#   mail: re-run `ntm --robot-mail-check`
#   quota: re-run `ntm --robot-health-oauth=<session>`
# Only then act.
```

**Validator.** Every major dispatch cycle logs a freshness line; stale sources re-checked before acting on them.

---

## OC-013 — --skip-first Is Not Optional

**Trigger.** Broadcasting a prompt via `ntm send --all`.

**Failure mode.** The prompt lands in your own user pane (pane 0 or 1 depending on tmux pane-base-index) as a zsh command, producing `zsh: command not found: <first-word-of-prompt>`. Worse, the prompt doesn't land on actual agents either if wrapping/quoting collides.

**Recipe.**

```bash
# ALWAYS use --skip-first (or -s) when broadcasting
ntm send <session> --all --skip-first --no-cass-check "<prompt>"

# Or target explicit agent pane list
ntm send <session> --panes=2,3,4,5 "<prompt>"

# Or use --robot-send which excludes the user pane by default
ntm --robot-send=<session> --msg="<prompt>"   # no --all flag → excludes user pane automatically
```

**Validator.** Last line of user pane is not `zsh: command not found: ...`.

---

## OC-014 — Double Ctrl-C For Wedged CLIs

**Trigger.** A cc or gmi CLI is wedged; `C-c` once just clears the current line.

**Failure mode.** Operator pastes more prompts into a pane where the CLI is broken.

**Recipe.**

```bash
# Double Ctrl-C within ~1s exits the wedged CLI
tmux send-keys -t <session>:0.<pane> C-c
sleep 0.3
tmux send-keys -t <session>:0.<pane> C-c

# Then relaunch via the repo alias (preserves --dangerously-bypass flags)
tmux send-keys -t <session>:0.<pane> "cc" Enter        # or "cod" / "gmi"

# Re-send marching orders
ntm --robot-send=<session> --panes=<pane> --msg="$(cat marching_orders.txt)"
```

**Validator.** `ps -ef | grep -E "(claude|codex|gemini)" | grep <pane_pid>` shows a fresh process.

---

## OC-015 — Bead Status Flip Beats Mail Ping-Pong

**Trigger.** You need to reassign a bead currently claimed by a saturated pane.

**Failure mode.** Sending "please release bead br-xxx" via mail waits hours for a response from a pane that may be down.

**Recipe.**

```bash
# Don't wait. Flip the status.
br update <bead_id> --status=open

# Reassign via coordinator
ntm assign <session> --auto --strategy=dependency

# Or direct claim
ntm --robot-bead-claim=<bead_id> --bead-assignee=<new_agent>
```

**Rule.** Mail is for coordination nuance; bead status is for ownership. Don't conflate them.

**Validator.** `br list --status=in_progress --json | jq '.issues[] | select(.id=="<bead_id>") | .assignee'` shows the new agent within 2 min.

---

## OC-016 — Convergence Termination Is Mandatory

**Trigger.** After a tending run, the orchestrator keeps looping even though commits have stopped.

**Failure mode.** Infinite nudging. Every tick produces more "exemplary" prose. Tokens wasted, user annoyed.

**Recipe.** Hard stop when ALL three conditions hold:

1. `git log --since="1 hour ago" --author=<swarm-account>` = 0
2. ≥2 consecutive ticks: every pane's tail contains convergence language (see list in ANTI-PATTERNS.md)
3. `br ready --json` = 0 AND `br list --status=in_progress,claimed` unchanged between ticks

```bash
CONV=0
for tick in $(seq 1 20); do
  commits=$(git -C "$REPO" log --since="1 hour ago" --oneline | wc -l)
  ready=$(br ready --json | jq '.issues | length')
  inflight=$(br list --status=in_progress,claimed --json | jq '.issues | length')

  if [ "$commits" -eq 0 ] && [ "$ready" -eq 0 ] && [ "$inflight" -eq "$PREV_INFLIGHT" ]; then
    CONV=$((CONV+1))
    [ "$CONV" -ge 2 ] && { echo "CONVERGED — exit"; break; }
  else
    CONV=0
  fi
  PREV_INFLIGHT=$inflight
  sleep 600
done
```

**Validator.** Loop exited cleanly; final message to user includes commit count, closed beads, and explicit "swarm converged" statement.

---

## OC-017 — Palette Edit-Before-Send For Template Prompts

**Trigger.** You're about to re-use a saved dispatch prompt that contains a bead ID ("fix bd-3qoly").

**Failure mode.** The bead in the template is already closed; the prompt lands in a session where it's irrelevant; agent wastes a tick investigating.

**Recipe.**

```bash
# Use palette edit-before-send (ntm commit ad20c3e1+)
# Ctrl-P to open palette, select template, 'e' to edit, then send
# OR adjust the message in the command line before dispatch
ntm send <session> --template=next-bead --var bead_id=br-$ACTUAL_ID --no-cass-check
```

**Rule.** Never dispatch templates with stale IDs. Either substitute via `--var` or edit-before-send.

**Validator.** Bead IDs in recent dispatches match currently-open beads, not stale ones.

---

## OC-018 — rch Sync Is Not Universal

**Trigger.** Tests run fine locally but fail on the remote rch worker with "file not found" or stale behavior.

**Failure mode.** Agents assume `rch exec` rsyncs everything; in fact, only paths listed in `transfer.extra_sync_dirs` sync.

**Recipe.**

```bash
# Check config
grep -A10 '^\[transfer\]' ~/.rch/config.toml

# Add missing directory
# (edit ~/.rch/config.toml, append the path to transfer.extra_sync_dirs)

# Or force one-shot sync
rch sync --include-paths=crates/mynew-crate

# Or fall back to local until rch config is updated
cargo test --lib --package mynew-crate
```

**Validator.** Remote tests use the newest local edit; `rch exec md5sum <file>` matches local `md5sum`.

---

## OC-019 — Coordinator Digest Can Lie

**Trigger.** `ntm coordinator digest <session>` returns "no conflicts" but agents report `FILE_RESERVATION_CONFLICT`.

**Failure mode.** Orchestrator trusts digest; conflicts persist; productivity drops without explanation.

**Recipe.**

```bash
# Cross-check digest with conflicts (separate code path)
DIGEST_CONFLICTS=$(ntm coordinator digest <session> | jq '.conflicts | length')
ACTUAL_CONFLICTS=$(ntm coordinator conflicts <session> | jq '.conflicts | length')

if [ "$DIGEST_CONFLICTS" != "$ACTUAL_CONFLICTS" ]; then
  echo "DIGEST LYING: digest=$DIGEST_CONFLICTS actual=$ACTUAL_CONFLICTS"
  # Trust conflicts; investigate digest separately
fi
```

**Rule.** When two `ntm coordinator ...` surfaces disagree, trust the more specific one.

**Validator.** `ntm coordinator digest` and `ntm coordinator conflicts` report consistent counts after resolution.

---

## OC-020 — Narrow Scope Before Widening

**Trigger.** You want to spawn a 7+ repo swarm with 20+ panes.

**Failure mode.** Operator's attention cannot keep up. Panes sit idle at prompt boxes for hours before being nudged. Throughput drops below 3-project baseline.

**Recipe (tier decision).**

| Operator | Max projects | Max panes/project |
| --- | --- | --- |
| Single human orchestrator | 1 | 6 |
| Single AI orchestrator | 3 | 6 (≤18 total) |
| Meta-orchestrator + per-project orchestrators | 7+ | 6 per project |

Beyond these, you need 2-tier orchestration (meta + per-project). Do not exceed the tier limit.

**Rule.** Narrow first. Prove steady-state productivity at 3×6. Then scale with 2-tier.

**Validator.** Every active pane has been nudged at most 1 tick ago; no pane has been idle >2 ticks without diagnosis.

---

## OC-021 — Macro Start-of-Session Beats Granular

**Trigger.** Starting a new swarm session. You're about to run 8+ individual registration/reservation commands.

**Failure mode.** Granular setup is slow, error-prone, and non-idempotent. Different agents' setups drift.

**Recipe (use Agent Mail macros when mail is healthy):**

```python
mcp__mcp-agent-mail__macro_start_session(
    project_key="/data/projects/foo",
    agent_name="GreenCastle",
    program="claude-code",
    model="claude-opus-4-7",
    initial_reservations=["crates/foo/**"],
    ttl_seconds=3600,
    introduce_to=["BlueOcean", "RedCanyon"]  # auto-handshake
)
```

For the orchestrator side:

```bash
ntm spawn <session> --cc=3 --cod=2 --gmi=1 --stagger-mode=smart \
  --prompt "$(cat marching_orders.txt)" \
  --worktrees   # if repo policy allows
```

**Rule.** Macros bundle register + reserve + introduce + inbox-fetch. Use them unless you specifically need granular control.

**Validator.** All agents register within 30s of session start; no registration retry loops.

---

## OC-022 — Cron The Operator Loop (Don't Hand-Tick)

**Trigger.** Manually tending a swarm for >30 min.

**Failure mode.** Operator forgets ticks; misses rate limits; misses stuck panes; swarm drifts.

**Recipe.** Use `CronCreate` (or `/loop 15m`) to run the orchestrator loop.

```text
# Example schedule prompt
Every 15 minutes: run one orchestrator tick for session <session>. Use `/vibing-with-ntm` Operator Loop recipe. If convergence detected (see OC-016), report and exit.
```

Or use the `/loop` skill for self-paced iteration. Or use a shell cron:

```bash
crontab -l | grep -v "orchestrator-tick" > /tmp/cron.new
echo "*/15 * * * * cd /data/projects/foo && /usr/local/bin/ntm-tick.sh >> /tmp/tick.log 2>&1" >> /tmp/cron.new
crontab /tmp/cron.new
```

**Rule.** If you're orchestrating for ≥30 min, automate the cadence. Every minute you hand-tick is a minute you should be coding.

**Validator.** Cron logs show every tick ran; no gap >20 min.

---

## OC-023 — Pre-Dispatch Hygiene Checklist

**Trigger.** About to send a non-trivial dispatch.

**Failure mode.** Dispatch lands with stale bead ID, wrong pane target, or duplicate of a recent prompt; wastes the tick.

**Recipe (pre-flight):**

```bash
# 1. Freshness
ntm --robot-snapshot | jq '.source_health'

# 2. Target is actually idle
ntm --robot-is-working=<session> --panes=<pane> | jq '.panes[] | .is_idle'

# 3. Reservation won't collide
ntm coordinator conflicts <session> | jq '.conflicts[] | select(.paths[] | test("<my_pattern>"))'

# 4. No duplicate recent prompt
ntm history search "<first 20 words of prompt>" --days=1 | head -5

# 5. Dispatch with --no-cass-check in orchestrator loops
ntm send <session> --pane=<pane> --no-cass-check "$(cat prompt.txt)"
```

**Validator.** Pre-flight passes before every non-trivial dispatch. Post-flight `ntm --robot-tail` shows the prompt actually rendered.

---

## OC-024 — Handoff Notes Beat Mail Replays

**Trigger.** A pane is ending its session (compaction, restart, shutdown).

**Failure mode.** The next pane on that bead has to re-discover everything from mail history.

**Recipe.**

```text
Before stopping, append a 5-line handoff note to bead <id> description:
  - What I did (commit SHAs if any)
  - Where I am (file, function, line)
  - One open question
  - The exact next step a fresh pane should take
  - Any gotcha (broken build, flaky test, etc.)

Then: `br update <id> --status=open` so the next agent can claim.
```

**Validator.** Fresh pane picks up the bead and advances it within 30 min without re-asking clarifying questions.

---

## OC-025 — "Done" Is Commits + Closed Beads + Push

**Trigger.** A pane reports "I've finished the bead."

**Failure mode.** "Finished" means different things: wrote code / ran tests / committed / pushed / closed bead. Skipping any step = work lost.

**Recipe (definition of done):**

```bash
# 1. Code exists
git status   # working tree clean

# 2. Tests pass locally (or per repo rules)
<repo-specific verify command>

# 3. Committed
git log -1   # shows my commit

# 4. Pushed
git push
git status   # "up to date with origin"

# 5. Beads closed
br close <bead_id> --reason="Completed"

# 6. Reservation released
ntm locks release <session> --paths="<pattern>"  # if using file reservations

# 7. Final mail reply (if thread open)
# send_message(thread_id="beads-<id>", subject="[beads-<id>] Completed", body="<summary>")
```

**Validator.** `br list --status=closed --id=<bead_id>` exists; `git push` succeeded; working tree clean.

---

## How To Use These Cards

- **In a swarm post-mortem:** "We hit OC-001 (rate limit probe) and OC-003 (stuck pane escalation). Root cause: OC-005 (missed claimed status)."
- **In a prompt:** "Follow OC-004 (Ship-or-Surface) immediately."
- **In a dispatch:** link the card ID from the marching orders.
- **In a new session:** scan the trigger list at the top of each card — any matches? Act preemptively.

Every card has a trigger and a validator. If neither fires, the card doesn't apply. If both fire regularly, it's a load-bearing pattern.
