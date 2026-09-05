# TROUBLESHOOTING — Common Symptoms and Fixes

> Per-symptom: **Symptom** observed → **Diagnosis** root causes → **Remediation** specific commands and references. When in doubt, re-read [methodology/ANTI-PATTERNS.md](methodology/ANTI-PATTERNS.md) first — most "weird" outcomes trace to a violated rule there.

---

## Symptom: Flaky bench (cv_pct > 5%)

**Symptom.** A microbench reports `cv_pct = 7.3` (or worse) across iterations. The "win" is inside the noise band.

**Diagnosis.**
1. **Workload too short.** TARGET_DURATION=5s is the design; if a single iteration finishes in <50 ms, MIN_ITERS=3 produces too few samples for stable median.
2. **Cold-start contamination.** WARMUP_ITERS=2 is the minimum; some workloads need more warmup to populate the page cache / JIT / branch predictor.
3. **Host noise.** Background processes, CPU frequency scaling, NUMA imbalance, hyperthreaded sibling interference.
4. **Population inside the timed window** (anti-pattern A23). Setup cost dominates the measurement.
5. **GC / allocator churn.** Heap fragmentation can make iteration-N slower than iteration-1.

**Remediation.**

```bash
# 1. Rerun the specific bench through the gauntlet wrapper
./scripts/run-bench-matrix.sh <target> <workspace> --bench <name>
# If this workload needs different iteration constants, change the bench harness
# or pass project-specific args to the underlying bench binary; the wrapper does
# not expose min/max-iteration flags.

# 2. Verify CPU pinning and frequency governor
sudo cpupower frequency-set -g performance
taskset -c 4-11 ./target/release-perf/<bench>   # pin to one NUMA node

# 3. Drop caches between iterations (only if your workload's design ALLOWS this)
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches

# 4. Audit measure_with_teardown() usage — teardown MUST be outside start.elapsed()
rg -nP 'start\.elapsed\(\)' --type rust crates/<project>-e2e/src/bin/

# 5. Repeat the bench; if cv_pct is still >5%, escalate to narrow attribution:
./scripts/run-narrow-benches.sh <target> <workspace> --benches <name>
# Then median + MAD detector reads from the narrow-bench artifact lane.
```

**Reference:** [tooling/BENCH-TOOLCHAIN.md § cv_pct discipline](tooling/BENCH-TOOLCHAIN.md), MINING-3 §1.2, anti-pattern A28.

If the workload genuinely cannot get below cv_pct=5%, document in the ledger as `noise-band-claim` (anti-pattern A10) with retry-condition: *"Retry only if this workload class exhibits measurable <property> below <threshold>"* (RETRY-CONDITION-VOCABULARY form 7).

---

## Symptom: Oracle preflight doctor returns red

**Symptom.** `./scripts/oracle-preflight-doctor.sh` exits non-zero; report shows `aggregate_outcome: "red"` and `certifying: false`.

**Diagnosis.** The doctor checks (MINING-2 §13):
1. C SQLite oracle binary exists and is executable.
2. Expected version matches the contract (e.g., `3.52.0`).
3. Subject identity is `"frankensqlite"` (or sibling-equivalent).
4. Reference identity is `"csqlite-oracle"` (or sibling-equivalent).
5. Fixture corpus cardinality floors met.
6. Fixture manifest mtime is fresh (not older than 7 days).
7. Manifest SHA-256 matches the recorded hash.

Common failures: (a) reference binary path drifted (rebuilt elsewhere); (b) `pkg-config` resolved a wrong libsqlite3 version; (c) someone edited a fixture without updating the manifest hash; (d) reference upgraded but `docs/contracts/<reference>_version_contract.toml` not updated.

**Remediation.**

```bash
# 1. Read the doctor's first_failure field
jq .first_failure_diagnosis reports/oracle-preflight-doctor.json

# 2. Verify reference binary
which sqlite3
sqlite3 --version
# Should match docs/contracts/sqlite_version_contract.toml [version] field

# 3. Verify identity strings (FrankenSQLite example)
rg -n 'SUBJECT_IDENTITY_LABEL|REFERENCE_IDENTITY_LABEL' crates/fsqlite-harness/src/differential_v2.rs
# Should be "frankensqlite" and "csqlite-oracle" respectively

# 4. Recompute fixture manifest hash
./scripts/compute-fixture-manifest-sha.sh > artifacts/fixture_manifest.sha256
diff artifacts/fixture_manifest.sha256 docs/contracts/fixture_manifest.expected.sha256

# 5. If reference version legitimately bumped, update the contract
$EDITOR docs/contracts/sqlite_version_contract.toml
git commit -m "contract: bump reference version to <new>"

# 6. Rerun
./scripts/oracle-preflight-doctor.sh <target> --workspace <workspace>
```

