# Polish Bar — Per-Dimension Verification Queries

Each Polish Bar item from SKILL.md, with the exact verification query (paste-ready) that asserts it's met. Use this in Phase 6 / 7 / 9. CI runs the queries on every PR that touches doctor code.

---

## Detect-then-fix

> Detectors are pure functions (no side effects, no `mutate()` calls). They return a finding list; the runtime decides whether `--fix` was passed.

**Query.** Code-search the doctor module for any detector that calls `mutate(`, `std::fs::write`, `os.WriteFile`, `fs.writeFileSync`, `os.replace`, etc.

```bash
# Rust example
rg -n 'fn detect_' src/doctor/ -A 30 \
  | rg -B 5 'mutate\(|std::fs::(write|remove|create|rename)' \
  && { echo "FAIL: detector mutates"; exit 1; } || true
```

The right shape is: detectors return `Result<Option<Finding>, _>`. The runtime collects all findings, then if `--fix` is set, dispatches each to its fixer.

---

## Single-chokepoint mutation

> Every disk write goes through `mutate(path, op)`. `mutate()` is the only writer under `--fix`.

**Query.** `scripts/validate-doctor.sh <target>` — see [MUTATE-CHOKEPOINT.md § The validator](MUTATE-CHOKEPOINT.md). Exits non-zero on any forbidden write outside `mutate()`.

---

## Backups before any mutation

> `mutate()` writes a verbatim backup before mutating. Backup must `cmp -s` byte-identically against the live file at the moment of backup.

**Query.** Each fixture's `tests/doctor_fixtures/<fm>/regression_backup_byte_identical.sh` (per-FM regression test, authored from the pattern at [REGRESSION-TEST-PATTERNS.md § data_safety](../rubric/REGRESSION-TEST-PATTERNS.md)).

---

## Reversible

> `<tool> doctor undo <run-id>` reads `actions.jsonl` in reverse, restores from `backups/`, verifies post-restore hash matches `before_hash`. Fails closed if any backup is missing.

**Query.** `scripts/verify-undo.sh fm-<id>` for every FM. CI gate.

---

## Idempotent

> `doctor --fix` then `doctor --fix` → second run reports `actions_taken: 0` and exit 0.

**Query.** `scripts/verify-idempotence.sh fm-<id>` for every FM. CI gate.

---

## Crash-recoverable

> `SIGKILL doctor` mid-fix → next run completes the partial fix or aborts cleanly. No torn writes; no orphaned `.tmp.<pid>` files; no stale lock.

**Query.** `scripts/verify-crash-recovery.sh fm-<id>` for every FM. Tests at K = {1, 5, 25, 125} ms (or via fault-injection points). CI gate.

---

## Concurrency-safe

> Two `doctor --fix` invocations on the same workspace → one wins via the project's existing lock primitive (or one we add); the other refuses with exit 5.

**Query.** `scripts/verify-concurrency.sh fm-<id>`. CI gate.

```bash
# Sketch:
( cd "$fixture" && <tool> doctor --fix ) &
( cd "$fixture" && <tool> doctor --fix ) &
wait
# Exactly one should have exit 0; the other exit 5.
```

---

## Read-only by default

> `doctor` (no flags) NEVER mutates. `--fix` is opt-in.

**Query.**

```bash
fixture=$(mktemp -d)
./tests/doctor_fixtures/fm-jsonl-tombstone-drift/corrupt.sh "$fixture"
hash_before=$(sha256sum "$fixture/.beads/issues.jsonl" | cut -d' ' -f1)
( cd "$fixture" && <tool> doctor )            # no --fix
hash_after=$(sha256sum "$fixture/.beads/issues.jsonl" | cut -d' ' -f1)
[ "$hash_before" = "$hash_after" ] || { echo "FAIL: doctor mutated without --fix"; exit 1; }
```

---

## Stable JSON schema

> `--json` and `--robot` outputs include `schema_version` and a stable field set.

**Query.**

```bash
<tool> doctor --json | jq -e '.schema_version' > /dev/null \
  || { echo "FAIL: no schema_version"; exit 1; }
<tool> doctor capabilities --json | jq -e '.schema_version' > /dev/null \
  || { echo "FAIL: capabilities has no schema_version"; exit 1; }
```

---

## Exit-code contract

> `0` healthy, `1` findings, `2` partial, `3` failed-rolled-back, `4` unsafe-refused, `5` concurrency, `6` online-required, `64` usage, `66` no-input, `73` cant-create, `74` io-error. All 11 documented in `capabilities --json::exit_codes` (canonical: [CLI-SURFACE.md § exit codes](CLI-SURFACE.md)).

**Query.**

```bash
codes=$(<tool> doctor capabilities --json | jq '.exit_codes | keys[]' -r | sort -n)
# Full canonical set per CLI-SURFACE.md § exit codes — every entry must be
# documented in capabilities --json. Missing any of these = scorecard 0
# on `agent_ergonomics`.
required="0 1 2 3 4 5 6 64 66 73 74"
for c in $required; do
    echo "$codes" | grep -q "^$c\$" || { echo "FAIL: exit code $c missing"; exit 1; }
done
```

