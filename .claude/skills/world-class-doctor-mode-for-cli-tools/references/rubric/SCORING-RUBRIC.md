# Ten-Dimension Scoring Rubric

Every scored item — each detector, each fixer, each verb, each emitted artifact field — gets 0–1000 across each of the ten dimensions below. Anchors at 0 / 250 / 500 / 750 / 1000 are concrete; intermediate values interpolate. Scores ≥ 700 require evidence cited in the per-item record (file:line, fixture path + test name); `scripts/scorecard.py validate <workspace>` rejects unsourced high scores.

The aggregate score per failure mode is the **median** across the ten dimensions for that FM. The aggregate per-tool score is the per-FM median weighted by `frequency × blast_radius` (see [PRIORITY-FORMULA.md](PRIORITY-FORMULA.md)).

---

## 1. agent_intuitiveness — "first command an agent guesses works (or redirects usefully)"

| Score | Anchor |
|-------|--------|
| 0 | `<tool> doctor` errors out on a healthy workspace, or hangs, or launches a TUI that blocks an agent. |
| 250 | `<tool> doctor` runs but the only output is "see --help"; the agent has no information to act on. |
| 500 | `<tool> doctor` produces a human-readable summary; an agent CAN act after parsing prose. `--json` exists but isn't mentioned in `--help`. |
| 750 | `<tool> doctor`, `<tool> doctor --json`, `<tool> doctor --help`, `<tool> doctor capabilities` all work. `--help` mentions `--json` and `capabilities`. |
| 1000 | The first command an agent guesses (`<tool> doctor`, `<tool> doctor --json`, or `<tool> doctor --help`) returns useful output. Common typos (`<tool> dr`, `<tool> doc`, `<tool> doctore`) emit a "did you mean: doctor" hint with the corrected command. The error from any wrong invocation cites the exact correct flag. |

**Evidence required for ≥ 750:** transcript or file:line citation of the help text + the typo handler.

---

## 2. agent_ergonomics — "stable JSON, exit codes, stdout/stderr discipline, no TTY assumptions"

| Score | Anchor |
|-------|--------|
| 0 | stdout mixes log lines and data; exit codes are random; ANSI escapes in `--json`; non-TTY launches a TUI. |
| 250 | `--json` exists but stdout still has log noise; exit codes don't match documentation. |
| 500 | stdout is data, stderr is progress, ANSI is suppressed on non-TTY, but `NO_COLOR` is ignored or `--robot` doesn't exist. |
| 750 | stdout/stderr split clean; `--json` and `--robot` work; `NO_COLOR`, `CI`, `TERM=dumb` honored; `--no-color` and `--no-progress` available. |
| 1000 | All of 750 + `schema_version` in JSON output + `--robot` adds the structured error wrapper + macros (`--robot-triage`) collapse round-trips + `<tool> doctor --json | jq` works without grep filtering. |

**Evidence:** schema file + a one-line test that asserts `<tool> doctor --json | jq -e .schema_version` exits 0.

---

## 3. automation_degree — "what fraction can be fixed without a human"

| Score | Anchor |
|-------|--------|
| 0 | `doctor` is read-only; no `--fix`. Repair requires a human running ad-hoc commands. |
| 250 | A `--fix` flag exists but only for one or two trivial findings; everything else still requires manual remediation. |
| 500 | `--fix` covers ~50 % of detected findings; the rest emit a remediation hint but require human action. |
| 750 | `--fix` covers ~85 % of P0/P1 findings; remaining findings are genuinely outside the doctor's scope (e.g., need user creds). |
| 1000 | `--fix` covers ≥ 95 % of P0/P1 findings; the few exceptions are explicitly enumerated in `capabilities --json::manual_remediations` with cited reasons (e.g., "requires user OAuth — gated behind `--online`"). |

**Evidence:** `capabilities --json::fixers` cardinality vs. `capabilities --json::detectors` cardinality, plus a list of manual exceptions.

