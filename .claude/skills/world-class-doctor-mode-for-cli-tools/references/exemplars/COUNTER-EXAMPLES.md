# Counter-Examples

Real-world CLI doctor surfaces that fail one or more Polish Bar items. Use these to sharpen the rubric and to remember what NOT to ship.

---

## Counter-example 1: `<unnamed-tool> doctor` mixes log lines into stdout JSON

**Symptom.** `<tool> doctor --json | jq` fails because stdout has interleaved progress lines.

**Diagnosis.** The tool's logger defaults to stdout. It only suppresses ANSI when stdout is non-TTY but doesn't redirect log output to stderr.

**Polish Bar item failed:** "Stdout = data, stderr = progress."

**Lift:** All progress goes to stderr. `--quiet` suppresses stderr but stdout is unaffected. `--json` and `--robot` force-redirect any stray prints to stderr.

---

## Counter-example 2: `--fix` writes in place; no backup

**Symptom.** Agent runs `<tool> doctor --fix`. The fix corrupts state. No way to recover. Agent has to recover from the user's git stash, if any.

**Diagnosis.** No `mutate()` chokepoint. Each fixer wrote directly via `std::fs::write` / `os.WriteFile` / `fs.writeFileSync`.

**Polish Bar item failed:** "Single-chokepoint mutation" + "Backups before any mutation" + "Reversible".

**Lift:** Refactor every disk write through `mutate(path, op)`. Verify with `scripts/validate-doctor.sh`.

---

## Counter-example 3: Idempotence broken by header re-stamping

**Symptom.** `<tool> doctor --fix; <tool> doctor --fix` — second invocation reports `actions_taken: 2` because the fixer rewrites a file with a fresh `generated_at: <timestamp>` header even when content is otherwise identical.

**Diagnosis.** The fixer's "no-op detector" check happens AFTER the timestamp is materialized.

**Polish Bar item failed:** "Idempotent."

**Lift:** Detector compares the *content* without timestamp; fixer skips entirely if content is healthy. If a timestamp is essential, place it in a side-channel (e.g., `actions.jsonl::finished_at_ns`), not in the file content.

---

## Counter-example 4: `--fix` panics mid-write

**Symptom.** `<tool> doctor --fix` panics on a malformed input. The target file is left half-written (`.tmp.<pid>` is gone; the real file has the first 4 KB of the new content and 8 KB of the old content).

**Diagnosis.** The fixer wrote to the target file directly via `seek + write`, didn't use temp-file + rename.

**Polish Bar item failed:** "Crash-recoverable" + "Atomic writes."

**Lift:** Every file write goes through `tempfile::NamedTempFile + persist()` (Rust), `os.CreateTemp + os.Rename` (Go), `tempfile.NamedTemporaryFile + os.replace` (Python), `fs.writeFileSync(tmp) + fs.renameSync` (Node/Bun). Cross-FS rename is NOT atomic — temp file MUST live in the same directory as the target.

---

## Counter-example 5: `doctor undo` doesn't actually restore

**Symptom.** Agent runs `<tool> doctor --fix`, then `<tool> doctor undo latest`. The doctor reports "undo complete" but `cmp -s backup live-file` reports differences.

**Diagnosis.** The fixer touched bytes outside the diff range it claimed (e.g., reformatted the JSON it wrote). The backup is byte-identical to the *original* but the post-undo state is the *reformatted* version because the undo implementation re-formats while it writes.

**Polish Bar item failed:** "Reversible (byte-for-byte)."

**Lift:** `mutate()` writes the backup BEFORE any read of the live file. Undo is `cp backup → live` with no transformation. Verify with `cmp -s` in the round-trip test.

---

## Counter-example 6: `capabilities --json` exists but lies

**Symptom.** `capabilities --json` lists 12 detectors. Calling `<tool> doctor` (or `--only fm-X`) only invokes 9 of them. Three declared detectors don't exist in code.

**Diagnosis.** Capabilities was hand-maintained and drifted from reality.

**Polish Bar item failed:** "Self-describing (capabilities)."

**Lift:** `capabilities` is generated FROM the live registry of detectors and fixers, not maintained separately. `scripts/verify-capabilities.sh` round-trips the contract and fails CI if any declared item isn't callable.

---

## Counter-example 7: TUI launches when `--robot` is set

**Symptom.** Agent runs `<tool> doctor --robot --explain fm-X`. Tool launches a TUI. Agent session blocks until timeout.

**Diagnosis.** The `--robot` flag parser sets `output_format = "robot"` but the explain code path forks into a TUI inspector regardless.

**Polish Bar item failed:** "No TTY assumptions" + "Stdout = data."

**Lift:** A single `is_robot_mode()` (or `output_format != "human"`) check at the *entry point* of every subcommand. If true, every TUI / spinner / interactive prompt is replaced with a JSON output path. CI tests this with a `--robot` smoke run on a non-TTY pty.

---

## Counter-example 8: Doctor needs network for read-only diagnose

**Symptom.** `<tool> doctor` (no flags, supposed to be cheap and read-only) makes a DNS lookup to a vendor API. In a sandbox without network, doctor hangs for 30 s before timing out.

**Diagnosis.** A "license check" detector runs by default and calls home.

**Polish Bar item failed:** "Offline by default."

**Lift:** Network-dependent detectors are `online_required: true` in `capabilities --json`. They're skipped unless `--online` is set. When skipped, they emit a `findings_only_offline` finding describing what they would have checked.

---

## Counter-example 9: `--fix` deletes files

**Symptom.** Doctor finds a stale lock file. `--fix` calls `unlink()`. Per AGENTS.md "RULE NUMBER 1: NO FILE DELETION" the project's policy is violated.

**Polish Bar item failed:** "No file deletion."

**Lift:** Renaming a stale lock to `.doctor/runs/<id>/quarantine/locks/<basename>` is the doctor's "delete" semantics. The user reviews the quarantine periodically; deletion is their decision, not the doctor's. The `Op` enum has no `DeletePath` variant under `--fix`.

---

## Counter-example 10: Concurrency causes torn writes

**Symptom.** Two terminals run `<tool> doctor --fix` simultaneously. Both report success but the target state file is corrupted (interleaved bytes).

**Diagnosis.** No advisory lock. Both processes wrote to the same temp+rename pair, which races.

**Polish Bar item failed:** "Concurrency-safe."

**Lift:** `mutate()` acquires a per-path advisory lock (`fs2`/`fd-lock` Rust, `syscall.Flock` Go, `portalocker`/`fcntl` Python, `proper-lockfile` TS) before any read or write. If the lock is unavailable, exit 5 (concurrency_lost) with a finding identifying the holder when discoverable.

---

## The pattern

Every counter-example here would have been caught by Phase 5's safety harness. That's the point of Phase 5 — it's the gate between "code looks plausible" and "code is fit for an agent to run unsupervised in a sandbox."
