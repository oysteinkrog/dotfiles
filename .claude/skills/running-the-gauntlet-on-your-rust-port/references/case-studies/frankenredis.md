# Case Study: FrankenRedis — `/dp/frankenredis`

The largest "implicit-discipline → explicit-discipline" lift in the family. Conformance is wired against `redis-7.2.5`; what's missing is the central ledger, the formal `RespValue` comparator, and the e-process invariants for protocol/coordination guarantees.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | RESP-class ([PROJECT-CLASSES.md § RESP-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T4 — Platform** (workspace structure: `fr-bench`, `fr-command`, `fr-config`, `fr-conformance`, `fr-eventloop`, `fr-expire`, `fr-persist`, `fr-protocol`, `fr-repl`, `fr-runtime`, `fr-sentinel`, `fr-server`, `fr-store`) |
| **Recommended mode** | `gauntlet-full` — this is the first proper application of the gauntlet; subsequent runs go `incremental-rebase` after the ledger lands |
| **Reference pinning** | `docs/contracts/redis_version_contract.toml` to be created at `redis-7.2.5`; preflight doctor verifies `INFO server` `redis_version` matches and `RESP_VERSION=3` is default; vendored `redis-server` binary path pinned |
| **README claims summary** | RESP2/3 wire-compatible drop-in; 241 commands; RDB v11 + AOF persistence; replication; Lua scripting; cluster mode. Conformance vs vendored Redis/Valkey 7.2.4-7.2.5 via RESP transcripts is the headline claim. |

Recent activity (commits `eb448ba4`, `7874d6e6`, `188258a8`) shows oracle-port hardening in flight — `frankenredis-vcv8o` (cap concurrent e2e server processes) and `frankenredis-fhxwy` (collision-free oracle ports). These are *infra* beads; the gauntlet would land *discipline* beads on top.

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ✅ | vs vendored Redis 7.2.4 via RESP transcripts; RDB/AOF byte fixtures; stream/group fixtures |
| Negative ledger | ⚠️ implicit | Discussions in commit messages and chat; **no central `docs/progress/perf-negative-results.md`** |
| cass | ✅ | mining wired |
| Agent Mail | ✅ | per-bead thread IDs |
| bv | ✅ | robot endpoints |
| Math layer (§75–76) | ❌ | no e-process layer; no Beta posteriors; no conformal bands |
| MT-scale harness | ⚠️ implicit | handles N concurrent client connections; **no `mt_mvcc_bench`-class adversarial workload** |
| RaptorQ | ❌ | not applicable; AOF is the persistence analog |
| `RespValue` normalized comparator | ❌ | no formalized 14-RESP3-type comparator with collection-semantics rules |
| AGENTS.md mandate paragraph | ⚠️ | partial; missing the 60-day cass mining mandate + failure terms |
| Crash boundaries | ⚠️ partial | RDB/AOF tests exist; **not enumerated as the 6+ named boundaries** (`BeforeAofRewriteRename` … `DuringFsync`) |
| `RdbFaultVfs` | ❌ | no equivalent of `fault_vfs.rs` for AOF/RDB |
| Primary score | ❌ | no "RPS p99 latency" with explicit threshold; benches present but unweighted |
| `.bench-history/comprehensive_bench.latest.json` | ❌ | not committed |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** `fr-bench` crate exists; client+server bench infrastructure works. RPS measurements happen ad-hoc. No keep-gate. No `release-perf` profile distinction documented. No `.bench-history` ratchet. Pass-over-pass discipline is informal — perf claims live in commit messages.

**First 3 gaps the gauntlet would surface in round 1:**
1. **No `.bench-history/comprehensive_bench.latest.json` baseline.** Every perf claim made so far has no machine-checkable baseline; the gauntlet's first action is to capture one and commit it.
2. **`resp_parse_time_ns` not exposed as a hot-path counter.** The fast-path RESP3 parser likely has sub-frame attribution headroom but no per-phase counter to attribute. First profile-card pass would reveal.
3. **Pipeline-depth effect on p99 not measured.** Benches likely fix `pipeline_depth=1` or some constant; the headline matrix demands `[1, 16, 128]` ratios.

