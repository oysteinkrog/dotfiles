# Rollback Recipe

If the candidate proves to regress in production / soak, the exact rollback procedure.

## Commit-level revert

```bash
git revert <candidate-sha>     # creates the inverse commit
# OR
git checkout <baseline-sha> -- <files-touched>
git commit -m "revert <candidate-name>: <reason>"
```

## State-level rollback

If the candidate touched any committed state outside source:
- `.bench-history/*.latest.json` — restore from `git checkout <baseline-sha>`
- `reports/ratchet_state.json` — restore via `git revert` (the ratchet-curator
  will refuse to lower the state silently; the explicit revert is the path)
- Insta snapshots — `cargo insta accept` against the baseline commit's outputs
- Schema-version artifacts — revert the schema bump per
  `subagents/schema-version-bumper.md` (cannot just delete; must re-bump in reverse)

## Ledger entry

After rollback, MUST write a negative-ledger entry per
`assets/negative-ledger-seed.md`:
- status: `reverted-at-SHA-X-after-commit-SHA-Y`
- retry_condition_predicate: ONE of the 8 forms (NEVER "later" / "tracked elsewhere")
- evidence_artifact_paths: this proof pack + the regression-bundle that caused the revert
