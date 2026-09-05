# Mining Prior Sessions via /cass

Optional Phase 0.5 step. Searches `cass` index for prior cleanup runs against the same repo (or related repos) to surface lessons learned.

---

## When useful

- Re-running cleanup on a repo that's been cleaned before — find what was deferred or escalated.
- Cleaning a repo whose owner ran cleanups on related repos — adopt their archetype-level overrides.
- Investigating why a previous run halted (e.g., secret-leak escalation, large refactor in flight).

---

## Searches the cass-miner subagent runs

```bash
# Direct: prior cleanups on this repo
cass search "<repo-basename> cleanup" --robot --limit 10 --fields minimal --days 180
cass search "<repo-basename> repo janitor" --robot --limit 10 --fields minimal --days 180
cass search "<repo-basename> tracked top-level" --robot --limit 10 --fields minimal --days 180

# Related: archetype-level lessons
cass search "<archetype> cleanup deferred" --robot --limit 10 --fields minimal --days 180
cass search "TOML hardcoded paths skip move" --robot --limit 5 --fields minimal --days 180
cass search "secret leak <archetype>" --robot --limit 5 --fields minimal --days 180

# Pattern-specific
cass search "git filter-repo shallow clone" --robot --limit 5 --fields minimal --days 365
cass search "force-add bypass gitignore" --robot --limit 5 --fields minimal --days 365
```

---

## What to extract

For each hit:

1. **Was the run successful?** If it halted: why? Add the cause to the current run's `cass_findings.md`.
2. **What categories did it defer?** If a Cat-C-style deferral happened previously, the same pattern likely applies now.
3. **Were any secrets found?** If yes: the secret is rotated by now (per the playbook), but the `.gitignore` patterns and pre-commit hook should be in place. Verify they survived.
4. **Were there false-positive deletes?** Document them so the current run's REFERENCE-GREP catches the same case.

---

## Output: `<workspace>/cass_findings.md`

Plain markdown summary, one section per relevant finding:

```markdown
# CASS findings — repo-janitor pre-flight for /data/projects/<repo>

## Prior cleanups (3 hits)

### 2026-04-27 cleanup (109 → 45 files)
- Path: cass session 900368e8...
- Mode: Standard
- Outcome: 8 commits landed; Cat C (15 TOMLs) DEFERRED.
- **Lesson:** Cat C TOMLs are referenced by 20+ Rust files via hardcoded
  paths. Don't move them this run unless user wants the larger surgery.

### 2026-03-15 cleanup (attempted, halted)
- Path: cass session a72cdef0...
- Mode: Standard
- Outcome: HALTED at Phase 6 due to mid-rebase state
- **Lesson:** Project sometimes has long-lived rebases; check `git status`
  before starting. Phase 0 git-doctor catches this.

## Archetype-level lessons (2 hits)

### "TOML hardcoded paths skip move" pattern
- Source: cass session ... (frankensqlite Apr-27)
- **Rule:** When a candidate has ≥10 inbound refs via hardcoded path strings
  in source code, mark category DEFERRED.

## Secret-leak findings (0 hits)

No prior secret-leak escalations found for this repo.
```

The main agent reads this before Phase 4 verdict computation. Prior lessons can shift the smell rules' priors for this run.

---

## When cass is unavailable

If `cass health` returns unhealthy or the index is stale:

1. Surface the warning to the user.
2. Skip Phase 0.5 entirely.
3. Run without prior-context.

The skill's design doesn't require cass; it's a quality enhancement.

---

## Privacy note

`cass` indexes prior sessions, which may contain prompts, file paths, and snippets from those sessions. Don't include verbatim secrets or PII in `cass_findings.md`. The cass-miner subagent extracts lessons (rules, patterns, deferrals) but not raw content.

If a prior session surfaced a secret: don't reproduce the secret in the findings. Just record "secret-leak escalated successfully" with a date.
