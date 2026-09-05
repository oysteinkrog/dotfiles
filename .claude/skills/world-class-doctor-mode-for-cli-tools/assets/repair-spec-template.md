# RS-fm-<id> — <title>

**Failure mode:** fm-<id>
**Subsystem:** <subsystem>
**Severity:** P0 | P1 | P2 | P3
**Currently auto-detected:** yes | no
**Currently auto-fixed:** yes | no

> Operators applied: 🩺 🚪 💾 ↩ 🔁 ⚡ 🔒 🧪 🛡 (mark the ones that apply)

---

## Detector

> PURE function. Returns `Finding | None`. NEVER calls `mutate()`. NEVER writes.

```pseudocode
fn detect_<id>(repo: &Repo) -> Option<Finding> {
    // Read disk / read in-memory state / read env vars.
    // Compute the broken-state predicate.
    let observed = ...;
    if !is_broken(observed) {
        return None;
    }
    Some(Finding {
        id: "fm-<id>",
        severity: P_,
        evidence: { /* file:line, query, hash */ },
        remediation: {
            command: "<tool> doctor --fix --only fm-<id>",
            explain_command: "<tool> doctor explain fm-<id>",
            auto_fixable: true,
        },
    })
}
```

---

## Fixer

> Routes EVERY write through `mutate(path, op)`. The fixer plans the writes
> in memory, then issues mutate() calls. Returns FixResult { actions_planned,
> actions_taken }.

```pseudocode
fn fix_<id>(repo: &Repo, ctx: &MutateContext) -> Result<FixResult> {
    // 1. Re-read current state (don't trust the detector's snapshot — it may
    //    be stale by Phase 5 timing).
    let current = ...;

    // 2. Compute desired state.
    let desired = ...;

    // 3. For each (path, op) in the plan:
    let mut actions_taken = 0;
    for (path, op) in plan_diff(current, desired) {
        let result = mutate(ctx, path, op)?;
        if result.ok { actions_taken += 1; }
    }

    // 4. Verify post-state via the detector.
    if detect_<id>(repo).is_some() {
        bail!("fix did not eliminate the finding");
    }
    Ok(FixResult { actions_planned: ..., actions_taken })
}
```

---

## Preconditions

- <e.g., the project's primary lock is acquirable>
- <e.g., the schema_version in capabilities matches the on-disk version>
- <e.g., the `.doctor/runs/<run-id>/backups/` directory is writable>

If any precondition fails, the fixer must NOT call mutate(). Instead, the
detector should already be emitting a finding pointing at the unmet
precondition; the fixer refuses with the precondition-appropriate exit code:
**exit 4** (`refused_unsafe`) for schema/scope/general preconditions, **exit 5**
(`concurrency_lost`) for lock-related preconditions, **exit 6** (`online_required`)
when a network probe is needed but `--online` was not passed. See the
canonical exit-code table in [CLI-SURFACE.md § exit_codes](../references/methodology/CLI-SURFACE.md).

---

## Invariants preserved

- <e.g., the issue ID set in issues.jsonl is unchanged>
- <e.g., no comments in source files are touched>
- <e.g., the .git/ directory is never touched>

---

## Backup spec

Files backed up by this fixer (verbatim, byte-identical, via mutate()):

- `<absolute-or-repo-relative-path>` — full file
- `<another-path>` — full file
- DB rows: `<table>::<rowkey-pattern>` — `pg_dump` / `sqlite3 .dump` of affected rows

The backup directory will be `<repo>/.doctor/runs/<run-id>/backups/<rel-path>`.

---

## Inverse

`<tool> doctor undo <run-id>` reads `actions.jsonl` in reverse and restores
each backup over its target.

Special-case logic (only if needed):
- <e.g., this fixer creates a file that didn't exist before. Undo restores
  the empty state by `Op::Rename` the created file to
  `<run-dir>/quarantine/created/<path>`. Per AGENTS.md no-delete, the file
  is moved aside, not deleted.>

---

## Idempotence proof sketch

After `fix_<id>` runs once successfully:

1. The post-fix state matches `desired`.
2. `detect_<id>` returns `None` against the post-fix state (verified inside
   the fixer at Step 4).
3. Therefore a second `fix_<id>` invocation enters the `if !is_broken
   { return None }` branch in the detector, returns no finding, and the
   runtime skips the fixer.

The second-run `actions_taken` is `0`. Verified by `verify-idempotence.sh fm-<id>`.

---

## Fixture spec

`tests/doctor_fixtures/fm-<id>/`:

### corrupt.sh
- Takes one positional arg: `target_dir`.
- Sets up a clean isolated workspace inside `target_dir`.
- Runs the project's bootstrap (e.g., `<tool> init`) so the workspace
  starts healthy.
- Applies the deterministic recipe: <describe exact bytes / steps>
- Stores byte-identical baseline at `$target_dir/.fixture_baseline/`.

### assert.sh
- Takes one arg: `target_dir`.
- Runs `<tool> doctor` (no flags) in `target_dir`.
- Asserts exit code 0.
- Asserts the FM's specific invariants: <list>

### README.md
- One paragraph describing what the fixture represents.
- The CASS quote / bead ID / git SHA that motivated this FM.
- Expected exit codes for corrupt → diagnose → fix → undo.

---

## Open questions

- <any item the implementer should confirm with the user>
