# Parallel Fan-Out Cookbook

Concrete patterns for dispatching parallel subagents on this skill. Each pattern: trigger / shape / coordination / merge.

## Pattern 1: Per-crate fan-out (Phase 1 RECON)

**Trigger:** Phase 1 starting on a multi-crate workspace.

**Shape:** N parallel `surface-archaeologist` instances, one per crate.

```bash
for crate in <port>/crates/*/; do
  cname=$(basename "$crate")
  ./scripts/dispatch-subagent.sh surface-archaeologist \
    --param crate="$cname" \
    --param target="$crate" \
    --param out="<workspace>/phase1_recon_${cname}.md" \
    --thread "gauntlet-<run-id>-phase1-${cname}" \
    --lane cc_3 \
    --reservation "tool://surface-archaeology-${cname}" \
    --rch-if-large &
done
wait
```

**Coordination:** each instance reserves `tool://surface-archaeology-<crate>` (exclusive). No cross-instance dependencies; they don't talk.

**Merge:** `synthesizer` subagent reads every `phase1_recon_<crate>.md` and emits `phase1_unified_recon.md`.

---

## Pattern 2: Per-pillar fan-out (Phase 9 BASELINE)

**Trigger:** Phase 9 starting.

**Shape:** 3 parallel baseline runners — perf, conformance, surface.

```bash
./scripts/dispatch-subagent.sh baseline-runner-perf \
  --param target="$TARGET" --param workspace="$WORKSPACE" \
  --thread "gauntlet-<run-id>-phase9-perf" \
  --lane cc_2 \
  --reservation "tool://comprehensive-bench" \
  --rch &

./scripts/dispatch-subagent.sh baseline-runner-conformance \
  --param target="$TARGET" --param workspace="$WORKSPACE" \
  --thread "gauntlet-<run-id>-phase9-conformance" \
  --lane cc_1 \
  --reservation "tool://oracle-runner" \
  --rch &

./scripts/dispatch-subagent.sh baseline-runner-surface \
  --param target="$TARGET" --param workspace="$WORKSPACE" \
  --thread "gauntlet-<run-id>-phase9-surface" \
  --lane cc_3 \
  --reservation "tool://feature-coverage-compute" &

wait
```

**Coordination:** distinct reservations per pillar; no contention.

**Merge:** orchestrator emits `phase9_baseline_summary.md` consolidating the three pillar reports.

---

## Pattern 3: Per-behavior-class fan-out (Phase 6 oracle-test-author)

**Trigger:** Phase 6 building the per-behavior-class oracle E2E test scaffold.

**Shape:** N parallel `oracle-test-author` instances, one per behavior class (SQL has ~22, RESP has ~12, etc. per `references/patterns/05-SUBJECT-ORACLE-COMPARATOR.md § Per-domain analogues`).

```bash
CLASS=$(jq -r .detected_class <workspace>/phase0_project_class.json)
case "$CLASS" in
  SQL-class) BEHAVIORS=("null-semantics" "three-valued-logic" "group-by-having" "recursive-cte" "join-type-semantics" "trigger-semantics" "returning" "generated-columns" "window-function" "pragma-introspection" "like-glob-escape" "subquery-semantics" "numeric-arithmetic-edges" "blob-io" "foreign-keys" "check-constraints" "conflict-resolution" "compound-select" "default-values" "attach-temp" "alter-table-rename-propagation") ;;
  RESP-class) BEHAVIORS=("get-set" "expire" "hash" "list" "set" "sorted-set" "stream" "pubsub" "cluster" "script" "transaction" "persistence") ;;
  # ... per-class lists ...
esac

for b in "${BEHAVIORS[@]}"; do
  ./scripts/dispatch-subagent.sh oracle-test-author \
    --param behavior-class="$b" \
    --param out="<port>/crates/<port>-e2e/tests/${b}_oracle_e2e.rs" \
    --thread "gauntlet-<run-id>-phase6-oracle-${b}" \
    --lane cc_1 \
    --reservation "tool://oracle-test-author-${b}" &
done
wait
```

**Coordination:** per-behavior reservations; merges via the harness build (one Cargo workspace).

---

## Pattern 4: Per-soak-runner parallel (Phase 15)

**Trigger:** Phase 15 starting; all 6 soak runners dispatch simultaneously.

**Shape:** 6 parallel rch jobs, each long-running.

