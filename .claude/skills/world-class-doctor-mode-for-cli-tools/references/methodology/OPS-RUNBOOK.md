# Ops Runbook — Operating the Doctor Day-to-Day

After Phase 8 wires the doctor into pre-commit and CI, the doctor is in production. This runbook is for the team operating it: daily/weekly/monthly tasks, alert response, and pass-N → pass-N+1 cadence.

For the **agent's** view (per-invocation usage), see `<tool> doctor robot-docs`. This file is for **human operators** (the developer team).

---

## Daily

**5-minute morning check** (or at every CI run, automatically):

```bash
<tool> doctor health   # cheap; should be < 200ms
```

If `health` reports `findings`, run `<tool> doctor --json | jq '.findings[].id'` to see which FMs surfaced.

**Read CI's doctor step output** before merging anyone's PR. The doctor's CI gate is in `.github/workflows/doctor.yml` (per Phase 8).

---

## Weekly

**Tuesday morning:** review the past week's `scorecard_history.jsonl` trend.

```bash
tail -100 .doctor/scorecard_history.jsonl \
  | jq -s 'group_by(.tool_version) | map({version: .[0].tool_version, runs: length, avg_score: ([.[].aggregate_score] | add / length)})'
```

Flag if:
- Aggregate score drifted down by > 30 pts.
- A specific FM started showing up that didn't last week.
- `health_p95_ms` increased by > 50% from baseline.

**Friday afternoon:** review `regression_alerts.md` if non-empty. Each unacked regression is a hard-stop on the next pass — either ack with a written reason, or revert the change that caused it.

---

## Monthly

**First Monday:** run cass mining for new failure modes.

```bash
cd <workspace>
# Mine the past month for tool-specific issues.
cass search "<tool> broken" --days 30 --robot --limit 30 \
  | jq -r '.hits[] | select(.kind=="MANUAL_FIX") | .source_path'
```

If a recurring "I had to manually fix X" appears that the doctor didn't catch, file a P1 bead for the next pass.

**Schedule a doctor pass-N+1** via the skill if:
- Aggregate score fell below 700 (Polish Bar floor).
- ≥ 5 new P0/P1 FMs accumulated in beads.
- New cookbook pattern applies (e.g., the project added a daemon component → Pattern 4 retrofit).
- A version bump changed `doctor_contract_version` and you need a migration pass.

---

## Quarterly

**Pass-N+1 doctor build.** Apply the skill in `re-score-only` mode first to confirm the current baseline. Then `upgrade` mode to add new fixers.

Estimated effort: 4–8 hours wall time at Squad tier with multi-model triangulation. The skill's WORKED-EXAMPLE.md is the reference timeline.

**Adversarial review.** Run [ADVERSARIAL-REVIEW.md](ADVERSARIAL-REVIEW.md) scenarios A-F against the current doctor. File P0 beads for any failures.

---

## Annual

**Re-mine extended cass evidence.** Update [CASS-EVIDENCE-INDEX.md](../exemplars/CASS-EVIDENCE-INDEX.md) with new themes. Update [QUOTE-BANK.md](QUOTE-BANK.md) with new strong quotes (allocate next Q-NNN ID).

**Doctor contract version review.** If the contract has been minor-bumped 5+ times since the last major bump, consider whether the accumulated changes warrant a major bump (per [VERSIONING.md](VERSIONING.md)).

**Skill self-review.** Run a meta-doctor pass (Pattern 12) over THIS skill if the user maintains it. Verify cross-refs, Q-IDs, fixture coverage.

---

## Alert response

### "Doctor regression" (aggregate score dropped > 50 pts)

