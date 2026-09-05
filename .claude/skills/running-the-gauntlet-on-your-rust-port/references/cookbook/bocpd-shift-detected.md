# bocpd-shift-detected

> BOCPD regime label flipped to `ShiftDetected` mid-soak on a monitored parity-score stream. Investigate: real regime change, or model drift, or convergence-loop oscillation.

## Trigger

Any of:

- `<workspace>/phase15_soak_bocpd/summary.json` reports `terminal_regime != "Stable"`.
- `<workspace>/round_<N>/soak/bocpd_alerts.jsonl` has a new entry.
- The CI `.github/workflows/bocpd-regime.yml` posts a release-blocking annotation for the parity-score stream (or a sub-pillar stream).
- A maintainer notices the parity-score time series visibly changes character around a known commit.

The shift detector is intentionally conservative; a single window flip can be a false positive, but two consecutive windows with `ShiftDetected` is the escalation rule from `parity-runbook-template.md § 9`.

## Operator Pipeline

```
⊞ SOAK (extend)            re-run the soak window to confirm shift isn't a one-window artifact
↓
⚠ ESCALATE-TO-FRESH-REPRO  bundle the shift evidence with the surrounding windows
↓
⌘ REDUCE / MINIMIZE        find the commit / event range where the shift occurred
↓
🧪 EXPERIMENT-DESIGN       hypothesize the cause: real regression, calibration drift, regime change
```

The minimization here is `git bisect`-style across the parity-score stream — find the shortest commit range where the regime flips from `Stable → ShiftDetected`.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
STREAM=<the BOCPD stream, e.g., parity_score | conformance_pass_rate | perf_geomean_ratio>

# 1. Re-run the soak window to confirm
"$WORKSPACE/scripts/run-soak-campaign.sh" "$PORT" "$WORKSPACE" --bocpd-stream "$STREAM" \
  --duration 4d --resume \
  --output "$WORKSPACE/round_$(cat $WORKSPACE/.round)/soak/bocpd/${STREAM}_extended.json"

# 2. Inspect the regime sequence
jq '[.windows[] | {start, end, regime, p_changepoint}]' \
  "$WORKSPACE/round_$(cat $WORKSPACE/.round)/soak/bocpd/${STREAM}_extended.json"
# Expect: pre-shift Stable, then a transient ShiftDetected, then either Stable (false positive)
# or persistent ShiftDetected (real regime change).

# 3. Bundle the shift evidence
"$WORKSPACE/scripts/run-conformance-suite.sh" "$PORT" "$WORKSPACE" --no-fuzz
# Copy the relevant shift window metadata into the emitted FailureBundle.

# 4. Find the commit range that drove the shift
"$WORKSPACE/scripts/mine-ledger.sh" "$WORKSPACE" --terms "$STREAM" --since "$(jq -r '.shift_window_start' $WORKSPACE/round_$(cat $WORKSPACE/.round)/soak/bocpd/${STREAM}_extended.json)" \
  --until "$(jq -r '.shift_window_end' $WORKSPACE/round_$(cat $WORKSPACE/.round)/soak/bocpd/${STREAM}_extended.json)"

# Bisect-style: for each commit in the range, replay the parity-score sampling
git -C "$PORT" rev-list "<shift_window_start>".."<shift_window_end>" | while read SHA; do
  git -C "$PORT" checkout "$SHA"
  "$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
  cp "$WORKSPACE/reports/parity_score.json" "/tmp/score_$SHA.json"
done
# Inspect: which commit is the first with shifted distribution?

# 5. File hypothesis
cat >> "$WORKSPACE/PERF_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — bocpd-shift-$STREAM — investigating
- stream: $STREAM
- regime_before: Stable
- regime_after: ShiftDetected
- shift_window: <ISO_start> .. <ISO_end>
- suspect_commit_range: <git SHA range>
- hypothesis: regression-introduced | calibration-drift | regime-change-due-to-workload-evolution | one-window-noise
- expected_signal: <which sub-stream or counter changes>
- falsifiability: <what would prove the shift is benign>
- one_line_invocation: $WORKSPACE/scripts/run-soak-campaign.sh $PORT $WORKSPACE --bocpd-stream $STREAM --duration 4d
- results_inline: <fill after experiment>
EOF

