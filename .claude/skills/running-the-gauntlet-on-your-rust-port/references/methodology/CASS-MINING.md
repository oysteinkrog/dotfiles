# CASS-MINING — Cross-Machine Search Recipes per Failure-Term Class

The gauntlet's negative-ledger discipline depends on mining 60 days of `cass` session history BEFORE starting any perf/conformance/surface-affecting work. This file is the canonical per-failure-class recipe book.

If you don't have `/cass` installed: see [SKILL-FALLBACKS.md § /cass](SKILL-FALLBACKS.md). The pipeline degrades gracefully but the discipline (records-the-blocker, never-silently-skip) holds.

---

## The 60-Day Baseline Mandate (Verbatim)

From [assets/agents-md-mandate-paragraph.md](../../assets/agents-md-mandate-paragraph.md) — drop this paragraph into the target project's `AGENTS.md` near the top:

> **Negative-Evidence Discipline**
>
> This project maintains three durable negative-evidence ledgers in `docs/progress/`:
> - `perf-negative-results.md` — performance ideas that were measured and rejected.
> - `conformance-negative-results.md` — conformance hypotheses that were tested and refuted.
> - `surface-deferrals.md` — surface features explicitly Excluded with rationale and retry-condition predicate.
>
> > **Verbatim from the gauntlet methodology (CC.md lines 479–482):** "This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass, and add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction."
>
> Before any agent starts a perf-affecting change, a conformance-affecting change, or a surface-affecting change, the agent MUST:
>
> 1. **Grep the relevant ledger** for the proposed hotspot, behavior, or feature.
> 2. **Mine 60 days of `cass` session history** for failure terms.
> 3. **Check recent commits** for prior closure on this candidate.
> 4. **If `cass` is unavailable or the ledger is reserved**, the agent MUST record a *blocker* entry rather than silently skipping.
>
> > **Verbatim from CODEX.md §10.2 lines 1464–1472:** "For major perf campaigns, agents must also mine: last 60 days of CASS session history, recent commits, perf artifacts, failed/rejected/slower/regressed terms. If CASS or the ledger is unavailable or reserved, the agent must record a blocker or patch-ready entry rather than silently skipping the step."

This is **K-3 verbatim** — negative evidence is a first-class output. Skipping the mine is not a "saving time" optimization; it's a discipline violation that defeats the gauntlet.

---

## Cross-Machine Invocation (canonical)

Per the `/cass` skill's Cross-Machine Search section, every gauntlet run mines ALL five machines. Findings are aggregated; if a machine is unreachable, a BLOCKER entry is logged (never silent skip).

```bash
RUN_ID=$(date +%Y%m%d-%H%M%S)-$(git -C <target> rev-parse --short HEAD)
WORKSPACE=<workspace>

mkdir -p "$WORKSPACE/cass_findings"

for MACHINE in local css csd ts1 ts2; do
  echo "[$(date -Iseconds)] mining $MACHINE for 60d..."
  if [ "$MACHINE" = local ]; then
    timeout 30s cass search "<query-string-from-recipe>" --robot --days 60 --limit 50 --mode lexical --timeout 30000 \
      > "$WORKSPACE/cass_findings/${MACHINE}_${RUN_ID}.jsonl" 2> "$WORKSPACE/cass_findings/${MACHINE}_${RUN_ID}.err"
  else
    ssh "$MACHINE" 'timeout 30s cass search "<query-string-from-recipe>" --robot --days 60 --limit 50 --mode lexical --timeout 30000' \
      > "$WORKSPACE/cass_findings/${MACHINE}_${RUN_ID}.jsonl" 2> "$WORKSPACE/cass_findings/${MACHINE}_${RUN_ID}.err"
  fi
  if [ $? -ne 0 ]; then
    echo "BLOCKER: cass on $MACHINE failed" \
         | tee -a "$WORKSPACE/docs/progress/perf-negative-results.md"
  fi
done

# Aggregate
jq -s 'add' "$WORKSPACE/cass_findings/"*_${RUN_ID}.jsonl > "$WORKSPACE/cass_findings_${RUN_ID}.jsonl"
```

