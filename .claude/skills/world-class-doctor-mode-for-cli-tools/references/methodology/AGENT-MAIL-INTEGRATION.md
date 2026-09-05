# Agent Mail Integration — Concrete Patterns

Per AGENTS.md § MCP Agent Mail (Q-009 + skill `agent-mail`), file reservations and threaded messaging coordinate parallel agents working on the same project. This skill uses Agent Mail as the coordination spine for Phase 4 implementer fan-out.

---

## When to use

- **Always** when ≥ 2 implementer agents are dispatched in Phase 4 (Pair, Squad, or Swarm tier).
- **Always** when a Phase 7 fresh-eyes pass overlaps with an in-progress Phase 4 implementer.
- **Always** when the Phase 8 integration-wirer touches files an implementer also touches.

When **not** to use: solo-tier passes (single agent throughout). Agent Mail's overhead doesn't pay off for a single worker.

---

## Files that must be reserved

The following files are written by multiple agents during a typical pass — reservations REQUIRED:

| File / glob | Owners | Thread id |
|-------------|--------|-----------|
| `crates/doctor-core/src/mutate.rs` (or language equivalent) | Lead implementer + any subsystem implementer adding new ops | `doctor-<pass>-impl-shared-mutate` |
| `crates/doctor-core/src/capabilities.rs` | Every subsystem implementer (each registers detectors/fixers) | `doctor-<pass>-impl-capabilities` |
| `src/<binary>/doctor/mod.rs` (the CLI surface) | Lead implementer | `doctor-<pass>-impl-surface-<binary>` |
| `src/<binary>/doctor/help.rs` (the `--help` text) | Lead implementer | `doctor-<pass>-impl-help-<binary>` |
| `tests/doctor_fixtures/run_all.sh` | Fixture-author + every fixture-author per subsystem | `doctor-<pass>-fixtures-runner` |
| `.doctor_workspace/manifest.json` | Every script that calls `manifest-update.sh` | `doctor-<pass>-manifest` |
| `.doctor_workspace/scorecard.md` | Phase 6 scorecard generator (single agent; reservation just for crash-resilience) | `doctor-<pass>-scorecard` |
| The target's `.gitignore` | Anyone who touches `.doctor/` for the first time | `doctor-<pass>-gitignore` |

---

## The reservation idiom

Each implementer subagent's prompt includes:

```
Before editing any file in your assigned subsystem:

1. Compute the file glob you need (typically src/<binary>/doctor/<subsystem>/**).
2. Acquire reservation:

   file_reservation_paths(
       project_key=<abs-target>,
       agent_name=<your-name>,
       paths=[<your-glob>],
       ttl_seconds=3600,
       exclusive=true,
       reason="doctor-<pass>-impl-<subsystem>"
   )

3. If the call returns FILE_RESERVATION_CONFLICT, do NOT proceed. Instead:
   - Read the conflicting reservation's owner.
   - Send them a thread message: send_message(thread_id="<your-thread-id>",
     to=<owner>, subject="[<thread>] coordinating on <glob>", ack_required=true).
   - Wait for ack OR timeout (5 minutes); on timeout, escalate to Phase 4 lead.

4. After your edits, release: release_file_reservations(...).

5. If the edit is to a SHARED file (mutate.rs, capabilities.rs, help.rs),
   ALSO acquire the shared thread's reservation BEFORE acquiring your subsystem's.
```

The two-phase locking (shared → subsystem) prevents deadlocks; the lead implementer's reservations on shared files are short-lived (one edit at a time), so subsystem implementers don't starve.

---

## Threading

Per AGENTS.md, threads carry semantic context. The doctor skill's threads:

| Thread id | Purpose | Lifetime |
|-----------|---------|----------|
| `doctor-<pass>` | Top-level coordination; pass announcements | Whole pass |
| `doctor-<pass>-phase1` | Archaeology subagent coordination | Phase 1 |
| `doctor-<pass>-phase3-synthesis` | Synthesizer ↔ archaeologists Q&A | Phase 3 |
| `doctor-<pass>-impl-<subsystem>` | Per-subsystem implementer thread | Phase 4 |
| `doctor-<pass>-impl-shared-mutate` | mutate() coordination | Phase 4 |
| `doctor-<pass>-fresh-eyes-round-<N>` | Fresh-eyes review per round | Phase 7 |
| `doctor-<pass>-handoff` | Phase 10 handoff notes | Phase 10 |

Every commit / PR comment / bead update references the relevant thread via `thread_id` so an oncall can reconstruct the conversation.

---

## Pre-commit guard

Per AGENTS.md § MCP Agent Mail, `install_precommit_guard` is idempotent. The skill's Phase 8 integration-wirer:

1. Calls `install_precommit_guard(project_key=<target>)` at the start.
2. After the doctor's own pre-commit hook is in place, calls `mcp__mcp-agent-mail__install_precommit_guard` again — both are idempotent and play well together.
3. The guard prevents pushing if there are unreleased file reservations (so a leaving agent can't strand a lock).

If the guard fails to install, Phase 8 emits a warning to stderr and proceeds without it. Not a blocker.

---

## Force-release as last resort

If an implementer dies mid-pass without releasing its reservations, the next pass's archaeologist (or a meta-agent) calls:

```
mcp__mcp-agent-mail__force_release_file_reservation(
    project_key=<target>,
    agent_name=<my-agent-name>,
    file_reservation_id=<orphan-reservation-id>,
    note="prior-pass-died-without-release; orphan reservation",
    notify_previous=true
)
```

Per Q-009, never force-release without first writing a thread message naming the orphan and the reason. The audit trail is the protection.

---

## Failure modes

| Symptom | Cause | Recovery |
|---------|-------|----------|
| Implementer hangs on `file_reservation_paths` | TTL elapsed; lock not released | Force-release with audit message; retry |
| Two implementers acquire the same path (race) | Reservations not used; or conflicting non-exclusive=true | Reservation IS the protection — if it failed, agent-mail itself is broken; file as P0 against agent-mail |
| Stale reservations after pass-N completes | Phase 10 handoff didn't release | Phase 10 must explicitly `release_file_reservations` for every reservation it created. Add to the handoff-writer's checklist |
| Multiple agents acking the same thread message | Agent identity drift | Use `register_agent` cleanly per Phase 0; thread messages are tied to specific agent names |

---

## When agent-mail isn't available

Per [SKILL-FALLBACKS.md](SKILL-FALLBACKS.md), the inline fallback is **serial Phase 4** — only one implementer at a time, no concurrency. Loses parallelism but preserves correctness. The thread metadata moves to `<workspace>/coordination/threads/<thread-id>.md` (a Markdown log per thread).

The fallback is correct but slow. For a typical Squad-tier pass, serial Phase 4 takes 4× as long as the parallel version. Worth installing agent-mail.
