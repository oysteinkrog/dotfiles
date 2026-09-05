# e-process-rejection

> An invariant's e-value crossed `1/α` (Ville's-inequality rejection). The invariant has been falsified at the configured significance level. Triage the rejection, attribute the root cause, file the FailureBundle, decide whether to fix the engine or recalibrate the e-process.

## Trigger

Any of:

- `cargo test --test eprocess_smoke -- --release` fails with the rejection annotation.
- `bv --robot-insights | jq '.EProcesses[] | select(.e_value > .reject_threshold)'` is non-empty.
- A soak runner posts `<workspace>/round_<N>/soak/eprocess_alerts.jsonl` with a new entry.
- The CI `.github/workflows/eprocess-ville-alarm.yml` posts a release-blocking annotation.

Hardware-enforced invariants (`p₀=1e-9, λ=0.999, α=1e-6`) are the most adversarial; a rejection there is almost never noise. Software-enforced invariants (`p₀=1e-6, λ=0.9, α=0.001`) tolerate more model-mismatch — but the discipline is the same.

## Operator Pipeline

```
⚠ ESCALATE-TO-FRESH-REPRO   emit FailureBundle for the rejection
↓
⌘ REDUCE / MINIMIZE        delta-debug the input stream that drove the e-value over 1/α
↓
⊙ DEBOUNCE-FALSE-POSITIVE  is the rejection a real invariant violation, or model-mismatch?
↓
🧪 EXPERIMENT-DESIGN       file the hypothesis: violation vs miscalibration vs reference drift
↓
⊕ ISOMORPHIC-REWRITE       enumerate fixes: engine fix OR e-process recalibration
```

The choice of engine-fix vs recalibration is the load-bearing call. A maintainer cannot recalibrate to make a real violation go away; the rejection threshold is contractually fixed (parameters live in `assets/eprocess-calibration-template.toml`).

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
INVARIANT_ID=<the rejected invariant, e.g., INV-DURABILITY-FSYNC-BEFORE-ACK>

# 1. Emit FailureBundle from the rejection
cd "$PORT"
"$WORKSPACE/scripts/run-conformance-suite.sh" "$PORT" "$WORKSPACE" --no-fuzz
# Copy or annotate the emitted FailureBundle with invariant_id=$INVARIANT_ID.

# 2. Inspect the rejection envelope
jq '{
  e_value, reject_threshold, p0, lambda, alpha,
  schedule_fingerprint, first_violation_event,
  input_stream_length, sequence_likelihood,
  engines
}' "$WORKSPACE/round_$(cat $WORKSPACE/.round)/conformance/eprocess_rejections/$INVARIANT_ID.json"

# 3. Reduce the input stream that drove the rejection
"$WORKSPACE/scripts/replay-failure.sh" \
  "$WORKSPACE/round_$(cat $WORKSPACE/.round)/conformance/eprocess_rejections/$INVARIANT_ID.json" \
  --minimize

# 4. Distinguish: is this real violation, or model-mismatch (calibration drift)?
"$WORKSPACE/scripts/run-conformance-suite.sh" "$PORT" "$WORKSPACE" --no-fuzz
# Replays the same stream against the oracle when the harness implements that path.
# If the oracle ALSO rejects → real invariant violation in both engines (escalate upstream)
# If only the subject rejects → engine bug in the port
# If neither rejects on replay but original did → schedule-dependent or noise

# 5. File hypothesis
cat >> "$WORKSPACE/CONFORMANCE_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — eproc-reject-$INVARIANT_ID — investigating
- invariant_id: $INVARIANT_ID
- e_value_at_rejection: <number>
- reject_threshold: <number = 1/alpha>
- p0_lambda_alpha: <as configured>
- hypothesis: engine-violation | reference-also-violates | calibration-drift | schedule-noise
- expected_signal: <which sub-counter or which oracle replay outcome>
- falsifiability: <what 'cleared' would look like>
- one_line_invocation: $WORKSPACE/scripts/run-conformance-suite.sh $PORT $WORKSPACE --no-fuzz
- results_inline: <fill after fix or recalibration>
EOF

# 6. Create the bead
br create \
  --title "eproc-reject-$INVARIANT_ID" \
  --priority 0 \
  --type bug \
  --labels "pillar:conformance,lane:cc_4,recipe:e-process-rejection,invariant:$INVARIANT_ID"

# 7. Apply the fix (engine change) OR file a structured calibration revision
# Calibration revisions require a parity_score_contract bump + paragraph rationale + user signoff
# (waiver-author subagent handles the workflow).

