# Anti-Patterns — Concrete, Named, With Fixes

<!-- TOC: Dispatch & Prompt (AP-1..6) | Observation & Monitoring (AP-7..12) | Pane Lifecycle (AP-13..18) | Coordination (AP-19..24) | Scale & Cadence (AP-25..28) | Dev-Loop (AP-29..33) | Meta/Orchestrator (AP-34..38) | Convergence Language Dictionary | How To Extend -->

Every entry is a pattern observed in real swarm sessions. Organized by where in the orchestration flow they occur. Fix each by following the linked operator card or recipe.

---

## Dispatch & Prompt Anti-Patterns

### AP-1: `--all` Broadcast Without `--skip-first`

**Symptom.** User pane shows `zsh: command not found: <first-word-of-prompt>`.

**Root cause.** `ntm send --all` includes pane index 0 (or 1 depending on `pane-base-index`). Without `-s` / `--skip-first`, the prompt text hits the user's zsh shell.

**Fix.** Always pass `--skip-first`, or use `--robot-send` (excludes user pane automatically). See OC-013.

### AP-2: Dispatch Blocked By CASS Duplicate Check

**Symptom.** `ntm send` hangs at `Continue anyway? [y/N]` in an orchestrator loop. Operator never sees the prompt.

**Root cause.** `ntm send` has `--cass-check` on by default; it asks for confirmation if a similar prompt was used recently.

**Fix.**
- For orchestrator loops: always pass `--no-cass-check`.
- For structural safety: use `ntm --robot-send` (non-interactive by design).

### AP-3: Generic-Terse Nudges ("Next review.", "Keep going.")

**Symptom.** Ticks 1-3 produced real review beads; tick 4+ produces vague "looks fine" responses.

**Root cause.** Nudges shortened to lose all specificity. Agent has nothing concrete to act on.

**Fix.** OC-010: Specific verb + specific target + specific exit condition in every nudge. If you can't, stop nudging.

### AP-4: Templated Prompt With Stale Bead ID

**Symptom.** Agent spends a tick investigating "bd-3qoly" which closed 2 days ago.

**Root cause.** Reused a saved dispatch template without editing.

**Fix.** OC-017: Use palette edit-before-send, or substitute via `--var`.

### AP-5: "Reread AGENTS.md" In Every Nudge

**Symptom.** First ~30s of every tick is spent re-bootstrapping context; useful work starts late.

**Root cause.** Drag text left over from initial dispatch template.

**Fix.** Drop "Reread AGENTS.md" from steady-state nudges. Keep it only for initial dispatch and post-compaction resume.

### AP-6: Broadcast When Targeted Would Do

**Symptom.** Every pane receives the same prompt even though only 1-2 are relevant.

**Root cause.** Operator defaults to `--all` for convenience.

**Fix.** Dispatch by pane index or agent type (`--cc`, `--cod`, `--gmi`) when possible. Reserve `--all` for shutdown broadcasts or truly universal directives.

---

## Observation & Monitoring Anti-Patterns

### AP-7: Trusting Stale Rate-Limit Messages

**Symptom.** Operator treats pane as dead for 3 hours; wall actually lifted 2 hours ago.

**Root cause.** Pane buffer message ("resets 3pm") is stale the moment it renders; cc CLI doesn't re-check until user interacts.

**Fix.** OC-001: Ping-probe every 10 min. Use `--robot-health-oauth` for provider truth.

### AP-8: Bash-Grepping Pane Buffers Instead Of Robot Surfaces

**Symptom.** Operator's tick logic is `tmux capture-pane -p | grep "Working\|Idle"`. Flaky.

**Root cause.** Pane buffer is a display medium, not a state medium. Alt-screen, color codes, word wrap all break regex.

**Fix.** Use `ntm --robot-is-working`, `--robot-tail`, `--robot-agent-health`. Registry-backed, schema-stable.

### AP-9: `ntm activity` / `ntm health` With Stale Timestamps

**Symptom.** All timestamps read "56 years ago" or epoch.

**Root cause.** Legacy command path; does not refresh cached timestamp store.

**Fix.** Use `--robot-is-working`, `--robot-agent-health`, `--robot-diagnose` (live pane sampling + provider probe).

### AP-10: Missing `claimed` In Status Counts

**Symptom.** Orchestrator reports backlog = 20; actual backlog is 70.

**Root cause.** `br list --status=open,in_progress` skips the `claimed` state (beads a pane has locked but not started).

**Fix.** OC-005: Always `br list --status=open,claimed,in_progress`.

### AP-11: Single-Point State Observation

**Symptom.** Acted on `--robot-is-working` saying "idle", but pane was actually mid-compile.

**Root cause.** Only one observation; no cross-check.

**Fix.** OBSERVABILITY.md "Three-Observation Rule": need 3 independent signals (real-time + persistent + system) before state-changing action.

### AP-12: Convergence Language Accepted As Progress

**Symptom.** Every pane says "exemplary", "ready to ship", "no fixes needed"; orchestrator continues nudging for 2+ hours.

**Root cause.** Operator reading prose as work; git log says zero commits.

