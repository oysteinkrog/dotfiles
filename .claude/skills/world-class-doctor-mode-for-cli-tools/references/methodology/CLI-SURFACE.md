# CLI Surface — Verbatim Help, Flags, JSON Shapes

This file pins the EXACT spelling, flag set, exit codes, JSON schemas, and `--help` text for the doctor surface. Implementations in any language must match this contract. The `agent_intuitiveness` and `agent_ergonomics` dimensions in the rubric assume this surface.

---

## Top-level invocation

```text
<tool> doctor [SUBCOMMAND] [OPTIONS]
```

If no SUBCOMMAND is given, the default subcommand is `diagnose` (read-only, no mutations).

## Subcommands

| Subcommand | Purpose | Mutates? | Default exit semantics |
|------------|---------|----------|------------------------|
| `diagnose` (default) | Run all detectors. Print findings. | NO | 0 healthy, 1 findings, 4 unsafe-refused |
| `fix` | Run detectors, then run fixers for each finding (alias: bare `--fix` flag on diagnose) | YES (via `mutate()`) | 0 all fixed, 2 partial, 3 failed and rolled back, 4 unsafe-refused |
| `undo <run-id>` | Restore from `.doctor/runs/<run-id>/backups/`. `<run-id>` may be `latest`. | YES (restore-only; no new mutations beyond restore) | 0 restored, 3 restore failed |
| `explain <finding-id>` | Expand a single finding with full evidence and the exact remediation command. | NO | 0 |
| `capabilities` | Print machine-readable contract: detectors, fixers, exit codes, env vars, run-artifact schema. | NO | 0 |
| `health` | Cheap liveness summary. One line stdout + exit code. | NO | 0 healthy, 1 anything else |
| `robot-docs` | Paste-ready agent handbook. | NO | 0 |
| `gc [--before <date>]` | Prune old `.doctor/runs/<run-id>/` directories (and their `backups/` subdirs) whose `started_at` is before `<date>`. **Requires `--yes` and explicit `--before` — never deletes silently.** Per [KERNEL § Axiom 3](KERNEL.md), only `undo` and `gc` may delete; gc is gated on user-confirmed cutoff so the user explicitly accepts loss of undo capability for those runs. | YES (run-dir + backup deletion, gated by `--yes` + `--before`) | 0 |
| `ls` | List `.doctor/runs/` with `{run_id, started_at, exit_code, action_count}`. | NO | 0 |
| `diff [<ref>]` | Compute what `--fix` WOULD change against current state (or against an earlier run-id if `<ref>` is given). Output is a unified diff (text mode) or a JSON action list (`--json`). **Read-only.** Equivalent to `--dry-run --fix` but agent-ergonomic. | NO | 0 (clean diff or empty diff), 4 (refused-unsafe) |

## Flags

Universal flags (apply to every subcommand):

| Flag | Type | Default | Purpose |
|------|------|---------|---------|
| `--json` | bool | false | Stable JSON to stdout. Implies `--no-color`, `--no-progress`. |
| `--robot` | bool | false | Alias for `--json` plus structured error wrapper. |
| `--quiet` | bool | false | Suppress diagnostic stderr; data still goes to stdout. |
| `--verbose` / `-v` | bool, repeatable | 0 | Increase stderr verbosity (`-v` info, `-vv` debug, `-vvv` trace). |
| `--no-color` | bool | auto-detect | Force-disable ANSI. Honored by `NO_COLOR` env, `TERM=dumb`, non-TTY. |
| `--no-progress` | bool | auto-detect | Force-disable spinners. Honored on non-TTY. |

Flags for `diagnose` (and the default invocation):

