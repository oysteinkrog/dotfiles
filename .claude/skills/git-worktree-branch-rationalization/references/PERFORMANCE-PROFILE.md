# Performance Profile — Per-Phase Profiling Beyond MEASUREMENT.md SLOs

[MEASUREMENT.md](MEASUREMENT.md) defines per-phase **SLOs** (target wall times). This file is the per-phase **profile** — actual measurements captured during the run, deviation analysis, bottleneck identification, and self-tuning recommendations.

Adapted from [/profiling-software-performance](../../profiling-software-performance/SKILL.md). The principle is: **SLOs are targets; profiles are measurements; deviation reveals bottlenecks.** A skill that only knows its targets but not its measurements can't improve.

> **Why profile at all?** Per [/profiling-software-performance](../../profiling-software-performance/SKILL.md): "Profile-driven performance optimization" — every optimization decision should be backed by a measurement, not by hand-wavy intuition. The branch-rationalization skill has 12 phases and ~30 scripts; without per-phase profiling, you can't tell whether the run is bottlenecked on Phase 5 triage, Phase 7 harmonization, Phase 8 apply gates, or Phase 9 fresh-eyes — and you can't auto-tune the next run.

---

## 1. What gets profiled

Three layers, increasing in granularity:

| Layer | What it measures | Output |
|---|---|---|
| **Per-phase** | Wall time for each of the 12 phases | `phase_timings.tsv` rolled up from script timings |
| **Per-script** | Wall time + CPU% + IO bytes for each of ~30 scripts | `script_timings.tsv` (one row per script invocation) |
| **Per-subagent** | Wall time + token count for each Task subagent invocation | `subagent_timings.tsv` |

For the swarm-tier modes (Comprehensive/Council), a fourth layer profiles parallelism efficiency:

| Layer | What it measures | Output |
|---|---|---|
| **Per-worker** | Per-batch wall time across N parallel workers in Phase 5/7/9 | `parallelism_efficiency.tsv` — measures speedup ÷ N_workers |

---

## 2. Per-script instrumentation

Every mutating script in `scripts/` is wrapped with the bash `time` builtin. The output is appended to `script_timings.tsv` in the workspace.

### 2.1 The wrapper

```bash
# Sourced from scripts/project-root.sh, called as the first line of every script:

with_timing() {
    local script_name="$1"
    local phase="$2"
    shift 2
    local start_epoch=$(date +%s.%N)
    local start_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Capture rusage:
    /usr/bin/time -f '%e\t%U\t%S\t%P\t%M\t%I\t%O' -o /tmp/timing.$$.txt "$@"
    local exit_code=$?

    local end_epoch=$(date +%s.%N)
    local wall=$(awk -v s="$start_epoch" -v e="$end_epoch" 'BEGIN{printf "%.3f", e-s}')
    local rusage=$(cat /tmp/timing.$$.txt)
    rm -f /tmp/timing.$$.txt

    echo -e "$start_iso\t$phase\t$script_name\t$wall\t$rusage\t$exit_code" >> "$WS/script_timings.tsv"
    return $exit_code
}
```

The columns of `script_timings.tsv`:

| Column | Meaning |
|---|---|
| `start_iso` | UTC timestamp |
| `phase` | Phase number (1–12) |
| `script_name` | Filename, e.g., `apply-keeper.sh` |
| `wall_seconds` | Wall clock time |
| `elapsed_real` | `time -f %e` |
| `cpu_user` | `time -f %U` |
| `cpu_sys` | `time -f %S` |
| `cpu_pct` | `time -f %P` (CPU% of one core; >100% = multi-core utilization) |
| `max_rss_kb` | `time -f %M` |
| `inputs` | `time -f %I` (filesystem inputs) |
| `outputs` | `time -f %O` (filesystem outputs) |
| `exit_code` | 0 = success |

### 2.2 IO + CPU augmentation

For scripts whose `wall_seconds > 30s`, the wrapper additionally launches `pidstat` against the script's PID:

