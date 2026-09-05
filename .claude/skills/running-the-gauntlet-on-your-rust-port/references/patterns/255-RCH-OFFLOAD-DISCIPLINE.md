# pattern:255-RCH-OFFLOAD-DISCIPLINE

## What

Anything that takes **>5 minutes of wall-time** is offloaded to `rch exec --`. The full `comprehensive-bench` matrix, multi-day Miri / sanitizer runs, fuzz campaigns, loom / shuttle sweeps, multi-thousand-iter crash-boundary suites, multi-day BOCPD soaks — all of these have wall-time outside the interactive session budget. They are dispatched as `rch exec --` jobs that run on a remote worker pool, return their artifacts via `rch sync`, and emit completion telemetry the agent can poll without blocking the session. The *interactive* part of the gauntlet (planning, profile inspection, ledger maintenance, bead authoring) stays local; the *expensive* part is offloaded.

## Why

Failure mode prevented: *the agent that watches a 6-hour bench finish*. Sessions have token budgets; the agent that spends them on `cargo bench --bench comprehensive_bench` blocking on the loop has wasted them. Worse, a session timeout mid-bench produces an unreplayable failure; the rch job's artifact survives the session, with full run-identity stack.

There is a secondary discipline reason: **wasted compute is real cost**. An 8-hour bench that turned out to be running with the wrong PRAGMA or wrong fixture is 8 hours of host time gone. The pre-flight (oracle preflight doctor + concurrent-mode guard + fixture hash) MUST run locally before the rch job dispatches, precisely so the expensive part doesn't run against a misconfigured baseline.

## Where in the gauntlet

- `SKILL.md` Up-Front Confirmations §5: "Local vs `rch`-offloaded heavy passes? Recommend `rch` for anything >5 minutes wall time"
- `scripts/run-soak-campaign.sh` — dispatches long-running fuzz/miri/loom/shuttle/crash-boundary/BOCPD/e-process to rch
- The 16-phase pipeline: Phase 5 (perf), Phase 6 (conformance), Phase 11 (iterate), Phase 15 (soak) are the heavy phases
- `[orchestration/ORCHESTRATION.md § rch offload heuristic](../orchestration/ORCHESTRATION.md)`

## The >5-minute rule

| Task | Wall-time | Locality |
|---|---|---|
| `cargo test -p <crate>` (single crate) | seconds | local |
| `cargo bench --bench <one>` quick | < 5 min | local |
| Oracle preflight doctor | < 1 min | local (REQUIRED local — never offload pre-flight) |
| `comprehensive-bench` full matrix | 30 min – 2 h | **rch** |
| `mt-mvcc-bench` full sweep | 15 min – 1 h | **rch** |
| `swarm_multiprocess` 60s × 8 children × iters | 30 min – 2 h | **rch** |
| Miri across harness internals | hours – days | **rch** |
| 24h fuzz against differential APIs | 24 h | **rch** |
| Loom / shuttle multi-thousand-iter | hours – days | **rch** |
| Crash-boundary fault VFS multi-thousand-iter | hours – days | **rch** |
| BOCPD soak on parity-score stream | days | **rch** |
| Adversarial-search against every gate | hours – days | **rch** |

## Same-host vs cross-host concerns

The keep-gate rule "same minute" (MINING-1 §1: "same git state, same `target/`, same machine, same minute") means the focused + broad gate measurements *must run on the same physical host*. Therefore:

- The `comprehensive-bench` + the targeted focused bench → **one rch job, single host**. Don't split across two workers; the ratio diff would be confounded by host-to-host variability.
- Soak runs (fuzz, miri, loom, shuttle) are *single-result* artifacts and CAN cross hosts; the artifact's content-address `artifact_id` (K-11) is the join key, not the host.
- Conformance baselines that produce per-machine fingerprints (e.g., `truncate_score`-rounded scorecards) are cross-host *iff* the truncation has been applied and the platform fingerprint is recorded.

The shorthand: **keep-gate measurements are same-host single-job; soaks and conformance ratchets are cross-host with content-address join.**

## When NOT to offload

- **Preflight doctor.** The point of preflight is to refuse to dispatch when the host config is wrong. Running it on the rch worker just postpones the failure.
- **Bead authoring / ledger writes / commit creation.** These are interactive editorial tasks; rch's value is wall-time offload, not editorial offload.
- **Profile inspection (samply / flamegraph viewing).** The artifact comes back from rch; opening it is local.
- **Anything under 5 minutes.** rch dispatch + sync overhead exceeds the savings; just run it local.
- **Anything where the artifact must be written to the workspace within the session.** If a downstream phase needs the result before the session ends, choose between (a) waiting locally or (b) splitting into two sessions joined by the rch job id.

## Composition

- Pairs with [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) — every rch job's outputs embed the full stack; the join key after the job returns is `run_id`.
- Pairs with [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — same-minute focused + broad → one rch invocation that runs both back-to-back on one host.
- Pairs with [pattern:260-AGENT-MAIL-RESERVATIONS](260-AGENT-MAIL-RESERVATIONS.md) — long rch jobs reserve `resource://rch-worker-pool` and `tool://comprehensive-bench` against parallel agents.
- Pairs with the `/rch` skill — for routing, worker selection, dispatch ergonomics, telemetry conventions.

## Pitfalls

- **Offloading the preflight doctor.** Defeats the purpose. Preflight is the cheap fail-fast; if it can't run locally, the local env is broken and the rch dispatch is doomed.
- **Splitting a same-run-window measurement across two rch hosts.** Confounds the ratio with host variance. Two benches whose results must be compared go in one job.
- **Forgetting to capture the rch job id in the gauntlet workspace.** The job's artifact may be retrievable later, but without the id the agent has to grep the worker pool. Store the id in the run-identity stack.
- **Polling the rch job synchronously.** Defeats the offload; the session blocks on the poll loop. Use `rch wait` with a high timeout or fire-and-forget with a check-on-next-tick pattern.
- **Treating rch as "background mode for cargo bench."** It's a separate execution context with a separate environment, separate cargo cache, separate target/ directory. The reproduction has to be explicit.
- **Offloading a job that depends on host-local fixtures not synced.** `rch sync` is required before dispatch for fixtures that aren't in the repo; or, store fixtures content-addressed in a shared location.
- **Per-class trap (ML): GPU jobs to rch workers that don't have the right CUDA version.** The worker selector must match on GPU capability; defaulting to "any worker" produces a CPU-only run that times out the GPU bench.
- **Per-class trap (HTTP): wrk2/oha load generators run on the rch worker, target the local subject — the network hop confounds latency.** Either run the load generator on the same worker as the subject or measure with explicit network-loopback baseline.
