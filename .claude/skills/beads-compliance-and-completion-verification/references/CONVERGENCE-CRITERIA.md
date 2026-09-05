# CONVERGENCE-CRITERIA.md — When The Audit Is "Done"

The audit isn't a one-shot. It's an iterative loop that converges over multiple passes as remediation work lands. This file specifies the formal convergence semantics that `scripts/convergence-check.py` implements.

---

## The five criteria (all must be true)

A pass is **converged** when ALL of the following hold:

1. **Score-delta within tolerance.** For every bead present in both this pass and the prior pass, `|score_now - score_prior| ≤ <delta_threshold>` (default ±10). Beads only present in this pass (newly-created completion-debt beads) are excluded from this check.

2. **Zero new false-closed findings.** No bead that was *not* on the prior pass's false-closed list appears on this pass's false-closed list. (Beads that were on the prior list and remain on this list are OK — they're tracked.)

3. **Zero new synthesis findings.** Phase 7 must produce no new integration gaps, contract drifts, orphaned ACs, or dependency anomalies that weren't on the prior pass. (Resolved findings disappearing is fine and expected.)

4. **Rubric-consistency pass.** Phase 10's spot-check (5 random scorecards re-derived from evidence) must show every spot-check within ±50 points of the scorer's value. The fresh reviewer records this in `passes/<PASS>/fresh_eyes_review.json`; `convergence-check.py` fails closed if that artifact is missing or says the spot-check failed.

5. **All remediation beads exist.** Every completion-debt bead created in the prior pass's `remediation.md` is present in `inventory.jsonl` (i.e., the bead-graph state after Phase 9 actually persists across passes).

---

## Tunable knobs (per project, in `rubric.md`)

| Knob | Default | What it controls |
|------|--------:|------------------|
| `convergence.delta_threshold` | 10 | Per-bead max score change between passes |
| `convergence.allow_new_false_closed` | 0 | Number of new false-closed beads tolerated (rare; only relax if you're discovering new bead types) |
| `convergence.spot_check_count` | 5 | How many scorecards Phase 10 re-derives independently |
| `convergence.spot_check_max_deviation` | 50 | Max allowed deviation between scorer and Phase-10 fresh-eyes |
| `convergence.priority_sensitivity` | true | If true, P0/P1 deltas use a tighter threshold (5) than P2–P4 (10) |

---

## Edge cases

### Rubric changed between passes

If `manifest.json#rubric_sha256` differs from the prior pass, score deltas are not directly comparable. `convergence-check.py` records:

```json
{
  "rubric_changed_since_prior_pass": true,
  "is_converged": false,
  "reason": "Rubric was updated; cannot verify convergence until two passes use the same rubric."
}
```

The next pass starts fresh: it can converge with the pass *after* it. The user is told why.

### Project repo had unrelated commits between passes

The audit doesn't track project-repo commits per pass; it records `project_git_sha_at_pass_start` in `manifest.json`. If a bead's score changed because the project code drifted (not because of remediation), that's a real change and should not be filtered out. The convergence check operates on scores, not on score-causation.

### Bead was tombstoned between passes

A bead that existed in the prior pass and was tombstoned (deleted) in this pass:
- Removed from this pass's scoring.
- Recorded in `convergence.json` under `beads_tombstoned_since_prior: [...]`.
- Doesn't count as a delta or a new false-closed.

### Bead was deferred between passes

A bead that was `closed` in prior and is now `deferred`:
- Treated as removed from the false-closed pool (deferred beads are in scope for spec extraction but not for the false-closed flag).
- Score is still computed and tracked.

### New beads added between passes (not by Phase 9)

Beads created by other agents/users between passes are added to this pass's universe and audited normally. Their first-pass scores set their baseline; the next pass after that can detect convergence for them.

---

## What "not converged" produces

When `convergence.json#is_converged: false`, the report writes:

```markdown
> ## ⚠ Not converged

> Reasons:
> - 3 beads have score deltas > 10 (worst: bd-abc123, Δ 47 points)
> - 2 new false-closed beads since prior pass: bd-foo, bd-bar
> - 0 new synthesis findings ✓
> - Rubric consistency: PASS (5/5 spot-checks within tolerance) ✓
> - All remediation beads exist: PASS ✓

> **Next-pass tasks:**
> 1. Re-verify bd-abc123 — investigate why the score moved 47 points (likely real change in source).
> 2. Spec-extract bd-foo and bd-bar (newly false-closed) — were they missed in prior pass?

> **To run another pass:** invoke /beads-compliance-and-completion-verification on this project after remediation work has landed. The next pass will write to passes/<new-UTC>/.
```

The user knows exactly what's left. They invoke the skill again whenever the bead-state has materially changed (typically after agents have worked through the remediation backlog).

---

## What "converged" produces

When `convergence.json#is_converged: true`, the report writes:

```markdown
> ## ✓ Converged

> Two consecutive passes show no material score changes and zero new false-closed findings.
>
> The bead graph is now truthful: every closed bead is either (a) actually done with score ≥ threshold or (b) explicitly tracked as completion-debt with a follow-up bead pointing at the gap.
>
> Recommended cadence going forward: re-run this audit weekly during active development, monthly during maintenance, or after any large feature merge.
```

The user can then archive the audit dir or keep running passes on a slower cadence as a tripwire.

---

## Long-term: the audit dir as a tripwire

Once converged, the audit dir is kept around. A scheduled job (cron / GH Actions / `/loop`) can re-run the skill periodically:

```bash
# Weekly tripwire
0 6 * * 1 cd <project> && /home/ubuntu/.claude/skills/beads-compliance-and-completion-verification/scripts/bootstrap-audit.sh . 700 closed-only && <run all phases>
```

Any pass that produces a non-converged result (e.g., a regression or a new false-closed bead) generates a notification — early warning that bead hygiene has slipped.

This is the "tripwire mode" — converged baseline + periodic re-verification = guaranteed bead-graph truthfulness over time.