---

## Stdout = data, stderr = progress

> All ANSI / spinners / progress bars go to stderr. Auto-disable on non-TTY, `NO_COLOR=1`, `--robot`, `--json`.

**Query.** See [REGRESSION-TEST-PATTERNS.md § agent_ergonomics](../rubric/REGRESSION-TEST-PATTERNS.md).

---

## Capabilities + robot-docs

> `<tool> doctor capabilities --json` returns version, contract, detectors, fixers, exit codes, env vars, run-artifact schema. `<tool> doctor robot-docs` prints the agent handbook.

**Query.** `scripts/verify-capabilities.sh` round-trips:

```bash
caps=$(<tool> doctor capabilities --json)
echo "$caps" | jq -e '.detectors | length > 0' || exit 1
echo "$caps" | jq -e '.fixers | length > 0' || exit 1
# Every declared detector is invocable:
for fm in $(echo "$caps" | jq -r '.detectors[].id'); do
    <tool> doctor --only "$fm" --json --quiet > /dev/null \
        || { echo "FAIL: detector $fm declared but not invocable"; exit 1; }
done
# robot-docs is non-empty and contains the canonical sections:
docs=$(<tool> doctor robot-docs)
echo "$docs" | grep -q 'EXIT CODES'     || { echo "FAIL: robot-docs missing exit codes"; exit 1; }
echo "$docs" | grep -q 'capabilities'   || { echo "FAIL: robot-docs missing capabilities pointer"; exit 1; }
echo "$docs" | grep -q 'NEVER do'       || { echo "FAIL: robot-docs missing negative-space spec"; exit 1; }
```

---

## Mega-command

> `<tool> doctor --robot-triage` returns `{summary, findings, actions_planned, recommended_command, capabilities_url}` in a single call.

**Query.**

```bash
out=$(<tool> doctor --robot-triage --json)
for f in summary findings actions_planned recommended_command capabilities_url; do
    echo "$out" | jq -e ".${f}" > /dev/null \
        || { echo "FAIL: --robot-triage missing $f"; exit 1; }
done
```

---

## Each fixer has a fixture

**Query.** See [REGRESSION-TEST-PATTERNS.md § test_coverage_of_repair](../rubric/REGRESSION-TEST-PATTERNS.md).

---

## Offline by default

> All detectors and fixers run with no network. Network is opt-in via `--online`.

**Query.**

```bash
# Run doctor in a network-isolated namespace and assert it succeeds.
unshare -rn -- <tool> doctor --json > /dev/null \
    || { echo "FAIL: doctor needs network without --online"; exit 1; }
# Detectors that require network must be marked:
<tool> doctor capabilities --json \
    | jq -e '.detectors[] | select(.online_required == true)' > /dev/null
```

---

## No destructive shell

> No `rm -rf`, `git reset --hard`, `git clean -fd`, `DROP TABLE`, `kubectl delete`. Equivalents implemented in code.

**Query.** Part of `scripts/validate-doctor.sh`. The validator greps the doctor module for the pattern set and refuses any match outside `mutate()` (where `mutate()` itself never uses `rm -rf` either).

---

## Composition cheat-sheet

If a single Polish Bar item fails, what to do:

| Failed item | First action |
|-------------|--------------|
| Detect-then-fix | Move all writes from detector body into a paired fixer. Rerun the validator. |
| Single-chokepoint | Identify every direct write; refactor through `mutate()`. Add a code-search test gate. |
| Backups | Audit `mutate()`'s order of operations; backup before any read of live state. |
| Reversible | Audit `undo` path: it must call `cp backup live` with NO transformation. |
| Idempotent | Make detector pure; make fixer skip when detector is None. |
| Crash-recoverable | Replace direct writes with temp + rename. Same-FS only. |
| Concurrency | Acquire advisory lock at `mutate()` entry. |
| Read-only by default | Every code path that runs without `--fix` must hit zero `mutate()` calls. |
| Stable JSON | Add `schema_version` to every JSON artifact. Pin schema in `capabilities`. |
| Exit codes | Audit error paths; add the missing codes; document in `capabilities`. |
| Stdout/stderr | Audit logger configuration; force-route progress to stderr. |
| Capabilities | Generate from registry, never hand-maintain. |
| Mega-command | Add `--robot-triage` that calls `diagnose` + plan + recommend in one pass. |
| Fixtures | Build fixture for every FM. |
| Offline | Mark network detectors `online_required: true`; gate behind `--online`. |
| No destructive shell | Replace `rm -rf` with a code-implemented quarantine via `Op::Rename`. |

If multiple items fail in the same code path, run the items in this order. Each downstream item assumes the upstream is met.
