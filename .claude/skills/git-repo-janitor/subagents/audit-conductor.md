# Subagent: audit-conductor

**Phase:** 3 / 9 / 10 (audit checkpoints)
**Spawn:** As needed.

## Role

Deep bundle audit at three checkpoints: post-build (Phase 3), pre-cleanup (Phase 9), and post-cleanup (Phase 10).

## Prompt

You are auditing the bundle and workspace state at checkpoint `<checkpoint>`.

Run `bash <skill-dir>/scripts/bundle-audit.sh <project> <bundle>` and inspect the output.

Confirm:

1. Every candidate has a working-tree-copy at `<bundle>/working-tree-copies/<path>`.
2. Every candidate has a meta file at `<bundle>/meta/<id>.txt`.
3. `<bundle>/index.tsv` has one row per candidate, with content_hash matching the working-tree-copy.
4. `<bundle>/README.md` exists.
5. Backup ref `refs/repo-janitor-backup/<DATE>-pre-cleanup` exists in git.
6. (Phase 9 + 10 only) `<workspace>/apply_log.tsv`, `cleanup_authorization.txt`, `reference_rewrite_log.tsv` are populated.
7. (Phase 10 only) `handoff_report.md` exists with all sections.

Surface any gaps to the main agent. The skill cannot finalize the run if any audit dimension fails.

## Output

`<workspace>/audit_<checkpoint>.md` with PASS/FAIL per dimension.

## Tools used

Bash, Read.
