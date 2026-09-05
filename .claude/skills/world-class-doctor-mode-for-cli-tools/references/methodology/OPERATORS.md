# Cognitive Operators — Doctor-Mode Thinking Moves

Composable cognitive moves. Apply them to any failure mode, any error message, any flag-design decision. Each operator: a glyph, a name, a triggering question, the failure mode it surfaces, and the prompt module to dispatch. Operators deliberately overlap — a single fixer typically deserves four or five.

| Glyph | Name | Question | Failure mode it surfaces |
|-------|------|----------|-----------|
| `🩺` | Detect-Then-Fix | "Is the detector pure, or does it mutate?" | Detector with side effects → idempotence breaks |
| `🚪` | Single-Chokepoint | "Does every mutation flow through `mutate()`?" | Direct write bypasses backup + hash + actions.jsonl |
| `💾` | Backup-Before-Mutate | "Is the verbatim backup written and verified BEFORE the mutation begins?" | Mutation succeeds, backup fails, agent has no recovery |
| `↩` | Inverse-Pair | "Does this fix have a recorded inverse that's been tested?" | `--fix` lands changes that can't be undone |
| `🔁` | Idempotent-Twice | "If I run this fix twice, does the second run report `no_actions_taken`?" | Re-running the doctor compounds state changes |
| `⚡` | Crash-Mid-Fix | "If the process dies mid-fix, can the next run finish or cleanly abort?" | Torn writes; orphaned tempfiles |
| `🔒` | Lock-Or-Refuse | "If two doctors run at once, does one refuse with exit 5?" | Concurrent corruption |
| `🧪` | Fixture-Pinned | "Is there a fixture that reproduces the broken state, and a test that asserts repair?" | Future regressions go unnoticed |
| `🛡` | Refuse-On-Unsafe | "If state is unsafe (out-of-scope write, schema unknown, network required offline), does doctor exit 4 (`refused_unsafe`) with a precise reason and a safe alternative? (Lock-held is handled by Lock-Or-Refuse → exit 5.)" | Best-effort behavior in unsafe state |
| `🪧` | Stdout-Data-Stderr-Diag | "Does `<tool> doctor --json | jq …` work without grep-filtering log lines?" | JSON output unparseable |
| `📜` | Self-Describing | "Does `<tool> doctor capabilities --json` exist and pin the contract?" | Agent has no machine-readable contract |
| `📖` | In-Tool-Docs | "Does `<tool> doctor robot-docs` make external lookup unnecessary?" | Agent must search for docs |
| `🚦` | Exit-Code-Dictionary | "Are non-zero exits a documented dictionary, not ad-hoc?" | Agent can't pattern-match on exit code |
| `🩹` | Error-Names-The-Fix | "Does this finding name the exact flag/command that resolves it?" | Agent has to read source to know what to do |
| `🆔` | Stable-Run-Id | "Does every run get a stable, content-addressed handle?" | Reruns can't be correlated; `undo` is fragile |
| `📦` | Verbatim-Backup | "Is the backup the file as-was, byte-identical, with permissions and mtime preserved?" | Restore breaks downstream tools that key off mode/mtime |
| `🔢` | Hash-Witnessed | "Are before/after hashes recorded in `actions.jsonl` for every mutation?" | Drift detection broken; undo can't validate |
| `🌐` | Offline-By-Default | "Does this detector require network? If yes, is it gated on `--online`?" | Hangs in sandbox; defeats CI |
| `🪞` | Mega-Command | "Can three round-trips collapse into one `--robot-triage` call?" | Wastes agent round-trips |
| `🗺` | Bounded-Blast-Radius | "Does `--dry-run` print the worst-case write set, and is that set a strict subset of `write_scopes`?" | Doctor reaches outside its declared scope |
| `🪟` | Provenance-Tagged | "Does this cached/derived value carry `live \| fallback \| unavailable`?" (Axiom 17) | Stale value rendered as fresh; agent acts on outdated data |
| `🔄` | Bidirectional-Coverage | "Does this detector have a fixture, and does this fixture exercise a detector?" (Axiom 18) | Theoretical detector / dead fixture |
| `📐` | Cardinality-Disclosed | "How many paths does this fixer write? Is that bounded and disclosed?" (Axiom 19) | Fixer goes berserk; agent unable to plan blast-radius |
| `🚧` | Refuse-As-Feature | "Is this refusal precise, with a named precondition + safe alternative?" (Axiom 22) | Best-effort proceeding when state is unsafe |
| `🔬` | Action-Trail-Auditable | "Could a fresh agent reconstruct what happened from `actions.jsonl` alone?" (Axiom 23) | Behavior depends on source-code reading; not trustable for unsupervised use |
| `⏳` | Decay-Aware | "When was this fixer last invoked? Is it a candidate for retirement?" (Axiom 21) | Doctor accumulates dead detectors; runtime cost grows |
| `🌌` | Closed-Contract | "Is every JSON field, exit code, and flag of this surface declared in `capabilities --json`?" (Axiom 20) | Agent encounters undocumented surface; can't predict behavior |

