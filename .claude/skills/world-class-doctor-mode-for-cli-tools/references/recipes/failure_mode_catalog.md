# Cross-Language Failure-Mode Catalog

A class-by-class catalog of failure modes that recur across CLI tools regardless of language. For each class: typical symptoms, typical root causes, a representative detector pseudocode, a representative fixer pseudocode (always through `mutate()`), what gets backed up, and the fixture spec.

Phase 1's archaeologist uses this catalog as a starting point per subsystem.

---

## State files (embedded DB, JSONL, lockfiles, pidfiles)

### Symptoms
- `<tool>` panics with "no such table" or "malformed database" on a previously-working workspace.
- `<tool>` reports "lock held" for a process that's no longer alive.
- Two stores (DB + JSONL) disagree about the same record.
- `pragma integrity_check` returns non-OK.
- Sidecar files (`.db-wal`, `.db-shm`, `.db-journal`) present without their primary.

### Typical root causes
- Process killed mid-write; atomic-rename pattern missing.
- Sidecar family handled inconsistently across cleanup ops.
- Two writers raced because no advisory lock.
- A migration ran partially (DB at v8 schema while binary expects v7).

### Detector
```
detect_db_integrity(repo) -> Option<Finding>:
    db_path = repo/.<tool>/state.db
    if not db_path.exists(): return None
    open db read-only
    result = exec("PRAGMA integrity_check")
    if result != "ok":
        return Finding{id="fm-state-files-db-integrity", evidence={query, result}}
    return None
```

### Fixer
```
fix_db_integrity(repo, ctx):
    # Goal: rebuild from the project's source-of-truth (e.g., issues.jsonl).
    # 1. Backup the entire DB family.
    for f in [state.db, state.db-wal, state.db-shm, state.db-journal]:
        if exists(repo/f):
            mutate(ctx, repo/f, Op::Rename {to: ctx.run_dir/quarantine/state-files/f})
    # 2. Rebuild from JSONL.
    new_bytes = build_db_from_jsonl(read(repo/.<tool>/issues.jsonl))
    mutate(ctx, repo/.<tool>/state.db, Op::WriteFile { content: new_bytes, mode: 0o644 })
```

### Backup spec
- `state.db`, `state.db-wal`, `state.db-shm`, `state.db-journal` — entire family, atomically.

### Fixture
`tests/doctor_fixtures/fm-state-files-db-integrity/`:
- `corrupt.sh` — initialize, then truncate `state.db` to half its bytes.
- `assert.sh` — run `<tool> doctor`; assert exit 0; assert `pragma integrity_check` returns OK.

---

## Configs (TOML/YAML/JSON, env files, MCP configs)

### Symptoms
- Config file doesn't parse.
- Required keys missing.
- Conflicting keys with project defaults.
- MCP config references a no-longer-installed server.

### Typical root causes
- Manual edit introduced a syntax error.
- Migration of config schema didn't run.
- A merged config from multiple sources double-defined a key.

### Detector
```
detect_config_parseable(repo) -> Option<Finding>:
    config_path = repo/.<tool>/config.toml
    if not config_path.exists(): return None
    try parse(read(config_path))
    on err: return Finding{id="fm-configs-parse-error", evidence={file:line:col, error_msg}}
    return None
```

### Fixer
```
fix_config_parseable(repo, ctx):
    # Refuse — user must fix manually. Detector already filed remediation
    # with the parse error location and column.
    bail!("manual_remediation_required")
```

Many config issues should NOT be auto-fixed (the doctor doesn't know the user's intent). The detector emits a finding; the remediation is "edit `<file:line:col>` per the syntax error". List under `manual_remediations` in `capabilities --json`.

For the auto-fixable subset (e.g., adding a missing key with a documented default):

```
fix_missing_config_key(repo, ctx):
    config = parse(read(repo/.<tool>/config.toml))
    if "required_key" not in config:
        config["required_key"] = DEFAULT_VALUE
        mutate(ctx, repo/.<tool>/config.toml, Op::WriteFile {
            content: serialize(config), mode: 0o644
        })
```

