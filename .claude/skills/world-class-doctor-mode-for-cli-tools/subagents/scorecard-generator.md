# subagent: scorecard-generator (Phase 6)

**Description.** Compute per-FM × per-dimension scores using the 10-dimension rubric, emit `failure_mode_scores.jsonl`, `scorecard.md`, and `heatmap.svg`.

## Inputs

- `{{workspace}}/analysis/repair_specs/*.md`
- `{{target}}` — for runtime probing
- `<tool> doctor capabilities --json` output
- `tests/doctor_fixtures/run_all.sh` results
- `../references/rubric/SCORING-RUBRIC.md`
- `../references/rubric/PRIORITY-FORMULA.md`
- `../references/rubric/SURFACE-CLASSES.md`

## Outputs

- `{{workspace}}/failure_mode_scores.jsonl`
- `{{workspace}}/scorecard.md`
- `{{workspace}}/scorecard_pass_<N>.md`
- `{{workspace}}/heatmap.svg`

## Prompt

```
You are the scorecard-generator. Compute per-failure-mode scores against the
10-dimension rubric and produce the workspace's scorecard artifacts.

PROCEDURE.

1. Read the rubric: `../references/rubric/SCORING-RUBRIC.md`. The 10
   dimensions are:
   agent_intuitiveness, agent_ergonomics, automation_degree, data_safety,
   idempotence, reversibility, diagnostic_specificity,
   blast_radius_containment, observability, test_coverage_of_repair.

2. Enumerate failure modes from `<tool> doctor capabilities --json::detectors[].id`.
   For each, find the corresponding repair_spec at
   `{{workspace}}/analysis/repair_specs/<id>.md` and the fixture at
   `tests/doctor_fixtures/<id>/`.

3. Score each FM against each dimension using the anchors at
   0/250/500/750/1000 in the rubric. For score >= 700, you MUST cite
   evidence (file:line, fixture path + test name).

4. Append per-FM rows to `failure_mode_scores.jsonl`. Schema:
   {fm_id, dimension, score, evidence_path, evidence_line_or_test, run_id,
    frequency, blast_radius}. One row per (fm, dimension) — 10 rows per FM.
   `frequency` and `blast_radius` are PER-FM weights (not per-dimension), so
   they repeat identically on each of the 10 rows for a given FM. Allowed
   values:
   - `frequency`: numeric (0.5..2.0) or label "rare"=0.5, "occasional"=1.0,
     "often"=2.0. Source: CASS findings count + bug-tracker hit count + git
     log mentions. If unknown, default 1.0 (occasional).
   - `blast_radius`: numeric (0.25..4.0) or label "cosmetic"=0.25,
     "nuisance"=0.5, "degrades_correctness"=1.0, "corrupts_state"=2.0,
     "loses_data"=4.0. Source: PRIORITY-FORMULA.md rubric. Required for
     correct aggregate; default 1.0 if truly unknown.
   Both are clamped to [0.5, 2.0] by scorecard.py before weighting.

5. Compute per-FM medians and aggregate score using the formula in
   PRIORITY-FORMULA.md (and OUTPUT-SCHEMA.md § scorecard.json):
   `aggregate = sum(per_FM_median × frequency × blast_radius) / sum(frequency × blast_radius)`.

6. Run `scripts/scorecard.py render {{workspace}}` to generate:
   - `scorecard.md` (human-readable, with a per-FM table and aggregate)
   - `scorecard_pass_<N>.md` (historical record)
   - `heatmap.svg` (FM × dimension grid; hot=low score)

7. Append a one-line summary to `scorecard_history.jsonl` via:
   `scripts/scorecard.py append-history <run-dir> {{target}}/.doctor/scorecard_history.jsonl`
   (the script handles the JSON shape — `{run_id, started_at, tool_version,
   doctor_version, ok, total_findings, aggregate_score, actions_taken}` —
   and appends with fsync so the line is durable).
   Do NOT hand-write the JSON line — use the script.

8. Run `scripts/diff-scorecards.py {{workspace}} <N-1> <N>` if a previous pass
   exists. Emit:
   - `{{workspace}}/uplift_diff.md` (delta table)
   - `{{workspace}}/regression_alerts.md` (any FM dropped > 50 pts)

VALIDATION.
- `python3 scripts/scorecard.py validate {{workspace}}` must exit 0. The
  validator reads `{{workspace}}/failure_mode_scores.jsonl`, rejects scores
  >= 700 without evidence, and rejects any regression block emitted by
  `diff-scorecards.py` unless it has a non-placeholder ACK line.

EXIT CRITERIA.
- failure_mode_scores.jsonl exists; one row per (fm, dimension).
- scorecard.md exists.
- heatmap.svg exists.
- `scorecard.py validate` exits 0.
- (If pass > 1) uplift_diff.md and regression_alerts.md committed.
```

## Exit criteria

- All artifacts exist and pass validation
- Aggregate score recorded in `manifest.json::aggregate_score` via:
  `scripts/manifest-update.sh {{workspace}} --set-int .aggregate_score=<N>`
  (the script handles flock + atomic rename so concurrent updates don't
  lose data — never hand-edit `manifest.json` directly per round-53 audit).

## Failure modes

- A score >= 700 lacks evidence. Refuse to commit; either lower the score or find evidence.
- Regression > 50 pts. Hard stop. Investigate root cause; either revert the change or explicitly acknowledge in `regression_alerts.md` with reasoning.
