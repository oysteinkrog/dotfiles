# Resumability

**Source axiom:** Axiom 20. A clean run produces the same artifacts as a busy run, just with empty bodies. Re-entry never crashes; it always produces a coherent state.

This reference is the per-phase resumability contract.

---

## Two kinds of resume

### 1. Clean re-run on a previously-cleaned repo

Goal: emit "nothing to do" gracefully.

Behavior:
- Phase 1 re-uses `project_profile.json` if present and ≤7 days old; else re-runs.
- Phase 2 always re-runs (cheap; produces fresh `candidates.tsv`).
- Phase 2.5 always re-runs (security regression-check; cheap).
- Phase 3 detects existing bundle, verifies byte-equality of any candidates that survived; if matches, skips re-creation.
- Phase 4 short-circuits when `candidates.tsv` is empty (header-only file).
- Phase 5 emits "nothing to triage" decision table.
- Phases 6, 7, 8 short-circuit; nothing to apply.
- Phase 9 always runs (verification cost is cheap relative to risk; would catch any drift).
- Phase 10 emits "0 candidates triaged, 0 commits authored" handoff.

The handoff says "repo is clean; no action needed."

### 2. Resume mid-run after interruption

Goal: continue from the last successful state.

Behavior per phase:
- Phase 1: re-uses if fresh.
- Phase 2: re-runs (cheap).
- Phase 2.5: re-runs.
- Phase 3: reuses bundle if `bundle_verification.log` shows zero mismatches; else rebuilds.
- Phase 4: re-runs only batches without a `batch_NNN.tsv`. Already-completed batches are kept.
- Phase 5: re-presents the merged decision table; user re-confirms or overrides.
- Phase 6: reads `apply_log.tsv`; skips already-committed moves (matched by candidate id).
- Phase 7: analogous via `apply_log.tsv`.
- Phase 8: refuses to re-run if `.gitignore` already has the proposed additions; emits "already done."
- Phase 9: always re-runs.
- Phase 10: re-emits `handoff_report.md` from the latest log files.

---

## Resumability state file

`<workspace>/run_state.json`:

```json
{
  "run_id": "repo-janitor-20260508T170000Z",
  "mode": "full",
  "tier": "T3+2 (effective T4)",
  "started_at": "2026-05-08T17:00:00Z",
  "phase_completed": "6",
  "phase_in_progress": "7",
  "next_phase": "7",
  "resumable": true,
  "phase_artifacts": {
    "1": ["project_profile.json"],
    "2": ["candidates.tsv", "candidates_grouped.md", "reference_graph.json"],
    "2.5": ["secret_findings.tsv"],
    "3": ["bundle_verification.log"],
    "4": ["triage/batch_001.tsv", "triage/batch_002.tsv"],
    "5": ["triage.tsv", "triage_decision.md", "user_overrides.tsv", "move_plan.md", "delete_plan.md", "gitignore_plan.md"],
    "6": ["apply_log.tsv", "reference_rewrite_log.tsv"]
  },
  "interrupted_at": "2026-05-08T19:42:00Z",
  "interrupted_reason": "context-window limit",
  "mode_history": ["full"],
  "escalations": []
}
```

On re-entry, the main agent reads this file and confirms:
- "Last run was `<mode>` mode, completed Phase `<phase_completed>` at `<interrupted_at>`. Resume from Phase `<next_phase>`?"

---

## Per-phase re-entry behaviour

### Phase 0 (up-front confirmations)

If `run_state.json` exists:
- Skip the intake prompt; confirm: "Resuming previous run. Skip the up-front confirmations?"
- If user confirms: load values from `project_profile.json`; if user wants to change inputs, re-do Phase 0.

### Phase 1 (project profile)

```bash
if [[ -f .repo_janitor_workspace/project_profile.json ]]; then
    age_seconds=$(( $(date +%s) - $(stat -c %Y .repo_janitor_workspace/project_profile.json) ))
    if (( age_seconds < 604800 )); then  # 7 days
        echo "Profile fresh; reusing."
    else
        echo "Profile is $((age_seconds / 86400)) days old; re-running for safety."
        run_phase_1
    fi
else
    run_phase_1
fi
```

### Phase 2 (inventory)

Always re-run. Cheap. Produces fresh `candidates.tsv`. If candidate set has drifted (concurrent agents created/removed files), the new inventory reflects it.

### Phase 2.5 (secret scan)

Always re-run. Cheap. Catches new secret-leak introductions since the last run.

### Phase 3 (bundle)

```bash
if [[ -f .repo_janitor_workspace/bundle_path.txt ]]; then
    bundle=$(cat .repo_janitor_workspace/bundle_path.txt)
    if [[ -d "$bundle" ]] && [[ -f "$bundle/index.tsv" ]]; then
        # Re-verify byte-equality
        bash scripts/verify-bundle.sh "$project" "$bundle"
        if [[ $? -eq 0 ]]; then
            echo "Bundle valid; reusing."
        else
            echo "Bundle invalid; rebuilding into a fresh in-project bundle path."
            mv "$bundle" "$bundle.invalid.$(date -u +%Y%m%dT%H%M%SZ)"
            run_phase_3
        fi
    else
        run_phase_3
    fi
else
    run_phase_3
fi
```

### Phase 4 (triage)

For each batch range (e.g., 0-29, 30-59, 60-89):
- If `triage/batch_NNN.tsv` exists with a non-empty body, skip.
- Else, spawn the triage worker for that batch.

### Phase 5 (merge & confirm)

Always re-runs. Reads all `batch_*.tsv` files; emits fresh decision table. User re-confirms.

If `user_overrides.tsv` exists from a previous run, apply it on top of the freshly-merged `triage.tsv`.

