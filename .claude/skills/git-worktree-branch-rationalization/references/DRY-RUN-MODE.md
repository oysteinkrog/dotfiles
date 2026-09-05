# Dry-Run Mode — Top-Level Preview Before Any Mutation

A top-level dry-run synthesizes every Phase 8 apply and every Phase 10 destructive action into a single review artifact **before** the run executes any of them. The user reads one document and decides go/no-go for the whole run. Per-apply dry-runs (already in `apply-keeper.sh` via `git cherry-pick --no-commit`) are local to one keeper; the top-level dry-run is the strategic preview that the per-apply dry-runs feed into.

Adapted from [/saas-billing-patterns-for-stripe-and-paypal](../../saas-billing-patterns-for-stripe-and-paypal/SKILL.md) — that skill's principle "every mutation must be previewable" is the source axiom for this file. Cross-link to [SKILL.md Source Corpus § saas-billing-patterns](../SKILL.md#source-corpus): "dry-run-before-mutate ergonomics."

> **The contract.** When the user types `--dry-run` at intake (or sets `DRY_RUN=1` in the environment), the run goes all the way through Phase 8 and Phase 10 in **simulation mode**: every command is enumerated, every outcome is predicted, every artifact is written to a `dry_run_report.md` — and **nothing is mutated**. The rationalization branch is not created, no cherry-pick lands, no worktree is removed, no branch is deleted, no backup ref is touched.

---

## 1. Why a top-level dry-run mode

The skill already has per-apply dry-runs at three points:

- Phase 5 triage worker runs `git cherry-pick --no-commit` as an **apply-check** to set the `apply_check_status` column ([TRIAGE-RUBRIC.md § Apply check](TRIAGE-RUBRIC.md)).
- Phase 8 `apply-keeper.sh` runs `git cherry-pick --no-commit` before every actual cherry-pick — only on clean dry-run does it commit.
- Phase 8b `partial-splitter.md` per-commit dry-runs.

Those three are **local** safety nets — each one prevents a single bad apply. They don't tell the user what the **whole run** will look like. Specifically, the per-apply dry-run can't predict:

- The order of applies (re-fingerprinting may flip a verdict downstream)
- Total disk freed by Phase 10 worktree removals
- Total branches that will be deleted, by bucket
- Cumulative conflict density (helps user decide between Squad and Swarm tier)
- Whether Phase 10 cleanup will leave any open PRs broken
- Whether CI workflow YAML references branches scheduled for deletion (per [CI-WORKFLOW-AWARENESS.md](CI-WORKFLOW-AWARENESS.md))
- Whether any worktree's `origin` remote points at a local clone (per [REMOTE-AS-WORKTREE-FOOTGUN.md](REMOTE-AS-WORKTREE-FOOTGUN.md))

Per **/saas-billing-patterns-for-stripe-and-paypal**: a billing system's `--dry-run` previews the *entire* charge-and-invoice flow before running it. Branch rationalization is structurally similar — many small mutations compose into one large state change. The cumulative preview is what makes the change **reviewable** instead of merely **reversible**.

> **Why a separate mode and not just print-then-run?** Print-then-run makes the user authorize from a stale plan: by the time the user has read the plan, the run has already moved. Dry-run mode produces the same plan as a static artifact the user can pause on, share with a peer (per `/slb` two-person rule for high-stakes runs), or convert into a `expected_outcomes.json` that the real run validates against (Section 7). Cross-link to [AGENTS.md "Mandatory explicit plan"](../../../../AGENTS.md): the user reviews the plan, *then* authorizes.

---

## 2. How dry-run differs from per-apply dry-runs

| Layer | Scope | Output | When it runs | Mutation? |
|---|---|---|---|---|
| Phase 5 apply-check | One branch | `triage.tsv:apply_check_status` column | Phase 5 triage | None |
| Phase 8 cherry-pick `--no-commit` | One commit | console + abort on non-zero | Inside `apply-keeper.sh`, before each apply | None (auto-`git cherry-pick --abort` on dirty) |
| Phase 8b partial-splitter `--no-commit` | One commit subset | per-row in `partial_split_log.tsv:dry_run_status` | Inside `partial-splitter.md` | None |
| **Top-level dry-run** | **Whole Phase 8 + Phase 10** | **`dry_run_report.md` + `expected_outcomes.json`** | **From intake all the way through, before any apply** | **None — guard at every mutation site** |