**Fix.** OC-016 Convergence Termination. If the three hard conditions hold, stop.

---

## Pane Lifecycle Anti-Patterns

### AP-13: Identical Tail ≥3 Ticks, Operator Keeps Nudging

**Symptom.** Tick 5 sees same 70 lines as tick 2, zero growth.

**Root cause.** Pane wedged on `/usage`, `/rate-limit-options`, paste buffer, or crashed. Nudges don't reach the CLI.

**Fix.** OC-003 Stuck-Pane Escalation Ladder. Don't skip rungs.

### AP-14: `ntm rotate` Timeout, Operator Gives Up

**Symptom.** `ntm rotate` runs for 5 min, returns timeout, operator escalates to user.

**Root cause.** Rotate uses CLI interactive prompts; wedged CLIs can't cooperate.

**Fix.** Skip `ntm rotate` when CLI is wedged; go straight to `ntm --robot-restart-pane` (uses `tmux respawn-pane -k` directly).

### AP-15: Single Ctrl-C Doesn't Exit CLI

**Symptom.** Operator sends `C-c`; CLI prints a new prompt (only canceled the current line).

**Root cause.** cc/cod/gmi CLIs require double C-c to exit.

**Fix.** OC-014: `tmux send-keys C-c; sleep 0.3; tmux send-keys C-c`.

### AP-16: Codex Buffer Corruption After Interrupt

**Symptom.** Next send into codex pane shows concatenation of old buffer + new prompt; prompt doesn't execute.

**Root cause.** Codex TUI retains partial buffer after C-c; new send prepends onto it.

**Fix.** **Always** `Escape Escape Escape C-u` before sending fresh prompts into any codex pane that had any prior interrupt. Not just "stuck" panes.

### AP-17: Saturated-Context Rehabilitation

**Symptom.** 4-day-old cc pane, circular planning, every nudge consumes more context.

**Root cause.** Operator trying to rescue a context-toast pane instead of replacing it.

**Fix.** OC-011: Replace, don't rehabilitate. Fresh pane on bead-scoped handoff > 4-day-old pane always.

### AP-18: Auto-Compact Eats Your Working Set

**Symptom.** Context hit 5%; auto-compact fired; next prompt returns vague "based on earlier context…".

**Root cause.** Compaction summarizer drops precise state details in favor of high-level narrative.

**Fix.** OC-009: Pre-empt at ≤85%. Write a bead-scoped handoff, then restart the pane.

---

## Coordination Anti-Patterns

### AP-19: Agent Mail Retry-Register Infinite Loop

**Symptom.** Pane retries `register_agent` for 4 hours; never produces code.

**Root cause.** Agent interprets mail server unavailability as a transient error to retry, not a signal to fall back.

**Fix.** OC-007: Mail-down → `br update --assignee` soft lock, proceed with work. Do NOT retry registration.

### AP-20: Too-Broad File Reservations

**Symptom.** One agent reserved `**/*.rs`; every other agent hits `FILE_RESERVATION_CONFLICT`.

**Root cause.** Agent used globstar pattern or leading-`/` in reservation.

**Fix.** OC-008: Detect and force-release; educate owner to use narrow patterns.

### AP-21: Bead Assignee Mail Ping-Pong

**Symptom.** "Please release bead br-xxx" thread; 4 hours of back-and-forth; no work landed.

**Root cause.** Operator used mail as an ownership transfer protocol; mail is for nuance, not control.

**Fix.** OC-015: Flip bead status + reassign. Don't wait for mail response.

### AP-22: Duplicate Work From Missing Domain Assignment

**Symptom.** Two agents claim overlapping beads; both edit the same files; merge hell.

**Root cause.** Spawn happened without explicit per-pane domain assignment.

**Fix.** OC-006: Assign crate/directory domains at spawn. Enable coordinator auto-assign.

### AP-23: Coordinator Digest False Negatives

**Symptom.** `ntm coordinator digest` says "no conflicts"; agents still report collisions.

**Root cause.** Known swallowed-error path in digest.go.

**Fix.** OC-019: Cross-check with `ntm coordinator conflicts` (separate code path). Trust conflicts.

### AP-24: Stale `build_slots` Leases

**Symptom.** Build operations silently blocked even with worktrees disabled.

**Root cause.** Switching between worktree/non-worktree mode leaves 1-hour leases active.

**Fix.** `ntm --robot-snapshot | jq '.build_slots.leases'` → force-release any stale lease or wait out TTL.

---

## Scale & Cadence Anti-Patterns

### AP-25: 7+ Project Orchestration By Single Operator

**Symptom.** Panes sit idle at prompt boxes for hours; orchestrator reports "tending 7 projects" but productivity is below 3-project baseline.

**Root cause.** Operator attention budget exceeded.

**Fix.** OC-020: Narrow to 3 projects × 6 panes. Use 2-tier orchestration for higher scale.

### AP-26: Sub-3-Minute Polling

**Symptom.** Ticks every 60s; orchestrator burns tokens on monitoring; real work interrupted.

