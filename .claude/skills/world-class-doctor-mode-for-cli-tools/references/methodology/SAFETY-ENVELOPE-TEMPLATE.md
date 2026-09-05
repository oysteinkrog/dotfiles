# Safety Envelope Template

Phase 3 produces a project-specific `<workspace>/analysis/safety_envelope.md` extending the universal envelope below. The project-specific envelope can ADD constraints; it must not remove or contradict any universal one.

---

## Universal envelope (every doctor must obey)

1. **No file deletion during diagnose/fix/undo.** Per AGENTS.md RULE 1. `<tool> doctor undo` RESTORES from backup; it never erases. Quarantined files are MOVED via `Op::Rename`, not deleted. The only deletion-capable surface is separate retention cleanup: `<tool> doctor gc --before <date> --yes`, which never runs implicitly or as part of a fixer.

2. **No destructive shell commands.** Never `rm -rf`, `git reset --hard`, `git clean -fd`, `DROP TABLE`, `kubectl delete`, or any equivalent. If equivalent semantics are needed, implement them in code, scoped, recorded.

3. **Writes are scoped.** Doctor only writes inside `capabilities --json::write_scopes` (typically `.<tool>/`, `~/.config/<tool>/`, `<workspace>/.doctor/`, and any `data_paths` it owns). Out-of-scope writes refuse with exit 4 by default.

4. **Writes are atomic.** Every disk write uses write-tmp-then-rename (or DB transaction). No in-place truncation. No half-written files visible to readers.

5. **Backups are verbatim.** No transcoding, no normalization. `cmp -s backup live` succeeds at the moment of backup.

6. **Hashes witness everything.** Every `mutate()` call records `{path, before_hash, after_hash, op, timestamp}` in `actions.jsonl`. SHA-256 minimum.

7. **Locks are explicit.** `mutate()` takes the project's existing lock (or a doctor-specific one) before any read or write. If unavailable for K seconds (default 5 s), refuse with exit 5.

8. **Network only on opt-in.** Default is offline. `--online` required for any network call. Network failures downgrade to `findings_only_offline`; never wedge a fixer.

9. **No mutation in detect mode.** `<tool> doctor` (no `--fix`) never writes anywhere except append-only `.doctor/runs/<run-id>/{report.json, report.md}` artifacts and an atomic update of `.doctor/latest`.

10. **No mutation if any precondition fails.** Each fixer has explicit preconditions. If any fails, refuse with a finding pointing at the unmet precondition: exit 4 for unsafe non-lock preconditions, exit 5 for lock contention, exit 6 for online-required checks when `--online` was not passed.

---

## Project-specific extensions (template — fill in during Phase 3)

Use the section below as the skeleton for `<workspace>/analysis/safety_envelope.md`.

```markdown
# Safety Envelope — <tool> doctor (project-specific)

Extends the universal envelope at `references/methodology/SAFETY-ENVELOPE-TEMPLATE.md`. Adds project-specific constraints; never removes or contradicts.

## Write scopes (strict)

The full set of paths `<tool> doctor` may write to under `--fix`:

- `<repo>/.<tool>/`
- `<repo>/.doctor/`
- `~/.config/<tool>/`        (only if XDG_CONFIG_HOME isn't set)
- `<XDG_CONFIG_HOME>/<tool>/` (otherwise)

**Anything else is forbidden.** Out-of-scope writes refuse with exit 4 and a `safety_block` finding.

## Read scopes (informational)

The full set of paths the doctor reads (no constraint, but documented):

- `<repo>/.<tool>/`
- `<repo>/.git/HEAD`           (read-only; just for run-id derivation)
- ...

## DB family handling (if applicable)

If the project uses an embedded DB:

- The DB file family is treated as ONE unit: `<db>.db`, `<db>.db-wal`, `<db>.db-shm`, `<db>.db-journal`.
- Backups copy ALL family members or NONE (atomic).
- Restores write ALL family members or NONE.
- Mid-restore failure refuses to leave a partial family on disk.

## Lock primitive

The doctor uses `<repo>/.<tool>/.doctor.lock` (advisory) acquired via:

- Rust: `fs2::FileExt::try_lock_exclusive()`
- Go: `syscall.Flock(fd, LOCK_EX|LOCK_NB)`
- Python: `portalocker.lock(fd, portalocker.LOCK_EX | portalocker.LOCK_NB)`
- TS: `proper-lockfile.lockSync(<path>, { realpath: false })`

Lock TTL: 5 minutes, auto-released on process exit. If still held after a 5 s acquire timeout, refuse with exit 5.

## "Will never do"

- Touch `.git/` directly (only via the project's existing git-aware code paths).
- Remove or rewrite the user's commits.
- Delete configuration the user wrote.
- Modify files outside the documented write scopes.
- Run any external command not in the explicit allow-list (allow-list TBD per project).
- Probe network unless `--online` is set.
- Mutate while a concurrent doctor invocation holds the lock.

## Project-specific invariants

(Fill in during Phase 3 after reading all repair specs. Examples:)

- Issue IDs in `.beads/issues.jsonl` are UUIDv7-ish and never reassigned by the doctor.
- The DB schema_version monotonically increases; doctor never downgrades.
- Stale lockfiles older than 1 hour are quarantine candidates.
- Configuration files preserve the user's comment lines.

## Exit-4 conditions (project-specific)

(Add to the universal exit-4 conditions:)

- DB schema_version is unknown (binary doesn't have a migration for it).
- Two doctor runs detected within 1 second on the same workspace (race).
- The DB is currently being written to by another process.
- ...
```

The template above is a starting point. Phase 3's synthesizer reads every repair spec, extracts the load-bearing project-specific invariants, and fills in this template.
