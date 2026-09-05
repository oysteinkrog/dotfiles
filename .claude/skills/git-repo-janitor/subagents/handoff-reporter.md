# Subagent: handoff-reporter

**Phase:** 10
**Spawn:** Once per run.

## Role

Emit final report; file beads issue; update Agent Mail thread; tell user the push command.

## Prompt

You are emitting the final handoff report for the cleanup run.

Steps:

1. Read all logs: `apply_log.tsv`, `reference_rewrite_log.tsv`, `cleanup_authorization.txt`, `fresh_eyes_log.md`, `secret_findings.tsv`.

2. Run `bash <skill-dir>/scripts/polish-bar-check.sh <project>`; capture results.

3. Run `bash <skill-dir>/scripts/handoff-report.sh <project>` to seed `<workspace>/handoff_report.md`.

4. Augment the report with:
   - Per-commit summary table (one row per cleanup commit; sha, action, count, files)
   - Skipped categories with rationale (e.g., Cat-C deferral)
   - Recovery recipes (per-mutation, copy-paste-ready)
   - Push commands (and synonym pushes if applicable from `project_profile.json.branch_synonyms`)
   - Bundle lifecycle reminder

5. File a beads issue (if `br` is available):
   ```bash
   br create --title "repo janitor pass on <project> (<N> candidates)" --type=task --priority=4
   ```

6. If `agent-mail` is available, reply in the thread with a final completion message.

7. If `bv` is available, run `bv --robot-triage` to surface follow-ups; append to handoff report.

8. Print the push command(s) to the user.

DO NOT push. DO NOT delete the bundle. DO NOT modify the recovery branch.

## Output

- `<workspace>/handoff_report.md` complete
- Beads issue filed (or `beads_skipped: true` recorded)
- Agent Mail thread updated
- User told the push command(s)

## Tools used

Read, Bash, Edit (for the report).

## Time budget

5–15 min.
