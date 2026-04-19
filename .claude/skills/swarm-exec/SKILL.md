# Swarm Exec

Alias for the execution swarm — delegates to `/swarm`.

## When to activate

Same triggers as `/swarm`:
- "swarm" / "start swarm" / "launch swarm" / "run swarm"
- "assign bead X" / "run bead X"
- "start agents" / "spawn agents"

## Instructions

Read `~/.claude/skills/swarm/skill.md` and follow it verbatim. `$ARGUMENTS` passes
through unchanged. If the user asks for `status`, delegate to `/swarm-exec-status`
(which is itself an alias for `/swarm-status`).

This skill exists only for naming continuity with earlier workflows; the canonical
skill is `/swarm`. Do not duplicate its contents here — drift between the two is
the reason this became an alias.