### (b) Conformance — current state + first 3 gaps

**Current state.** RESP transcript fixtures exist; per-command pass-rate is measured. The new oracle-port-collision fix (`fhxwy`) suggests the test harness is exercised. But — there's no `RespValue` normalized type that *forces* collection-semantics correctness; comparisons are probably string-byte against transcripts.

**First 3 gaps:**
1. **Set/Hash comparator orders comparison.** Without a `RespValue::Set` that compares as multiset, an SMEMBERS-returns-in-different-order divergence shows up as a false-positive mismatch. Likely surfaces 5–20 false positives in round 1.
2. **RESP3 `Double`, `BigNumber`, `Map`, `Set`, `Push`, `Attribute` variants** — first-pass differential will reveal at least one command where the RESP2 fallback is used inadvertently, losing type fidelity (e.g., `HRANDFIELD WITHVALUES` returning array instead of Map under RESP3).
3. **PUBSUB FIFO ordering per subscriber** — no e-process exists to monitor "FIFO per subscriber" — under high replication backlog pressure, the gauntlet would catch out-of-order delivery that the existing transcript tests miss because they're single-subscriber.

### (c) Surface — current state + first 3 gaps

**Current state.** 241 commands × RDB v11 × AOF × replication × Lua × cluster mode is a *wide* surface. `fr-command` enumerates implemented commands but there's no formal FeatureUniverse with weights, present/partial/missing/excluded.