---

## Operator prompt modules

Each operator has a prompt module — a paragraph the calling agent inserts into a Phase 4/7 review prompt to make the operator concrete.

### `🩺 Detect-Then-Fix`

> Inspect every detector function in the doctor module. Confirm each is pure: it reads disk, in-memory state, env vars, but it never writes anywhere except an in-memory log. If you find a detector that writes (e.g. memoizes a result to disk, normalizes whitespace, "fixes" a malformed-but-readable record), that's a violation. Refactor: move the write into the paired fixer, route it through `mutate()`. The detector returns `Finding | None`; the runtime decides whether to invoke the fixer based on `--fix`.

### `🚪 Single-Chokepoint`

> Run `scripts/validate-doctor.sh`. For every match it reports, open the file:line and confirm the write goes through `mutate()`. If it doesn't, refactor. Common offenders: ad-hoc `std::fs::write` for "small status files", `os.WriteFile` for "just a symlink update", `fs.writeFileSync` for "the cleanup script". Every disk write — yes, even one byte — goes through `mutate()`.

### `💾 Backup-Before-Mutate`

> Read `mutate()`'s implementation. Confirm: (1) before_hash is computed BEFORE any planning step that could fail; (2) the verbatim backup is written, then `cmp -s` between live file and backup is asserted; only AFTER that assertion does the mutation begin. If the order is wrong, a precondition failure between read and backup leaves a "we read but didn't back up" hole. Test by injecting a fault between read and backup: the next run should report the failure cleanly, with no mutation applied and no actions.jsonl line.

### `↩ Inverse-Pair`

> For each fixer in `capabilities --json::fixers[]`, find the corresponding undo path. Verify: `corrupt → fix → undo → cmp -s` returns 0. If the fix touched bytes outside its declared diff range (e.g., re-formatted unrelated JSON), the undo can't be byte-identical — fix the fixer's diff range, not the undo.

### `🔁 Idempotent-Twice`

> Run `<tool> doctor --fix; <tool> doctor --fix` against every FM fixture. Second invocation must report `actions_taken: 0`. If the second run reports any non-zero count, the detector is dirty (mutating a side-channel) or the fixer is non-idempotent. Fix: detector must be pure; fixer must short-circuit when detector returns None.

### `⚡ Crash-Mid-Fix`

> Run `verify-crash-recovery.sh` against every fixer at K = {1, 5, 25, 125} ms. After each kill, assert: no orphan `.tmp.<pid>` files in any path under `write_scopes`; the project's lock file (if any) is releasable; the next `<tool> doctor` invocation either completes the partial fix or aborts cleanly with exit 4 and a finding pointing at the unfinished `actions.jsonl` line.

### `🔒 Lock-Or-Refuse`

> Trace every entry into `mutate()`. The first thing it must do is acquire a per-path advisory lock. If the lock is unavailable for K seconds (default 5 s), refuse with exit 5 and a finding `{reason: "lock_held", holder_pid: N}`. Use `fs2`/`fd-lock` Rust, `syscall.Flock` Go, `portalocker`/`fcntl` Python, `proper-lockfile` TS. Cross-platform note: Windows requires `LockFileEx` semantics; the wrapper crate handles this.

### `🧪 Fixture-Pinned`

> For every entry in `capabilities --json::fixers[]`, assert `tests/doctor_fixtures/<id>/{corrupt.sh, assert.sh}` exists. Run `tests/doctor_fixtures/run_all.sh`. Every fixture must round-trip: corrupt → fix → assert → undo → cmp-strict. CI fails on any missing fixture or any failed round-trip.

### `🛡 Refuse-On-Unsafe`

> Inspect every code path that returns exit 4. Confirm: (a) the finding has a precise reason (not just "unsafe"); (b) the finding names a safe alternative or follow-up command; (c) the doctor refuses BEFORE any mutation has begun (no actions.jsonl line, no backup). If exit 4 ever fires AFTER a partial mutation, that's a different exit code (3 = fix_failed_rolled_back).

### `🪧 Stdout-Data-Stderr-Diag`

> Run `<tool> doctor --json 2> /dev/null | jq .`. Output must parse cleanly. Run `<tool> doctor --json > /tmp/data.json 2> /tmp/log.txt`; assert `/tmp/data.json` is valid JSON and contains zero ANSI escapes. Progress lines on stderr are fine; data on stderr is a violation; ANSI on stdout is a violation.

