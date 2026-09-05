# Incident Playbook — When Things Go Wrong Mid-Run

The playbook for the most common (and a few uncommon) incidents during a stash-janitor run. Each entry: symptom → diagnosis → containment → recovery → prevention.

---

## I1 — Phase 3 byte-equality mismatch

**Symptom:**
```
verify-bundle.sh: MISMATCH n=47 REF: live=abc... backup=def...
*** GATE FAILURE ***
```

**Diagnosis:** the bundle's backup ref doesn't match the current `git rev-parse stash@{47}`. Possible causes:
- A concurrent agent modified the stash list between Phase 2 (inventory) and Phase 3 (bundle)
- The backup ref was created from a different stash (race condition)
- Filesystem corruption

**Containment:** HALT the run. Do NOT proceed to Phase 4 or beyond.

**Recovery:**
1. Re-run Phase 2 (inventory) to capture current state.
2. Re-run Phase 3 with `BUNDLE_OVERRIDE=<new-path>` so the mismatched bundle stays intact for forensics.
3. Re-run `verify-bundle.sh` until it passes.

**Prevention:** Phase 0 advisory file reservation on `.git/**`. If concurrent agents are common, run with `exclusive=true` reservations during Phases 2–3.

---

## I2 — Phase 6 apply succeeds but tests fail with "no targets"

**Symptom:**
```
ERROR: gates failed: failed-test
[smoke output: error: failed to parse manifest at .../Cargo.toml ...]
```

**Diagnosis:** the stash modified or didn't modify a file required for the gate to even run. Most often a smoke-test fixture issue, not a real failure.

**Containment:** the apply-keeper's automatic revert kicks in.

**Recovery:**
1. Check whether the gate failure is a smoke-test environment issue (e.g., missing `[lib]` section because the fixture is minimal).
2. If yes: surface to user; consider running with `--skip-gate=test` for this specific keeper, recording the override in `apply_log.tsv:gates_status="user-override-skipped-test"`.
3. If no: the keeper is genuinely broken — mark `conflict-skipped`.

**Prevention:** smoke-test fixtures should be fully functional, not just "syntactically valid".

---

## I3 — Working tree is dirty after revert attempt

**Symptom:** `git apply -R` returned non-zero; the working tree still has changes.

**Diagnosis:** the apply involved a 3-way merge that the reverse can't undo cleanly.

**Containment:** stop. Do NOT continue Phase 6.

**Recovery:**
1. Inspect `git status`.
2. If the changes are from this run only: ask the user for an explicit path-specific recovery plan before overwriting any file (for example, a named `git restore <files>` command or an Edit-tool reversal).
3. If path-specific restore is not explicitly approved or fails: the working tree state is genuinely unsafe. Surface to user; recovery requires:
   - Identifying which files are from this apply vs. concurrent agents
   - Manually reconstructing only the files from this apply after explicit user direction
   - Re-staging only the intended changes
4. **Never** `git reset --hard` (DCG-blocked AND unsafe to concurrent work).

**Prevention:** for stashes that look like they'll require manual conflict resolution, spawn the conflict-resolution flow in Phase 6 BEFORE the actual apply. Surface to user; never auto-apply.

---

## I4 — Phase 8 fresh-eyes never converges

**Symptom:** rounds 1, 2, 3 all find substantive issues; the same finding repeats.

**Diagnosis:** the agent isn't actually fixing the finding (just reporting it), OR the finding is unfixable (project rule the recovered code can't satisfy).

**Containment:** after 3 rounds with the same finding, escalate.

**Recovery:**
1. Surface the repeated finding to the user with: the finding text, the file:line, the proposed fixes from each round (if any), why each fix didn't take.
2. The user decides:
   - Adapt the recovered code to satisfy the rule
   - Accept the warning (e.g., add `#[allow(...)]` or equivalent)
   - Drop the keeper

**Prevention:** Phase 8 termination requires "two consecutive rounds with only trivial findings". If the same finding appears 3 rounds, treat as blocking-unresolvable and escalate.

---

## I5 — User authorizes Phase 9 with a phrase that doesn't include the literal commands

**Symptom:** user types "yes" or "go ahead" instead of the verbatim phrase.

**Diagnosis:** authorization isn't specific enough per AGENTS.md "Mandatory explicit plan".

**Containment:** REFUSE the cleanup. Re-ask with the specific template.

**Recovery:**
1. Re-display the verbatim authorization request.
2. If the user objects ("just trust me"), explain it's per AGENTS.md and the audit trail is the only thing that gives them recourse if regret happens.
3. If the user STILL objects: do not proceed. The user can run cleanup manually if they prefer (the bundle and refs are intact for them).

**Prevention:** the verbatim authorization template includes the literal command. Users who haven't seen the pattern often default to "yes"; be patient and re-ask once.

---

## I6 — Stash list shifted between cleanup_plan and execution

