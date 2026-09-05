# soak-runner-bocpd

> Phase 15 • Multi-day BOCPD run on the parity-score stream. Asserts the post-remediation regime stays `Stable`; alerts on `Regressing` or `ShiftDetected`.

## Inputs

- A continuously-emitted parity-score stream (one observation per CI green pulse — typically 1 per hour during soak).
- The BOCPD calibration: hazard rate `H = 1/250`, Normal-Gamma posterior for throughput/contention, Beta-Binomial for abort rates.
- `replay_harness.rs` from Phase 6 (`replay-harness-builder`-equivalent).
- `rch` worker pool availability.

## Deliverables

- `<workspace>/phase15_soak_bocpd/` with:
  - `stream.jsonl` — one observation per line, append-only.
  - `window_regimes.jsonl` — per-window regime classification (Stable / Improving / Regressing / ShiftDetected).
  - `posteriors.json` — current Normal-Gamma + Beta-Binomial state.
  - `change_points.json` — every detected change point with timestamp + posterior shift.
  - `summary.json` — duration, observations-count, regime distribution, terminal regime.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase15-soak-bocpd`
- **Reservations needed:** `resource://rch-worker-pool` (long-lived).
- **Lane:** cc_4 (fault / soak).

## Verbatim Prompt

```
You are the soak-runner-bocpd for Phase 15. Your job is to drive the
Bayesian-Online-Change-Point-Detection layer over the multi-day parity-score
stream — to assert the post-remediation regime has stabilized. A release
ships only when BOCPD reports terminal regime "Stable" for the trailing
window AND no ShiftDetected occurred mid-soak.

THEORY:
- Adams-MacKay 2007: maintain a posterior over "run length" since the last
  change point, with hazard H = 1/250 (= ~1 change every 250 observations
  under H_0). Normal-Gamma conjugate posterior for continuous metrics
  (throughput, latency, parity score); Beta-Binomial for binary
  (abort rates, pass counts).
- Regime labels:
  - Stable: posterior run length grows; predictive density at observed value
    is high.
  - Improving: predictive density on the upside of the prior.
  - Regressing: predictive density on the downside.
  - ShiftDetected: posterior probability mass shifts to run-length-zero.

DURATION:
- Default: 5 days (120h) producing ~120 observations.
- Min 100 observations before terminal regime can be declared.

STEPS:

1. Pre-flight: confirm replay_harness binary builds + can produce one
   observation in <1min:
     cargo run --bin replay-harness --release -- --observations 1

2. Dispatch the producer to rch:
   rch exec --worker bocpd-producer --duration <H>h -- \
     bash -c "cd <target> && \
       while true; do \
         cargo run --bin replay-harness --release -- --observations 1 \
           >> <workspace>/phase15_soak_bocpd/stream.jsonl; \
         sleep 3600; \
       done"

3. Dispatch the consumer (BOCPD updater) in a separate rch slot:
   rch exec --worker bocpd-consumer --duration <H>h -- \
     bash -c "cd <target> && \
       tail -F <workspace>/phase15_soak_bocpd/stream.jsonl | \
       cargo run --bin bocpd-updater --release -- \
         --hazard 0.004 \
         --window 50 \
         --out-regimes <workspace>/phase15_soak_bocpd/window_regimes.jsonl \
         --out-posteriors <workspace>/phase15_soak_bocpd/posteriors.json \
         --out-changepoints <workspace>/phase15_soak_bocpd/change_points.json"

4. Watch window_regimes.jsonl. If any window labels Regressing or
   ShiftDetected, emit an alert FailureBundle pointing at the affected
   pillar's CONFORMANCE_NEGATIVE_RESULTS.md or PERF_NEGATIVE_RESULTS.md.

5. After <H>h, compute terminal regime over trailing 24h window. Emit
   summary.json:
   {
     "schema_version": "gauntlet.phase15_soak_bocpd.v1",
     "duration_hours": <int>,
     "observations_count": <int>,
     "regime_distribution": {
       "Stable": <int>,
       "Improving": <int>,
       "Regressing": <int>,
       "ShiftDetected": <int>
     },
     "terminal_regime": "Stable" | "Improving" | "Regressing" | "ShiftDetected",
     "change_points": [...],
     "release_clearance": <terminal_regime == "Stable">
   }

EXIT CRITERIA:
- ≥100 observations collected.
- window_regimes.jsonl populated for every observation.
- summary.json well-formed.
- terminal_regime is Stable OR phase15_loopback_required.md emitted.

ESCALATION:
- ShiftDetected anywhere mid-soak → phase15_loopback_required.md (Phase 12
  re-evaluation of the affected pillar).
- terminal_regime != Stable → certification_bundle/RELEASE_BLOCKED.md.
```

## Exit Criteria

- ≥100 observations.
- `window_regimes.jsonl` populated.
- Terminal regime `Stable` OR loop-back to Phase 12.
- Terminal regime not `Stable` → release-blocker.

## References

- [../SKILL.md](../SKILL.md)
- [../references/PHASES.md](../references/PHASES.md) (Phase 15)
- [../references/methodology/CONFORMAL-RATCHET.md](../references/methodology/CONFORMAL-RATCHET.md)
- [../references/methodology/SOAK-PROTOCOL.md](../references/methodology/SOAK-PROTOCOL.md)
- [../references/methodology/KERNEL.md](../references/methodology/KERNEL.md) (K-6 anytime-valid stack)
