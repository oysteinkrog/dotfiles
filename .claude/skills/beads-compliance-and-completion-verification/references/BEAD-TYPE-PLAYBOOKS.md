# BEAD-TYPE-PLAYBOOKS.md — Per-Type Verification Recipes

<!-- TOC: Feature | Bug (with BISECT) | Epic | Chore | Docs | Infra | Performance | Security | Migration | Question | Custom | Multi-type beads -->

Different bead types deserve different verification depth. The rubric in `BEAD-TYPE-WEIGHTS.md` says *what* to weight; this file says *how* to actually verify each type. Apply alongside the phase loop in `PHASES.md`.

> **Rule of thumb.** Bug beads stand or fall on their *regression test*. Feature beads on their *happy-path + error-path + edge-case test trio*. Epic beads on *child-completion + integration test*. Docs on *file existence + reachability*. Infra on *idempotency + rollback*. Migrations on *forward + reverse*. Security on *threat-model coverage*. Performance on *benchmark before/after with statistical significance*.

---

## Feature beads (`type: feature`)

### Implicit requirements (auto-injected by spec extractor)

- `implicit.feature.happy_path_test` — at least one test exercising the documented happy path.
- `implicit.feature.error_path_test` — at least one test exercising the documented failure mode.
- `implicit.feature.edge_case_test` — boundary conditions (empty input, max input, unicode, etc.).
- `implicit.feature.user_facing_doc` — README / docs section covering the new capability.
- `implicit.feature.telemetry` — if performance-sensitive, at least one metric / log / trace exposing the new code path's behavior in production.
- `implicit.feature.rollback_path` — feature flag OR ability to disable without redeploy (when scope warrants).

### Verification recipe (per phase)

| Phase | What to do |
|------:|------------|
| 2 | Spec-extract code artifacts + the test trio (happy/error/edge) + docs + telemetry |
| 3 | Locate the function/module + each of the three tests + the docs commit + the metric emission |
| 4 | Run the trio; capture stdout. Must exit 0 with non-trivial assertions on each |
| 5 | Anti-theater scan focused on: hardcoded happy-path returns, `assert true` in error-path test, mocks for the user-facing surface |
| 6 | Coverage of the bead's primary file ≥ 80% line / 70% branch; the three tests must collectively touch all branches |
| 7 | Cross-reference: does any other bead's spec assume this feature behaves a certain way? Contract drift check |

### Common false-closed pattern

Feature beads frequently close with happy-path-only tests. The error-path test is implicit; the spec extractor adds it; Phase 6 catches the missing branch coverage. Severity: **MAJOR** dock on dimension 2 + 4.

---

## Bug beads (`type: bug`)

### Implicit requirements

- `implicit.bug.regression_test` — a test that **fails on the prior commit and passes on the fix commit**. (BISECT proof.)
- `implicit.bug.root_cause_documented` — bead notes / close reason explains the actual root cause, not just the symptom.
- `implicit.bug.no_other_callers_broken` — full test suite still passes after the fix.

### Verification recipe

| Phase | What to do |
|------:|------------|
| 2 | Spec extract: the regression test name, the file/function fixed, the symptom |
| 3 | Locate the test + the fix in `git log --grep=<bead-id>`. Confirm the test was added in the same commit as the fix (or in a closely-paired commit) |
| 4 | **BISECT-verify**: `git stash` the fix; run the test → must FAIL. Restore the fix; run the test → must PASS. This is the proof. If the test passes both with AND without the fix, it's not actually a regression test |
| 5 | Anti-theater on the test body — was it `assert true`? Was it added but `#[ignore]`-d? |
| 6 | Coverage of the affected branch — the regression test should hit it |
| 7 | Did the fix introduce a contradiction with another bead's stated invariant? |

### BISECT verification snippet

```bash
# Save the current state
ORIG_SHA=$(git -C <PROJECT> rev-parse HEAD)
TEST_NAME="<from spec.json>"

# Find the fix commit
FIX_SHA=$(git -C <PROJECT> log --grep="<bead-id>" --format='%H' | tail -1)

# Run the test on the parent of the fix commit
git -C <PROJECT> checkout "${FIX_SHA}^"
EXIT_BEFORE=$(cargo test "$TEST_NAME" >/dev/null 2>&1; echo $?)

# Run the test on the fix commit
git -C <PROJECT> checkout "$FIX_SHA"
EXIT_AFTER=$(cargo test "$TEST_NAME" >/dev/null 2>&1; echo $?)

# Restore
git -C <PROJECT> checkout "$ORIG_SHA"

# A real regression test: failed before, passes after.
if [ "$EXIT_BEFORE" -ne 0 ] && [ "$EXIT_AFTER" -eq 0 ]; then
  echo "BISECT PASS: regression test verified"
else
  echo "BISECT FAIL: test does not actually regress without the fix"
fi
```

If BISECT fails, bead's dimension 2 → 0 (the test is theater).

