# cv-pct-flake

> A microbench reported `cv_pct > 5` on a single run, or `cv_pct > 5` on three consecutive runs (the quarantine threshold). Decide: rerun, refactor the bench, quarantine, or accept widened noise band.

## Trigger

Any of:

- A bench's JSON report includes `summary.cv_pct > 5` AND the bench is in the `keep-gate-eligible` set.
- `python3 scripts/check_flake_budget.py .bench-history/` reports a quarantine candidate (3 consecutive `cv_pct > 5`).
- A perf claim cites a number from a bench whose `cv_pct` wasn't reported (the report is invalid; treat as flake-until-proven).
- The pass-over-pass detector emits a "delta within noise band, but cv_pct widened" annotation.

This recipe runs BEFORE `perf-regression-triage.md`. A regression on a flaky bench has no signal; bound cv_pct first.

## Operator Pipeline

```
⟁ TRIANGULATE-PROFILE     re-run the bench under controlled conditions; check measure_with_teardown
↓
⬡ INSTRUMENT-HOT-PATH     is the bench measuring framework noise instead of work?
↓
🗄 LEDGER-RETIRE (mine)   has this bench been quarantined before?
↓
🧪 EXPERIMENT-DESIGN      file PERF_HYPOTHESIS_LEDGER.md entry for the noise hypothesis
```

No `⚖` step — flake fixes don't update the ratchet; they update the bench harness.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
BENCH=<the flaky bench name, e.g., mt-mvcc-bench>

# 1. Rerun through the narrow-bench wrapper; it captures flamegraph/samply/strace by default.
cd "$PORT"
"$WORKSPACE/scripts/run-narrow-benches.sh" "$PORT" "$WORKSPACE" --benches "$BENCH"
# Inspect the artifact lane. If the repeated run's cv_pct is now <5, the original was sampling artifact.

# 2. Verify measure_with_teardown discipline — teardown OUTSIDE the timed window?
rg -n -A 5 "measure_with_teardown" "$PORT/crates" "$PORT/benches" || true
# Look for teardown calls inside start.elapsed() — that's the classic flake source.

# 3. Verify the bench uses the release-perf profile, not --release
grep -r "profile.release-perf" "$PORT/Cargo.toml" "$PORT/.cargo/config.toml" 2>/dev/null
# Missing release-perf → bench is running with LTO=off → spurious variance.

# 4. Mine the ledger for prior flake quarantines of this bench
"$WORKSPACE/scripts/mine-ledger.sh" "$WORKSPACE" --terms "$BENCH" --filter "cv_pct|flake|noise|quarantine"

# 5. Check the host profile — population-in-timed-window can also be a host issue
cat "$WORKSPACE/host_profile.json" | jq '.cpu.governor, .cpu.isolation, .ram.thp_state'
# governor != "performance", thp != "always", or isolation == "off" → host is the noise source.

# 6. File the hypothesis
cat >> "$WORKSPACE/PERF_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — flake-$BENCH-cv — investigating
- target_workload: $BENCH
- baseline_cv_pct: <observed>
- hypothesis: framework-noise | teardown-in-timed-window | host-noise | algorithmic-jitter | true-perf-bimodal
- expected_signal: <which counter or which N-of-runs split will resolve>
- falsifiability: <what would prove the hypothesis WRONG; e.g., "host pinned to perf governor still > 5">
- one_line_invocation: $WORKSPACE/scripts/run-narrow-benches.sh $PORT $WORKSPACE --benches $BENCH
- results_inline: <fill after experiment>
EOF

# 7. Create the bead
br create \
  --title "flake-$BENCH-cv" \
  --priority 2 \
  --type investigation \
  --labels "pillar:perf,lane:cc_2,recipe:cv-pct-flake,bench:$BENCH"