The aggregated `cass_findings_<run_id>.jsonl` is the durable output. It is read by:
- `scripts/mine-ledger.sh` (called from every perf-bead pre-flight)
- `subagents/idea-wizard-orchestrator.md` (so the wizard doesn't propose ideas already on the negative-ledger)
- `subagents/final-report-author.md` (the FINAL_GAUNTLET_REPORT.md § Negative-Evidence appendix cites the findings)

If `cass-mine-only` mode was used (see [MODE-ROUTER.md § cass-mine-only](MODE-ROUTER.md)), this is the entire deliverable.

---

## Per-Failure-Class Query Recipes

Each recipe defines the **calibrated grep terms** for that failure class. The terms are deliberately overlapping — a "perf regression on workload X" search uses both universal terms (`rejected`, `reverted`, ...) AND project-class-specific terms (`micro-lever trap`, `MT8 attribution`, ...).

### Recipe 1 — "perf regression on workload X"

**When to use:** before starting any perf campaign targeting workload X. Find prior attempts that were rejected.

**Universal grep terms:**
```
rejected
reverted
abandoned
slower
regressed
"didn't help"
"within noise"
"no improvement"
"failed to improve"
"rolled back"
"backed out"
"not a keep"
"keep gate"
```

**Project-class-specific terms (additional):**

| Class | Terms |
|---|---|
| SQL-class | `MT8 attribution`, `micro-lever trap`, `within ±3-5% noise band`, `focused vs broad`, `ratio frontier`, `fused-design target`, `DML mutation operator`, `cold start`, `concurrent_mode_default_guard`, `pass-over-pass`, `bench-history` |
| RESP-class | `event-loop changes`, `parser fast paths`, `allocator swaps`, `write coalescing`, `AOF batching`, `RDB codec changes`, `command dispatch hot path`, `pubsub deliver time` |
| Numerical-Python-class | `SIMD/vectorization changing dtype`, `view/copy shortcuts`, `RNG acceleration breaking bit-exact seeds`, `ufunc loop selection`, `BLAS thread count`, `array_view_creates` |
| ML-System-class | `kernel fusion changes`, `memory format changes`, `allocator pooling`, `graph capture`, `autograd tape shortcuts`, `AD shortcuts breaking higher-order gradients`, `aten_dispatch hot path`, `NCCL collective time` |
| HTTP-Protocol-class | `extractor fast paths`, `parser zero-copy changes`, `validation schema caching`, `DI lifetime changes`, `route match time`, `middleware traversal time` |

**Canonical invocation:**
```bash
QUERY="(rejected OR reverted OR abandoned OR slower OR regressed OR 'didn't help' OR 'within noise' OR 'keep gate') AND <WORKLOAD_X>"
for MACHINE in local css csd ts1 ts2; do
  if [ "$MACHINE" = local ]; then
    timeout 30s cass search "$QUERY" --robot --days 60 --limit 50 --mode lexical --timeout 30000
  else
    ssh "$MACHINE" "timeout 30s cass search $(printf '%q' "$QUERY") --robot --days 60 --limit 50 --mode lexical --timeout 30000"
  fi
done | jq -s 'add' > "$WORKSPACE/cass_findings/perf_regression_X.jsonl"
```

**Output triage:** each finding lands as a row in `docs/progress/perf-negative-results.md` with:
- Original session date
- One-line summary
- Retry-condition predicate (one of the 8 forms from [RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md))
- Decision: "satisfies predicate → reconsider" OR "does not satisfy → defer; do not start new work"

### Recipe 2 — "oracle divergence in behavior class Y"

**When to use:** before authoring a new oracle E2E test in behavior class Y (e.g., NULL semantics, three-valued logic, JOIN semantics). Find prior divergences.

**Grep terms:**
```
"oracle divergence"
"TrueDivergence"
"NullHandlingDifference"
"TypeAffinityDifference"
"FloatingPointDifference"
"OrderDependentDifference"
"FalsePositive"
"mismatch"
"diverge"
"semantic gap"
"first_divergence"
"FailureBundle"
```

**Plus behavior-class-specific terms:**
| Behavior class | Additional terms |
|---|---|
| NULL semantics | `IS NULL`, `IS NOT NULL`, `three-valued logic`, `NULL coercion` |
| GROUP BY edges | `HAVING`, `bare group`, `non-aggregate`, `GROUP BY rollup` |
| JOIN semantics | `LEFT OUTER`, `RIGHT OUTER`, `FULL OUTER`, `CROSS JOIN`, `NATURAL JOIN` |
| Window functions | `OVER`, `PARTITION BY`, `frame`, `RANGE BETWEEN`, `ROWS BETWEEN` |
| Trigger semantics | `BEFORE`, `AFTER`, `INSTEAD OF`, `RECURSIVE TRIGGER` |
| RESP encoding | `RESP3`, `verbatim string`, `BigNumber`, `Map type`, `Set type` |
| Tensor ULP | `gradcheck`, `assert_allclose`, `atol`, `rtol`, `ULP` |

**Output triage:** findings land in `docs/progress/conformance-negative-results.md` with subsystem attribution (Parser / Resolver / Planner / Vdbe / Storage / Wal / Mvcc / Functions / Extension / TypeSystem / Pragma / Unknown — per the `Subsystem` enum from MINING-2 §5).

### Recipe 3 — "fault VFS bug"

**When to use:** before authoring a new `FaultSpec` (SQL-class), before drafting a new fault-injection profile in any class.

**Grep terms:**
```
"FaultKind"
"FaultSpec"
"FaultInjectingVfs"
"TornWrite"
"PartialWrite"
"PowerCut"
"DiskFull"
"torn-wal-frame"
"partial-checkpoint"
"recovery non-deterministic"
"crash boundary"
"BeforeWalHeaderWrite"
"AfterWalFrameAppendBeforeFsync"
"fault profile"
"FaultTriggerRecord"
```

Plus class-specific:
| Class | Additional |
|---|---|
| RESP-class | `RdbFaultVfs`, `partial AOF rewrite`, `mid-rdb torn write`, `fsync-then-power-cut`, `EAGAIN storm` |
| ML-System-class | `CheckpointFaultVfs`, `partial torch.save`, `mid-shard NCCL drops`, `CUDA_ERROR_LAUNCH_FAILED` |
| HTTP-Protocol-class | `RequestFaultMiddleware`, `connection drop mid-body`, `slow-loris`, `partial multipart` |

### Recipe 4 — "concurrency interleaving bug"

**When to use:** before adding a `loom` / `shuttle` target, before debugging an MT8 (or class-equivalent) flakey test.

**Grep terms:**
```
"loom"
"shuttle"
"interleaving"
"deadlock"
"race condition"
"DPOR"
"Mazurkiewicz"
"happens-before"
"AB or AB or BA"
"non-deterministic interleaving"
"thread starvation"
"livelock"
"priority inversion"
```

Plus class-specific:
| Class | Additional |
|---|---|
| SQL-class | `mt-mvcc-bench`, `MT8 attribution`, `swarm_multiprocess`, `BEGIN CONCURRENT`, `SSI conflict`, `SireadTable`, `LockExclusivity`, `VersionChainOrder` |
| RESP-class | `event-loop reentrancy`, `pubsub FIFO`, `client buffer overflow` |
| ML-System-class | `NCCL all-reduce`, `gradient race`, `optimizer step race`, `parameter server race` |

### Recipe 5 — "ratchet anomaly"

**When to use:** when `scripts/apply-ratchet.sh` returns `Quarantine` or `Block`; before deciding whether to waive or to remediate.

**Grep terms:**
```
"ratchet"
"ratchet quarantine"
"quarantine"
"waiver"
"lower bound"
"conformal band"
"truncate_score"
"per-category bound"
"primary score regression"
"geomean regression"
".bench-history"
"pass-over-pass"
"both gates"
"same run window"
```

### Recipe 6 — "BOCPD ShiftDetected"

**When to use:** when Phase 15 soak's `subagents/soak-runner-bocpd.md` reports `ShiftDetected` mid-window; investigate whether real regression or noise.

**Grep terms:**
```
"BOCPD"
"ShiftDetected"
"regime shift"
"hazard rate"
"H = 1/250"
"Beta-Binomial"
"Normal-Gamma"
"abort rate posterior"
"throughput posterior"
"replay_harness"
"window_regimes"
```

### Recipe 7 — "FeatureUniverse weight rebalance"

**When to use:** before `add-feature` mode or when surface-pillar ratchet quarantines; check whether weight rebalances have been attempted and rejected before.

**Grep terms:**
```
"FeatureUniverse"
"sum(weights)"
"weight rebalance"
"parity_score_contract"
"exclusion_rationale"
"truncate_score"
"per-category weight"
"loader rejects"
"weight normalization"
"FeatureId"
```

### Recipe 8 — "cancellation correctness bug" (FastMCP / HTTP-Protocol)

**When to use:** before debugging cancellation budgets / four-valued outcomes in FastMCP or any HTTP-Protocol-class port.

**Grep terms:**
```
"cancellation"
"cancel_token"
"four-valued outcome"
"outcome classification"
"budget exceeded"
"capability security"
"resource streaming"
"tool invocation latency"
"JSON-RPC error mapping"
"macro expansion"
"schema generation"
```

### Recipe 9 — "checkpoint corruption" (FrankenTorch / ML-System)

**When to use:** before debugging `torch.save` / state-dict / autograd-tape corruption in ML-System-class ports.

**Grep terms:**
```
"checkpoint corruption"
"torch.save partial"
"state_dict roundtrip"
"NCCL drop"
"CUDA_ERROR_LAUNCH_FAILED"
"gradient checkpoint"
"dispatch_table"
"autograd tape append"
"jit cache"
"compile cache"
"gradcheck"
"nondeterministic_op_count"
"memcpy_h2d"
```

### Recipe 10 — "RDB/AOF crash boundary" (FrankenRedis / RESP-class)

**When to use:** before debugging persistence-state-machine bugs in RESP-class ports.

**Grep terms:**
```
"RDB crash"
"AOF rewrite"
"BGSAVE"
"BGREWRITEAOF"
"appendfsync"
"DuringRdbWrite"
"BeforeAofRewriteRename"
"AfterReplOffsetBeforeAck"
"MidPsync"
"DuringFsync"
"replication_backlog_appends"
"client_io_eagain_count"
```

---

## Aggregated Output Schema: `cass_findings_<run_id>.jsonl`

Each line in the JSONL is one `cass`-returned hit, augmented with:

```jsonc
{
  // From cass --json
  "session_id": "<UUID>",
  "machine": "local | css | csd | ts1 | ts2",
  "session_path": "/path/to/transcript.jsonl",
  "matched_at": "2026-05-22T19:14:00Z",
  "snippet": "...the matching transcript line, ≤200 chars...",
  "session_summary": "...one-line session-level summary...",

  // Augmented at aggregation time
  "recipe_id": "perf_regression | oracle_divergence | fault_vfs_bug | ...",
  "failure_class": "perf | conformance | fault | concurrency | ratchet | bocpd | feature | cancellation | checkpoint | persistence",
  "subsystem_attribution": "Parser | Resolver | Planner | Vdbe | Storage | Wal | Mvcc | Functions | Extension | TypeSystem | Pragma | Unknown",
  "triage_priority": 0-5,  // 0 = highest, 5 = lowest
  "deduplicated_against": ["<prior-finding-id>", ...],

  // Decision (populated after triage by mine-ledger.sh or by the orchestrator)
  "decision": "satisfies_retry_predicate | does_not_satisfy | NEEDS_REFINEMENT | NEW_HYPOTHESIS_SPAWNED",
  "decision_rationale": "<one-paragraph>",
  "ledger_entry_path": "docs/progress/<which-ledger>.md#<anchor>"  // if landed in a ledger
}
```

Schema versioning: `LOG_SCHEMA_VERSION` field at the top of every aggregated file. Current: `cass-findings.v1.0.0`.

---

## When `cass` is unavailable

If `cass` is not installed, not authenticated, or one of the five machines is unreachable, **do not silently skip**. Per the AGENTS.md mandate:

```bash
cat >> "$WORKSPACE/docs/progress/perf-negative-results.md" <<EOF

## BLOCKER: cass unavailable

- timestamp: $(date -Iseconds)
- environment: gauntlet_workspace
- attempted machines: <list>
- failures: <list with error messages>
- impact: cannot verify whether prior optimization attempts exist on this hotspot
- next_action:
  - install cass via \`jsm install cass\` if available
  - otherwise: fall back to inline rg over ~/.claude/projects/ + git log mining
  - re-attempt cass mining before declaring convergence
- patch-ready: <if a partial mine is possible (e.g., 1-of-5 machines reachable), proceed with patch-ready entry that documents the partial coverage>
EOF
```

The orchestrator continues but stamps every emitted artifact from this run with `provenance: cass_partial_or_skipped_at_<timestamp>` so a future agent (or `subagents/final-report-author.md`) knows to caveat the findings.

Fallback search via `rg` over `~/.claude/projects/`:

```bash
for term in rejected reverted abandoned slower regressed "within noise" "keep gate"; do
  rg --json -i "$term" ~/.claude/projects/ --type-add 'sess:*.jsonl' --type sess \
    > "$WORKSPACE/cass_findings/fallback_rg_${term// /_}.jsonl"
done
```

The fallback is partial (only local machine, no session-level context, no auth-gated transcripts) but better than zero coverage.

---

## Patch-ready entries

A patch-ready entry is the structured fallback for cases where the discipline cannot be fully executed. It is NOT a free pass.

```markdown
## Patch-ready entry: <name>

- timestamp: <ISO 8601>
- partial-coverage details: <what was mined; what wasn't>
- rationale for proceeding: <why we can't wait>
- assumed risks: <what bugs the partial coverage might miss>
- next-attempt trigger: <when to re-run the full mine; e.g., "after css machine network restored">
- compensating controls: <e.g., "running Phase 14 fresh-eyes with all 3 reviewers + multi-model triangulation to compensate">
```

A bead-graph-validator check rejects any closed bead whose preflight cass mine has only a patch-ready entry without an explicit `compensating controls` line. The discipline shouldn't degrade silently.

---

## How the orchestrator uses the findings

After `cass_findings_<run_id>.jsonl` exists, the orchestrator:

1. **Pre-flight check** (before any Phase 5/6/7 work): for each proposed hotspot/behavior/feature, grep the JSONL. If hits exist, READ the retry-condition predicate, check whether current evidence satisfies it. If not, do NOT proceed; log the deferral.

2. **Idea-wizard input** (Phase 10): the wizard sees the JSONL and won't propose ideas already on the negative-ledger.

3. **Convergence-tracker input** (Phase 11): every new finding NOT in the prior cass mine counts as a "new genuine finding" for the convergence count.

4. **Final-report input** (Phase 16): the `FINAL_GAUNTLET_REPORT.md § Negative-Evidence Trail` cites the count of pre-existing findings, the count of newly-confirmed findings, the count of deferred findings with retry predicates.

5. **Certification bundle** (Phase 16): `certification_bundle/negative_evidence_summary.json` is the machine-readable summary; the auditor reads it before the human-readable narrative.

---

## Failure modes / common mistakes

- **Mining only one machine** — defeats the cross-machine search; FrankenSQLite's discipline mines all five. Document if one is unreachable.
- **Mining with `--days 7`** — the 60-day window is what the AGENTS.md mandate requires. Short windows miss the systematic patterns.
- **Skipping universal terms in favor of just project-class terms** — universal terms catch general optimization-rejection patterns that are class-agnostic.
- **Counting cass hits without reading the retry predicate** — a hit is data; the retry predicate is the gate. A finding that "satisfies the predicate now" still requires the discipline of writing why.
- **Silent skip when `cass` errors** — violates the AGENTS.md mandate. ALWAYS log a BLOCKER entry.
- **Treating fallback `rg` results as full-coverage** — fallback is partial; stamp artifacts accordingly.
- **Re-running the mine each phase without caching** — `cass` is expensive; cache `cass_findings_<run_id>.jsonl` per run and reuse across phases.

---

## See also

- [SKILL.md § Negative-Ledger Mandate](../../SKILL.md) — the headline statement.
- [methodology/RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md) — the 8 predicate forms each finding lands with.
- [methodology/KERNEL.md § K-3](KERNEL.md) — negative evidence first-class axiom.
- [assets/agents-md-mandate-paragraph.md](../../assets/agents-md-mandate-paragraph.md) — the verbatim mandate to drop into the target project's AGENTS.md.
- [SKILL-FALLBACKS.md § /cass](SKILL-FALLBACKS.md) — what to do if cass is missing.
- The `/cass` skill's own SKILL.md — for cass CLI usage details, --robot/--json conventions, and Cross-Machine Search section.