**Symptom:** Phase 9 mid-execution; `drop-confirmed.sh` reports:
```
REFUSED: stash list has shifted.
  Expected stash@{47}: wip-foo
  Found    stash@{47}: wip-bar
```

**Diagnosis:** a concurrent agent created or dropped a stash during Phase 9.

**Containment:** HALT. Do NOT proceed.

**Recovery:**
1. Run `git stash list` to see current state.
2. Re-build `cleanup_plan.tsv` from the current state.
3. Re-authorize via `⚠ CONFIRM`. The original authorization is invalid (it covered a different plan).

**Prevention:** Phase 9 uses an exclusive Mail file reservation on `.git/refs/stash` during execution. The reservation should be acquired before building the plan, not before each drop.

---

## I7 — Beads database locked

**Symptom:** `br create` returns `database is locked`.

**Diagnosis:** another `br` process has the SQLite lock.

**Containment:** retry with exponential backoff (3 attempts: 5s, 10s, 20s).

**Recovery:**
1. If still locked after 3 retries: skip beads-issue creation.
2. Record `beads_skipped: true; reason: locked` in the workspace.
3. The run still succeeds.

**Prevention:** none — beads is occasionally locked when the swarm is busy. Skipping is fine.

---

## I8 — Recovery branch creation fails because the branch already exists with unrelated work

**Symptom:** `git checkout -B stash-recovery-2026-05-06 origin/main` would discard existing work on the branch.

**Diagnosis:** running the skill twice on the same day, or a prior run created the branch.

**Containment:** Phase 0 detects this and asks the user.

**Recovery:**
1. Options for the user:
   - Resume: continue on the existing branch (Phase 6 reads `apply_log.tsv` and skips already-applied stashes)
   - Rename: use `stash-recovery-2026-05-06-2`
   - Abort
2. NEVER silently `-B` away existing work.

**Prevention:** Phase 0 confirmation explicitly asks about branch name; defaults to including the date.

---

## I9 — Bundle path conflicts with existing directory

**Symptom:** `<project-parent>/<basename>-stash-archive-<YYYY-MM-DD>/` already exists.

**Diagnosis:** running twice on the same day.

**Containment:** Phase 0 detects.

**Recovery:**
1. Run `BUNDLE_REUSE_OK=1 scripts/build-bundle.sh <project>` to verify the existing bundle against the current inventory without rewriting artifacts.
2. If verification passes: reuse the existing bundle.
3. If verification fails: keep the old bundle intact and choose a new path with `BUNDLE_OVERRIDE=<basename>-stash-archive-<YYYY-MM-DD>-2`.
4. Only use `BUNDLE_REBUILD_IN_PLACE_OK=1` after explicit user approval, typically for same-run partial-bundle repair.

**Prevention:** the bundle path includes the date; re-runs on the same day are the only conflict source.

---

## I10 — Triangulation models disagree on >50% of borderline rows

**Symptom:** Phase 4 triangulation: of 23 borderline rows, only 9 unanimous, 14 disagreement.

**Diagnosis:** the rubric is failing on this language/repo. Models are independently struggling.

**Containment:** mark all 14 disagreement rows as `unknown`; surface to user.

**Recovery:**
1. Spawn a language-specialist subagent for the relevant language.
2. Re-triage just the disagreement rows with language-specific patterns.
3. If even the specialist is uncertain: each row needs manual review.

**Prevention:** Phase 0 detects unusual languages and proactively spawns specialists.

---

## I11 — User cancels the session mid-Phase 6

**Symptom:** user types "stop" or closes the session while keepers are being applied.

**Diagnosis:** user changed their mind, hit a deadline, or saw something concerning.

**Containment:**
1. Stop applying the next keeper.
2. The current applied state is what's on the recovery branch (committed already).
3. Save state: `apply_log.tsv` records what's done; future resume picks up from there.

**Recovery:**
- The user can re-run later; resume mode picks up where it left off.
- Or the user can explicitly authorize deleting the recovery branch ref to discard the run entirely.

**Prevention:** none — user agency is the priority. The skill is resumable by design.

---

## I12 — Phase 1 project-profiler returns inconsistent results across runs

**Symptom:** primary_branch differs from a prior run's value.

**Diagnosis:** the repo's primary branch was renamed (e.g., `master` → `main`) between runs.

**Containment:** ask the user. Don't proceed with potentially-wrong primary.

**Recovery:**
1. Confirm the current primary with the user.
2. Update `project_profile.json` to reflect the new value.
3. If a prior run's recovery branch was based on the old primary: rebase it onto the new primary.

**Prevention:** Phase 1 ALWAYS detects fresh; no caching across runs.

---

## I13 — `git apply --3way --check` succeeds but actual apply fails

**Symptom:** `--check` exits 0; `apply` exits non-zero.