# 8. Decide:
#    a) Fix the bench (teardown moved out, warmup added, host pinned)
#    b) Quarantine the bench in .bench-history (it's still tracked, but doesn't gate)
#    c) Widen the noise band for this bench in parity_score_contract.toml (last resort; requires a documented reason)
```

## Beads to claim (or create)

- `flake-<bench>-cv` (this recipe creates it).
- If the bench is structurally flaky (e.g., a true bimodal workload) — dependency: `pattern:170-ROBUST-REGRESSION-DETECTOR` — median + MAD instead of mean + stddev.
- Dependency: `pattern:135-MEASURE-WITH-TEARDOWN` — teardown discipline.
- Dependency: `pattern:140-RELEASE-PERF-PROFILE` — never `--release`.
- Dependency (test): `test-flake-<bench>-cv-bounded` — N=10 reruns produce `cv_pct < 5`.
- Dependency (doc): `doc-flake-<bench>-resolution` — short note in `docs/progress/flake-resolutions/`.

If the bench is quarantined (not fixed) — additional dep on `pattern:255-RCH-OFFLOAD-DISCIPLINE` if the quarantine is host-related (rch worker pool produces lower noise than dev host).

## Exit Criteria

- [ ] Bench rerun with N=10 + warmup; `cv_pct` reported.
- [ ] If `cv_pct < 5` with N=10: original was sampling artifact; mark resolved, bench stays gating.
- [ ] If `cv_pct > 5` with N=10: teardown / profile / host audit complete; root cause identified.
- [ ] Hypothesis ledger entry filed.
- [ ] One of: (a) bench fixed; (b) bench quarantined with a documented quarantine entry in `<workspace>/.bench-history/quarantine.json`; (c) noise band widened with a parity_score_contract revision bump + a paragraph rationale.
- [ ] Quarantined benches are still recorded in `.bench-history` (they just don't gate); they are NEVER deleted.
- [ ] If host was the issue, recipe linked to `host_profile.json` audit + recommendation (pin governor, isolate cores, set THP, …).

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| "Reran once, it was 4%, we're good." | Single rerun cannot bound `cv_pct`. N≥5 minimum; N=10 for benches that are gate-blocking. |
| Deleting the flaky bench from `.bench-history`. | The history file is the gate. Quarantining keeps the history; deleting hides the noise. |
| Widening the noise band without a contract revision bump. | The noise band is in `parity_score_contract.toml`. Edits without a revision bump are silent gate relaxation. |
| Re-running until you get a green pass. | If 1 of 5 runs passes, the result is `5x cv` over the run set — that's the actual variance. |
| Population inside the timed window. | Classic teardown-in-elapsed bug; check `measure_with_teardown` discipline. |
| Quarantining without a quarantine entry. | The quarantine.json file is the contract. No entry = the bench is silently disabled. |
| Treating the flake as a regression. | Routing `flake → perf-regression-triage` wastes 45 minutes on noise. Bound cv_pct first. |
| Reporting bench numbers without `cv_pct`. | Reports without `cv_pct` are invalid; the perf lane should refuse to score them. |

## Cross-references

- [../patterns/135-MEASURE-WITH-TEARDOWN.md](../patterns/135-MEASURE-WITH-TEARDOWN.md) — teardown outside timed window.
- [../patterns/140-RELEASE-PERF-PROFILE.md](../patterns/140-RELEASE-PERF-PROFILE.md) — `release-perf` mandatory.
- [../patterns/170-ROBUST-REGRESSION-DETECTOR.md](../patterns/170-ROBUST-REGRESSION-DETECTOR.md) — median + MAD.
- [../patterns/155-BENCH-HISTORY-RATCHET.md](../patterns/155-BENCH-HISTORY-RATCHET.md) — `.bench-history` is the gate.
- [../patterns/125-COMPREHENSIVE-BENCH.md](../patterns/125-COMPREHENSIVE-BENCH.md) — comprehensive-bench JSON v3.
- [../patterns/255-RCH-OFFLOAD-DISCIPLINE.md](../patterns/255-RCH-OFFLOAD-DISCIPLINE.md) — when to offload to rch for noise control.
- [../tooling/BENCH-TOOLCHAIN.md](../tooling/BENCH-TOOLCHAIN.md) — criterion/hyperfine/samply pitfalls.
- [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) — keep-gate vocabulary.
- Related motions: [perf-regression-triage.md](perf-regression-triage.md), [mt8-attribution-flat.md](mt8-attribution-flat.md), [bocpd-shift-detected.md](bocpd-shift-detected.md).
