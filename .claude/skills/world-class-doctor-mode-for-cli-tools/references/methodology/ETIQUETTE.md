# Multi-Agent Etiquette

Per AGENTS.md § Note for Codex/GPT-5.5 (Q-009), multiple agents work on the user's projects simultaneously, often "multiple times PER MINUTE." The doctor is a uniquely-privileged surface — it MUTATES state. This file pins the rules for how a doctor invocation behaves when it shares a project with other agents.

This file complements [AGENT-MAIL-INTEGRATION.md](AGENT-MAIL-INTEGRATION.md) (which covers Phase 4 implementer coordination during a doctor *build*) by addressing **runtime** etiquette: what an agent invoking `<tool> doctor` should do when other agents are active.

---

## The eight rules

### 1. Never run `<tool> doctor --fix` without explicit human or planner consent

A doctor `--fix` mutates project state, often touching many files. Other agents may be mid-edit. Even if the doctor's lock primitive serializes against itself, it doesn't serialize against ad-hoc agent edits.

**Pattern:** before `--fix`, the agent should:
1. Run `<tool> doctor --json` (read-only diagnose) and surface findings to the user/planner.
2. Wait for explicit "yes, fix that" instruction.
3. Then run `<tool> doctor --fix --only <specific-fm-id>`.

The skill's `dispatch-prompts.md` includes this two-step pattern as the default.

Exception: if the doctor is invoked AS PART of a documented automation (CI gate, pre-commit hook, scheduled cron), the consent is implicit in the automation's existence. The user already approved the cadence by enabling the hook.

### 2. Acquire Agent Mail file reservations BEFORE diagnose mode reads files an editor might be writing

Per AGENTS.md, multiple agents edit files concurrently. If a doctor reads `.beads/issues.jsonl` while another agent is writing it, the read is racy.

**Pattern:** in a multi-agent context, even read-only diagnose should:
```
mcp__mcp-agent-mail__file_reservation_paths(
    project_key=<repo>,
    agent_name=<my-name>,
    paths=[".beads/issues.jsonl", ".beads/beads.db"],
    ttl_seconds=120,
    exclusive=false,    # NON-exclusive: just declares "I'm reading"
    reason="doctor-diagnose"
)
```

`exclusive=false` means other readers can coexist, but writers will see the reservation and back off (or wait). This is the cooperative-courtesy pattern.

For `--fix`, ALWAYS `exclusive=true`:
```
mcp__mcp-agent-mail__file_reservation_paths(
    project_key=<repo>,
    agent_name=<my-name>,
    paths=[".beads/**", ".doctor/**"],
    ttl_seconds=600,
    exclusive=true,
    reason="doctor-fix"
)
```

### 3. Never doctor a workspace another agent has reserved with `exclusive=true`

If `mcp__mcp-agent-mail__file_reservation_paths(...)` returns `FILE_RESERVATION_CONFLICT`:

1. Read the conflicting reservation's holder.
2. Send a thread message to them naming the conflict and asking for ETA.
3. Wait for ack OR timeout (5 minutes).
4. If still conflicted: **refuse to proceed.** Report the conflict to the user/planner.

**Never force-release another agent's reservation** unless the user explicitly authorizes (and the user is the only entity allowed to issue `force_release_file_reservation`).

### 4. The "I see uncommitted changes I didn't make" rule

Per AGENTS.md (Q-009), uncommitted changes are normal: another agent made them.

**Patterns the doctor must follow:**
- Never `git stash` to "clean up" before running. The stash contains another agent's work.
- Never `git reset --hard` for the same reason.
- If the doctor's diagnose finds project files in unexpected states, the doctor reports them as findings — never auto-corrects assuming malice.

The doctor's `--fix` is scoped to known data paths in `capabilities::write_scopes`. It doesn't touch source code. Other agents' source-code edits are out-of-scope for the doctor.

### 5. Per-doctor-invocation isolation

Each `<tool> doctor` invocation creates its own `.doctor/runs/<run-id>/` directory. Concurrent invocations don't share state — they're independent runs with distinct run-ids.

But: they CONTEND on the project's lock. Per Axiom 6, one wins, others refuse with exit 5.

**Agent A:** runs `<tool> doctor --fix`, holds lock for 30s.
**Agent B:** invoked `<tool> doctor --fix` 5s after A. Refuses with exit 5 + finding `lock_held_by: <A's run-id>`.
**Agent B's response:** wait + retry, OR report the conflict to the user.

### 6. Streaming health on long-running daemons

For Pattern 4 (daemon CLIs), agents can subscribe to `<tool> doctor health --watch` for NDJSON updates. Multiple subscribers are OK; the daemon serves them via the same protocol-read endpoint.

But: agents should not invoke `<tool> doctor --fix` while a watching agent is reading. The watcher's reads are read-only (the daemon emits state via the protocol, not via filesystem reads), so they're safe to coexist with diagnose-mode but NOT with fix-mode.

The doctor's lock primitive (per Axiom 6) ensures `--fix` can't proceed if any other agent is mid-fix; it does NOT block read-mode watchers. That's intentional.

### 7. Respect the human's terminal session

