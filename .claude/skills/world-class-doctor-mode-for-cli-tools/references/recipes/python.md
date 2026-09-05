# Python Recipe — Building `<tool> doctor`

## Packages

- `typer` (or `click`) — CLI surface
- `pydantic` v2 — JSON schemas
- `portalocker` (or `fcntl`) — advisory file locks
- `hashlib` — SHA-256 (stdlib)
- `pathlib` — paths (stdlib)
- `signal` — SIGINT/SIGTERM (stdlib)

`pyproject.toml`:

```toml
[project.dependencies]
typer = "^0.12"
pydantic = "^2"
portalocker = "^2"
```

## CLI surface (typer)

```python
import typer
from typing import Optional, List
from enum import Enum

app = typer.Typer(name="<tool>")
doctor = typer.Typer(name="doctor", help="Diagnose and (optionally) repair workspace state.")
app.add_typer(doctor)

class Severity(str, Enum):
    P0 = "P0"; P1 = "P1"; P2 = "P2"; P3 = "P3"

@doctor.callback(invoke_without_command=True)
def doctor_default(
    ctx: typer.Context,
    fix: bool = typer.Option(False, "--fix"),
    dry_run: bool = typer.Option(False, "--dry-run"),
    only: Optional[List[str]] = typer.Option(None, "--only"),
    skip: Optional[List[str]] = typer.Option(None, "--skip"),
    since: Optional[str] = typer.Option(None, "--since"),
    online: bool = typer.Option(False, "--online"),
    explain: Optional[str] = typer.Option(None, "--explain"),
    severity: Severity = typer.Option(Severity.P3, "--severity"),
    quick: bool = typer.Option(False, "--quick"),
    json_out: bool = typer.Option(False, "--json"),
    robot: bool = typer.Option(False, "--robot"),
    quiet: bool = typer.Option(False, "--quiet"),
    robot_triage: bool = typer.Option(False, "--robot-triage"),
    no_color: bool = typer.Option(False, "--no-color"),
    no_progress: bool = typer.Option(False, "--no-progress"),
    verbose: int = typer.Option(0, "-v", count=True),
    force: bool = typer.Option(False, "--force"),
    yes: bool = typer.Option(False, "--yes"),
):
    """Default subcommand: diagnose."""
    if ctx.invoked_subcommand is None:
        diagnose(...)

@doctor.command()
def diagnose(): ...

@doctor.command()
def fix(): ...

@doctor.command()
def undo(run_id: str, strict: bool = typer.Option(True, "--strict/--no-strict")):
    """Restore from .doctor/runs/<run-id>/backups/."""
    ...

@doctor.command()
def explain(finding_id: str): ...

@doctor.command()
def capabilities():
    """Print machine-readable contract."""
    ...

@doctor.command()
def health(): ...

@doctor.command(name="robot-docs")
def robot_docs(): ...

@doctor.command()
def gc(before: Optional[str] = typer.Option(None, "--before")):
    """Prune old runs (requires --yes + --before)."""
    ...

@doctor.command()
def ls(): ...
```

## `mutate()` chokepoint