**Reference:** [tooling/ORACLE-TOOLCHAIN.md § oracle preflight doctor](tooling/ORACLE-TOOLCHAIN.md), MINING-2 §13.

Never proceed to Phase 6 conformance work with a red preflight — the entire pillar's evidence is invalid until green.

---

## Symptom: Reservation conflict on `tool://comprehensive-bench`

**Symptom.** Agent A tries to reserve `tool://comprehensive-bench` (60 minutes); MCP Agent Mail returns `RESERVATION_CONFLICT`. Agent B is holding the lock for 47 more minutes.

**Diagnosis.**
1. **Honest conflict** — B is actively running the bench; serialize.
2. **Stale lock** — B died/crashed without releasing; need force-release.
3. **Reservation too coarse** — B reserved `tool://comprehensive-bench` for the entire matrix; A wants only a narrow bench (mt-mvcc-bench).

**Remediation.**

```bash
# 1. Inspect the current reservation
ntm robot mail reservations --resource 'tool://comprehensive-bench'

# 2. If B is alive (check ntm robot status), agent A queues:
ntm robot mail send --thread gauntlet-<run>-phase5-fanout \
   --body "queued for tool://comprehensive-bench; will retry at <ETA+5min>"

# 3. If B is dead (no recent ticks), force-release with audit log
ntm robot mail reservations release \
   --resource 'tool://comprehensive-bench' \
   --reason "B-agent crashed without release; verified via ntm robot status"

# 4. Better long-term: split the reservation
# - tool://comprehensive-bench[mt-mvcc-bench]  (narrow)
# - tool://comprehensive-bench[mt-oltp-bench]
# - tool://comprehensive-bench[perf-update-delete]
# Document in orchestration/ORCHESTRATION.md
```

**Reference:** [orchestration/ORCHESTRATION.md § reservation conventions](orchestration/ORCHESTRATION.md), anti-pattern A31 (communication purgatory).

---

## Symptom: `.bench-history/*.latest.json` missing or malformed

**Symptom.** `./scripts/apply-ratchet.sh` reports `previous file missing or fails schema validation`.

**Diagnosis.**
1. **First run on this branch** — no baseline yet; legitimate.
2. **Baseline deleted accidentally** (`git rm` in a rebase).
3. **Schema drift** — `schema_version` in the file is older than the current bench writer emits.
4. **JSON corruption** (truncated write; interrupted commit).

**Remediation.**

```bash
# 1. Diagnose
jq . .bench-history/comprehensive_bench.latest.json | head -5
# If empty or "parse error": corrupt
# If schema_version != current: drift

# 2. Recover from git
git log --oneline -- .bench-history/comprehensive_bench.latest.json
git show <last-good-sha>:.bench-history/comprehensive_bench.latest.json > .bench-history/comprehensive_bench.latest.json

# 3. If schema drift, regenerate from a fresh bench run on the SAME git state as the previous baseline
git stash  # if needed
git checkout <previous-baseline-sha>
./scripts/run-bench-matrix.sh <target> <workspace>
cp <workspace>/.bench-history/comprehensive_bench.latest.json .bench-history/comprehensive_bench.latest.json
git checkout -  # back to your branch
git stash pop  # if you stashed
git add .bench-history/comprehensive_bench.latest.json
git commit -m "bench: regenerate baseline on current schema"

# 4. If first-run / legitimate-absence: seed it
./scripts/run-bench-matrix.sh <target> <workspace>
cp <workspace>/.bench-history/comprehensive_bench.latest.json .bench-history/comprehensive_bench.latest.json
git add . && git commit -m "bench: initial baseline"
```

**Reference:** MINING-3 §4 ("Pass-over-pass gate is a *file*. `.bench-history/*.latest.json` is committed.").

---

## Symptom: Ratchet quarantine vs waiver decision

**Symptom.** `./scripts/apply-ratchet.sh` returns `Quarantine` — the change is on the boundary; not a clear `Allow` or `Block`. Operator needs to decide: quarantine (block the merge) or waiver (allow with structured exception)?