Top-level dry-run **subsumes** the lower layers: when `DRY_RUN=1`, every script consults the env var and short-circuits at the mutation boundary, but still produces the prediction. The lower per-apply dry-runs are the building blocks the top-level mode composes.

Cross-link to [PHASES.md § Phase 8 — Apply](PHASES.md) and [PHASES.md § Phase 10 — Destructive Cleanup](PHASES.md) for the actions being previewed.

---

## 3. What dry-run produces

The artifact is a single file: `<workspace>/dry_run_report.md`. Its sections mirror the phase loop.

### 3.1 Report header (summary counts)

```markdown
# Dry-Run Report — branch+worktree rationalization on <basename>

Generated: <UTC timestamp>
Mode: <Quick|Standard|Comprehensive|Council>
Run id: <beads id or synthetic>
Bundle path (would be written to): <path>
Rationalization branch (would be created): branch-rationalization-<DATE>

## Summary

| Phase | Action | Count |
|---|---|---|
| 8 cherry-pick    | commits to land via cherry-pick | 23 |
| 8 squash-merge   | branches to land via squash      | 7 |
| 8 rebase-merge   | branches to land via rebase      | 2 |
| 8 harmonized     | per-file syntheses               | 5 (touching 12 files) |
| 8 split-apply    | partial-novel branches           | 4 (recovering 9 commits) |
| 8 dirty-wt-only  | worktree dirty captures          | 3 |
| 10 worktree rm   | worktrees to remove              | 17 |
| 10 branch -d     | branches to delete (merged)      | 28 |
| 10 branch -D     | branches to delete (unmerged)    | 6 |
| Predicted conflicts | files needing user resolution | 2 |
| Disk freed (estimate) | sum of worktree sizes        | 14.3 GB |
| Backup-refs created | one per deleted branch          | 34 |
| CI YAML edits required | files needing branch-ref bumps | 2 |

Predicted total wall time: 38–62 min (Standard tier)
```

### 3.2 Phase 8 prediction sections

Each Phase 8 action gets a sub-section. Format:

```markdown
## Phase 8 § Cherry-Pick — `wip-BACK-1742`

Source: `wip-BACK-1742` @ sha `8a3d2c9`
Strategy: `cherry-pick`
Predicted outcome: **CLEAN** (per Phase 5 `apply_check_status=clean`)
Files touched: 3 (`src/parser.rs`, `src/parser_test.rs`, `tests/fixtures/ok_packet.bin`)
Predicted commit message subject: `recover defensive OK-packet length-cap from wip-BACK-1742`
Predicted commit SHA shape: ~12 hex (cannot be predicted exactly; SHA depends on parent + author + timestamp)
Per-keeper gates that would run: `cargo test --lib parser::tests`, `cargo clippy -- -D warnings`, `ubs src/parser.rs src/parser_test.rs`
Predicted gate outcome: **PASS** (per `apply_check_status=clean` AND no canonical drift since fingerprinting)

If executed, this would call:
  git cherry-pick --no-commit 8a3d2c9
  # then commit with the predicted subject + body per COMMIT-MESSAGE-CRAFT.md
```

### 3.3 Phase 8 harmonized-synthesis sections

Harmonization is the cognitive move that distinguishes this skill (Axiom 1). Dry-run renders the **proposed code** as part of the preview:

```markdown
## Phase 8 § Harmonized Synthesis — `src/logger.rs`

Variants composed:
| Source branch | Source SHA | Hunk | Identified intent |
|---|---|---|---|
| agent-cleanup-pass-3 | 4f0e2a1 | redact_secrets() guard | defensive |
| feature/length-cap   | b91d77c | OK-packet length cap | defensive (different vector) |
| feature/redact-secrets | 5e22a8b | trace-redaction map | refactor + observability |
| (worktree) `data-projects-foo--wt-3` | (dirty) | type-narrowing on `LogEvent` | type-narrowing |

Proposed synthesis (will be applied via Edit tool, NOT a script):

```rust
pub fn redact_secrets(event: &LogEvent) -> RedactedLogEvent {
    let mut out = RedactedLogEvent::new(event);
    out.cap_payload(MAX_PAYLOAD);  // from feature/length-cap
    out.apply_redaction_map(&REDACTION_MAP);  // from feature/redact-secrets
    if let LogEvent::Trace { secret_keys, .. } = event {
        out.guard_secret_keys(secret_keys);  // from agent-cleanup-pass-3
    }
    out
}
```

Predicted commit message subject: `harmonize logger hardening from agent-cleanup-pass-3 + feature/length-cap + feature/redact-secrets`
Predicted gate outcome: **PASS** (variant matrix confidence 0.92; intent attribution coverage 100%)

If executed, this would write the above synthesis via the Edit tool, run gates, then commit per COMMIT-MESSAGE-CRAFT.md § Harmonized synthesis pattern.
```

