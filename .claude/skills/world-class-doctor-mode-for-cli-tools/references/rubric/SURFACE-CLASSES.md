# Per-Class Scoring Guidance

The ten-dimension rubric applies to every scored item, but each item's *class* changes which dimensions are load-bearing. This file says which dimensions matter most for each class and what evidence to require.

## detector

A pure function that examines state and returns `Finding | None`. Detectors NEVER mutate.

**Heavy dimensions:** `agent_intuitiveness`, `diagnostic_specificity`, `observability`.
**Lighter dimensions:** `data_safety`, `reversibility`, `idempotence` (these mostly score N/A — a pure function trivially satisfies them).

**Required evidence at ≥ 750:**
- Source location (`file:line`).
- A `--explain <finding-id>` output showing exact bytes / row / line that triggered.
- A test that exercises the detector against the corresponding fixture and asserts the finding fires.

## fixer

A function that mutates state via `mutate()`. Returns `FixResult { actions_planned, actions_taken }`.

**Heavy dimensions:** `data_safety`, `idempotence`, `reversibility`, `blast_radius_containment`, `test_coverage_of_repair`.
**Lighter dimensions:** `agent_intuitiveness` (intuitiveness is delegated to the parent verb).

**Required evidence at ≥ 750:**
- Source location of the fixer.
- The `mutate()` audit (`scripts/validate-doctor.sh`) exits 0.
- The five Phase-5 tests pass for this fixer.
- The fixture exists and round-trips.

## verb (subcommand)

A top-level subcommand (`diagnose`, `fix`, `undo`, `explain`, `capabilities`, `health`, `robot-docs`, `gc`, `ls`).

**Heavy dimensions:** `agent_intuitiveness`, `agent_ergonomics`, `observability`, `diagnostic_specificity`.
**Lighter dimensions:** `idempotence` (only meaningful for `fix` and `undo`), `data_safety` (only meaningful for `fix`, `undo`, `gc`).

**Required evidence at ≥ 750:**
- `--help` text.
- `--json` schema (linked from `capabilities --json`).
- Exit-code dictionary entry.

## flag

A single CLI flag (`--json`, `--robot`, `--fix`, `--dry-run`, `--only`, …).

**Heavy dimensions:** `agent_intuitiveness`, `agent_ergonomics`.
**Lighter dimensions:** rest mostly N/A.

**Required evidence at ≥ 750:**
- `--help` line cited.
- A test that asserts the flag has the documented effect (or is consumed and forwarded as documented).

## artifact (one of `report.json`, `actions.jsonl`, `scorecard.json`, `capabilities --json`, …)

**Heavy dimensions:** `agent_ergonomics`, `observability`, `test_coverage_of_repair` (schema-pinned tests).
**Lighter dimensions:** `agent_intuitiveness` (delegated to verb).

**Required evidence at ≥ 750:**
- `schema_version` field present.
- A schema file (JSON Schema or equivalent) referenced from `capabilities --json::report_schema`.
- A round-trip test that emits an artifact and parses it back.

## fixture

A reproducibly-broken state in `tests/doctor_fixtures/<failure-mode>/`.

**Heavy dimensions:** `test_coverage_of_repair`, `reversibility`, `idempotence`.
**Lighter dimensions:** `agent_intuitiveness` (N/A — fixtures aren't agent-facing).

**Required evidence at ≥ 750:**
- `corrupt.sh` deterministically reproduces the broken state.
- `assert.sh` returns 0 only when the post-fix state is healthy.
- Round-trip (corrupt → fix → assert → undo → byte-identical) passes.

## capability declaration

An entry in `capabilities --json::detectors[*]` or `fixers[*]`.

**Heavy dimensions:** `agent_ergonomics`, `diagnostic_specificity`, `test_coverage_of_repair`.

**Required evidence at ≥ 750:**
- The declared item is invocable (`scripts/verify-capabilities.sh` round-trips).
- All preconditions are documented.
- `writes_to` is a strict subset of `write_scopes`.

## error message

Any error printed to stderr by the doctor.

**Heavy dimensions:** `agent_intuitiveness`, `agent_ergonomics`, `diagnostic_specificity`.

**Required evidence at ≥ 750:**
- Names what failed, where (file:line / key= / row+table), and **the exact flag/command that fixes it**.
- Has a "did you mean" hint for common typos / mis-orderings if applicable.
