---
name: handoff-reporter
description: Phase 10 — emit the final handoff report, file beads issue, run bv triage, remind user to push.
---

# Handoff Reporter

Owns Phase 10. The user's wrap-up. Includes counts, recovered SHAs, recovery recipes, push instructions, bundle lifecycle note.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir

## Workflow

1. Run `scripts/handoff-report.sh {PROJECT}`. This produces `<workspace>/handoff_report.md`.

2. **Augment the report** by reading `apply_log.tsv` + `partial_split_log.tsv` to surface:
   - Each recovered commit's full SHA + the original stash's date + the message
   - Conflict resolutions performed (with paths to the context.md files)
   - Any `superseded-during-apply` flips from Phase 6 (which Phase 4 thought were novel)

3. **File a beads issue**:
   ```bash
   br create \
     --title "stash janitor pass on <basename> (<N> stashes)" \
     --type=task \
     --priority=4 \
     --json
   # Then update with --status=closed --reason "..." once written
   ```
   Link the issue id back into the report. If `br` is unavailable, skip and record `beads_skipped: true`.

4. **Update Agent Mail thread**:
   ```
   send_message(
     thread_id=<beads-id>,
     subject="[<beads-id>] Completed: stash janitor",
     body=<one-paragraph summary>
   )
   release_file_reservations(...)
   ```

5. **bv triage** — if available:
   ```bash
   bv --robot-triage > <workspace>/post_run_bv_triage.json
   ```
   If the recovered commits unblocked any beads issues, append a "Newly unblocked beads" section to the report.

6. **Print push instructions to user** verbatim:
   ```
   Stash janitor run complete. To land the recovered work:

     git push origin stash-recovery-<DATE>
     # Then open a PR against <primary-branch> for review

   Bundle path: <BUNDLE>
   Beads issue: <id>
   Report: <workspace>/handoff_report.md
   ```

## Critical rules

- **Never push.** Print the command; the user pushes.
- **Never delete the bundle.** Note its path; user manages lifecycle.
- **If `br` or Agent Mail are unavailable**, skip those steps and record in the report.
- **Run `polish-bar-check.sh`** as a final sanity check. If any dimension fails, escalate before declaring success.

## Coordination

- File reservation: `paths=[".stash_janitor_workspace/handoff_report.md"]`, `exclusive=true`.

## Quality gates

- [ ] `handoff_report.md` exists with all sections filled
- [ ] Recovered commits are listed with SHA + stash + message
- [ ] Recovery recipes are verbatim shell commands
- [ ] Push command is printed (not executed)
- [ ] Beads issue filed (or `beads_skipped` recorded)
- [ ] `polish-bar-check.sh` passes

## Exit criteria

Report emitted; user told the push command; main agent declares run complete.
