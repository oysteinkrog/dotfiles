# First-Bug-Hunt Recipe: RESP-Class

Empirically, these 10 bug classes surface in the first day of running the gauntlet on a RESP-class port (frankenredis). Steps ordered by frequency × set-up cost.

**Prerequisites:** vendored `redis-server` binary at pinned version on UNIX domain socket; `RespValue::{14 RESP3 variants}` normalized comparator; deterministic command trace; `EngineIdentity::Subject = "frankenredis"`, `EngineIdentity::Oracle = "redis-7.2.5-oracle"`.

Per item: **symptom** → **paste-ready repro** → **MismatchClassification expected** → **severity** → **fix pattern**.

---

## 1. RESP3 Set / Hash unordered-semantics false positives

**Symptom.** `SMEMBERS s` returns elements in different order across runs (correct per RESP3 Set semantics) but byte-string comparison flags as mismatch. ~5–20 false positives in round 1.

**Repro:**
```bash
./scripts/resp-oracle.sh --command "SADD s a b c d e; SMEMBERS s" --runs 5
```

```rust
let cmds = "SADD s a b c d e\nSMEMBERS s\n";
scenario_resp(cmds, "set_unordered");  // EquivalenceExpectation::SetEquivalence
```

**MismatchClassification:** `OrderDependentDifference` (priority 4) when string-compared; `FalsePositive` after RespValue normalization.
**Severity:** **low (false positive)** — but blocks signal; **high (after sanitation)** if real ordering bug.
**Fix pattern:** `RespValue::Set(Vec<RespValue>)` compared as unordered multiset; `RespValue::Map(Vec<(K, V)>)` compared as unordered map.

---

## 2. Integer overflow at command edges

**Symptom.** `INCRBY key 9223372036854775807` then `INCRBY key 1` — oracle returns error (overflow); subject wraps. Or returns `0`. Or panics.

**Repro:**
```bash
./scripts/resp-oracle.sh --command "SET k 9223372036854775806; INCRBY k 1; INCRBY k 1"
```

```rust
scenario_resp("\
SET k 9223372036854775806\n\
INCRBY k 1\n\
INCRBY k 1\n", "integer_overflow_edge");
```

**MismatchClassification:** `TrueDivergence { description: "i64 wrap vs error" }`.
**Severity:** **critical** — silent data corruption.
**Fix pattern:** [pattern:30-DIFFERENTIAL-V2-ENVELOPE](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) with explicit integer-edge corpus; cover `i64::MIN`, `i64::MAX`, `0`, `-1`.

---

## 3. BITCOUNT / BITOP edge ranges

**Symptom.** `BITCOUNT key 0 -1 BYTE` vs `BITCOUNT key 0 -1 BIT` — RESP 7.0 added BIT mode. Default is BYTE. Subject may inherit wrong default.