The proposed code is rendered verbatim — the user can paste it into a peer-review tool, share via `/slb`, or annotate before the run executes. Cross-link to [HARMONIZATION.md](HARMONIZATION.md) for the variant-matrix methodology.

### 3.4 Phase 10 destructive prediction sections

For every removal, the verbatim command + the protected-status check + the predicted disk freed:

```markdown
## Phase 10 § Worktree Removal — `data-projects-foo--wt-3`

Verbatim command (would run): `git worktree remove /data/projects/foo--wt-3`
Protected-status check: `protected.tsv` has no entry → safe to remove
Worktree dirty state: 4 staged files, 2 unstaged, 1 untracked → archived to bundle § `worktrees/data-projects-foo--wt-3/`
Disk freed (estimate via `du -sh`): 1.7 GB
Active worktree (the user's CWD)? No → eligible for removal
Concurrent-agent activity (per `git status` snapshot): clean → eligible
Backup ref to be created: `refs/branch-rationalization-backup/feature-redact-secrets-5e22a8b78f12`

If executed, this would call:
  # 1. Final dirty-state re-snapshot (per Axiom 12 working-tree-drift):
  ./scripts/snapshot-tree.sh /data/projects/foo--wt-3 final
  # 2. Compare to bundle's snapshot — abort if drift:
  diff <(snapshot) "<bundle>/worktrees/data-projects-foo--wt-3/status.txt"
  # 3. Remove (refused on dirty by git itself; --force only with verbatim user OK):
  git worktree remove /data/projects/foo--wt-3
```

```markdown
## Phase 10 § Branch Deletion — `feature/redact-secrets`

Verbatim command (would run): `git branch -d feature/redact-secrets`
Backup ref (would be created): `refs/branch-rationalization-backup/feature-redact-secrets-5e22a8b78f12`
`-d` vs `-D`: `-d` (branch is fully merged onto rationalization branch — Axiom 8)
Bucket: `applied-keeper`
Position in cleanup order: 23 of 34
Protected-status check: `protected.tsv` has no entry → safe to delete

Pre-conditions verified (would be re-checked at execution time):
  - Phase 8 cherry-pick of 5e22a8b landed on rationalization branch (commit aa11bb22 per apply_log.tsv)
  - `git merge-base --is-ancestor feature/redact-secrets branch-rationalization-<DATE>` = 0
  - Backup ref `refs/branch-rationalization-backup/feature-redact-secrets-5e22a8b78f12` is present in bundle's namespace

If executed, this would call:
  git update-ref refs/branch-rationalization-backup/feature-redact-secrets-5e22a8b78f12 \
    refs/heads/feature/redact-secrets    # (already done in Phase 3, sanity-checked here)
  git branch -d feature/redact-secrets
```

### 3.5 Predicted conflicts

For Phase 5 rows with `apply_check_status=conflict`, dry-run renders the **conflict context** the user would see at Phase 8:

```markdown
## Predicted Conflict — `wip-BACK-2071` on `src/webhook.rs`

Cherry-pick dry-run output:
  CONFLICT (content): Merge conflict in src/webhook.rs

Predicted conflict location: src/webhook.rs:L245-L267
Conflicting hunks:
  - canonical's match-expression refactor (commit a1b2c3d, 2026-04-22)
  - branch's defensive null-check (commit 8c5e7f1, 2026-04-18)

User decision required before Phase 8 can proceed.
Suggested action: include in harmonization plan (Phase 7) — see [HARMONIZATION.md § 4 Per-file variant matrix].
```

### 3.6 CI workflow + remote topology callouts