```bash
# Background pidstat capturing IO + CPU at 1s granularity:
pidstat -d -u -p $$ 1 > "$WS/pidstat_${script_name}_$$.log" &
local pidstat_pid=$!
trap "kill $pidstat_pid 2>/dev/null" EXIT
```

This produces a per-second timeline. Useful for identifying within-script bottlenecks (e.g., "build-bundle.sh spends 80% of its time in the `git format-patch` loop, not the `git bundle create`").

### 2.3 Skipping profile in low-stakes modes

In Quick mode, profiling overhead can dominate the run. The wrapper consults `project_profile.json:profiling_enabled`:

| Mode | profiling_enabled | rationale |
|---|---|---|
| Quick | false | overhead not worth it for ≤30 min runs |
| Standard | true (per-phase + per-script only) | overhead acceptable; per-subagent skipped |
| Comprehensive | true (all layers) | full profile to inform self-tuning |
| Council | true (all layers + per-worker parallelism) | full profile + multi-model triangulation timing |

> **Why a per-mode toggle?** Per /profiling-software-performance: "profile only what you intend to measure." For a 15-minute Quick run, a 30-second profile-aggregation phase at the end is 3% overhead — not worth it. For a 6-hour Comprehensive run, 30 seconds is 0.14% — definitely worth it.

---

## 3. Per-phase aggregation

`script_timings.tsv` is rolled up into `phase_timings.tsv`:

```bash
# In scripts/aggregate-timings.sh (called at Phase 11):
awk -F'\t' 'NR > 1 { phase_wall[$2] += $4; phase_count[$2]++ }
            END { for (p in phase_wall) printf "%s\t%.3f\t%d\n", p, phase_wall[p], phase_count[p] }' \
    "$WS/script_timings.tsv" > "$WS/phase_timings.tsv"
```

Result:

| Phase | Wall (sec) | Script count | Notes |
|---|---|---|---|
| 0 | 12.4 | 3 | git-doctor, snapshot-tree, intake |
| 0.5 | 47.8 | 4 | discover-project, check-skills, cass-mine, github-pr-awareness |
| 1 | 89.2 | 1 | discover-project (deep) |
| 2 | 142.3 | 2 | discover-branches-worktrees, prefix-classifier |
| 3 | 312.7 | 4 | build-bundle (276s), verify-bundle (28s), bundle-audit (4s), recovery-test (5s) |
| ... | ... | ... | ... |

---

## 4. Comparison to SLO

After aggregation, each phase's actual wall time is compared to its MEASUREMENT.md SLO:

```bash
# In scripts/slo-comparison.sh:
declare -A SLO_STANDARD=(
    [3]=600    # Phase 3 in Standard mode: ≤(B+W)*2 seconds for B=80, W=15 = 190s; bumped for safety
    [5]=900    # Phase 5: 5–15 min; 900s is the upper bound
    [8]=2700   # Phase 8: 15–45 min; 2700s upper
    # ... per phase ...
)

mode=$(jq -r '.mode' "$PROJECT/project_profile.json")
declare -n SLO_TABLE="SLO_${mode^^}"  # e.g., SLO_STANDARD

while IFS=$'\t' read -r phase wall count; do
    slo=${SLO_TABLE[$phase]:-0}
    if (( $(echo "$wall > $slo * 1.5" | bc -l) )); then
        echo "$phase BREACHED $wall vs SLO $slo (>50%)" >> "$WS/slo_breaches.tsv"
    elif (( $(echo "$wall > $slo" | bc -l) )); then
        echo "$phase OVER $wall vs SLO $slo" >> "$WS/slo_breaches.tsv"
    fi
done < "$WS/phase_timings.tsv"
```

The `slo_breaches.tsv` is rolled into the final `performance_profile.md` as the "Phases that exceeded their SLO" section.

> **Why >50% as the breach threshold?** Per MEASUREMENT.md: SLOs are calibrated against the asupersync 213-branch + 47-worktree scenario. ±50% accounts for normal variance (network, disk cache state, parallel agent activity). >50% indicates a structural slowdown worth investigating.

---

## 5. Self-tuning — what the profile suggests for the next run

