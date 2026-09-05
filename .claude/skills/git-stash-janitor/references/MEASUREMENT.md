# Measurement — Per-Phase SLOs and Quality Metrics

If you can't measure a phase, you can't improve it. This file defines the artifacts each phase produces, their SLOs (service-level objectives), and the quality metrics that distinguish a successful run from a half-finished one.

Adapted from documentation-website's MEASUREMENT.md and saas-billing's polish-bar metrics.

---

## Per-Phase Artifact Manifest

| Phase | Required artifacts | Optional artifacts |
|-------|-------------------|--------------------|
| 0 | `wt_phase0.txt` | `run_id.txt`, `cass_findings.md` (if Phase 0.5 ran) |
| 1 | `project_profile.json` | `architecture_summary.md` (Comprehensive) |
| 2 | `inventory.tsv`, `inventory_grouped.md` | — |
| 3 | bundle dir + `bundle_path.txt` + `bundle_verification.log` | `bundle_audit.log` (Comprehensive) |
| 4 | `triage/batch_*.tsv` (one per worker) | `triage_triangulation.tsv` (Comprehensive) |
| 5 | `triage.tsv`, `triage_decision.md`, `phase5_user_authorization.txt` | `user_overrides.tsv` |
| 6 | `apply_log.tsv` | `conflicts/stash_<NNN>.context.md` (per conflict) |
| 7 | `partial_split_log.tsv` | `<bundle>/diffs/<NNN>.split.diff` (per partial) |
| 8 | `fresh_eyes_log.md` | `triangulation_log.md` (Comprehensive) |
| 9 | `cleanup_plan.tsv`, `cleanup_authorization.txt`, `cleanup_log.tsv` | bucket-grouped sections in `cleanup_plan.tsv` / `handoff_report.md` (Comprehensive) |
| 10 | `handoff_report.md`, `polish-bar-check.sh` transcript | `post_run_bv_triage.json` |
| 11 | `skill_feedback.md` (if run) | — |

A run is "complete" only when every required artifact for the modes-run-up-to-this-point exists and is non-empty.

---

## Per-Phase SLOs (Wall Time)

These are empirical targets from the asupersync 127-stash run plus extrapolation. Use them to detect when a phase is taking unusually long (likely cause: rubric tuning issue, repo size, or network).

| Phase | Quick (5–9 by default; <5 only after warning override) | Standard (10–80) | Comprehensive (80+) |
|-------|-------------|------------------|---------------------|
| 0     | 1–3 min      | 3–5 min           | 5–10 min            |
| 0.5 (CASS) | n/a    | 2–5 min           | 5–10 min            |
| 1     | 3–5 min      | 5–15 min          | 10–30 min           |
| 2     | 1–2 min      | 2–5 min           | 5–15 min            |
| 3     | 2–5 min      | 5–15 min          | 15–45 min           |
| 4     | 5–15 min     | 20–60 min         | 60–180 min          |
| 5     | 1–5 min user | 5–15 min user     | 15–45 min user      |
| 6     | 5–30 min     | 20–60 min         | 60–180 min          |
| 7     | n/a          | 0–30 min          | 30–90 min           |
| 8     | 10–20 min    | 30–60 min         | 60–180 min          |
| 9     | 1–5 min user | 5–15 min user     | 15–45 min user      |
| 10    | 2–5 min      | 5–10 min          | 10–20 min           |
| 11    | n/a          | n/a               | 30–90 min           |
| **Total wall** | **30–60 min** | **2–4 h** | **4–10 h** |

The "user" entries are time-spent-waiting-for-user, not agent compute time. Phase 5 in Comprehensive often takes longer than the agent compute because the user reviews 100+ rows.

---

## Triage Quality Metrics (Phase 4 output)

After Phase 4 completes, run `scripts/verdict-stats.sh` to compute:

| Metric | Healthy range | Investigate if |
|--------|---------------|----------------|
| `verdict_distribution` | 60–90% superseded; 5–25% garbage; 1–5% novel | <50% superseded → likely supersession-detection issue; >40% garbage → message conventions need codifying |
| `confidence_mean` | 0.85+ | <0.80 → rubric uncertainty; consider triangulation |
| `unknown_rate` | <5% | >10% → fingerprint extractor failing on this language; spawn language-specialist |
| `partial_novel_rate` | <10% | >20% → many stashes mix landed + WIP; suggests refactor-in-progress workflow |
| `file_existence_coverage_mean` | >0.9 | <0.7 → many stashes reference deleted files; spawn archaeologist |
| `apply_check_clean_rate` | >95% | <80% → context drift heavy; spawn archaeologist for stale rows |

