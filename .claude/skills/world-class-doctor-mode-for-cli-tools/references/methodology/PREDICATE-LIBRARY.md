# Predicate Library — Reusable Detector Building Blocks

Detectors are pure functions: state in, Finding | None out. Many detectors share predicates: "is this PID alive?", "is this path inside write_scopes?", "are these bytes valid UTF-8?". This file pins the canonical predicates the doctor's detectors should reach for.

Use as a reference when authoring detectors. Implementations match the language recipes (Rust / Go / Python / TS / Java / Bash).

---

## P-001 — `is_process_alive(pid: int) -> bool`

Used by: lockfile detectors, pidfile detectors, daemon-state detectors.

**Rust:**
```rust
fn is_process_alive(pid: u32) -> bool {
    use std::process::Command;
    Command::new("kill").args(&["-0", &pid.to_string()]).status()
        .map(|s| s.success()).unwrap_or(false)
}
```

**Go:**
```go
func isProcessAlive(pid int) bool {
    proc, err := os.FindProcess(pid)
    if err != nil { return false }
    return proc.Signal(syscall.Signal(0)) == nil
}
```

**Python:**
```python
def is_process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False
```

**TypeScript:**
```typescript
function isProcessAlive(pid: number): boolean {
    try {
        process.kill(pid, 0);
        return true;
    } catch {
        return false;
    }
}
```

**Bash:**
```bash
is_process_alive() { kill -0 "$1" 2>/dev/null; }
```

**Caveats:**
- On Linux/macOS, signal 0 only checks delivery, doesn't actually signal.
- PID reuse: a different process may have inherited the PID. Use `/proc/<pid>/cmdline` (Linux) to verify it's the expected program.
- On Windows, `kill -0` doesn't work; use `OpenProcess(PROCESS_QUERY_INFORMATION, false, pid)`.

---

## P-002 — `in_write_scope(path, scopes) -> bool`

Used by: every fixer; the `mutate()` chokepoint MUST call this.

**Rust:**
```rust
fn in_write_scope(path: &Path, scopes: &[PathBuf]) -> bool {
    let canonical = path.canonicalize().unwrap_or(path.to_path_buf());
    scopes.iter().any(|s| {
        let scope_canon = s.canonicalize().unwrap_or(s.clone());
        canonical.starts_with(&scope_canon)
    })
}
```

**Go:**
```go
func inWriteScope(path string, scopes []string) bool {
    abs, err := filepath.Abs(path)
    if err != nil { return false }
    real, err := filepath.EvalSymlinks(abs)
    if err != nil { real = abs }
    for _, s := range scopes {
        sa, _ := filepath.Abs(s)
        sr, _ := filepath.EvalSymlinks(sa)
        if sr == "" { sr = sa }
        rel, err := filepath.Rel(sr, real)
        if err == nil && !strings.HasPrefix(rel, "..") { return true }
    }
    return false
}
```

**Python:**
```python
def in_write_scope(path: Path, scopes: list[Path]) -> bool:
    canonical = path.resolve(strict=False)
    for scope in scopes:
        try:
            canonical.relative_to(scope.resolve(strict=False))
            return True
        except ValueError:
            continue
    return False
```

**Caveats:**
- MUST canonicalize (resolve symlinks) before comparing.
- A symlink in the path that escapes scope is a [SECURITY.md § Class 3](SECURITY.md) attack; this predicate is the defense.

---

## P-003 — `atomic_write(path, content, mode) -> Result`

Used by: `mutate()`'s `WriteFile` op; any direct write that needs atomicity.

**Rust:**
```rust
fn atomic_write(path: &Path, content: &[u8], mode: u32) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    use tempfile::NamedTempFile;
    let parent = path.parent().unwrap_or(Path::new("."));
    let mut tmp = NamedTempFile::new_in(parent)?;
    use std::io::Write;
    tmp.write_all(content)?;
    tmp.as_file().sync_data()?;
    std::fs::set_permissions(tmp.path(), std::fs::Permissions::from_mode(mode))?;
    tmp.persist(path).map_err(|e| e.error)?;
    Ok(())
}
```

