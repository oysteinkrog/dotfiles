# perf-regression-triage

> Pass-over-pass shows -X% on a primary score. Diagnose, decide, and remediate without taking 2 hours to re-derive the procedure.

## Trigger

Any of:

- `scripts/apply-ratchet.sh` returns `Block` or `Quarantine` on a perf field with negative delta.
- `.bench-history/<bench>.latest.json` diff against the previous run exceeds the gate (primary `-3%`, geomean `-5%`, per-category `-10%`, p90 `-15%`, throughput `-5%`).
- A CI bench job posts a regression annotation; OR a maintainer manually observed a slowdown on local dev.
- `bv --robot-insights | jq '.Regressions'` lists a new entry.

If the apparent regression is *only* on a microbench with `cv_pct > 5`, route through [cv-pct-flake.md](cv-pct-flake.md) FIRST. Do not enter this recipe until cv_pct is bounded.

## Operator Pipeline

```
⚠ ESCALATE-TO-FRESH-REPRO   confirm the regression is real, not a flake or wrong-host artifact
↓
🗄 LEDGER-RETIRE (mine)     has this regression been seen and closed before?
↓
⬡ INSTRUMENT-HOT-PATH      what changed in HotPathProfileSnapshot since the last clean run?
↓
⤴ ATTRIBUTE-TO-MT8         what's the new top frame ≥0.1% self-time?
↓
⟁ TRIANGULATE-PROFILE     do flamegraph + samply + dhat + strace agree on the attribution?
↓
🧪 EXPERIMENT-DESIGN       file the hypothesis in PERF_HYPOTHESIS_LEDGER.md
↓
⊕ ISOMORPHIC-REWRITE      enumerate ≥2 behavior-preserving fixes; score on Impact×Confidence/Effort
↓
⚖ RATCHET-LOWER-BOUND     does the chosen rewrite raise the conformal lower bound back?
↓
🪟 FRESH-EYES              three reviewers, two consecutive clean rounds before close
```

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path to gauntlet workspace>
PORT=<absolute path to subject port>
WORKLOAD=<bench/category that regressed; e.g., mt-mvcc-bench>

# 1. Confirm regression is real (not a flake): rerun bench against same git SHA + same host
cd "$PORT"
"$WORKSPACE/scripts/run-bench-matrix.sh" "$PORT" "$WORKSPACE" --bench "$WORKLOAD"
# Compare against the .bench-history baseline:
diff <(jq '.summary' "$WORKSPACE/.bench-history/$WORKLOAD.latest.json") \
     <(jq '.summary' "$WORKSPACE/artifacts/bench/$WORKLOAD/${WORKLOAD}_report.json")

# 2. Ledger mine: has the same regression been seen + closed before?
"$WORKSPACE/scripts/mine-ledger.sh" "$WORKSPACE" --terms "$WORKLOAD"
"$WORKSPACE/scripts/mine-cass-cross-machine.sh" "$WORKSPACE" --term "$WORKLOAD" --window 60d

# 3. Capture profile under the regressed workload
"$WORKSPACE/scripts/run-narrow-benches.sh" "$PORT" "$WORKSPACE" --benches "$WORKLOAD"
# Dispatch the mt8-attribution-profiler subagent for the top-10 frames ≥0.1%

# 4. File the hypothesis BEFORE attempting a fix
cat >> "$WORKSPACE/PERF_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — perf-regression-$WORKLOAD — investigating
- target_workload: $WORKLOAD
- baseline_sha: $(git -C $PORT log -1 --format=%H .bench-history/$WORKLOAD.latest.json)
- regressed_sha: $(git -C $PORT rev-parse HEAD)
- hypothesis: <one-sentence root-cause guess>
- expected_signal: <which counter / which frame / which gate>
- falsifiability: <what would prove the hypothesis WRONG>
- one_line_invocation: $WORKSPACE/scripts/run-narrow-benches.sh $PORT $WORKSPACE --benches $WORKLOAD
- results_inline: <fill after experiment>
EOF

# 5. Create the bead
br create \
  --title "perf-regression-$WORKLOAD" \
  --priority 1 \
  --type investigation \
  --labels "pillar:perf,lane:cc_2,recipe:perf-regression-triage"

# 6. Once a rewrite candidate is picked, re-bench + ratchet
"$WORKSPACE/scripts/run-bench-matrix.sh" "$PORT" "$WORKSPACE" --bench "$WORKLOAD"
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/apply-ratchet.sh" "$WORKSPACE"

