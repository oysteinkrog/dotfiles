# Rust Recipe — Building `<tool> doctor`

## Crates

- `clap` (derive) — CLI surface
- `serde` + `serde_json` — JSON shapes
- `sha2` — SHA-256 hashing
- `tempfile` — atomic write via NamedTempFile + persist()
- `fs2` — advisory file locks (or `fd-lock`)
- `is-terminal` — TTY detection
- `chrono` — RFC 3339 timestamps
- `signal-hook` — SIGINT/SIGTERM handling for crash-recovery
- `anyhow` or `thiserror` — error types

`Cargo.toml`:

```toml
[dependencies]
clap = { version = "4", features = ["derive"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
sha2 = "0.10"
tempfile = "3"
fs2 = "0.4"
is-terminal = "0.4"
chrono = { version = "0.4", features = ["serde"] }
signal-hook = "0.3"
anyhow = "1"
filetime = "0.2"
```

## CLI surface (clap derive)

```rust
use clap::{Parser, Subcommand, ValueEnum};

#[derive(Parser)]
#[command(name = "<tool>", version)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Diagnose and (optionally) repair workspace state.
    Doctor {
        #[command(subcommand)]
        sub: Option<DoctorCmd>,

        /// Apply fixers for findings.
        #[arg(long)]
        fix: bool,
        /// Print the fix plan; do not execute.
        #[arg(long)]
        dry_run: bool,
        /// Scope to a subset of detectors or subsystems.
        #[arg(long, value_delimiter = ',')]
        only: Vec<String>,
        /// Inverse of --only.
        #[arg(long, value_delimiter = ',')]
        skip: Vec<String>,
        /// Diff against an earlier run.
        #[arg(long)]
        since: Option<String>,
        /// Enable network probes.
        #[arg(long)]
        online: bool,
        /// Expand a single finding.
        #[arg(long)]
        explain: Option<String>,
        /// Run only fast-path detectors (< 200ms).
        #[arg(long)]
        quick: bool,
        /// Stable JSON to stdout (implies --no-color).
        #[arg(long)]
        json: bool,
        /// Alias for --json with structured error wrapper.
        #[arg(long)]
        robot: bool,
        /// Suppress diagnostic stderr; stdout data is unchanged.
        #[arg(long)]
        quiet: bool,
        /// Mega-command: returns summary, findings, actions_planned, recommended_command, capabilities_url.
        #[arg(long)]
        robot_triage: bool,
        /// Force-disable ANSI.
        #[arg(long)]
        no_color: bool,
        /// Force-disable spinners.
        #[arg(long)]
        no_progress: bool,
        /// Verbosity. Use multiple times.
        #[arg(short, long, action = clap::ArgAction::Count)]
        verbose: u8,
        /// Override exit-4 refusal in documented cases ONLY. Requires --yes.
        #[arg(long)]
        force: bool,
        /// Skip confirmations for --force and gc.
        #[arg(long)]
        yes: bool,
    },
}

#[derive(Subcommand)]
enum DoctorCmd {
    /// Run all detectors. Read-only. (Default if no subcommand given.)
    Diagnose,
    /// Run detectors, then apply fixers. Backs up before every mutation.
    Fix,
    /// Restore from .doctor/runs/<run-id>/backups/.
    Undo {
        run_id: String,
        #[arg(long, default_value_t = true)]
        strict: bool,
    },
    /// Expand a single finding.
    Explain { finding_id: String },
    /// Print machine-readable contract.
    Capabilities,
    /// Cheap one-line liveness summary.
    Health,
    /// Paste-ready agent handbook.
    RobotDocs,
    /// Prune old runs (requires --yes + --before <date>).
    Gc {
        #[arg(long)]
        before: Option<String>,
    },
    /// List runs.
    Ls,
}
```

## The `mutate()` chokepoint (Rust)

