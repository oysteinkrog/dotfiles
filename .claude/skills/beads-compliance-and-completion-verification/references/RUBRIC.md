# RUBRIC.md — The Scoring Rubric (0–1000) in Full

The rubric in `SKILL.md` is the headline. This file is the **deterministic mechanics** that the scorer subagent applies. Two runs over the same evidence pack must produce the same score.

The `rubric.md` written into the audit dir at bootstrap is a snapshot of this file plus any per-project tunings. **Always score against the audit dir's `rubric.md`**, not this file directly — that way old passes remain reproducible.

---

## Dimension breakdown

### 1. Implementation completeness vs. spec — max 300

Per `spec.json`, every code-artifact item must be either `FOUND` (with citations in `evidence.json`) and `PASS` (Phase 4 verdict) and not contradicted by `theater.json`.

```
score_1 = 300 * (
    sum_over_code_items(weight_i * status_score_i)
    / sum_over_code_items(weight_i)
)

status_score_i:
  FOUND + PASS + no BLOCKING theater    → 1.0
  FOUND + PASS + MAJOR theater          → 0.5
  FOUND + PASS + BLOCKING theater       → 0.0  (theater invalidates "found")
  FOUND + FAIL                          → 0.25 (code exists but doesn't work)
  FOUND + ERROR                         → 0.1
  AMBIGUOUS                             → 0.3
  MISSING                               → 0.0
```

**Item weights:**
- A code artifact named explicitly in the bead body → weight 2.
- A code artifact named only in `acceptance_criteria` (e.g., "the parser must support X") → weight 2.
- An implicit requirement derived from bead type → weight 1.

**Boundary cases:**
- Bead has zero code-artifact items in spec (e.g., docs-only bead) → dimension is `n/a`, weight redistributed to docs/migrations dimension.
- Bead's only code item is `MISSING` → score 0 in this dimension.

---

### 2. Required tests present and meaningfully passing — max 250

For each test type explicitly named in the bead's spec:

```
score_2 = 250 * (
    sum_over_test_types(weight_t * test_score_t)
    / sum_over_test_types(weight_t)
)

test_score_t:
  Phase 4 verdict PASS + Phase 5 no BLOCKING test-theater    → 1.0
  PASS + MAJOR test-theater (e.g., trivial assertion in 80% of suite) → 0.4
  PASS + BLOCKING test-theater (e.g., `assert true`)         → 0.0
  FAIL                                                       → 0.0
  TIMEOUT                                                    → 0.2 (partial credit, dock for budget)
  SKIPPED                                                    → 0.0 (the test exists but is `#[ignore]`-d)
  MISSING                                                    → 0.0
  UNVERIFIED_INFRA                                           → flagged; do not score; user must re-run
```

**Test type weights** (default; per-bead-type tunings in `BEAD-TYPE-WEIGHTS.md`):
- Unit tests → weight 1
- Integration tests → weight 2
- E2E tests → weight 3
- Fuzz tests → weight 2
- Property tests → weight 2
- Metamorphic tests → weight 2
- Golden artifacts → weight 1
- Conformance harnesses → weight 3

**Boundary cases:**
- Bead spec has zero tests required → dimension is `n/a` *only if* the bead is a docs/chore type. For features/bugs, missing tests = 0.
- Test "passes" but Phase 5 says the implementation it tests short-circuits → BLOCKING; score 0.

---

### 3. Anti-theater / no stubs / no mocks where forbidden — max 150

Aggregate `theater.json` findings.

```
base = 150
penalty_per_BLOCKING = 50
penalty_per_MAJOR    = 15
penalty_per_MINOR    = 3
penalty_NOTE         = 0

score_3 = max(0, base - sum(penalties))
```

**Special cases (zero out):**
- Any BLOCKING finding tied to the *primary* deliverable of the bead (e.g., the bead is "implement X" and X has `unimplemented!()`) → `score_3 = 0` regardless of other findings.
- A mock found where `spec.constraints.no_mocks: true` → BLOCKING.
- Sleep used to simulate I/O work in production code (not test code) → BLOCKING.

**Boundary cases:**
- Bead allows mocks (`spec.constraints.allowed_mocks: [...]`) → mocks of those services don't count as findings.
- A `TODO` comment with a linked follow-up bead ID (e.g., `// TODO(bd-xyz): handle edge case`) → MINOR, not MAJOR; the gap is tracked.

