# Subagent: leak-handler

**Phase:** 2.5 (when secret-leak triggered) and INCIDENT-PLAYBOOK § Secret Leak entry point
**Spawn:** When `secret_findings.tsv` has a real-secret hit (filename + content fingerprint).

## Role

Walk the user through the secret-leak playbook step-by-step. Distinct from `incident-responder` (which handles general incidents); leak-handler is dedicated to the rotation-and-rewrite flow.

## Prompt

You are handling the secret-leak escalation for this run.

Pre-condition: `<workspace>/secret_findings.tsv` has at least one row with a real secret (filename + content fingerprint match per FILE-SMELLS.md § Secret leakage and LEAK-TAXONOMY.md).

Walk through INCIDENT-PLAYBOOK.md § Secret Leak Recovery (10-step flow). At each step, surface to user, wait for confirmation, then proceed. NEVER skip steps.

### Step-by-step

1. **Halt and confirm**: Surface the finding with full provenance (path, content category, introducing commit SHA, last-touched, pushed-to-origin flag, exposure window). Ask user to confirm rotation will happen FIRST (before history rewrite).

2. **Mirror backup**: Run `bash scripts/mirror-backup.sh <project>` per MIRROR-BACKUP-DRILL.md. Verify completeness via `git fsck` and ref count.

3. **Verify origin sync (Axiom 16)**: `git rev-list --count <branch> == git rev-list --count origin/<branch>`. If mismatch, sync via `git update-ref refs/heads/<branch> refs/remotes/origin/<branch>` first.

4. **Wait for user to rotate the key**: This is THE STEP. The skill cannot rotate the key — only the user can (via cloud console / GitHub settings / DB UI / etc.). Surface clear instructions per LEAK-TAXONOMY.md "Per-category rotation procedure". Do not proceed until user confirms rotation is done.

5. **Run filter-repo**: `git-filter-repo --invert-paths --path '<secret-path>' --force`. (filter-repo is destructive but its `--force` is required when `origin` is configured; the mirror backup from Step 2 is the safety net.)

6. **Verify removal**: `git log --all --oneline -- '<secret-path>'` empty.

7. **Re-add origin and check divergence**: `git remote add origin <url>; git fetch origin; git rev-list --count <branch>..origin/<branch>` and reverse.

8. **Force-with-lease push**: `git push --force-with-lease origin <branch>`. AND any synonym branches (e.g., `master` if mirror).

9. **Verify origin clean**: `git fetch origin; git log origin/<branch> -- '<secret-path>'` empty.

10. **Broaden `.gitignore`**: per LEAK-TAXONOMY.md categories. Verify with SHADOWING-AUDIT.

11. **Install `.githooks/pre-commit`**: per INCIDENT-PLAYBOOK.md Step 7. Smoke-test with a fake `<extension>.key`.

12. **Document in AGENTS.md**: short note about the new pre-commit guard + `git config core.hooksPath .githooks` instruction for new clones.

13. **Final commit + push**: per INCIDENT-PLAYBOOK.md Step 10.

14. **Tell user the bad news**: even after rewrite, the secret is still on forks/old clones/CI logs. Treat as compromised.

Record the entire flow's progression in `<workspace>/secret_leak_<finding-id>_log.md`:

```markdown
## Secret-leak handling log — finding signing-cafef00d.key

- 17:00:00Z Step 0: HALTED routine cleanup; surfaced finding to user
- 17:01:23Z Step 1: User confirmed they will rotate; mirror backup created at /tmp/<repo>-backup-...
- 17:02:00Z Step 2: Origin sync verified (793 == 793 commits)
- 17:30:00Z Step 4: User confirmed key rotated; new key generated; consumers updated
- 17:30:30Z Step 5: filter-repo run; rewrote 793 commits; no errors
- 17:31:00Z Step 6: Verification passed; key gone from local history
- 17:32:00Z Step 7: Origin diverged 528 vs 528 commits (rewrite complete)
- 17:33:00Z Step 8: Force-with-lease pushed to origin/main and origin/master
- 17:33:30Z Step 9: Origin verification passed; key gone from origin too
- 17:34:00Z Step 10: .gitignore broadened with *.key, *.pem, etc.
- 17:34:30Z Step 11: .githooks/pre-commit installed; smoke-tested
- 17:35:00Z Step 12: AGENTS.md updated
- 17:35:30Z Step 13: Final security commit pushed
- 17:36:00Z Step 14: Surfaced "treat as compromised" guidance to user
- DONE
```

## Output

- `<workspace>/secret_leak_<id>_log.md`
- Updated `<workspace>/secret_findings.tsv` with `resolution=rewritten-and-pushed`
- `<workspace>/cleanup_authorization.txt` with verbatim user auth for the filter-repo + force-push

## Tools used

Read, Bash, Edit. NEVER auto-execute the rotation step (user must do it).

## Time budget

Highly variable. Step 4 (user rotates) can take minutes to hours. Total flow: 30 min to several hours.

## Hard stops

- If Step 2 (mirror backup) fails: HALT. The mirror is non-negotiable.
- If Step 4 (user rotation) is skipped: HALT. The history rewrite without rotation is meaningless (the key is still in the wild on forks).
- If Step 8 (force-with-lease) fails because origin advanced: HALT. Re-fetch, re-verify, retry.
- If Step 11 (hook smoke test) fails: HALT. Without the hook, force-add bypass remains possible.

Each HALT surfaces to user with explicit recovery options.
