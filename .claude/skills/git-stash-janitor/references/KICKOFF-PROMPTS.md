# Kickoff Prompts — Verbatim Templates Per Mode

After Up-Front Confirmations, the main agent sends one of these prompts (verbatim) to itself or the orchestrator subagent to start the pipeline. The prompt is calibrated to the mode and includes the recorded user inputs.

> **"Spawn" means: invoke via the Task tool in the current Claude Code session.** No external orchestration is required. The prompts below work in a single-session run; if the user is running NTM, the orchestrator instead uses NTM panes for the same logical subagents (see ORCHESTRATION.md § Optional: NTM Swarm Topology).

Adapted from the saas-billing-patterns kickoff-prompts pattern.

---

## Quick mode (5–9 stashes by default; <5 only after warning override)

```
You are the orchestrator for a git-stash-janitor Quick run.

Project: {PROJECT_PATH}
Stash count: {N}
Output mode: {full | triage-only | apply-only}
Recovery branch: {RECOVERY_BRANCH}
Bundle path: {BUNDLE_PATH}

Run the pipeline serially:

1. Phase 1: spawn project-profiler subagent → project_profile.json
2. Phase 2: spawn inventory-agent subagent → inventory.tsv
3. Phase 3: spawn bundle-builder subagent → recovery bundle + verify-bundle.sh gate
4. Phase 4: triage all {N} stashes in a single batch via triage-batch.sh; one worker
5. Phase 5: spawn triage-merger subagent; present decision table; WAIT for user "go"
6. Phase 6: spawn keeper-applier subagent; sequential applies + per-apply gates
7. Phase 7: skip if no partially-novel rows; otherwise spawn partial-splitter
8. Phase 8: spawn fresh-eyes subagent; ≥1 round (Quick mode allows 1 round)
9. Phase 9: gated cleanup; verbatim authorization
10. Phase 10: handoff report

Stop conditions: any phase gate fails → halt and surface to user.
```

---

## Standard mode (10–80 stashes)

```
You are the orchestrator for a git-stash-janitor Standard run.

Project: {PROJECT_PATH}
Stash count: {N}
Mode: Standard ({worker_count} parallel triage workers)
Output mode: {OUTPUT_MODE}
Recovery branch: {RECOVERY_BRANCH}
Bundle path: {BUNDLE_PATH}

Pipeline:

Phase 0: register beads issue (br create --title "stash janitor pass on {basename}").
         Reserve advisory file lock on .git/** via Agent Mail.

Phase 1: spawn project-profiler. Read AGENTS.md, README.md, run codebase-archaeology.

Phase 2: spawn inventory-agent. Group by message-prefix family.

Phase 3: spawn bundle-builder. Verify byte-equality. HARD GATE.

Phase 4: partition inventory.tsv into {worker_count} batches of ~20 stashes.
         Spawn {worker_count} triage-worker subagents in parallel.
         Each writes triage/batch_<id>.tsv.
         Workers reserve only their own batch tsv.

Phase 5: spawn triage-merger. Build triage_decision.md. WAIT for user "go".
         Apply user_overrides if any. Capture phase5_user_authorization.txt.

Phase 6: spawn keeper-applier. For each novel-and-accretive row in triage.tsv (chronological):
         - WORKING-TREE-DRIFT snapshot
         - RE-FINGERPRINT against recovery branch HEAD
         - APPLY-3WAY --check then apply
         - RECOVER (run gates from project_profile.json)
         - Stage + commit with focused message (rewrite from auto-generated)
         - Append to apply_log.tsv
         On conflict: surface to user; resolve via Edit tool only.

Phase 7: spawn partial-splitter for partially-novel rows.

Phase 8: spawn fresh-eyes. ≥2 rounds. Termination: 2 consecutive trivial-only rounds + gates green.

Phase 9: build cleanup_plan.tsv (bucket-ordered, descending n per bucket).
         Present verbatim authorization request.
         WAIT for user phrase that includes a literal command.
         Record in cleanup_authorization.txt.
         Drop one at a time via drop-confirmed.sh; never `git stash clear`.

Phase 10: spawn handoff-reporter. Emit handoff_report.md. File beads issue summary.
          Run polish-bar-check.sh as final gate. Print push command.
          Do NOT push.
```

---

## Comprehensive mode (80+ stashes; flagship project)