```rust
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use sha2::{Digest, Sha256};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
pub enum Op {
    /// Create-or-overwrite the file at `path`.
    WriteFile { content: Vec<u8>, mode: u32 },
    /// Append to the file at `path`.
    AppendFile { content: Vec<u8> },
    /// Rename `path` → `to` (single-FS atomic rename).
    Rename { to: PathBuf },
    /// Set the mode of `path`.
    Chmod { mode: u32 },
    /// Execute `sql` against the project's DB inside a transaction; rolls back on error.
    DbExec { sql: String },
    /// Run a versioned migration on the project's DB; rolls back on error.
    DbMigrate { from: u32, to: u32 },
    /// Replace the symlink at `path` with one pointing at `target`, atomically.
    SymlinkAtomic { target: PathBuf },
}

#[derive(Debug, Serialize)]
pub struct ActionRecord {
    pub path: String,
    pub op: String,
    pub before_hash: String,
    pub after_hash: String,
    pub started_at_ns: u128,
    pub finished_at_ns: u128,
    pub run_id: String,
    pub fixer_id: String,
    pub ok: bool,
    /// Per-op extension. For `Op::Rename { to }` this is the destination
    /// path. `doctor undo` reads this to reverse the move. Required for
    /// renames per OUTPUT-SCHEMA.md § Per-op fields and the canonical
    /// asset template `assets/actions-jsonl-line-template.json`. Other ops
    /// leave this `None`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rename_to: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rolled_back: Option<bool>,
}

pub struct Capabilities {
    pub write_scopes: Vec<PathBuf>,
}

pub struct MutateContext {
    pub run_id: String,
    pub run_dir: PathBuf,
    pub capabilities: Capabilities,
    pub actions_file: Mutex<fs::File>,
    pub fixer_id: String,
    pub repo_root: PathBuf,
    pub dry_run: bool,
    pub start_ns: u128,
}

#[derive(Debug)]
pub struct ActionResult {
    pub ok: bool,
    pub before_hash: String,
    pub after_hash: String,
    pub error: Option<String>,
}

fn sha256_hex(bytes: &[u8]) -> String {
    let h = Sha256::digest(bytes);
    format!("sha256:{:x}", h)
}

fn read_or_empty(path: &Path) -> std::io::Result<Vec<u8>> {
    match fs::read(path) {
        Ok(b) => Ok(b),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(e) => Err(e),
    }
}

fn ensure_in_scope(caps: &Capabilities, path: &Path) -> anyhow::Result<()> {
    let canonical = canonicalize_existing_or_parent(path)?;
    for scope in &caps.write_scopes {
        let canonical_scope = canonicalize_existing_or_parent(scope)?;
        if canonical.starts_with(&canonical_scope) { return Ok(()); }
    }
    anyhow::bail!("path {} is outside write_scopes", path.display())
}

fn canonicalize_existing_or_parent(path: &Path) -> std::io::Result<PathBuf> {
    if path.exists() {
        return path.canonicalize();
    }
    let parent = path.parent().unwrap_or_else(|| Path::new(".")).canonicalize()?;
    let name = path.file_name().ok_or_else(|| {
        std::io::Error::new(std::io::ErrorKind::InvalidInput, "path has no file name")
    })?;
    Ok(parent.join(name))
}

fn copy_verbatim_with_perms(src: &Path, dst: &Path) -> std::io::Result<()> {
    if let Some(parent) = dst.parent() { fs::create_dir_all(parent)?; }
    fs::copy(src, dst)?;
    let meta = fs::metadata(src)?;
    fs::set_permissions(dst, fs::Permissions::from_mode(meta.permissions().mode()))?;
    let mtime = filetime::FileTime::from_last_modification_time(&meta);
    filetime::set_file_mtime(dst, mtime).ok();
    Ok(())
}

fn cmp_strict(a: &Path, b: &Path) -> std::io::Result<()> {
    let ba = fs::read(a)?;
    let bb = fs::read(b)?;
    if ba != bb {
        return Err(std::io::Error::new(
            std::io::ErrorKind::Other,
            "backup verify failed (cmp-strict)",
        ));
    }
    Ok(())
}

fn now_ns() -> u128 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
}

pub fn mutate(ctx: &MutateContext, path: &Path, op: Op) -> anyhow::Result<ActionResult> {
    // 1. Per-path advisory lock. The lock file lives next to the target with a
    // distinct name; we deliberately do NOT use `with_extension` because it
    // REPLACES the existing extension (so `foo.txt` → `foo.doctor-lock` would
    // collide if `foo.doctor-lock` were ever a real target).
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let basename = path.file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "_root_".to_string());
    let lock_path = parent.join(format!(".{}.doctor-lock", basename));
    fs::create_dir_all(parent)?;
    let lock_file = fs::OpenOptions::new()
        .create(true).read(true).write(true).open(&lock_path)?;
    use fs2::FileExt;
    if !lock_file.try_lock_exclusive().is_ok() {
        anyhow::bail!("lock_held");
    }

    // 2. before_hash.
    let before_bytes = read_or_empty(path)?;
    let before_hash = sha256_hex(&before_bytes);

    // 3. Preconditions.
    ensure_in_scope(&ctx.capabilities, path)?;

    // 4. Verbatim backup.
    let rel = path.strip_prefix(&ctx.repo_root).unwrap_or(path);
    let backup = ctx.run_dir.join("backups").join(rel);
    if !ctx.dry_run && path.exists() {
        copy_verbatim_with_perms(path, &backup)?;
        cmp_strict(path, &backup)?;
    }

    // 5. Plan + 6. Execute atomically.
    let started_at_ns = now_ns() - ctx.start_ns;
    if ctx.dry_run {
        eprintln!("[dry-run] would mutate {}: {:?}", path.display(), &op);
        return Ok(ActionResult {
            ok: true, before_hash: before_hash.clone(),
            after_hash: before_hash, error: None,
        });
    }
    execute_atomic(path, &op, &before_bytes)?;

    // 7. after_hash.
    let after_bytes = read_or_empty(path)?;
    let after_hash = sha256_hex(&after_bytes);
    let finished_at_ns = now_ns() - ctx.start_ns;

    // 8. Record.
    // For Rename ops, set `rename_to` to the destination so `doctor undo`
    // can reverse the move. Other ops leave `rename_to` as None.
    let rename_to = match &op {
        Op::Rename { to } => Some(to.to_string_lossy().into_owned()),
        _ => None,
    };
    let record = ActionRecord {
        path: rel.to_string_lossy().into_owned(),
        op: format!("{:?}", op).split('{').next().unwrap_or("").trim().to_string(),
        before_hash: before_hash.clone(),
        after_hash: after_hash.clone(),
        started_at_ns,
        finished_at_ns,
        run_id: ctx.run_id.clone(),
        fixer_id: ctx.fixer_id.clone(),
        ok: true, rename_to, error: None, rolled_back: None,
    };
    let line = serde_json::to_string(&record)? + "\n";
    let mut f = ctx.actions_file.lock().unwrap();
    f.write_all(line.as_bytes())?;
    f.sync_data()?;

    Ok(ActionResult { ok: true, before_hash, after_hash, error: None })
}

fn execute_atomic(path: &Path, op: &Op, _before: &[u8]) -> anyhow::Result<()> {
    use tempfile::NamedTempFile;
    let parent = path.parent().unwrap_or(Path::new("."));
    match op {
        Op::WriteFile { content, mode } => {
            let mut tmp = NamedTempFile::new_in(parent)?;
            tmp.write_all(content)?;
            tmp.as_file().sync_data()?;
            let perms = fs::Permissions::from_mode(*mode);
            fs::set_permissions(tmp.path(), perms)?;
            tmp.persist(path).map_err(|e| anyhow::anyhow!(e.error))?;
        }
        Op::AppendFile { content } => {
            let mut f = fs::OpenOptions::new().append(true).create(true).open(path)?;
            f.write_all(content)?;
            f.sync_data()?;
        }
        Op::Rename { to } => {
            if let Some(p) = to.parent() { fs::create_dir_all(p)?; }
            fs::rename(path, to)?;          // `path` is the source per the mutate() contract
        }
        Op::Chmod { mode } => {
            fs::set_permissions(path, fs::Permissions::from_mode(*mode))?;
        }
        Op::SymlinkAtomic { target } => {
            // Create a fresh symlink name, then rename atomically.
            use std::os::unix::fs::symlink;
            let tmp = path.with_file_name(format!(
                "{}.doctor-symlink-tmp.{}.{}",
                path.file_name().map(|s| s.to_string_lossy()).unwrap_or_else(|| "target".into()),
                std::process::id(),
                now_ns()
            ));
            symlink(target, &tmp)?;
            fs::rename(&tmp, path)?;
        }
        Op::DbExec { sql } => {
            // Project-specific. Wrap in a transaction; commit on success.
            todo!("wire to project's DB layer with BEGIN IMMEDIATE / COMMIT")
        }
        Op::DbMigrate { from, to } => {
            // Project-specific. Run the named migration script in a transaction.
            todo!("wire to project's migration runner")
        }
    }
    Ok(())
}
```