Anomalies signal where to spawn specialist subagents.

---

## Apply Quality Metrics (Phase 6 + Phase 7)

| Metric | Healthy | Investigate |
|--------|---------|-------------|
| `apply_success_rate` | >90% (of novel-and-accretive rows) | <70% → triage rubric over-classifying as novel |
| `gates_pass_first_try_rate` | >90% | <80% → many stashes need adapt-to-current-main; rewrite-don't-recover heuristic |
| `mean_files_changed_per_keeper` | 1–5 | >10 → keepers are too large; could be split |
| `mean_duration_per_apply_seconds` | <120 | >300 → gate suite is slow; consider running gates in parallel |
| `conflict_skipped_rate` | <10% | >30% → bundle is stale; primary branch advanced too far during run |

---

## Bundle Integrity Metrics (Phase 3 ongoing)

Computed at Phase 3 and re-checked at Phase 9 (just before cleanup):

| Metric | Required value |
|--------|----------------|
| `bundle.diff_count` | == `inventory.tsv:row_count` |
| `bundle.meta_count` | == `inventory.tsv:row_count` |
| `backup_ref_count` | == `inventory.tsv:row_count` |
| `byte_equality_mismatches` | 0 |
| `untracked_dirs_present_for_minus_u_stashes` | 100% (every `has_untracked=true` row has a stashed-untracked dir) |

ANY of these failing aborts the run.

---

## Fresh-Eyes Convergence Metrics (Phase 8)

| Metric | Pass condition |
|--------|----------------|
| `rounds_run` | ≥2 (Quick: 1; Standard: 2; Comprehensive: 3) |
| `consecutive_trivial_rounds` | ≥2 at end |
| `gates_green_at_termination` | true |
| `findings_per_round_trend` | Decreasing (round N+1 should have fewer findings than round N) |
| `same_finding_repeat_count` | <3 (if a finding appears 3 rounds, escalate as blocking-unresolvable) |

---

## Handoff Report Quality Metrics (Phase 10)

| Section | Required |
|---------|----------|
| Counts | Every verdict bucket count + final_stash_count + recovered_commit_count |
| Recovered commits table | One row per row in `apply_log.tsv` + `partial_split_log.tsv` with new_commit_sha |
| Recovery recipes | Verbatim shell commands for cherry-pick + apply, with bundle path |
| Push command | Verbatim, present-tense, NOT executed |
| Bundle lifecycle | One paragraph; mentions DCG-blocked rm; mentions `mv` to trash |
| Beads issue id | If beads available |
| polish-bar-check.sh result | Pass count + fail count |

---

## Run-Level Aggregate Metrics

After Phase 10, the handoff report includes run-level stats:

```json
{
  "run_id": "stash-janitor-2026-05-06-asupersync",
  "stash_count_initial": 127,
  "stash_count_final": 0,
  "recovered_commits": 1,
  "user_overrides_applied": 0,
  "phases_with_user_gates": 3,
  "user_authorization_phrases_recorded": 3,
  "wall_clock_seconds": 8420,
  "agent_compute_seconds": 21330,  // sum across all subagents
  "tier": "Squad",
  "mode": "Comprehensive",
  "fresh_eyes_rounds": 3,
  "triangulation_rows": 23,
  "polish_bar_pass_count": 9,
  "polish_bar_fail_count": 0
}
```

These metrics feed the `cass` index for future runs and the `bv` post-run triage.

---

## Cost Accounting (Optional)

For runs that care about agent compute cost:

```bash
# At end of Phase 10:
total_input_tokens=$(jq -s 'map(.input_tokens) | add' run_audit/*.jsonl)
total_output_tokens=$(jq -s 'map(.output_tokens) | add' run_audit/*.jsonl)
echo "Total tokens: in=$total_input_tokens out=$total_output_tokens"
```

The cost-per-recovered-commit metric is a useful efficiency signal:
- < $1 per recovered commit → cheap; run liberally
- $1–$5 → typical for Comprehensive on a 100-stash repo
- > $10 → either the recovery yield is low (most stashes superseded) or the triangulation is over-applied

---

## When Metrics Disagree With Outcomes

If Polish Bar passes but the user reports the run was useless: instrument Phase 11 user-lens review more aggressively. The metrics are a proxy for quality, not quality itself.

If Polish Bar fails but the user is happy: investigate the failing dimension. Either the dimension is over-strict or the user has accepted a known violation (which should be recorded as a known-acceptable override in the handoff).