```
You are the orchestrator for a git-stash-janitor Comprehensive run.

Project: {PROJECT_PATH}
Stash count: {N}
Mode: Comprehensive ({worker_count} workers + multi-model triangulation)
Output mode: {OUTPUT_MODE}
Recovery branch: {RECOVERY_BRANCH}
Bundle path: {BUNDLE_PATH}

This is a high-stakes run. Run with ALL the discipline:
- All operators applied per phase (★ ✦ ◐ ⬡ ⚠ ✧ ⇄ ⊕ ⊙ ⌘ ⊞ ↺)
- Multi-model triangulation on Phase 4 borderline rows AND Phase 8 rounds 2-3
- One plan-level authorization in Phase 9, with commands grouped by bucket
- Phase 11 user-lens review enabled

Pipeline:

Phase 0: register beads + Mail thread. Reserve .git/**, .stash_janitor_workspace/**.

Phase 0.5: CASS mining. Spawn cass-miner subagent.
           Look for prior runs of this skill on this project or similar repos.
           Surface relevant findings (e.g., "previous run authored 3 keepers; user rolled back 1").

Phase 1: spawn project-profiler PLUS codebase-report subagent.
         Profile + 200-word architecture summary.

Phase 2: spawn inventory-agent. Group by message-prefix family.

Phase 3: spawn bundle-builder. Verify byte-equality. Spot-check 5 random stashes via
         independent re-derivation (`diff <(git stash show -p --binary <sha>) <bundle>/diffs/<n>.diff`).

Phase 4: spawn {worker_count} triage workers (~20 stashes each).
         For rows with confidence < 0.75: spawn triangulator subagent
         (Codex + Gemini independent triage on those rows). Merge by intersection.
         Surface unanimous-low-confidence rows to user in Phase 5.

         If any stash references files removed from main (file_existence_coverage < 0.5):
         spawn archaeologist subagent for that stash → reconstruct intent before classifying.

Phase 5: spawn triage-merger. Decision table includes a "triangulation" column showing
         model agreement. WAIT for user. Apply overrides.

Phase 6: spawn keeper-applier. Per-apply gates (test + typecheck + lint + ubs).
         Per-conflict: spawn commit-message-author subagent to draft the commit message.
         Triangulator reviews each conflict resolution.

Phase 7: spawn partial-splitter. Use Edit tool for semantic splits; use `partial-split.sh` only for exact hunk-number filtering.

Phase 8: spawn fresh-eyes ≥3 rounds. Each round uses a different reading stance:
         - Round 1: literal/skeptical (catches overt bugs)
         - Round 2: forensic (asks "what was the intent?" on each keeper)
         - Round 3: adversarial (assumes the rubric is wrong)
         Triangulate rounds 2 and 3 across Codex + Gemini.

Phase 9: one verbatim authorization for the full cleanup plan. The plan groups
         commands by bucket in execution order:
         - garbage
         - superseded / superseded-by-newer-stash
         - novel-but-stale
         - applied-keeper (last)
         Record the user's exact phrase in cleanup_authorization.txt.

Phase 10: spawn handoff-reporter. Full report including:
          - Triangulation summary
          - Phase 4 confidence distribution
          - Per-bucket drop logs
          - bv --robot-triage of newly-unblocked beads
          Run polish-bar-check.sh.

Phase 11: spawn idea-wizard-reviewer for user-lens review.
          Output: skill_feedback.md with proposed improvements.
```

---

## Triage-only mode (any stash count)

```
You are the orchestrator for a git-stash-janitor triage-only run.

Project: {PROJECT_PATH}
Stash count: {N}
Output mode: triage-only

Run Phases 1–5 only. STOP after Phase 5 with the decision table delivered to user.

NO destructive actions. NO commits. NO drops.

Phase 5 output:
- triage.tsv (verdicts)
- triage_decision.md (markdown table)
- inventory.tsv
- recovery bundle (always built; even in triage-only the bundle is the safety net)
- handoff_report.md with "triage-only mode" note + recovery recipes

Make the bundle anyway. The user may decide later to run a `full` pass; the bundle
is reusable across runs as long as the stash list hasn't changed.
```

---

## Apply-only mode

```
You are the orchestrator for a git-stash-janitor apply-only run.

Project: {PROJECT_PATH}
Stash count: {N}
Output mode: apply-only

Pre-condition: triage.tsv must exist from a prior run with output_mode=triage-only.
If not, refuse and ask the user to run triage first.

Pipeline:
1. Phase 0: confirm triage.tsv age (warn if >24h old).
2. Phase 1-5: skip if existing artifacts are recent and clean.
3. Phase 3: re-verify bundle (artifacts must still match live stashes).
4. Phase 6: apply keepers per existing triage.tsv.
5. Phase 7: split-apply per existing triage.tsv.
6. Phase 8: fresh-eyes ≥2 rounds.
7. SKIP Phase 9 (cleanup). Stashes remain in the list.
8. Phase 10: handoff report notes "apply-only run; stashes still present".

Use case: user wants the recovered commits but isn't ready to drop the stashes yet.
```

---

## Resume mode (interrupted prior run)

```
You are the orchestrator for a git-stash-janitor RESUMED run.

Project: {PROJECT_PATH}
Workspace: {PROJECT}/.stash_janitor_workspace/  (existing)

A prior run was interrupted. Detect resumption point:

1. Check what artifacts exist:
   project_profile.json → Phase 1 done
   inventory.tsv → Phase 2 done
   bundle_path.txt + bundle_verification.log clean → Phase 3 done
   triage.tsv complete → Phase 4 done
   phase5_user_authorization.txt → Phase 5 done
   apply_log.tsv with keepers → Phase 6 in progress (resume from last applied)
   fresh_eyes_log.md → Phase 8 (re-run; cheap relative to risk)
   cleanup_authorization.txt → Phase 9 already happened; refuse to re-run

2. Tell the user what's already done and where you'll pick up.

3. If Phase 9 already happened (cleanup_log.tsv exists with rows): the run is COMPLETE.
   Re-emitting Phase 10 handoff is fine; doing anything else is not.

4. If the working tree has changes from the prior run (e.g., a half-applied keeper):
   surface to user with the apply_log.tsv:gates_status and proposed action
   ('mark conflict-skipped, continue from next' is the default).

5. If the bundle's byte-equality verification has gone stale (the live stash list
   changed since Phase 3): keep the old bundle intact and rebuild with a new
   `BUNDLE_OVERRIDE` suffix. Never overwrite a non-empty bundle unless the user
   explicitly approved same-run partial-bundle repair.

6. From the resume point, follow the appropriate mode's kickoff prompt above.
```