1. Identify which FM regressed: `scripts/diff-scorecards.py <workspace> <prior-pass> <current-pass>`.
2. `git log --since=<prior-pass-date> -- src/<doctor-module>` — what changed in the doctor module?
3. If the regression is a deliberate trade-off (e.g., a new precondition that's stricter), add an ACK to `regression_alerts.md`.
4. Otherwise, revert the change, file a P1 bead, address in the next pass.

### "Health latency budget exceeded"

1. Identify the slow detector from recent run artifacts:
   ```bash
   python3 -c 'import glob,json; s={}; [s.setdefault(k,[]).append(v) for p in glob.glob(".doctor/runs/*/report.json") for k,v in (json.load(open(p)).get("per_detector_ms") or {}).items()]; [print(f"{sorted(v)[int((len(v)-1)*0.95)]}ms\t{len(v)} samples\t{k}") for k,v in sorted(s.items(), key=lambda kv: sorted(kv[1])[int((len(kv[1])-1)*0.95)] if kv[1] else 0, reverse=True)[:10]]'
   ```
2. Profile that detector specifically.
3. Either optimize OR move to a slower tier (`tier: "default"` or `tier: "deep"`).
4. Update `<tool> doctor capabilities --json::detectors[].tier`.

### "Findings spike"

1. Read the latest `report.json` for the spike's contents.
2. Cross-reference with the project's recent commits — did something break the project's state semantics?
3. If the project introduced a new failure mode the doctor catches, confirm the finding is expected, add/refresh the fixture, and scope an auto-fix if it is safe.
4. If the project introduced a new failure mode the doctor doesn't catch — that's a Phase 1 archaeology gap; file a P1 bead.

### "Panic detected"

1. The doctor's runtime caught a panic (good — Axiom 5 holds). The catch is for safety, but the underlying bug is a P0.
2. Read the captured stderr in the run-artifact's `stderr.log`.
3. Find the file:line that panicked. Convert to a `safety_block` finding instead.
4. File P0; address before next release.

### "Lock contention > 5%"

1. Are agents running multiple doctor invocations concurrently? Maybe the project's CI is parallelizing tests that each invoke doctor.
2. If yes: serialize them (or accept the contention if it's fast).
3. If no: the lock TTL might be too short; review `lock_timeout_seconds` in capabilities.

### "Backup failure"

This is **never** acceptable. Investigate immediately:
1. Pull the run-artifact for the failing run.
2. Check `actions.jsonl` — was a line written without a corresponding backup?
3. If yes: `mutate()` chokepoint is broken; this is a Phase 4 implementation bug. P0.
4. If no: external interference (someone deleted `.doctor/runs/<id>/backups/` between mutate() and read). Investigate the broader environment.

---

## On-call protocol

For projects that have on-call rotations:

| Severity | Response |
|----------|----------|
| P0 (data corrupted; doctor caught it but the fixer panicked) | Page; revert recent changes; restore from `.doctor/runs/<latest>/backups/` if needed |
| P0 (doctor refuses with exit 4 in a context where it shouldn't) | Page; the refusal IS the safe behavior; investigate why the precondition fired |
| P1 (CI doctor step failing for > 30 min) | Slack the doctor team; investigate the latest commit |
| P2 (scorecard regression notification) | Address in next sprint; add ACK if intentional |
| P3 (doctor cosmetic fix needed) | File bead; address in next quarterly pass |

---

## Doctor team responsibilities

A small project can have one person owning the doctor. Larger projects split:

| Role | Responsibilities |
|------|------------------|
| **Doctor lead** | Quarterly pass; alert response; cookbook pattern selection |
| **Doctor implementer** | Phase 4 of each pass; per-FM detector + fixer + fixture |
| **Adversarial reviewer** | Quarterly run of [ADVERSARIAL-REVIEW.md](ADVERSARIAL-REVIEW.md); annual extended cass mining |
| **Operator** | Daily `<tool> doctor health` checks; weekly trend review; monthly bead grooming |

---

## When to retire a fixer

Sometimes a fixer outlives its usefulness:
- The FM's root cause was eliminated upstream (e.g., the project rewrote the offending subsystem).
- The fixer is now dead code (no fixture corruption produces this state anymore).

**Per AGENTS.md no-delete, never literally delete the fixer code.** Instead:
1. Mark it `deprecated: true` in `capabilities --json::fixers[]`.
2. Skip it in the runtime registry (so it's not invoked).
3. Keep its fixture in `tests/doctor_fixtures/` — it documents the historical FM.
4. After 1 year of zero invocations, the project lead can move the file to a `deprecated/` subdirectory of the doctor module (still NOT deleting).

---

## Recovery from a botched doctor pass

If pass-N+1 introduced a regression that wasn't caught and now production is on a buggy doctor:

1. **`git revert` the doctor pass commits.** They're isolated on the `doctor-mode-pass-N+1` branch and merged via PR; the merge commit is reversible.
2. Run pass-N's binary to verify health restored.
3. File a P0 bead with the failed pass details.
4. Re-enter the methodology with the failure as a known-bad input to fixture suite for pass-N+2.

The doctor's own version control discipline (feature branch, per-spec commits) is precisely so this is recoverable.