---

### 4. Test depth — max 150

Aggregate `test_depth.json` checks.

```
score_4 = 150 * (
    sum_over_depth_checks(check_score)
    / count_of_depth_checks
)

check_score:
  PASS                       → 1.0
  PARTIAL (e.g., coverage 70-79% when target 80) → 0.5
  FAIL                       → 0.0
  WAIVED (with valid reason) → counts in numerator at 1.0; counts in denominator
  INFRA_MISSING              → 0.0 (and flag for Phase 10)
```

**Coverage thresholds (default; tunable in `rubric.md`):**
- Bead's own surface line coverage ≥ 80% → PASS, ≥ 70% → PARTIAL, < 70% → FAIL.
- Branch coverage ≥ 70% → PASS, ≥ 60% → PARTIAL, < 60% → FAIL.

**Fuzz depth checks:** all four (corpus exists, harness compiles, ran for stated time, no crashes) must PASS for full credit; missing any = PARTIAL or FAIL.

---

### 5. Documentation, telemetry, migrations, feature flags — max 100

For each non-code artifact named in spec:

```
score_5 = 100 * (
    sum(item_present ? 1 : 0)
    / count_of_non_code_items
)
```

If spec has zero non-code items → dimension is `n/a`; redistribute 100 points proportionally to dimensions 1 and 2.

**What counts:**
- README updated → check `git log` for the bead ID touching README.
- Migration script → check `migrations/` or equivalent + verify it can be applied to a fresh DB.
- Feature flag → check the flag exists in the project's feature-flag config.
- Telemetry → check the metric/log/trace name is emitted in the code.
- Runbook → check the file exists + the bead's procedure is in it.

---

### 6. Cross-bead integration & no contradictions — max 50

Aggregate findings from `synthesis.md` that touch this bead.

```
base = 50
penalty_per_integration_gap_caused  = 25
penalty_per_contradiction_caused    = 25
penalty_per_orphaned_AC             = 10
penalty_per_dependency_anomaly      = 10

score_6 = max(0, base - sum(penalties))
```

**Bonus:** beads that *resolved* a prior pass's integration gap → +10 (capped at 50 total).

---

## Putting it together

```
total_score = score_1 + score_2 + score_3 + score_4 + score_5 + score_6
verdict     = band_lookup(total_score)
false_closed = (status == "closed") AND (total_score < threshold)
```

The scorecard MUST cite the evidence file paths for every dimension. A score without citations is invalid.

---

## Tie-breakers and edge cases

| Situation | Handling |
|-----------|----------|
| Bead has empty `acceptance_criteria` field | Use only `description` + `design` for spec extraction; flag `original_bead_quality_low` in scorecard but don't penalize the implementer for the bead author's brevity |
| Bead body says "WIP" or "draft" but status=closed | Auto-flag as false-closed regardless of score; status-body mismatch is a Phase 1 finding |
| Bead is part of an epic that was closed; bead itself is closed | Score normally; epic completion ≠ child completion |
| Bead's claimed evidence is on a stale branch (not main) | Score the *intended* state from the branch; flag in synthesis as "merge required for this to count on main" |
| Test passes but coverage tool can't measure it (e.g., closed-source dep) | Score test as PASS; depth check WAIVED with reason |
| Two beads claim the same code as their evidence | Both score on it; flag in synthesis as "shared evidence — bead scope unclear" |
| Bead was closed by `br close <id> --reason "duplicate of bd-xyz"` | Verify bd-xyz exists and is closed with score ≥ threshold; if so, this bead inherits its score; if not, propagate the gap |

---

## Per-project tuning

The `rubric.md` written into the audit dir is the source of truth for that project's audit. Tunable knobs:

- Score threshold (default 700).
- Coverage thresholds (default 80% line / 70% branch).
- Test type weights.
- Bead-type-specific weight overrides (see `BEAD-TYPE-WEIGHTS.md`).
- Convergence delta threshold (default ±10).
- Allowed-mock list (project-wide; per-bead overrides still apply).

**Document every tuning in the rubric file's frontmatter so future passes are reproducible.** Tunings between passes are allowed but must be recorded as `rubric_version_bumped_at: <UTC>` and reflected in `convergence.json` so score deltas are interpreted correctly (a score change driven by a rubric change is not a real change).