The bottleneck phase indicates which knob to turn next time.

| Bottleneck | Suggested next-run change |
|---|---|
| Phase 1 (project profile detection) >SLO | check-skills.sh probing 14 skills is slow; cache `phase0_skill_inventory.json` for 7 days (already done) — is the cache being consulted? |
| Phase 3 (bundle creation) >SLO | bump `bundle_parallelism` in project_profile.json from default 2 to 4–8 (Standard → Comprehensive concurrency) |
| Phase 5 (triage) >SLO with `<5 branches/worker/min` | spawn `language-specialist` subagent (large diffs need AST tooling) |
| Phase 5 (triage) >SLO with `>10 branches/worker/min` per worker | the workers are fast but contention is the issue; reduce worker count |
| Phase 7 (harmonization) >SLO with mean variants per file >6 | the swarm was unfocused; consider folding sibling branches before harmonization (per [HARMONIZATION.md § 5](HARMONIZATION.md)) |
| Phase 8 (apply) dominates wall time | per-keeper gates are slow; consider sampling gates instead of full-suite (only when project_profile.json `gate_sampling_allowed: true`) |
| Phase 9 (fresh-eyes) >SLO with rounds=5 | the run is non-converging; surface to user; suggest reducing scope or splitting the run |
| Phase 9.5 (audit) >SLO | per-dimension auto-fix loops are not converging; cap at 3 cycles per [AUDIT-AFTER-RUN.md § 6.1](AUDIT-AFTER-RUN.md) |
| Per-script `apply-keeper.sh` median wall >180s | gate suite is slow; document per-project `gate_command_max_wall_seconds` |

The `performance_profile.md` writes these as **explicit tuning suggestions** for the user's next run:

```markdown
## Self-Tuning for the Next Run

Based on this run's profile:

  Phase 3 spent 312s (SLO was 190s — 64% over). Recommend setting:
    project_profile.json:bundle_parallelism = 4 (currently 2)

  Phase 5 mean throughput was 4.2 branches/worker/min (target 10). Recommend:
    Spawn a language-specialist subagent at Phase 5; the project has a large Rust codebase (387 .rs files)
    and ast-grep-based fingerprinting will be faster than the default text-grep.

  Phase 8 dominated wall time (1820s of 3340s total = 54%). Recommend:
    Reduce Phase 9 round count from 3 to 2 in next run; the per-apply gates already give us
    high confidence that the rationalization branch is clean. Setting in project_profile.json:
      fresh_eyes_rounds_target = 2
```

> **Why suggestions, not auto-apply?** Per AGENTS.md "Mandatory explicit plan", configuration changes that affect future runs need user authorization. The profile produces evidence-backed recommendations; the user decides.

---

## 6. Profile output — `performance_profile.md`

Single markdown file at `<workspace>/performance_profile.md`, appended as a section to `handoff_report.md`.

### 6.1 Structure

