# Adversarial Review — Specific Attack Scenarios

The Phase 7 fresh-eyes prompts are calibrated to find bug classes. This file enumerates **specific** attack scenarios beyond those prompts — concrete failure injections and crafted inputs the reviewer should construct and run.

Use these in Phase 7 (after the calibrated prompts) and in Phase 5 (as supplemental fault-injection beyond `verify-crash-recovery.sh`). When the user is the adversary (a curious or malicious agent runs the doctor), each scenario is a real risk you must not ignore.

---

## A. Filesystem path attacks

### A.1 — Symlink escape from inside `write_scopes`

**Setup:** Plant `<repo>/.beads/inner -> /etc/passwd`.
**Agent invocation:** `<tool> doctor --fix`.
**Expected:** `mutate()` resolves the symlink, sees the resolved path is outside `write_scopes`, refuses with exit 4 and a `safety_block` finding citing the symlink + the resolved path.

**Code-level check:** In `mutate()`, the `ensure_in_scope` function MUST canonicalize:
```rust
let canonical = path.canonicalize().or_else(|_| Ok::<_, std::io::Error>(path.to_owned()))?;
ensure_in_scope(caps, &canonical)?;
```

If `ensure_in_scope` works on the un-resolved path, this attack succeeds. Failure mode is documented at [SECURITY.md § Class 3](SECURITY.md).

### A.2 — Path traversal via `--only`

**Setup:** Healthy workspace.
**Agent invocation:** `<tool> doctor --fix --only "../../etc/passwd"`.
**Expected:** Argument parser refuses non-`fm-…` IDs OR the runtime simply finds no matching detector and exits 0 with no actions. Either way, no out-of-scope read.

**Code-level check:** `--only` accepts only IDs matching `^fm-[a-z0-9-]+$`. Reject otherwise with exit 64.

### A.3 — TOCTOU between detect and fix