| Flag | Type | Default | Purpose |
|------|------|---------|---------|
| `--fix` | bool | false | Apply fixers for findings. Routes through `mutate()`. |
| `--dry-run` | bool | false | (with `--fix`) Print the plan, do NOT execute. |
| `--only=<id1,id2,...>` | list of detector or subsystem ids | all | Scope to a subset. |
| `--skip=<id1,id2,...>` | list | none | Inverse of `--only`. |
| `--since=<run-id>` | string | none | Diff findings against an earlier run. |
| `--online` | bool | false | Enable network probes (DNS, TLS, vendor APIs). Default: offline-only. |
| `--explain <finding-id>` | string | none | Expand a single finding (alternative to the `explain` subcommand). |
| `--severity=<P0\|P1\|P2\|P3>` | string | P3 | Minimum severity to emit. |
| `--budget=<duration>` | string | none | Refuse to start if remaining budget < est. cost (e.g. `--budget=5s`). |
| `--quick` | bool | false | Run only the fast-path detectors (< 200ms total). For pre-commit hooks. |
| `--force` | bool | false | Override exit-4 refusal in specific, documented cases ONLY. Requires `--yes`. |
| `--yes` | bool | false | Skip the confirmation prompt for `--force` and `gc`. |

Flags for `undo`:

| Flag | Type | Default | Purpose |
|------|------|---------|---------|
| `--dry-run` | bool | false | Print the restore plan, do NOT execute. |
| `--strict` | bool | true | Refuse if any backup is missing or hash-mismatched. (Use `--no-strict` to attempt best-effort restore — strongly discouraged.) |

---

## Exit codes (universal)

| Code | Name | Meaning |
|------|------|---------|
| `0` | `success_or_healthy` | `diagnose`: workspace healthy. `fix`: all findings fixed. `undo`: restore complete. |
| `1` | `findings_present_no_fix` | `diagnose` (no `--fix`): findings exist; `--fix` is the recommended next step. |
| `2` | `fix_partial` | `fix`: some findings fixed, some not. See `report.json::partial_failures`. |
| `3` | `fix_failed_rolled_back` | `fix`: at least one mutation failed; rolled back via `mutate()`'s undo path. |
| `4` | `refused_unsafe` | `diagnose` or `fix` refused to act because the state is unsafe (schema mismatch, no permission, out-of-scope write, non-lock precondition failure, etc.). The finding tells you which. |
| `5` | `concurrency_lost` | A concurrent doctor invocation won the lock; this one refused. |
| `6` | `online_required` | `--online` required for at least one finding; doctor exited rather than emit incomplete results. |
| `64` | `usage_error` | Unknown flag, missing argument, etc. (POSIX `EX_USAGE`). |
| `66` | `no_input` | Target path doesn't exist or isn't a recognized project. |
| `73` | `cant_create` | Couldn't create `.doctor/runs/<run-id>/`; backups directory unwritable. |
| `74` | `io_error` | Filesystem I/O error during read or non-mutating write (e.g., writing report.json). |

Documented in `<tool> doctor capabilities --json` under `exit_codes`.

---

## `--help` text (verbatim — auto-disable color when stdout isn't a TTY)

```text
<tool> doctor — diagnose and (with --fix) repair workspace state.

USAGE
    <tool> doctor [SUBCOMMAND] [OPTIONS]

SUBCOMMANDS
    diagnose             Run all detectors (default). Read-only.
    fix                  Run detectors, then apply fixers. Backs up before every mutation.
    undo <run-id>        Restore from .doctor/runs/<run-id>/backups/.
    explain <finding-id> Expand a single finding with full evidence.
    capabilities         Print machine-readable contract (JSON).
    health               Cheap one-line liveness summary.
    robot-docs           Paste-ready agent handbook (Markdown).
    gc                   Prune old runs (requires --yes + --before <date>).
    ls                   List runs in .doctor/runs/.
    diff [<ref>]          Show what --fix would change. Read-only.

COMMON FLAGS
    --json               Stable JSON to stdout (implies --no-color).
    --robot              Alias for --json with structured error wrapper.
    --quiet              Suppress diagnostic stderr; stdout data unchanged.
    --fix                (diagnose) Apply fixers for findings.
    --dry-run --fix      Print the fix plan; do not execute.
    --only <id,...>      Scope to a subset of detectors or subsystems.
    --since <run-id>     Diff against an earlier run.
    --online             Enable network probes. Default: offline-only.
    --quick              Run only fast-path detectors (< 200 ms). For pre-commit.
    --explain <id>       Same as the `explain` subcommand.
    -v, -vv, -vvv        Increase stderr verbosity.
    --no-color           Force-disable ANSI (also honors NO_COLOR).

EXIT CODES
    0  healthy / fix complete / undo complete
    1  findings present (no --fix)
    2  fix partial
    3  fix failed and rolled back
    4  refused (unsafe state — see finding)
    5  concurrency: another doctor holds the lock
    6  --online required for at least one finding
    64 usage error

EXAMPLES
    # Find issues; print human-readable report.
    <tool> doctor

    # Find issues; emit JSON for an agent.
    <tool> doctor --json | jq

    # Plan a fix, but don't execute.
    <tool> doctor --dry-run --fix

    # Apply fixes; back up everything; emit run-id.
    <tool> doctor --fix

    # Restore from the most recent fix run.
    <tool> doctor undo latest

    # Cheap liveness check (for CI).
    <tool> doctor health

    # Print the agent handbook.
    <tool> doctor robot-docs

LEARN MORE
    <tool> doctor capabilities --json
    <tool> doctor robot-docs
```

