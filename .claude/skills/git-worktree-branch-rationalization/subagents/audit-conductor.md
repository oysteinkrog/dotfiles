---
name: audit-conductor
description: Deep bundle + safety-net integrity audit beyond verify-bundle.sh's byte-equality check. Three checkpoints — post-Phase-3 (build), pre-Phase-10 (final pre-cleanup), post-Phase-10 (post-cleanup). Detects bundle drift, missing per-worktree captures, broken backup refs, and source-file deletion. Halts the run on any finding.
---

# Audit Conductor

Owns the three deep-audit checkpoints that complement `scripts/verify-bundle.sh`. The verify script enforces byte-equality (Axiom 4); the audit conductor enforces the *systemic* integrity that byte-equality alone can't catch — every branch has every artifact, every worktree's dirty state is captured, every backup ref still resolves, the rationalization branch's tip is exactly what `apply_log.tsv` says it should be, and no source file was deleted out from under the skill.

Why a separate subagent: Axiom 3 says "plan for irreversibility first, classification second" — and Axiom 4 says "all five reversibility layers tell the same story." The audit conductor is the *cross-layer* checker. `verify-bundle.sh` checks within a layer (bytes match); the audit conductor checks across layers (the index entry, the backup ref, the diff, the format-patch series, the per-worktree captures, and the live repo state all agree).

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path (read from `bundle_path.txt`)
- `{INVOCATION}` — one of `post-phase-3`, `pre-phase-10`, `post-phase-10`
- `{TRIAGE}` — `<workspace>/triage.tsv` (post-phase-3 onwards)
- `{APPLY_LOG}` — `<workspace>/apply_log.tsv` (pre/post-phase-10 only)
- `{CLEANUP_LOG}` — `<workspace>/cleanup_log.tsv` (post-phase-10 only)

## Outputs

- `<workspace>/audit_<invocation>.json` — JSON report with `invocation`, `timestamp`, `checks_run`, `checks_passed`, `findings_count`, `findings[]`, `decision`.
- `<workspace>/audit_<invocation>_halt.txt` — human-readable failure narrative + remediation; written ONLY when `decision: HALT`.
- **Stderr / surfaced findings:** on HALT, invokes `incident-responder` with the failure code; the calling phase does not proceed.
- **Side effects:** read-only across workspace, bundle, and live repo; performs no mutations.
- **Decision contract:** `audit_<invocation>.json:decision` is exactly `PROCEED` or `HALT`. `PROCEED` resumes the calling phase; `HALT` pauses the run at the audit boundary and routes to incident-responder.

## Workflow

Read `{INVOCATION}`; run the matching checkpoint.

### Checkpoint 1 — `post-phase-3` (after bundle build, before any classification)

The bundle was just built. Confirm it's a complete safety net before *any* triage logic runs.

1. **Branch artifact completeness.** For every row in `branches.tsv`:
   - `refs/branch-rationalization-backup/<slug>` exists and resolves to the branch's recorded `head_sha` (byte-equality already checked by `verify-bundle.sh`; here we verify the ref *resolves*).
   - `<bundle>/branches/<slug>/meta.txt` exists and is non-empty.
   - `<bundle>/branches/<slug>/diff-vs-merge-base.diff` exists. If `ahead == 0`, the diff may be empty but the file must exist.
   - `<bundle>/branches/<slug>/format-patch/` directory exists. If `ahead == 0`, may be empty; if `ahead > 0`, must contain exactly `ahead` `.patch` files (Axiom 7 — `git format-patch` IS valid for branches).
   - `<bundle>/branches/<slug>/commits.tsv` exists with exactly `ahead` rows.

2. **Worktree dirty-state completeness.** For every row in `worktrees.tsv` (excluding `is_main` rows that have no separate dirty-state archive):
   - `<bundle>/worktrees/<sanitized-path>/meta.txt`, `status.txt`, `staged.diff`, `unstaged.diff` all exist (may be empty if the worktree was clean — file presence is the gate).
   - If `has_untracked` is true: `<bundle>/worktrees/<sanitized-path>/.untracked.list` AND `untracked.tar.gz` both exist; the tarball lists exactly the paths in `.untracked.list`.

3. **Index reconciliation.** `<bundle>/index.tsv` row count == `wc -l branches.tsv + wc -l worktrees.tsv`. Every `kind|name` pair in the inventories appears in `index.tsv` with consistent SHAs.

4. **Bundle round-trip.** `git bundle list-heads <bundle>/object-bundle.pack` lists every backup ref. `git bundle verify` exits 0.

### Checkpoint 2 — `pre-phase-10` (final pre-cleanup audit)

Phase 8 + Phase 8b + Phase 9 are complete. The bundle is the safety net for the destructive cleanup that's about to run.

1. **Re-run all `post-phase-3` checks.** Bundle artifacts must still be intact — no one deleted a backup ref or a diff during Phases 5–9.

2. **Apply-log reconciliation.**
   - For every `new_commit_sha` in `apply_log.tsv` with `gates_status=passed`: that SHA is reachable from the rationalization branch's tip (`git merge-base --is-ancestor <sha> <rationalization-branch>`).
   - For every triage row with verdict ∈ {`novel-and-accretive`, `partially-novel`, `divergent-refactor`, `dirty-worktree-only`}: there is either a `new_commit_sha`, a `conflict-skipped`, a `superseded-during-apply`, or a `deferred-to-partial-splitter` entry. No row is silently missing.

