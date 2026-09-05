# RFC — The Doctor Contract

> **Status:** Living. The contract evolves with `doctor_contract_version`.
>
> **Audience:** agents (Claude / Codex / Gemini / etc.) implementing or invoking
> doctors built by this skill. Agent-builders adopting this contract for their own
> tools. Maintainers of THIS skill auditing for contract adherence.
>
> **Conventions:** RFC 2119 keywords (MUST, SHOULD, MAY) used per IETF style.

This file is the doctor contract written as if it were an RFC: explicit, testable, audience-neutral. Other reference files in this skill are explanations OF the contract; this file IS the contract.

---

## 1. Scope

This RFC defines the agent-facing contract for any CLI tool's `doctor` subcommand built using the `world-class-doctor-mode-for-cli-tools` skill. The contract specifies:

- The required subcommands and flags.
- The exit-code dictionary.
- The JSON output schemas.
- The per-run artifact layout.
- The chokepoint invariants.
- The reflection surface.

A `<tool> doctor` implementation that satisfies this RFC MUST be invocable by any agent compatible with this RFC's `doctor_contract_version`.

---

## 2. Subcommands

A conformant `<tool> doctor` MUST implement these subcommands:

| Subcommand | Read-only? | Purpose |
|------------|-----------|---------|
| `diagnose` (default) | Yes | Run all detectors; report findings; no mutation. |
| `fix` | No | Run detectors, then fixers (subject to flags). |
| `undo <run-id>` | Special | Restore from a prior run's backups. |
| `explain <finding-id>` | Yes | Expand a single finding's evidence. |
| `capabilities` | Yes | Print the contract (this RFC instantiated for this tool). |
| `health` | Yes | Cheap (< 200 ms) liveness summary. |
| `robot-docs` | Yes | Paste-ready agent handbook. |
| `gc` | No (gated on --yes + --before) | Prune old run-dirs. |
| `ls` | Yes | List runs in `.doctor/runs/`. |
| `diff [<ref>]` | Yes | Compute what `--fix` WOULD change without mutating. Optional `<ref>` baselines against a prior run-id (default: current state). Output is a unified diff (or JSON action list with `--json`). MAY also be invoked as `--dry-run --fix`; the `diff` subcommand is the agent-ergonomic spelling.

Implementations MAY add additional subcommands (e.g., `verify-install` for installer-pattern tools). Additional subcommands MUST be declared in `capabilities --json::extra_subcommands`.

---

## 3. Universal flags

A conformant doctor MUST support:

| Flag | Type | Default | Purpose |
|------|------|---------|---------|
| `--json` | bool | false | Stable JSON output to stdout. |
| `--robot` | bool | false | Alias for `--json` plus structured envelope. |
| `--quiet` | bool | false | Suppress diagnostic stderr. |
| `--verbose` / `-v` | int (count) | 0 | Increase stderr verbosity. |
| `--no-color` | bool | auto | Force-disable ANSI. |
| `--no-progress` | bool | auto | Force-disable spinners. |

For `diagnose` and the bare invocation, additionally:

| Flag | Type | Default | Purpose |
|------|------|---------|---------|
| `--fix` | bool | false | Apply fixers to findings. |
| `--dry-run` | bool | false | (with `--fix`) Print plan; do not execute. |
| `--only=<id1,id2,...>` | list | all | Scope to a subset. |
| `--skip=<id1,id2,...>` | list | none | Inverse of `--only`. |
| `--since=<run-id>` | string | none | Diff against an earlier run. |
| `--online` | bool | false | Enable network probes. |
| `--explain=<finding-id>` | string | none | Expand one finding. |
| `--severity=<P0\|P1\|P2\|P3>` | string | P3 | Minimum severity to emit. |
| `--quick` | bool | false | Run only fast-path detectors. |
| `--budget=<duration>` | string | none | Refuse if estimated cost exceeds. |
| `--force` | bool | false | Override exit-4 (requires `--yes`). |
| `--yes` | bool | false | Skip confirmations for `--force` and `gc`. |
| `--robot-triage` | bool | false | Mega-command. |

Auto-detection rules:

- `--no-color` MUST be auto-true when stdout is not a TTY OR when `NO_COLOR=1` OR when `TERM=dumb`.
- `--no-progress` MUST follow the same auto-detection.
- `--json`/`--robot` MUST imply `--no-color` and `--no-progress`.

---

## 4. Exit-code dictionary

