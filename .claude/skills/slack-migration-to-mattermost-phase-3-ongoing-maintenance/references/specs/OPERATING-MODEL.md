# Operating Model

How the operator + agent + skill interact during ongoing ops.

## The three actors

- **Operator**: a human who reads reports, approves destructive actions,
  and makes go/no-go calls on upgrades / DR.
- **Agent**: Claude Code or Codex session running against the skill. Runs
  scripts, reads reports, writes summaries, asks for approval before
  anything destructive.
- **Skill**: the directory containing `maintain.sh`, scripts, prompts,
  references, subagents. Deterministic; no state other than
  `workdir-phase3/`.

## The weekly rhythm

```
Saturday 02:00 UTC — automated weekly-sweep (cron on operator workstation)
                     │
                     ▼
Sunday             — operator's backup dump lands on off-site
                     │
                     ▼
Monday 09:00 local — operator spends 2 min reading latest summary
                     │                      │
                     │                      │ all green
                     │                      └──────▶ done for the week
                     │
                     │ anything red/yellow
                     ▼
                    Operator pastes prompts/orient.md, agent investigates.
                    Operator decides: fix now, schedule fix, or escalate.
```

## The "ongoing" interaction loop

Each stage is:

1. **Operator** pastes a prompt from `prompts/<stage>.md`.
2. **Agent** reads the prompt, loads relevant references, plans the run.
3. **Agent** invokes `./maintain.sh <stage>` (possibly with pre-checks).
4. **Skill** runs the stage, writes `<stage>-<ts>.json` + `latest-<stage>.json`.
5. **Agent** reads the JSON, summarizes in 2-3 sentences to the operator.
6. **Operator** reads the summary, approves any follow-up or moves on.

The round-trip for an uneventful weekly-sweep is under 5 minutes of
operator attention.

## Approval prompts

The agent pauses for operator approval before:

- any `ssh` command that writes on the target (install, restart, delete)
- `./maintain.sh update-mattermost` actually starting the apt install
- `./maintain.sh rotate-credentials` actually revoking old credentials
- `./maintain.sh schedule-reboot` actually queueing a reboot
- anything in `prompts/disaster-recovery.md` past phase D1

Read-only probes (`health`, `db-health`, `backup`'s pg_dump) don't
require per-command approval once the session is approved for SSH to
your target.

## What the agent decides on its own

- Which diagnostic reference to read when a check is red.
- How to format the summary.
- Whether to ask a clarifying question.
- When to suggest escalation (but not when to execute it).

## What the agent never decides on its own

- Whether to run a destructive stage.
- Whether to skip a gate.
- Whether a backup is "good enough" to rely on.
- Whether to restart a service.
- Whether to rotate credentials.
- Whether to declare disaster recovery.
- What to post to users.

For all of the above, the agent proposes and the operator approves.

## Context between sessions

Phase 3 is stateless across agent sessions; everything the agent needs
to know is in:

- `config.env`
- `workdir-phase3/reports/` (especially `latest-*.json`)
- The references in this folder

A new operator or a new agent session can paste `prompts/orient.md` to
get up to speed in one round-trip.

## Multi-operator scenarios

Two operators sharing a Mattermost:

- Same `config.env`, same `workdir-phase3/`. Sync via a private repo or a
  shared drive.
- Each operator has their own PAT (rotate if an operator leaves).
- Each operator has their own SSH key (`authorized_keys` has both).
- `ROLLBACK_OWNER` designates which operator is primary for destructive
  approval.

## Relation to Phase 1 + Phase 2

Phase 3 is independent of Phase 1 + Phase 2 after the first week. It
reads from Phase 2's config for initial setup (see
[../CROSS-PHASE-INTAKE-CONTRACT.md](../CROSS-PHASE-INTAKE-CONTRACT.md))
and can invoke Phase 2's `render-config` during DR, but day-to-day
operation is self-contained.

If your organization later decides to re-run a migration (add a new
workspace, import delta content, etc.), Phase 2's skill remains installed
and usable.