```python
from __future__ import annotations
import hashlib
import json
import os
import shutil
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Union

import portalocker


@dataclass
class Op:
    kind: str  # "WriteFile" | "AppendFile" | "Rename" | "Chmod" | "SymlinkAtomic" | "DbExec" | "DbMigrate"
    content: bytes = b""
    mode: int = 0o644
    target: Optional[Path] = None
    sql: Optional[str] = None


@dataclass
class Capabilities:
    write_scopes: list[Path]


@dataclass
class MutateContext:
    run_id: str
    run_dir: Path
    capabilities: Capabilities
    actions_file: object        # io.IOBase
    actions_lock: threading.Lock
    fixer_id: str
    repo_root: Path
    dry_run: bool
    start_ns: int


@dataclass
class ActionResult:
    ok: bool
    before_hash: str
    after_hash: str
    error: Optional[str] = None


def sha256_hex(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def read_or_empty(path: Path) -> bytes:
    return path.read_bytes() if path.exists() else b""


def ensure_in_scope(caps: Capabilities, path: Path) -> None:
    abs_path = path.resolve()
    for scope in caps.write_scopes:
        try:
            abs_path.relative_to(scope.resolve())
            return
        except ValueError:
            continue
    raise PermissionError(f"path {path} outside write_scopes")


def copy_verbatim(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)  # preserves mode + mtime


def cmp_strict(a: Path, b: Path) -> None:
    if a.read_bytes() != b.read_bytes():
        raise IOError("backup verify failed (cmp-strict)")


def mutate(ctx: MutateContext, path: Path, op: Op) -> ActionResult:
    # Lock file lives next to the target with a distinct, hidden name. We avoid
    # `path.with_suffix(...)` because `with_suffix` REPLACES the last suffix
    # (e.g., foo.txt -> foo.doctor-lock), risking collisions if .doctor-lock
    # is itself a real target. The dotted prefix also helps tools that ignore
    # dotfiles to skip these locks during recursive scans.
    lock_path = path.parent / f".{path.name}.doctor-lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock = portalocker.Lock(
        str(lock_path), mode="a+", timeout=0,                # 0 = fail fast on contention
        flags=portalocker.LOCK_EX | portalocker.LOCK_NB,
    )
    try:
        # Lock is actually acquired here, not at construction.
        lock.acquire()
    except portalocker.LockException:
        # Concurrent doctor invocation holds the lock — return graceful sentinel
        # so the caller can map this to exit code 5 (concurrency_lost).
        return ActionResult(ok=False, before_hash="", after_hash="", error="lock_held")

    try:
        before = read_or_empty(path)
        before_hash = sha256_hex(before)

        ensure_in_scope(ctx.capabilities, path)

        rel = path.relative_to(ctx.repo_root)
        backup = ctx.run_dir / "backups" / rel
        if not ctx.dry_run and path.exists():
            copy_verbatim(path, backup)
            cmp_strict(path, backup)

        started_ns = time.monotonic_ns() - ctx.start_ns
        if ctx.dry_run:
            print(f"[dry-run] would mutate {path}: {op.kind}", file=sys.stderr)
            return ActionResult(ok=True, before_hash=before_hash, after_hash=before_hash)

        execute_atomic(path, op)

        after = read_or_empty(path)
        after_hash = sha256_hex(after)
        finished_ns = time.monotonic_ns() - ctx.start_ns

        record = {
            "path": str(rel),
            "op": op.kind,
            "before_hash": before_hash,
            "after_hash": after_hash,
            "started_at_ns": started_ns,
            "finished_at_ns": finished_ns,
            "run_id": ctx.run_id,
            "fixer_id": ctx.fixer_id,
            "ok": True,
        }
        # For Rename ops, include `rename_to` so `doctor undo` can reverse
        # the move. Required per OUTPUT-SCHEMA.md § Per-op fields.
        if op.kind == "Rename":
            record["rename_to"] = str(op.target)
        line = json.dumps(record, separators=(",", ":")) + "\n"
        with ctx.actions_lock:
            ctx.actions_file.write(line)
            ctx.actions_file.flush()
            os.fsync(ctx.actions_file.fileno())

        return ActionResult(ok=True, before_hash=before_hash, after_hash=after_hash)
    finally:
        # Always release; portalocker holds it via fcntl/Win32 even if the
        # process panics. The release_held check in the caller's --robot output
        # depends on this finally running.
        lock.release()


def execute_atomic(path: Path, op: Op) -> None:
    parent = path.parent
    parent.mkdir(parents=True, exist_ok=True)
    if op.kind == "WriteFile":
        fd, tmp_str = tempfile.mkstemp(prefix=".doctor.tmp.", dir=parent)
        try:
            os.write(fd, op.content)
            os.fsync(fd)
        finally:
            os.close(fd)
        os.chmod(tmp_str, op.mode)
        os.replace(tmp_str, path)
    elif op.kind == "AppendFile":
        with open(path, "ab") as f:
            f.write(op.content)
            f.flush()
            os.fsync(f.fileno())
    elif op.kind == "Rename":
        op.target.parent.mkdir(parents=True, exist_ok=True)
        os.replace(path, op.target)
    elif op.kind == "Chmod":
        os.chmod(path, op.mode)
    elif op.kind == "SymlinkAtomic":
        tmp = path.parent / f".{path.name}.doctor-symlink-tmp.{os.getpid()}.{time.time_ns()}"
        os.symlink(op.target, tmp)
        os.replace(tmp, path)
    else:
        raise ValueError(f"unknown op {op.kind}")
```

## Detector + Fixer pair

```python
from pydantic import BaseModel, Field

class Remediation(BaseModel):
    command: str
    explain_command: str
    auto_fixable: bool
    estimated_actions: int

class Finding(BaseModel):
    id: str
    severity: str
    subsystem: str
    title: str
    evidence: dict
    remediation: Remediation


def detect_stale_pid_file(repo: Path) -> Optional[Finding]:
    pid_path = repo / ".tinycli" / "tinycli.pid"
    if not pid_path.exists():
        return None
    pid = int(pid_path.read_text().strip())
    if process_alive(pid):
        return None
    return Finding(
        id="fm-concurrency-primitives-stale-pid-file",
        severity="P1",
        subsystem="concurrency_primitives",
        title=f"Stale pidfile from PID {pid} (not alive)",
        evidence={"file": str(pid_path), "pid": pid},
        remediation=Remediation(
            command="<tool> doctor --fix --only fm-concurrency-primitives-stale-pid-file",
            explain_command="<tool> doctor explain fm-concurrency-primitives-stale-pid-file",
            auto_fixable=True,
            estimated_actions=1,
        ),
    )


def fix_stale_pid_file(repo: Path, ctx: MutateContext) -> None:
    pid_path = repo / ".tinycli" / "tinycli.pid"
    quarantine = ctx.run_dir / "quarantine" / "pids" / pid_path.name
    mutate(ctx, pid_path, Op(kind="Rename", target=quarantine))


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False
```

## TTY / NO_COLOR detection

```python
def use_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("CI"):
        return False
    if os.environ.get("TERM") == "dumb":
        return False
    return sys.stdout.isatty()
```

## Signal handling

```python
import signal

def install_signal_handlers():
    def handler(signum, frame):
        # Atomic os.replace means the worst case is a half-written
        # .doctor.tmp.* in the parent dir; next run's recovery quarantines.
        sys.exit(130)
    signal.signal(signal.SIGINT, handler)
    signal.signal(signal.SIGTERM, handler)
```

## Common pitfalls (Python)

- **`os.rename` ≠ `os.replace`.** On Windows, `os.rename` fails if target exists; `os.replace` doesn't. Use `os.replace` everywhere.
- **`shutil.copy` does NOT preserve mtime.** Use `shutil.copy2`.
- **`open(..., "w")` truncates immediately.** Use `tempfile.mkstemp` + `os.replace` for atomicity.
- **`pickle`** is forbidden in the doctor module — never use it for state. JSON only.
- **`portalocker.Lock(..., flags=...)` without timeout** blocks indefinitely. Always set `timeout` and handle `LockException`.
- **`pathlib.Path.read_text()`** decodes UTF-8; use `read_bytes()` for byte-identical comparisons.
- **`pydantic` v2 strict mode** rejects extra fields by default; opt in to `model_config = ConfigDict(extra="forbid")` for capabilities/report schemas to catch drift.