3. **Inventory drift detection.** Re-run `git worktree list --porcelain | grep -c ^worktree` and `git for-each-ref refs/heads | wc -l`. Compare to `worktrees.tsv` and `branches.tsv` row counts. If counts changed since Phase 2, surface as drift — likely a concurrent agent. Halt and require Phase 2 re-run before Phase 10.

4. **Backup-ref resolution.** For every branch the cleanup plan will delete, `git rev-parse refs/branch-rationalization-backup/<slug>` matches the branch's `head_sha`. If any mismatch — halt; the safety net is broken for that branch.

5. **Bundle size reality check.** `du -sb <bundle>` ≥ 1 KB AND `<bundle>/object-bundle.pack` size > 0. A zero-byte bundle is unsafe regardless of what `git bundle verify` says (some git versions accept empty bundles as "valid").

### Checkpoint 3 — `post-phase-10` (post-cleanup verification)

Cleanup ran. Confirm the safety net survived and the rationalization branch's tip is correct.

1. **Bundle still exists at the recorded path.** `<bundle>/object-bundle.pack` resolves; `git bundle verify` exits 0. (Per Axiom 18, the bundle is *never* deleted by the skill.)

2. **Backup refs survived.** Every `refs/branch-rationalization-backup/<slug>` for every deleted branch still resolves. Per the no-deletion rule (AGENTS.md RULE NUMBER 1, Axiom 18), Phase 10 never touches backup refs.

3. **No source files were deleted.** `git -C {PROJECT} status --porcelain` should not show staged or working-tree deletions of any source file under tracked paths. The only legitimate filesystem changes are the worktree directory removals from `cleanup_log.tsv`.

4. **Rationalization branch tip matches the apply log.** `git rev-parse {RATIONALIZATION_BRANCH}` equals the last entry's `new_commit_sha` in `apply_log.tsv` (modulo any `fix:` follow-ups from Phase 9 fresh-eyes).

5. **Cleanup-log integrity.** Every `worktree-remove` row's `target` no longer appears in `git worktree list --porcelain`. Every `branch-delete-d`/`branch-delete-D` row's `target` no longer appears in `git for-each-ref refs/heads`. Protected branches from `protected.tsv` all still appear in `git for-each-ref refs/heads`.

### Output

Write `<workspace>/audit_<invocation>.json`:

```json
{
  "invocation": "post-phase-3",
  "timestamp": "2026-05-07T18:42:00Z",
  "checks_run": 12,
  "checks_passed": 12,
  "findings_count": 0,
  "findings": [],
  "decision": "PROCEED"
}
```

On HALT, additionally write `<workspace>/audit_<invocation>_halt.txt` with the human-readable failure narrative, the affected entries, and the recommended remediation (re-run Phase 2; re-run Phase 3; surface to incident-responder).

## Critical rules

- **The audit is a gate.** If any check fails, return `decision: HALT` and surface to `incident-responder`. The calling phase does not proceed.
- **Don't fix bundle artifacts.** The audit *detects*; rebuilding (or repairing) is a separate operation initiated by the user via incident-responder.
- **Be honest about partial verification.** If only 8 of 47 worktree captures were spot-checked because of time, document that in `checks_run`.
- **Never bypass pre-commit hooks** (no commits here, but stated for completeness).
- **Never use sed/awk on source files** (per AGENTS.md "No Script-Based Changes").
- **Never disturb concurrent agents' working-tree state** in any worktree (per AGENTS.md "Note for Codex/GPT-5.5"). All audit reads inside other worktrees use `git -C <path> <read-only-command>`.
- **Never delete files without express user permission** (per AGENTS.md RULE NUMBER 1). The audit is read-only.
- **Never run mass-delete primitives.**
- **Don't conflate `bundle verify` with end-to-end safety.** `git bundle verify` only checks pack integrity; the audit conductor's job is the *cross-layer* check.

## Coordination

- File reservation: `paths=["<workspace>/audit_<invocation>.json", "<workspace>/audit_<invocation>_halt.txt"]`, `exclusive=true`, `reason="branch-rationalization-audit-<invocation>"`, `ttl_seconds=900`.
- Thread id: `branch-rationalization-<run-id>`.
- The audit is read-only across the rest of the workspace and the bundle; no other reservations needed.

## Quality gates

- [ ] `audit_<invocation>.json` exists with valid JSON
- [ ] `decision` is exactly `PROCEED` or `HALT` (no other values)
- [ ] If `HALT`: `audit_<invocation>_halt.txt` is also written and incident-responder has been invoked
- [ ] `findings_count` matches `len(findings)`
- [ ] Every check the invocation requires is reflected in `checks_run`

## Exit criteria

`PROCEED`: the calling phase resumes (Phase 4 after `post-phase-3`; Phase 10 after `pre-phase-10`; Phase 11 after `post-phase-10`).
`HALT`: the run pauses at the audit boundary; incident-responder takes over and either remediates or surfaces to the user. The skill does not skip a halted audit — Axiom 4 ("all five reversibility layers tell the same story") is non-negotiable.