### Common false-closed pattern

"Fixed by adding null check, no test." Bug beads close without the regression test that would have caught the bug. Phase 6 catches via the implicit requirement.

---

## Epic beads (`type: epic`)

### Implicit requirements

- `implicit.epic.children_closed` — every child bead is `closed`.
- `implicit.epic.children_pass_grade` — every child bead's score ≥ threshold.
- `implicit.epic.integration_test` — at least one e2e test that exercises the epic's full flow.

### Verification recipe

| Phase | What to do |
|------:|------------|
| 2 | Spec-extract from epic body + recurse: enumerate every child bead the epic references |
| 3 | Locate the integration test (the one that exercises end-to-end) |
| 4 | Run the integration test; must hit real services per `/testing-real-service-e2e-no-mocks` |
| 5 | If integration test mocks the very services it should integrate, BLOCKING |
| 6 | Coverage check is meaningless for epics; instead check that every child's surface is touched by the integration test |
| 7 | The epic's score is dominated by dimension 6 (cross-bead). Synthesize: do the children compose into a coherent whole? |

### Scoring override

For epics, dimension 6 max is **500** (per `BEAD-TYPE-WEIGHTS.md`). The other dimensions max 100 each. So even a perfect-implementation epic with all children done but no integration test caps at ~600.

### Common false-closed pattern

Epic closed because all children are closed, but no integration test. The flow has never been exercised end-to-end. Or: epic closed when half its children are still `open`/`in_progress`. Both flag automatically.

---

## Chore beads (`type: chore`)

### Implicit requirements

- `implicit.chore.tests_still_pass` — full test suite green on HEAD after the chore.
- `implicit.chore.build_still_green` — build/lint clean.
- `implicit.chore.no_unrelated_drift` — git diff is constrained to the chore's stated surface; no surprise changes elsewhere.

### Verification recipe

| Phase | What to do |
|------:|------------|
| 2 | Spec extract: what's the chore's stated surface (files / modules) |
| 3 | `git log --grep=<bead-id> -- <stated-surface>` should match. Files outside the surface in the diff → flag |
| 4 | Full test suite + build + lint on HEAD |
| 5 | Anti-theater: was a refactor incomplete (some call sites still use the old API)? |
| 6 | No coverage delta required (refactors usually preserve coverage). But: was test coverage maintained? |
| 7 | Did the chore break a sibling bead's contract? |

### Common false-closed pattern

Refactor closed but call sites still use the old API in one obscure file. Phase 5 catches via the partial-refactor pattern (search for the old function name in the codebase; if any non-test callers remain, MAJOR).

---

## Docs beads (`type: docs`)

### Implicit requirements

- `implicit.docs.file_exists` — the doc file exists at the cited path.
- `implicit.docs.reachable` — linked from the docs index / README / sidebar.
- `implicit.docs.accurate` — content matches the actual code (spot-check).
- `implicit.docs.no_broken_links` — internal cross-links resolve.

### Verification recipe

| Phase | What to do |
|------:|------------|
| 2 | Spec extract: which file path, which section, which audience |
| 3 | Confirm file exists; confirm reachable from index |
| 4 | "Run" the doc by extracting any code blocks and executing them — they must parse / compile / run without modification |
| 5 | Anti-theater on docs: vague "comprehensive" / "robust" without numeric backing → MINOR (use `/de-slopify` heuristics) |
| 6 | Run a link-checker over the doc; broken internal links → FAIL |
| 7 | Cross-reference: does another bead claim "documented in <X>" where X is this doc, but <X> doesn't actually cover it? |

### Scoring override

Per `BEAD-TYPE-WEIGHTS.md`, dimension 5 (docs) max is **750**. Docs beads stand or fall on the doc itself.

### Common false-closed pattern

Docs bead closed but the doc file is empty / "TODO: write this section" / placeholder content. Phase 5 catches via TODO scan; Phase 6 catches via empty-section detection.

---

## Infra beads (`type: chore` or custom `type: infra`)

### Implicit requirements

- `implicit.infra.idempotent` — re-running the infra change has no effect.
- `implicit.infra.rollback_path` — there is a documented + tested way to undo it.
- `implicit.infra.observability` — the change emits at least one metric / log / trace so failure modes are visible in production.
- `implicit.infra.no_breaking_change_to_callers` — downstream consumers (CI, deploy scripts, other repos) still work.

### Verification recipe

| Phase | What to do |
|------:|------------|
| 2 | Spec extract: what infra is changing, what's the rollback, what's observable |
| 4 | Run the infra change in a sandbox (e.g., `terraform plan` against a test workspace). Then run it twice — second run must be a no-op (idempotency proof) |
| 5 | Anti-theater: hardcoded credentials, dummy resource names, `# TODO: configure` comments |
| 6 | Rollback path: actually run it. Re-run the deploy → must succeed |
| 7 | Did this change break CI on any sibling repo? Cross-repo check via `/ru-multi-repo-workflow` |