# 6. Create the bead
br create \
  --title "bocpd-shift-$STREAM" \
  --priority 1 \
  --type investigation \
  --labels "pillar:perf,lane:cc_4,recipe:bocpd-shift-detected,stream:$STREAM"
```

## Beads to claim (or create)

- `bocpd-shift-<stream>` (this recipe creates it).
- Dependency: `pattern:80-BOCPD-REGIME-DETECTION` — the regime contract.
- Dependency: `pattern:170-ROBUST-REGRESSION-DETECTOR` — the median + MAD detector that surfaces the suspect commits.
- If the shift maps to a real regression — link to a `perf-regression-<workload>` bead (chain through [perf-regression-triage.md](perf-regression-triage.md)).
- If the shift maps to an oracle change — link to an `oracle-div-<sig>` bead.
- Dependency (test): `test-bocpd-shift-<stream>-resolved` — extended soak rerun shows `Stable` for two consecutive windows.
- Dependency (doc): `doc-bocpd-shift-<stream>-resolution` — entry in `docs/progress/soak-resolutions/`.

## Exit Criteria

- [ ] Extended soak run completed at full duration (4d for parity_score; 24h for sub-pillars).
- [ ] Regime sequence inspected; shift is either confirmed (two consecutive `ShiftDetected` windows) or rejected (the single flip was a one-window artifact).
- [ ] If confirmed: shift evidence bundled; suspect commit range identified via bisect.
- [ ] Hypothesis filed.
- [ ] If real regression: chained to `perf-regression-triage` or `oracle-divergence-triage` for the actual remediation.
- [ ] If calibration drift: BOCPD prior re-tuned (via the calibration revision workflow — `subagents/waiver-author.md`, user signoff required).
- [ ] If regime-change-due-to-workload-evolution (e.g., reference released a new feature that broadens the workload): re-baseline expected, calibration may need adjustment.
- [ ] Two consecutive `Stable` windows on the post-fix soak rerun before close.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Re-tuning the BOCPD prior to make the shift go away. | Same as e-process recalibration — silent gate relaxation. Use the waiver workflow. |
| Declaring `Stable` after one window. | One window is the original false-positive distance. Need two consecutive `Stable` windows to clear. |
| Skipping the bisect because "the regression is obvious." | The bisect is the evidence. Without it, the linkage from shift to commit is a guess. |
| Assuming the shift is in the BOCPD model, not the data. | Models flip occasionally on noise; data shifts persist. Confirm via extended soak. |
| Not bundling the shift evidence. | The next agent can't reproduce the regime call without the surrounding windows. |
| Treating `ShiftDetected` as a hard failure on first flip. | Single-window flips are within the false-positive budget; only two-consecutive is the escalation trigger. |
| Running the extended soak on the original host that was already drifting. | Host drift can masquerade as data shift; run on rch worker pool for cleaner signal. |
| Closing without the `Stable`-for-two-windows non-regression test. | The shift can recur; the test pins the resolution. |

## Cross-references

- [../patterns/80-BOCPD-REGIME-DETECTION.md](../patterns/80-BOCPD-REGIME-DETECTION.md) — regime contract + parameter table.
- [../patterns/170-ROBUST-REGRESSION-DETECTOR.md](../patterns/170-ROBUST-REGRESSION-DETECTOR.md) — sister detector for short windows.
- [../patterns/90-FAILURE-BUNDLE.md](../patterns/90-FAILURE-BUNDLE.md) — shift-evidence bundle.
- [../patterns/255-RCH-OFFLOAD-DISCIPLINE.md](../patterns/255-RCH-OFFLOAD-DISCIPLINE.md) — clean-host requirement for soak.
- [../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) — multi-day BOCPD spec.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — release decisions condition on `Stable` regime.
- Related motions: [perf-regression-triage.md](perf-regression-triage.md), [e-process-rejection.md](e-process-rejection.md), [oracle-divergence-triage.md](oracle-divergence-triage.md), [cv-pct-flake.md](cv-pct-flake.md).