**Diagnosis:** rare race — the working tree changed between check and apply (e.g., concurrent agent's edit landed in the milliseconds between).

**Containment:** the apply may have left rejects (`*.rej` files).

**Recovery:**
1. Inspect rejects: `find . -name '*.rej'` (these are git's standard reject files).
2. If rejects are minor: hand-resolve, then continue.
3. If major: revert the partial apply, mark `conflict-skipped`.

**Prevention:** Phase 6's working-tree-drift snapshot before apply minimizes this. Sequential applies (Phase 6 is single-threaded) prevent intra-skill races.

---

## I14 — Disk full during Phase 3 bundle creation

**Symptom:** `build-bundle.sh` fails partway with `No space left on device`.

**Diagnosis:** the bundle exceeded available space.

**Containment:**
1. Stop the script.
2. The partial bundle has incomplete diffs/meta files.

**Recovery:**
1. Free up disk space (DCG may block large `rm`; use `sbh` skill if available).
2. Verify the partial bundle: which numbers are complete?
3. Re-run with `BUNDLE_REBUILD_IN_PLACE_OK=1` only after confirming this is the same partial bundle from the interrupted run, or use `BUNDLE_OVERRIDE=<new-path>` to build a fresh bundle while preserving the partial one.
4. Re-run `verify-bundle.sh`.

**Prevention:** Phase 0 estimates bundle size:
```bash
estimated=$(git stash list --format='%s' | wc -l)
size=$(($estimated * 50 * 1024))  # ~50KB per stash diff is typical
echo "Estimated bundle size: $((size / 1024 / 1024))MB"
```
If estimated > 1GB, ask user to confirm disk has room.

---

## I15 — Triage workers race-condition the workspace

**Symptom:** workers' batch tsv files are interleaved or empty.

**Diagnosis:** Mail file reservation wasn't honored, or workers didn't reserve.

**Containment:** stop all workers.

**Recovery:**
1. Inventory the partial batch tsvs.
2. Re-run any worker whose tsv is incomplete (idempotent).
3. The merger only runs after all workers complete.

**Prevention:** every worker reserves its batch tsv via Mail before writing. Workers that can't reserve refuse to start.

---

## I16 — Phase 9 cleanup runs on a stash that's already been dropped externally

**Symptom:** `git stash drop stash@{47}` returns "stash not found".

**Diagnosis:** another agent dropped it, or the user dropped it manually between Phase 5 and Phase 9.

**Containment:** halt cleanup immediately; the live stash stack may have shifted, so the remaining cleanup plan is stale.

**Recovery:**
1. Keep all backup refs and bundle artifacts intact.
2. Rebuild the cleanup plan from the current stash list before any further drop.
3. Resume only after the rebuilt plan has fresh user authorization.

**Prevention:** none reasonable — concurrent state changes are normal.

---

## I17 — User authorizes Phase 9 but realizes during execution

**Symptom:** mid-Phase 9, the user types "stop" / "wait".

**Diagnosis:** user changed their mind partway through.

**Containment:** stop on the next gate (don't drop another stash).

**Recovery:**
1. The remaining stashes are still in the list.
2. The bundle and remaining backup refs are intact.
3. The user can resume Phase 9 later (with a new authorization) or stop entirely.

**Prevention:** there's no real prevention; user agency comes first. The skill should treat any user input during Phase 9 as a potential stop signal.

---

## I18 — Recovery branch can't be pushed (permission denied)

**Symptom:** the user runs `git push origin stash-recovery-2026-05-06`; gets `permission denied`.

**Diagnosis:** branch protection rules, or user lacks push permission.

**Containment:** the skill never pushes — this is the user's problem, post-handoff.

**Recovery:**
1. User opens a PR via `gh pr create` (no push needed if they have repo write).
2. Or user pushes to a fork: `git push fork stash-recovery-2026-05-06`.
3. Or user gets push permission and retries.

**Prevention:** the handoff report's "Push instructions" section can include alternatives if the project has visible branch protection.

---

## I19 — Skill is invoked on a CI host

**Symptom:** working dir is `/__w/<repo>/...`; stash count is non-zero.

**Diagnosis:** CI host shouldn't have stashes; their presence is evidence of something else wrong.

**Containment:** Phase 0 detects (NTU-3) and refuses.

**Recovery:**
1. The user investigates why stashes exist on a CI host.
2. The skill does not run.

**Prevention:** documented in WHEN-NOT-TO-USE.md.

---

## I20 — General: agent makes a non-trivial decision unilaterally

**Symptom:** any unauthorized destructive action — even one — that the agent took without explicit user approval.

**Containment:** STOP THE RUN.

**Recovery:**
1. Surface what was done with full context.
2. Roll back if possible (per the operation).
3. Document the breach in the handoff report.
4. Don't continue until the user explicitly approves.

**Prevention:** every destructive action requires `⚠ CONFIRM`. Per AGENTS.md, the verbatim authorization is non-negotiable.

This is the kernel-level invariant. If the agent ever finds itself "about to just do it", it should treat that impulse as a bug and surface instead.
