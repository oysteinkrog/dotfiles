---
name: cass-miner
description: Phase 0.5 — mine prior agent sessions via /cass for context, conventions, prior runs, and related incidents. Optional but valuable.
---

# CASS Miner

Owns Phase 0.5 (optional). Searches prior agent sessions for context that informs Phase 4 triage and Phase 5 user surface.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BASENAME}` — basename of the project

## Workflow

1. Verify cass availability: `cass health --json`. If not available, write a stub `cass_findings.md` and exit cleanly.
2. Run `scripts/cass-mine.sh {PROJECT}`. This handles default queries:
   - `"stash janitor {basename}"` (prior runs)
   - `"git stash {basename}"` (any prior stash work)
   - For each ticket id found in the inventory's stash messages: `"<ticket-id>"`
3. **Review findings.** For each cass match, classify into:
   - `prior-run-on-this-project` — augment Phase 5's user surface with "previous run authored N keepers"
   - `convention-discovery` — augment `project_profile.json:stash_message_conventions` with the discovered patterns
   - `related-incident` — flag for Phase 4 confidence-boost on relevant fingerprints
   - `domain-knowledge` — feed to Phase 6 commit-message-author for richer prose
   - `irrelevant` — discard

4. Write `cass_findings.md` with the classified findings. Include:
   - Source session paths (so the user can read them)
   - Classification per finding
   - Skill-state summary at the end ("0 priors," "1 prior with 2 unmerged keepers," etc.)

## Critical rules

- **Never run bare `cass`** (launches TUI, blocks the session).
- **Always use `--robot --json`** for parseable output.
- **Use `--days 90`** (or shorter) to bound the search.
- **If cass isn't available, skip cleanly.** Don't fail the run.
- **Privacy:** cass findings stay in the workspace; don't push them.

## Coordination

- File reservation: `paths=[".stash_janitor_workspace/cass_findings.md"]`, `exclusive=true`, `reason="stash-janitor-phase0.5"`.
- Thread id: `stash-janitor-<run-id>`.

## Quality gates

- [ ] `cass_findings.md` exists (even if empty / skipped)
- [ ] Each finding has a classification
- [ ] Skill-state summary at end of file

## Exit criteria

Findings file written; main agent uses it to inform Phase 4 (rubric tweaks) and Phase 5 (user-facing context).
