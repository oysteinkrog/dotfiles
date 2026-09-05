# Subagent: phantom-deletion-detector

**Phase:** 1 / 2 transition (before any cleanup work)
**Spawn:** Once per run.

## Role

Detect phantom deletions per Axiom 24 + PHANTOM-DELETIONS.md. Halt the cleanup if more than 5 phantom deletions are present.

## Prompt

You are detecting phantom deletions before any cleanup work begins.

Steps:

1. Get all currently-deleted-but-tracked files:
   ```bash
   git status --porcelain | awk '$1 == "D" {print $2}' > /tmp/deleted_files.txt
   ```

2. For each, check if the LAST commit was a deletion:
   ```bash
   while IFS= read -r path; do
       last_commit_op=$(git log -1 --pretty=format: --name-status -- "$path" 2>/dev/null | tail -1 | awk '{print $1}')
       if [[ "$last_commit_op" != "D" ]]; then
           echo "PHANTOM: $path  (last_commit_op=$last_commit_op; file is deleted from working tree but its last commit didn't delete it)"
       fi
   done < /tmp/deleted_files.txt > <workspace>/phantom_deletions.tsv
   ```

3. Count phantom deletions:
   ```bash
   phantom_count=$(grep -c "^PHANTOM:" <workspace>/phantom_deletions.tsv)
   ```

4. If `phantom_count > 5`: **HALT** the cleanup. Surface to user per PHANTOM-DELETIONS.md template.

5. Investigate the cause:
   - Check `git reflog` for recent unusual operations.
   - Check shell history if available (`atuin export`, `~/.bash_history`).
   - Check ntm panes if active.
   - Write findings to `<workspace>/phantom_deletion_diagnostic.md`.

6. Group by subtree:
   ```bash
   awk -F: '/^PHANTOM:/ {split($2, parts, "/"); print parts[1]}' <workspace>/phantom_deletions.tsv | sort | uniq -c
   ```

7. Generate restoration script (NOT auto-executed) — per PHANTOM-DELETIONS.md:
   ```bash
   cat > <workspace>/restore-phantom-deletions.sh <<EOF
   #!/usr/bin/env bash
   # restore-phantom-deletions.sh
   # Source: phantom_deletions.tsv
   set -euo pipefail
   cd $project
   # ... per-subtree restore commands
   EOF
   chmod +x <workspace>/restore-phantom-deletions.sh
   ```

8. Surface to user with the recommendation. Three options:
   (a) Restore — run the script
   (b) Keep removed — the user confirms these are intentional manual deletions
   (c) Investigate per-subtree — surface a detailed list

## Output

- `<workspace>/phantom_deletions.tsv`
- `<workspace>/phantom_deletion_diagnostic.md` (only if phantom_count > 5)
- `<workspace>/restore-phantom-deletions.sh` (only if phantom_count > 5)

## Tools used

Read, Bash, Edit.

## Time budget

1-3 min for detection. User-driven for resolution.

## Hard stops

If phantom_count > 5 AND user picks (a) "restore" but the restoration script fails: HALT. Investigate before proceeding. The repo is in an unsafe state for cleanup until working tree matches HEAD intent.

If user picks (b) "keep removed" but the deletions span 5+ files in 3+ subtrees: ask one more time. Mass deletions are rarely intentional in a single subtree, let alone scattered.

If user picks (c) "investigate" and ends up with 50% of the deletions intentional and 50% accidental: mark those rows in `triage.tsv` with verdict `restore-do-not-commit` for the accidental ones, `surface-to-user` for the rest, then continue.
