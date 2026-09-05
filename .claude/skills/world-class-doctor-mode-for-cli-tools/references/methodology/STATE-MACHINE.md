# Doctor Lifecycle State Machine

The doctor's behavior at runtime is a finite state machine. Phase 7 fresh-eyes uses it as a checklist; the safety harness uses it as a partition of test cases; agents reading `<run-id>/report.json` can pinpoint exactly which transition they're inspecting.

This file pins the canonical states, the legal transitions, and the invariants that hold in each state.

---

## States

```
                                ┌──────────────┐
                                │   IDLE       │
                                │ (no run dir, │
                                │  no lock)    │
                                └──────┬───────┘
                                       │  invocation
                                       ▼
                                ┌──────────────┐
                                │  STARTING    │
                                │  (run-id     │
                                │  derived;    │
                                │  run-dir     │
                                │  created)    │
                                └──────┬───────┘
                                       │  detectors loaded
                                       ▼
                                ┌──────────────┐
                                │  DIAGNOSING  │
                                │  (detectors  │
                                │  run; pure;  │
                                │  no writes)  │
                                └──────┬───────┘
                                       │ ┌──── exit 0 (no findings) ──┐
                                       │ │                             │
                                  ┌────┴─┴────┐                ┌──────▼─────┐
                                  │ findings? │ no             │   DONE_OK  │
                                  └─────┬─────┘                │ (report    │
                                        │ yes                  │  written;  │
                                        ▼                      │  symlink)  │
                                  ┌──────────┐                 └────────────┘
                                  │  --fix?  │ no              ┌──────────────┐
                                  └────┬─────┘────────────────►│ DONE_FINDINGS│
                                       │ yes                   │ (exit 1;     │
                                       ▼                       │ report ok)   │
                                ┌──────────────┐               └──────────────┘
                                │  PLANNING    │
                                │  (compute    │
                                │  ordered     │
                                │  fix queue)  │
                                └──────┬───────┘
                                       │
                                ┌──────┴─ precondition fail ──┐
                                │                              ▼
                                │                        ┌──────────────┐
                                │                        │  REFUSING    │
                                │                        │  (exit 4;    │
                                │                        │  no mutations│
                                │                        │  yet)        │
                                │                        └──────────────┘
                                ▼
                                ┌──────────────┐
                                │  ACQUIRING_  │
                                │  LOCK         │
                                └──┬───────┬───┘
                                   │       │ contended
                                   │       ▼
                                   │  ┌──────────────┐
                                   │  │ LOCK_LOST    │
                                   │  │ (exit 5)     │
                                   │  └──────────────┘
                                   │ acquired
                                   ▼
                                ┌──────────────┐
                                │  MUTATING    │
                                │  (mutate()   │
                                │  per fixer;  │
                                │  in order)   │
                                └──┬───┬───┬───┘
                       ┌──────────┘   │   └──────────┐
                       │ all ok       │ partial      │ panic / SIGKILL
                       ▼              ▼              ▼
              ┌──────────────┐ ┌──────────────┐ ┌─────────────────┐
              │ VERIFYING    │ │ ROLLING_BACK │ │ ABORTED          │
              │ (re-run      │ │ (per         │ │ (atomicity holds; │
              │  detectors;  │ │  actions.    │ │ next run reads    │
              │  expect None)│ │  jsonl in    │ │ partial actions   │
              └──┬───────┬───┘ │  reverse)    │ │ and recovers)     │
                 │       │     └──────┬───────┘ └─────────────────┘
                 │ pass  │ residual   │
                 ▼       │            ▼
            ┌──────────┐ │      ┌──────────────┐
            │ DONE_OK  │ │      │ DONE_FAILED  │
            │ (exit 0) │ │      │ (exit 3;     │
            └──────────┘ │      │ all backups  │
                         │      │ restored)    │
                         ▼      └──────────────┘
                ┌──────────────┐
                │ DONE_PARTIAL │
                │ (exit 2;     │
                │ some fixed)  │
                └──────────────┘
```

---

## Per-state invariants

### IDLE
- No `.doctor/runs/<this-run>/` directory exists.
- No `.doctor/.doctor.lock` (or project lock) is held by this process.
- `latest` symlink may or may not exist (from prior runs).

### STARTING
- `target_sha` resolved.
- `run_id = sha256(target_sha + iso8601_utc_seconds)[..6]` computed (Q-013 style).
- `.doctor/runs/<run-id>/` created, mode 0700.
- `.doctor/runs/<run-id>/{report.json, actions.jsonl, backups/}` not yet written.
- The lock is **not** acquired here — diagnose mode never touches the project lock.

### DIAGNOSING
- Every detector callable runs in this state.
- Detectors are PURE: no `mutate()` calls, no disk writes, no env var changes.
- Every detector's verdict (Finding | None) is collected in memory.
- If a detector itself crashes (panic / unwrap), the runtime catches the panic and emits a `safety_block` finding citing the detector that crashed; doctor proceeds with remaining detectors.