A conformant doctor MUST use these exit codes with these semantics:

| Code | Name | Meaning |
|------|------|---------|
| 0 | `success_or_healthy` | Healthy / fix complete / undo complete. |
| 1 | `findings_present_no_fix` | `diagnose` (no `--fix`): findings exist. |
| 2 | `fix_partial` | `fix`: some findings fixed, some not. |
| 3 | `fix_failed_rolled_back` | `fix`: at least one mutation failed; rolled back. |
| 4 | `refused_unsafe` | Refused to act due to unsafe state. |
| 5 | `concurrency_lost` | Another doctor holds the lock. |
| 6 | `online_required` | `--online` required for at least one finding. |
| 64 | `usage_error` | Bad CLI usage (POSIX EX_USAGE). |
| 66 | `no_input` | Target path doesn't exist or isn't a project. |
| 73 | `cant_create` | Couldn't create run-dir. |
| 74 | `io_error` | Filesystem I/O error during read/non-mutating write. |

Implementations MAY introduce additional exit codes, which MUST be declared in `capabilities --json::exit_codes`. Repurposing an existing code is a MAJOR contract bump.

---

## 5. JSON output schemas

### 5.1 `diagnose --json` schema

```jsonc
{
  "schema_version": "1.0",        // REQUIRED
  "tool": "<tool>",                // REQUIRED
  "tool_version": "<semver>",      // REQUIRED
  "doctor_version": "<semver>",    // REQUIRED
  "run_id": "<ISO8601>__<id>",    // REQUIRED
  "run_dir": ".doctor/runs/<run-id>", // REQUIRED
  "started_at": "<RFC3339>",       // REQUIRED
  "finished_at": "<RFC3339>",      // REQUIRED
  "duration_ms": 123,              // REQUIRED
  "target_sha": "<git-sha>",       // OPTIONAL (omit if non-git)
  "ok": false,                     // REQUIRED
  "state": "DONE_FINDINGS",        // REQUIRED — terminal state per STATE-MACHINE.md (one of DONE_HEALTHY, DONE_FINDINGS, DONE_FIXED, DONE_PARTIAL, DONE_FAILED, DONE_REFUSED, DONE_CONCURRENCY_LOST)
  "summary": { ... },              // REQUIRED
  "findings": [ ... ],             // REQUIRED (may be empty)
  "partial_failures": [ ... ],     // REQUIRED when state=DONE_PARTIAL or exit_code=2; per-finding {fm_id, reason, attempted_action}; empty array otherwise
  "exit_code": 1,                  // REQUIRED (matches the actual exit code)
  "next_steps": [ ... ]            // REQUIRED (may be empty)
}
```

Each `finding` object:

```jsonc
{
  "id": "fm-...",                  // REQUIRED
  "severity": "P0|P1|P2|P3",      // REQUIRED
  "subsystem": "<name>",           // REQUIRED
  "title": "<short>",              // REQUIRED
  "evidence": { ... },             // REQUIRED, structured (file:line, hash, query, etc.)
  "confidence": 0.95,              // REQUIRED — float in [0.0, 1.0]. Detector's confidence
                                   // that this finding represents real corruption (vs. a
                                   // false positive). 1.0 = deterministic (e.g., sha hash
                                   // mismatch); 0.7 = heuristic (e.g., suspicious mtime);
                                   // 0.5 = informational only. Agents MAY filter
                                   // `confidence < 0.7` for noisy detectors.
                                   // Per-detector confidence rationale belongs
                                   // in the detector spec and, when exposed,
                                   // the capabilities entry.
  "remediation": {                 // REQUIRED
    "command": "<paste-ready>",    // canonical name (see assets/report-template.json + CLI-SURFACE.md)
    "explain_command": "<tool> doctor explain <id>",
    "auto_fixable": true,
    "estimated_actions": 1
  }
}
```

**Confidence guidance**:
- `1.0` — deterministic check that cannot false-positive (sha mismatch, schema version mismatch, syntactic JSONL parse error).
- `0.9` — high-confidence heuristic (file present + content structure violated; DB integrity_check fail).
- `0.7` — heuristic with known false-positive class (mtime-based staleness check; line-count divergence with possible benign causes).
- `0.5` — informational signal worth surfacing but uncertain (loose-object accumulation; suggested upgrade available).
- `< 0.5` — speculative; should not be emitted by default. Use `--severity` to filter.