## Detector + Fixer pair

```rust
#[derive(Debug, Serialize)]
pub struct Finding {
    pub id: String,
    pub severity: String,   // "P0" | "P1" | "P2" | "P3"
    pub subsystem: String,
    pub title: String,
    pub evidence: serde_json::Value,
    pub remediation: Remediation,
}

#[derive(Debug, Serialize)]
pub struct Remediation {
    pub command: String,
    pub explain_command: String,
    pub auto_fixable: bool,
    pub estimated_actions: u32,
}

pub fn detect_jsonl_tombstone_drift(repo: &Path) -> anyhow::Result<Option<Finding>> {
    let jsonl = repo.join(".beads/issues.jsonl");
    let db_tombstones: Vec<String> = read_db_tombstones(&repo.join(".beads/beads.db"))?;
    let jsonl_ids: Vec<String> = read_jsonl_ids(&jsonl)?;
    let drift: Vec<&String> = db_tombstones.iter()
        .filter(|t| jsonl_ids.contains(t)).collect();
    if drift.is_empty() { return Ok(None); }
    Ok(Some(Finding {
        id: "fm-state-files-jsonl-tombstone-drift".to_string(),
        severity: "P2".to_string(),
        subsystem: "state_files".to_string(),
        title: format!("{} tombstones in DB still present in JSONL", drift.len()),
        evidence: serde_json::json!({
            "file": ".beads/issues.jsonl",
            "drifted_ids": drift,
        }),
        remediation: Remediation {
            command: "br doctor --fix --only fm-state-files-jsonl-tombstone-drift".into(),
            explain_command: "br doctor explain fm-state-files-jsonl-tombstone-drift".into(),
            auto_fixable: true,
            estimated_actions: drift.len() as u32,
        },
    }))
}

pub fn fix_jsonl_tombstone_drift(repo: &Path, ctx: &MutateContext) -> anyhow::Result<()> {
    let jsonl = repo.join(".beads/issues.jsonl");
    let db_tombstones = read_db_tombstones(&repo.join(".beads/beads.db"))?;
    let current = std::fs::read(&jsonl)?;
    let cleaned = strip_lines_with_ids(&current, &db_tombstones);
    mutate(ctx, &jsonl, Op::WriteFile { content: cleaned, mode: 0o644 })?;
    Ok(())
}

// fn read_db_tombstones(_: &Path) -> anyhow::Result<Vec<String>> { todo!() }
// fn read_jsonl_ids(_: &Path) -> anyhow::Result<Vec<String>> { todo!() }
// fn strip_lines_with_ids(_: &[u8], _: &[String]) -> Vec<u8> { todo!() }
```