```markdown
# Performance Profile — branch-rationalization-2026-05-07 on <basename>

Generated: 2026-05-07T16:42:18Z
Mode: Standard
Total wall time: 56 min 48 sec (3408 sec)
Total CPU time (user + sys): 4920 sec (1.44× wall — modest parallelism)

## Per-Phase Breakdown (sorted by wall descending)

| Phase | Wall | % of total | SLO (Standard) | Status |
|---|---|---|---|---|
| 8 (Apply) | 1820 | 53% | 900-2700 | OK |
| 5 (Triage) | 612 | 18% | 300-900 | OK |
| 9 (Fresh-eyes) | 487 | 14% | 600-1800 | OK (under) |
| 3 (Bundle) | 312 | 9% | 190 | BREACHED (+64%) |
| 7 (Harmonization) | 89 | 3% | 0-1800 | OK |
| ... | ... | ... | ... | ... |

[Bar chart, ASCII, sized to terminal width]

Phase 8 (Apply)        ████████████████████████████████████████████████████ 1820s
Phase 5 (Triage)       ███████████████████ 612s
Phase 9 (Fresh-eyes)   ███████████████ 487s
Phase 3 (Bundle)       ██████████ 312s
Phase 7 (Harmonization) ███ 89s
Phase 1 (Profile)      ██ 89s
Phase 2 (Inventory)    ████ 142s

## Bottleneck Callout

The dominant phase is Phase 8 (Apply) at 53% of total wall time. Within Phase 8:
  - Per-keeper gates (cargo test + cargo clippy + ubs): 78% of Phase 8 wall (1420s)
  - Cherry-pick + commit operations: 12% (218s)
  - Conflict resolution (manual user time): 10% (182s)

The gates are the rate-limiter. See "Self-Tuning for the Next Run" for the suggestion.

## Per-Script Breakdown (top 10 by wall)

| Script | Phase | Invocations | Total wall | Mean wall | Max wall |
|---|---|---|---|---|---|
| apply-keeper.sh | 8 | 23 | 1820 | 79.1 | 312 |
| triage-batch.sh | 5 | 4 | 612 | 153 | 198 |
| fresh-eyes.md (subagent) | 9 | 3 rounds × 3 prompts = 9 | 487 | 54.1 | 89 |
| build-bundle.sh | 3 | 1 | 276 | 276 | 276 |
| harmonization-plan.sh | 7 | 1 | 89 | 89 | 89 |
| ... | ... | ... | ... | ... | ... |

## Per-Subagent Breakdown

| Subagent | Phase | Invocations | Total wall | Total tokens (input + output) |
|---|---|---|---|---|
| triage-worker.md | 5 | 4 | 612 | 320,000 + 18,000 |
| harmonization-planner.md | 7 | 1 | 89 | 87,000 + 12,000 |
| keeper-applier.md | 8 | 23 | 1820 | 480,000 + 25,000 |
| fresh-eyes.md | 9 | 9 | 487 | 290,000 + 14,000 |

## Parallelism Efficiency (Comprehensive/Council only)

[Phase 5 example for Standard with 4 parallel triage workers:]

| Metric | Value |
|---|---|
| Workers spawned | 4 |
| Total branches triaged | 87 |
| Sum of per-worker wall | 612 sec |
| Phase 5 wall (max of any worker) | 198 sec |
| Speedup (sum÷max) | 3.09× |
| Parallelism efficiency (speedup ÷ N_workers) | 0.77 (target ≥0.7) |

## SLO Breaches

| Phase | Wall | SLO | Excess | Likely cause |
|---|---|---|---|---|
| 3 | 312 | 190 | +64% | bundle_parallelism=2; 47 worktrees and 213 branches; format-patch loop is serial per branch |

## Self-Tuning for the Next Run

[suggestions per § 5]
```

### 6.2 Format

The bar chart uses Unicode block characters (`█`) sized to the terminal. The chart's max width is 60 chars (fits in 80-column terminals). Each phase's bar is proportional to its wall time relative to the longest.

The per-script and per-subagent tables are sorted descending by `total_wall`. Tables are limited to top 10 to keep the report readable; the full data is in `phase_timings.tsv` and `script_timings.tsv`.

---

## 7. Cumulative profile across runs

Per /profiling-software-performance: "track baselines, flag regressions." The skill maintains a **per-project performance baseline** that subsequent runs compare against.

### 7.1 Baseline file

Stored at `<project-root>/.worktree_branch_rationalization_workspace/performance_baseline.json`:

```json
{
    "project": "/data/projects/foo",
    "schema_version": "1.0",
    "runs": [
        {
            "run_id": "beads-1234",
            "date": "2026-05-07",
            "mode": "Standard",
            "B": 87,
            "W": 18,
            "phase_timings": {"3": 312, "5": 612, "7": 89, "8": 1820, "9": 487},
            "total_wall": 3408
        },
        {
            "run_id": "beads-1567",
            "date": "2026-04-22",
            "mode": "Standard",
            "B": 64,
            "W": 12,
            "phase_timings": {"3": 198, "5": 432, "7": 56, "8": 1240, "9": 327},
            "total_wall": 2412
        }
    ]
}
```

### 7.2 Regression flagging