---

## Performance beads (`type: feature` with perf budget OR custom `type: perf`)

### Implicit requirements

- `implicit.perf.benchmark_exists` — a benchmark exists in the project's bench harness.
- `implicit.perf.budget_documented` — the bead body states a numeric target (latency / throughput / memory).
- `implicit.perf.measurement_methodology` — methodology cited (`/profiling-software-performance` or equivalent).
- `implicit.perf.statistical_significance` — N runs with confidence intervals, not a single point measurement.
- `implicit.perf.regression_guard` — CI fails if the benchmark regresses by > X%.

### Verification recipe

| Phase | What to do |
|------:|------------|
| 2 | Spec extract: budget, metric, percentile, sample size |
| 4 | Run the benchmark per `/profiling-software-performance` methodology. Capture median + p95 + p99. Compare to the bead's stated budget |
| 5 | Anti-theater: was the bench tuned to "win" by selecting a favorable workload? Cross-check by running on a representative-load fixture |
| 6 | Statistical significance: at least 30 samples; CI overlap test against the budget |
| 7 | Did the perf gain regress another bead's correctness? Performance optimizations often trade correctness; cross-check via the full test suite |

### Verdict

If the measured value misses the budget: bead's dimension 1 score → 0, regardless of whether code is "implemented." A perf bead that doesn't meet its budget is by definition not done.

---

## Security beads (`type: bug` or `type: feature` with `security` label)

### Implicit requirements

- `implicit.security.threat_model_referenced` — the bead body references the threat (e.g., "CSRF", "SQLi", "auth bypass", CWE-N).
- `implicit.security.regression_test` — same as bug bead BISECT requirement.
- `implicit.security.fuzz_coverage` — for input-handling code, a fuzzer covers the attack class per `/testing-fuzzing`.
- `implicit.security.adjacent_audit` — `/security-audit-for-saas` patterns adjacent to the fix were checked for similar issues.
- `implicit.security.no_silent_disclosure` — the fix does not leak the vulnerability via error message / log.

### Verification recipe

| Phase | What to do |
|------:|------------|
| 2 | Spec extract: CWE, attack class, affected surface |
| 4 | BISECT proof (as bug bead) + run the fuzzer for the stated duration if applicable |
| 5 | Anti-theater on the fix: hardcoded "if !user.is_admin: return 403" without any actual permission check; mocked auth in the regression test |
| 6 | Fuzz coverage of the attack class (e.g., for SQLi: dictionary fuzzer with quote-mutations) |
| 7 | Sibling-bead check: are similar attack surfaces in other beads patched too? |

---

## Migration beads (`type: chore` or custom `type: migration`)

### Implicit requirements

- `implicit.migration.forward_tested` — applies cleanly to a fresh DB.
- `implicit.migration.reverse_tested` — rollback applies cleanly to a post-migration DB.
- `implicit.migration.data_integrity` — sample data passes through forward + reverse and is byte-identical (or documented exception).
- `implicit.migration.zero_downtime_compatible` — if the bead claims zero-downtime, both old + new application versions can run against the migrated schema simultaneously (for the cutover window).

### Verification recipe

| Phase | What to do |
|------:|------------|
| 2 | Spec extract: schema before / after, data transformation, rollback |
| 4 | Spin up a fresh disposable DB (via `/testing-real-service-e2e-no-mocks`). Apply forward migration. Apply reverse. Apply forward again. All must succeed |
| 5 | Anti-theater: did the rollback actually undo? `pg_dump` before forward and after reverse should match (modulo timestamps) |
| 6 | If zero-downtime claimed: run both old + new app versions against the migrated schema; both must pass their unit tests |
| 7 | Did the schema change break a downstream bead's expected column names / types? |

---

## Question beads (`type: question`)

Question beads don't fit the standard rubric. Score binary:
- `answered: true` — the close reason references the answer (text, link, or another bead).
- `answered: false` — closed without an answer.

If `answered: false` AND status=closed, treat as false-closed regardless of dimensional scoring.

---

## Custom types

For `Custom(<name>)` types, the spec extractor falls back to `task` defaults. Override in `rubric.md#custom_type_weights`:

```yaml
custom_type_weights:
  research:
    implementation: 100
    tests: 100
    docs: 600
    cross_bead: 200
  spike:
    implementation: 200
    tests: 100
    docs: 400
  experiment:
    implementation: 200
    tests: 200
    docs: 100
    test_depth: 300   # the experiment IS the test
```

Document any new custom-type playbook here as a new section so future audits are reproducible.

---

## Cross-cutting: when a bead has multiple types

A "feature + bug fix" bead (rare but exists) inherits implicit requirements from both lists. The scorer takes the union of implicit requirements; weights default to feature unless `bug` is in labels.

For ambiguous cases, the spec extractor records `bead_type_inferred: <X>` in `spec.json#extraction_notes` so Phase 10 fresh-eyes can audit the inference.
