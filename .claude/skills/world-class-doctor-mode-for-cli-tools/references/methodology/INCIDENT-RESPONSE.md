# Incident Response — Active-Incident Playbook

[CASE-STUDIES.md](CASE-STUDIES.md) is postmortem narrative. This file is the **active-incident** playbook: what to do RIGHT NOW when production is on fire and the doctor is the tool reaching for the brake.

The "I'm operating an agent or a team and there's an active incident" runbook. Time-pressured. Step-by-step.

---

## Triage in 60 seconds

```
1. <tool> doctor health
2. case the result:
   - "ok ..."           → not the doctor's problem; check upstream
   - "findings ..."     → doctor sees state issues; deeper investigation
   - "unsafe ..."       → doctor refused; structured response below
   - "concurrency ..."  → another doctor running; wait or investigate
3. If health > 5 seconds → already a doctor performance issue (its own bug).
```

This 60s triage answers: is the doctor relevant to this incident at all?

---

## Tier 1 — User-visible incident, doctor is silent

The user reports `<tool> X is broken`. `<tool> doctor` says healthy.

**This is the hardest case.** The doctor doesn't see the problem. Either:

(a) **The FM isn't in the doctor's coverage.** Mine cass for the symptom; if it's a new pattern, add a P1 bead for next pass.

(b) **The detector is wrong.** Read the relevant detector source. Compare against the actual broken state (if reproducible). Often the detector reads a stale cache OR uses a heuristic that misses this specific case.

(c) **The user's reproduction is in a different workspace than the doctor's target.** Verify cwd. The doctor targets cwd by default; if the user's broken state is elsewhere, that's why.

**Do not auto-fix anything in this tier.** Establish coverage first; fix in the next pass.

---

## Tier 2 — Doctor reports findings; user wants them gone

The user runs `<tool> doctor` and sees findings. They want to clear them.

**Procedure:**

1. **Read the JSON.** Don't trust the human-readable summary; the JSON is the contract.
   ```
   <tool> doctor --json | jq .
   ```

2. **Classify the findings.** For each: P0/P1/P2/P3, auto_fixable Y/N.

3. **Decide order.** Per dependency_graph.json: schemas before state_files; locks before everything.

4. **Plan via dry-run.**
   ```
   <tool> doctor --dry-run --fix --only fm-XXX
   ```
   Verify the bytes-affected estimate matches expectation.

5. **Execute one FM at a time** if possible. If the dependency_graph allows scoped fixes:
   ```
   <tool> doctor --fix --only fm-XXX
   ```
   Then re-diagnose:
   ```
   <tool> doctor --json | jq .summary
   ```

6. **If anything goes sideways**, undo immediately:
   ```
   <tool> doctor undo latest
   ```

7. **Iterate per FM until ok.**

---

## Tier 3 — Doctor reports exit 4 (refused unsafe)

```
{
  "exit_code": 4,
  "state": "REFUSING",
  "reason": "<reason-name>",
  "evidence": {...},
  "remediation": {...}
}
```

The doctor **refused on purpose**. This is correct behavior (Axiom 22).

**Procedure:**

1. **Read the reason.** Match against the cookbook:
   - `schema_version_unknown` → tool version mismatch; align tools.
   - `precondition_failed_<X>` → fix the underlying condition; do NOT --force.
   - `out_of_scope_write_attempted` → indicates either a malicious input or a bug in capabilities; investigate before any fix.
   - Lock contention is exit 5 (`concurrency_lost`); wait or investigate the holder PID. Online-required work is exit 6; re-run with `--online` only when the user/planner approves network access.

2. **Read the remediation field.** Most exit-4 reasons include a paste-ready remediation OR a "set up X then re-run" instruction.

3. **Do NOT --force without thorough understanding.** Per [DECISION-LOG.md D-010](DECISION-LOG.md), refuse-with-redirect is the correct behavior; --force is for documented exceptions only.

4. **If --force is genuinely needed:**
   ```
   <tool> doctor --fix --only fm-XXX --force --yes
   ```
   Both flags required. After running, file a bead documenting the --force use case so the next pass can encode it as a less-invasive remediation.

---

## Tier 4 — Doctor returned exit 3 (fix failed, rolled back)

```
{
  "exit_code": 3,
  "state": "DONE_FAILED",
  "actions_failed": N,
  "backups_restored": N
}
```

The fixer's mutate() call returned an error; the runtime rolled back per the chokepoint contract.

**Procedure:**

1. **Verify rollback completed.** Compare hashes:
   ```
   <tool> doctor ls --json | jq '.runs[0].state'
   # Expect: DONE_FAILED with backups_restored == actions_attempted
   ```

2. **Read the run-dir's stderr.log.** The actual error (network, disk, permission, etc.) is captured there.

3. **Verify the live workspace is in pre-fix state.** Compare every path in actions.jsonl against the corresponding backup; SHA-256 should match.