```bash
rch exec --worker soak-fuzz --duration 24h -- \
  ./scripts/dispatch-subagent.sh soak-runner-fuzz \
  --workspace "$WORKSPACE" \
  --thread "gauntlet-<run-id>-phase15-fuzz" &

rch exec --worker soak-miri --duration 72h -- \
  ./scripts/dispatch-subagent.sh soak-runner-miri \
  --workspace "$WORKSPACE" \
  --thread "gauntlet-<run-id>-phase15-miri" &

rch exec --worker soak-loom --duration 48h -- \
  ./scripts/dispatch-subagent.sh soak-runner-loom \
  --workspace "$WORKSPACE" \
  --thread "gauntlet-<run-id>-phase15-loom" &

rch exec --worker soak-crash --duration 48h -- \
  ./scripts/dispatch-subagent.sh soak-runner-crash-boundary \
  --workspace "$WORKSPACE" \
  --thread "gauntlet-<run-id>-phase15-crash" &

rch exec --worker soak-bocpd --duration 120h -- \
  ./scripts/dispatch-subagent.sh soak-runner-bocpd \
  --workspace "$WORKSPACE" \
  --thread "gauntlet-<run-id>-phase15-bocpd" &

rch exec --worker soak-adversarial --duration 48h -- \
  ./scripts/dispatch-subagent.sh soak-runner-adversarial \
  --workspace "$WORKSPACE" \
  --thread "gauntlet-<run-id>-phase15-adversarial" &

# Don't `wait` here — soak runs for days. Set up notifications instead.
```

**Coordination:** distinct rch worker pools per runner.

**Merge:** `phase15_soak_designs.md` linked to per-runner summary files; loop-back to Phase 12 if any soak surfaces `TrueDivergence` or `ShiftDetected` or CRITICAL adversarial finding.

---

## Pattern 5: Multi-model triangulation (Phase 14 T3+)

**Trigger:** Phase 14, project is T3+, holistic review needed.

**Shape:** Same prompt dispatched to 3-4 distinct models in parallel.

```bash
# Per references/methodology/TRIANGULATION.md dispatch matrix.
for model in claude-opus codex gemini grok; do
  ./scripts/dispatch-subagent.sh triangulator \
    --param lens=correctness \
    --param model=$model \
    --param target=harness \
    --thread "gauntlet-<run-id>-phase14-triangulation-correctness-${model}" \
    --lane cross-cutting &
done
wait
```

**Coordination:** no reservations needed (each model is independent); aggregation via `subagents/triangulator.md`.

**Merge:** `CONSENSUS.md` per the consensus-rule matrix.

---

## Pattern 6: Per-fault-category parallel (Phase 6 fault-injector-author)

**Trigger:** Phase 6 building the fault VFS coverage.

**Shape:** N parallel `fault-injector-author` instances, one per `FaultKind`.

```bash
FAULTS=("TornWrite" "PartialWrite" "PowerCut" "IoError" "ReadFailure" "WriteFailure" "Latency" "DiskFull")
for f in "${FAULTS[@]}"; do
  ./scripts/dispatch-subagent.sh fault-injector-author \
    --param fault-kind="$f" \
    --thread "gauntlet-<run-id>-phase6-fault-${f}" \
    --lane cc_4 \
    --reservation "tool://fault-vfs-${f}" &
done
wait
```

**Coordination:** per-fault reservations; merge via Cargo workspace build.

---

## Anti-patterns

### Excessive fan-out

❌ Spawning 100 parallel subagents because "the bead graph has 100 ready beads".

✅ Cap fan-out at the available `rch` worker pool size + N local agents (typically 4-12 total). More than that and the orchestrator can't track them, and the MCP Agent Mail thread count explodes.

### Cross-lane contention

❌ Dispatching cc_1 + cc_2 agents that both want to edit `crates/<port>-harness/src/lib.rs`.

✅ Reserve files via MCP Agent Mail with `exclusive=true`. Lane convention exists exactly to minimize this; cross-lane is OK with a handoff thread.

### Stale reservations

❌ Subagent crashes; its reservation never releases; downstream agents block forever.

✅ Always set `ttl_seconds=3600` (or appropriate). Reservations auto-expire. The orchestrator polls for expired reservations and resurrects work.

### Synchronous wait on a hung agent

❌ Orchestrator's `wait` blocks indefinitely because one of the parallel agents hung.

✅ Set a timeout on the blocking wait/monitor step that follows `dispatch-subagent.sh`; the dispatcher itself only starts or renders work and does not supervise long-running agents. On timeout, write `<workspace>/timeout_<thread-id>.md`; the orchestrator decides recovery.

## Cross-references

- [`orchestration/ORCHESTRATION.md`](ORCHESTRATION.md) — the cc_N lane convention.
- [`orchestration/AGENT-FUNGIBILITY.md`](AGENT-FUNGIBILITY.md) — the swarm-init prompt.
- `pattern:260-AGENT-MAIL-RESERVATIONS` (file exists as `../patterns/260-AGENT-MAIL-RESERVATIONS.md` — the canonical reservation conventions).
