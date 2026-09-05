# Subagent: recovery-drill-runner

**Phase:** 3 (after bundle build) and Phase 9 round 3
**Spawn:** Once per checkpoint.

## Role

Verify recovery recipes work. Phase 3 spot-checks one candidate; Phase 9 verifies the full recovery chain.

## Prompt

You are verifying that recovery recipes actually work.

### Phase 3 spot check (after bundle build)

1. Pick one candidate at random from `<workspace>/candidates.tsv`.
2. Read its row from `<bundle>/index.tsv`; note the `content_hash_sha256`.
3. Verify the bundle copy matches:
   ```bash
   sha256sum <bundle>/working-tree-copies/<path>
   ```
   should equal the recorded hash.
4. Verify recovery via the documented method:
   ```bash
   tmp=$(mktemp -d)
   cp <bundle>/working-tree-copies/<path> $tmp/recovered
   sha256sum $tmp/recovered
   ```
   should match the live file's hash.
5. Verify backup ref recovery:
   ```bash
   date_str=$(date -u +%Y-%m-%d)
   git show "refs/repo-janitor-backup/${date_str}-pre-cleanup":<path> | sha256sum
   ```
   should match.

If any verification fails: HALT. Bundle is unsafe. Restart Phase 3.

### Phase 9 round 3 (after all cleanups landed)

For each verdict in `triage.tsv`, simulate recovery:

1. **For move**: pick one moved file; verify `git revert <move-commit>` produces a clean revert (DRY-RUN: `git revert --no-commit <sha>; git restore --staged --worktree .`).

2. **For delete-and-gitignore**: pick one deleted file; verify `git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- <path>` would restore it (DRY-RUN: check the path exists in the backup ref's tree).

3. **For gitignore-only**: pick one new pattern; verify `git check-ignore -v <synthetic-path>` fires correctly.

4. **For protected**: no recovery test needed (the file wasn't touched).

Write findings to `<workspace>/recovery_drill.md`:

```markdown
## Recovery drill — Phase 9 round 3

### Move recovery
- Sample candidate: COMPREHENSIVE_PLAN_FOR_DUMMY.md (id=017)
- Recovery method: git revert <move-commit-sha>
- DRY-RUN result: PASS (revert applies cleanly)

### Delete-and-gitignore recovery
- Sample candidate: storage.sqlite3 (id=000)
- Recovery method: git checkout refs/repo-janitor-backup/2026-05-08-pre-cleanup -- storage.sqlite3
- DRY-RUN result: PASS (file exists in backup ref tree)

### Gitignore-only recovery
- Sample pattern: /storage*.sqlite3*
- Verification: git check-ignore -v storage.sqlite3
- Result: PASS (.gitignore:42:/storage*.sqlite3* storage.sqlite3)
```

If any drill fails: HALT Phase 10. Investigate; fix; re-run drill.

## Output

- `<workspace>/recovery_drill.md` (with PASS/FAIL per dimension)

## Tools used

Read, Bash.

## Time budget

3-5 min per checkpoint.