**Repro:**
```bash
./scripts/resp-oracle.sh --command "SET k foobar; BITCOUNT k 0 -1; BITCOUNT k 0 -1 BYTE; BITCOUNT k 0 -1 BIT; BITCOUNT k 0 0 BIT"
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **medium-high** — bitmap queries return wrong counts.
**Fix pattern:** [pattern:40-METAMORPHIC-TRANSFORMS](../patterns/40-METAMORPHIC-TRANSFORMS.md) `TransformFamily::Literal` per-byte/bit; add explicit corpus per range mode.

---

## 4. PEXPIREAT vs EXPIREAT precision

**Symptom.** `PEXPIREAT k 1234567890123` sets ms-precision; `EXPIREAT k 1234567890` sets s-precision. Subject may truncate ms internally to s, losing sub-second precision; first sub-second `TTL` check fails.

**Repro:**
```bash
./scripts/resp-oracle.sh --command "\
SET k v;
PEXPIREAT k 9999999999999;
PTTL k;
EXPIREAT k 9999999999;
TTL k;
PTTL k"
```

**MismatchClassification:** `TrueDivergence { description: "ms precision lost" }`.
**Severity:** **medium-high** — TTL-sensitive logic breaks (rate limiters, locks).
**Fix pattern:** ensure internal expire-time storage is ms; PTTL/TTL conversion at read.

---

## 5. SCRIPT LOAD vs EVAL determinism

**Symptom.** `EVAL "return 1+1" 0` returns `2`. `SCRIPT LOAD "return 1+1"` returns SHA. `EVALSHA <sha> 0` returns `2`. Subject's SHA computation may use different hash function or different normalization → SHA differs from oracle.

**Repro:**
```bash
./scripts/resp-oracle.sh --command "\
SCRIPT FLUSH;
SCRIPT LOAD 'return 1+1';
EVAL 'return 1+1' 0"
```

Compare SHA bytes.

**MismatchClassification:** `TrueDivergence { description: "SHA-1 of Lua source differs" }`.
**Severity:** **high** — clients caching SHAs across restarts break.
**Fix pattern:** SHA-1 of the *exact byte sequence* of the script source; document normalization (whitespace, line-ending) policy in contract.

---

## 6. PUBSUB FIFO ordering per subscriber under backlog

**Symptom.** Under high publish rate + slow subscriber, replication backlog grows; subscriber receives messages out of order. RESP spec requires FIFO per subscriber.

**Repro:**
```bash
./scripts/resp-oracle.sh --pubsub-flood --publishers 10 --subscribers 5 --rate 10000 --duration 30s
# check per-subscriber message order
```

**MismatchClassification:** `TrueDivergence`.
**Severity:** **critical** — pubsub-based event-sourcing breaks.
**Fix pattern:** [pattern:70-E-PROCESSES](../patterns/70-E-PROCESSES.md) — INV-PUBSUB-FIFO as software-enforced e-process; `p₀=1e-6, λ=0.9, α=0.001`; Ville-bounded rejection when ordering violated.

---

## 7. CLUSTER MOVED redirect handling

**Symptom.** Subject in cluster mode receives `MOVED` redirect for key it owns (slot ownership recently changed); client should re-resolve and retry; subject may panic or return wrong error code.

**Repro:**
```bash
./scripts/resp-cluster-oracle.sh --command "\
CLUSTER MEET 127.0.0.1 7001;
CLUSTER ADDSLOTSRANGE 0 8191;
# trigger slot migration
SET key:in-migrating-slot value"
```

**MismatchClassification:** `TrueDivergence { description: "MOVED handling differs" }`.
**Severity:** **high** — cluster-mode reliability.
**Fix pattern:** explicit cluster-mode crash boundary `MidSlotMigration`; per-boundary recovery assertion.

---

## 8. AOF rewrite during MULTI / EXEC

**Symptom.** AOF rewrite triggered mid-MULTI; transaction state lost in AOF; replay diverges.

**Repro:**
```bash
./scripts/resp-aof-crash-oracle.sh --boundary BeforeAofRewriteRename --workload "MULTI; SET k1 v1; SET k2 v2; EXEC"
```

Combines with [pattern:30-DIFFERENTIAL-V2-ENVELOPE](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) crash-boundary harness.

**MismatchClassification:** `TrueDivergence`.
**Severity:** **critical** — durability violation.
**Fix pattern:** explicit AOF crash boundary corpus; per-boundary recovery → `BGREWRITEAOF` cycle → state-equality assertion vs oracle.

---

## 9. RDB v11 byte-fidelity drift across host endianness

**Symptom.** RDB file generated on subject host bit-incompatible with oracle's RDB on different endianness host; `redis-check-rdb` may pass but bit-byte SHA differs.

**Repro:**
```bash
./scripts/resp-rdb-oracle.sh --workload bulk-write-1M-keys --hosts local,arm-worker
# diff SHA-256 of RDB files
```

**MismatchClassification:** `TrueDivergence` (if SHA differs) or `FalsePositive { reason: "endianness expected" }` if documented.
**Severity:** **medium** — cross-host RDB transfer breaks.
**Fix pattern:** Tier 1 byte equality for RDB on same architecture; Tier 2 canonical after architecture-normalization.

---

## 10. Expiration sweep regression under high-key-count

**Symptom.** With 10M keys, 1% TTL'd, `expiration_sweep_time_ns` saturates and starves command dispatch. Subject may sweep O(N) per tick; oracle samples adaptively.

**Repro:**
```bash
./scripts/resp-stress-oracle.sh --workload "DEBUG POPULATE 10000000; EXPIRE-RANDOM 1pct 60s; sleep 30; INFO stats"
# check ops/sec degradation
```

**MismatchClassification:** `TrueDivergence { description: "throughput collapse under expiration pressure" }`.
**Severity:** **high** — production DoS.
**Fix pattern:** [pattern:205-ATOMIC-BOOL-EMPTY-GATE](../patterns/205-ATOMIC-BOOL-EMPTY-GATE.md) on expiration sweep; adaptive sampling per `--hz` setting.

---

## Empirical first-day stats

- **3–5 of the above 10 in the first hour** (Set unordered FP + integer overflow + BITCOUNT BIT + PEXPIREAT precision + PUBSUB FIFO)
- **7–9 in the first day**
- **All 10 by round 3**

Items 6 (PUBSUB FIFO), 8 (AOF crash-boundary), and 10 (expiration sweep) are the deepest — they require concurrent workloads + soak time. They are the strongest motivators for landing the e-process layer.

---

## Cross-references

- [PROJECT-CLASSES.md § RESP-Class](../taxonomy/PROJECT-CLASSES.md)
- [case-studies/frankenredis.md](../case-studies/frankenredis.md)
- [patterns/70-E-PROCESSES.md](../patterns/70-E-PROCESSES.md)
- [patterns/205-ATOMIC-BOOL-EMPTY-GATE.md](../patterns/205-ATOMIC-BOOL-EMPTY-GATE.md)