**Setup:** Run `<tool> doctor --fix`. Concurrently, mid-run, modify the target file from outside the doctor.
**Expected:** The doctor's `mutate()` chokepoint reads the file again BEFORE writing, computes the new before_hash, and either:
- proceeds (the modified content matches the fixer's expected pre-state)
- aborts with a `safety_block` finding (the file was modified out from under us)

**Code-level check:** `mutate()` must read `before_bytes` immediately before writing the backup, NOT cache an earlier read from the detector phase.

---

## B. JSON / IO attacks

### B.1 — Crafted `actions.jsonl` poisoning

**Setup:** Run `<tool> doctor --fix`, complete it, then **modify** `.doctor/runs/<id>/actions.jsonl` to insert a fake action with `path: ../../../etc/passwd` and a corresponding fake backup at `.doctor/runs/<id>/backups/etc/passwd`.
**Agent invocation:** `<tool> doctor undo <id>`.
**Expected:** `undo --strict` (default) reads the actions.jsonl, checks each path is in `write_scopes`, refuses with exit 4 and an `unsafe_undo` finding citing the suspicious entry.

**Code-level check:** undo's per-action validator is:
```python
for action in actions:
    if not in_write_scope(action.path):
        raise UnsafeUndoError(f"action path {action.path} outside write_scopes")
    backup = run_dir / "backups" / action.path
    if not backup.exists():
        raise UnsafeUndoError(f"backup missing for {action.path}")
    if sha256(backup.read_bytes()) != action.before_hash:
        raise UnsafeUndoError(f"backup hash mismatch for {action.path}")
```

### B.2 — JSON output stdin injection (in `--explain`)

**Setup:** Plant a finding with `evidence: "garbage; { \"injected\": true }"`.
**Agent invocation:** `<tool> doctor --explain fm-...`.
**Expected:** The doctor JSON-encodes the entire output once (no string interpolation of evidence into a JSON template). Agents parsing `--explain --json` get a single JSON document; the injected payload is just a string field.

**Code-level check:** Use the language's structured JSON serializer (`serde_json` / `encoding/json` / `json.dumps` / `JSON.stringify`); never string-interpolate.

### B.3 — Credential leak via finding evidence

**Setup:** Workspace has `~/.config/<tool>/credentials` with mode 0o644 (P1 finding).
**Agent invocation:** `<tool> doctor --json`.
**Expected:** The finding's evidence contains the file path and `mode_octal: "644"` but **NOT the file contents**. The redaction set in [SECURITY.md § Class 2](SECURITY.md) catches token patterns.

**Code-level check:** Evidence builders never include `read_bytes()` of credential-class files; they only stat metadata. For non-credential files, raw bytes go through `redact_secrets()`.

---

## C. Concurrency attacks

### C.1 — Lock-acquire race

**Setup:** Spawn N=100 `<tool> doctor --fix` invocations in tight loop.
**Expected:** Exactly one wins (exit 0/2/3); the others all exit 5 with `lock_held` finding. No torn writes; no mixed actions.jsonl entries.

**Code-level check:** `try_lock_exclusive` with `LOCK_NB`; never `lock_exclusive` (which would block).

### C.2 — Lock orphan after panic

**Setup:** Modify the doctor (in a fork / test branch) to `panic!("test")` mid-`mutate()`. Run. Observe.
**Expected:** Even on panic, the lock file's fcntl lock is released (because the file descriptor is closed during stack unwinding / process termination). Next run can acquire.

**Code-level check:** No `std::mem::forget(lock_file)`; lock guard's `Drop` runs on panic.

### C.3 — Mid-fix process kill

**Setup:** SIGKILL the doctor between `mutate()` writing the backup and writing the live file (a tiny race window).
**Expected:** Next run's recovery reads `actions.jsonl`. The aborted action has either:
- No line in `actions.jsonl` (the line is appended only on success) → no record of the partial action; live file is the original.
- Or, the backup file exists but no actions.jsonl line → quarantine the orphan backup and emit a finding.

**Code-level check:** `mutate()`'s order:
1. Acquire lock
2. Read live file → before_hash
3. Write backup
4. Cmp-strict
5. **Plan in memory**
6. **Write to disk atomically (temp + rename)**  ← if SIGKILL between 5 and 6, no live-file change
7. Read live file → after_hash
8. Append actions.jsonl line ← if SIGKILL between 6 and 8, the change is on disk but unrecorded

The dangerous gap is 6–8. Mitigation: write actions.jsonl line BEFORE step 6, then update with after_hash post-write. The agent reading actions.jsonl sees the entry; if before_hash matches and after_hash is the empty string, recovery detects the mid-write crash and treats it as a `pending` action.

This is a real subtlety — the implementer must choose:
- (A) record-then-write: append line with `pending: true`, then mutate, then update after_hash. Recovery sees `pending`.
- (B) write-then-record: simpler but creates the 6–8 gap above. Recovery has no record.

Recommendation: **(A) for the chokepoint of any P0 fixer; (B) is acceptable for P3 cosmetic fixers.**

---

## D. State machine attacks

### D.1 — Repeated --fix from a half-completed prior run

**Setup:** Kill mid-`MUTATING`. Then run `<tool> doctor --fix` again.
**Expected:** Recovery detects orphan backups (per C.3); refuses with exit 4 and a `partial_run_<id>_must_resolve_first` finding pointing at `<tool> doctor undo <id>` or `<tool> doctor recover <id>`.

**Code-level check:** Phase-0 detector for "in-flight runs" reads each run-dir's `actions.jsonl`; if the last entry has `pending: true` or no `after_hash`, that run is in-flight.

### D.2 — Double-undo

**Setup:** Run `<tool> doctor --fix`. Run `<tool> doctor undo <id>`. Run `<tool> doctor undo <id>` again.
**Expected:** Second undo is idempotent: detects the run is already undone (each backup's hash equals the live file's hash), reports `actions_taken: 0`, exits 0.

**Code-level check:** Undo iterates actions in reverse; for each, if `live_file_hash == before_hash`, skip (already restored).

### D.3 — Undo across binary version bump

**Setup:** Run `<tool> doctor --fix` with binary v1.0. Upgrade to v2.0 (which bumps `doctor_contract_version`). Run `<tool> doctor undo <id>` from v2.0.
**Expected:** v2.0's actions.jsonl reader detects the v1.0 schema; either reads it correctly (forward-compat) or refuses with a clear error citing v1.0 (per [VERSIONING.md](VERSIONING.md) Strategy B).

**Code-level check:** `actions.jsonl` schema_version is read FIRST.

---

## E. Resource-exhaustion attacks

### E.1 — Disk-full during `mutate()`

**Setup:** Mount a 1MB tmpfs at `<run-dir>/backups/`. Run `<tool> doctor --fix` against a corrupted fixture whose backup needs > 1MB.
**Expected:** `mutate()`'s backup write fails with ENOSPC. The fixer aborts with exit 3 (rollback). Any partial backup is removed; live file is unchanged.

**Code-level check:** `mutate()` does NOT proceed to mutation unless the backup write succeeds AND `cmp_strict` succeeds.

### E.2 — Pathologically deep symlink chain

**Setup:** `<repo>/.beads/a -> b -> c -> ... -> /etc/passwd`.
**Expected:** `path.canonicalize()` either resolves (and refuses out-of-scope) or fails with `ELOOP` after the kernel's symlink limit (40 on Linux). The doctor handles ELOOP and emits a finding rather than crashing.

### E.3 — Million-line `actions.jsonl`

**Setup:** Concoct an `actions.jsonl` with 1M lines (e.g., a buggy fixer that ran `mutate()` in a loop).
**Agent invocation:** `<tool> doctor undo <id>`.
**Expected:** Undo streams the file (line by line); does not read it all into memory. Memory usage is bounded.

**Code-level check:** Reverse-iterate via line buffering (read whole file once but process actions in reverse via a Vec — bounded by file size) OR use `tac` / `Vec::reverse` after reading. For pathological files (>1GB), refuse with a clear error.

---

## F. Trust-boundary attacks

### F.1 — Modified `.doctor/.gitignore`

**Setup:** A malicious commit removes `.doctor/` from `.gitignore` so backups would be checked in.
**Expected:** Phase-0 setup re-asserts `.gitignore` includes `.doctor/`; goes through `mutate()` for the change so it's auditable. The pre-commit hook (Phase 8) blocks if `.doctor/` content is staged.

### F.2 — Modified bundled trust anchor

**Setup:** A malicious commit replaces the bundled signing key in the installer-pattern doctor.
**Expected:** This is detectable only by the project's own release-time signature check (CI verifies the binary signature). The doctor itself trusts its bundled anchor. Per [recipes/installer.md](../recipes/installer.md), this is the trust boundary; defense is at the build/release layer, not the doctor layer.

### F.3 — `--force` plus `--yes` slip-through

**Setup:** Find a code path where `--force` bypasses a precondition without `--yes`.
**Expected:** `--force` is structurally gated on `--yes`; CLI parser refuses `--force` without `--yes` with exit 64.

**Code-level check:** Parser-level gate, not runtime check (the parser refuses before any state is touched).

---

## How to use this file

In Phase 7's third round (or at Pair+ tier in a separate "adversarial round"):

1. The reviewer agent reads this file.
2. For each scenario A.1 through F.3, the reviewer constructs the setup as a temporary fixture (in `tests/doctor_fixtures/adversarial/<id>/`) and runs the documented invocation.
3. If the doctor behaves as Expected, the scenario passes.
4. If not, file a P0/P1 bead and re-enter Phase 4.

The 18 scenarios above are the core set. Project-specific scenarios are added per-pattern (e.g., installer-pattern projects add F.2 variants for their specific trust manifest).

A future enhancement: turn this into a runnable `tests/doctor_fixtures/adversarial/run_all.sh` that exercises every scenario against the current binary in CI.
