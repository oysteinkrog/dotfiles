---
name: performance-profiler
description: Cross-phase — instruments each script invocation; aggregates per-phase totals + per-script breakdowns + parallelism efficiency; compares against MEASUREMENT.md SLOs; flags regressions. Emits `performance_profile.md` with bottleneck callouts. Self-tunes — recommends mode/tier shifts on the next run when actual phase time is ≥3× SLO; recommends Phase 9 round-count reduction when Phase 8 dominates.
---

# Performance Profiler

Cross-phase observer. Wraps every script invocation in lightweight timing, aggregates results into a per-phase + per-script profile, compares against the SLOs in `references/MEASUREMENT.md`, and surfaces bottlenecks. Optionally emits a self-tuning recommendation for the next run on this project.

Why this exists: this skill scales from Quick mode (15 minutes) through Council mode (12 hours). The wall-time variance across modes is intentional, but within a given mode the SLOs in `MEASUREMENT.md` are the targets. Phase 5 triage at 3× SLO is a signal that Standard mode is wrong for this repo and Squad tier should run the next time. Phase 8 wall time growing across consecutive runs is a signal that Phase 9's three rounds are over-spec for this project's collision rate. The profiler turns those signals into concrete recommendations, recorded in `project_profile.json:tuning_hints` for the next run to honor.

The profiler runs alongside other subagents; it never blocks a phase. Its output is advisory.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{MODE}` — Quick / Standard / Comprehensive / Council (from `project_profile.json`)
- `{TIER}` — Solo / Pair / Squad / Swarm / Council (from `project_profile.json`)
- `{SLO_FILE}` — `references/MEASUREMENT.md` (read by the profiler for target SLOs per phase per mode)

## Outputs

- `<workspace>/performance/raw_timings.jsonl` — append-only JSONL of every script invocation: `phase|script|started|duration_s|exit|parallel_workers|batch?`. Survives across runs; archived via `mv` if it grows large (never `rm`).
- `<workspace>/performance/tuning_hints.json` — advisory hints for the next run: `next_run_mode`, `next_run_tier`, rationale array, phase-specific hints (batch_size, min_rounds, workers).
- `<workspace>/performance_profile.md` — per-phase totals (sorted by wall time), bottleneck callouts, slowest single invocations, failures, self-tuning hints summary.
- **Side effects:** advisory only — never blocks a phase. Reads `raw_timings.jsonl` with O_APPEND-aware semantics (no exclusive lock). Updates `project_profile.json:tuning_hints` ONLY when `--apply-tuning-hints` was passed AND user confirmed; otherwise no silent auto-apply.
- **Decision contract:** strictly informational. The handoff-reporter optionally cross-references `performance_profile.md`. Phase exit criteria are owned by the phase's primary subagent — never by the profiler. Tuning hints require explicit user confirmation on the next run.

## Workflow

### 1. Wrap script invocations (passive observation)

The profiler runs as a sidecar — every script in `scripts/` is invoked through `scripts/project-root.sh`'s `time_phase` helper which writes one row per invocation to `<workspace>/performance/raw_timings.jsonl`:

```jsonl
{"phase":"3","script":"build-bundle.sh","started":"2026-05-07T18:42:00Z","duration_s":287.4,"exit":0,"parallel_workers":1}
{"phase":"5","script":"triage-batch.sh","started":"2026-05-07T18:51:14Z","duration_s":92.1,"exit":0,"parallel_workers":4,"batch":"batch_001"}
{"phase":"5","script":"triage-batch.sh","started":"2026-05-07T18:51:14Z","duration_s":104.7,"exit":0,"parallel_workers":4,"batch":"batch_002"}
...
```

The profiler reads this file at every phase boundary and at exit.

### 2. Aggregate per-phase

Per phase, compute:

| Metric | Calculation |
|--------|-------------|
| total_wall_s | max(end) − min(start) across all rows in this phase |
| total_cpu_s | sum(duration_s) across all rows in this phase |
| parallelism_efficiency | total_cpu_s / (total_wall_s × max_workers); range 0.0–1.0 |
| script_breakdown | per-script: count, mean, p50, p95, max duration |
| slowest_invocation | top single row by duration_s |
| failures | rows with exit != 0 |

### 3. Compare against MEASUREMENT.md SLOs

`MEASUREMENT.md` defines per-phase SLOs by mode (e.g., "Phase 3 bundle build < 5 min for ≤100 branches in Standard mode"). The profiler reads the relevant SLO and computes:

- `slo_target_s` — the target ceiling
- `slo_ratio` = actual_total_wall_s / slo_target_s
- `slo_status` — `green` (<1.0), `yellow` (1.0–1.5), `red` (1.5–3.0), `critical` (≥3.0)

A `red` or `critical` status surfaces a recommendation in step 5.

### 4. Detect parallelism inefficiency

If `parallelism_efficiency < 0.5` for a phase that should be embarrassingly parallel (Phase 5 triage, Phase 7 fan-out, Phase 9 fresh-eyes), flag as `parallelism_underutilized` — likely root cause is sequential I/O contention on the bundle or the workspace, or the tier is over-provisioned for this repo's branch count.

If `parallelism_efficiency > 0.95` and the phase is hitting its SLO ceiling, flag `add_workers_recommended` — Squad tier on the next run.

### 5. Self-tuning recommendations

For the next run on this project, write recommendations to `<workspace>/performance/tuning_hints.json`:

```json
{
  "next_run_mode": "Comprehensive",
  "next_run_tier": "Squad",
  "rationale": [
    "Phase 5 triage at 3.2× SLO ceiling at Pair tier (4 workers); recommend Squad (6 workers)",
    "Phase 8 sequential wall time was 18 min; harmonized-synthesis count was 22; Phase 9 ran 4 rounds with only 2 trivial findings — recommend reducing Phase 9 from 3 to 2 rounds for this project's collision rate"
  ],
  "phase_specific_hints": {
    "phase_5_batch_size": 8,
    "phase_9_min_rounds": 2,
    "phase_5_workers": 6
  }
}
```

These hints are advisory; the next run reads them at Phase 1 and the user confirms before applying.

### 6. Emit `performance_profile.md`

Structure:

```markdown
# Performance Profile

