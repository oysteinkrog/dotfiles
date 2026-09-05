# cross-pillar-regression

> Fixing a perf bead lowered the conformance lower bound (or vice versa, or either lowered surface coverage). The gauntlet forbids declaring victory on one pillar while another regresses. Decide: waive (with cross-pillar trade-off rationale), redesign, or revert.

## Trigger

Any of:

- After closing a perf bead, `apply-ratchet.sh` reports `Block` on the conformance category.
- After landing a conformance fix, the perf geomean drops > 5% on a related workload.
- After implementing a surface feature, an oracle test in an adjacent area went red.
- `bv --robot-insights | jq '.CrossPillarRegressions'` is non-empty.
- A reviewer notices the perf-win commit's diff also touches comparator or canonicalization code.

This recipe is the rarest of the twelve motions (most fixes are pillar-scoped), but it's the highest-stakes — a cross-pillar regression that's accepted silently becomes the gauntlet's biggest credibility loss.

## Operator Pipeline

```
⊕ ISOMORPHIC-REWRITE       enumerate fixes that recover the regressed pillar WITHOUT undoing the gain
↓
⚖ RATCHET-LOWER-BOUND     re-check both pillars; both must clear the floor for Allow
↓
🪟 FRESH-EYES              the trade-off rationale is the most adversarial review target
↓
📐 CONFORMAL-BAND          confirm decision uses lower bound on BOTH pillars, not one or the other
```

The pipeline is intentionally short: by the time you're here, the diagnosis is already done; the question is what to do, not why it happened. Most of the work is enumerating alternatives that don't recreate the original trade-off.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
SOURCE_PILLAR=<the pillar whose fix caused the regression: perf | conformance | surface>
SINK_PILLAR=<the pillar that regressed: perf | conformance | surface>
SOURCE_BEAD=<bead id of the precipitating fix>
WORKLOAD_OR_TEST=<the regressed workload or test name>

# 1. Confirm both pillars' current state
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
jq '.categories | to_entries[] | {category: .key, point_estimate: .value.mean, conformal_lower_bound: .value.lower}' \
  "$WORKSPACE/reports/parity_score.json"

# 2. Mine for prior cross-pillar trade-offs in the same area
"$WORKSPACE/scripts/mine-ledger.sh" "$WORKSPACE" --terms "$SOURCE_PILLAR,$WORKLOAD_OR_TEST" --filter "cross.pillar|trade.off|regressed"
"$WORKSPACE/scripts/mine-cass-cross-machine.sh" "$WORKSPACE" --term "cross-pillar $WORKLOAD_OR_TEST" --window 60d

# 3. Inspect the precipitating commit
git -C "$PORT" show "$(br show $SOURCE_BEAD --json | jq -r '.commits[0]')" --stat
# Look for: comparator code touched in a perf-bead, canonicalization moved in a surface bead, etc.

# 4. File the cross-pillar hypothesis
cat >> "$WORKSPACE/${SOURCE_PILLAR^^}_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — crosspillar-${SOURCE_PILLAR}-${SINK_PILLAR} — investigating
- source_pillar: $SOURCE_PILLAR
- sink_pillar: $SINK_PILLAR
- source_bead: $SOURCE_BEAD
- workload_or_test: $WORKLOAD_OR_TEST
- hypothesis: trade-off-fundamental | trade-off-incidental-can-decouple | source-fix-was-wrong
- expected_signal: <if "decouple" is right, what alternative implementation looks like>
- falsifiability: <e.g., "if no rewrite recovers the sink pillar without losing the source gain, trade-off is fundamental">
- one_line_invocation: $WORKSPACE/scripts/compute-parity-score.sh $WORKSPACE
- results_inline: <fill after decision>
EOF

# 5. Create the bead
br create \
  --title "crosspillar-${SOURCE_PILLAR}-${SINK_PILLAR}" \
  --priority 0 \
  --type investigation \
  --labels "pillar:multi,lane:cc_1,recipe:cross-pillar-regression,source-bead:$SOURCE_BEAD"

# 6. Enumerate isomorphic rewrites (mandatory: ≥3)
# Path A: decouple — find a rewrite that achieves the source gain without touching the sink path
# Path B: redesign — replace the source fix with a different approach that doesn't trade off
# Path C: waive — file a structured trade-off waiver (user signoff; see subagents/waiver-author.md)
# Path D: revert — back out the source fix entirely; the gain wasn't worth the loss

# 7. For each rewrite, generate proof sketch + Impact×Confidence/Effort score
# Use references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md for the 5-line proof

# 8. After choosing + landing the chosen rewrite:
"$WORKSPACE/scripts/run-bench-matrix.sh" "$PORT" "$WORKSPACE"
"$WORKSPACE/scripts/run-conformance-suite.sh" "$PORT" "$WORKSPACE"
"$WORKSPACE/scripts/compute-feature-coverage.sh" "$WORKSPACE"
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/apply-ratchet.sh" "$WORKSPACE"