---

## 4. data_safety — "every mutation backs up first, verbatim"

| Score | Anchor |
|-------|--------|
| 0 | `--fix` writes in place. No backups. No way to recover if it goes wrong. |
| 250 | Backups exist but only for some files; some fixers bypass the chokepoint. |
| 500 | All fixers back up via the chokepoint, but backups are not byte-identical (e.g., reformatted) or don't preserve permissions. |
| 750 | All fixers back up byte-identically through `mutate()`; permissions and mtime preserved; `cmp -s` between live file and backup at the moment of backup succeeds. |
| 1000 | All of 750 + `before_hash`/`after_hash` recorded in `actions.jsonl` for every mutation + DB rows backed up as `pg_dump`/`sqlite3 .dump` of affected rows + the universal safety envelope (no-delete, atomic-write, scoped-paths) is enforced by `scripts/validate-doctor.sh` in CI. |

**Evidence:** `actions.jsonl` line schema + a test that calls `mutate()` and asserts the backup exists, has matching hash, and `cmp -s` succeeds.

---

## 5. idempotence — "run twice = run once"

| Score | Anchor |
|-------|--------|
| 0 | Second `--fix` invocation re-applies the fix or corrupts state. |
| 250 | Second `--fix` reports "no changes" but actually wrote files (e.g., re-stamps a header). |
| 500 | Second `--fix` is a no-op for most fixers but a few are non-idempotent. |
| 750 | All fixers are idempotent: second `--fix` writes nothing and exits 0 with `actions_taken: 0`. |
| 1000 | All of 750 + a CI gate that runs `verify-idempotence.sh` against every failure-mode fixture in `tests/doctor_fixtures/` + any future non-idempotent change is caught. |

**Evidence:** `scripts/verify-idempotence.sh` exit 0 across the fixture suite.

---

## 6. reversibility — "every fix has an inverse; `doctor undo <run-id>` works byte-for-byte"

| Score | Anchor |
|-------|--------|
| 0 | No undo. Once `--fix` runs, the previous state is gone. |
| 250 | `undo` exists but only for some fixers; others are silently irreversible. |
| 500 | All fixers have an undo, but byte-identical restore isn't guaranteed (e.g., reformatting the JSON it touched). |
| 750 | `<tool> doctor undo <run-id>` restores byte-identically from `backups/`; verified by hash comparison. |
| 1000 | All of 750 + `undo.sh` is generated per run and is itself idempotent + concurrent `undo` is locked + `undo --strict` (default) refuses on hash mismatch + a CI gate runs `verify-undo.sh` against every fixture. |

**Evidence:** `scripts/verify-undo.sh` exit 0; the test asserts `cmp -s` between corrupted-baseline and post-undo state.

---

## 7. diagnostic_specificity — "findings cite exact location and the exact fix command"

| Score | Anchor |
|-------|--------|
| 0 | Finding messages are generic ("something is wrong with state"). |
| 250 | Findings name the subsystem but not the file or line. |
| 500 | Findings cite the file. The remediation is "see docs" or "see --help". |
| 750 | Findings cite `file:line` (or `key=` / row + table / json-pointer) AND the exact remediation command (`<tool> doctor --fix --only fm-...`). |
| 1000 | All of 750 + `<tool> doctor explain <finding-id>` expands the finding with full evidence: the queried code path, the exact bytes that triggered it, the SHA-256 hash of the offending state, and a copy-paste-ready fix command. |

**Evidence:** sample `--explain` output for one P0 + one P2 finding.

---

## 8. blast_radius_containment — "worst case is bounded and disclosed in dry-run"