---

## JSON shapes

All JSON outputs include a stable top-level field `schema_version`. Bumps follow semver: minor for additive fields, major for renamed/removed/typed fields.

### `diagnose --json` (default)

```jsonc
{
  "schema_version": "1.0",
  "tool": "br",
  "tool_version": "0.4.7",
  "doctor_version": "1.0.0",
  "run_id": "2026-05-06T14-23-07Z__a3f9b2",
  "run_dir": ".doctor/runs/2026-05-06T14-23-07Z__a3f9b2",
  "started_at": "2026-05-06T14:23:07Z",
  "finished_at": "2026-05-06T14:23:07.412Z",
  "duration_ms": 412,
  "target_sha": "deadbeef...",
  "ok": false,
  "summary": {
    "total_findings": 3,
    "by_severity": { "P0": 1, "P1": 0, "P2": 2, "P3": 0 },
    "auto_fixable": 3,
    "online_required": 0
  },
  "findings": [
    {
      "id": "fm-jsonl-tombstone-drift",
      "severity": "P2",
      "subsystem": "state_files",
      "title": "Two issues marked tombstoned in DB but still present in issues.jsonl",
      "confidence": 1.0,
      "evidence": {
        "file": ".beads/issues.jsonl",
        "lines": [142, 187],
        "query": "select issue_id from tombstones",
        "hash": "sha256:..."
      },
      "remediation": {
        "command": "br doctor --fix --only fm-jsonl-tombstone-drift",
        "explain_command": "br doctor explain fm-jsonl-tombstone-drift",
        "auto_fixable": true,
        "estimated_actions": 2
      }
    }
  ],
  "exit_code": 1,
  "next_steps": [
    "Run: br doctor --fix",
    "Or scope: br doctor --fix --only fm-jsonl-tombstone-drift",
    "Inspect: br doctor explain fm-jsonl-tombstone-drift"
  ]
}
```

### `fix --json`

Adds `actions` and partial-failure data.

```jsonc
{
  "schema_version": "1.0",
  "tool": "br",
  "run_id": "2026-05-06T14-23-07Z__a3f9b2",
  "run_dir": ".doctor/runs/2026-05-06T14-23-07Z__a3f9b2",
  "started_at": "...",
  "finished_at": "...",
  "duration_ms": 1247,
  "ok": true,
  "summary": {
    "findings_before": 3,
    "findings_after": 0,
    "actions_taken": 5,
    "bytes_backed_up": 18293
  },
  "actions_jsonl_path": ".doctor/runs/2026-05-06T14-23-07Z__a3f9b2/actions.jsonl",
  "backups_dir": ".doctor/runs/2026-05-06T14-23-07Z__a3f9b2/backups",
  "undo_command": "br doctor undo 2026-05-06T14-23-07Z__a3f9b2",
  "exit_code": 0
}
```

### `capabilities --json`