### Backup spec
- The full original config file.

### Fixture
- `corrupt.sh` — write a config file with the missing required key.
- `assert.sh` — assert the key is now present with the default value.

---

## Schemas (DB migrations, schema-version mismatches)

### Symptoms
- "Schema version 7 but binary expects 8."
- Missing index drops query performance to unusable.
- A migration ran partially; some tables at vN, others at vN+1.

### Typical root causes
- User ran a newer binary than what last migrated the DB.
- Migration code crashed mid-run.
- Manual SQL edit bypassed the migration system.

### Detector
```
detect_schema_version_mismatch(repo) -> Option<Finding>:
    on_disk = read_schema_version(repo/.<tool>/state.db)
    expected = COMPILED_SCHEMA_VERSION
    if on_disk != expected:
        return Finding{id="fm-schemas-version-mismatch",
                       severity: "P0",
                       evidence={on_disk, expected, migration_path: known_or_unknown}}
    return None
```

### Fixer
```
fix_schema_version_mismatch(repo, ctx):
    on_disk = read_schema_version(repo/.<tool>/state.db)
    if on_disk > COMPILED_SCHEMA_VERSION:
        # Refuse — would be a downgrade.
        bail!("refused: downgrade from v{on_disk} to v{COMPILED_SCHEMA_VERSION}")
    # Run migrations forward, in order.
    for v in (on_disk + 1) ..= COMPILED_SCHEMA_VERSION:
        mutate(ctx, repo/.<tool>/state.db, Op::DbMigrate { from: v - 1, to: v })
```

### Backup spec
- DB family (`.db`, `.db-wal`, `.db-shm`, `.db-journal`) before the first migration.

### Fixture
- `corrupt.sh` — initialize at version (`COMPILED_SCHEMA_VERSION - 1`); truncate or downgrade.
- `assert.sh` — assert `read_schema_version()` == `COMPILED_SCHEMA_VERSION`.

---

## Caches (derived indexes, memo files, completion scripts)

### Symptoms
- Stale completion script offers commands that no longer exist.
- Memo file points at a deleted source file.
- Index returns stale results.

### Typical root causes
- Source file changed but cache wasn't invalidated.
- Cache version drifted from binary version.

### Detector
```
detect_stale_completion(repo) -> Option<Finding>:
    completion_path = ~/.bash_completion.d/<tool>
    if not completion_path.exists(): return None
    cached_version = parse_version_comment(completion_path)
    if cached_version != BINARY_VERSION:
        return Finding{id="fm-caches-stale-completion",
                       severity: "P3",
                       evidence={cached_version, expected: BINARY_VERSION}}
    return None
```

### Fixer
```
fix_stale_completion(repo, ctx):
    new_completion = generate_completion_script(BINARY_VERSION)
    mutate(ctx, ~/.bash_completion.d/<tool>,
           Op::WriteFile { content: new_completion, mode: 0o644 })
```

### Backup spec
- The old completion file.

### Fixture
- `corrupt.sh` — write a completion file with a bogus old version comment.
- `assert.sh` — assert the new file's version matches `BINARY_VERSION`.

---

## Sockets / pidfiles

### Symptoms
- Socket file present but no listener.
- Pidfile present but the PID isn't alive.

### Typical root causes
- Process crashed without cleanup.
- SIGKILL bypassed cleanup handlers.

### Detector
```
detect_orphan_socket(repo) -> Option<Finding>:
    sock = repo/.<tool>/socket
    if not sock.exists(): return None
    if can_connect(sock): return None
    return Finding{id="fm-sockets-orphan",
                   evidence={file: sock, last_modified: stat(sock).mtime}}
```

### Fixer
```
fix_orphan_socket(repo, ctx):
    sock = repo/.<tool>/socket
    quarantine = ctx.run_dir/quarantine/sockets/<basename>
    mutate(ctx, sock, Op::Rename { to: quarantine })
```