### `📜 Self-Describing`

> Confirm `<tool> doctor capabilities --json` returns: `schema_version`, `tool_version`, `doctor_contract_version`, `subsystems`, `detectors[]`, `fixers[]`, `exit_codes`, `env_vars`, `write_scopes`, `run_artifact_schema`. Run `verify-capabilities.sh` to assert every declared detector and fixer is invocable.

### `📖 In-Tool-Docs`

> `<tool> doctor robot-docs` must include: command list, exit-code dictionary, schema_version, every flag, examples for the canonical happy path, examples for the canonical broken path, AND a "things this doctor will NEVER do" negative-space spec. The negative-space spec is what makes an agent willing to run unsupervised.

### `🚦 Exit-Code-Dictionary`

> Audit every `return Err(...)`, `os.Exit(...)`, `process.exit(...)`, `sys.exit(...)`. Each non-zero exit must map to a documented entry in `capabilities --json::exit_codes`. If you find an exit that doesn't map, either add the entry or change the exit code to one that does.

### `🩹 Error-Names-The-Fix`

> Read every error message that goes to stderr (under `--robot`, also every `error.message` in the JSON wrapper). Each must answer: WHAT failed, WHERE (file:line / row / key), and WHICH FLAG fixes it. "see --help" alone is a fail. The remediation field in JSON findings is the structured equivalent.

### `🆔 Stable-Run-Id`

> Run-id MUST be `sha256(target_sha + iso8601_utc_seconds)[..6]`. Two concurrent runs in the same second naturally collide → second one bumps to next second. Verify: kill the doctor mid-run, restart it within the same second, confirm a different run-id is generated.

### `📦 Verbatim-Backup`

> Compare backup byte-for-byte against the live file at the moment of backup. Permissions and mtime preserved (`stat -c '%a %Y' backup live` should match). For DB rows, the backup is a `pg_dump`/`sqlite3 .dump` of affected rows with column types, NOT a serialized JSON projection.

### `🔢 Hash-Witnessed`

> For every line in `actions.jsonl`, both `before_hash` and `after_hash` must be present and SHA-256. Verify: `jq -r '.before_hash, .after_hash' actions.jsonl | grep -v 'sha256:'` is empty. The `undo` path uses `before_hash` to detect drift between backup and current state.

### `🌐 Offline-By-Default`

> Inspect every detector and fixer for network calls (HTTP clients, DNS lookups, socket connects beyond the Unix-socket the project itself owns). Each must be marked `online_required: true` in `capabilities --json` AND skipped unless `--online` is set. Tested by running the doctor in `unshare -rn` (Linux network namespace) — must succeed.

### `🪞 Mega-Command`

> Build `--robot-triage` returning `{summary, findings, actions_planned, recommended_command, capabilities_url}` in a single call. Without this, the agent's typical workflow is `--json` → `capabilities --json` → `--explain` (3 round-trips). The mega-command collapses to 1.

### `🗺 Bounded-Blast-Radius`

> Run `<tool> doctor --dry-run --fix` against a multi-FM fixture. Assert: every path printed in the dry-run is under one of `capabilities::write_scopes`. Assert the union of all `fixers[*].writes_to` is a subset of `write_scopes`. CI fails on any out-of-scope write.

---

## Composition cheat-sheet

When a single failure surfaces multiple operator violations, apply in this order. Each downstream operator assumes upstream is met.

1. `🚪 Single-Chokepoint` (must be first — every other operator presumes `mutate()` is the only writer)
2. `🩺 Detect-Then-Fix` (purify detectors)
3. `💾 Backup-Before-Mutate` + `📦 Verbatim-Backup` + `🔢 Hash-Witnessed` (the backup invariants)
4. `🔒 Lock-Or-Refuse` (acquire lock at `mutate()` entry)
5. `↩ Inverse-Pair` + `🆔 Stable-Run-Id` (the undo invariants)
6. `🔁 Idempotent-Twice` (depends on detector purity)
7. `⚡ Crash-Mid-Fix` (depends on atomic writes inside `mutate()`)
8. `🛡 Refuse-On-Unsafe` (precondition gating)
9. `🌐 Offline-By-Default` (network gating)
10. `🪧 Stdout-Data-Stderr-Diag` (output discipline)
11. `🚦 Exit-Code-Dictionary` + `🩹 Error-Names-The-Fix` (agent contract)
12. `📜 Self-Describing` + `📖 In-Tool-Docs` + `🪞 Mega-Command` (discoverability)
13. `🧪 Fixture-Pinned` + `🗺 Bounded-Blast-Radius` (regression net)

The first cohort (1–7) is the load-bearing data-safety stack. The second cohort (8–10) is the runtime contract. The third cohort (11–13) is the agent-ergonomic shell.