| Score | Anchor |
|-------|--------|
| 0 | `--fix` could touch anywhere on the filesystem. No write-scope declaration. |
| 250 | Write-scope is implicit ("inside the project"). No `--dry-run`. |
| 500 | `capabilities --json::write_scopes` lists paths, but they're not enforced — `--fix` could still write outside. |
| 750 | `write_scopes` is enforced at runtime (the `mutate()` chokepoint refuses paths outside scope). `--dry-run --fix` prints every path that would be touched. |
| 1000 | All of 750 + the union of all `fixers[*].writes_to` is a strict subset of `write_scopes` + a Phase 7 fresh-eyes prompt checks for any code path that writes outside scope + a CI gate (`scripts/validate-doctor.sh`) fails the build if any disk write happens through a non-`mutate()` path. |

**Evidence:** `validate-doctor.sh` exit 0 on the latest commit + a sample `--dry-run --fix` output enumerating the write set.

---

## 9. observability — "structured logs, run-id, --explain, machine-parseable artifacts"

| Score | Anchor |
|-------|--------|
| 0 | No run-id, no artifacts, no logs to investigate after the fact. |
| 250 | A run-id exists but artifacts are unstructured prose. |
| 500 | `report.json` is emitted but has no schema_version; logs are noisy. |
| 750 | `.doctor/runs/<run-id>/` directory with `report.{json,md}`, `actions.jsonl`, `backups/`, `undo.sh` per run; symlink `latest`; `scorecard_history.jsonl` aggregate. |
| 1000 | All of 750 + `schema_version` in every JSON artifact + structured stderr (`-v`/`-vv`/`-vvv` levels) + `<tool> doctor explain <id>` and `<tool> doctor ls` work + every `mutate()` call records `started_at_ns`, `finished_at_ns`, `before_hash`, `after_hash`, `run_id`, `fixer_id`. |

**Evidence:** sample run directory + the schema URL in `capabilities --json`.

---

## 10. test_coverage_of_repair — "fixture reproduces broken state; test asserts repair"

| Score | Anchor |
|-------|--------|
| 0 | No fixtures. Repair is unverified. |
| 250 | A few ad-hoc tests touch some fixers; no systematic fixture suite. |
| 500 | `tests/doctor_fixtures/` exists with a fixture per ~50 % of failure modes. |
| 750 | `tests/doctor_fixtures/` has one fixture per failure mode; round-trip (corrupt → fix → assert healthy → undo → byte-identical) passes for each. |
| 1000 | All of 750 + ≥ 5 combinatorial-pair fixtures for the worst offenders + `tests/doctor_fixtures/run_all.sh` is wired into CI + Phase 9 ran clean + property tests (e.g., from `testing-metamorphic`) assert `fix(corrupt(x)) ≡ x` for every invariant. |

**Evidence:** `tests/doctor_fixtures/run_all.sh` exit 0; CI workflow file path.

---

## Aggregation

```
fm_score(fm) = median(dim_scores[fm][1..10])

aggregate_score(tool) =
    Σ_fm  fm_score(fm) × frequency_clamped(fm) × blast_radius(fm)
    ─────────────────────────────────────────────────────────────────
    Σ_fm                 frequency_clamped(fm) × blast_radius(fm)

frequency_clamped(fm) = clamp(frequency(fm), 0.5, 2.0)
```

Frequency is from CASS mining (number of times this FM was mentioned in the past 90 days of agent sessions) + bug-tracker count (open + recently-closed) + git-log mention count. Blast radius comes from `[PRIORITY-FORMULA.md](PRIORITY-FORMULA.md)`.

---

## Termination thresholds

The Phase 4/5/6/7 loop terminates when ALL of:

- Median uplift in the last pass < 25 points.
- No FM regressed > 50 points.
- Phase 4 produced no new top-N detector/fixer that wasn't a near-duplicate of one applied.
- Phase 7 fresh-eyes ran clean two times in a row (only trivial edits).
- The fixture suite round-trips for every fixture.

Hard stop: any single regression > 50 points blocks progress until the root cause is named and either reverted or explicitly acknowledged in `regression_alerts.md`.