### Backup spec
- The socket file (just for forensics; sockets aren't restorable).

### Fixture
- `corrupt.sh` — `mkfifo .<tool>/socket` (or `nc -lU` then kill).
- `assert.sh` — assert no socket remains; assert quarantine has the moved file.

---

## Hooks (git hooks, pre-commit, IDE hooks)

### Symptoms
- Pre-commit hook references a missing binary.
- Hook ordering wrong (formatter runs after linter that depends on formatted output).
- Hook is a broken symlink.

### Typical root causes
- Project moved; hook still points at old absolute path.
- Tool was uninstalled; hook entry stayed.

### Detector
```
detect_broken_hook(repo) -> Option<Finding>:
    hook = repo/.git/hooks/pre-commit
    if not hook.exists(): return None
    if not hook.is_executable():
        return Finding{id="fm-hooks-not-executable",
                       evidence={file: hook, mode: stat(hook).mode}}
    if hook.is_symlink() and not target_exists(hook):
        return Finding{id="fm-hooks-broken-symlink",
                       evidence={file: hook, target: readlink(hook)}}
    # Parse the hook for missing binaries.
    for line in read(hook):
        bin = first_word(line)
        if bin in PATH_BIN_LIKE and not which(bin):
            return Finding{id="fm-hooks-missing-binary",
                           evidence={file: hook, line, binary: bin}}
    return None
```

### Fixer
```
fix_hook_not_executable(repo, ctx):
    mutate(ctx, repo/.git/hooks/pre-commit, Op::Chmod { mode: 0o755 })

fix_hook_broken_symlink(repo, ctx):
    quarantine = ctx.run_dir/quarantine/hooks/<basename>
    mutate(ctx, repo/.git/hooks/pre-commit, Op::Rename { to: quarantine })

fix_hook_missing_binary(repo, ctx):
    # Refuse — auto-installing missing binaries is out-of-scope; doctor
    # emits a finding with the install instruction.
    bail!("manual_remediation_required: install <bin>")
```

### Backup spec
- The hook file.

### Fixture
- `corrupt.sh` — `chmod -x .git/hooks/pre-commit` and/or `ln -s /nonexistent .git/hooks/pre-commit`.
- `assert.sh` — assert hook is executable AND not a broken symlink.

---

## Plugins (plugin dirs, extension manifests)

### Symptoms
- Plugin manifest references a missing directory.
- Plugin version skewed from host version.
- Two plugins claim the same name.

### Detector
```
detect_plugin_drift(repo) -> Option<Finding>:
    manifest = repo/.<tool>/plugins/manifest.json
    if not manifest.exists(): return None
    plugins = parse(read(manifest))
    for p in plugins:
        if not (repo/.<tool>/plugins/<p.name>).exists():
            return Finding{id="fm-plugins-missing-dir",
                           evidence={plugin: p.name}}
    return None
```

### Fixer
```
fix_plugin_drift(repo, ctx):
    manifest = parse(read(repo/.<tool>/plugins/manifest.json))
    cleaned = [p for p in manifest if (repo/.<tool>/plugins/<p.name>).exists()]
    mutate(ctx, repo/.<tool>/plugins/manifest.json,
           Op::WriteFile { content: serialize(cleaned), mode: 0o644 })
```

### Backup spec
- The manifest file.

### Fixture
- `corrupt.sh` — register a plugin in the manifest without creating its directory.
- `assert.sh` — assert the manifest no longer references the missing plugin.

---

## Secrets (keychain, env, credential files)

### Symptoms
- API key not set; doctor can't probe vendor APIs.
- Credential file world-readable (mode 0o644 on a key file).
- Token expired (only detectable via the vendor's API).

### Typical root causes
- User installed the binary on a new machine and didn't re-auth.
- File mode wrong from `cp` without `-a`.

### Detector (offline)
```
detect_credential_perms(repo) -> Option<Finding>:
    cred = ~/.config/<tool>/credentials
    if not cred.exists(): return None
    mode = stat(cred).mode & 0o777
    if mode & 0o077 != 0:  # any read/write for group/other
        return Finding{id="fm-secrets-perms-too-permissive",
                       severity: "P1",
                       evidence={file: cred, mode_octal: oct(mode)}}
    return None
```

### Fixer
```
fix_credential_perms(repo, ctx):
    cred = ~/.config/<tool>/credentials
    mutate(ctx, cred, Op::Chmod { mode: 0o600 })
```

### Backup spec
- The credential file (its bytes are unchanged; only the mode changes; backup captures both pre-mutation).

### Fixture
- `corrupt.sh` — create the credential file with mode 0o644.
- `assert.sh` — assert mode is 0o600.

### Online detector (gated by `--online`)
```
detect_token_expired(repo) -> Option<Finding>:
    if not args.online: return Finding{id="...", findings_only_offline: true}
    token = read(~/.config/<tool>/credentials)
    if not vendor_api.is_token_valid(token):
        return Finding{id="fm-secrets-token-expired",
                       severity: "P0",
                       evidence={vendor: ...}}
    return None
```

---

## Permissions (file modes, ownership, ACLs)

Similar to secrets but for non-credential files. Detector uses `stat`; fixer uses `Op::Chmod`. Auto-fix only when the project's documented mode is unambiguous.

---

## External artifacts (man pages, embedded data files)

### Symptoms
- Man page out of date with binary.
- Embedded data file checksum mismatch.

### Detector
```
detect_data_file_drift(repo) -> Option<Finding>:
    expected = EMBEDDED_DATA_HASH  # baked at build time
    actual = sha256(read(install_prefix/share/<tool>/data.bin))
    if expected != actual:
        return Finding{id="fm-external-artifacts-data-drift",
                       evidence={expected, actual}}
    return None
```

### Fixer
```
fix_data_file_drift(repo, ctx):
    # Reinstall the embedded data file from the binary's bundled copy.
    bundled = read(BINARY_BUNDLED_DATA)  # via include_bytes! / //go:embed / etc.
    mutate(ctx, install_prefix/share/<tool>/data.bin,
           Op::WriteFile { content: bundled, mode: 0o644 })
```

---

## Concurrency primitives

Covered as part of state_files (lockfiles) and sockets (orphaned listeners).

---

## Userland state (XDG dirs, ~/.config, OAuth tokens)

### Symptoms
- `~/.config/<tool>/` doesn't exist (first-run state).
- XDG_CONFIG_HOME set but the directory doesn't exist.
- Stale OAuth refresh token.

### Detector
```
detect_xdg_dirs(repo) -> Option<Finding>:
    config_dir = $XDG_CONFIG_HOME/<tool> or ~/.config/<tool>
    if not config_dir.exists():
        return Finding{id="fm-userland-state-config-dir-missing",
                       severity: "P3",
                       evidence={path: config_dir}}
    return None
```

### Fixer
```
fix_xdg_dirs(repo, ctx):
    # Doctor should NOT create directories it doesn't manage. Refuse and
    # emit a remediation: "run <tool> init".
    bail!("manual_remediation_required: run `<tool> init`")
```

This is the kind of FM doctor detects but doesn't auto-fix. Listing it under `manual_remediations` in `capabilities --json` makes the contract explicit.

---

## What this catalog does NOT cover

- **Network-only failure modes** (e.g., vendor API unreachable). These are `online_required: true` detectors; the doctor's offline-by-default policy means they're skipped unless `--online` is set.
- **Project-specific FMs** (e.g., `fm-projectX-foo-bar-quux`). Phase 1's archaeologist mines these per-project.
- **User-data corruption that's actually the user's fault** (e.g., the user manually edited a JSON file and broke it). Doctor detects and emits a finding; the remediation names the file:line:col but the doctor doesn't auto-fix unstructured user data.

The Phase 1 archaeologist uses this catalog as a starting point and adds project-specific FMs from cass mining + bug tracker + git log.