4. **DO NOT re-run --fix immediately.** The same fixer will fail the same way. File a bead; investigate; fix the fixer; ship in the next pass.

5. **Workspace is safe to use** — rollback is the safety machinery working as designed.

---

## Tier 5 — Doctor itself crashed (panic / SIGKILL)

The doctor process died abnormally. The next `<tool> doctor` invocation should detect the partial run and either complete or refuse.

**Procedure:**

1. **Check for orphan tempfiles:**
   ```
   find <write-scopes> -name '.doctor.tmp.*' -type f
   ```
   If any: the next run's recovery detector (per [STATE-MACHINE.md ABORTED](STATE-MACHINE.md)) should quarantine.

2. **Run `<tool> doctor` (no flags).** Recovery happens here. Expected outcomes:
   - `state: ABORTED → cleaned up; no findings` → recovery worked.
   - `state: DONE_FINDINGS` with a `partial_run_<id>` finding → manual investigation needed; doctor refused to proceed.

3. **If neither outcome:** the recovery detector is broken. File a P0 bead; the next pass MUST add the recovery detector for whatever subsystem missed it.

4. **Worst case:** manually quarantine orphan tempfiles via `mv .doctor.tmp.NNN ~/quarantine/` (operator typing this; doctor never does), then re-run.

---

## Tier 6 — Doctor's `--fix` ran but state is still wrong

The doctor reported `DONE_OK` (exit 0) but the user observes the original broken state.

**This is a P0 doctor bug.** The detector returned None (after fix) but the actual state isn't fixed. Either:

(a) **The detector is wrong.** It says "fixed" but the predicate is too lax.

(b) **The fixer mutated the wrong thing.** The `actions.jsonl` shows writes that didn't address the user's symptom.

(c) **A race.** Another agent re-broke the state in the time between doctor's verify-step and the user's check.

**Procedure:**

1. Inspect `<run-dir>/actions.jsonl`. Confirm the writes happened.
2. Inspect the detector source. Check if its predicate matches the user's symptom.
3. If mismatch (case a): file P0 bead to refine the detector.
4. If correct mutation but symptom persists (case b): file P0 bead to fix the fixer.
5. If multi-agent activity nearby (case c): coordinate; re-run after others finish.

---

## Common pitfalls during incident response

1. **Running --fix without dry-run first.** Always dry-run; a 30-second sanity check prevents 30 minutes of recovery.

2. **Skipping `<tool> doctor undo latest` when uncertain.** Undo is byte-for-byte safe; you can always undo and try again. Don't accumulate uncertain changes.

3. **Using --force to "make the doctor be quiet".** Refusals are findings; respect them. --force is for documented exceptions only, not for bypassing the doctor.

4. **Re-running a known-failing fixer.** Each retry is wasted effort + accumulating run artifacts. Investigate first.

5. **Ignoring exit 5 (concurrency lost).** It means another doctor IS running; that one will finish and clear the lock. Wait, then check if your fix is still needed.

6. **Forgetting to file a bead for what you found.** The incident's value is the lesson; the bead is how the lesson persists.

---

## During-incident invocations cheat-sheet

```
# Quick triage
<tool> doctor health
<tool> doctor --quick --json    # < 1s; fast-path detectors only

# Full read-only diagnose
<tool> doctor --json | jq .

# Find a specific finding's evidence
<tool> doctor explain fm-XXX

# Mega-command (one round-trip for everything)
<tool> doctor --robot-triage --json | jq .

# Plan a fix without executing
<tool> doctor --dry-run --fix --only fm-XXX

# Execute a scoped fix
<tool> doctor --fix --only fm-XXX

# Roll back the most recent fix
<tool> doctor undo latest

# List all runs (for forensic context)
<tool> doctor ls --json | jq '.runs[] | {run_id, state, exit_code, started_at}'
```

---

## After the incident — within 24 hours

1. Append a Case Study to [CASE-STUDIES.md](CASE-STUDIES.md) with:
   - The incident (what the user saw)
   - The doctor's role (caught / didn't catch / refused / fixed)
   - Mapping to FM IDs
   - Lift to add (new FM, refined detector, etc.)
2. File beads for any P0/P1 findings.
3. Run `python3 scripts/scorecard.py append-history` to record the incident's run-id in the trend.

The methodology is the persistence (Axiom 16). Every incident leaves a trace.

---

## When the doctor itself is the incident

If the doctor IS what's broken (e.g., its --fix corrupted user data despite the safety machinery):

1. **Stop using the doctor.** Pin to the previous version.
2. **Restore from external backup** (the user's git stash, separate snapshot, or last known-good state).
3. File a P0 bead targeting the exact safety axiom that failed.
4. Pass-N+1 MUST add a fixture reproducing the failure AND a passing test demonstrating the fix.
5. Until that pass, the doctor is "down for maintenance."

This is rare — the methodology is designed against this case — but when it happens, it's the highest-priority work.
