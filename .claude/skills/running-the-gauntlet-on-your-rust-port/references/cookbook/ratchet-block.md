# ratchet-block

> `scripts/apply-ratchet.sh` emitted `Block`. The proposed change lowers the conformal lower bound on parity score below the ratchet floor. Decide: waive (with signoff), fix (recover the bound), or revert (back the change out).

## Trigger

Any of:

- `scripts/apply-ratchet.sh <workspace>` outputs `Block` for one or more categories.
- The CI `.github/workflows/parity-score-ratchet.yml` posts a release-blocking annotation.
- `cat <workspace>/reports/ratchet_state.json | jq '.last_decision'` returns `"Block"`.
- The pre-push hook (`scripts/bead-graph-validator.sh` + ratchet) rejects a push.

`Block` is the gauntlet's most consequential signal: it means a release candidate is being made worse, not just held steady. `Quarantine` (sibling outcome) means held — not worsened — and routes through a different (lighter) recipe.

## Operator Pipeline

```
⚖ RATCHET-LOWER-BOUND      re-confirm Block is on lower bound, not point estimate
↓
📐 CONFORMAL-BAND          inspect the band: is it widening or shifting?
↓
🗄 LEDGER-RETIRE (mine)    has this category been blocked before for a similar reason?
↓
⊕ ISOMORPHIC-REWRITE       enumerate 3 paths: waive, fix, revert; pick on rubric + signoff
```

Most `Block` outcomes resolve with `fix` (the agent finds a rewrite that recovers the lower bound). `waive` is rare and requires user signoff via `subagents/waiver-author.md`. `revert` is the default safe path when neither fix nor waive close cleanly within the iteration window.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
CATEGORY=<the blocked category, from parity_score_contract.toml>

# 1. Re-confirm the block (idempotent)
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/apply-ratchet.sh" "$WORKSPACE"
# Output includes: lower_bound_now, lower_bound_floor, delta, decision

# 2. Inspect the conformal band: width + position
jq '{
  point_estimate: .categories["'$CATEGORY'"].mean,
  lower_bound:   .categories["'$CATEGORY'"].lower,
  upper_bound:   .categories["'$CATEGORY'"].upper,
  band_width:    (.categories["'$CATEGORY'"].upper - .categories["'$CATEGORY'"].lower),
  floor:         "see reports/ratchet_state.json"
}' "$WORKSPACE/reports/parity_score.json"

# Is the band widening (more variance, lower bound dragged down) vs shifting (mean moved down)?
# - Widening: more samples needed; possibly a calibration issue or a flaky bench
# - Shifting: real regression; route through perf-regression-triage / oracle-divergence-triage

# 3. Mine prior closures
"$WORKSPACE/scripts/mine-ledger.sh" "$WORKSPACE" --terms "$CATEGORY" --filter "ratchet|block|waive|revert"
"$WORKSPACE/scripts/mine-cass-cross-machine.sh" "$WORKSPACE" --term "ratchet block $CATEGORY" --window 60d

# 4. Identify the precipitating change
git -C "$PORT" log --oneline --since="1 week ago" -- "crates/$CATEGORY*" || true
# Plus inspect the most recent .bench-history changes in this category

# 5. Decide: waive | fix | revert
#
# 5a. FIX (most common):
#     Route into perf-regression-triage.md or oracle-divergence-triage.md depending on pillar.
#     The bead chain is: ratchet-block-<category> --depends-on--> <triage-bead>
#
# 5b. WAIVE (rare; requires structured user signoff):
#     # NEVER self-sign. Always invoke waiver-author with user confirmation.
#     # The waiver records: category, regression magnitude, why fix isn't viable,
#     # expiration date (max 30 days), retry-condition predicate to retire the waiver.
#     # See subagents/waiver-author.md.
#
# 5c. REVERT:
#     git -C "$PORT" log -1 --format=%H -- $CATEGORY*  # find the precipitating commit
#     git -C "$PORT" revert <SHA>
#     # File a negative-ledger entry naming the retry-condition predicate that would
#     # justify trying the change again.

# 6. Create the bead
br create \
  --title "ratchet-block-$CATEGORY" \
  --priority 0 \
  --type investigation \
  --labels "pillar:scoring,lane:cc_2,recipe:ratchet-block,category:$CATEGORY"

# 7. After action, re-confirm Allow
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/apply-ratchet.sh" "$WORKSPACE"
# Expect: Allow. If still Block, the action was insufficient.