**Diagnosis.** Quarantine is the default conservative choice. Waivers are structured exceptions: dated, severity-bounded, with an explicit retry condition.

**Decision tree:**

| Condition | Decision |
|---|---|
| The regression is in a workload **not on the frontier** (low business value) AND a waiver is requested with a dated retry condition | Waiver |
| The regression is in a workload **on the frontier** | Quarantine; do not waiver |
| The regression is below noise band (`delta_pct ≤ cv_pct`) AND `cv_pct` legitimate (matches historical) | Allow (within noise — but log ledger entry) |
| The regression is a **side-effect of a correctness fix** AND the fix is justified | Waiver with `correctness-priority` reason |
| The change touches a fused-design path (anti-pattern A14) | Block (architectural mismatch) |
| Unclear → ask the maintainer; never silently waive | Quarantine + open beads issue |

**Remediation.**

```bash
# 1. Read the ratchet report
jq . reports/ratchet/decision.json

# 2. Identify which gate flipped
jq '.gate_decisions[] | select(.decision != "Allow")' reports/ratchet/decision.json

# 3. To waiver, write the structured entry
cat > docs/progress/waivers/<bead_id>-waiver.toml <<EOF
[waiver]
bead_id = "<bead_id>"
date = "$(date -u +%Y-%m-%d)"
severity_cap = "warning"          # never "critical"
expires = "$(date -u -d '+30 days' +%Y-%m-%d)"
gate = "p90_max_regression_pct"
delta = "-12%"
threshold = "-15%"
reason = "Correctness fix for bd-XXXX requires this; tracked at bd-YYYY for follow-up perf work."
retry_condition = "Retry as standalone perf bead when bd-YYYY merges."
EOF
git add docs/progress/waivers/ && git commit -m "waiver: $bead_id"

# 4. Verify the waiver registers against the current score
./scripts/apply-ratchet.sh <workspace> --score <workspace>/reports/parity_score.json --waiver "$bead_id"
```

**Reference:** [methodology/CONFORMAL-RATCHET.md § waiver discipline](methodology/CONFORMAL-RATCHET.md), MINING-3 §9 ("Waivers: structured, dated, severity-bounded. No invisible exceptions.").

---

## Symptom: First-failure explainer not populated

**Symptom.** CI failure summary shows the test name and a stack trace but no `first_divergence` byte-offset, no replay command, no remediation playbook.

**Diagnosis.**
1. The bench/test didn't emit a `FailureBundle`.
2. `FailureBundle` was emitted but the `/failure/first_divergence` jsonptr is empty.
3. The CI summary parser is looking at the wrong field name.

**Remediation.**

```bash
# 1. Verify FailureBundle was emitted
find target/test-artifacts -name "failure_bundle*.json" -mtime -1 | head
jq . target/test-artifacts/<bundle>.json | head -50

# 2. If bundle exists but first_divergence is empty:
# The test framework didn't call .with_first_divergence(...) at the divergence point.
# Audit the test:
rg -nP 'FailureBundle::new|\.with_first_divergence' crates/<project>-harness/src/

# 3. If bundle is missing entirely:
# Test framework crashed before emitting. Add panic-hook to dump partial bundle.
# Quote (Q-012): "A partial bundle with provenance is more valuable than no bundle."

# 4. Re-run the failing test with --nocapture and bundle-dump
RUST_BACKTRACE=full cargo test -p <crate> --test <test_name> -- --nocapture
ls target/test-artifacts/failure_bundle*.json
```

**Reference:** [tooling/ORACLE-TOOLCHAIN.md § FailureBundle](tooling/ORACLE-TOOLCHAIN.md), MINING-2 §15, MINING-2 §17.

---

## Symptom: E-process unable to reject (insufficient evidence)

**Symptom.** Invariant monitor runs for hours; `E_global(t)` never crosses `1/α`. Suspected violation persists.

**Diagnosis.**
1. **Insufficient samples** — Ville's inequality is anytime-valid but not anytime-powerful; small effect sizes need many samples.
2. **Calibration wrong** — using hardware-enforced parameters (`p₀=1e-9, α=1e-6`) for a software-enforced invariant (which needs `p₀=1e-6, α=0.001`).
3. **Wrong invariant** — the violation is happening but the formulated `MvccInvariant::SnapshotStability` check isn't catching it.
4. **The invariant actually holds** — agent's prior was wrong.

**Remediation.**