**Root cause.** Default bias toward faster polling.

**Fix.** 4 min (just-dispatched), 10-17 min (steady), 30 min (deep-work) — see Steady-State Cadence.

### AP-27: Hand-Ticking For Hours

**Symptom.** Operator manually runs each tick; eventually misses ticks; drifts.

**Root cause.** No cron/schedule automation.

**Fix.** OC-022: Use `CronCreate`, `/loop`, or shell cron once orchestrating ≥30 min.

### AP-28: Over-Nudging A Converged Swarm

**Symptom.** 2+ hours of nudging after backlog was clear; every pane says "already complete"; zero commits.

**Root cause.** Orchestrator doesn't have a termination condition.

**Fix.** OC-016 Convergence Termination: three hard conditions → stop.

---

## Dev-Loop Anti-Patterns

### AP-29: rch File-Sync Assumed Universal

**Symptom.** Remote tests fail with "file not found" even though local edits compile.

**Root cause.** `rch exec` only syncs paths in `transfer.extra_sync_dirs`.

**Fix.** OC-018: Check config; add missing paths or fall back to local build.

### AP-30: Missing Handoff Notes At Shutdown

**Symptom.** Fresh pane picks up bead; spends 30 min re-discovering state; asks clarifying questions.

**Root cause.** Previous pane stopped without writing a handoff note to the bead.

**Fix.** OC-024: Handoff note is a shutdown requirement, not a nicety.

### AP-31: "Done" Without Push

**Symptom.** Agent reports "finished br-xxx"; local commit exists but `git push` never ran; work stranded.

**Root cause.** Definition of done was fuzzy.

**Fix.** OC-025: Done = commits + closed beads + push + verified working tree clean.

### AP-32: Prose Purgatory / Ship-or-Surface Violation

**Symptom.** Pane actively working; zero commits in 2+ hours; output is subsystem walkthroughs and self-reviews.

**Root cause.** Marching orders didn't constrain the output medium.

**Fix.** OC-004 Ship-or-Surface: commit within 60 min OR surface a concrete blocker. No prose.

### AP-33: Review-Bead Inflation Without Closure

**Symptom.** Open bead count grows from 50 to 300 across a multi-day swarm.

**Root cause.** Agents file new review beads every round; never close existing ones.

**Fix.** Alternate close/review prompts weighted by backlog depth (PLAYBOOK.md). Block new review-bead creation when backlog >100.

---

## Meta / Orchestrator Anti-Patterns

### AP-34: Guessing Instead Of Querying The Registry

**Symptom.** Operator invokes `--robot-foobar` which doesn't exist; silent failure or error.

**Root cause.** Memory/training-data recall instead of live capability query.

**Fix.** Always `ntm --robot-capabilities | jq` before using an unfamiliar flag. See ROBOT-MODE.md.

### AP-35: Deprecated Flag Usage

**Symptom.** Commands silently misbehave (e.g., `--assign-beads` ignored).

**Root cause.** Old docs or training data using pre-rename flags.

**Fix.** See ROBOT-MODE.md deprecated → canonical table. Verify via `--robot-help=<surface>`.

### AP-36: Cursor Held Across Long Waits

**Symptom.** `ntm --robot-events --cursor=<old>` returns `CURSOR_EXPIRED` after sleeping for >1h.

**Root cause.** Cursor is GC'd after ~1 hour.

**Fix.** Resync with `--robot-snapshot` whenever cursor age > 45 min (proactive) or on first `CURSOR_EXPIRED` (reactive).

### AP-37: Acting On Stale Source Data

**Symptom.** Reassigned a bead that was already closed 10 min ago; wasted the tick.

**Root cause.** Used snapshot's bead list without checking `source_health.beads.status`.

**Fix.** OC-012: Source-health check before every state-changing action.

### AP-38: Not Using Native Stuck-Detect

**Symptom.** Operator manually tracks per-pane tail-hash; misses cases.

**Root cause.** Reinventing `--robot-health-restart-stuck`.

**Fix.** `ntm --robot-health-restart-stuck=<session> --stuck-threshold=10m --dry-run` in every tick.

---

## Convergence Language Dictionary (for AP-12)

When multiple panes produce these phrases across 2+ consecutive ticks AND git log is empty, the swarm has converged. Stop.

- "exemplary"
- "already complete"
- "no fixes needed"
- "ready to ship"
- "no changes required"
- "the implementation is solid"
- "code is clean"
- "nothing to add"
- "looks good to me"
- "LGTM"
- "tests are passing"
- "all conditions met"

None of these are a substitute for a commit SHA. If the pane can't name a SHA from this tick, it did no new work.

---

## How To Extend This File

New anti-pattern format:

1. **Name** — short, searchable, unique (AP-NN)
2. **Symptom** — observable evidence (what you'd see in a log or snapshot)
3. **Root cause** — why it happens
4. **Fix** — pointer to operator card (OC-NN) or concrete recipe

If you observe a new pattern three times across different swarms, promote it from anecdote to entry here. If you observe it five+ times, also create an operator card (OC-NN) with a prompt module and a validator.