# 8. Persist the new ratchet state (monotonic)
"$WORKSPACE/scripts/update-ratchet-state.sh" "$WORKSPACE" "$WORKSPACE/reports/parity_score.json"
```

## Beads to claim (or create)

- `ratchet-block-<category>` (priority 0; release-blocking).
- Dependency: `pattern:75-BAYESIAN-CONFORMAL-SCORE` — the lower-bound math.
- Dependency: `pattern:155-BENCH-HISTORY-RATCHET` (if perf pillar) — `.bench-history` as the gate.
- Dependency: `pattern:180-NEGATIVE-LEDGER` — every waived or reverted change must have a ledger entry with a retry-condition predicate.
- If `fix` path: linked to a `perf-regression-<workload>` or `oracle-div-<sig>` bead.
- If `waive` path: linked to a waiver bead authored by `subagents/waiver-author.md`; waiver expires in ≤30 days.
- If `revert` path: revert commit linked; ledger entry filed with one of the 8 retry-condition predicate templates.
- Dependency (test): `test-ratchet-block-<category>-resolved` — re-run of `apply-ratchet.sh` returns `Allow`.
- Dependency (doc): `doc-ratchet-block-<category>-resolution`.

## Exit Criteria

- [ ] Block re-confirmed (not a transient).
- [ ] Lower bound vs floor vs band width inspected; widening-vs-shifting distinguished.
- [ ] Prior closures mined (60-day window).
- [ ] Decision made: `fix` | `waive` | `revert` with explicit rationale.
- [ ] If `fix`: routed through the appropriate triage cookbook (perf or oracle); chained bead; `apply-ratchet.sh` now returns `Allow`.
- [ ] If `waive`: user signoff via `waiver-author.md`; waiver entry in `reports/waivers.jsonl` with expiration ≤30 days and a retry-condition predicate that would retire it; `apply-ratchet.sh` returns `Waiver` (not `Allow`); CI annotation acknowledges the waiver.
- [ ] If `revert`: revert commit landed; negative-ledger entry with retry-condition predicate; `apply-ratchet.sh` returns `Allow` on the reverted state.
- [ ] `reports/ratchet_state.json` updated with monotonicity enforcement (`scripts/update-ratchet-state.sh` rejects non-monotonic updates except via waivers).
- [ ] Two fresh-eyes clean rounds before closing the bead.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| "Just bump the floor." | The ratchet floor only moves UP. Bumping down to dodge a block is the lie the gauntlet exists to prevent. |
| Self-signed waiver. | Waivers are user-signed, never agent-signed. The waiver-author subagent enforces this. |
| Open-ended waiver (no expiration). | Every waiver has `≤30 days` expiration; agents must re-confront the gap. |
| Citing the point estimate. | Release decisions use the LOWER bound. If point estimate is fine but lower bound is below floor, the block stands. |
| Reverting without a ledger entry. | Reverts are negative results too; without a retry-condition predicate, the same change comes back in three months. |
| Closing the bead without `apply-ratchet.sh` returning `Allow` or `Waiver`. | The bead's job is to clear the block. If the block stands, the bead is open. |
| Routing through `perf-regression-triage` without first confirming the block is on a perf category. | A surface-pillar block routes through `surface-gap-found`, not perf triage. |
| Updating `ratchet_state.json` by hand. | Use `update-ratchet-state.sh`; it routes the score artifact through `apply-ratchet.sh`'s monotonicity + waiver gate. |

## Cross-references

- [../patterns/75-BAYESIAN-CONFORMAL-SCORE.md](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md) — Beta posterior + conformal band math.
- [../patterns/155-BENCH-HISTORY-RATCHET.md](../patterns/155-BENCH-HISTORY-RATCHET.md) — the perf-side ratchet file.
- [../patterns/180-NEGATIVE-LEDGER.md](../patterns/180-NEGATIVE-LEDGER.md) — ledger entry schema.
- [../patterns/185-RETRY-CONDITION-PREDICATE.md](../patterns/185-RETRY-CONDITION-PREDICATE.md) — the 8 predicate templates.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — full ratchet contract.
- [../methodology/RETRY-CONDITION-VOCABULARY.md](../methodology/RETRY-CONDITION-VOCABULARY.md) — vocabulary.
- [../../assets/parity-score-contract-template.toml](../../assets/parity-score-contract-template.toml) — category weights + floors.
- Related motions: [perf-regression-triage.md](perf-regression-triage.md), [oracle-divergence-triage.md](oracle-divergence-triage.md), [cross-pillar-regression.md](cross-pillar-regression.md), [surface-gap-found.md](surface-gap-found.md).