```bash
# 1. Inspect the e-process state
jq .invariants[].current_e_value reports/eprocess/run-*.json
# E_value should drift toward 1/α over time if violation real

# 2. Confirm calibration matches invariant class
rg -nP 'p_0|lambda|alpha' crates/<project>-harness/src/eprocess.rs
# Hardware (CAS-enforced INV-1, INV-2, INV-7): p₀=1e-9, λ=0.999, α=1e-6
# Software (INV-3..INV-6 + SsiFalsePositiveRate): p₀=1e-6, λ=0.9, α=0.001

# 3. Add more samples — run the workload longer
./scripts/run-soak-campaign.sh <target> <workspace> --campaigns eprocess --invariant <invariant> --duration 24h

# 4. If after 24h E_value still flat: invariant likely holds.
#    Either: (a) close the bead "no violation observed in 24h soak"
#    Or:    (b) refine the invariant to be more specific

# 5. If E_value is climbing but slow: extend soak; document in ledger
echo "E_value 0.42 → 0.87 over 24h; needs 72h soak to cross 1e3 threshold" \
   >> docs/progress/eprocess-investigations.md
```

**Reference:** [methodology/KERNEL.md § e-processes](methodology/KERNEL.md), MINING-2 §10, quote [Q-019].

---

## Symptom: BOCPD regime stuck `ShiftDetected`

**Symptom.** Replay harness reports `Regime::ShiftDetected` for multiple consecutive runs; never settles back to `Stable | Improving | Regressing`.

**Diagnosis.**
1. **True instability** — actual regime is non-stationary; system is genuinely shifting.
2. **Hazard rate too low** — `H = 1/250` may be wrong for fast-shifting workloads.
3. **Predictive model mismatch** — Normal-Gamma for throughput is right; but a workload with bimodal distribution breaks the model.
4. **Outliers in the run prefix** — first samples skew the posterior.

**Remediation.**

```bash
# 1. Inspect the window_regimes vector
jq .window_regimes reports/replay/run-*.json
# A series like [Stable, Stable, ShiftDetected, ShiftDetected, ShiftDetected]
# means the shift is real; an oscillation like [Stable, Shift, Stable, Shift]
# means hazard rate or model is misspecified.

# 2. Try a different hazard rate in the project replay harness
# (run-bench-matrix.sh does not expose BOCPD model parameters).
cargo test --test replay_harness -- --nocapture bocpd_hazard_0_01

# 3. Switch predictive model if bimodal
# Edit replay_harness.rs to use a mixture model or escalate to manual inspection.

# 4. If genuine instability: investigate the underlying cause
# - GC pause? Thermal throttle? Container CPU limit hit?
# - cass mine: ./scripts/mine-cass-cross-machine.sh <workspace> --terms "regime,shift,unstable,bimodal"

# 5. Document in ledger if no clear cause found, with retry condition
```

**Reference:** [tooling/BENCH-TOOLCHAIN.md § BOCPD](tooling/BENCH-TOOLCHAIN.md), MINING-2 §7.

---

## Symptom: cass index stale or `cass health` red

**Symptom.** `cass health` reports stale index; `timeout 30s cass search "<term>" --robot --mode lexical --timeout 30000` returns 0 hits for terms you know exist.

