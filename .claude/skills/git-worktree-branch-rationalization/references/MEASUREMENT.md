# Measurement — Per-Phase SLOs and Quality Metrics

If you can't measure a phase, you can't improve it. This file defines the artifacts each phase produces, their SLOs (service-level objectives), and the quality metrics that distinguish a successful run from a half-finished one.

Adapted from [git-stash-janitor's MEASUREMENT.md](../../git-stash-janitor/references/MEASUREMENT.md). Two units of management (branches + worktrees) double the artifact-count vs. stash-janitor and shift the wall-time targets accordingly.

> **Why measurement at all?** Per [SKILL.md "The Polish Bar"](../SKILL.md#the-polish-bar-non-negotiable): "A 'successful rationalization run' is not 'the branches are gone.'" Every Polish-Bar dimension here has a corresponding metric — if the metric isn't being measured, the dimension isn't being checked.

---

## 1. Per-Phase Artifact Manifest

| Phase | Required artifacts | Optional artifacts |
|---|---|---|
| 0 | `wt_phase0.txt`, `bundle_path.txt` (placeholder) | `run_id.txt` (if beads available), `cass_findings.md` (if Phase 0.5 ran) |
| 1 | `project_profile.json` | `architecture_summary.md` (Comprehensive) |
| 2 | `worktrees.tsv`, `branches.tsv`, `inventory_grouped.md` | — |
| 3 | bundle dir + `bundle_path.txt` (final) + `bundle_verification.log` | `bundle_audit.log` (Comprehensive) |
| 4 | `protected.tsv` | `protected_diff.md` (Comprehensive — diff vs auto-protected) |
| 5 | `triage/batch_*.tsv` (one per worker), `triage.tsv` | `triage_triangulation.tsv` (Comprehensive) |
| 6 | `triage_decision.md`, `phase6_user_authorization.txt` | `user_overrides.tsv` |
| 7 | `harmonization_plan.md` (only if ≥2 branches collide on a file) | `harmonization_triangulation.md` (Council) |
| 8 | `apply_log.tsv` | `conflicts/branch_<slug>.context.md` (per conflict) |
| 8b | `partial_split_log.tsv` | `<bundle>/branches/<slug>/diff-vs-merge-base.split.diff` (per partial) |
| 9 | `fresh_eyes_log.md` | `triangulation_log.md` (Comprehensive) |
| 10 | `cleanup_authorization.txt`, `cleanup_log.tsv` | bucket-grouped sections in `cleanup_log.tsv` (Comprehensive) |
| 11 | `handoff_report.md`, `polish-bar-check.sh` transcript | `post_run_bv_triage.json`, `post_run_bv_priority.json` |
| 12 | `skill_feedback.md` (if run) | — |

A run is "complete" only when every required artifact for the modes-run-up-to-this-point exists and is non-empty. The `polish-bar-check.sh` script (Phase 11) verifies this.

---

## 2. Per-Phase SLOs (Wall Time)

These are empirical targets calibrated against the asupersync 213-branch + 47-worktree scenario and extrapolation. Use them to detect when a phase is taking unusually long (likely cause: rubric tuning issue, repo size, or network).

`B` = branch count (excluding canonical), `W` = worktree count (excluding the active worktree).

| Phase | Quick (W<5, B<30) | Standard (W 5–20, B 30–100) | Comprehensive (W 20+, B 100+) | Council (production-critical) |
|---|---|---|---|---|
| 0 | 1–3 min | 3–5 min | 5–10 min | 10–15 min |
| 0.5 (CASS) | 1–2 min | 2–5 min | 5–15 min | 15–30 min |
| 1 | 3–5 min | 5–15 min | 10–30 min | 20–45 min |
| 2 | ≤ (B + W) seconds | 2–5 min | 5–15 min | 10–30 min |
| 3 | ≤ (B + W) seconds | ≤ (B + W) × 2 seconds | ≤ (B + W) × 2 seconds | ≤ (B + W) × 3 seconds (with redundant verification) |
| 4 | 1–3 min user | 3–10 min user | 10–30 min user | 30–60 min user (multi-model adjudication) |
| 5 | 1–5 min agent | 5–15 min agent | 15–45 min agent | 45–120 min agent |
| 6 | 1–3 min user | 3–10 min user | 10–30 min user | 15–45 min user |
| 7 | n/a (skipped) | 0–30 min | 30–90 min | 60–180 min |
| 8 | 5–15 min | 15–45 min | 45–180 min | 60–240 min |
| 8b | 0–5 min | 0–15 min | 0–30 min | 0–45 min |
| 9 | 5–10 min | 10–30 min | 30–90 min | 60–180 min |
| 10 | 2–5 min | 5–10 min | 10–20 min | 15–30 min (with slb peer review) |
| 11 | 1–3 min | 3–10 min | 10–30 min | 30–60 min |
| 12 | n/a | n/a | 0–30 min (optional) | 0–60 min (optional) |
| **Total wall** | **30–60 min** | **1.5–4 h** | **3–8 h** | **6–14 h** |

> **Why Phase 3 is `(B + W) × N` seconds?** Phase 3 builds backup refs + the object bundle + per-branch diffs + per-branch format-patch series + per-worktree dirty captures. Each of those is `O(1) per entity` if the per-entity build is done in parallel. The SLO accounts for parallelism: Quick mode is single-threaded, Standard parallelizes 2-way, Comprehensive parallelizes 4–8 way (worker count comes from `project_profile.json:bundle_parallelism`).

The "user" entries are time-spent-waiting-for-user, not agent compute time. Phase 4 (protection confirmation) and Phase 6 (triage confirmation) often take longer than the agent compute because the user reviews tables of 100+ rows.

---

## 3. Phase 5 Triage Throughput

| Metric | Healthy | Investigate if |
|---|---|---|
| `branches_per_worker_per_min` | ~10 (a worker does fingerprint + verify-on-canonical + cherry-vs-canonical + verdict per branch) | <5 → fingerprint extraction is expensive (likely large diffs) → spawn language-specialist |
| `worktrees_per_worker_per_min` | ~20 (worktrees triage faster: just dirty-state classification + canonical comparison) | <10 → many worktrees with dirty state requiring deeper inspection |
| `verdict_distribution` | 30–60% superseded; 10–30% already-merged; 5–25% novel-and-accretive; 5–15% partially-novel; 5–15% novel-but-stale; 0–10% divergent-refactor; 0–5% garbage | superseded <20% → likely supersession-detection issue (canonical recently force-pushed?); garbage >15% → message conventions need codifying |
| `confidence_mean` | ≥0.85 | <0.80 → rubric uncertainty; consider triangulation. Council mode triggers automatic multi-model triangulation when confidence_mean <0.80 |
| `unknown_rate` (`pending-user-confirmation` verdicts) | <5% | >10% → fingerprint extractor failing on this language; spawn language-specialist or escalate to Comprehensive |
| `partial_novel_rate` | <15% | >25% → many branches mix landed + WIP; suggests refactor-in-progress workflow; user may want to delay the run until the refactor lands |
| `apply_check_clean_rate` (`git cherry-pick --no-commit --check` succeeds) | >85% (of novel-and-accretive rows) | <70% → context drift heavy; canonical advanced too far during the agent-swarm period; consider rebasing branches against current canonical before triage |

Anomalies signal where to spawn specialist subagents.

**How to measure:** `scripts/triage-batch.sh` writes per-worker timestamps; `scripts/merge-triage.sh` aggregates into `triage.tsv` columns `verdict`, `confidence`, `apply_check_status`. The verdict-stats subagent (called from `scripts/polish-bar-check.sh`) computes the distribution.

**What to do if missed:** lower the mode (Comprehensive → Standard re-runs are cheap), run multi-model triangulation via `/multi-model-triangulation` for borderline rows, or surface to user with a reduced-scope plan ("triage just the agent-cc-* family this run; revisit the rest").

---

## 4. Phase 7 Harmonization Plan Quality

| Metric | Healthy | Investigate if |
|---|---|---|
| `harmonization_plan_generation_seconds_per_contested_file` | ≤ 30 sec (Standard) / ≤ 60 sec (Comprehensive — deeper variant analysis) | >120 sec → harmonization-planner is over-deliberating; check if too many variants per file (>6 typically means the swarm was unfocused) |
| `mean_variants_per_contested_file` | 2–4 | >6 → swarm was unfocused; consider folding sibling branches before harmonization (per [HARMONIZATION.md § 5](HARMONIZATION.md)) |
| `intent_attribution_coverage` (% of variants with non-empty `identified intent`) | 100% | <100% → harmonization-planner couldn't classify some hunks; surface to user before Phase 8 |
| `synthesis_proposal_coverage` (% of contested files with a `proposed synthesis` filled in) | 100% | <100% → some files are blocked-on-user-decision; halt Phase 8 until resolved |
| `divergent_refactor_count` | 0–N (informational) | High counts mean the swarm did incompatible refactors; surface as "explicit divergence; user picks one" |
| `confidence_mean_per_synthesis` | ≥0.80 | <0.70 forces user decision per [HARMONIZATION.md § 2](HARMONIZATION.md) variant matrix `confidence` column |

**How to measure:** `scripts/harmonization-plan.sh` writes per-file timestamps; the harmonization-planner subagent emits `harmonization_plan.md` with one section per contested file, with a confidence per row.

**What to do if missed:** spawn additional harmonization-planner subagents (Council tier triangulates across Codex + Claude + Gemini); OR surface to user explicitly with the variant matrix and "I cannot synthesize this file confidently — please decide manually".

---

## 5. Phase 8 Apply Quality

| Metric | Healthy | Investigate if |
|---|---|---|
| `apply_throughput_keepers_per_minute` | ~1 keeper / 60s + per-apply gate time | <0.5/min → gates are slow; consider running gates in parallel against the working tree (carefully — only when all gates are read-only) |
| `apply_success_rate` (% of `novel-and-accretive` rows that produced a clean commit) | >90% | <70% → triage rubric over-classifying as novel; re-fingerprint and re-verify |
| `harmonized_synthesis_first_apply_pass_rate` (% of harmonized commits that pass gates on first apply) | ≥90% | <80% → the synthesis is over-ambitious; consider fewer composed variants per synthesis |
| `gates_pass_first_try_rate` (% of any keeper that passes test/typecheck/lint on first try) | >90% | <80% → many keepers need adapt-to-current-canonical work; escalate to manual Edit per file |
| `mean_files_changed_per_keeper` | 1–8 (harmonized syntheses naturally touch more files than single-branch cherry-picks) | >15 → the synthesis is too broad; split |
| `mean_duration_per_apply_seconds` | <180 (gates dominate) | >600 → gate suite is slow; consider running gates in parallel or sampling |
| `conflict_skipped_rate` | <10% | >25% → bundle is stale; canonical advanced too far during run; halt and re-bundle or escalate to manual |
| `re_fingerprint_flip_rate` (% of remaining keepers whose verdict flipped after the most-recent apply per [Axiom: ⊞ RE-FINGERPRINT](OPERATOR-LIBRARY.md)) | 5–25% | 0% → re-fingerprinting may not be running; >40% → triage was too coarse, many "duplicates" lurking |

**How to measure:** `scripts/apply-keeper.sh` writes a row to `apply_log.tsv` per keeper with `start_time`, `end_time`, `gates_status`, `new_commit_sha`. The polish-bar script aggregates per-keeper.

**What to do if missed:** lower throughput targets are acceptable for Comprehensive mode (the priority is correctness, not speed). For `apply_success_rate < 70%`, halt and re-triage; for `conflict_skipped_rate > 25%`, halt and re-bundle.

---

## 6. Bundle Integrity Metrics (Phase 3 ongoing)

Computed at Phase 3 and re-checked at Phase 10 (just before destructive cleanup):

| Metric | Required value |
|---|---|
| `bundle.branch_diff_count` | == `branches.tsv:row_count` |
| `bundle.branch_format_patch_subdir_count` | == `branches.tsv:row_count` |
| `bundle.branch_meta_count` | == `branches.tsv:row_count` |
| `bundle.worktree_meta_count` | == `worktrees.tsv:row_count` (excluding the active worktree, which is auto-protected) |
| `bundle.worktree_status_count` | == `worktrees.tsv:row_count` |
| `bundle.worktree_staged_diff_count` | == `worktrees.tsv:row_count` |
| `bundle.worktree_unstaged_diff_count` | == `worktrees.tsv:row_count` |
| `bundle.untracked_tarball_count` | == count of worktrees whose Phase 2 inventory had `untracked > 0` |
| `backup_ref_count_branches` | == `branches.tsv:row_count` |
| `byte_equality_mismatches` | 0 |
| `bundle_round_trip_status` | "OK" (`git bundle list-heads` succeeds AND every listed ref resolves) |

ANY of these failing aborts the run. Per [Axiom 3](../SKILL.md#the-rationalization-kernel-universal-axioms): "Plan for irreversibility first, classification second."

**How to measure:** `scripts/verify-bundle.sh` produces `bundle_verification.log` with per-metric pass/fail. `scripts/polish-bar-check.sh` re-runs the verification before Phase 10.

**What to do if missed:** halt the run; spawn the incident-responder subagent with `INCIDENT_CODE=I1` (bundle byte-equality mismatch). Recovery via re-running Phase 3 end-to-end.

---

## 7. Phase 9 Fresh-Eyes Convergence Metrics

| Metric | Pass condition |
|---|---|
| `rounds_run` | Quick: 1; Standard: ≥2; Comprehensive: ≥3; Council: ≥3 with multi-model adjudication |
| `consecutive_trivial_rounds` | ≥2 at end (Quick: 1) — see [FRESH-EYES-PROMPTS.md § termination rules](FRESH-EYES-PROMPTS.md) |
| `gates_green_at_termination` | true (project's `test`, `typecheck`, `lint`, `ubs` all exit 0) |
| `findings_per_round_trend` | Decreasing (round N+1 should have fewer findings than round N) |
| `same_finding_repeat_count` | <3 (if a finding appears 3 rounds, escalate as blocking-unresolvable per [FRESH-EYES-PROMPTS.md "Convergence detection"](FRESH-EYES-PROMPTS.md)) |
| `harmonization_specific_findings_count` | 0 by termination — every harmonized synthesis preserves each cited intent |
| `cleanup_specific_findings_count` | 0 by termination — backup refs intact, bundle round-trips, rationalization-branch tip is clean |
| `mean_round_duration_minutes` | ≤10 per round (per [FRESH-EYES-PROMPTS.md](FRESH-EYES-PROMPTS.md) round budget) |

**How to measure:** the fresh-eyes subagent writes one block per round into `fresh_eyes_log.md` with `findings_count`, `severity_distribution`, `gates_status`, `round_duration_minutes`. Convergence is computed by comparing rounds.

**What to do if missed:** if `same_finding_repeat_count >= 3`, surface to user as a blocking issue requiring manual decision; if rounds keep generating new substantive findings, the rationalization branch may be unsound — consider rolling back via the bundle.

---

## 8. Triage Accuracy

| Metric | Healthy | Investigate if |
|---|---|---|
| `triage_override_rate` (% of Phase 5 verdicts changed by user in Phase 6) | <5% | >15% → rubric is miscalibrated; investigate which verdict bucket has the most overrides |
| `verdict_change_after_phase8_apply` (% of remaining keepers whose verdict flipped post-apply per ⊞ RE-FINGERPRINT) | 5–25% | 0% → re-fingerprinting may not be running; >40% → triage was too coarse |

> **Why ≥95% triage accuracy?** Per the brief: "Triage accuracy: ≥95% of verdicts unchanged after Phase 6 user review (low override count)." If users override more than 5%, the rubric needs project-specific tuning; the cass-findings (per [CASS-MINING.md](CASS-MINING.md)) often surface convention-discoveries that fix the underlying rubric.

---

## 9. Resumability

| Metric | Required |
|---|---|
| `resume_success_rate` (% of mid-run interruptions that resume cleanly via the workspace's per-phase artifacts) | ≥95% |
| `phase_idempotence` (re-running a completed phase produces the same artifacts) | 100% for Phases 0–7; 100% conditional on `apply_log.tsv` for Phase 8 (already-applied keepers skipped) |

**How to measure:** the integration-test (`scripts/integration-test.sh`) injects a SIGTERM mid-Phase-N and verifies that re-running picks up from the last-completed phase boundary.

**What to do if missed:** the per-phase artifact must be re-checked for completeness before resuming; if any artifact is partial (e.g., `apply_log.tsv` ends mid-row), the inventory-agent re-snapshots and the apply-keeper subagent re-applies from the last-known-good commit.

> **Why this matters:** Per [SKILL.md "The Polish Bar"](../SKILL.md#the-polish-bar-non-negotiable): "Resumable — If interrupted mid-Phase 8, re-running picks up from the last successful commit using `apply_log.tsv` + git log on the rationalization branch." A skill that loses an hour of work to a SIGINT is not production-ready.

---

## 10. Polish Bar Coverage

| Dimension | Pass = | Where measured |
|---|---|---|
| Recovery completeness | 100% (every entry has all 5 layers) | Phase 3 verify + Phase 10 pre-cleanup re-verify |
| Verdict evidence | 100% (every triage row cites concrete evidence) | Phase 5 worker output |
| No phantom keepers | 0 (no novel without FINGERPRINT proving symbols don't exist) | Phase 5 + Phase 6 review |
| Harmonization fidelity | 100% (every contested file has a variant matrix) | Phase 7 harmonization_plan.md |
| Per-apply gates | 100% (every Phase 8 commit has gates passing) | Phase 8 apply_log.tsv |
| Focused commit messages | 100% (every keeper-commit explains *why* with source-branch citations) | Phase 8 + Phase 11 review |
| Order of cleanup | Worktrees → branches; protected NEVER deleted | Phase 10 cleanup_log.tsv |
| Verbatim authorization | Phase 10 gated on cleanup_authorization.txt presence + content | Phase 10 |
| Idempotent | Re-run produces no commits | scripts/integration-test.sh |
| Resumable | ≥95% | Section 9 |

Total: 10 dimensions; ALL must pass for the run to be "complete." Per [SKILL.md "The Polish Bar"](../SKILL.md#the-polish-bar-non-negotiable): "If a run can't satisfy these, it has not 'completed successfully' — it has half-finished and needs to flow back through whichever phase failed."

**How to measure:** `scripts/polish-bar-check.sh` runs all 10 checks; any fail blocks the handoff.

---

## 11. Run-Level Aggregate Metrics

After Phase 11, the handoff report includes run-level stats:

```json
{
  "run_id": "branch-rationalization-2026-05-07-asupersync",
  "branch_count_initial": 213,
  "branch_count_final": 7,
  "worktree_count_initial": 47,
  "worktree_count_final": 2,
  "recovered_keepers": 23,
  "harmonized_syntheses": 7,
  "user_overrides_applied": 4,
  "phases_with_user_gates": 5,
  "user_authorization_phrases_recorded": 5,
  "wall_clock_seconds": 18420,
  "agent_compute_seconds": 67330,
  "tier": "Squad",
  "mode": "Comprehensive",
  "fresh_eyes_rounds": 3,
  "triangulation_rows": 0,
  "polish_bar_pass_count": 10,
  "polish_bar_fail_count": 0,
  "rationalization_branch": "branch-rationalization-2026-05-07",
  "rationalization_branch_tip": "abc123def456...",
  "bundle_path": "/data/projects/asupersync-branch-worktree-archive-2026-05-07",
  "bundle_size_bytes": 184320000,
  "beads_issue": "br-1742",
  "cass_findings_count": 8
}
```

These metrics feed the `cass` index for future runs (via the session's natural indexing) and the `bv` post-run triage.

---

## 12. Cost Accounting (Optional)

For runs that care about agent compute cost:

```bash
# At end of Phase 11:
total_input_tokens=$(jq -s 'map(.input_tokens) | add' run_audit/*.jsonl)
total_output_tokens=$(jq -s 'map(.output_tokens) | add' run_audit/*.jsonl)
echo "Total tokens: in=$total_input_tokens out=$total_output_tokens"
```

Cost-per-recovered-keeper (or cost-per-deleted-branch) is a useful efficiency signal:

| Range | Interpretation |
|---|---|
| < $1 / keeper | Cheap; run liberally |
| $1–$5 / keeper | Typical for Comprehensive on a 100-branch repo |
| > $20 / keeper | Either the recovery yield is low (most branches superseded) or triangulation is over-applied — consider Standard tier |

| Range | Cost-per-deleted-branch |
|---|---|
| < $0.10 | Healthy; deleting is cheap, the value is in the *backup* layer |
| > $1 | The triage rubric is over-deliberating on branches that should be obviously superseded; tune `protected_by_convention_patterns` |

---

## 13. When Metrics Disagree With Outcomes

If Polish Bar passes but the user reports the run was useless: instrument Phase 12 user-lens review more aggressively. The metrics are a proxy for quality, not quality itself.

If Polish Bar fails but the user is happy: investigate the failing dimension. Either the dimension is over-strict or the user has accepted a known violation (which should be recorded as a known-acceptable override in the handoff).

> **Why measurement is descriptive, not prescriptive:** Metrics let an agent (or operator) recognize *that something is off* before deciding *what to do about it*. They never replace user judgment. Per AGENTS.md "Mandatory explicit plan": every destructive action requires explicit user authorization, regardless of how green the metrics look.

---

## 14. Cross-links

- Polish Bar dimensions: [POLISH-BAR.md](POLISH-BAR.md)
- Phase exit criteria: [PHASES.md](PHASES.md)
- Triage rubric (verdict definitions): [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md)
- Bundle integrity contract: [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md)
- Fresh-eyes termination rules: [FRESH-EYES-PROMPTS.md](FRESH-EYES-PROMPTS.md)
- Recovery recipes (when metrics signal a halt): [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md), [ADVANCED-RECOVERY.md](ADVANCED-RECOVERY.md)
