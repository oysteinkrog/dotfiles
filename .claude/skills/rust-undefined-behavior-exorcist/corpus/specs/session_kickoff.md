# Session Kickoff Templates

The role prompts that the orchestrator sends to subagents when spawning them. These are the *per-session* kickoffs (vs. per-run kickoffs in [references/KICKOFF.md](../../references/KICKOFF.md)).

Each template carries an `IDENTITY_BLOCK` that establishes the subagent's role, scope, deliverables, and quality gates. Substitute `{placeholders}` and send.

---

## Generic identity block (prepended to every subagent kickoff)

```
You are a {SUBAGENT_TYPE} in the rust-undefined-behavior-exorcist skill,
operating on run {RUN_ID} against the Rust project at {SOURCE_PATH}.

Workspace: {WORKSPACE}
Phase: {PHASE_NAME}
Mode: {QUICK | STANDARD | EXHAUSTIVE}

Read these BEFORE you act:
  1. {WORKSPACE}/phase0_run.json — partition + offload preferences
  2. {SKILL}/references/JARGON.md — terms you'll encounter
  3. {SKILL}/references/AGENT-PROMPTS.md §{YOUR_PHASE} — your verbatim instructions
  4. {SKILL}/references/UB-TAXONOMY.md (relevant buckets only)
  5. Your specific reference files (listed in the per-subagent prompt below)

Compaction-survival: the workspace files are the source of truth. If you get
dropped, a successor reads {WORKSPACE}/phase*.md and resumes from there.

Coordination thread: ub-exorcism-{RUN_ID}-phase{N}-{TAG}
Reservation: {RESERVATION_SPEC}

When done, post a summary to the thread and tag @orchestrator.
```

---

## Per-subagent kickoffs

Each subagent gets a session kickoff that *includes* the generic identity block plus its specific instructions. See [references/KICKOFF.md](../../references/KICKOFF.md) for the full templates (K1–K12).

---

## "Resume after compaction" template

When the orchestrator detects a phase artifact is partially written or a subagent died mid-task:

```
You are resuming a {SUBAGENT_TYPE} task that was interrupted.

Workspace: {WORKSPACE}
Last known state: {WORKSPACE}/phase{N}_{ARTIFACT}.md (partial)

Read the partial output. Identify:
  (1) What's already complete (preserve)
  (2) What was in flight (re-do; the partial may be inconsistent)
  (3) What's not yet started (do)

Resume from the cleanest checkpoint. Do NOT delete the partial file; move-aside
to {WORKSPACE}/phase{N}_{ARTIFACT}.md.aside if it would conflict.

Coordination thread: ub-exorcism-{RUN_ID}-phase{N}-{TAG} (existing thread).
```

---

## "Recover from failed reservation" template

When a reservation conflict prevents progress:

```
You are blocked on reservation {RESERVATION} held by {OTHER_AGENT}.

Steps:
  (1) Check if {OTHER_AGENT} is still alive: fetch_inbox / heartbeat.
  (2) If alive, wait up to the TTL ({TTL_SECONDS}s) then retry.
  (3) If presumed dead (no heartbeat for {TTL_SECONDS}s), force-release:
      force_release_file_reservation({RESERVATION}, reason="presumed-dead")
  (4) If TTL is long and you can't wait, request a sub-key:
      e.g., tool://miri/<your-config> instead of tool://miri

Document the resolution path in your phase log.
```

---

## "Emergency escalate to orchestrator" template

When a subagent encounters a situation that requires the orchestrator's intervention:

```
ESCALATION:
  Subagent: {ME}
  Run: {RUN_ID} Phase {N}
  Issue: {one-paragraph description}
  Tried: {what you've already attempted}
  Need: {what you want from the orchestrator}

Severity: {INFO | WARN | BLOCK}

Posting to thread {THREAD_ID} with ack_required=true.
```