```jsonc
{
  "schema_version": "1.0",
  "tool": "br",
  "tool_version": "0.4.7",
  "doctor_version": "1.0.0",
  "doctor_contract_version": "1.0",
  "platform": { "os": "linux", "arch": "x86_64" },
  "subsystems": ["state_files", "configs", "schemas", "caches", "concurrency_primitives", "userland_state"],
  "detectors": [
    {
      "id": "fm-jsonl-tombstone-drift",
      "subsystem": "state_files",
      "severity": "P2",
      "description": "Issues tombstoned in DB still present in JSONL",
      "estimated_cost_ms": 30,
      "online_required": false
    }
  ],
  "fixers": [
    {
      "id": "fm-jsonl-tombstone-drift",
      "preconditions": ["lock_acquired", "backup_dir_writable", "issues_jsonl_present"],
      "writes_to": [".beads/issues.jsonl"],
      "ops": ["WriteFile"],
      "reversible": true,
      "idempotent": true,
      "estimated_cost_ms": 50
    }
  ],
  "manual_remediations": [
    {
      "id": "fm-network-anthropic-api-key-missing",
      "instruction": "Set ANTHROPIC_API_KEY in your environment, then re-run `<tool> doctor`.",
      "reason": "Doctor cannot generate API keys. User action required."
    }
  ],
  "exit_codes": {
    "0": "success_or_healthy",
    "1": "findings_present_no_fix",
    "2": "fix_partial",
    "3": "fix_failed_rolled_back",
    "4": "refused_unsafe",
    "5": "concurrency_lost",
    "6": "online_required",
    "64": "usage_error",
    "66": "no_input",
    "73": "cant_create",
    "74": "io_error"
  },
  "env_vars": {
    "BR_DOCTOR_LOG_LEVEL": "trace|debug|info|warn|error",
    "BR_DOCTOR_BACKUPS_DIR": "override the default .doctor/ location",
    "NO_COLOR": "disable ANSI"
  },
  "write_scopes": [".beads", ".doctor"],
  "run_artifact_schema": "https://schemas.example/doctor/run-artifact/1.0.json",
  "report_schema": "https://schemas.example/doctor/report/1.0.json"
}
```

### `health` (one line + exit code)

```text
ok  br=0.4.7 doctor=1.0.0 findings=0 last_run=2026-05-06T14:23:07Z run_id=2026-05-06T14-23-07Z__a3f9b2
```

```text
findings  br=0.4.7 doctor=1.0.0 findings=3 P0=1 P2=2 last_run=2026-05-06T14:23:07Z run_id=2026-05-06T14-23-07Z__a3f9b2
```

```text
concurrency  br=0.4.7 doctor=1.0.0 reason=lock_held holder_pid=12345 last_run=none
```

Exit codes: `0` ok, `1` findings present, `4` unsafe, `5` concurrency, `74` io.

### `robot-docs` (Markdown to stdout)

A self-contained agent handbook. Includes:
1. The CLI surface (this file's first half, condensed).
2. Exit codes table.
3. JSON schema pointers.
4. Five canonical examples (healthy, broken-with-findings, broken-with-fix, undo, explain).
5. The capabilities endpoint for machine-readable extraction.
6. A "things doctor will NEVER do" list (delete during diagnose/fix/undo, run destructive shell, write outside scope), plus the explicit `gc --before <date> --yes` retention-cleanup exception.

Output ends with a single newline; no trailing color codes.

### `--robot-triage` (mega-command JSON)

```jsonc
{
  "schema_version": "1.0",
  "summary": { "ok": false, "total_findings": 3, "auto_fixable": 3 },
  "quick_ref": ["P0: 1 finding", "P2: 2 findings", "All auto-fixable"],
  "findings": [/* same as diagnose findings */],
  "actions_planned": [
    { "fixer_id": "fm-jsonl-tombstone-drift", "writes_to": [".beads/issues.jsonl"], "estimated_bytes": 4096 }
  ],
  "recommended_command": "br doctor --fix --only fm-jsonl-tombstone-drift",
  "capabilities_url": "br doctor capabilities --json",
  "robot_docs_command": "br doctor robot-docs"
}
```
