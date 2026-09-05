# subagent: handoff-writer (Phase 10)

**Description.** Write `<workspace>/HANDOFF.md` summarizing this pass's outcome, queued beads, and recommendations for the next pass.

## Inputs

- `{{workspace}}/manifest.json`
- `{{workspace}}/scorecard_pass_<N>.md`
- `{{workspace}}/uplift_diff.md`
- `{{workspace}}/regression_alerts.md` (if present)
- `{{workspace}}/agent_simulations/post_pass_<N>/notes.md`
- `br list --status=open --json` (open beads filed during this pass)
- `../assets/handoff-template.md`

## Outputs

- `{{workspace}}/HANDOFF.md`
- An agent-mail thread message (if `mcp__mcp-agent-mail__send_message` is available; idea #14, round 55):
    - `thread_id`: `doctor-pass-{{N}}-handoff`
    - `subject`: `[doctor-pass-{{N}}] Handoff: <one-line summary>`
    - `body`: full `HANDOFF.md` content (or pointer if > 8KB)
    - `ack_required`: true (so the next-pass orchestrator must acknowledge before proceeding)
    - Plus a `release_file_reservations` call for every reservation this pass created
- A `mail_handoff.json` artifact under `{{workspace}}/` recording the message_id + send timestamp + receiving thread URI, so subsequent passes can audit "did handoff fire?" deterministically. If agent-mail isn't installed, write `{"skipped": true, "reason": "agent-mail not available"}` so consumers don't conflate "skipped" with "failed".

## Prompt

Full prompt in [../references/methodology/AGENT-PROMPTS.md § handoff-writer](../references/methodology/AGENT-PROMPTS.md#handoff-writer-phase-10). Use verbatim.

## Required sections

1. Pass summary: pass number, target_sha, started_at, finished_at, duration
2. Scorecard before/after: aggregate + top 5 improvements + top 5 regressions
3. What changed: commits on `doctor-mode-pass-<N>` with one-line summaries
4. Open issues: beads filed during pass with priority
5. Next pass recommendations: 3–7 high-priority items
6. Files of interest: pointers to key artifacts

## Length budget

~80–150 lines. The next pass's first action is reading this.

## Exit criteria

- HANDOFF.md exists, contains all six required sections, is under 200 lines.
