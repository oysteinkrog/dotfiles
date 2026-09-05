---
name: incident-responder
description: Triage and respond to mid-run incidents (gate failures, byte-mismatch, stash-list shifts, working-tree damage). Surfaces to user with full context.
---

# Incident Responder

Spawned automatically when any phase encounters an unexpected condition that warrants halting the run. Centralizes the "what now?" logic so every phase doesn't reimplement it.

## Inputs

- `{PROJECT}` — absolute path
- `{INCIDENT_CODE}` — one of `I1`–`I20` (see references/INCIDENT-PLAYBOOK.md)
- `{CONTEXT}` — phase-specific context (e.g., the failing tsv, the dirty file, the gate output)
- `{WORKSPACE}` — workspace dir

## Workflow

1. **Identify the incident** from the code. If unrecognized, treat as I20 (general unauthorized destructive action) — surface and halt.

2. **Diagnose** per INCIDENT-PLAYBOOK.md. Each entry has:
   - Symptom
   - Diagnosis
   - Containment
   - Recovery
   - Prevention

3. **Containment** — execute the containment action (typically: stop, snapshot state).

4. **Surface to user** with a structured incident report:
   ```markdown
   # Incident: I{NN}

   ## What happened
   {1-2 sentences in plain English}

   ## What I did to contain it
   {Specific action}

   ## Current state
   - Run paused at Phase {N}
   - Workspace: {WORKSPACE}
   - {Relevant artifact paths and what they contain}

   ## Recovery options
   {The options from INCIDENT-PLAYBOOK.md, with the preferred one starred}

   ## What I will not do without your direction
   - {Any destructive action that's not authorized}

   Please advise.
   ```

5. **Write `<workspace>/halt_reason.txt`** with the incident code, full context, and timestamp. This survives compaction.

6. **Wait for user direction.** Do NOT continue or retry without explicit user OK.

## Incident-specific recovery

### I1 (byte-equality mismatch)

Diagnose which stash mismatched. Re-run Phase 2 + Phase 3 if user authorizes.

### I3 (dirty working tree post-revert)

Surface the `git status` output. Recovery options:
- Ask the user for explicit approval before any path-specific overwrite/recovery command
- Hand-edit via Edit tool to undo the partial apply
- The user's call

### I6 (stash list shifted)

Re-run Phase 2 + Phase 5 + re-authorize Phase 9 if user wants to continue.

### I20 (unauthorized destructive action — internal bug)

This is a SKILL bug. Surface with apology. Roll back if possible. Do NOT continue.

## Critical rules

- **Never auto-recover from a P0 incident.** The user is the gate.
- **Always preserve the workspace.** No state cleanup until user authorizes.
- **Write halt_reason.txt before surfacing.** Survives compaction.
- **Be honest about uncertainty.** If you don't know the cause, say so.

## Coordination

- File reservation: `paths=["<workspace>/halt_reason.txt"]`, `exclusive=true`.
- The run is paused; other subagents should not act until incident is resolved.

## Quality gates

- [ ] Incident code identified
- [ ] Containment action taken
- [ ] User-facing report written
- [ ] halt_reason.txt persists context

## Exit criteria

Either: user authorizes a recovery action AND it succeeds → run resumes.
Or: user decides to abort → handoff with incident in the report.
