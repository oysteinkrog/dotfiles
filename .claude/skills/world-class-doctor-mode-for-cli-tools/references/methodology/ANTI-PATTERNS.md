# Anti-Patterns

A consolidated list of patterns that break the doctor contract. Each row: the violation, why it's wrong, the fix. Keep this file when reviewing PRs to the doctor module.

| ✗ Anti-pattern | Why it breaks the contract | Fix |
|----------------|---------------------------|-----|
| Bypass `mutate()` "for performance" | Breaks backup + hash + actions.jsonl. The undo path can't see the change. | Every disk write goes through `mutate()`. The performance overhead of one more function call is < 1 µs and dwarfed by I/O. |
| Score a detector >= 700 without evidence | Rubric is meaningless if anchored to vibes. | `scorecard.py validate <workspace>` rejects unsourced high scores. Cite file:line / fixture path. |
| Write a fixer without a fixture | Pass-N+1 can't tell "fixed" from "regressed". | Phase 9 is mandatory. `validate-pass.sh` (when it exists) checks. |
| Delete a file inside doctor | Violates AGENTS.md RULE 1. | Use `Op::Rename` to move the file under `<run-dir>/quarantine/`. The user reviews and decides whether to delete. |
| `rm -rf` inside any fixer | Destructive shell forbidden by AGENTS.md. | Implement equivalent in code: enumerate, back up, write new state via `mutate()`. |
| Apply a fix even though the lock is held | Concurrency-corrupts user state. | Refuse with exit 5 and a finding identifying the holder. |
| Print color/progress to stdout | Breaks `--json | jq`. | All ANSI / spinners go to stderr. Auto-disable on non-TTY / `NO_COLOR` / `--robot` / `--json`. |
| `panic!` / `unwrap()` on user-supplied paths | Crashes doctor in the worst possible moment. | Convert to a `safety_block` finding with exit 4 and a precise reason. |
| Backwards-compat shim for an existing flag | Project is pre-1.0; AGENTS.md forbids shims. | Just change the code. Demote any related skill to a fallback. |
| Mix data and progress on stdout | Breaks composability. | Stdout = data, stderr = progress. No exceptions. |
| Network probes in detect mode by default | Doctor must work in a sandbox. | Network is opt-in via `--online`. |
| Score the same FM under two different IDs | Cumulative scoring breaks across passes. | `fm_id` is content-derived (subsystem + symptom slug); use `compute-fm-id.py`. |
| Land changes on `main` of the target | Per AGENTS.md and basic git hygiene. | Always feature branch `doctor-mode-pass-<N>`; merge only with explicit user approval. |
| Modify the workspace as part of Phase 4 (in-tree code) | The workspace is the *measurement*; should be untouched by code changes. | Code changes go on the worktree's feature branch. Workspace tracks measurements only. |
| Treat "no `capabilities` endpoint" as a feature gap | The methodology IS to find these gaps. | If `capabilities` is missing, that's a P0 finding scored under diagnostic_specificity + observability. |
| Ship a fixer that prints "fixed" but didn't write actions.jsonl | Future undo cannot find the action. | `mutate()` is the only writer; if it didn't run, the fix didn't happen — emit a different finding instead. |
| Random / wall-clock IDs for run-id | Breaks determinism + reproducibility. | Run-id derived from `sha256(target_sha + iso8601_utc_seconds)[..6]`. |
| Detector with side effects ("memoize the result for next time") | Idempotence breaks. | Detector is pure. Memoization (if needed) goes through `mutate()` with the result as the op. |
| Fixer that reads the live file AFTER backup is written | Race between read and backup. | Order: read live → compute hash → write backup → cmp-strict → execute. The read inside `mutate()` happens BEFORE the backup write. |
| Fixer that re-formats unrelated bytes ("clean up trailing whitespace while we're here") | Reversibility breaks because undo isn't byte-identical. | Touch ONLY the bytes that need to change. The fixer's diff range is exactly its scope. |
| Cross-FS rename for atomicity | `rename(2)` is not atomic across filesystems. | Temp file MUST be in the same directory as the target. |
| Copy without preserving permissions/mtime for backups | Restore breaks downstream tools that key off mode. | `shutil.copy2` (Python), `cp -a` (Bash), preserve permissions explicitly. |
| `<tool> doctor` (no flags) writes to disk | Read-only by default invariant violated. | Detection writes ONLY to `.doctor/runs/<run-id>/{report.json, report.md}` and the `latest` symlink. Nowhere else. |
| Configurable defaults that change behavior under `--robot` | An agent can't predict behavior across configs. | `--robot` mode pins all behavior knobs to canonical defaults. Configs only affect non-robot mode. |
| Logging the full backup contents to stderr at `-v` | Blows up agent context. | Log the path + the hash, not the bytes. |
| Running tests as part of `<tool> doctor` | Detection should be cheap. | Tests live in `tests/doctor_fixtures/`. Doctor's `health` is < 200 ms. |
| Hard-coded English in error messages | Breaks i18n / localization. | Use the project's existing i18n primitive if any. (Pre-1.0 projects MAY hard-code English; document it.) |
| `panic!` if the lock can't be acquired | Crashes doctor in a fully recoverable situation. | Refuse with exit 5 and a finding. |
