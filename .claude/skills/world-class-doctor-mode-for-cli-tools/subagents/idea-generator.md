# subagent: idea-generator (Phase 10)

**Description.** Surface second-order ergonomic improvements via `/idea-wizard`. File as beads with priority 3 (backlog).

## Inputs

- `{{workspace}}/HANDOFF.md`
- `{{workspace}}/agent_simulations/post_pass_<N>/notes.md`
- `<tool> doctor capabilities --json`
- `/idea-wizard` skill

## Outputs

- `{{workspace}}/ideas_pass_<N>.md` — generated ideas with rationale
- Beads filed at priority 3 for ideas worth pursuing

## Prompt

```
You are the idea-generator. Use the /idea-wizard skill to surface second-order
improvements to `<tool> doctor` based on this pass's findings.

INPUTS.
- HANDOFF.md (this pass's outcome)
- agent_simulations/post_pass_<N>/notes.md (cold-prober's wished-this-existed list)
- capabilities --json (the contract surface)

PROCEDURE.

1. Invoke /idea-wizard with the focus prompt:

   "Generate 10-15 ideas for improving the doctor surface of {{tool}}. Focus
   on: agent-ergonomic uplift, fixture coverage gaps, additional fixers for
   FMs that are currently detect-only, observability improvements, and
   scorecard regressions surfaced this pass. Each idea: title, one-paragraph
   rationale, expected uplift dimension, complexity (S/M/L), open questions."

2. Filter the ideas:
   - Discard ideas that duplicate already-open beads.
   - Discard ideas that violate AGENTS.md (file deletion, destructive shell).
   - Keep the top 10 by (rationale_strength × inverse_complexity).

3. For each kept idea, file a bead:
   br create --type=task --priority=3 --title="doctor: idea: <short>" \
       --body="<rationale + expected uplift + open questions>"

4. Save the full idea list to {{workspace}}/ideas_pass_<N>.md, including
   discarded ideas with the discard reason.

EXIT CRITERIA.
- ideas_pass_<N>.md exists with 10+ ideas
- 3-10 ideas filed as priority-3 beads
- No idea violates AGENTS.md
```

## Exit criteria

- ideas list committed
- beads filed

## Failure modes

- `/idea-wizard` not installed. Fall back to the cold-prober's `wished-this-existed` list as raw idea inputs.
- All ideas duplicate open beads. Note this in `ideas_pass_<N>.md` and skip filing new beads.
