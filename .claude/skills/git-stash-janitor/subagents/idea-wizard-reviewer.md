---
name: idea-wizard-reviewer
description: Phase 11 (optional) — review the run from a user-experience perspective. Produces skill_feedback.md for skill maintainers.
---

# Idea-Wizard Reviewer

Owns Phase 11 (optional, off by default). A fresh agent reviews the entire run from the perspective of "did this save the user time, and what would have made it better?"

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir (with all artifacts from prior phases)
- `{HANDOFF_REPORT}` — path to handoff_report.md

## Workflow

Use the Forensic + Adversarial reading stances combined.

1. Read in this order:
   - `handoff_report.md` (the official summary)
   - `apply_log.tsv` and `cleanup_log.tsv` (what actually happened)
   - `triage_decision.md` and `user_overrides.tsv` (what the user reviewed)
   - All `conflicts/*.context.md` (manual interventions)
   - `fresh_eyes_log.md` (what was caught late)
   - `cass_findings.md` (what context was available pre-run)
   - `verdict_stats.json` (the metrics)
   - `polish-bar-check.sh` transcript (the dimension scoring)

2. Identify friction points. For each, classify:
   - **Wait/repeat:** the user had to wait for the agent or was asked the same thing twice
   - **Ambiguous decision:** the rubric surfaced a row to the user with unclear evidence
   - **Missed coverage:** an issue caught by fresh-eyes that should have been caught by Phase 4 / 6
   - **Silent fallback:** something happened (e.g., `cass_skipped`) that the user didn't realize
   - **Excess noise:** the user was shown information they didn't need

3. For each friction point, propose a concrete change to:
   - SKILL.md (e.g., "add a Phase 0 sanity check for X")
   - A reference file (e.g., "STASH-SMELLS.md should include pattern Y")
   - A script (e.g., "discover-stashes.sh should also detect Z")
   - An operator card (e.g., "✦ FINGERPRINT should account for W")

4. Write `<workspace>/skill_feedback.md` with one section per friction point. Include:
   - Friction point description
   - Severity (low / medium / high)
   - Proposed change
   - Justification

5. Optionally: file beads issues against this skill for skill maintainers (use a separate beads project if available, or open issues with a `[stash-janitor-skill]` label).

## Critical rules

- **Don't propose code changes to the user's repo.** This is skill self-improvement, not user assistance.
- **Be specific.** "The skill could be better" is not feedback. "PHASES.md § Phase 6 should clarify what 'sequential' means in practice" is feedback.
- **Cite artifacts.** Reference the workspace files that inform each finding.
- **Don't blame the user.** If they made a verdict override that backfired, that's information about the rubric, not the user.

## Coordination

- File reservation: `paths=["<workspace>/skill_feedback.md"]`, `exclusive=true`.

## Quality gates

- [ ] skill_feedback.md exists with sections per friction point
- [ ] Each section has: description, severity, proposed change, justification
- [ ] Citations to specific workspace artifacts

## Exit criteria

Feedback file written. Optionally, beads issues filed. The user is informed that the file is for skill maintainers; they can read it but the run itself is complete.
