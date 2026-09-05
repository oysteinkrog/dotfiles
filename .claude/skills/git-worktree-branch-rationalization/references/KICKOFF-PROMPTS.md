# Kickoff Prompts — Verbatim Templates Per Mode

After Up-Front Confirmations, the main agent sends one of these prompts (verbatim) to itself or the orchestrator subagent to start the pipeline. The prompt is calibrated to the mode and includes the recorded user inputs.

> **"Spawn" means: invoke via the Task tool in the current Claude Code session.** No external orchestration is required. The prompts below work in a single-session run; if the user is running NTM, the orchestrator instead uses NTM panes for the same logical subagents (see [ORCHESTRATION.md § Optional: NTM Swarm Topology](ORCHESTRATION.md#optional-ntm-swarm-topology)).

Adapted from [git-stash-janitor's KICKOFF-PROMPTS.md](../../git-stash-janitor/references/KICKOFF-PROMPTS.md). The branch-and-worktree case adds: a **dedicated harmonization-planner subagent** at higher tiers, **two TSVs in inventory** (one for branches, one for worktrees), **multi-stage cleanup** (worktrees first, branches second, in bucket order), and **multi-model triangulation paths** for harmonization decisions per [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md).

---

## Decision Tree — Which Mode To Pick

```
W = git -C <project> worktree list --porcelain | grep -c '^worktree '
B = git -C <project> branch | wc -l    (local branches; canonical excluded)

├── W < 2 AND B < 5
│     └── REFUSE (skill is overkill); see WHEN-NOT-TO-USE.md
│
├── 2 ≤ W < 5  AND/OR  5 ≤ B < 30
│     └── Quick mode (Solo tier, single Claude session, ~15-30 min)
│
├── 5 ≤ W < 20  AND/OR  30 ≤ B < 100
│     └── Standard mode (Pair or Squad tier, ~30-90 min)
│
├── 20 ≤ W  AND/OR  100 ≤ B
│     └── Comprehensive mode (Squad/Swarm tier, ~2-6 h)
│
└── B ≥ 200  AND/OR  file collisions across ≥10 branches
      └── Comprehensive + Council tier (Swarm + multi-model triangulation,
          dedicated harmonization-planner subagent, ~4-12 h)

Stake-modifier (any tier upgrades by one if any apply):
  ├── production-critical or security-sensitive code on the contested branches
  ├── monorepo with submodules + LFS objects across ≥3 worktrees
  ├── ≥3 dirty worktrees with ≥10 untracked files each
  └── prior run was interrupted (resume mode adds an integrity-check pass)

Stake-modifier examples:
  - 12 worktrees, 60 branches, security-sensitive auth code → Comprehensive (not Standard)
  - 4 worktrees, 25 branches, just an after-swarm cleanup    → Quick
  - 47 worktrees, 213 branches, mixed agent + feature        → Comprehensive
  - 90 worktrees, 350 branches, public release pending       → Council
```

The mode is recorded in `project_profile.json` at Phase 1; phase gates (especially Phase 9 termination) adjust based on it. Per [PHASES.md § Mode Variants](PHASES.md#mode-variants).

---

## Auto-Detected Values

Every kickoff prompt fills these in from confirmed user inputs + Phase 0 detection (do NOT have the orchestrator re-detect them):

| Placeholder | Source | Example |
|---|---|---|
| `{PROJECT_PATH}` | User confirmed at intake | `/data/projects/asupersync` |
| `{BASENAME}` | `basename {PROJECT_PATH}` | `asupersync` |
| `{W}` | `git worktree list --porcelain | grep -c '^worktree '` | `47` |
| `{B}` | `git branch | wc -l` | `213` |
| `{CANONICAL}` | `git symbolic-ref refs/remotes/origin/HEAD` (then heuristics; never assume `main` per Axiom 5) | `main` or `master` or `develop` |
| `{RATIONALIZATION_BRANCH}` | Default `branch-rationalization-$(date -u +%Y-%m-%d)`; user override | `branch-rationalization-2026-05-07` |
| `{BUNDLE_PATH}` | Default `<project-parent>/<basename>-branch-worktree-archive-$(date -u +%Y-%m-%d)/` | `/data/projects/asupersync-branch-worktree-archive-2026-05-07/` |
| `{WORKSPACE}` | `<project>/.worktree_branch_rationalization_workspace/` | (constant) |
| `{OUTPUT_MODE}` | User confirmed: `full` / `triage-only` / `apply-only` | `full` |
| `{REMOTE_CLEANUP}` | User confirmed: `out-of-scope` (default) / `--prepare-remote-list` | `out-of-scope` |
| `{RUN_ID}` | UTC ISO timestamp suffix | `2026-05-07T18-30-00Z` |
| `{WORKER_COUNT}` | From the tier table in [ORCHESTRATION.md § Worker Sizing](ORCHESTRATION.md#worker-sizing) | `4` (Squad) / `12` (Swarm) |

---

## What Each Mode Triggers

| Mode | Phase 5 workers | Phase 7 dedicated planner subagent | Multi-model triangulation | Phase 9 fresh-eyes rounds | Phase 11 user-lens |
|---|---|---|---|---|---|
| **Quick** | 1 (serial) | No (inline only when ≥2 collide) | Skipped | 1 round | Skipped |
| **Standard** | 2–4 parallel | No (inline if ≥2 collide) | Opt-in only on conflict resolution | ≥2 rounds, 1 model | Skipped |
| **Comprehensive** | 5–12 parallel | **Yes** (dedicated subagent; one fan-out per colliding-file group) | Opt-in (Path A/B/C per [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md)) on Phase 5 borderlines + Phase 7 + Phase 9 rounds 2-3 | ≥3 rounds, 3 stances | Optional |
| **Council** | 12+ parallel | **Yes** + Council triangulation on the variant matrix | **Required** on Phase 5 + Phase 7 + Phase 9 rounds 2-3 + Phase 11 | ≥3 rounds, multi-model adjudicated | Optional, recommended |

---

## Quick Mode

```
You are the orchestrator for a git-worktree-branch-rationalization Quick run.

Project: {PROJECT_PATH}
Worktrees: {W}
Branches: {B}
Output mode: {OUTPUT_MODE}
Canonical branch: {CANONICAL}
Rationalization branch: {RATIONALIZATION_BRANCH}
Bundle path: {BUNDLE_PATH}
Run id: {RUN_ID}

Run the pipeline serially in this Claude Code session:

1. Phase 1: spawn project-profiler subagent → project_profile.json
2. Phase 2: spawn inventory-agent subagent (two passes) → worktrees.tsv, branches.tsv, inventory_grouped.md
3. Phase 3: spawn bundle-builder subagent → recovery bundle + verify-bundle.sh gate (HARD GATE)
4. Phase 4: present auto-protected list + user-flagged additions; capture protected.tsv (USER GATE)
5. Phase 5: triage all non-protected entries in a single batch via triage-batch.sh; one worker
6. Phase 6: spawn triage-merger subagent; present decision table; WAIT for user "go" (USER GATE)
7. Phase 7: SKIP unless ≥2 branches collide on the same file. If yes, run inline harmonization
            (no dedicated subagent in Quick mode); user reviews harmonization_plan.md (USER GATE)
8. Phase 8: spawn keeper-applier subagent; sequential applies + per-apply gates
   Phase 8b: spawn partial-splitter subagent (for partially-novel rows)
9. Phase 9: spawn fresh-eyes subagent; 1 round (Quick mode allows 1 round)
10. Phase 10: gated cleanup; verbatim authorization (USER GATE);
              worktrees first, branches second; bucket order
11. Phase 11: handoff report

Stop conditions:
- Any phase gate fails → halt and surface to user
- Phase 3 verify-bundle.sh shows any MISMATCH → halt (Axiom 3)
- Phase 6 user types anything other than approval → halt
- Phase 10 user authorization phrase doesn't include literal command → re-ask once

Per AGENTS.md "Mandatory explicit plan", every destructive command in Phase 10
is restated verbatim before execution and recorded in cleanup_log.tsv.

Per AGENTS.md "Note for Codex/GPT-5.5", working-tree changes from concurrent
agents in any worktree are treated as if you made them yourself; never stash,
revert, or overwrite (Axiom 12).
```

---

## Standard Mode

```
You are the orchestrator for a git-worktree-branch-rationalization Standard run.

Project: {PROJECT_PATH}
Worktrees: {W}
Branches: {B}
Mode: Standard ({WORKER_COUNT} parallel triage workers; ~10 entries each)
Output mode: {OUTPUT_MODE}
Canonical branch: {CANONICAL}
Rationalization branch: {RATIONALIZATION_BRANCH}
Bundle path: {BUNDLE_PATH}
Run id: {RUN_ID}

Pipeline:

Phase 0: register beads issue: br create --title "branch+worktree rationalization on {BASENAME}".
         Reserve advisory file lock on .git/worktrees/**, .git/refs/heads/** via Agent Mail
         (thread_id=branch-rationalization-{RUN_ID}).

Phase 1: spawn project-profiler. Read AGENTS.md, README.md.

Phase 2: spawn inventory-agent (two passes). Group by name-prefix family.

Phase 3: spawn bundle-builder. Verify byte-equality + git bundle list-heads round-trip.
         HARD GATE — any MISMATCH halts.

Phase 4: compute auto-protected (canonical, currently-checked-out, project-profile patterns,
         worktree-pinned branches); confirm with user; write protected.tsv.

Phase 5: partition (branches.tsv ∪ worktrees.tsv) − protected.tsv into {WORKER_COUNT}
         batches of ~10 entries.
         Spawn {WORKER_COUNT} triage-worker subagents in parallel (Task tool).
         Each writes triage/batch_<id>.tsv.
         Workers reserve only their own batch tsv via Agent Mail.

Phase 6: spawn triage-merger. Build triage_decision.md. WAIT for user "go".
         Apply user_overrides if any.

Phase 7: HARMONIZATION GATE.
         If triage.tsv has any colliding-file group (≥2 non-protected branches OR
         ≥1 non-protected branch + ≥1 dirty worktree touching the same file):
           - Run harmonization inline (single planner; one fan-out per group)
           - Write harmonization_plan.md
           - Present to user; WAIT for user OK or in-place edits via Edit tool

Phase 8: spawn keeper-applier. For each row in triage.tsv with non-skip strategy
         (chronological by branch tip date by default):
         - WORKING-TREE-DRIFT snapshot per active worktree
         - RE-FINGERPRINT against rationalization branch HEAD
         - Pick strategy: cherry-pick / squash-merge / rebase-and-merge /
           harmonized-synthesis-via-Edit / split-commits / worktree-dirty-state
         - RECOVER (run gates from project_profile.json)
         - Stage only touched paths; commit with focused message
         - Append to apply_log.tsv

         On conflict: surface to user; resolve via Edit tool only (no scripts).

         Phase 8b: spawn partial-splitter for partially-novel rows.

Phase 9: spawn fresh-eyes. ≥2 rounds, different stance per round:
         Round 1: Literal
         Round 2: Forensic
         Termination: 2 consecutive trivial-only rounds + gates green.

Phase 10: build cleanup_plan.tsv (worktrees first, then branches in bucket order:
          garbage → superseded → already-merged → novel-stale (opt-in) →
          divergent-refactor (opt-in) → applied-keepers).
          Present verbatim authorization request.
          WAIT for user phrase that includes a literal command.
          Record in cleanup_authorization.txt.
          Execute one entry at a time via drop-retire-confirmed.sh; restate verbatim per entry.
          - Worktrees: git worktree remove (then prune residual metadata at end of bucket).
          - Branches: git branch -d (lowercase) preferred; -D only when user explicitly
            acknowledged unmerged-and-discardable.

Phase 11: spawn handoff-reporter. Emit handoff_report.md. File beads issue summary.
          Run polish-bar-check.sh as final gate. Print push command verbatim.
          Do NOT push. Do NOT delete the bundle.
```

---

## Comprehensive Mode

```
You are the orchestrator for a git-worktree-branch-rationalization Comprehensive run.

Project: {PROJECT_PATH}
Worktrees: {W}
Branches: {B}
Mode: Comprehensive ({WORKER_COUNT} workers + dedicated harmonization-planner +
       opt-in multi-model triangulation)
Output mode: {OUTPUT_MODE}
Canonical branch: {CANONICAL}
Rationalization branch: {RATIONALIZATION_BRANCH}
Bundle path: {BUNDLE_PATH}
Run id: {RUN_ID}

This is a high-stakes run. Run with ALL the discipline:
- All operators applied per phase (★ 🔒 🌳 ✦ ◐ ⬡ ⚠ ◇ ✧ ⊟ ⊠ ⇄ ⊕ ⊞ ↺ ⊙ ⊘ ⌘)
- Multi-model triangulation on Phase 5 borderline rows AND Phase 7 harmonization plan
  AND Phase 9 fresh-eyes rounds 2-3 (per MULTI-MODEL-TRIANGULATION.md path A → B → C)
- One plan-level authorization in Phase 10, with commands grouped by bucket
- Phase 12 user-lens review enabled

Pipeline:

Phase 0: register beads + Mail thread (thread_id=branch-rationalization-{RUN_ID}).
         Advisory reservations on .git/worktrees/**, .git/refs/heads/**,
         .worktree_branch_rationalization_workspace/**.

Phase 0.5: CASS mining. Spawn cass-miner subagent.
           Look for prior runs of this skill on this project or similar repos.
           Look for past sessions where the user manually rationalized branches
           or worktrees (the asupersync 47-worktree+213-branch session is the
           seed). Surface relevant findings (e.g., "previous run authored 6
           harmonized syntheses; user rolled back 1; cause was missing fixture").

Phase 1: spawn project-profiler PLUS codebase-report subagent.
         Profile + 200-word architecture summary. Detect canonical, merge_style,
         protected_by_convention_patterns, branching_model, branch_name_conventions.

Phase 2: spawn inventory-agent (two passes).
         Concurrency-tolerant: if any worktree's git status changes between passes,
         re-run that worktree only (don't re-run all of Pass A).
         Group by name-prefix family.

Phase 3: spawn bundle-builder. Verify byte-equality + bundle round-trip.
         Spot-check 5 random branches via independent re-derivation
         (diff <(git diff --binary $merge_base..$sha) <bundle>/branches/<slug>/diff-vs-merge-base.diff).
         Spot-check 3 random dirty worktrees similarly.

Phase 4: spawn cleanup-conductor in advisory mode (no destructive actions yet) to
         present the auto-protected list + recommendations on stale-locked worktrees,
         [gone]-tracking branches; user reviews; write protected.tsv.

Phase 5: spawn {WORKER_COUNT} triage-workers (~10 entries each).
         For rows with confidence < 0.75: trigger MULTI-MODEL-TRIANGULATION.md
         path A (preferred) → B → C as available. Merge by intersection.
         Surface unanimous-low-confidence rows to user in Phase 6.

         If any branch references files removed from canonical
         (file_existence_coverage < 0.5): spawn archaeologist subagent
         (codebase-archaeology) for that branch → reconstruct intent before
         classifying [MODE: Forensic per MODES-OF-REASONING.md].

Phase 6: spawn triage-merger. Decision table includes a "triangulation" column
         showing model agreement. WAIT for user. Apply overrides.

Phase 7: spawn DEDICATED harmonization-planner subagent.
         For each colliding-file group, build the variant matrix per HARMONIZATION.md.
         Identify intent (8-intent taxonomy). Apply synthesis principles.
         Flag divergent-refactor rather than synthesizing when in doubt.

         If ≥3 colliding-file groups: fan out per group (parallel).
         For each row with confidence < 0.7: trigger triangulation.

         User reviews harmonization_plan.md; can edit in-place via Edit tool;
         the document IS the spec for Phase 8.

Phase 8: spawn keeper-applier. Per-apply gates (test + typecheck + lint + ubs).
         Per-conflict: spawn commit-message-author subagent to draft the commit message
         (especially for harmonized syntheses — they cite ≥2 source branches and
         must answer "where did this hunk come from?" for each hunk).
         Triangulator reviews each conflict resolution and each harmonized synthesis.

         Phase 8b: spawn partial-splitter. Edit tool only for semantic splits;
         cherry-pick of the novel commit subset (per partial-splitter.md) for
         exact commit-list filtering. No source-mutating scripts.

Phase 9: spawn fresh-eyes ≥3 rounds. Each round uses a different stance:
         - Round 1: Literal (catches overt bugs)
         - Round 2: Forensic (asks "what was the intent?" on each keeper)
         - Round 3: Adversarial (assumes the rubric / harmonization plan is wrong;
                    pays particular attention to harmonized-synthesis commits where
                    integration bugs are most likely)
         Triangulate rounds 2 and 3 across Codex + Gemini if available.

Phase 10: one verbatim authorization for the full cleanup plan. The plan groups
          commands by bucket in execution order:
          A. Worktree removal (then prune)
          B. Branch deletion: garbage
          C. Branch deletion: superseded / superseded-by-newer-branch
          D. Branch deletion: already-merged
          E. Branch deletion: novel-stale (only if user opted in)
          F. Branch deletion: divergent-refactor (only if user opted in; default skip)
          G. Branch deletion: applied-keepers
          Record the user's exact phrase in cleanup_authorization.txt.
          Per-bucket re-confirmation before each bucket's commands run.

Phase 11: spawn handoff-reporter. Full report including:
          - Triangulation summary (Phase 5 + Phase 7 + Phase 9 if used)
          - Phase 5 confidence distribution
          - Per-bucket cleanup logs
          - Harmonization summary (one row per file; variants merged; result)
          - bv --robot-triage of newly-unblocked beads
          Run polish-bar-check.sh.

Phase 12: spawn idea-wizard-reviewer for user-lens review.
          Output: skill_feedback.md with proposed improvements.
```

---

## Council Mode

```
You are the orchestrator for a git-worktree-branch-rationalization Council run.

Project: {PROJECT_PATH}
Worktrees: {W}
Branches: {B}
Mode: Council ({WORKER_COUNT}+ workers + Council triangulation on harmonization +
       multi-model adjudication on every phase gate)
Output mode: {OUTPUT_MODE}
Canonical branch: {CANONICAL}
Rationalization branch: {RATIONALIZATION_BRANCH}
Bundle path: {BUNDLE_PATH}
Run id: {RUN_ID}

This is the highest-discipline run. Reserved for production-critical or security-
sensitive content. Ban all shortcuts. Multi-model triangulation is REQUIRED, not
opt-in.

Pipeline (delta from Comprehensive — everything else identical):

Phase 0: + double-checked confirmation. The user re-states the W and B counts
         verbatim in the kickoff message ("yes, run on 47 worktrees and 213 branches").

Phase 1: + multi-model triangulation on the architecture summary. Codex and
         Gemini each produce a 200-word summary; Claude reconciles; consensus
         summary lands in project_profile.json:architecture_summary.

Phase 3: + offline copy of object-bundle.pack to a second filesystem path
         (e.g., /tmp/) for redundancy.

Phase 4: + multi-model adjudication on ambiguous protection candidates
         (e.g., long-lived feature branches that look semi-active).

Phase 5: + 12+ workers; multi-model triangulation on EVERY borderline verdict
         (confidence < 0.85 — wider band than Comprehensive's 0.75).

Phase 6: + the user-facing decision table is reviewed by a fresh-eyes subagent
         BEFORE display to ensure the bucketing is correct and the override
         column is visible.

Phase 7: COUNCIL TRIANGULATION on the variant matrix.
         Every colliding-file group's variant matrix is built independently by
         Claude AND Codex AND Gemini. Disagreements are surfaced verbatim to user.
         Per file:
         - Unanimous synthesis proposal → confidence raised to 0.95; auto-apply OK
         - Majority (2 of 3) → confidence -0.10; surface if final < 0.70
         - 3-way disagreement → forced user decision; flag as potential divergent-refactor

Phase 8: + multi-model review of every commit (not just conflicts);
         + multi-model adjudication on every conflict resolution.

Phase 9: ≥3 rounds, multi-model adjudicated, fresh-eyes review of fresh-eyes findings
         (a meta-round that asks: "Did the prior fresh-eyes rounds miss anything?
         Look at their findings and the actual code; surface what they missed.").

Phase 10: plan-level authorization + per-bucket re-confirmation + post-cleanup audit.
          The post-cleanup audit re-runs Phase 2 inventory and confirms:
          - Every protected entry still exists
          - Every backup ref still resolves
          - The bundle still verifies (byte-equality + round-trip)
          - The rationalization branch's tip matches Phase 8's recorded SHA
          Audit results in cleanup_audit.tsv.

Phase 11: full report + retro section addressing:
          - Where Council triangulation added value
          - Where it was redundant (rubric agreed with all 3 models)
          - Whether the harmonization plan's confidence calibration tracked actual
            user override rate (calibration check)

Phase 12: ALWAYS run user-lens review. The reviewer reads handoff_report.md,
          the entire harmonization plan, the apply_log.tsv, and the cleanup_audit.tsv.
          Files improvement notes to skill_feedback.md.
```

---

## Triage-Only Mode

```
You are the orchestrator for a git-worktree-branch-rationalization triage-only run.

Project: {PROJECT_PATH}
Worktrees: {W}
Branches: {B}
Output mode: triage-only

Run Phases 0–6 only. STOP after Phase 6 with the decision table delivered to user.

NO destructive actions. NO commits. NO worktree removals. NO branch deletions.

Phase 7 is OPTIONAL in triage-only:
  - If ≥2 branches collide on a file AND user opts in: run Phase 7 inline,
    write harmonization_plan.md as a deliverable, then stop.
  - If user does not opt in: skip Phase 7 entirely; the colliding files are
    flagged in triage.tsv with the HARMONIZE bucket; user reviews them later.

Phase 6 output:
- triage.tsv (verdicts)
- triage_decision.md (markdown table)
- worktrees.tsv + branches.tsv + inventory_grouped.md
- recovery bundle (always built; even in triage-only the bundle is the safety net
  per Axiom 3: "Plan for irreversibility first, classification second")
- handoff_report.md with "triage-only mode" note + recovery recipes

The bundle is built UNCONDITIONALLY. The user may decide later to run a `full`
pass; the bundle is reusable across runs as long as the branch list and worktree
list haven't changed (re-verify byte-equality before reusing).
```

---

## Apply-Only Mode

```
You are the orchestrator for a git-worktree-branch-rationalization apply-only run.

Project: {PROJECT_PATH}
Worktrees: {W}
Branches: {B}
Output mode: apply-only

Pre-condition: triage.tsv MUST exist from a prior run with output_mode=triage-only.
If not, refuse and ask the user to run triage first.

Pipeline:
1. Phase 0: confirm triage.tsv age (warn if >24h old; concurrent agents may have
   shifted the worktree/branch list).
2. Phase 1-2: skip if existing artifacts are recent and clean; otherwise re-run.
3. Phase 3: re-verify bundle (artifacts must still match live branches and worktrees).
   If bundle is stale, BUILD A NEW BUNDLE with BUNDLE_OVERRIDE suffix; never
   overwrite a non-empty bundle (Axiom 3).
4. Phase 4: re-confirm protected.tsv if stale.
5. Phase 7: re-run if harmonization_plan.md is stale or new colliding-file groups exist.
6. Phase 8: apply keepers per existing triage.tsv + harmonization_plan.md.
   Phase 8b: split-apply per existing triage.tsv.
7. Phase 9: fresh-eyes ≥2 rounds.
8. SKIP Phase 10 (cleanup). Worktrees and branches remain in place.
9. Phase 11: handoff report notes "apply-only run; worktrees and branches still present".

Use case: user wants the recovered commits but isn't ready to remove worktrees and
delete branches yet. Common when the user wants to manually push the rationalization
branch first, watch CI, then come back for cleanup.
```

---

## Resume Mode (Interrupted Prior Run)

```
You are the orchestrator for a git-worktree-branch-rationalization RESUMED run.

Project: {PROJECT_PATH}
Workspace: {PROJECT_PATH}/.worktree_branch_rationalization_workspace/  (existing)

A prior run was interrupted. Detect resumption point by checking which artifacts
exist and are non-empty:

1. Artifact presence determines completion of each phase:
   project_profile.json                                → Phase 1 done
   worktrees.tsv + branches.tsv + inventory_grouped.md → Phase 2 done
   bundle_path.txt + bundle_verification.log clean    → Phase 3 done
   protected.tsv                                       → Phase 4 done
   triage.tsv complete (row count matches expected)    → Phase 5 done
   triage_decision.md + user "go" recorded             → Phase 6 done
   harmonization_plan.md (if applicable) + user OK     → Phase 7 done
   apply_log.tsv with new_commit_sha rows              → Phase 8 in progress (resume from last applied)
   partial_split_log.tsv                               → Phase 8b done/in-progress
   fresh_eyes_log.md                                   → Phase 9 (re-run; cheap relative to risk)
   cleanup_authorization.txt                           → Phase 10 already happened; refuse to re-run

2. Tell the user what's already done and where you'll pick up.

3. If Phase 10 already happened (cleanup_log.tsv exists with rows): the run is COMPLETE.
   Re-emitting Phase 11 handoff is fine; doing anything else is not.

4. If the working tree of any worktree has changes since Phase 0's wt_phase0.txt
   (concurrent-agent drift):
   - Treat as if you made them per AGENTS.md "Note for Codex/GPT-5.5" (Axiom 12).
   - Re-snapshot to wt_phase0_resume_<timestamp>.txt.
   - Don't surprise the user with "concerned questions" about drift.

5. If apply_log.tsv has gates_status=failed-<gate> on the last row: surface to user
   with the failure context and proposed action ('mark conflict-skipped, continue
   from next' is the default).

6. If the bundle's byte-equality verification has gone stale (the live branch or
   worktree list changed since Phase 3): keep the old bundle intact and rebuild
   with a new BUNDLE_OVERRIDE suffix. Never overwrite a non-empty bundle unless
   the user explicitly approved same-run partial-bundle repair.

7. From the resume point, follow the appropriate mode's kickoff prompt above.

Resume mode never silently skips a phase whose artifact exists but might be stale.
The user always knows what's reused vs. re-run.
```

---

## After-Swarm Mode (Specialized Variant)

```
You are the orchestrator for a git-worktree-branch-rationalization After-Swarm run.

This is a specialization of {Standard | Comprehensive | Council} (pick by counts).
Triggered when the user's prompt indicates the rationalization is happening
immediately after an agent swarm session ("clean up after the swarm", "I just had
12 cc + 6 cod agents working in this repo, please rationalize"), and concurrent
agents may STILL be active.

Project: {PROJECT_PATH}
Worktrees: {W}    (may include worktrees with active agents — flag them)
Branches: {B}     (may include branches being actively committed to)

Differences from the base mode:

1. Phase 0: query the user explicitly: "Are any agents still actively working
   in this repo or its worktrees right now?" If yes:
   - Run agent-mail file_reservation_paths(... [".git/worktrees/**",
     ".git/refs/heads/**"], reason="branch-rationalization-{RUN_ID}") with
     ttl_seconds=7200 (longer than default).
   - Add the active agents' worktrees to the protected.tsv with reason
     "active-agent-session". The user reviews and confirms.

2. Phase 2: re-inventory IS expected to drift between passes. Capture
   "drift_observed" in inventory_grouped.md as evidence.

3. Phase 5: every triage worker, before reading a branch's diff, re-checks
   `git rev-parse refs/heads/<name>` against the bundle's recorded SHA.
   If drift: the branch was advanced by a concurrent agent; freeze the
   bundle's SHA as the triage subject and add a note to the verdict.

4. Phase 8: WORKING-TREE-DRIFT check (↺ operator) is run BEFORE EVERY apply
   (not just at the start of Phase 8). Per Axiom 12, never disturb. Re-snapshot
   per worktree per apply.

5. Phase 10: before each git worktree remove, re-check whether any agent has
   modified that worktree since the bundle's capture. If yes, re-capture the
   dirty state into a NEW bundle subdirectory (worktrees/<wt_slug>-<timestamp>/)
   before running git worktree remove. The user reviews the new captures
   inline before authorizing the removal.

6. Phase 11: handoff report includes a section "Concurrent-agent observations"
   listing every drift event observed during the run.

This mode addresses the user's hard-won insight that branch-and-worktree
rationalization typically runs IMMEDIATELY AFTER a swarm session — the very
session that created the pile this skill is rationalizing. Per the cass-mined
sessions where the user manually rationalized branches/worktrees, the most
common failure mode is "another agent modified the file mid-rationalization".
This mode bakes that expectation into every gate.

See ORCHESTRATION.md § "Running After (or During) a Swarm" for the topology
details.
```

---

## Anti-Patterns in Kickoff

| ✗ | Why |
|---|-----|
| Running Comprehensive when W=3, B=12 | Worker overhead dominates; Quick is faster end-to-end |
| Running Quick when W=47, B=213 | Single triage worker is the bottleneck; Phase 5 takes hours |
| Skipping Phase 7 on a 200-branch repo | Agent-swarm aftermath always has file collisions; pick-or-drop loses content |
| Running without `{CANONICAL}` filled in | Don't assume `main`; refuse and re-detect (Axiom 5) |
| Running with the user's CWD inside a worktree marked for removal | The active worktree is auto-protected (Axiom 11); re-confirm protected.tsv |
| Re-running Phase 10 after `cleanup_log.tsv` exists | Refuse; the run is complete; re-emit handoff if needed |
| Bundling without verifying byte-equality + round-trip | Phase 3 is a hard gate (Axiom 3); skipping it makes the run unsafe |

---

## Cross-References

- Phase-by-phase playbook + per-phase exit criteria: [PHASES.md](PHASES.md)
- Per-subagent verbatim prompts: [AGENT-PROMPTS.md](AGENT-PROMPTS.md)
- Tier-selection details + parallelism boundaries: [ORCHESTRATION.md](ORCHESTRATION.md)
- Multi-model triangulation paths A → B → C: [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md)
- Mid-run incident response: [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md)
- Mode definitions + mode-variant table: [SKILL.md § Mode Variants](../SKILL.md#mode-variants)
- The intake-prompt template: `assets/intake-prompt.md`