### 5.2 `capabilities --json` schema

```jsonc
{
  "schema_version": "1.0",
  "tool": "<tool>",
  "tool_version": "<semver>",
  "doctor_version": "<semver>",
  "doctor_contract_version": "<semver>",
  "platform": { "os": "...", "arch": "..." },
  "subsystems": [ "<name>", ... ],
  "detectors": [ {
    "id": "fm-...",
    "subsystem": "<name>",
    "severity": "P0..P3",
    "description": "<short>",
    "estimated_cost_ms": 30,
    "online_required": false,
    "tier": "quick|default|deep|online"
  }, ... ],
  "fixers": [ {
    "id": "fm-...",
    "preconditions": [ "<name>", ... ],
    "writes_to": [ "<path-glob>", ... ],
    "ops": [ "<Op-variant>", ... ],
    "reversible": true,
    "idempotent": true,
    "cardinality": "low|high",
    "estimated_cost_ms": 50
  }, ... ],
  "manual_remediations": [ {
    "id": "fm-...",
    "instruction": "<plain-text>",
    "reason": "<why-not-auto-fixable>"
  }, ... ],
  "allowed_ops": [ "WriteFile", "AppendFile", "Rename", "Chmod", "DbExec", "DbMigrate", "SymlinkAtomic" ],  // closed set per [KERNEL.md § Axiom 2](KERNEL.md). `mutate()` MUST validate `op ∈ allowed_ops` before any write. Subset of the canonical 7-variant Op enum (see [MUTATE-CHOKEPOINT.md § The op enum](MUTATE-CHOKEPOINT.md)). Optional 8th `Chown` variant may be included by tools that need it.
  "exit_codes": { "<int>": "<name>", ... },
  "env_vars": { "<NAME>": "<purpose>", ... },
  "write_scopes": [ "<path-glob>", ... ],
  "lock_path": "<path>",
  "lock_timeout_seconds": 5,        // canonical default; matches OPERATORS.md, STATE-MACHINE.md, SAFETY-ENVELOPE-TEMPLATE.md. Tools may override but must declare here.
  "run_artifact_schema": "<URL>",
  "report_schema": "<URL>",
  "siblings": [ /* if multi-binary */ ]
}
```

### 5.3 `--robot` envelope

When `--robot` is set, the JSON output is wrapped:

```jsonc
{
  "success": true,                 // matches exit_code == 0
  "command": "doctor",
  "timestamp": "<RFC3339>",
  "data": { ... },                 // the actual output
  "error": {                       // OPTIONAL
    "code": "<exit-code-name>",
    "message": "<human-readable>",
    "details": "<optional>"
  },
  "suggestions": [ "<paste-ready>", ... ],   // empty if no findings
  "timing": {
    "started_at": "<RFC3339>",
    "duration_ms": 123
  }
}
```

This envelope is per Q-014 (caam robot pattern).

---

## 6. Per-run artifacts

A `<tool> doctor` invocation MUST create `<repo>/.doctor/runs/<run-id>/` containing:

| File | Required? | Purpose |
|------|-----------|---------|
| `report.json` | Yes | The structured report (matches schema 5.1). |
| `report.md` | Yes | Human-readable narrative version. |
| `actions.jsonl` | If --fix run | Append-only mutation log. |
| `backups/` | If --fix run with mutations | Verbatim file backups. |
| `scorecard.json` | If --fix run | Per-detector × per-dimension scores. |
| `undo.sh` | If --fix run | Idempotent rollback shell script. |
| `stderr.log` | Yes | Captured diagnostic stderr. |
| `stdout.json` | Yes | Copy of report.json (for replay). |

Files MUST be created with mode 0600 (or 0400 after run completion). Directory MUST be 0700 (or 0500 after).

---

## 7. The mutate() chokepoint

A conformant doctor MUST route every disk write under `--fix` through a single `mutate()` chokepoint that:

1. Acquires a per-path advisory lock.
2. Computes `before_hash = sha256(read_or_empty(path))`.
3. Validates `path ∈ write_scopes`.
4. Writes a verbatim backup; verifies via `cmp -s`.
5. Plans the mutation in memory.
6. Executes atomically (temp + rename for files; transaction for DBs).
7. Computes `after_hash`.
8. Appends a record to `actions.jsonl` with both hashes.
9. Releases the lock.

`scripts/validate-doctor.sh` MUST exit 0 against the doctor's source; this is the contract enforcement.

