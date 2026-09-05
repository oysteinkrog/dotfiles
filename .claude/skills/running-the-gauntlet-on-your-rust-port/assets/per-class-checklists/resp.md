# RESP-class Adoption Checklist

For ports in the RESP-class (frankenredis and future Redis-shaped reimplementations).

## Phase 0 — Workspace
- [ ] `<workspace>/` initialized as its own git repo
- [ ] `docs/contracts/redis_version_contract.toml` pins exact version (e.g., `7.2.5`)
- [ ] `[reference.extras]`: `modules = [...]`, `cluster_mode = false`, `persistence = "aof+rdb"`
- [ ] Reference `redis-server` binary vendored or pinned via package manager

## Phase 3 — Oracle wiring
- [ ] Vendored `redis-server` driven via UNIX domain socket
- [ ] `RespValue` enum with all 14 RESP3 variants
- [ ] Collection-semantics-aware comparator (Set vs Array vs Hash ordering rules)
- [ ] EngineIdentity: `SUBJECT_IDENTITY_LABEL = "<port>"`, `REFERENCE_IDENTITY_LABEL = "redis-oracle"`
- [ ] Oracle preflight verifies: server version + protocol mode + persistence settings + module set + cluster mode

## Phase 4 — Golden capture
- [ ] RDB v11 byte-fixture corpus
- [ ] AOF transcript corpus
- [ ] Stream / consumer-group fixtures
- [ ] Three-tier: Tier 1 byte (RESP frames hashed), Tier 2 canonical (Set sorted), Tier 3 logical (key-value-equivalent)

## Phase 5 — Performance
- [ ] `comprehensive-bench` per-command-family scenarios: GET/SET, MGET/MSET, HASH ops, LIST ops, SET ops, SORTED SET ops, STREAM ops
- [ ] Pipeline depth axis: 1, 16, 64, 256
- [ ] Concurrency axis: 1, 2, 4, 8, 16, 64, 256 clients
- [ ] `release-perf` profile (see SQL checklist)
- [ ] `protocol_version_guard.txt` (analog of `concurrent_mode_default_guard.txt`) in every artifact lane
- [ ] `HotPathProfileSnapshot` counters: `resp_parse_time_ns, dict_probe_count, aof_flush_time_ns, rdb_serialize_time_ns, command_dispatch_time_ns, pubsub_deliver_time_ns, cluster_slot_resolve_time_ns, expiration_sweep_time_ns, replication_backlog_appends, client_io_eagain_count`
- [ ] Primary keep-gate score: per-command-family weighted RPS + p99 latency
- [ ] `.bench-history/comprehensive_bench.latest.json` committed

## Phase 6 — Conformance
- [ ] Oracle E2E per command family + edge cases (integer overflow, FP representation, error categories, NULL semantics, array ordering)
- [ ] Differential V2 envelope with command-trace canonicalization
- [ ] Metamorphic transforms: command-reordering equivalence (where order doesn't matter), GETSET ≡ SET+GET, etc.
- [ ] Mismatch minimizer with command-trace-preservation guard
- [ ] Insta snapshots: RESP frame byte sequences per command family
- [ ] RdbFaultVfs: partial AOF rewrites, mid-RDB torn writes, fsync-then-power-cut, `EAGAIN` storms on replication socket
- [ ] 6+ named crash boundaries: BeforeAofRewriteRename, DuringRdbWrite, BeforeReplicationOffsetUpdate, MidPsync, AfterReplOffsetBeforeAck, DuringFsync
- [ ] Differential fuzz against the reference parser (`fuzz_resp_parser`, `fuzz_command_dispatch`)
- [ ] E-processes on: RESP frames well-formed, PUBSUB ordering FIFO per subscriber, DEL idempotent within transaction

## Phase 7 — Surface
- [ ] FeatureUniverse covers all 241 Redis commands (per the pinned version's COMMAND COUNT)
- [ ] Per-module surface for any included module (RedisJSON, RedisSearch)
- [ ] Cluster surface (if `cluster_mode = true`): SLOT, NODE, MIGRATING, ASKING

## Phase 8 — Negative ledger
- [ ] AGENTS.md mandate with RESP-class failure terms: `event-loop changes, parser fast paths, allocator swaps, write coalescing, AOF batching, RDB codec changes`

## RESP-class extras
- [ ] Replication lag bench (if cluster_mode)
- [ ] Lua script execution differential (if Lua enabled)
- [ ] PUBSUB FIFO-per-subscriber regression test
