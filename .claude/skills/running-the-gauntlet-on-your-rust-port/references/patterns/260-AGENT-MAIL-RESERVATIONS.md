# pattern:260-AGENT-MAIL-RESERVATIONS

## What

Parallel agents in the gauntlet (per the cc_1 / cc_2 / cc_3 / cc_4 lane convention) coordinate exclusive access to scarce or hot-loaded resources via **MCP Agent Mail reservations**. The reservation namespace is split into `tool://...` (transient code paths the agents drive, such as bench binaries and oracle runners) and `resource://...` (hardware or service capacity such as a GPU or the rch worker pool). Each reservation is tagged with a thread id of the form `gauntlet-<run-id>-<phase>-<bucket>` so that all messages about a single coordination concern collect in one thread. The pattern prevents collision (two agents running comprehensive-bench against the same target simultaneously) and enables auditability (every reservation has an owner agent and a TTL).

## Why

Failure mode prevented: *silent corruption from concurrent same-resource use*. Two agents that both reserve `tool://comprehensive-bench` and run it on the same target in the same minute will (a) thrash the host's CPU and produce noise in both runs, (b) write to `.bench-history/` in interleaved order, possibly losing one run, and (c) emit measurement results that violate the same-run-window keep-gate rule. The reservation system makes the conflict explicit at *request* time rather than discoverable at *artifact-comparison* time.

The secondary value: every reservation is a paper trail. "Who ran the bench at 14:32 on Tuesday?" has an answer (the agent that owned `tool://comprehensive-bench` in the thread `gauntlet-<run>-5-cc_2` at 14:32).

## Where in the gauntlet

- `SKILL.md` Parallelism Model section — names the reservations and the thread-id convention
- `[orchestration/ORCHESTRATION.md](../orchestration/ORCHESTRATION.md)` — full coordination protocol
- `/agent-mail` skill — the underlying MCP server and reservation lease model

## Verbatim reservation namespace

```
tool://comprehensive-bench    — the comprehensive_bench binary; exclusive use of host CPU
tool://oracle-runner          — the oracle E2E suite runner; exclusive use of oracle subprocess + fixtures
tool://fuzz-corpus            — exclusive write access to the fuzz corpus directory
tool://golden-fixtures        — exclusive write access to the golden-artifact directory
resource://gpu-0              — exclusive use of GPU device 0 (and gpu-N for N > 0)
resource://rch-worker-pool    — exclusive use of an rch worker slot
```

Additional per-class reservations:

| Class | Add |
|---|---|
| SQL | `tool://mt-mvcc-bench`, `tool://swarm-multiprocess`, `resource://wal-fixture-disk` |
| RESP | `tool://respfuzz`, `resource://redis-port-6379`, `resource://aof-fixture-disk` |
| Numerical | `resource://blas-thread-pool`, `resource://numpy-oracle-interpreter` |
| ML | `resource://gpu-0` … `resource://gpu-N`, `resource://distributed-rendezvous-port` |
| HTTP | `resource://http-port-8080`, `tool://wrk2-load-generator`, `resource://oha-worker` |

## Thread id convention

```
gauntlet-<run-id>-<phase>-<bucket>
```

Where:
- `<run-id>` is the run-identity stack's `run_id` (so all coordination for a single gauntlet run aggregates).
- `<phase>` is the 16-phase phase number (e.g., `5` for performance harness, `15` for soak).
- `<bucket>` is a per-phase shard / workload / bucket name (e.g., `wal-heavy-oltp`, `bucket-A`, `cc_2`).

Examples:
- `gauntlet-bd-foo-2026-05-22-14:32-1234-5-wal-heavy-oltp` — Phase 5 coordination for the wal-heavy-oltp bench bucket.
- `gauntlet-bd-foo-2026-05-22-14:32-1234-6-metamorphic-predicate` — Phase 6 coordination for the Predicate metamorphic family.

## cc_N lane convention

Per `SKILL.md` Parallelism Model:

```
cc_1 → conformance / oracle / differential / metamorphic / fault / crash-boundary
cc_2 → performance / benches / profile-cards / hot-path counters / regression detector
cc_3 → surface parity / coverage / feature universe / invariant catalog
cc_4 → fault / crash / soak / e-process / BOCPD / adversarial search
```

Soft assignment by pillar. Agents may cross lanes when work demands, but stay-in-lane minimizes reservation collisions (cc_2 owns `tool://comprehensive-bench`; cc_4 owns `resource://rch-worker-pool` for soaks; cc_1 owns `tool://oracle-runner`).

## TTL conventions per reservation type

| Reservation | Typical TTL | Renewal behavior |
|---|---|---|
| `tool://comprehensive-bench` | 90 min | extend on heartbeat; auto-release on session end |
| `tool://oracle-runner` | 30 min | extend on heartbeat |
| `tool://fuzz-corpus` | per-write critical section (seconds) | not renewed; held only during write |
| `tool://golden-fixtures` | per-capture (≤5 min) | not renewed |
| `resource://gpu-0` | 4 hr | extend; longest TTL because ML jobs are long |
| `resource://rch-worker-pool` | per-job (matches rch job estimate) | reservation released on `rch wait` return |

Rule of thumb: TTL should approximate the 99th-percentile wall time of the operation. Too short causes false-loss thrashing; too long blocks other agents on dead reservations.

## Composition

- Pairs with [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) — thread ids embed the run_id; reservation metadata is a side artifact of the run.
- Pairs with [pattern:255-RCH-OFFLOAD-DISCIPLINE](255-RCH-OFFLOAD-DISCIPLINE.md) — `resource://rch-worker-pool` is the reservation; rch is the dispatcher.
- Pairs with [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — same-minute focused + broad measurements need a single agent holding `tool://comprehensive-bench` for the duration of both.
- Pairs with the `/agent-mail` skill for the lease primitives, thread search, and dead-letter handling.

## Pitfalls

- **Reservation without TTL.** Eventually leaks; future agents see "held forever" and either bypass (defeats the system) or block (deadlock). Every reservation needs a wall-clock TTL.
- **Thread id without `<run-id>`.** Coordination from two distinct gauntlet runs collides in the same thread. The id format is load-bearing.
- **cc_N lane assignment ignored.** Two agents both think they're cc_2; both grab `tool://comprehensive-bench`; one wins, the other blocks unnecessarily. The lane convention is the *soft* allocation that prevents the *hard* reservation contention.
- **Polling the reservation status synchronously.** The whole point of MCP Agent Mail is async coordination; treating reservations as a sync lock acquisition loop defeats it.
- **Releasing a reservation that another agent is waiting on without notification.** Other agents may be blocked on the resource; the release should post to the thread.
- **Per-class trap (ML): two agents both claim `resource://gpu-0` because they didn't check the per-class reservation table.** The agent must inspect the class router output before requesting.
- **Per-class trap (HTTP): `resource://http-port-8080` is host-local but cross-process; the reservation system must be configured per-host, not global.**
- **Reservation held during interactive editorial work.** If cc_2 holds `tool://comprehensive-bench` while authoring a bead, no other agent can run perf — but no perf is running on the host. Release between dispatches; reacquire on next run.
- **Treating the reservation as a substitute for the keep-gate rule.** The reservation prevents *concurrent* same-bench runs; the keep-gate rule constrains *sequential* same-run-window measurement. Both are needed.
- **Forgetting the `tool://` vs `resource://` distinction.** `tool://` is a code path; `resource://` is a capacity. Mixing them produces unclear coordination semantics. Pick the right namespace.