---

## 8. Reflective discovery

A conformant doctor MUST emit a `capabilities --json` document that, when round-tripped via `scripts/verify-capabilities.sh`, satisfies:

- Every declared detector ID is invocable via `--only <id>`.
- Every declared fixer ID is in the runtime registry.
- Every declared exit code is reachable from at least one code path.
- Every `write_scopes` entry is honored at runtime.
- `tool_version` matches `<tool> --version`.
- `schema_version` matches the embedded contract version.

---

## 9. Online behavior

`--online` is opt-in. Without it, network detectors MUST be skipped silently and a `findings_only_offline` finding MUST be emitted listing what wasn't checked.

When `--online` is set:

- Network detectors run.
- Each network call MUST have a 10-second timeout.
- On timeout, the network detector emits `findings_only_offline` for itself and proceeds.
- The doctor's overall behavior MUST NOT degrade by hanging on a network failure.

---

## 10. Versioning

| Version field | Bump rule |
|---------------|-----------|
| `tool_version` | Project's existing semver; not the doctor's concern. |
| `doctor_version` | Minor for new fixers; major for incompatible refactors of internal types. |
| `doctor_contract_version` | Major for breaking changes to this RFC. Minor for additive (new fields, new exit codes). |
| `schema_version` (per artifact) | Often equal to `doctor_contract_version` but may bump independently. |

The doctor's actions.jsonl reader at version Y MUST parse files produced by version X for X ≤ Y within the same major. Cross-major compatibility is opt-in via the doctor's choice (per [VERSIONING.md](VERSIONING.md) Strategy A or B).

---

## 11. Negative-space spec

A conformant doctor MUST NOT:

- Delete files during diagnose/fix/undo. Quarantine via `Op::Rename` is the only fixer "delete" semantics; run-directory pruning is limited to the separately gated `gc --before <date> --yes` command.
- Run destructive shell commands (`rm -rf`, `git reset --hard`, etc.).
- Touch paths outside `write_scopes`.
- Probe network unless `--online` is set.
- Mutate when the project's lock is held by another process.
- Mutate without a verbatim backup.
- Write to paths discovered via symlink escape.
- Push commits to `main`/`master`.
- Run interactive prompts under `--robot` / `--json`.
- Output ANSI to stdout under `--robot` / `--json` / `NO_COLOR=1`.

`<tool> doctor robot-docs` MUST list this negative-space spec.

---

## 12. Conformance test suite

A doctor implementation claiming RFC conformance MUST pass:

- `scripts/validate-doctor.sh` (no out-of-chokepoint writes).
- `scripts/verify-capabilities.sh` (declared = invocable).
- `scripts/verify-undo.sh fm-<id>` for every FM (reversibility).
- `scripts/verify-idempotence.sh fm-<id>` for every FM.
- `scripts/verify-crash-recovery.sh fm-<id>` for every FM.
- `scripts/verify-concurrency.sh fm-<id>` for every FM.
- `scripts/verify-metamorphic.sh fm-<id>` for every FM.
- `tests/doctor_fixtures/run_all.sh` (per-FM round-trip).

Plus the relevant `[ADVERSARIAL-REVIEW.md]` scenarios for the project's pattern.

---

## 13. Future evolution

This RFC is living. Future bumps will:

- Add `--audience` flag (planned; mental-models.md).
- Add `<tool> doctor metrics-export` (planned; per [METRICS.md](METRICS.md)).
- Refine the `Op` enum if new mutation classes emerge.
- Add provenance tagging per Axiom 17.

Major bumps require a breaking-change rationale in [DECISION-LOG.md](DECISION-LOG.md) and a migration note in [CHANGELOG.md](../../CHANGELOG.md).

---

## Appendix A — Conformance checklist

```
[ ] All required subcommands exist
[ ] All universal flags supported
[ ] Exit-code dictionary matches Section 4
[ ] diagnose --json schema matches Section 5.1
[ ] capabilities --json schema matches Section 5.2
[ ] --robot envelope matches Section 5.3
[ ] Per-run artifacts created per Section 6
[ ] mutate() chokepoint per Section 7
[ ] Reflective discovery per Section 8
[ ] --online behavior per Section 9
[ ] Versioning per Section 10
[ ] Negative-space spec per Section 11
[ ] Conformance test suite per Section 12 passes
```

A doctor that passes this checklist is RFC-conformant. The skill's methodology produces such doctors by construction.
