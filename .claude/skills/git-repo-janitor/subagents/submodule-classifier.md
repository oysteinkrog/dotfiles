# Subagent: submodule-classifier

**Phase:** 1
**Spawn:** Once per run, but only if `.gitmodules` exists.

## Role

Per SUBMODULE-HANDLING.md: classify each submodule's state (fast-forward / rewind / dirty / etc.) and decide which require user attention before any cleanup.

## Prompt

You are classifying submodules in `<project>` per SUBMODULE-HANDLING.md.

Skip if `.gitmodules` doesn't exist.

Steps:

1. Enumerate submodules:
   ```bash
   git submodule status > <workspace>/submodule_status.txt
   ```

2. Get diff details:
   ```bash
   git diff --submodule=log > <workspace>/submodule_diff_log.txt
   git diff --submodule=short > <workspace>/submodule_diff_short.txt
   ```

3. Classify each submodule path:
   - **OK**: pointer matches recorded; no working-tree drift inside
   - **Fast-forward**: pointer changed forward; clean
   - **Rewind**: pointer changed BACKWARD (would lose commits if committed)
   - **Diverged**: pointer changed to an unrelated branch / SHA
   - **Dirty**: pointer changed AND working tree inside has uncommitted changes

4. Check for shallow submodules:
   ```bash
   git config --get-regexp '^submodule\..*\.shallow$'
   ```

5. Check for `protocol.file.allow` issues:
   ```bash
   git config --get protocol.file.allow
   ```

6. Build `<workspace>/submodule_warnings.tsv`:
   ```
   submodule_path                  status      action
   crates/frankenterm-vendor       rewind      skip; require user override (would lose commits)
   crates/frankenterm-core/python  dirty       skip; user must clean inside submodule first
   external/lz4                    ok          proceed with parent-repo cleanup; submodule out of scope
   ```

7. For each rewind/dirty/diverged: surface details to user. Provide the exact commands they could run if they want to proceed:

```
The submodule `crates/frankenterm-vendor` has a REWIND pointer change.

Current state:
  Recorded: abc123
  Current:  def456 (rewind — would lose 3 commits)

Lost commits if committed:
  - <commit 1 message>
  - <commit 2 message>
  - <commit 3 message>

Options:
  (a) Reset the submodule pointer (recommended):
      cd crates/frankenterm-vendor
      git checkout abc123

  (b) Confirm the rewind is intentional and override:
      Type "yes I understand and want to commit the rewind of crates/frankenterm-vendor" to proceed.

  (c) Investigate why the pointer rewound:
      cd crates/frankenterm-vendor && git reflog | head -20
```

8. Wait for user resolution per submodule before continuing.

## Output

- `<workspace>/submodule_status.txt`
- `<workspace>/submodule_diff_log.txt`
- `<workspace>/submodule_diff_short.txt`
- `<workspace>/submodule_warnings.tsv` with classification + recommended action
- Per-submodule resolution log in `<workspace>/submodule_resolutions.tsv`

## Tools used

Read, Bash.

## Time budget

2-10 min depending on submodule count and how many require user resolution.

## Special cases

- If parent repo's only "uncommitted change" is the submodule pointer update AND it's a fast-forward: surface "the only change is the submodule pointer; should I commit it?" with the per-submodule commit-message template.
- If multiple submodules are dirty with overlapping concerns: surface all together; let user resolve in batch.
- If submodule path is itself a candidate for cleanup (rare; usually it's a vendor dir): surface as "this is a submodule subtree; out of scope for the parent-repo cleanup; recommend separate skill instance."
