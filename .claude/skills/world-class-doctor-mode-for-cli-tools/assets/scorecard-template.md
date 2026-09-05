# Doctor Scorecard

**Tool:** `<tool>`  | **Version:** `<tool-version>`  | **Doctor version:** `<doctor-version>`
**Pass:** `<N>` | **Run-id:** `<ISO8601>__<run-id>` | **Started at:** `<ISO8601>`
**Target SHA:** `<git-sha>`

---

## Aggregate

**Aggregate score:** `<0–1000>` (median per-FM, weighted by frequency × blast_radius)

| Threshold | Met? |
|-----------|------|
| All fixers reversible | yes / no |
| All fixers idempotent | yes / no |
| All fixers crash-recoverable | yes / no |
| All fixers concurrency-safe | yes / no |
| `validate-doctor.sh` exit 0 | yes / no |
| Two clean fresh-eyes passes | yes / no |
| `tests/doctor_fixtures/run_all.sh` exit 0 | yes / no |

---

## Per-failure-mode scores

| FM | Median | Weight | agent_intuitiveness | agent_ergonomics | automation_degree | data_safety | idempotence | reversibility | diagnostic_specificity | blast_radius_containment | observability | test_coverage_of_repair |
|----|--------|--------|---------------------|------------------|-------------------|-------------|-------------|---------------|------------------------|--------------------------|---------------|-------------------------|
| fm-...-A | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |
| fm-...-B | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |

(13 columns: FM, Median, Weight, plus the 10 canonical dimensions in [SCORING-RUBRIC.md](../references/rubric/SCORING-RUBRIC.md). Header row matches exactly what `scripts/scorecard.py render <workspace>` produces — full dimension names so agents can parse without a key. See `heatmap.svg` for the visual.)

---

## Top improvements vs. previous pass

| FM | pass-(N-1) | pass-N | Δ |
|----|------------|--------|---|
| fm-...-A | 600 | 850 | +250 |
| fm-...-B | 720 | 900 | +180 |

---

## Regressions (each requires explicit acknowledgment)

| FM | pass-(N-1) | pass-N | Δ | ACK |
|----|------------|--------|---|-----|
| _none_ |  |  |  |  |

---

## Manual remediations (FMs we detect but cannot auto-fix)

| FM | Reason | User action |
|----|--------|-------------|
| fm-...-K | requires user OAuth (gated `--online`) | run `<tool> auth login`, then `<tool> doctor --online --fix` |

---

## What's next

- See `recommendations.jsonl` for ranked recommendations (Phase 4 input).
- See `HANDOFF.md` for the next-pass summary.
- See `agent_simulations/post_pass_<N>/notes.md` for cold-prober findings.
