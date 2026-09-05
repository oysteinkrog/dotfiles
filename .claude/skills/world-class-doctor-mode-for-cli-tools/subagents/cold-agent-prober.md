# subagent: cold-agent-prober (Phase 10; FRESH-CONTEXT agent)

**Description.** A fresh-context agent invokes the new doctor cold (no prior knowledge of this skill or the workspace) and reports what was confusing, ambiguous, or missing.

## Inputs

- `{{tool}}` binary in PATH
- `{{workspace}}/canonical_tasks.md` — the task list
- `<tool> doctor robot-docs` output

**THE PROBER MUST NOT READ:** SKILL.md, the workspace, the source, or any prior agent's transcripts.

## Outputs

- `{{workspace}}/agent_simulations/post_pass_<N>/<task>.transcript.jsonl` per canonical task
- `{{workspace}}/agent_simulations/post_pass_<N>/notes.md` summary

## Prompt

Full prompt in [../references/methodology/AGENT-PROMPTS.md § cold-agent-prober](../references/methodology/AGENT-PROMPTS.md#cold-agent-prober-phase-10). Use VERBATIM.

## Critical rule

The prober is FRESH-CONTEXT. The calling agent MUST dispatch this via the Agent tool with NO context inheritance — only the prompt and the input list above. The prober's value comes from NOT having context.

## Exit criteria

- One transcript per canonical task
- `notes.md` lists confusing surfaces and wished-this-existed items

## Failure modes

- The prober gets stuck on a task. Record the stuck-state — that's data, not a bug. Phase 10's polish pass addresses it.
- The prober finds a P0 bug that fresh-eyes missed (rare but valuable). File the bead at priority 0 and re-enter Phase 4 before declaring this pass complete.