# 9. Both source AND sink pillars must clear the floor on the LOWER bound
jq '.categories | to_entries[] | select(.key == "'$SOURCE_PILLAR'" or .key == "'$SINK_PILLAR'") |
  {category: .key, conformal_lower_bound: .value.lower}' \
  "$WORKSPACE/reports/parity_score.json"
# Both passes: true required.

# 10. Fresh-eyes against the trade-off rationale (adversarial)
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "crosspillar-${SOURCE_PILLAR}-${SINK_PILLAR}" --adversarial
```

## Beads to claim (or create)

- `crosspillar-<source>-<sink>` (priority 0; release-blocking).
- Dependency: `pattern:75-BAYESIAN-CONFORMAL-SCORE` — lower-bound on both pillars.
- Dependency: `pattern:250-ISOMORPHISM-PROOF` — the trade-off must be examined under behavior-preserving rewrites.
- Dependency: `pattern:180-NEGATIVE-LEDGER` (if waive or revert path) — the trade-off rationale is itself a ledger entry.
- Linked to the source bead (the original fix that caused the regression).
- Dependency (test): `test-crosspillar-${source}-${sink}-resolved` — both pillars clear floor.
- Dependency (bench): `bench-crosspillar-${source}-${sink}-no-regression` — confirms the bench hasn't moved adversely.
- Dependency (doc): `doc-crosspillar-${source}-${sink}-trade-off-analysis` — entry under `docs/progress/cross-pillar/`.

## Exit Criteria

- [ ] Both pillars' current state confirmed (point estimate + lower bound + floor for each).
- [ ] Prior cross-pillar trade-offs in the area mined.
- [ ] Precipitating commit inspected; the cross-cutting change identified.
- [ ] Hypothesis filed with the four-way category (trade-off-fundamental | incidental-can-decouple | source-fix-was-wrong | sink-was-wrong).
- [ ] ≥3 isomorphic rewrites enumerated (decouple | redesign | waive | revert); each with a 5-line proof.
- [ ] Chosen path executed; both pillars now clear the floor on the LOWER bound.
- [ ] If waive: user signoff via waiver-author; waiver names both pillars + expiration ≤30 days + retry-condition predicate.
- [ ] If revert: source fix backed out; ledger entry for both the original gain AND the revert with retry-condition predicates.
- [ ] Adversarial fresh-eyes pass on the trade-off rationale.
- [ ] Two fresh-eyes clean rounds.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Comparing the point estimate on one pillar to the lower bound on another. | Both must use the LOWER bound; mixing them lets you smuggle a regression past the gate. |
| "The conformance regression is tiny, the perf win is huge." | The conformal band converts both to comparable LOWER bounds. Trust the math, not the eye. |
| Closing the bead with only one pillar's ratchet checked. | `apply-ratchet.sh` evaluates ALL pillars; both must be `Allow`. |
| Waiving without identifying which architectural change would decouple. | The retry-condition predicate must name the decoupling change. "Maybe later" doesn't count. |
| Reverting silently and not filing a ledger entry for the loss of the original gain. | Both directions are negative results: the gain that was lost AND the regression that was avoided. |
| Treating the trade-off as inherent without enumerating decouple paths. | Most cross-pillar regressions ARE decouplable; "fundamental" is the rare case, not the default. |
| Skipping the adversarial fresh-eyes pass. | Trade-off rationales are where motivated reasoning hides; adversarial review catches it. |
| Linking only to the source bead, not also the regressed pillar's pre-existing baseline. | The post-mortem needs both anchors: what was traded, what was gained, what's the new state. |

## Cross-references

- [../patterns/75-BAYESIAN-CONFORMAL-SCORE.md](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md) — multi-pillar lower-bound math.
- [../patterns/250-ISOMORPHISM-PROOF.md](../patterns/250-ISOMORPHISM-PROOF.md) — 5-line proof template.
- [../patterns/180-NEGATIVE-LEDGER.md](../patterns/180-NEGATIVE-LEDGER.md) — both-directions ledger entries.
- [../patterns/185-RETRY-CONDITION-PREDICATE.md](../patterns/185-RETRY-CONDITION-PREDICATE.md) — predicate templates.
- [../remediation/ISOMORPHISM-PROOF-TEMPLATE.md](../remediation/ISOMORPHISM-PROOF-TEMPLATE.md) — proof template.
- [../remediation/REMEDIATION-PATTERNS.md](../remediation/REMEDIATION-PATTERNS.md) — 10 winning patterns; check whether one applies.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — full ratchet contract.
- [../methodology/ANTI-PATTERNS.md](../methodology/ANTI-PATTERNS.md) — agreement-by-error-message + related anti-patterns.
- Related motions: [perf-regression-triage.md](perf-regression-triage.md), [oracle-divergence-triage.md](oracle-divergence-triage.md), [ratchet-block.md](ratchet-block.md), [surface-gap-found.md](surface-gap-found.md).
