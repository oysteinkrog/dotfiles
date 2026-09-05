# Agent Fungibility

Per `/agent-fungibility-philosophy`: every agent is a generalist; any agent can pick up any bead/phase given the workspace state. The skill is designed so no "specialist" knowledge lives only in one agent's context — everything is durable.

## The core claim

A fresh agent, cold-started against `<workspace>/` and `SKILL.md`, can:

- Continue any phase mid-flight by reading `MEMORY.md` + the relevant `phase<N>_*.md` + the relevant `round_<N>/` directory.
- Take over a bead in-flight by reading the bead body, the referenced patterns, the relevant ledger entries, and the upstream beads it depends on.
- Audit a kept perf change by reading the proof pack alone — no chat history required.

If any of these break, the skill has a compaction-survival bug. See [`methodology/COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md).

## What "fungible" does NOT mean

Fungibility is about CONTINUITY, not about INTERCHANGEABILITY. Different agents are still better at different things:

- Codex tends to find idiom drift (use it in `triangulator` for the `idiom-drift` lens).
- Gemini tends to find logic gaps and unmodeled state transitions.
- Grok tends to find pragmatic issues and "what would actually happen in production".
- Opus (Claude) tends to find architectural soundness and design-level concerns.

These are tendencies, not laws. The `triangulator` subagent dispatches the same lens-specific prompt to multiple models because the disagreement is signal.

## The lane convention (cc_1 / cc_2 / cc_3 / cc_4)

Soft assignment by pillar to minimize MCP Agent Mail reservation collisions:

- **cc_1** — conformance / oracle / differential / metamorphic / fault / crash-boundary
- **cc_2** — performance / benches / profile-cards / hot-path counters / regression-detector
- **cc_3** — surface / coverage / feature-universe / invariant-catalog
- **cc_4** — fault / crash / soak / e-process / BOCPD / adversarial

Lane-crossing is OK but not the default. When agent X (cc_1 lane) needs to touch a perf file (cc_2 territory), it should:

1. Reserve the file via MCP Agent Mail.
2. Open a thread `gauntlet-<run-id>-handoff-<file>` mentioning cc_2 owner.
3. Make the change, document the cross-lane rationale in the session file.

## The "communication purgatory" anti-pattern

Agents waiting on each other for responses that never arrive. Symptoms:
- One agent's `send_message(ack_required=true)` and waits.
- The recipient's inbox is full of similar pending messages.
- Both agents are blocked.

Fix:
- Use TTL on `file_reservation_paths`; reservations auto-expire.
- Default to `ack_required=false`; the message is durable in the thread, the recipient picks it up when it picks it up.
- For blocking handoffs, use beads (the recipient's `br ready` will surface the next item; no synchronous wait needed).

## The "tidying up other agents' edits" anti-pattern

Per AGENTS.md verbatim:

> Treat those changes identically to changes that you yourself made. Just fool yourself into thinking YOU made the changes and simply don't recall it for some reason.

When you see modifications in files you didn't touch:
- DO NOT stash / revert / overwrite.
- DO commit them along with your own changes.
- DO NOT ask the user "what should I do about these unrelated changes". The answer is always "treat them as your own and continue".

This is the single most common failure mode for new agents (especially Codex/GPT-5.5 style).

## The "swarm init prompt" verbatim

Per `/multi-agent-swarm-workflow` + `/agent-fungibility-philosophy`:

When the orchestrator spawns N agents on the same workspace, the kickoff prompt EACH agent receives is:

```
You are agent <agent-id> in a swarm working on <workspace>. Your job is to
pick the next ready bead (via `br ready --json`), claim it (via `br update
<id> --status=in_progress --owner=<agent-id>`), and execute it per the
pattern + reference cross-links in its description.

Coordination rules:
- Before editing any file, reserve it via MCP Agent Mail file_reservation_paths
  with exclusive=true, ttl_seconds=3600.
- Communicate via the thread `gauntlet-<run-id>-<phase>-<bucket>` (see the
  bead's coordination_thread field).
- When you see changes in files you didn't make, treat them as your own and
  continue (per AGENTS.md).
- When done, `br close <id>` + release_file_reservations.
- Lane: <cc_N> (soft assignment; cross-lane OK with handoff thread).

The skill is /running-the-gauntlet-on-your-rust-port. Read SKILL.md first if
you haven't already.
```

The orchestrator fills `<agent-id>`, `<workspace>`, `<run-id>`, `<cc_N>`. Every agent gets the same prompt + the same workspace; the bead graph is the work queue.

## Cross-references

- AGENTS.md "Note for Codex/GPT-5.5" section (verbatim quote on tidying up other agents' edits)
- `/agent-fungibility-philosophy` — the principle
- `/multi-agent-swarm-workflow` — the swarm orchestration
- [`methodology/COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md) — what makes fungibility possible
- [`orchestration/ORCHESTRATION.md`](ORCHESTRATION.md) — the lane convention + reservation conventions