**First 3 gaps:**
1. **Cluster-mode commands** (`CLUSTER SLOTS`, `CLUSTER NODES`, `CLUSTER ADDSLOTSRANGE`, `MIGRATE`) likely marked `present` collectively but implementing only a subset.
2. **`DEBUG` subcommands** — `DEBUG SLEEP`, `DEBUG OBJECT`, `DEBUG JMAP` are referenced by the test harness itself (recent collision-free-ports fix probably uses `DEBUG SLEEP`); inventory must distinguish "used by harness" vs "exposed to clients".
3. **Module API + Lua / Functions** — server-side scripting surface is large and typically partial; classification needs `partial` accounting.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankenredis /dp/frankenredis__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: redis-7.2.5
# - oracle mode: subprocess RESP3 over deterministic socket
# - perf weights: StringOps=0.30, HashOps=0.15, ListOps=0.10, SetOps=0.10,
#   SortedSetOps=0.10, StreamOps=0.05, PubSub=0.05, Pipeline=0.10, Cluster=0.05
# - Phase 8 failure terms: RESP frame malformed, AOF rewrite race, RDB byte-drift,
#   PUBSUB ordering violation, replication offset desync, EAGAIN storm,
#   slot resolution miss, expiration sweep regression

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankenredis /dp/frankenredis__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 72
```

Wall time T4 × `gauntlet-full`: **30–45 days.**

---

## 5. Expected Pillar Findings

### Performance
1. **No `release-perf` profile** — current benches likely use `--release` (size-optimized); the LTO/codegen-units divergence will swamp the signal.
2. **Allocator selection drift** — jemalloc vs system allocator changes p99 by 5–15% on `SET` benchmarks; not documented in a contract.
3. **`resp_parse_time_ns` missing** as hot-path counter — first-pass profile card will surface it as the dominant frame.
4. **`expiration_sweep_time_ns` saturating under high-key-count load** — likely O(N) sweep with no AtomicBool gate (pattern 2 lesson).
5. **`replication_backlog_appends` not exposed** — replication-lag perf claims are unprovable without the counter.
6. **`pubsub_deliver_time_ns` quadratic in subscriber count** — likely O(N×M) for N publishers × M subscribers.
7. **`dict_probe_count` not exposed** — hash-table probe length under load is invisible.
8. **`cluster_slot_resolve_time_ns` not measured** — slot resolution is in the critical path of every CLUSTER command.

### Conformance
1. **`SMEMBERS` ordering false positives** — unordered Set comparator missing.
2. **`HGETALL` ordering false positives** — unordered Hash comparator missing.
3. **RESP3 `Map` vs RESP2 `Array` fallback** — at least one command using inadvertent fallback.
4. **`SCRIPT LOAD` SHA differs across runs** — non-deterministic script-loading order.
5. **`PUBSUB FIFO` violation under backlog pressure** — invariant exists in spec, no test exists in port.
6. **`EXPIRE` precision** — `PEXPIREAT` vs `EXPIREAT` accuracy at sub-second.
7. **`DEL` idempotence within `MULTI`/`EXEC`** — no e-process to monitor.
8. **`BITCOUNT` range edges** — start/end negative-index semantics.
9. **`CLUSTER MOVED` redirect handling** — when subject crosses cluster topology change.
10. **AOF rewrite during `MULTI`/`EXEC`** — torn AOF mid-transaction.

### Surface
1. **`CLIENT NO-EVICT` + `CLIENT NO-TOUCH`** likely missing.
2. **`OBJECT FREQ` LFU semantics** depend on `maxmemory-policy`; might be partial.
3. **`COMMAND GETKEYSANDFLAGS`** — Redis 7.0+ — might be missing.
4. **`LATENCY HISTORY`/`LATENCY GRAPH`** — diagnostic surface; likely excluded.
5. **`MEMORY DOCTOR`/`MEMORY STATS`** — likely excluded.

---

## 6. Patterns to Apply First

1. **[pattern:180-NEGATIVE-LEDGER](../patterns/180-NEGATIVE-LEDGER.md)** — seed `docs/progress/perf-negative-results.md` with verbatim FrankenSQLite preamble (CC.md lines 479–482).
2. **[pattern:05-SUBJECT-ORACLE-COMPARATOR](../patterns/05-SUBJECT-ORACLE-COMPARATOR.md)** — build `RespValue::{14 RESP3 variants}` normalized type with collection-semantics comparator.
3. **[pattern:125-COMPREHENSIVE-BENCH](../patterns/125-COMPREHENSIVE-BENCH.md)** — lift the comprehensive-bench template; six categories per RESP-class weights.
4. **[pattern:155-BENCH-HISTORY-RATCHET](../patterns/155-BENCH-HISTORY-RATCHET.md)** — commit `.bench-history/comprehensive_bench.latest.json` baseline.
5. **[pattern:70-E-PROCESSES](../patterns/70-E-PROCESSES.md)** — add INV-RESP-WellFormed (hardware-enforced `p₀=1e-9` — protocol parser correctness), INV-PUBSUB-FIFO (software-enforced `p₀=1e-6`), INV-DEL-Idempotent (software).

---

## 7. Estimated Rounds to Convergence

**10–14 rounds.** Round 1 surfaces the structural-absence gaps (no ledger, no `RespValue`, no `.bench-history`); rounds 2–5 fill in coverage; rounds 6–10 close the deep tail (PUBSUB FIFO, AOF rewrite race, cluster MOVED).

---

## 8. Risk Register

1. **`redis-server` subprocess port collisions** under parallel test execution (already a known issue — bead `fhxwy`). *Mitigation:* the new collision-free-ports fix + the `tool://oracle-runner` reservation must hold under T4 parallelism.
2. **Vendored Redis binary drift across hosts.** `rch`-offloaded runs may hit a different `redis-server` version than local. *Mitigation:* `oracle-preflight-doctor.sh` checks version on every host before certifying.
3. **Lua scripting determinism.** EVAL/EVALSHA results depend on Lua interpreter version; pin via the contract.

---

## 9. What Ships from Convergence

`certification_bundle/` shape per SQL-class plus:
- `resp_protocol_compliance.json` — per-RESP3-variant pass rate (14 variants)
- `rdb_aof_roundtrip.json` — Tier-1/2/3 per fixture
- `cluster_topology_consistency.json` — slot-ownership invariants
- `pubsub_fifo_eprocess.json` — Ville-bounded INV-PUBSUB-FIFO trajectory

Plus `FINAL_GAUNTLET_REPORT.md`, `PARITY_RUNBOOK.md`, `RELEASE_CERTIFICATION_TEMPLATE.md`.

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FrankenRedis](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § RESP-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/resp-class.md](../first-bug-hunt/resp-class.md)