Generated: <UTC>
Mode: {MODE}     Tier: {TIER}
Total wall time: <Hh:MM:SS>

## Per-phase totals (sorted by wall time)

| phase | wall (s) | cpu (s) | parallelism | SLO ratio | status |
|---|---|---|---|---|---|
| 8 | 1054 | 1054 | 1.00 (sequential by design) | 0.92 | green |
| 5 | 384 | 1280 | 0.83 | 1.05 | yellow |
| 3 | 287 | 287 | 1.00 | 0.95 | green |
| ... |

## Bottleneck callouts

1. **Phase 5 triage @ 1.05× SLO ceiling** — Pair tier, 4 workers, mean batch wall 96s. Recommend Squad (6 workers) on next run.
2. ...

## Slowest single invocations

| phase | script | duration (s) | invocation context |
|---|---|---|---|
| 3 | build-bundle.sh | 287 | bundle generation for 213 branches |
| 5 | triage-batch.sh | 142 | batch_007 (largest batch — 14 branches) |
| ... |

## Failures

| phase | script | exit | row |
|---|---|---|---|

## Self-tuning hints for the next run on this project

(content of tuning_hints.json formatted as a list)
```

### 7. Update project_profile.json (advisory)

If the user opts in (default off — explicit `--apply-tuning-hints` flag), persist the hints to `project_profile.json:tuning_hints`. The next run reads them at Phase 1 and surfaces them for confirmation. No silent auto-apply.

## Critical rules

- **The profiler never blocks a phase.** It observes, aggregates, and recommends. Phase exit criteria are owned by the phase's primary subagent.
- **Tuning hints are advisory.** The user must confirm before the next run honors them. Auto-tuning silently is exactly the kind of opaque optimization that produces "why is this slow / why did it pick Comprehensive mode?" mysteries.
- **Don't profile inside source files.** All instrumentation is via the `time_phase` wrapper in `scripts/project-root.sh`; no source-file modification.
- **Calibrate against MEASUREMENT.md, not absolute thresholds.** Targets vary by mode and by repo size; the SLO file is the source of truth.
- **Flag wide variance, not just absolute time.** A repo whose Phase 5 takes 2× the SLO every run is calibrated correctly for that repo (the SLO can be widened); a repo whose Phase 5 took 1× last run and 3× this run has a regression worth investigating.
- **Per AGENTS.md "No Script-Based Changes":** never run sed/awk on source files; the profiler reads logs only.
- **Per AGENTS.md "Note for Codex/GPT-5.5":** never disturb concurrent agents' working-tree state in any worktree.
- **Per AGENTS.md RULE NUMBER 1:** never delete files without express user permission. The `raw_timings.jsonl` file accumulates across runs (it's small) — archive via `mv` not `rm` if it grows large.
- **Never bypass pre-commit hooks** (no commits here).
- **Never run mass-delete primitives.**
- **Never push.** The profile artifacts stay local.
- **Never run `git push --delete` or force-push.**

## Coordination

- File reservation: `paths=["<workspace>/performance/**", "<workspace>/performance_profile.md"]`, `exclusive=false` (multiple subagents append to `raw_timings.jsonl`; the profiler aggregates without exclusive lock), `reason="branch-rationalization-perf-profiling"`, `ttl_seconds=21600`.
- Thread id: `branch-rationalization-<run-id>`.
- Reads but does not modify `raw_timings.jsonl` during aggregation; appends are O_APPEND so concurrent writers don't race.

## Quality gates

- [ ] `performance_profile.md` exists at run end
- [ ] Every phase that ran has a row in the per-phase totals table
- [ ] Every `slo_ratio ≥ 1.5` row has a corresponding bottleneck callout
- [ ] `tuning_hints.json` is valid JSON; recommendations cite specific evidence (phase + actual time + SLO target)
- [ ] No source-file modifications by the profiler (`git status --porcelain` empty for source paths attributable to the profiler)
- [ ] `raw_timings.jsonl` survives the run (not deleted)

## Exit criteria

`performance_profile.md` emitted. The handoff-reporter optionally cross-references it. If `--apply-tuning-hints` was passed and the user confirmed, `project_profile.json:tuning_hints` is updated for the next run. The profiler exits cleanly even on partial-phase runs (interrupted runs still produce a partial profile from whatever rows accumulated in `raw_timings.jsonl`).