**Go:**
```go
func atomicWrite(path string, content []byte, mode os.FileMode) error {
    parent := filepath.Dir(path)
    tmp, err := os.CreateTemp(parent, ".doctor.tmp.*")
    if err != nil { return err }
    // If a later step fails, leave the temp file for the crash-recovery detector
    // to quarantine. Do not delete it inside doctor code.
    if _, err := tmp.Write(content); err != nil { tmp.Close(); return err }
    if err := tmp.Sync(); err != nil { tmp.Close(); return err }
    if err := tmp.Close(); err != nil { return err }
    if err := os.Chmod(tmp.Name(), mode); err != nil { return err }
    return os.Rename(tmp.Name(), path)
}
```

**Python:**
```python
def atomic_write(path: Path, content: bytes, mode: int = 0o644) -> None:
    parent = path.parent
    fd, tmp = tempfile.mkstemp(prefix=".doctor.tmp.", dir=parent)
    try:
        os.write(fd, content)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.chmod(tmp, mode)
    os.replace(tmp, path)
```

**Caveats:**
- Temp MUST be in the SAME directory as target (cross-FS rename is non-atomic).
- `os.rename` (Python, < 3.3) fails if target exists on Windows; use `os.replace`.
- `fsync` before rename ensures data hits disk before metadata flip.

---

## P-004 — `cmp_strict(a, b) -> Result`

Used by: `mutate()`'s backup verification; undo's hash check.

**Rust:**
```rust
fn cmp_strict(a: &Path, b: &Path) -> std::io::Result<()> {
    let ba = std::fs::read(a)?;
    let bb = std::fs::read(b)?;
    if ba != bb {
        return Err(std::io::Error::new(std::io::ErrorKind::Other, "cmp-strict failed"));
    }
    Ok(())
}
```

**Bash:**
```bash
cmp_strict() { cmp -s "$1" "$2"; }
```

**Caveats:**
- For files > 100 MB, streaming compare (8KB chunks) is more efficient than read-all-bytes.
- `cmp -s` returns 0 on equal, 1 on different, 2 on error.

---

## P-005 — `sha256_file(path) -> hex`

Used by: every mutate() call (before/after hashes); undo verification.

**Rust:**
```rust
fn sha256_file(path: &Path) -> std::io::Result<String> {
    use sha2::{Sha256, Digest};
    let bytes = std::fs::read(path).unwrap_or_default();
    let digest = Sha256::digest(&bytes);
    Ok(format!("sha256:{:x}", digest))
}
```

**Bash:**
```bash
sha256_file() { echo "sha256:$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)"; }
```

**Caveats:**
- For empty / nonexistent files, return the empty-string hash (`sha256:e3b0c44...`) so equality checks work consistently.

---

## P-006 — `is_lock_acquirable(path) -> bool`

Used by: detectors that need to know if a lock is held without acquiring it.

**Rust:**
```rust
fn is_lock_acquirable(path: &Path) -> bool {
    use fs2::FileExt;
    let f = match std::fs::OpenOptions::new().create(true).read(true).write(true).open(path) {
        Ok(f) => f, Err(_) => return false,
    };
    if f.try_lock_exclusive().is_ok() { f.unlock().ok(); true } else { false }
}
```

**Caveats:**
- This predicate ACQUIRES then RELEASES the lock to test. Race-prone: between this check and a real `mutate()`, another process can grab the lock.
- Don't use in detectors that the runtime trusts as ground truth. Use only as a hint.

---

## P-007 — `is_valid_utf8(bytes) -> bool`

Used by: detectors checking config/JSONL files for malformed encoding.

**Rust:**
```rust
fn is_valid_utf8(bytes: &[u8]) -> bool {
    std::str::from_utf8(bytes).is_ok()
}
```

**Python:**
```python
def is_valid_utf8(bytes: bytes) -> bool:
    try:
        bytes.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False
```

---

## P-008 — `parses_as_json(bytes) -> bool`

Used by: detectors validating JSON config files.

**Python:**
```python
def parses_as_json(bytes: bytes) -> bool:
    import json
    try:
        json.loads(bytes)
        return True
    except json.JSONDecodeError:
        return False
```

**Caveats:**
- Returning bool loses the error location. For useful findings, return `Result[None, ParseError]` carrying file:line:col.

---

## P-009 — `db_integrity_ok(path) -> bool`

Used by: state_files detectors against SQLite.

**Bash:**
```bash
db_integrity_ok() {
    [ -f "$1" ] || return 1
    [ "$(sqlite3 "$1" 'PRAGMA integrity_check' 2>/dev/null)" = "ok" ]
}
```