### Phase 6 (apply moves)

For each move in the move plan:
- Check `apply_log.tsv` for a row with matching candidate id and `action=move`.
- If found and `gates_status=passed`, skip (already done).
- Else, apply.

If a move was started but the commit didn't land (process killed mid-Phase-6):
- The working tree may have the rename staged but not committed.
- The skill: detect this via `git diff --staged` showing a rename matching the move plan; commit the staged change with the prepared message; mark `apply_log.tsv`.

### Phase 7 (apply deletes)

Analogous to Phase 6. Per-glob batch. Check `apply_log.tsv` for already-committed batches.

### Phase 8 (gitignore)

Refuses to re-run if `.gitignore` already has all proposed additions:

```bash
all_added=true
for pat in $proposed_patterns; do
    grep -qF "$pat" .gitignore || all_added=false
done
if [[ "$all_added" == "true" ]]; then
    echo "All proposed gitignore patterns already present; skipping Phase 8."
fi
```

### Phase 9 (fresh-eyes)

Always re-runs from round 1 (regardless of previous round counts). The Phase 9 logic re-reads the apply state; if all moves/deletes/gitignore are already in place, the rounds run quickly (mostly verification, no edits).

### Phase 10 (handoff)

Re-emits `handoff_report.md` from the latest log files. The new report supersedes the old.

### Phase 11 (user-lens, optional)

Off by default. Re-runs if user explicitly asks.

---

## Authorization preservation

`cleanup_authorization.txt` is APPEND-ONLY across runs. Each authorization the user types is timestamped. On resume:

- The skill reads existing entries.
- For Phase 7/Phase 8 destructive ops that already have an entry covering THIS run's plan, the auth is reused.
- For new destructive ops (e.g., a Phase 7 batch that wasn't in the original plan), new auth is required.

The "covering THIS run's plan" check is by hash of the plan file:

```
# cleanup_authorization.txt
2026-05-08T17:30:00Z phase=7 plan_hash=abc123 auth="yes I understand and want to delete 13 files per the plan above"
2026-05-08T17:30:30Z phase=8 plan_hash=def456 auth="yes I understand and want to add 5 .gitignore rules per the plan above"
```

If the plan file's content hash matches an existing entry, auth is satisfied. If the plan changed (e.g., user added a row), new auth is required.

---

## Workspace state cleanup

If the user wants a fresh start instead of resume:

```bash
# Archive the old workspace
ts=$(date -u +%Y%m%dT%H%M%SZ)
mv .repo_janitor_workspace .repo_janitor_workspace_archive_$ts
# Now run the skill again — it'll see no workspace and start fresh
```

The skill never auto-deletes a previous workspace; it always offers (a) resume, (b) archive + start fresh, (c) abort.

---

## Cross-mode resumability

If the user switches modes mid-resume:

```
Phase 5 done in `triage-only` mode.
User now wants to continue with `full` mode.
```

The skill:
1. Verifies the previous mode's stop condition was met (Phase 5 plan exists, user reviewed).
2. Updates `run_state.json` with the new mode + `mode_history` append.
3. Resumes from Phase 6 (the next phase for `full` mode).

The escalator (OPERATING-MODES.md § Blast-radius escalator) is the formal mechanism for this.

---

## When resume is unsafe

The skill refuses to resume in these cases:

| Condition | Reason | What to do |
|-----------|--------|------------|
| `run_state.json` is corrupted or unparseable | Can't determine where to resume | Archive workspace; start fresh |
| The repo's HEAD has changed since the last run | The bundle's recovery is no longer aligned with the working tree | Archive; start fresh; the new run will create a fresh bundle |
| The user changed git config (e.g., `core.autocrlf`) since the last run | Bundle byte-equality may now fail | Re-verify bundle; if mismatches, archive and start fresh |
| The previous run halted in `harden-secret-leak` mid-filter-repo | Resume is risky; the filter-repo state may be corrupted | Restore from mirror backup; restart `harden-secret-leak` from Step 1 |
| The previous run is older than 30 days | Project state has likely drifted significantly | Archive; start fresh |

Each refusal is surfaced to the user with the reason; they decide.

---

## What survives a workspace deletion

If the user accidentally deletes `.repo_janitor_workspace/`:

- **Bundle survives only if `.repo_janitor_workspace/` survives** because the bundle is intentionally contained inside the project workspace.
- **Backup ref survives** (`refs/repo-janitor-backup/<DATE>-pre-cleanup`).
- **Recovery branch survives** (cleanup commits are in git history).
- **Workspace logs are gone** — `apply_log.tsv`, `triage.tsv`, `cleanup_authorization.txt`.

The skill can rebuild the workspace from git log + bundle (limited):

```bash
# Re-derive apply_log.tsv from git log
git log --oneline <recovery-branch> ^<base-branch> | awk '{...}' > apply_log.tsv

# Re-derive triage.tsv? Cannot — verdicts are in the deleted file.
# Resume is impossible in this state; user must start fresh from Phase 1.
```

The skill warns the user: "workspace gone; the in-project bundle and workspace logs are gone too. The recovery branch and backup ref may still exist, but cleanup decisions cannot be resumed. Recommended: start fresh; previous commits stay on the recovery branch."

---

## Idempotence vs. resumability

**Idempotence**: re-running on a clean repo produces no actions.
**Resumability**: re-running on a partial repo continues from where it stopped.

The two are related but distinct. Both are tested by SELF-TEST.md smoke tests:

- "Idempotence smoke test" — clean repo, expects 0 commits.
- "Resumption smoke test" — kill mid-Phase-6, re-run, expects continuation.

Both must pass before the skill is considered correct.