### PLANNING
- All findings collected.
- Plan is the list of fixers to invoke, ordered by `dependency_graph.json`.
- Conflict matrix consulted; conflicting fixers exclude each other and produce a `safety_block` finding.
- Pre-conditions per fixer evaluated; failures produce `safety_block` findings, never partial state.

### ACQUIRING_LOCK
- The project's existing lock (or `.doctor/.doctor.lock`) is acquired with `LOCK_NB`.
- 5-second timeout (configurable via `<tool> doctor capabilities --json::lock_timeout_seconds`).
- On failure → state LOCK_LOST.

### MUTATING
- For each fixer in plan order:
  - Each `mutate(path, op)` call appends one line to `actions.jsonl` after the mutation completes.
  - Backups exist for every path written.
  - `before_hash` and `after_hash` recorded.
- The lock is held throughout this state.

### VERIFYING
- Each fixer's detector is re-run against the post-fix state.
- Expected: all return None.
- If any returns a Finding, the fixer is marked partially-successful; the run state transitions to DONE_PARTIAL.

### ROLLING_BACK
- Triggered by mutate() returning Err.
- Reads `actions.jsonl` in reverse order.
- For each mutation, restores from `backups/<rel-path>` via `Op::WriteFile { content: backup_bytes, mode: backup_mode }`.
- Verifies post-restore hash matches `before_hash`; if not, escalates to DONE_FAILED with a `corrupt_rollback` finding.

### ABORTED
- Process killed externally.
- The next run's recovery detector reads `actions.jsonl` and detects an open transaction.
- It either completes the partial fix (rare; only if the remaining fixers' preconditions still hold) or quarantines the artifacts and prompts the user to run `<tool> doctor undo <run-id>` manually.

### DONE_OK / DONE_FINDINGS / DONE_PARTIAL / DONE_FAILED / LOCK_LOST / REFUSING
- Terminal states. Each has a fixed exit code.
- `latest` symlink updated atomically only on DONE_OK / DONE_FINDINGS / DONE_PARTIAL.
- `actions.jsonl` is closed (synced).
- The lock (if held) is released.
- The run-dir is read-only after this point (chmod 0500 directory, 0400 files).

---

## Legal transitions only

Each transition above is permitted; **anything else is a bug**. The Phase 7 fresh-eyes review uses this as a checklist:

- IDLE → STARTING: only via top-level invocation.
- STARTING → DIAGNOSING: only after run-dir creation.
- DIAGNOSING → DONE_OK: only when zero findings.
- DIAGNOSING → DONE_FINDINGS: only when findings exist AND `--fix` was NOT passed.
- DIAGNOSING → PLANNING: only when findings exist AND `--fix` was passed.
- PLANNING → REFUSING: precondition failure / conflict / `--force` not provided where required.
- PLANNING → ACQUIRING_LOCK: only when plan is fully validated.
- ACQUIRING_LOCK → MUTATING: only when lock acquired.
- ACQUIRING_LOCK → LOCK_LOST: only when lock acquisition timed out.
- MUTATING → VERIFYING: only when all planned fixers ran without error.
- MUTATING → ROLLING_BACK: when any fixer returned Err.
- MUTATING → ABORTED: external signal (SIGKILL); the doctor itself never transitions here directly.
- VERIFYING → DONE_OK: all detectors return None.
- VERIFYING → DONE_PARTIAL: at least one detector still finds a residual.
- ROLLING_BACK → DONE_FAILED: rollback complete, all backups restored.
- ROLLING_BACK → DONE_FAILED with `corrupt_rollback`: a backup was missing or hash-mismatched.

Forbidden transitions (bugs):
- MUTATING → DIAGNOSING (re-detection mid-fix is a TOCTOU window)
- ACQUIRING_LOCK → MUTATING without holding the lock
- PLANNING → MUTATING without ACQUIRING_LOCK
- DIAGNOSING → MUTATING (always go through PLANNING)

---

## State machine in `report.json`

The terminal state is recorded as `report.json::state`. Agents read this to know what happened:

```jsonc
{
  "state": "DONE_PARTIAL",
  "exit_code": 2,
  "findings": [...],
  "actions_taken": 5,
  "actions_failed": 2,
  "backups_restored": 0
}
```

```jsonc
{
  "state": "REFUSING",
  "exit_code": 4,
  "reason": "schema_version_unknown",
  "remediation": "..."
}
```

---

## When to consult this state machine

- **Phase 4 implementer review:** verify every `mutate()` call site is reachable only from MUTATING state.
- **Phase 5 safety harness:** test each transition (especially MUTATING → ABORTED → recovery).
- **Phase 7 fresh-eyes:** check no forbidden transitions exist in code.
- **Phase 9 fixture authoring:** every fixture exercises one terminal state.
- **At runtime postmortem:** read `report.json::state` to know which transition diverged from happy path.
