# Regression Test Patterns

For each rubric dimension, what a "good" regression test looks like, paste-ready (Bash / shell-agnostic) so it can be wired into CI regardless of the project's language.

Every applied recommendation lands a regression test in `tests/doctor_fixtures/<fm-id>/` (or in the project's existing test directory). Each test is named after the recommendation/finding ID. The test's exit 0 is the gate; the test's stderr describes the assertion that failed.

---

## agent_intuitiveness

```bash
# tests/doctor_fixtures/regression_help_text.sh
set -euo pipefail
help=$(<tool> doctor --help 2>&1)
echo "$help" | grep -q -- '--json'        || { echo "FAIL: --json not in --help"; exit 1; }
echo "$help" | grep -q -- 'capabilities'  || { echo "FAIL: capabilities not in --help"; exit 1; }
echo "$help" | grep -q -- 'robot-docs'    || { echo "FAIL: robot-docs not in --help"; exit 1; }
```

```bash
# tests/doctor_fixtures/regression_typo_hint.sh
out=$(<tool> doctore 2>&1 || true)
echo "$out" | grep -q 'did you mean: doctor' || { echo "FAIL: typo hint missing"; exit 1; }
```

## agent_ergonomics

```bash
# tests/doctor_fixtures/regression_stdout_data_only.sh
<tool> doctor --json > /tmp/stdout.txt 2> /tmp/stderr.txt
jq -e . < /tmp/stdout.txt > /dev/null || { echo "FAIL: stdout is not valid JSON"; exit 1; }
[ -s /tmp/stderr.txt ] || true   # progress on stderr is OK and expected
# stdout must contain ZERO ANSI escapes:
grep -q $'\x1b\[' /tmp/stdout.txt && { echo "FAIL: ANSI in --json stdout"; exit 1; } || true
```

```bash
# tests/doctor_fixtures/regression_no_color_honored.sh
NO_COLOR=1 <tool> doctor 2>&1 | grep -q $'\x1b\[' && { echo "FAIL: NO_COLOR ignored"; exit 1; } || true
```

## automation_degree

```bash
# tests/doctor_fixtures/regression_fix_coverage.sh
detectors=$(<tool> doctor capabilities --json | jq '.detectors | length')
fixers=$(<tool> doctor capabilities --json | jq '.fixers | length')
ratio=$(python3 -c "print($fixers / $detectors)")
python3 -c "import sys; sys.exit(0 if $ratio >= 0.85 else 1)" \
    || { echo "FAIL: automation ratio $ratio < 0.85"; exit 1; }
```

## data_safety

```bash
# tests/doctor_fixtures/regression_backup_byte_identical.sh
fixture_dir=$(mktemp -d)
./tests/doctor_fixtures/fm-jsonl-tombstone-drift/corrupt.sh "$fixture_dir"
cp -a "$fixture_dir" "$fixture_dir.baseline"
( cd "$fixture_dir" && <tool> doctor --fix > /tmp/fix.json )
run_id=$(jq -er .run_id /tmp/fix.json) || { echo "FAIL: --fix output missing run_id"; exit 1; }
backup_file="$fixture_dir/.doctor/runs/$run_id/backups/.beads/issues.jsonl"
baseline_file="$fixture_dir.baseline/.beads/issues.jsonl"
cmp -s "$backup_file" "$baseline_file" || { echo "FAIL: backup not byte-identical"; exit 1; }
```

## idempotence

```bash
# tests/doctor_fixtures/regression_idempotence.sh
fixture_dir=$(mktemp -d)
./tests/doctor_fixtures/fm-jsonl-tombstone-drift/corrupt.sh "$fixture_dir"
( cd "$fixture_dir" && <tool> doctor --fix > /tmp/run1.json )
( cd "$fixture_dir" && <tool> doctor --fix > /tmp/run2.json )
n=$(jq -r .summary.actions_taken /tmp/run2.json)
[ "$n" = "0" ] || { echo "FAIL: second run took $n actions"; exit 1; }
```

## reversibility

```bash
# tests/doctor_fixtures/regression_reversibility.sh
fixture_dir=$(mktemp -d)
./tests/doctor_fixtures/fm-jsonl-tombstone-drift/corrupt.sh "$fixture_dir"
cp -a "$fixture_dir" "$fixture_dir.baseline"
( cd "$fixture_dir" && <tool> doctor --fix > /tmp/fix.json )
run_id=$(jq -er .run_id /tmp/fix.json) || { echo "FAIL: --fix output missing run_id"; exit 1; }
( cd "$fixture_dir" && <tool> doctor undo "$run_id" )
# Use diff's --exclude to drop only the doctor's bookkeeping dir, then check
# diff's exit code directly. DON'T pipe through `grep -v 'Only in'` — that
# silently masks "file present in baseline but missing from target" and
# "file present in target but missing from baseline", both of which are real
# undo failures (per round-17 fix in assets/regression-test-template.sh).
diff -r --brief --exclude='.doctor' "$fixture_dir.baseline/.beads" "$fixture_dir/.beads" \
    || { echo "FAIL: undo not byte-identical"; exit 1; }
```

## diagnostic_specificity

```bash
# tests/doctor_fixtures/regression_finding_cites_remediation.sh
out=$(<tool> doctor --json | jq -r '.findings[] | .remediation.command')
[ -n "$out" ] || { echo "FAIL: findings have no remediation.command"; exit 1; }
echo "$out" | while read line; do
    echo "$line" | grep -q '^<tool> doctor' \
        || { echo "FAIL: remediation not paste-ready: $line"; exit 1; }
done
```

## blast_radius_containment

```bash
# tests/doctor_fixtures/regression_blast_radius.sh
write_scopes=$(<tool> doctor capabilities --json | jq -r '.write_scopes[]')
fixers_writes=$(<tool> doctor capabilities --json | jq -r '.fixers[].writes_to[]' | sort -u)
for path in $fixers_writes; do
    in_scope=false
    for scope in $write_scopes; do
        case "$path" in $scope*) in_scope=true; break ;; esac
    done
    $in_scope || { echo "FAIL: fixer writes to $path which is not in write_scopes"; exit 1; }
done
```

## observability

```bash
# tests/doctor_fixtures/regression_run_artifacts.sh
fixture_dir=$(mktemp -d)
./tests/doctor_fixtures/fm-jsonl-tombstone-drift/corrupt.sh "$fixture_dir"
( cd "$fixture_dir" && <tool> doctor --fix > /tmp/fix.json )
run_id=$(jq -er .run_id /tmp/fix.json) || { echo "FAIL: --fix output missing run_id"; exit 1; }
run_dir="$fixture_dir/.doctor/runs/$run_id"
for f in report.json report.md scorecard.json actions.jsonl undo.sh; do
    [ -f "$run_dir/$f" ] || { echo "FAIL: missing $f"; exit 1; }
done
[ -d "$run_dir/backups" ] || { echo "FAIL: missing backups/"; exit 1; }
[ -L "$fixture_dir/.doctor/latest" ] || { echo "FAIL: missing latest symlink"; exit 1; }
[ "$(readlink "$fixture_dir/.doctor/latest")" = "runs/$run_id" ] \
    || { echo "FAIL: latest symlink wrong target"; exit 1; }
```

## test_coverage_of_repair

```bash
# tests/doctor_fixtures/regression_every_fixer_has_fixture.sh
fixers=$(<tool> doctor capabilities --json | jq -r '.fixers[].id')
for fm in $fixers; do
    [ -d "tests/doctor_fixtures/$fm" ] \
        || { echo "FAIL: no fixture for $fm"; exit 1; }
    [ -x "tests/doctor_fixtures/$fm/corrupt.sh" ] \
        || { echo "FAIL: no corrupt.sh for $fm"; exit 1; }
    [ -x "tests/doctor_fixtures/$fm/assert.sh" ] \
        || { echo "FAIL: no assert.sh for $fm"; exit 1; }
done
```

---

These tests live in `tests/doctor_fixtures/`, are wired into the project's existing test runner (or a new `tests/doctor_fixtures/run_all.sh`), and run on every PR that touches doctor code. CI fails the build on any non-zero exit.