## TTY / NO_COLOR detection

```rust
use is_terminal::IsTerminal;

fn use_color() -> bool {
    if std::env::var_os("NO_COLOR").is_some() { return false; }
    if std::env::var_os("CI").is_some() { return false; }
    if std::env::var("TERM").as_deref() == Ok("dumb") { return false; }
    std::io::stdout().is_terminal()
}
```

## Signal handling for crash-recovery

```rust
use signal_hook::iterator::Signals;
use signal_hook::consts::*;

fn install_signal_handlers() {
    std::thread::spawn(|| {
        let mut sigs = Signals::new(&[SIGINT, SIGTERM]).expect("signals");
        for _ in sigs.forever() {
            // Atomic writes via tempfile + rename mean the worst case is a
            // half-written .tmp.<pid> file, which the next run's recovery
            // detector will quarantine. No torn writes to the live file.
            std::process::exit(130);
        }
    });
}
```

## Common pitfalls (Rust)

- **Cross-FS `fs::rename`** is NOT atomic. `tempfile::NamedTempFile::new_in(parent)` puts the temp file in the SAME directory as the target. Always.
- **`unwrap()` / `expect()` on user paths** will panic and leave the workspace half-mutated. Use `?` with `anyhow::Error` and let the runtime convert to a `safety_block` finding.
- **`std::fs::write` does NOT fsync.** Use `tempfile + sync_data() + persist`.
- **Lock release on panic.** `fs2`'s `try_lock_exclusive` lock is released on file drop, but if the process panics mid-`mutate()`, the lock file lingers. Wrap in `Drop`-aware guards.
- **clap derive's `default_value_t`** for `bool` defaults to `false` automatically; don't set it explicitly.
