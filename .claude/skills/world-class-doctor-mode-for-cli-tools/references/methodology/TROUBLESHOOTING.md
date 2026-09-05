# Troubleshooting

Failure mode catalog with recovery scripts. Indexed by symptom; each row links to the operator that catches it and the script that verifies the fix.

| Symptom | Root cause | Recovery |
|---------|------------|----------|
| Phase 1 inventory has < 5 FMs for a non-trivial CLI | Subsystem partition too coarse; bug-tracker scrape skipped | Re-run `subagents/archaeologist.md` with broader subsystem list. Add `git log --grep` mining and `br ready --json`/`gh issue list --json` mining. |
| Phase 4 implementer wrote a fixer that bypasses `mutate()` | Implementer didn't read MUTATE-CHOKEPOINT.md | Hard reject. Add to Phase 7 fresh-eyes prompt 3. Add code-search test gate (`scripts/validate-doctor.sh`). |
| Phase 5 reversibility test fails on one fixer | Fixer is not byte-identical reversible (e.g., reformats JSON it touches) | Restrict the diff to the minimal byte range. The fixer must not touch unrelated bytes. |
| Phase 5 idempotence test fails | Fixer's detector is dirty (mutating a side-channel) | Detector must be pure. Move the side-channel write into `mutate()`. |
| Phase 5 crash-recovery test leaves orphan `.tmp.<pid>` | Atomic rename not implemented | Use `tempfile::NamedTempFile` / `os.replace` / `fs.renameSync`. Cross-FS rename is NOT atomic — temp file must be in the same dir as target. |
| Phase 6 `capabilities --json` exists but lies | Schema drifts from reality | `scripts/verify-capabilities.sh` round-trips capabilities → invokes each declared detector → asserts they exist. Auto-generate capabilities from the registry. |
| Phase 6 score regression > 50 on a single fixer between passes | Side-effect of unrelated change in target repo | **Hard stop**. Diagnose root cause. Cite file:line in `regression_alerts.md`. Either revert or ack with a written reason. |
| Phase 7 fresh-eyes never goes quiet | Loop touching cosmetic surfaces | Tighten "trivial change" definition: only typo / whitespace counts. Rephrasing IS a change. |
| Phase 9 fixture has no test | Fixture-author wrote corrupter but didn't pair the assertion | Phase 9 isn't done until every fixture has a test asserting the round-trip. |
| Phase 10 cold prober gets stuck on canonical task | Real intent-inference gap, not a Phase 3 oversight | File as P0 bead for next pass; don't mark Phase 10 complete. |
| `<tool> doctor --json` mixes log lines and JSON | stdout/stderr split violation | Audit the logger configuration. Force-route progress to stderr. Score 0 on agent_ergonomics. |
| Doctor hangs in a sandbox | Detector requires network without `--online` | Mark the detector `online_required: true`. Default `--online=false`. Skip with `findings_only_offline`. |
| `<tool> doctor` panics on `--help` after some subcommand | Bug in the help-text generator | This IS a finding — score `agent_intuitiveness=0`, file P0 bead. |
| Tool prints to stdout AND stderr for the same data | Stdout/stderr split violation | Score 0 on agent_ergonomics; refactor logger. |
| `validate-doctor.sh` reports false positives in test code | Validator pattern over-matches | Add precise allow-list entry with rationale. Tests typically need to call destructive primitives in cleanup; that's OK as long as it's clearly in test code. |
| `validate-doctor.sh` reports false positives in error message strings | Pattern matched on `"git reset --hard"` inside a help-text string | Add allow-list for string literals containing the pattern adjacent to "NEVER do" or "would NEVER" or "robot-docs". |
| Two implementers race on the same file | Missing Agent Mail file reservation | Acquire reservation before edit. Thread id `doctor-<pass>-<phase>-<subsystem>`. |
| The project's existing build hook conflicts with doctor's writes | Pre-commit formatter touches `.doctor/` files | Add `.doctor/` to formatter's ignore list and `.gitignore`. |
| `verify-crash-recovery.sh` fails at K=125ms | A path in the fixer doesn't have an atomic boundary | Audit the path; add a temp+rename or DB transaction. Re-test. |
| `verify-concurrency.sh` reports both processes succeeded | No advisory lock at `mutate()` entry | Acquire `fs2`/`fd-lock` (Rust), `syscall.Flock` (Go), `portalocker` (Python), `proper-lockfile` (TS). |
| `<tool> doctor capabilities --json` lacks `schema_version` | Schema field omitted | Add `schema_version: "1.0"` at top level. |
| `--robot-triage` returns an error code that's not in the dictionary | Error path skipped capability registration | Add the missing exit code to `capabilities --json::exit_codes`. |
| Run-id collides with a previous run in the same second | Determinism feature working as intended | Bump the seconds counter. Run-id is `sha256(target_sha + iso8601_utc_seconds)[..6]` — collisions are deterministic. Wait for the next second. |
| `doctor undo latest` resolves to the wrong run | Symlink update wasn't atomic | Check that the symlink update goes through `Op::SymlinkAtomic` (symlink to temp + rename). |
| `health` takes longer than 200 ms | A detector classified as "fast-path" is actually expensive | Move to the regular detector list. Mark `estimated_cost_ms` honestly. |
| The user accidentally ran `doctor --fix` on a project they didn't mean to fix | No way to "preview before commit" | Always offer `--dry-run --fix` first. Make `--fix` print a "this will write to: ..." banner before executing. (Optional enhancement; the agent default has been to assume the user knows what they're doing — for human users, an interactive confirmation might be appropriate when stdout IS a TTY.) |
| jsm not installed but a referenced skill is missing | Helper-skill fallback path | The pipeline degrades gracefully. Note in `phase0_skill_inventory.json` and proceed with the inline fallback in [SKILL-FALLBACKS.md](SKILL-FALLBACKS.md). |
| Test suite fails because the fixture's `corrupt.sh` is non-deterministic | Fixture used `$RANDOM`, `$(date)`, `$$`, etc. | Replace with deterministic seed values. Fixtures must reproduce the same broken state on every machine. |

For a problem not on this list, run `<tool> doctor --explain <finding-id>` if a finding ID is involved, or open the workspace's `manifest.json` and `safety_harness.jsonl` for forensic context.