Cross-link to [CI-WORKFLOW-AWARENESS.md](CI-WORKFLOW-AWARENESS.md) and [REMOTE-AS-WORKTREE-FOOTGUN.md](REMOTE-AS-WORKTREE-FOOTGUN.md). If either applies, dry-run surfaces it as a separate top-level callout BEFORE the per-action sections:

```markdown
## CALLOUT — CI workflow YAML references branches scheduled for deletion

The following branches are scheduled for deletion in Phase 10:
  - master  (would be deleted as `superseded-by-newer-branch`)

But these CI files reference them:
  - .github/workflows/ci.yml:7        on: push: branches: [master, main]
  - README.md:142                     curl https://.../master/install.sh

→ Run will refuse Phase 10 cleanup of `master` until CI YAML is updated.
→ See ci_workflow_updates.md for proposed edits (would be authored at Phase 4 if confirmed).
```

```markdown
## CALLOUT — Worktree `origin` topology footgun

The following worktrees have `origin` pointing at a local path (not http/https/ssh/git):
  - /data/projects/frankensqlite-wt-bench → origin = file:///data/projects/frankensqlite

→ Phase 11 push instructions would print `git push github branch-rationalization-<DATE>`,
   NOT `git push origin branch-rationalization-<DATE>`. See remote_topology.md.
→ Phase 10 cleanup is REFUSED for any worktree on this list until user acknowledges.
```

---

## 4. Dry-run for the destructive phase specifically

Phase 10 is the highest-stakes phase. Dry-run renders the **entire cleanup plan** as a single review document, in the order Phase 10 would execute:

```markdown
## Phase 10 — Destructive Cleanup Plan (DRY-RUN; nothing executed)

Order (per Axiom 9 + Axiom 10):
  1. Worktree removals (17)
  2. Branch deletions in bucket order:
     a. garbage (4)
     b. superseded (12)
     c. already-merged (8)
     d. novel-stale (4)  → opt-in only
     e. divergent-refactor (2)  → opt-in only
     f. applied-keepers (4)

For each entry:
  [WT 1/17]  /data/projects/foo--wt-3
    cmd: git worktree remove /data/projects/foo--wt-3
    backup-status: archived in bundle § worktrees/data-projects-foo--wt-3/
    protected-check: PASS
    disk-freed: 1.7 GB
  [WT 2/17]  /data/projects/foo--wt-cleanup
    ...
  [BR 1/34]  agent-noop-pass-7
    cmd: git branch -d agent-noop-pass-7
    backup-ref: refs/branch-rationalization-backup/agent-noop-pass-7-19a4b6d3
    bucket: garbage
    -d vs -D: -d (no novel commits)
    protected-check: PASS
  [BR 2/34]  ...
```

Authorization preview: the user is shown what they'd be asked to type when they run for real.

```markdown
At Phase 10 execution, the user will be asked to type:

  yes I understand and want to remove 17 worktrees and delete 34 branches per cleanup_log.tsv

This authorization will be recorded in cleanup_authorization.txt with a UTC timestamp.

If the user does NOT type that exactly, Phase 10 refuses to run and the rationalization
branch is left intact for the user to push manually.
```

> **Why preview the auth phrase?** Per AGENTS.md "Mandatory explicit plan": "restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct." Showing the auth phrase in dry-run lets the user evaluate it in context before they commit to typing it.

---

## 5. Dry-run + harmonization

The harmonization plan (Phase 7, `harmonization_plan.md`) is **itself a dry-run for synthesis** — the user reviews variants and the proposed synthesis before any synthesis actually lands. Top-level dry-run extends this:

- Phase 7 always runs (in dry-run or real), because it's the cognitive phase that builds the synthesis. It writes `harmonization_plan.md` regardless of dry-run mode.
- In dry-run, Phase 8 reads `harmonization_plan.md`, renders each synthesis as a `## Phase 8 § Harmonized Synthesis` section, but does **not** apply via Edit. The proposed code is in the report; no file changes.

> **Why split the harmonization render between Phase 7 plan and dry-run preview?** The harmonization plan focuses on the *variant matrix* (what hunks come from where, what intent each represents). The dry-run preview focuses on the *integration* (the resulting file content + the resulting commit). Both are useful at different points in the user's review.

