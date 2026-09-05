# CASS Findings — Surprising Patterns from Prior Agent Sessions

Mined from `cass search` queries during the bootstrap. Each entry: a quote, citation, and what we learn from it for the doctor.

The freshest mining is run by `subagents/cass-miner.md` per Phase 0 and produces `<workspace>/cass_findings.{md,jsonl}`. This file holds the durable, recurring patterns across many sessions — the ones worth carrying skill-wide.

---

## Finding 1 — `caam robot` is the strongest agent-ergonomic surface in the user's repos

**Quote (cass search "agent friendly doctor health command"):**

> `caam robot status [provider]` - Full system overview with profiles, health, cooldowns
> `caam robot next <provider>` - Scoring algorithm to recommend best profile
> `caam robot act` - Execute actions (activate, cooldown, uncooldown, backup, refresh, delete)
> `caam robot health` - Quick health check (vault, database, profiles)
> `caam robot watch` - Stream status updates as newline-delimited JSON
> `caam robot limits <provider>` - Rate limits and burn rate data

**Citation:** caam analysis session, source_path elided.

**Lift:** The `<tool> robot <subcmd>` namespace is a pattern the doctor should adopt. We're putting the doctor's robot surface under `<tool> doctor --robot-*` rather than a top-level `<tool> robot doctor`, but the shape (`status | next | act | health | watch | limits`) translates directly:

- `status` → `<tool> doctor diagnose --json`
- `next` → `<tool> doctor explain <next-priority-finding>`
- `act` → `<tool> doctor --fix --only <id>`
- `health` → `<tool> doctor health`
- `watch` → `<tool> doctor health --watch` (NDJSON stream)
- `limits` → `<tool> doctor capabilities --json::budget`

---

## Finding 2 — Manual fixes for beads corruption are a recurring pain point

**Quote (cass search "manual fix corruption beads"):**

> "I now have the complete diff. Here is a detailed summary of all changes... SQLite Rollback Journal Support (`.db-journal`)... Adds `.beads/*.db-journal` to the stale lock file cleanup command..."

**Citation:** beads_rust large-diff review session.

**Lift:** Stale-lock cleanup is the canonical "thing the user is doing manually that should be in `br doctor --fix`." Specifically:

- Detect: `.db-journal`, `.db-wal`, `.db-shm`, `.beads/*.lock` from a process that's no longer alive (PID in lockfile vs. `kill -0` check).
- Fix: rename to `.doctor/runs/<id>/quarantine/locks/<basename>` (NOT delete; AGENTS.md).
- Fixture: spawn a child that takes the lock, kill it -9, assert detector fires, run `--fix`, assert the lock is in quarantine and the doctor reports healthy.

---

## Finding 3 — `cm doctor` validates environment but doesn't fix

**Quote (cass search "doctor command repair playbook"):**

> "`cm doctor`: Implemented system health checks for storage, dependencies, and config."
> "`cm doctor`: ✅ Diagnoses system state (correctly identified missing API keys in current environment)."

**Citation:** gemini session 2025-12-07T23-37 reviewing the cm CLI.

**Lift:** The "missing API key" finding is a great example of a P1 finding that is NOT auto-fixable: the doctor can't generate the key, only the user can. This is the case for `capabilities --json::manual_remediations`. The error must say:

```
ANTHROPIC_API_KEY not set. Set it via:
  export ANTHROPIC_API_KEY=...
Then re-run `cm doctor`.
```

The remediation command is a `bash` snippet, not a `<tool>` subcommand. That's fine — the field is `remediation.command_or_instruction`.

---

## Finding 4 — Sidecar files (WAL, SHM, journal) are a perennial trap

**Quote (from beads_rust diff review):**

> "Previously the codebase only handled WAL-mode sidecar files (`.db-wal`, `.db-shm`). These changes add consistent support for the rollback journal file (`.db-journal`)."

**Lift:** Cross-language failure mode: any tool that uses SQLite has at least four sidecar files (`.db`, `.db-wal`, `.db-shm`, `.db-journal`) and any cleanup or copy operation must handle the whole family or risk corruption. The doctor's detector for "DB family integrity" should:

- Enumerate all four siblings.
- Verify they're all present or all absent (not partial).
- For backup: copy all four atomically.
- For restore: write all four atomically (best done by stopping the DB, copying, restarting).

PostgreSQL has its own family (`pg_xact/`, `pg_wal/`, etc.) but for embedded DBs the SQLite four-file pattern is dominant.

---

## Finding 5 — Robot-docs is best-in-class when it includes "things tool will NEVER do"

**Quote (from caam robot analysis):**

> "Design principles: JSON output by default (no --json flag needed), No interactive prompts - designed exclusively for programmatic use, Structured error responses with error codes, Actionable suggestions included in output, Exit codes: 0=success, 1=error, 2=partial success, Compact but complete information"

**Lift:** `<tool> doctor robot-docs` should print the doctor's *negative space* alongside its capabilities:

```markdown
## What this doctor will NEVER do

- Delete files during diagnose/fix/undo. `<tool> doctor undo` RESTORES from backup;
  it does not erase. Quarantined files are MOVED, not deleted. Retention cleanup is
  the separately gated `doctor gc --before <date> --yes` command.
- Run destructive shell (rm -rf, git reset --hard, git clean -fd). All equivalent
  semantics are implemented in code, scoped to documented paths, and recorded in
  actions.jsonl.
- Touch paths outside `capabilities.write_scopes`. Out-of-scope writes refuse with
  exit 4.
- Probe network unless `--online` is set. Default is offline-only.
- Mutate when the project's lock is held. Concurrent doctor invocations refuse with
  exit 5.
- Mutate without a verbatim backup. The mutate() chokepoint refuses if the backup
  fails to verify cmp-strict against the live file at the moment of backup.
```

This negative-space spec is what makes an agent willing to run the doctor unsupervised.

---

## Finding 6 — `br doctor` already implements quarantine-instead-of-delete

**Quote (from `/dp/beads_rust_c49_72yf27/src/cli/commands/doctor.rs`):**

> ```rust
> #[serde(skip_serializing_if = "Vec::is_empty")]
> quarantined_artifacts: Vec<PathBuf>,
> ```

**Lift:** This is the AGENTS.md no-delete rule operationalized. Other tools should adopt the same field name (`quarantined_artifacts`) so agents see a consistent vocabulary across the toolkit. The doctor's `--robot-triage` mega-command exposes the quarantine list under `summary.quarantined_count` and `actions_planned[].quarantines_to`.

---

## Finding 7 — Implementing `--fix --dry-run` is half the work and protects the user

**(General observation across sessions, not a single quote.)**

In sessions where the user wanted to run a fix and asked for "show me what you'd do first," the agent regularly grepped for "dry-run" or "plan" in the tool's `--help`. When neither existed, the agent had to read the source to know what the fixer would touch. That's a prima-facie ergonomics failure that the rubric scores under `blast_radius_containment`.

**Lift:** `--dry-run --fix` is a Polish Bar requirement. It must:

1. Print every path that would be mutated, by FM ID.
2. Print every backup that would be written.
3. Print the estimated bytes affected per path.
4. Exit 0 if the plan is valid; exit 4 if any precondition fails.

A common mistake: dry-run that "checks paths" but skips the backup-and-hash dry-run. The plan must include backup paths so the user can disk-budget.
