---
rubric_version: 1.0.0
score_threshold: 700
delta_threshold_for_convergence: 10
coverage_minimum_line: 0.80
coverage_minimum_branch: 0.70
allow_new_false_closed: 0
spot_check_count: 5
spot_check_max_deviation: 50
---

# Project-Specific Rubric — Beads Compliance Audit

This file is the **source of truth** for scoring during this project's audit. The skill's `references/RUBRIC.md` is the default; this file may tune it. Document every tuning so future passes are reproducible.

## Dimension weights (default — see references/BEAD-TYPE-WEIGHTS.md for type overrides)

| Dimension | Max | What it measures |
|-----------|----:|------------------|
| Implementation completeness vs. spec | 300 | Every code artifact named in the bead exists and does what the bead says |
| Required tests present and meaningfully passing | 250 | Each test type the bead names exists, runs, and exercises real code paths |
| Anti-theater / no stubs / no mocks where forbidden | 150 | Zero TODOs, unimplemented!, hardcoded returns, mocks-where-forbidden, assert true, dead branches |
| Test depth | 150 | Coverage over bead's surface; fuzzer ran for stated time; goldens fresh; e2e hit real services |
| Documentation, telemetry, migrations, feature flags | 100 | Whatever non-code artifacts the bead enumerated |
| Cross-bead integration & no contradictions | 50 | This bead's contracts hold; doesn't break a sibling bead |
| **TOTAL** | **1000** | |

## Verdict bands

| Band | Range | Verdict |
|------|------:|---------|
| 🟢 Verified | 950–1000 | Truly done. Ship-ready. |
| 🟢 Substantially complete | 850–949 | Minor gaps; document and move on. |
| 🟡 Partial | 700–849 | Acceptable for now; not "closed" caliber if status says closed. |
| 🟠 False-closed (mild) | 500–699 | Status lies. Reopen or completion-debt. |
| 🔴 False-closed (severe) | 250–499 | Substantially fictional. Reopen with high priority. |
| 🚨 Theater | 0–249 | Implementation essentially absent. |

## False-closed flag

`status == "closed"` AND `total_score < score_threshold` (frontmatter) → goes on the false-closed list and triggers Phase 9 remediation.

## Per-project tunings (recorded for reproducibility)

(Document any deviations from default weights, thresholds, or band boundaries here. Each tuning entry: when, why, who.)

| Date (UTC) | Knob | Old | New | Reason |
|------------|------|-----|-----|--------|
| (none yet) |      |     |     |        |

## Bead-type overrides

See `references/BEAD-TYPE-WEIGHTS.md` for the canonical per-type weighting. To override for this project, list overrides here:

| Type | Implementation | Tests | Anti-theater | Depth | Docs | Cross-bead |
|------|---------------:|------:|-------------:|------:|-----:|-----------:|
| (use defaults) | | | | | | |

## Allowed mocks (project-wide)

Any mock listed here is permitted across the project regardless of per-bead `constraints.no_mocks`. Per-bead `allowed_mocks` further extends this. Use sparingly; the whole point of the audit is to push real-service testing.

| Mocked service | Justification | Approved by |
|----------------|---------------|-------------|
| (none) | | |

## Coverage thresholds

- Line: ≥ 80% PASS, 70-80% PARTIAL, < 70% FAIL
- Branch: ≥ 70% PASS, 60-70% PARTIAL, < 60% FAIL

Per-bead `spec.constraints.coverage_minimum_*` overrides these.

## Convergence

- Per-bead score deltas between passes must be within ±10 points.
- Zero new false-closed beads since prior pass.
- Zero new synthesis findings.
- Phase 10 spot-checks within ±50 of scorer values.
- All prior-pass remediation beads exist in current inventory.

## Rubric change history

Bumping any field in this file's frontmatter (or a weight in this body) requires a new line here so the next pass's `convergence-check.py` can interpret score changes correctly:

| Date (UTC) | rubric_version (old → new) | Field changed | Why |
|------------|----------------------------|---------------|-----|
| (none yet) | | | |