Cross-link to [HARMONIZATION.md § 4 Per-file variant matrix](HARMONIZATION.md) for the harmonization-plan format, and to [COMMIT-MESSAGE-CRAFT.md § Harmonized synthesis](COMMIT-MESSAGE-CRAFT.md) for the resulting commit-message shape.

---

## 6. Output format

The dry-run report is a single markdown file at `<workspace>/dry_run_report.md` with the following structure:

```
# Dry-Run Report — branch+worktree rationalization on <basename>

[header — generation timestamp, mode, run id, bundle path, rationalization branch]

## Summary
[counts table from § 3.1]

## CALLOUT
[CI workflow + remote-topology footguns from § 3.6, only if any apply]

## Phase 8 — Apply Preview

### § Cherry-Pick
[one sub-section per cherry-pick from § 3.2]

### § Squash-Merge
[one sub-section per squash-merge]

### § Rebase-and-Merge
[one sub-section per rebase-and-merge]

### § Harmonized Synthesis
[one sub-section per synthesis from § 3.3]

### § Split-Apply (Phase 8b)
[one sub-section per partial-novel branch]

### § Dirty-Worktree-Only
[one sub-section per worktree dirty capture]

## Predicted Conflicts
[from § 3.5; one sub-section per predicted conflict]

## Phase 10 — Destructive Cleanup Plan
[from § 4]

## Predicted Authorization Phrase
[from § 4]

## Total Predicted Wall Time
[from § 3.1, with phase-by-phase breakdown]

## Reversibility Story
For every action above, the recovery recipe (read from RECOVERY-RECIPES.md):
[one row per action: action → recovery recipe id → verbatim command]
```

A companion file `<workspace>/expected_outcomes.json` carries the structured prediction (Section 7).

---

## 7. Resumability — `expected_outcomes.json`

A successful dry-run produces a structured JSON the actual run can compare against. If reality diverges from prediction, halt and surface.

### 7.1 File shape

```json
{
  "schema_version": "1.0",
  "generated_at": "2026-05-07T14:23:45Z",
  "run_id": "beads-1234",
  "rationalization_branch": "branch-rationalization-2026-05-07",
  "bundle_path": "/data/projects/foo-branch-worktree-archive-2026-05-07/",
  "phase_8": {
    "cherry_pick": [
      {
        "source_branch_slug": "wip-BACK-1742-8a3d2c9bf01a",
        "source_sha": "8a3d2c9bf01a3e57",
        "strategy": "cherry-pick",
        "predicted_apply_status": "clean",
        "predicted_files_touched": ["src/parser.rs", "src/parser_test.rs", "tests/fixtures/ok_packet.bin"],
        "predicted_gate_status": "pass"
      }
    ],
    "harmonized_synthesis": [
      {
        "target_file": "src/logger.rs",
        "source_branches": ["agent-cleanup-pass-3", "feature/length-cap", "feature/redact-secrets"],
        "source_shas": ["4f0e2a1", "b91d77c", "5e22a8b"],
        "variant_matrix_id": "harmonization_plan.md#L12-L67",
        "synthesis_confidence": 0.92,
        "predicted_gate_status": "pass"
      }
    ]
  },
  "phase_10": {
    "worktree_removals": [
      {
        "path": "/data/projects/foo--wt-3",
        "predicted_disk_freed_bytes": 1825361920,
        "backup_status": "archived",
        "protected": false
      }
    ],
    "branch_deletions": [
      {
        "name": "feature/redact-secrets",
        "slug": "feature-redact-secrets-5e22a8b78f12",
        "bucket": "applied-keeper",
        "delete_flag": "-d",
        "backup_ref": "refs/branch-rationalization-backup/feature-redact-secrets-5e22a8b78f12"
      }
    ]
  },
  "callouts": {
    "ci_workflow_updates_required": ["master"],
    "remote_topology_footguns": []
  }
}
```

### 7.2 Real-run validation

When the real run executes (without `DRY_RUN=1`), `apply-keeper.sh` and `drop-retire-confirmed.sh` consult `expected_outcomes.json` and compare reality to prediction. Any divergence halts the run with a clear surface to the user:

| Divergence | Action |
|---|---|
| A predicted-clean cherry-pick now conflicts | Halt at that apply; surface with both the predicted-clean status and the actual conflict context; user decides go/no-go |
| A predicted-pass gate fails | Halt; the canonical drifted between dry-run and execution; re-run dry-run to refresh the prediction |
| A worktree's predicted disk freed differs by >20% | Warn (the worktree size changed since dry-run); proceed if user confirms |
| A branch scheduled for `-d` now requires `-D` | Halt; the branch's merge status changed between dry-run and execution |
| A branch scheduled for deletion has gained new commits | Halt; concurrent agent pushed work to the branch (per Axiom 12, treat as if you made it — but **don't delete it**); user decides |
| A worktree's status snapshot drifted | Halt; re-snapshot per [WORKTREE-STATE.md](WORKTREE-STATE.md); user decides go/no-go |

> **Why re-validate?** Per Axiom 12 (working-tree-drift): "Snapshot once at Phase 0; re-snapshot before each destructive operation." `expected_outcomes.json` is the formal version of "the dry-run snapshot" — the real run validates against it the same way it validates against the bundle's byte-equality.

Cross-link to [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md) for the surfacing patterns.

### 7.3 expected_outcomes.json freshness

A dry-run report goes stale when canonical advances. The real run computes a `staleness_window` from `expected_outcomes.json:generated_at`:

| Window | Behavior |
|---|---|
| <1 hour | Trust dry-run; validate at each mutation site as above |
| 1–24 hours | Warn at intake: "dry-run is N hours old; canonical may have advanced; consider re-running dry-run" |
| >24 hours | Refuse to consume; require fresh dry-run before real execution |

> **Why an upper bound?** Beyond 24 hours, the rate of canonical advance + agent-swarm activity makes the prediction unreliable. The user's mental model from yesterday's dry-run isn't reliable today.

---

## 8. Worked example — the synthetic 8-scenario SELF-TEST repo

The skill's `SELF-TEST.md` references a synthetic repo with 8 scenarios covering every verdict + worktree-state combination. A dry-run on that repo produces:

```markdown
# Dry-Run Report — branch+worktree rationalization on dcg-self-test
Generated: 2026-05-07T14:23:45Z
Mode: Standard
Bundle path (would be written to): /tmp/dcg-self-test-branch-worktree-archive-2026-05-07/
Rationalization branch (would be created): branch-rationalization-2026-05-07

## Summary
| Phase | Action | Count |
|---|---|---|
| 8 cherry-pick    | commits to land via cherry-pick | 2 (scenarios A, D) |
| 8 squash-merge   | branches to land via squash      | 1 (scenario E) |
| 8 harmonized     | per-file syntheses               | 1 (scenarios F+G colliding on src/parser.rs) |
| 8 split-apply    | partial-novel branches           | 1 (scenario H) |
| 10 worktree rm   | worktrees to remove              | 3 (scenarios A-wt, C-wt, F-wt) |
| 10 branch -d     | branches to delete (merged)      | 5 |
| 10 branch -D     | branches to delete (unmerged)    | 1 (scenario H, opt-in only) |
| Predicted conflicts | files needing user resolution | 0 |
| Disk freed (estimate) | sum of worktree sizes        | 12 MB |
| Backup-refs created | one per deleted branch          | 6 |
| CI YAML edits required | files needing branch-ref bumps | 0 |

Predicted total wall time: 8–12 min (Quick tier — small enough to bump down)

## Phase 8 — Apply Preview

### § Cherry-Pick — `scenario-A` (novel-and-accretive)
Source: scenario-A @ b1c2d3e (1 commit ahead of canonical, file `tests/scenario_a.rs`)
Predicted outcome: CLEAN
Predicted commit subject: `recover scenario-A novel test from scenario-A`

### § Cherry-Pick — `scenario-D` (partially-novel single-commit)
Source: scenario-D @ aa11bb2 (1 novel commit + 1 already-merged commit; only the novel one is picked)
Predicted outcome: CLEAN

### § Squash-Merge — `scenario-E` (small-coherent)
Source: scenario-E (5 commits → squash to 1)
Predicted commit subject: `recover scenario-E small-coherent feature from scenario-E (squash)`

### § Harmonized Synthesis — `src/parser.rs` (scenarios F + G)
Variants composed:
| Source branch | Hunk | Intent |
|---|---|---|
| scenario-F | parse_v2() defensive null-check | defensive |
| scenario-G | parse_v2() type-narrowing for &[u8] inputs | type-narrowing |

Proposed synthesis (rendered in dry-run; would be written via Edit):
[full synthesized parse_v2() function body]

Predicted commit subject: `harmonize parser hardening from scenario-F + scenario-G`

### § Split-Apply (Phase 8b) — `scenario-H` (partially-novel multi-commit)
3 of 5 commits are novel; 2 are already-merged.
Predicted outcome: 3 commits cherry-picked, 2 skipped

## Phase 10 — Destructive Cleanup Plan

[WT 1/3]  /tmp/dcg-self-test-wt-A
  cmd: git worktree remove /tmp/dcg-self-test-wt-A
  backup-status: archived
  disk-freed: ~4 MB
[WT 2/3]  /tmp/dcg-self-test-wt-C
  ...
[BR 1/6]  scenario-B (already-merged)
  cmd: git branch -d scenario-B
  bucket: already-merged
  ...

## Reversibility Story

| Action | Recovery recipe |
|---|---|
| 17 worktree removals | RECOVERY-RECIPES.md R4 / R10 |
| 34 branch deletions  | RECOVERY-RECIPES.md R1 / R2 / R9 |
| Rationalization branch | RECOVERY-RECIPES.md R6 / R7 |
| Whole run undo       | RECOVERY-RECIPES.md R13 |
```

The user reads this once, decides go/no-go, and either:

- Re-runs without `--dry-run` (validates against `expected_outcomes.json`), OR
- Edits the triage / harmonization plan, re-runs dry-run, repeats until satisfied, OR
- Aborts (no work was lost; nothing was mutated).

---

## 9. Implementation notes for scripts

Every script that mutates checks `DRY_RUN`:

```bash
# In scripts/apply-keeper.sh, scripts/drop-retire-confirmed.sh, etc.:
if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY-RUN] would run: $cmd_to_predict"
    record_to_dry_run_report "$cmd_to_predict" "$predicted_outcome"
    exit 0
fi
# … real mutation here …
```

The intake script (Phase 0) sets `DRY_RUN=1` in the workspace's `env.sh` if `--dry-run` is passed; every later script sources `env.sh` first. Cross-link to [PHASES.md § Phase 0](PHASES.md).

> **Why guard at the script boundary, not at a single top-level branch?** Per AGENTS.md "No Script-Based Changes": brittle regex transforms create more problems than they solve. The same wisdom applies to a single conditional at the top: if dry-run is implemented as one big `if ! DRY_RUN; then …; fi`, every new mutation site has to remember to nest under it. Guarding at the script-boundary (every mutating script consults `DRY_RUN` independently) makes the contract explicit and grep-able: `git grep DRY_RUN scripts/`.

---

## 10. Cross-links

- [PHASES.md](PHASES.md) — what each phase does (the action sequence dry-run previews)
- [AUDIT-AFTER-RUN.md](AUDIT-AFTER-RUN.md) — the post-run audit (the dry-run is its forward-looking analogue)
- [KICKOFF-PROMPTS.md](KICKOFF-PROMPTS.md) — intake template; `--dry-run` is offered at "Output mode?"
- [HARMONIZATION.md](HARMONIZATION.md) — the variant-matrix methodology dry-run renders
- [COMMIT-MESSAGE-CRAFT.md](COMMIT-MESSAGE-CRAFT.md) — the predicted commit-message shape
- [CI-WORKFLOW-AWARENESS.md](CI-WORKFLOW-AWARENESS.md) — CI YAML callout in § 3.6
- [REMOTE-AS-WORKTREE-FOOTGUN.md](REMOTE-AS-WORKTREE-FOOTGUN.md) — remote topology callout in § 3.6
- [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) — the recipes referenced in the Reversibility Story section
- [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md) — surface-and-halt patterns when reality diverges from prediction
- [WORKTREE-STATE.md](WORKTREE-STATE.md) — re-snapshot semantics dry-run depends on
- [/saas-billing-patterns-for-stripe-and-paypal](../../saas-billing-patterns-for-stripe-and-paypal/SKILL.md) — source axiom: "every mutation must be previewable"
- [AGENTS.md "Mandatory explicit plan"](../../../../AGENTS.md) — verbatim authorization the dry-run preview lets the user evaluate