# 7. Fresh-eyes before close
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "perf-regression-$WORKLOAD"
```

## Beads to claim (or create)

- `perf-regression-<workload>` (this recipe creates it).
- Dependency: `pattern:160-MT8-ATTRIBUTION` — must be applied (named frame, quoted citation).
- Dependency: `pattern:155-BENCH-HISTORY-RATCHET` — `.bench-history/<workload>.latest.json` updated atomically with source change.
- Dependency (test): `test-perf-regression-<workload>` — a regression test that pins the kept baseline.
- Dependency (bench): `bench-<workload>-baseline-pinned` — confirms the new baseline is stable across 5 reruns with `cv_pct < 5`.
- Dependency (doc): `doc-perf-regression-<workload>-resolution` — short note in `docs/progress/perf-resolutions/`.

The bead graph validator (`scripts/bead-graph-validator.sh`) blocks close until all three dep classes are linked.

## Exit Criteria

- [ ] Regression is confirmed on rerun (not a flake). `cv_pct < 5` on the bench.
- [ ] Ledger mine ran; either no prior closure OR the prior closure's retry-condition predicate was satisfied (record which).
- [ ] Top-10 MT8 frames captured under steady-state; at least one frame ≥0.1% named as the proximate cause.
- [ ] Triangulation: flamegraph + at least one of (samply | dhat | strace) agree on the top frame.
- [ ] Hypothesis ledger entry filed with all six fields (hypothesis / repro / expected-signal / falsifiability / one-line-invocation / results-inline).
- [ ] ≥2 isomorphic rewrites enumerated; chosen one passes the 5-line proof template (see [../remediation/ISOMORPHISM-PROOF-TEMPLATE.md](../remediation/ISOMORPHISM-PROOF-TEMPLATE.md)).
- [ ] `apply-ratchet.sh` emits `Allow` after the fix; conformal lower bound is at or above the pre-regression floor.
- [ ] `.bench-history/<workload>.latest.json` committed in the same commit as the source change.
- [ ] Three fresh-eyes reviewers ran; two consecutive clean rounds.
- [ ] If the fix was rejected as "not worth it", a negative-ledger entry with one of the 8 retry-condition predicates was filed.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| "It's probably just noise." | Without `cv_pct < 5%` evidence on N≥5 reruns, this is a guess. Run the bench again before claiming. |
| "I'll fix it in the next refactor." | The hypothesis ledger entry must be written NOW, even if the fix is deferred. Deferred ≠ undocumented. |
| "I'll skip the ledger grep this once." | The cass-miner subagent runs first. Period. The AGENTS.md mandate is non-optional. |
| Optimizing before triangulation. | If profilers disagree, the disagreement IS the finding. Optimizing into disagreement makes the noise worse, not better. |
| Bumping a counter under 0.1% self-time. | Micro-lever trap. The change you're tuning is below the bench's noise floor; the "win" is sampling artifact. |
| Bench result on different git SHA than source change. | Run focused + broad benches from the same `target/` build, same machine, same minute. |
| `.bench-history` not committed with the source change. | "Pass-over-pass gate is a file." If the file isn't committed, the next agent has no baseline. |
| Closing the bead without the documentation dep. | Six months later, the next agent re-derives the regression because nobody wrote down what happened. |
| Quoting the point estimate. | Release decisions use the conformal LOWER bound. Point estimate is for intermediate dashboards only. |

## Cross-references

- [../patterns/155-BENCH-HISTORY-RATCHET.md](../patterns/155-BENCH-HISTORY-RATCHET.md) — the `.bench-history` file is the gate.
- [../patterns/160-MT8-ATTRIBUTION.md](../patterns/160-MT8-ATTRIBUTION.md) — named-frame requirement.
- [../patterns/170-ROBUST-REGRESSION-DETECTOR.md](../patterns/170-ROBUST-REGRESSION-DETECTOR.md) — median + MAD detector.
- [../patterns/165-PASS-OVER-PASS-GATE.md](../patterns/165-PASS-OVER-PASS-GATE.md) — same-run-window discipline.
- [../patterns/150-PROFILE-FIRST-CARD.md](../patterns/150-PROFILE-FIRST-CARD.md) — profile before you touch.
- [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) — the keep-gate vocabulary.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — lower-bound math.
- [../methodology/RETRY-CONDITION-VOCABULARY.md](../methodology/RETRY-CONDITION-VOCABULARY.md) — the 8 predicate templates.
- [../methodology/CASS-MINING.md](../methodology/CASS-MINING.md) — the 60-day cross-machine recipe.
- Related motions: [ratchet-block.md](ratchet-block.md), [mt8-attribution-flat.md](mt8-attribution-flat.md), [cv-pct-flake.md](cv-pct-flake.md), [cross-pillar-regression.md](cross-pillar-regression.md).
