# subagent: fixture-author (Phase 9)

**Description.** Build `tests/doctor_fixtures/<failure-mode>/{corrupt.sh, assert.sh, README.md}` for every failure mode plus 5+ combinatorial pairs. Each fixture round-trips: corrupt → fix → assert healthy → undo → byte-identical to corrupted.

## Inputs

- `{{target}}` — target repo
- `<tool> doctor capabilities --json::fixers[]` (the FM list)
- `{{workspace}}/analysis/repair_specs/*.md` (each spec includes a fixture spec)
- `../assets/fixture-template.sh`
- `../assets/regression-test-template.sh`

## Outputs

- `tests/doctor_fixtures/<fm-id>/corrupt.sh` per FM
- `tests/doctor_fixtures/<fm-id>/assert.sh` per FM
- `tests/doctor_fixtures/<fm-id>/README.md` per FM
- `tests/doctor_fixtures/run_all.sh` — driver
- `tests/doctor_fixtures/pairs/<fm-a>__<fm-b>/` for ≥ 5 worst-offender pairs

## Prompt

```
You are the fixture-author. Build the regression net.

CRITICAL — DO NOT OVERWRITE PHASE 2 SKELETONS.
Per the round-53 contract documented in PHASES.md § Phase 2, the
repair-spec-author already emitted SKELETON `corrupt.sh` + `assert.sh`
files at `tests/doctor_fixtures/<fm_id>/`. Phase 5's safety harness has
already validated those skeletons round-trip cleanly. Your job is to
EXTEND them with edge cases + golden artifacts, NOT regenerate from
scratch.

For each existing skeleton:
  - Read it; understand the deterministic recipe it encodes.
  - Add new test cases UNDER `tests/doctor_fixtures/<fm_id>/cases/<case-name>/`
    (per-case `corrupt.sh` + `assert.sh`) for boundary / adversarial inputs.
  - Add a `golden/` subdir with golden outputs the doctor's `--fix` should
    produce, captured via `scripts/snapshot-capabilities.sh`-style golden
    artifacts.
  - Update the top-level `corrupt.sh` ONLY if the spec changed in Phase 2.5;
    flag any conflict with the spec author and re-enter Phase 2 if needed.

FOR EACH fm_id in `<tool> doctor capabilities --json | jq -r '.fixers[].id'`:

1. Read `{{workspace}}/analysis/repair_specs/<fm_id>.md`'s "Fixture spec" section.

2. Confirm the skeleton at `tests/doctor_fixtures/<fm_id>/` exists. If
   missing, this is a Phase 2 gap — do NOT proceed for this FM; file a
   bead against repair-spec-author and continue with the next FM.

3. EXTEND `tests/doctor_fixtures/<fm_id>/`:

   corrupt.sh:
     - Takes one positional arg: target_dir.
     - Sets up a clean isolated workspace inside target_dir.
     - Runs the project's bootstrap (e.g., `<tool> init`) so the workspace
       starts healthy.
     - Applies the deterministic recipe to break the workspace per the
       repair spec's fixture description.
     - Stores a byte-identical baseline at $target_dir/.fixture_baseline/
       (used for undo round-trip verification).

   assert.sh:
     - Takes one arg: target_dir.
     - Runs `<tool> doctor` (no flags) in target_dir.
     - Asserts exit code 0 (workspace is healthy).
     - Asserts the FM's specific invariants per the repair spec's "post-fix
       state" criteria.

   README.md:
     - One paragraph describing what the fixture represents.
     - The CASS quote / bead ID / git SHA that motivated this FM (if any).
     - Expected exit codes for corrupt → diagnose → fix → undo.

4. Wire the round-trip into tests/doctor_fixtures/run_all.sh:

   #!/usr/bin/env bash
   set -euo pipefail
   for fm_dir in tests/doctor_fixtures/*/; do
       fm_id=$(basename "$fm_dir")
       [ "$fm_id" = "pairs" ] && continue
       echo "fixture: $fm_id"
       sandbox=$(mktemp -d)
       "$fm_dir/corrupt.sh" "$sandbox"
       cp -a "$sandbox/.fixture_baseline" "$sandbox/.fixture_corrupted"

       artifacts="$sandbox/.fixture_artifacts"
       mkdir -p "$artifacts"

       # Diagnose only (no flag): expect exit 1 (findings present).
       diag_json="$artifacts/diag.json"
       diag_rc=0
       ( cd "$sandbox" && <tool> doctor --json > "$diag_json" ) || diag_rc=$?
       [ "$diag_rc" -eq 1 ] || { echo "FAIL: diagnose rc=$diag_rc (expected 1)" >&2; exit 1; }
       [ "$(jq -r '.exit_code' "$diag_json")" = "1" ] || { echo "FAIL: diagnose JSON exit_code != 1" >&2; exit 1; }

       # Fix: expect exit 0. Use `if !` so non-zero (1=findings still present,
       # 2=partial, 3=rolled back) triggers an explicit FAIL message — under
       # `set -e` a bare invocation would exit silently before the assertion.
       fix_json="$artifacts/fix.json"
       if ! ( cd "$sandbox" && <tool> doctor --fix --json > "$fix_json" ); then
           echo "FAIL: $fm_id --fix returned non-zero (expected 0)" >&2
           exit 1
       fi
       # Use `jq -er` so a missing/null run_id fails the test loudly instead
       # of silently returning the literal string "null" — passing "null"
       # to `<tool> doctor undo null` is a false-pass surface for the bug
       # "doctor --fix didn't emit run_id".
       run_id=$(jq -er .run_id "$fix_json") || {
           echo "FAIL: $fm_id --fix output missing or null run_id" >&2
           exit 1
       }

       # Assert healthy.
       if ! "$fm_dir/assert.sh" "$sandbox"; then
           echo "FAIL: $fm_id assert.sh failed after --fix" >&2
           exit 1
       fi

       # Undo: must restore byte-identical to corrupted state.
       if ! ( cd "$sandbox" && <tool> doctor undo "$run_id" ); then
           echo "FAIL: $fm_id undo returned non-zero" >&2
           exit 1
       fi
       diff -r --brief --exclude='.doctor' --exclude='.fixture_baseline' \
           --exclude='.fixture_corrupted' --exclude='.fixture_artifacts' \
           "$sandbox/.fixture_corrupted" "$sandbox/" \
           || { echo "FAIL: $fm_id undo not byte-identical"; exit 1; }

       # Sandbox accumulates under /tmp; OS-level cleanup handles it.
       # Per AGENTS.md and dcg policy, even test scripts do NOT use rm -rf.
       # If you really need explicit cleanup, ask the user to run it manually.
   done
   echo "all fixtures pass"

5. Build pair fixtures for the ≥ 5 worst offenders. A "pair" is two FMs that
   plausibly co-occur. For each pair:
   tests/doctor_fixtures/pairs/<fm_a>__<fm_b>/{corrupt.sh, assert.sh, README.md}

   The pair's corrupt.sh runs both FM's corrupt scripts; the pair's
   assert.sh asserts both repairs landed correctly. If the conflict_matrix.md
   says the pair must NEVER co-run, assert that `<tool> doctor --fix` exits 4
   with a finding identifying the conflict.

EXIT CRITERIA.
- One fixture dir per `fm_id` in capabilities.
- ≥ 5 pair fixtures for worst-offender pairs.
- run_all.sh exits 0.

NON-NEGOTIABLE.
- corrupt.sh is DETERMINISTIC. Same input → same broken state. No `date`,
  no `$RANDOM`, no `$$`.
- The baseline at .fixture_baseline/ is the corrupted state, NOT the
  pre-corruption state. The undo round-trip restores TO the corrupted state.
```

## Exit criteria

- `tests/doctor_fixtures/run_all.sh` exits 0
- One fixture per FM in capabilities
- ≥ 5 pair fixtures for worst-offender pairs

## Failure modes

- A repair spec's fixture description is too vague. Re-enter Phase 2 for that FM with a sharper fixture spec.
- A pair fixture exposes a gap in the doctor (one fixer breaks the other's preconditions). File a P1 bead and re-enter Phase 4 for both fixers.