If a human is actively typing in the terminal (`stdout.isatty()` is true on the doctor's process), the doctor MAY emit color and progress. If invoked from a non-TTY (CI, agent), suppress.

The "respect the human's terminal" rule extends to: don't print enormous JSON to a human terminal. If `--json` is passed AND stdout is a TTY, that's a deliberate user choice. But the agent invoker should pipe to `jq` or redirect to a file.

The doctor doesn't enforce this; it's an agent best-practice.

### 8. Document your runs in the project's mail

After every `<tool> doctor --fix` invocation, post a short summary to the project's mail:

```
mcp__mcp-agent-mail__send_message(
    project_key=<repo>,
    sender_name=<my-name>,
    to=[<relevant-agent-names>],
    subject="[doctor] pass <run-id>: <N> findings, <K> fixed",
    body_md="Run id: <id>. Findings: ... Actions taken: ... See .doctor/runs/<id>/ for full report.",
    thread_id="doctor-runs-<repo>"
)
```

The sender addresses the agents whose reservations, files, or workstreams were affected; Agent Mail does not support blind broadcast. Other agents reading their inbox see what the doctor did. If something later breaks, the audit trail is in the mail.

For diagnose-only runs, mail is optional (it's a lot of noise). For `--fix` runs, mail is mandatory at the etiquette level.

---

## Conflict scenarios

### Scenario A — Two agents both want to `--fix`

Agent A and Agent B both notice findings and decide to fix. They both invoke `<tool> doctor --fix` within 100 ms of each other.

**Outcome:** One acquires the lock; the other refuses with exit 5. The loser:
1. Reads the winner's run-id from the exit-5 finding.
2. Waits for the winner to finish (poll `<tool> doctor ls` for the run-id's terminal state).
3. Re-runs diagnose (the winner may have fixed everything; loser has nothing to do).
4. If findings remain, runs `--fix` for the residual.

The doctor's lock is the protection. Both agents end up with consistent state.

### Scenario B — Doctor wants to run; another agent is mid-edit on a non-doctor file

Agent A is editing `src/feature.rs`. Agent B wants to run `<tool> doctor --fix` to address an unrelated `.beads/issues.jsonl` finding.

**Outcome:** Agent A's edit on `src/feature.rs` is OUTSIDE the doctor's `write_scopes`. The doctor doesn't touch it. The two agents proceed in parallel without conflict.

### Scenario C — Doctor wants to run; another agent is mid-edit on a file IN doctor's write_scopes

Agent A has `.beads/issues.jsonl` open and is mid-edit (e.g., adding a new bead). Agent B wants to run `<tool> doctor --fix` which would also rewrite `.beads/issues.jsonl`.

**Outcome:**
- If A acquired an exclusive Agent Mail reservation on `.beads/**`: Agent B's reservation request returns `FILE_RESERVATION_CONFLICT`. Agent B refuses to proceed.
- If A has NOT reserved: Agent B acquires the doctor's lock and runs. Agent A's in-progress edit is still in their working memory (not yet on disk). When A flushes, A's writes overlap doctor's. **One of the two LOSES.** This is the bad case.

The protection: **agents that edit files in doctor's write_scopes MUST acquire Agent Mail reservations.** This is a project-wide etiquette rule, not a doctor-specific rule. The Pre-commit guard (Phase 8 + AGENTS.md) enforces this — committing without a fresh reservation triggers a warning.

### Scenario D — Agent invokes doctor from the wrong CWD

Agent A's CWD drifted to `~/projects/wrong-project/`. Agent A invokes `<tool> doctor --fix` thinking it's targeting their intended project.

**Outcome:** The doctor targets cwd by default. It rewrites the WRONG project's state.

**Recovery:** Agent A notices, runs `<tool> doctor undo latest`. State restored.

**Prevention:** The doctor should print the target path early in stderr:
```
[<tool> doctor] target: /home/user/projects/wrong-project
[<tool> doctor] continuing in 0s (set NOCONFIRM=1 to skip)
```

This is a friction tradeoff. For CI/automation it should be silent (NOCONFIRM=1 in CI); for interactive use it's a useful confirmation.

---

## When etiquette fails

The doctor's safety machinery is designed assuming etiquette WILL fail occasionally. The byte-for-byte undo (Axiom 3), the verbatim backups (Axiom 2), the per-run isolation (Axiom 13) are protections against bad etiquette. They turn etiquette violations from "permanent damage" to "5-minute revert."

But etiquette is still the first line of defense. A project where agents respect the rules above sees doctor invocations almost never trigger the recovery machinery.

---

## How to test etiquette

In Phase 5's safety harness, the concurrency test (`verify-concurrency.sh`) tests the doctor's lock. Beyond that:

- **Adversarial test E.2** ([ADVERSARIAL-REVIEW.md § C.2](ADVERSARIAL-REVIEW.md)): plant a stale lock from a non-doctor process; verify doctor refuses.
- **Adversarial test E.3** (Scenario D above): invoke doctor from a wrong CWD; verify the printed target matches user expectation.

For team-level testing, schedule an "etiquette drill" once a quarter where agents deliberately conflict and the team observes whether the doctor + Agent Mail + per-run isolation all hold.
