# The `mutate()` Chokepoint

> **Single rule.** Every disk write performed by `<tool> doctor --fix` flows through ONE function: `mutate(path, op) -> ActionResult`. No exceptions. No "this one is small." No "this is just appending." No "this is just a chmod." The validator (`scripts/validate-doctor.sh`) fails CI if any other code path writes under `--fix`.

This is the load-bearing invariant of the entire skill. Get this right and reversibility, idempotence, observability, and crash-recovery come almost for free. Get this wrong and you cannot prove anything about the doctor.

---

## What `mutate()` does (in order)

1. **Acquire the per-path lock** (advisory; project's existing lock primitive if any).
2. **Compute `before_hash`** — SHA-256 of the file's bytes (or the empty hash for "did not exist").
3. **Validate preconditions** — the path is inside `capabilities.write_scopes`; the op is in `capabilities.allowed_ops`; the per-fixer preconditions list passes.
4. **Write the verbatim backup** — copy the file as-was to `<run-dir>/backups/<rel-path>` (preserve mtime + permissions). For DB rows, the backup is a `pg_dump` / `sqlite3 .dump` of the affected rows. Verify the backup with `cmp -s` against the live file before proceeding.
5. **Plan the mutation** — produce the new bytes (or the schema migration, or the row update) entirely in memory.
6. **Execute atomically** — write-tmp-then-rename for files; transaction with rollback for DB; appropriate atomic primitive for the FS layer.
7. **Compute `after_hash`** — SHA-256 of the post-state bytes.
8. **Append to `actions.jsonl`** — one line `{path, op, before_hash, after_hash, started_at_ns, finished_at_ns, run_id, fixer_id, ok: bool}`.
9. **Release the lock**.
10. **Return** `ActionResult { ok, before_hash, after_hash, error: Option<...> }`.

If any step 3–6 fails, no backup is needed, no `actions.jsonl` line is written, and no lock state changes — the system is unchanged. If steps 7–8 fail (extraordinarily rare), restore from backup.

---

## The `op` enum

```
enum Op {
    WriteFile { content: Vec<u8>, mode: Permissions },     // create-or-overwrite
    AppendFile { content: Vec<u8> },                        // append-only
    Rename { to: PathBuf },                                 // path is the source; single-FS atomic rename
    Chmod { mode: Permissions },                            // metadata-only mutation
    DbExec { sql: String, args: Vec<Value> },               // single transaction; rolls back on error
    DbMigrate { from: u32, to: u32 },                       // versioned migration; rolls back on error
    SymlinkAtomic { target: PathBuf },                      // for `.doctor/latest`
}
```

The seven canonical variants are `WriteFile`, `AppendFile`, `Rename`, `Chmod`, `DbExec`, `DbMigrate`, `SymlinkAtomic`. All five language recipes (Rust, Go, Python, TypeScript, JVM) implement exactly these seven.

**Optional `Chown { uid: u32, gid: u32 }`** — historically listed for completeness but no recipe implements it and no asset template uses it. Add it lazily if your project has a real ownership-fixing fixer (rare — typically only matters for installer-pattern doctors that touch system files; see [`recipes/installer.md`](../recipes/installer.md)). When added, follow OUTPUT-SCHEMA.md § Per-op fields and include the previous owner in the `before_hash` (or a separate `before_owner` field) so undo can restore.

`DeletePath` is **forbidden** under AGENTS.md "no file deletion." If a fixer thinks it needs to delete, it actually wants `mutate(ctx, &offending_path, Op::Rename { to: <run-dir>/quarantine/<rel-path> })`. The user can review and remove the quarantined file later — that decision is theirs, not the doctor's.

---

## Reference implementations (sketches)

These are sketches showing the *shape* of `mutate()` in each language. **They are not compilable as-is** — they reference an abstract `LockManager` and `Capabilities` type that you'll wire to your project's existing primitives. For copy-paste-ready code with concrete locking primitives (`fs2`, `syscall.Flock`, `portalocker`, `proper-lockfile`), see the per-language recipes:

- Rust → [../recipes/rust.md](../recipes/rust.md)
- Go → [../recipes/go.md](../recipes/go.md)
- Python → [../recipes/python.md](../recipes/python.md)
- TypeScript / Bun / Deno → [../recipes/typescript.md](../recipes/typescript.md)
- Ruby / C / C++ / Zig / Elixir / Bash → [../recipes/other-languages.md](../recipes/other-languages.md)

The skeletons below all share the same 8-step shape (lock → before_hash → preconditions → backup → plan → execute atomically → after_hash → record).

### Rust skeleton

This is a sketch, not the implementation. The actual code lives in the target repo, in its idioms.

```rust
pub struct MutateContext<'a> {
    pub run_id: &'a str,
    pub run_dir: &'a Path,
    pub capabilities: &'a Capabilities,
    pub actions_file: Mutex<File>,        // .doctor/runs/<run-id>/actions.jsonl
    pub fixer_id: &'a str,
    pub repo_root: &'a Path,
    pub locks: &'a LockManager,
    pub dry_run: bool,
    pub start: std::time::Instant,        // captured at run start
}

pub struct ActionResult {
    pub ok: bool,
    pub before_hash: [u8; 32],
    pub after_hash: [u8; 32],
    pub error: Option<String>,
}

pub fn mutate(ctx: &MutateContext, path: &Path, op: Op) -> Result<ActionResult> {
    // 1. Per-path advisory lock.
    let _guard = ctx.locks.acquire(path)?;

    // 2. before_hash.
    let before_bytes = read_or_empty(path)?;
    let before_hash = sha256(&before_bytes);

    // 3. Preconditions.
    ensure_in_scope(ctx.capabilities, path)?;
    ensure_op_allowed(ctx.capabilities, &op)?;

    // 4. Verbatim backup.
    let rel = path.strip_prefix(ctx.repo_root)?;
    let backup = ctx.run_dir.join("backups").join(rel);
    if !ctx.dry_run {
        copy_verbatim_with_perms(path, &backup)?;
        cmp_files_strict(path, &backup)?;  // refuse if not byte-identical
    }

    // 5. Plan in memory (op-specific).
    let plan = plan_op(path, &op, &before_bytes)?;

    // 6. Execute atomically.
    if ctx.dry_run {
        // Print to stderr, don't touch disk.
        eprintln!("[dry-run] would mutate {}: {}", path.display(), describe(&op));
        return Ok(ActionResult { ok: true, before_hash, after_hash: before_hash, error: None });
    }
    execute_atomic(&plan)?;  // write-tmp-then-rename; transaction; etc.

    // 7. after_hash.
    let after_bytes = read_or_empty(path)?;
    let after_hash = sha256(&after_bytes);

    // 8. Record.
    let line = serde_json::to_string(&ActionRecord {
        path: rel.to_owned(),
        op: describe_op(&op),
        before_hash: hex(before_hash),
        after_hash: hex(after_hash),
        started_at_ns: ctx.start.elapsed().as_nanos() as u64,
        finished_at_ns: now_ns(),
        run_id: ctx.run_id.to_owned(),
        fixer_id: ctx.fixer_id.to_owned(),
        ok: true,
    })? + "\n";
    let mut f = ctx.actions_file.lock();
    f.write_all(line.as_bytes())?;
    f.sync_data()?;
    drop(f);

    Ok(ActionResult { ok: true, before_hash, after_hash, error: None })
}
```

---

## Reference Go implementation (skeleton)

```go
type MutateContext struct {
    RunID         string
    RunDir        string
    Capabilities  *Capabilities
    ActionsFile   *os.File
    actionsMu     sync.Mutex
    FixerID       string
    RepoRoot      string
    Locks         *LockManager
    DryRun        bool
}

type ActionResult struct {
    OK         bool
    BeforeHash [32]byte
    AfterHash  [32]byte
    Err        error
}

func Mutate(ctx *MutateContext, path string, op Op) (ActionResult, error) {
    guard, err := ctx.Locks.Acquire(path)
    if err != nil {
        return ActionResult{}, err
    }
    defer guard.Release()

    beforeBytes, err := readOrEmpty(path)
    if err != nil { return ActionResult{}, err }
    beforeHash := sha256.Sum256(beforeBytes)

    if err := ensureInScope(ctx.Capabilities, path); err != nil { return ActionResult{}, err }
    if err := ensureOpAllowed(ctx.Capabilities, op); err != nil { return ActionResult{}, err }

    rel, _ := filepath.Rel(ctx.RepoRoot, path)
    backup := filepath.Join(ctx.RunDir, "backups", rel)

    if !ctx.DryRun {
        if err := copyVerbatim(path, backup); err != nil { return ActionResult{}, err }
        if err := cmpStrict(path, backup); err != nil { return ActionResult{}, err }
    }

    plan, err := planOp(path, op, beforeBytes)
    if err != nil { return ActionResult{}, err }

    if ctx.DryRun {
        fmt.Fprintf(os.Stderr, "[dry-run] would mutate %s: %s\n", path, describe(op))
        return ActionResult{OK: true, BeforeHash: beforeHash, AfterHash: beforeHash}, nil
    }

    if err := executeAtomic(plan); err != nil { return ActionResult{}, err }

    afterBytes, err := readOrEmpty(path)
    if err != nil { return ActionResult{}, err }
    afterHash := sha256.Sum256(afterBytes)

    record := ActionRecord{
        Path:         rel,
        Op:           describeOp(op),
        BeforeHash:   hex.EncodeToString(beforeHash[:]),
        AfterHash:    hex.EncodeToString(afterHash[:]),
        StartedAtNS:  uint64(time.Since(ctx.start).Nanoseconds()),
        FinishedAtNS: uint64(time.Now().UnixNano()),
        RunID:        ctx.RunID,
        FixerID:      ctx.FixerID,
        OK:           true,
    }
    line, _ := json.Marshal(record)
    line = append(line, '\n')

    ctx.actionsMu.Lock()
    defer ctx.actionsMu.Unlock()
    if _, err := ctx.ActionsFile.Write(line); err != nil { return ActionResult{}, err }
    if err := ctx.ActionsFile.Sync(); err != nil { return ActionResult{}, err }

    return ActionResult{OK: true, BeforeHash: beforeHash, AfterHash: afterHash}, nil
}
```

---

## Reference Python implementation (skeleton)

```python
@dataclass
class MutateContext:
    run_id: str
    run_dir: Path
    capabilities: Capabilities
    actions_file: TextIO
    actions_lock: threading.Lock
    fixer_id: str
    repo_root: Path
    locks: LockManager
    dry_run: bool

@dataclass
class ActionResult:
    ok: bool
    before_hash: str
    after_hash: str
    error: Optional[str] = None

def mutate(ctx: MutateContext, path: Path, op: Op) -> ActionResult:
    with ctx.locks.acquire(path):
        before_bytes = path.read_bytes() if path.exists() else b""
        before_hash = hashlib.sha256(before_bytes).hexdigest()

        ensure_in_scope(ctx.capabilities, path)
        ensure_op_allowed(ctx.capabilities, op)

        rel = path.relative_to(ctx.repo_root)
        backup = ctx.run_dir / "backups" / rel
        backup.parent.mkdir(parents=True, exist_ok=True)

        if not ctx.dry_run and path.exists():
            shutil.copy2(path, backup)              # preserves mtime + permissions
            assert filecmp.cmp(path, backup, shallow=False), "backup verify failed"

        plan = plan_op(path, op, before_bytes)
        if ctx.dry_run:
            print(f"[dry-run] would mutate {path}: {describe(op)}", file=sys.stderr)
            return ActionResult(ok=True, before_hash=before_hash, after_hash=before_hash)

        execute_atomic(plan)

        after_bytes = path.read_bytes() if path.exists() else b""
        after_hash = hashlib.sha256(after_bytes).hexdigest()

        record = {
            "path": str(rel),
            "op": describe_op(op),
            "before_hash": before_hash,
            "after_hash": after_hash,
            "started_at_ns": (time.monotonic_ns() - ctx.start_ns),
            "finished_at_ns": time.monotonic_ns(),
            "run_id": ctx.run_id,
            "fixer_id": ctx.fixer_id,
            "ok": True,
        }
        line = json.dumps(record, separators=(",", ":")) + "\n"
        with ctx.actions_lock:
            ctx.actions_file.write(line)
            ctx.actions_file.flush()
            os.fsync(ctx.actions_file.fileno())

    return ActionResult(ok=True, before_hash=before_hash, after_hash=after_hash)
```

---

## Reference TypeScript / Bun / Deno implementation (skeleton)

```typescript
interface MutateContext {
    runId: string;
    runDir: string;
    capabilities: Capabilities;
    actionsFile: number;          // file descriptor
    actionsLock: AsyncMutex;
    fixerId: string;
    repoRoot: string;
    locks: LockManager;
    dryRun: boolean;
    startNs: bigint;
}

interface ActionResult {
    ok: boolean;
    beforeHash: string;
    afterHash: string;
    error?: string;
}

export async function mutate(ctx: MutateContext, path: string, op: Op): Promise<ActionResult> {
    using guard = await ctx.locks.acquire(path);

    const beforeBytes = await readOrEmpty(path);
    const beforeHash = sha256Hex(beforeBytes);

    ensureInScope(ctx.capabilities, path);
    ensureOpAllowed(ctx.capabilities, op);

    const rel = relPath(ctx.repoRoot, path);
    const backup = joinPath(ctx.runDir, "backups", rel);
    await mkdirp(dirname(backup));

    if (!ctx.dryRun && (await exists(path))) {
        await copyVerbatim(path, backup);
        await cmpStrict(path, backup);
    }

    const plan = planOp(path, op, beforeBytes);
    if (ctx.dryRun) {
        process.stderr.write(`[dry-run] would mutate ${path}: ${describe(op)}\n`);
        return { ok: true, beforeHash, afterHash: beforeHash };
    }

    await executeAtomic(plan);

    const afterBytes = await readOrEmpty(path);
    const afterHash = sha256Hex(afterBytes);

    const record = {
        path: rel,
        op: describeOp(op),
        before_hash: beforeHash,
        after_hash: afterHash,
        started_at_ns: Number(process.hrtime.bigint() - ctx.startNs),
        finished_at_ns: Date.now() * 1_000_000,
        run_id: ctx.runId,
        fixer_id: ctx.fixerId,
        ok: true,
    };
    const line = JSON.stringify(record) + "\n";

    await ctx.actionsLock.runExclusive(async () => {
        await fs.write(ctx.actionsFile, line);
        await fs.fsync(ctx.actionsFile);
    });

    return { ok: true, beforeHash, afterHash };
}
```

---

## Atomicity primitives by language

| Language | File-write atomicity |
|----------|----------------------|
| Rust | `tempfile::NamedTempFile` + `persist()` (uses `rename(2)`) |
| Go | `os.CreateTemp(dir, ...)` + `os.Rename` |
| Python | `tempfile.NamedTemporaryFile(dir=..., delete=False)` + `os.replace()` (NOT `os.rename`) |
| Node/TS | `fs.writeFileSync(tmp, ...)` + `fs.renameSync(tmp, target)` (Linux) / `fs.renameSync` after closing (Windows) |
| Bun | `Bun.write(tmp, ...)` + `fs.renameSync` |
| Deno | `Deno.writeFileSync(tmp, ...)` + `Deno.renameSync` |
| Ruby | `Tempfile.create(dir: ...)` + `File.rename` |
| C/C++ | `mkostemp` + `fdatasync` + `rename` |
| Zig | `std.fs.cwd().createFile(tmp, .{})` + `std.fs.cwd().rename(tmp, target)` |
| Elixir | `File.write!(tmp, ...)` + `File.rename!(tmp, target)` |
| Bash | `mktemp -p $(dirname target) ...` + `mv` |

**Cross-FS rename is NOT atomic.** The temp file MUST live in the same directory as the target so the kernel's `rename(2)` is just a directory entry swap. If the temp file is on `/tmp` and the target is on `/home`, you've broken atomicity.

For DB writes, atomicity comes from the transaction. Wrap the SQL in `BEGIN IMMEDIATE; ... COMMIT;` (SQLite) or `BEGIN; ... COMMIT;` (PostgreSQL) and rollback on any error inside `mutate()`.

---

## The validator (`scripts/validate-doctor.sh`)

```bash
#!/usr/bin/env bash
# Fail if any code path writes under doctor --fix that doesn't go through mutate().

set -euo pipefail
target=$1

# 1. Find every file that's part of the doctor subsystem.
doctor_files=$(rg -l --type=$(detect_lang $target) -e 'fn doctor|sub doctor|"doctor"' "$target/src" "$target/cmd" || true)

# 2. For each, find writes that DON'T pass through mutate().
forbidden=(
    'std::fs::write\b'
    'std::fs::remove'
    'fs.writeFileSync'
    'fs.unlink'
    'fs.unlinkSync'
    'os.WriteFile'
    'os.Remove'
    '\.unlink\('
    'File.rm'
    'open\(.*"w"\)'                # Python file write
    'shutil.copy[^v]'               # Python (allow only copy_verbatim wrapper)
    'rm -[a-zA-Z]*r'                # rm -rf in shellouts
    'git reset --hard'
    'git clean -[a-zA-Z]*f'
    'DROP TABLE'
    'kubectl delete'
)

violations=0
for file in $doctor_files; do
    for pat in "${forbidden[@]}"; do
        if rg -q -e "$pat" "$file"; then
            # OK if the line is inside mutate() definition itself.
            if ! rg -q -B 30 "fn mutate|func Mutate|def mutate|export.*function mutate" "$file"; then
                echo "VIOLATION: $file matches forbidden pattern: $pat" >&2
                violations=$((violations + 1))
            fi
        fi
    done
done

[ $violations -eq 0 ]
```

The actual implementation lives at `scripts/validate-doctor.sh`. This is a sketch.