**Caveats:**
- `PRAGMA integrity_check` is a heavy operation on large DBs; use `quick_check` in fast-path tier.
- Doesn't detect logical inconsistencies (foreign-key violations, custom invariants); just structural.

---

## P-010 — `mode_at_most(path, max_octal) -> bool`

Used by: permission detectors.

**Python:**
```python
def mode_at_most(path: Path, max_octal: int) -> bool:
    return (path.stat().st_mode & 0o777) <= max_octal
```

**Bash:**
```bash
mode_at_most() {
    local m
    m=$(stat -c '%a' "$1" 2>/dev/null) || return 1
    [ "$m" -le "$2" ]
}
```

---

## P-011 — `is_socket_responsive(path, timeout_ms) -> bool`

Used by: daemon-state detectors.

**Python:**
```python
def is_socket_responsive(path: str, timeout_ms: int = 100) -> bool:
    import socket
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout_ms / 1000.0)
    try:
        s.connect(path)
        return True
    except (OSError, ConnectionRefusedError):
        return False
    finally:
        s.close()
```

**Caveats:**
- Only checks reachability, not protocol correctness. The daemon may be partially wedged but still accepting connections.
- For higher-fidelity check, send a protocol-level health request and verify the response.

---

## P-012 — `port_holder_pid(port) -> Optional[int]`

Used by: port-conflict detectors.

**Bash:**
```bash
port_holder_pid() {
    lsof -ti tcp:"$1" 2>/dev/null | head -1
    # Or: ss -ltnp 'sport = :PORT' | awk -F'pid=' 'NR>1{print $2}' | cut -d, -f1
}
```

**Caveats:**
- Requires `lsof` or `ss` installed; document as soft-dep.
- May return multiple PIDs if the port is shared (rare for TCP); take first.

---

## P-013 — `git_branch_is_main(repo) -> bool`

Used by: `branch-env-safety` detectors.

**Bash:**
```bash
git_branch_is_main() {
    branch=$(git -C "$1" symbolic-ref --short HEAD 2>/dev/null)
    [ "$branch" = "main" ] || [ "$branch" = "master" ]
}
```

**Caveats:**
- Detached HEAD returns empty branch; treat as "not main" (refuse for safety).
- Project's "production branch" may not be `main` — make this configurable per project.

---

## P-014 — `version_in_range(actual, min, max) -> bool`

Used by: schema_version_mismatch detectors.

**Python:**
```python
def version_in_range(actual: str, min_inclusive: str, max_exclusive: str) -> bool:
    from packaging.version import parse
    return parse(min_inclusive) <= parse(actual) < parse(max_exclusive)
```

**Caveats:**
- For non-semver versions, fall back to lexicographic compare (rarely correct; document the limitation).

---

## P-015 — `path_within_repo(path, repo_root) -> bool`

Used by: detectors that operate on paths the user passed.

**Python:**
```python
def path_within_repo(path: Path, repo_root: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(repo_root.resolve(strict=False))
        return True
    except ValueError:
        return False
```

---

## How to use this library

1. When authoring a new detector, search this file FIRST for existing predicates.
2. If you write a new general-purpose predicate, add it here. Allocate the next P-NNN.
3. Tests for predicates live in `tests/predicates/<P-NNN>.test.<lang>`.
4. The predicate library is part of the doctor's shared library (`doctor-core` per [recipes/multi-binary-toolkit.md](../recipes/multi-binary-toolkit.md)) so all subsystem detectors share them.

---

## Predicates that are NOT in the library

Some predicates are intentionally NOT generalized:

- **Project-specific schema validation.** Each project's `parses_as_<their-format>` is bespoke; would couple the library to project schemas.
- **Vendor-specific health checks.** `is_cloudflare_account_active`, `is_stripe_token_valid` — these are per-tool; live in their respective recipes.
- **Project-specific "broken" predicates.** What "broken" means is project-specific by definition.

The library captures the universal kernel; project-specific predicates compose on top.

---

## Adding a predicate

When you find yourself writing the same logic in multiple detectors:

1. Allocate the next P-NNN.
2. Implement in all 5 canonical languages (Rust, Go, Python, TS, Bash).
3. Add caveats section.
4. Add a test in `tests/predicates/`.
5. Cite this file from any detector that uses it.

The library grows with the methodology. Periodic audits (per quarterly OPS-RUNBOOK) consolidate ad-hoc detectors into shared predicates.