**Diagnosis.**
1. **Index corruption** (interrupted write; disk full mid-update).
2. **Schema migration pending** (cass binary upgraded; old index in incompatible format).
3. **Permission issue** (cass can't read session logs).
4. **Cross-machine sync stale** — local cass is fine, but `mine-cass-cross-machine.sh` polls hosts that haven't synced recently.

**Remediation.**

```bash
# 1. Local health
cass health --json | jq

# 2. Rebuild local index
cass reindex --full --verbose

# 3. If reindex fails: do not wipe from an automated gauntlet session.
#    Record a blocker and ask the operator whether they want cass's destructive
#    reset command run manually under the local repo's destructive-command policy.
WORKSPACE="${WORKSPACE:?set WORKSPACE to the gauntlet workspace path}"
printf '%s\n' "cass reindex failed; operator decision required" \
  >> "$WORKSPACE/phase0_cass_index_blockers.md"

# 4. Cross-machine: poll each host explicitly
for h in css csd ts1 ts2; do
  ssh $h 'cass health --json' | jq ".hostname = \"$h\""
done

# 5. If a remote host is red: SSH in and rebuild on that host
ssh css 'cass reindex --full'

# 6. Re-run mining
./scripts/mine-cass-cross-machine.sh <workspace>
```

**Reference:** `/cass` skill (parent SKILL.md proprietary-skills list).

If a perf bead's pre-flight blocks on cass unavailability: **record a blocker entry** rather than silently skipping (per the AGENTS.md mandate paragraph, quote [Q-002]).

---

## Symptom: `convergence-tracker.sh` exits non-zero past round 15

**Symptom.** Run is at round 15; convergence-tracker reports "needs 2 consecutive clean rounds" or "open hypotheses remain".

**Diagnosis.**
1. **Genuine non-convergence** — new findings keep arriving each round; the gauntlet is doing its job.
2. **Findings are duplicates** — same root cause keeps surfacing because the dedup logic isn't catching it.
3. **Hypothesis status never updated** — entries linger in `NEEDS_REFINEMENT` because no one closed them.
4. **Round bookkeeping broken** — the per-round findings files aren't being written or counted.

**Remediation.**

```bash
# 1. Inspect what convergence-tracker is counting
WORKSPACE=<workspace>
./scripts/convergence-tracker.sh "$WORKSPACE" || true
jq . "$WORKSPACE/reports/convergence_tracker.json"

# 2. Dedup new findings against prior rounds
for r in $(seq 1 15); do
  jq -c '.findings[]?' "$WORKSPACE/round_$r/findings.jsonl" 2>/dev/null || true
done | sort -u > "$WORKSPACE/all-findings-dedup.jsonl"
wc -l "$WORKSPACE/all-findings-dedup.jsonl"   # actual unique count

# 3. Spot-check NEEDS_REFINEMENT entries
rg 'NEEDS_REFINEMENT' "$WORKSPACE"/*HYPOTHESIS_LEDGER.md
# Each must have an owner; convert stale ones to NO_EVIDENCE or NEW_HYPOTHESIS_SPAWNED

# 4. Confirm Phase-14 fresh-eyes reviewers ran and reported clean
ls "$WORKSPACE"/round_15/fresh-eyes-{A,B,C}-findings.md
# Each must have <3 high-severity findings

# 5. If genuinely non-convergent past 20 rounds: escalate
# This is a sign that either (a) the project is more divergent than expected
# (run more rounds) or (b) the gauntlet's findings detection is too noisy
# (tighten the new-finding definition).

# 6. Convergence math
# clean_last_two must be true: the last two rounds each had <3 new findings AND
# every entry in {GAUNTLET_EXPERIMENT_DESIGNS, PERF/CONFORMANCE/SURFACE_HYPOTHESIS_LEDGERs}
# must be in {CONFIRMED_GAP, NO_EVIDENCE, NEEDS_REFINEMENT-with-owner, NEW_HYPOTHESIS_SPAWNED}
```

**Reference:** [methodology/CONVERGENCE.md](methodology/CONVERGENCE.md). Minimum is 10 rounds (parent SKILL.md Convergence Rule); 20+ rounds for swarm/squad runs is not unusual.

---

## Symptom: rch worker pool exhausted

**Symptom.** `rch` reports "all workers busy" or "[RCH] local" fallback triggers — long-running builds fall back to local machine.

**Diagnosis.**
1. **Worker pool actually full** — too many concurrent campaigns dispatched.
2. **Stale jobs holding workers** — a previous campaign didn't release its worker.
3. **Worker health degraded** — a worker is in slow/sad state but not removed from pool.
4. **Disk pressure on workers** — `sbh` daemon constrained the worker.

**Remediation.**

```bash
# 1. Check pool status
rch status --json | jq

# 2. Identify stale jobs
rch jobs --running --json | jq '.[] | {id, age_minutes, worker, command}'
# Kill jobs older than expected wall time
rch kill <job_id>

# 3. Mark unhealthy workers
rch worker health --json | jq '.[] | select(.health != "green")'
rch worker drain <hostname> --reason "slow disk"

# 4. Disk pressure on a worker
ssh <worker> 'sbh status'
# If high: ssh <worker> 'sbh cleanup --aggressive'

# 5. Reduce gauntlet's rch demand temporarily
./scripts/run-soak-campaign.sh <target> <workspace> --duration 4h --campaigns bocpd --no-rch

# 6. If pool is genuinely too small for the workload: provision more
# (consult standard fleet setup notes)
```

**Reference:** `/rch` skill in parent SKILL.md proprietary-skills list, [orchestration/ORCHESTRATION.md § rch offload heuristic](orchestration/ORCHESTRATION.md).

---

## Symptom: "Other agent edited my file mid-run"

**Symptom.** Agent A opens a file, makes changes; on save, `git diff` shows unfamiliar changes mixed with A's edits. Another agent B was concurrently editing.

**Diagnosis.** Lane collision (anti-pattern A32). Cc_N lane convention was either not followed or the file is in a shared region.

**Remediation.** **DO NOT REVERT B's CHANGES.** Anti-pattern A32: "tidying others' edits → destroys parallel work."

```bash
# 1. Inspect the unfamiliar changes
git diff <file>
# Identify what's yours vs theirs

# 2. Treat B's changes as your own
# Stage them; reconcile mentally; preserve their intent

# 3. Reach out via Agent Mail thread
ntm robot mail send --thread gauntlet-<run>-phase<N>-coordination \
   --body "Saw your edit to <file>; reconciling with my Phase-<N> work. Will preserve your <X> change; question about <Y>."

# 4. If reconciliation is impossible (genuine semantic conflict):
# - Branch your work
# - Note in coordination thread
# - Let owner resolve

# 5. Long-term: improve lane assignment
# Update orchestration/ORCHESTRATION.md so this file region is single-owner
```

**Reference:** anti-pattern A32; [orchestration/ORCHESTRATION.md § lane convention](orchestration/ORCHESTRATION.md).

---

## Symptom: "Phase 6 oracle test fails on a behavior that should pass"

**Symptom.** Differential test reports `MISMATCH` for a query that you're confident both engines handle correctly.

**Diagnosis.**
1. **Whitespace / normalization mismatch** — one engine wraps strings in single quotes, other doesn't.
2. **Float precision** — `0.1 + 0.2 == 0.30000000000000004` vs `0.3` rendering difference.
3. **NULL vs empty string** — one engine renders as `NULL`, other as `''`.
4. **NaN / Inf rendering** — `nan` vs `NaN` vs `NULL`.
5. **Type affinity** — one engine returns `INTEGER`, other returns `REAL` for the same expression.
6. **Order non-determinism** — query without ORDER BY; engines return same multiset in different orders.

**Remediation.**

```bash
# 1. Inspect the MismatchClassification
jq '.classification' reports/oracle/<run>/mismatch-<n>.json
# {OrderDependentDifference, TypeAffinityDifference, NullHandlingDifference,
#  FloatingPointDifference{max_epsilon_str}, FalsePositive{reason}, TrueDivergence{description}}

# 2. If it's classified as TrueDivergence — that's a real bug; open beads issue
# 3. If it's one of the 5 known classes:
#    OrderDependentDifference: add ORDER BY OR widen equivalence to MultisetEquivalence
#    TypeAffinityDifference: review which engine is correct per the reference doc
#    NullHandlingDifference: review NULL semantics; often a real bug masquerading
#    FloatingPointDifference: bump ULP tolerance OR investigate why the gap widened
#    FalsePositive: document the reason; the classifier needs to mark this case

# 4. Run NormalizedValue::normalize_value() on both sides manually
rg -nP 'normalize_value' crates/<project>-harness/src/oracle.rs
# Verify the function handles your case

# 5. If normalization needs to change: update oracle.rs::normalize_value(),
# add a regression test, update fixture manifest hash
```

**Reference:** [tooling/ORACLE-TOOLCHAIN.md § MismatchClassification](tooling/ORACLE-TOOLCHAIN.md), MINING-2 §1, MINING-2 §4.

---

## Symptom: `FeatureUniverse` loader rejects with `sum-weights != 1.0`

**Symptom.** Parity-score computation fails at startup: `loader rejected: category 'ReadSingle' has sum-weights 1.0042`.

**Diagnosis.** Weight invariant violated: per the FeatureUniverse design (MINING-3 §11), `sum(weights) == 1.0 per category` is a load-bearing invariant enforced by the loader. Floating-point arithmetic on hand-written weights tends to drift.

**Remediation.**

```bash
# 1. Inspect the offending category
jq '.categories[] | select(.id == "ReadSingle")' parity_features.toml
# Sum the weights
jq '.categories[] | select(.id == "ReadSingle") | [.features[].weight] | add' parity_features.toml

# 2. Either adjust one weight to compensate, OR normalize all weights post-loading
# Option A: hand-fix
$EDITOR parity_features.toml
# Make the smallest weight absorb the delta

# Option B: have the loader normalize (only if you accept loss of "stable weights" property)
# Edit parity_taxonomy.rs to do: weight_i := weight_i / sum(weights)
# But this defeats the auditability of the contract — prefer Option A

# 3. Re-run truncate_score check to ensure deterministic output
./scripts/compute-parity-score.sh <workspace>
```

**Reference:** MINING-3 §11, [taxonomy/FEATURE-UNIVERSE.md](taxonomy/FEATURE-UNIVERSE.md).

---

## Symptom: "All-three-pillar simultaneous regression"

**Symptom.** A single bead lands; perf regresses by −4%, conformance pass-rate drops by 1.2pp, surface coverage falls by 0.8pp. Catastrophic.

**Diagnosis.** This is the worst-case outcome of `change-behavior-while-we're-here` (anti-pattern A4) or `architectural-change-dressed-as-micro-optimization` (A13). The bead bundled too many concerns; one change broke multiple invariants simultaneously.

**Remediation.**

```bash
# 1. Immediately revert
git revert <bead_commit>
git push  # restore baseline

# 2. Post-mortem: which one-lever was actually the cause?
# Use git bisect against the within-bead commits
PORT=$(pwd)
WORKSPACE="${PORT}__gauntlet_workspace"
git bisect start HEAD~10 <bead_commit>
git bisect run "$WORKSPACE/scripts/gauntlet.sh" "$PORT" "$WORKSPACE" --mode quick-smoke

# 3. Split the bead into one-lever sub-beads
# Each sub-bead must have:
# - one-lever scope
# - own proof pack
# - own ledger entry (kept or rejected)

# 4. Ledger the failure
cat >> docs/progress/perf-negative-results.md <<EOF
## $(date +%Y-%m-%d) bd-XXXX REVERTED — three-pillar regression
**Status:** pulled
**Scratch worktree:** /data/tmp/<project>-bd-XXXX-failed
**Cause:** bead bundled <change A> + <change B> + <change C>; all three landed together; oracle suite caught conformance regression but perf+surface also regressed.
**Retry condition:** Reconsider as 3 separate one-lever beads; each must have its own proof pack.
EOF
```

**Reference:** anti-pattern A2 (multi-change), A4 (behavior change while we're here), A13 (architectural dressed as micro-opt).

---

## Symptom: Failure bundle missing `/failure/first_divergence`

**Symptom.** FailureBundle is emitted but the `first_divergence_jsonptr` field is empty or points at nothing.

**Diagnosis.** The test harness emitted the bundle on a panic / late-stage failure, but never recorded the actual divergence point. Common when: (a) the divergence is detected post-hoc by a verifier; (b) the test uses `assert!(...)` instead of the structured `record_divergence(jsonptr, ...)` call; (c) the bundle is built from a templated "failure path" that doesn't track the first divergence.

**Remediation.**

```bash
# 1. Audit divergence-recording sites
rg -nP 'record_divergence|first_divergence' crates/<project>-harness/src/
rg -nP 'assert!|assert_eq!' crates/<project>-e2e/tests/*_oracle_e2e.rs

# 2. Convert raw asserts to structured calls
# Before:
#     assert_eq!(frank_rows, csql_rows, "MISMATCH at {query}");
# After:
#     if frank_rows != csql_rows {
#         failure_bundle
#             .record_divergence("/queries/<idx>/result/<row>/<col>", frank_rows, csql_rows)
#             .expect("record divergence");
#     }

# 3. Re-run; verify
./scripts/run-conformance-suite.sh <target> <workspace>
jq .first_divergence_jsonptr target/test-artifacts/failure_bundle*.json | head
```

**Reference:** MINING-2 §15, MINING-2 §17, quote [Q-013].

---

## Symptom: `selections=` counts diverge between runs

**Symptom.** Two runs that should be byte-identical (same seed, same workload, same git state) produce different `selections=` counter values.

**Diagnosis.** Non-determinism in the workload. Common sources: (a) HashMap iteration order; (b) thread scheduling for parallel scenarios; (c) RNG seed not propagated; (d) wall-clock-dependent code path; (e) filesystem mtime read into a hash; (f) PID / process-id leaked into a key.

**Remediation.**

```bash
# 1. Bisect what differs between the two runs
diff <(jq .selections reports/run-A.json) <(jq .selections reports/run-B.json)

# 2. Identify the diverging scenario
# Each scenario's selections= counter is independent; the one that differs is the suspect.

# 3. Audit that scenario for non-determinism
rg -nP 'HashMap|rand::|SystemTime::now|process::id|env::var' \
   crates/<project>-e2e/src/bin/comprehensive_bench.rs

# 4. Common fixes:
# - HashMap → BTreeMap for ordered iteration
# - rand::random() → seeded ChaCha8Rng with the SeedContract derivation
# - SystemTime::now() → injected clock
# - env::var → moved to setup (outside the hot loop)

# 5. Re-run; verify counters match byte-for-byte
./scripts/run-bench-matrix.sh <target> <workspace>
cp <workspace>/artifacts/bench/comprehensive_bench/comprehensive_bench_report.json reports/run-A2.json
./scripts/run-bench-matrix.sh <target> <workspace>
cp <workspace>/artifacts/bench/comprehensive_bench/comprehensive_bench_report.json reports/run-B2.json
diff <(jq .selections reports/run-A2.json) <(jq .selections reports/run-B2.json)
# Should be empty
```

**Reference:** [methodology/KEEP-GATE-RULES.md § selections= byte-identical](methodology/KEEP-GATE-RULES.md), MINING-2 §4 (SeedContract).

---

## Symptom: `concurrent_mode_default_guard.txt` absent from artifact lane

**Symptom.** A perf claim is being made for a "concurrent MVCC win"; the artifact lane lacks `concurrent_mode_default_guard.txt`. Suspect the win was measured with concurrent mode silently off.

**Diagnosis.** Anti-pattern A27 (concurrent mode silently off). The proof file exists precisely because of the Feb 2026 incident where an agent silently disabled concurrent mode; pass-over-pass didn't catch it for two rounds.

**Remediation.**

```bash
# 1. Verify whether the run had concurrent mode on
# Re-run with explicit verification
./scripts/run-bench-matrix.sh \
   <target> <workspace> \
   --bench comprehensive_bench

cat <workspace>/artifacts/bench/comprehensive_bench/concurrent_mode_default_guard.txt
# Expected: CONCURRENT_MODE_DEFAULT=true / GIT_SHA=<sha> / TIMESTAMP=<iso>

# 2. If the guard file says false: the prior win is invalid
# - Revert the perf change
# - Ledger entry: "concurrent_mode_default was false; perf win invalid"
# - Re-do the optimization with concurrent mode confirmed-on

# 3. Wire the guard file into the artifact-lane writer
# Every comprehensive_bench run must drop the guard
rg -nP 'concurrent_mode_default_guard' crates/<project>-e2e/src/bin/comprehensive_bench.rs

# 4. CI gate: refuse to accept a perf claim without the guard file
# Add to .github/workflows/verification-gates.yml:
# - test -f reports/run-*/concurrent_mode_default_guard.txt
# - grep -q 'CONCURRENT_MODE_DEFAULT=true' reports/run-*/concurrent_mode_default_guard.txt
```

**Reference:** MINING-3 §1.9, anti-pattern A27. For Redis the analog is `RESP_VERSION=3` (or whichever default); for Torch it's `CUDA_DEVICE_COUNT`; per-class adaptations in [taxonomy/PROJECT-CLASSES.md](taxonomy/PROJECT-CLASSES.md).

---

## Quick Diagnostic Decision Tree

When you don't know where to start:

1. **Is the gate complaining?** → which gate? read its specific error → cross-link below.
2. **Is the bench flaky?** → § "Flaky bench (cv_pct > 5%)" above.
3. **Is the oracle preflight red?** → § "Oracle preflight doctor returns red" above.
4. **Is the parity score regressing?** → check waiver tree → § "Ratchet quarantine vs waiver decision" above.
5. **Is the convergence-tracker stuck?** → § "convergence-tracker.sh exits non-zero" above.
6. **Are agents fighting over files?** → § "Other agent edited my file mid-run" above.
7. **Catastrophic three-pillar regression?** → revert immediately → § "All-three-pillar simultaneous regression" above.

When still stuck: read [methodology/ANTI-PATTERNS.md](methodology/ANTI-PATTERNS.md) cover-to-cover. Most "weird" outcomes are listed there with a fix-section.

---

**End of TROUBLESHOOTING.** If you encounter a symptom not listed here that recurs across runs: add it. The point of this document is to compound; every new symptom + fix here is one less wasted hour next time.