# 8. Re-run the soak campaign against the fixed code; e-value must stay < 1/α for full soak duration
"$WORKSPACE/scripts/run-soak-campaign.sh" "$PORT" "$WORKSPACE" --invariant "$INVARIANT_ID" --duration 24h
```

## Beads to claim (or create)

- `eproc-reject-<INV-X>` (priority 0; rejection is a release-blocking signal).
- Dependency: `pattern:70-E-PROCESSES` — Ville-inequality rejection contract.
- Dependency: `pattern:90-FAILURE-BUNDLE` — rejection envelope is a FailureBundle variant.
- Dependency: `pattern:80-BOCPD-REGIME-DETECTION` (if recalibrating; the BOCPD stream tells you whether the rejection was a regime change or steady-state violation).
- Dependency (test): `test-eproc-<INV-X>-cleared` — soak rerun produces `e_value < 1/α` for the full window.
- Dependency (bench): not always required; only if the fix touches a perf-affecting path.
- Dependency (doc): `doc-eproc-<INV-X>-resolution` — entry under `docs/progress/eprocess-resolutions/` explaining the root cause + the fix or the recalibration rationale.

## Exit Criteria

- [ ] FailureBundle emitted for the rejection; all 14 fields populated (or partial with explicit "why").
- [ ] Input stream reduced to 1-minimal (or documented as already 1-minimal).
- [ ] Replay-with-reference distinguishes: engine-violation vs reference-also-violates vs calibration-drift vs schedule-noise.
- [ ] Hypothesis filed.
- [ ] If engine-violation: fix landed; replay confirms e-value stays below threshold over full soak duration.
- [ ] If reference-also-violates: escalate upstream (file an issue against the reference project); the port doesn't change.
- [ ] If calibration-drift: structured calibration revision filed via `subagents/waiver-author.md` with user signoff; new parameters committed to `assets/eprocess-calibration-template.toml` AND `parity_score_contract.toml` revision bumped.
- [ ] If schedule-noise: increase λ, re-run soak; if still rejects, treat as real violation.
- [ ] Two consecutive soak runs at full duration without rejection.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Recalibrating to make the rejection go away. | Calibration is contractual; silent adjustment is dishonesty. Use the waiver-author subagent and user signoff. |
| Treating the rejection as a flake without replay. | Hardware-enforced invariants reject deterministically; flake assumption requires explicit replay evidence. |
| Patching the e-process implementation to weaken the test. | The e-process is shared infrastructure; weakening it weakens every invariant. Change the engine, not the test. |
| Skipping the FailureBundle "because the rejection envelope already has the seed." | The bundle is the canonical replay artifact; the rejection envelope isn't a replacement. |
| Closing without the 24h+ soak rerun. | A 5-minute "soak" doesn't certify that the e-value stays low; the original violation may recur. |
| Not distinguishing engine-violation from reference-also-violates. | If the reference also violates, the port isn't broken — the world model is. Escalate, don't fix. |
| Lowering `α` (raising `1/α`) to dodge rejection. | Same as recalibrating; weakens the gate without admitting it. |
| Closing the bead with `test-` dep that uses a different invariant. | The non-regression test must exercise the exact invariant that rejected. |

## Cross-references

- [../patterns/70-E-PROCESSES.md](../patterns/70-E-PROCESSES.md) — e-process construction + Ville's inequality.
- [../patterns/80-BOCPD-REGIME-DETECTION.md](../patterns/80-BOCPD-REGIME-DETECTION.md) — regime context for calibration decisions.
- [../patterns/90-FAILURE-BUNDLE.md](../patterns/90-FAILURE-BUNDLE.md) — bundle schema.
- [../patterns/95-FIRST-FAILURE-EXPLAINER.md](../patterns/95-FIRST-FAILURE-EXPLAINER.md) — `first_violation_event`.
- [../patterns/60-FAULT-VFS.md](../patterns/60-FAULT-VFS.md) — many durability-class rejections originate from fault injection.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — how rejections affect ratchet decisions.
- [../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) — soak durations per invariant class.
- [../../assets/eprocess-calibration-template.toml](../../assets/eprocess-calibration-template.toml) — parameter contract.
- Related motions: [oracle-divergence-triage.md](oracle-divergence-triage.md), [bocpd-shift-detected.md](bocpd-shift-detected.md), [new-fault-class-discovered.md](new-fault-class-discovered.md).
