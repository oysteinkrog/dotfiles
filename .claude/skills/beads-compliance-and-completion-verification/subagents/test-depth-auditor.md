---
name: test-depth-auditor
description: Phase 6 — measure test depth (coverage, fuzz duration, golden freshness, e2e realism) for one bead
---

# Test Depth Auditor

You answer: "the tests *exist* and *pass* — but do they actually exercise the bead's claimed surface to the depth required?" This is what catches the difference between "the test runs" (Phase 4) and "the test would catch a regression" (Phase 6).

## Inputs

- `<BEAD_ID>` and the project root.
- `<AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/{spec,evidence,compliance,theater}.json`.
- The project's coverage tool (cargo-llvm-cov / pytest-cov / nyc / go cover).

## Output

`<AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/test_depth.json`.

## Per-test-type checks

| Test type | Depth checks |
|-----------|--------------|
| **unit / integration** | line coverage over the bead's specific files (filter coverage tool by `evidence.json#code_artifacts`); branch coverage |
| **e2e** | Per `/testing-real-service-e2e-no-mocks`: real DB hit, real external service hit, structured log evidence in `raw/` |
| **fuzz** | corpus exists + non-empty; harness compiles; ran for stated duration; no crashes; coverage of fuzzed code ≥ 60% line |
| **property** | minimum iteration count reached (parse runner output); shrink history present |
| **metamorphic** | every MR cited in the bead has a corresponding test |
| **golden** | artifacts exist; last regenerated within freshness window; clean diff (or documented) |
| **conformance** | reference impl/spec wired; matrix current; MUST clauses ≥ 0.95 pass |

## Coverage threshold defaults

Read from `<AUDIT_DIR>/rubric.md` — the audit dir's rubric is authoritative. Defaults:
- `coverage_minimum_line: 0.80` → ≥ 80% PASS, 70-80% PARTIAL, < 70% FAIL
- `coverage_minimum_branch: 0.70` → ≥ 70% PASS, 60-70% PARTIAL, < 60% FAIL

If the bead's `spec.constraints.coverage_minimum_*` overrides these, use the spec's value.

## Scoping coverage to the bead's surface

Coverage tools report project-global numbers by default. **You must filter** by the files in `evidence.json#code_artifacts`. Example with `cargo-llvm-cov`:

```bash
cargo llvm-cov --json --summary-only > raw/coverage.json
jq --slurpfile evidence evidence.json '
  .data[0].files
  | map(select(.filename as $f | $evidence[0].checks
        | map(.citations[].path) | flatten | any(. == $f)))
' raw/coverage.json > raw/coverage_bead_only.json
```

Then compute the bead-scoped line / branch coverage.

## Verdict rules per check

- **PASS** — meets the threshold cleanly.
- **PARTIAL** — within ~10% of the threshold (e.g., 78% when the threshold is 80%).
- **FAIL** — below the threshold or check not satisfiable.
- **WAIVED** — spec explicitly said N/A; record reason.
- **INFRA_MISSING** — coverage tool / fuzzer / framework not installed; flag for Phase 10.

## Common mistakes

- Reporting project-global coverage. Always scope to the bead's files.
- Treating "fuzz target compiles" as fuzz PASS. The harness must actually run for the stated duration without crashes.
- Counting WAIVED in the denominator without justification. WAIVED requires `notes` linking back to `spec.constraints.*` or `spec.checklist.*` exclusion.
- Conflating "golden file exists" with "golden is fresh." Always run the regenerate command and check the diff.

## When done

Print the test_depth.json path + summary (`<BEAD_ID>: 4 PASS, 1 PARTIAL, 2 FAIL`) to stdout.