On each run, the new profile is compared to the median of the last 5 runs:

```bash
median_phase8=$(jq -r '.runs | sort_by(.date) | reverse | .[:5] | map(.phase_timings."8") | sort | .[length/2|floor]' "$BASELINE")
this_run_phase8=$(awk '$1==8 {print $2}' "$WS/phase_timings.tsv")

regression_pct=$(echo "scale=2; ($this_run_phase8 - $median_phase8) / $median_phase8 * 100" | bc)
if (( $(echo "$regression_pct > 25" | bc -l) )); then
    echo "Phase 8 wall regressed +${regression_pct}% vs 5-run median ($median_phase8 → $this_run_phase8)" \
        >> "$WS/regression_alerts.tsv"
fi
```

Regression alerts are surfaced in `performance_profile.md`:

```markdown
## Regressions vs Recent Runs

| Phase | This run | 5-run median | Change | Likely cause |
|---|---|---|---|---|
| 8 | 1820s | 1340s | +35.8% | new gate added to project's pre-commit hook? Check `git log -p` on `.git/hooks/pre-commit` since the last run |
| 3 | 312s | 220s | +41.8% | branch count grew 87 from 64 (+36%); proportional to growth — not a regression |
```

### 7.3 Baseline normalization

For meaningful comparison, the baseline records are normalized to per-100-branches and per-10-worktrees. A 200-branch run isn't a regression vs a 100-branch run just because it took longer — it's expected.

---

## 8. Profile in CI / shared environments

When the skill runs in CI (detected via `CI=true` env var), profiling is **enabled by default** but with one adjustment:

- Don't write to `performance_baseline.json` (CI runs are not representative of human runs).
- Do write `performance_profile.md` as a CI artifact for trend analysis.

The CI artifacts can be aggregated externally (e.g., into a Datadog dashboard) for cross-project tracking.

---

## 9. Worked example

After running on the synthetic SELF-TEST repo:

```markdown
# Performance Profile — branch-rationalization-2026-05-07 on dcg-self-test

Total wall: 8 min 12 sec
Total CPU: 9 min 47 sec (1.19× wall)

## Per-Phase Breakdown (sorted by wall)

| Phase | Wall | % | SLO | Status |
|---|---|---|---|---|
| 8 (Apply) | 240 | 49% | 300-900 | OK (under) |
| 9 (Fresh-eyes) | 132 | 27% | 300-600 | OK (under) |
| 3 (Bundle) | 32 | 6% | 16 | BREACHED (+100%) |
| 5 (Triage) | 28 | 6% | 60-300 | OK (under) |
| ... | ... | ... | ... | ... |

## Bottleneck Callout

For an 8-scenario synthetic repo, the dominant phase is Phase 8 at 49% — expected.
Phase 3 breached SLO by 100% but the absolute time (32s) is small; SLO calibration
for tiny repos may need adjustment.

## Self-Tuning for the Next Run

  No actionable tuning for synthetic SELF-TEST; the run is too small to characterize.
```

---

## 10. Cross-links

- [/profiling-software-performance](../../profiling-software-performance/SKILL.md) — source skill for the profiling methodology
- [/extreme-software-optimization](../../extreme-software-optimization/SKILL.md) — companion skill if optimization opportunities appear
- [MEASUREMENT.md](MEASUREMENT.md) — SLOs the profile compares against
- [PHASES.md](PHASES.md) — phase loop the profile measures
- [POLISH-BAR.md § Resumability](POLISH-BAR.md) — performance baseline supports cross-run comparison
- [AUDIT-AFTER-RUN.md](AUDIT-AFTER-RUN.md) — the audit catches code quality; the profile catches operational quality
- [DRY-RUN-MODE.md](DRY-RUN-MODE.md) — predicts wall time; the profile measures actual; deviation is calibration data
- [ORCHESTRATION.md](ORCHESTRATION.md) — orchestration tier (Solo/Pair/Squad/Swarm/Council) the profile validates
- [AGENTS.md "UBS"](../../../../AGENTS.md) — UBS is one of the gates that contributes to Phase 8's profile
