# Orchestration

How to fan a gauntlet run out across multiple agents without losing coherence, without colliding on shared resources, and without falling into communication purgatory.

The mental model: a **single orchestrator** with a stable run-ID drives the loop; per-phase **fan-out** assigns work to lane-specialized subagents (cc_1 / cc_2 / cc_3 / cc_4); coordination uses **MCP Agent Mail** thread IDs and **per-resource reservations** with TTLs; expensive work routes to `rch`-offloaded workers; the orchestrator and every subagent treat the **workspace markdown files as the single source of truth** so a compaction or model swap is recoverable.

---

## Orchestrator Role

A single orchestrator agent owns:
- The `<project>__gauntlet_workspace/` directory.
- The four hypothesis ledgers (`GAUNTLET_EXPERIMENT_DESIGNS.md`, `PERF_HYPOTHESIS_LEDGER.md`, `CONFORMANCE_HYPOTHESIS_LEDGER.md`, `SURFACE_PARITY_HYPOTHESIS_LEDGER.md`).
- The three negative-result ledgers (`docs/progress/perf-negative-results.md`, `conformance-negative-results.md`, `surface-deferrals.md`).
- Phase transitions (Phase 0 → 1 → … → 16).
- The convergence tracker: `scripts/convergence-tracker.sh` is the CI gate; the orchestrator runs it after every Phase 11 sub-round.

The orchestrator does **not** implement code. It dispatches work. The subagents implement.

Per phase, the orchestrator:
1. Reads the relevant subset of workspace files.
2. Computes which subagents need to fire (one per lane, one per crate, etc.).
3. Drops Agent Mail messages on the per-phase thread ID with task assignments.
4. Waits on a deadline (not a synchronous poll).
5. Aggregates results; updates ledgers; runs the convergence tracker; decides next phase.

---

## Lane Assignment: cc_1 / cc_2 / cc_3 / cc_4

The cc_N convention from FrankenSQLite. **Soft assignment by pillar**; agents may cross lanes, but stay-in-lane minimizes MCP Agent Mail reservation collisions and lets each agent build deep tool muscle-memory in one area.

| Lane | Primary responsibilities |
|---|---|
| **cc_1** | conformance / oracle / differential / metamorphic / fault / crash-boundary. Authors `*_oracle_e2e.rs` tests, wires the 30-line `scenario()` template, runs `oracle-runner`, populates `CONFORMANCE_HYPOTHESIS_LEDGER.md`. |
| **cc_2** | performance / benches / profile-cards / hot-path counters / regression detector. Authors `comprehensive_bench.rs` + focused benches, runs `samply` / `cargo-flamegraph` / `dhat`, populates `PERF_HYPOTHESIS_LEDGER.md`. |
| **cc_3** | surface parity / coverage / feature universe / invariant catalog. Authors `parity_taxonomy.rs`, the FeatureUniverse loader, the SurfaceMatrix, populates `SURFACE_PARITY_HYPOTHESIS_LEDGER.md`. |
| **cc_4** | fault / crash / soak / e-process / BOCPD / adversarial. Runs long-tail experiments under `rch`; long-running fuzz / miri / loom / shuttle / crash-boundary / BOCPD / e-process soak. |

When the orchestrator dispatches a "Phase 6 conformance test author" job, cc_1 gets the lock; cc_3 takes the surface-parity authoring; cc_4 takes the parallel fuzz/miri soak. Cross-lane fires are noted in the Agent Mail thread.

For tiny ports, the lanes collapse: solo runs use a single `cc_*` that wears all hats; pair runs split cc_1+cc_3 vs cc_2+cc_4.

---

## MCP Agent Mail Thread IDs

Convention: `gauntlet-<run-id>-<phase>-<bucket>`.

| Phase | Example thread IDs |
|---|---|
| Phase 0 | `gauntlet-r17-p0-bootstrap` |
| Phase 1 | `gauntlet-r17-p1-recon-crate-fsqlite-vdbe`, `gauntlet-r17-p1-recon-crate-fsqlite-wal`, … |
| Phase 5 | `gauntlet-r17-p5-bench-workload-readsingle`, `gauntlet-r17-p5-bench-workload-mvcc8`, … |
| Phase 6 | `gauntlet-r17-p6-conformance-null`, `gauntlet-r17-p6-conformance-groupby`, `gauntlet-r17-p6-metamorphic-predicate`, `gauntlet-r17-p6-fault-walfileappend`, `gauntlet-r17-p6-eprocess-inv3`, … |
| Phase 7 | `gauntlet-r17-p7-surface-pragma`, `gauntlet-r17-p7-surface-functions`, … |
| Phase 11 | `gauntlet-r17-p11-round-04-iteration-coordinator` |
| Phase 14 | `gauntlet-r17-p14-fresheyes-a`, `gauntlet-r17-p14-fresheyes-b`, `gauntlet-r17-p14-fresheyes-c` |
| Phase 15 | `gauntlet-r17-p15-soak-fuzz`, `gauntlet-r17-p15-soak-miri`, `gauntlet-r17-p15-soak-loom`, `gauntlet-r17-p15-soak-crash`, `gauntlet-r17-p15-soak-bocpd`, `gauntlet-r17-p15-soak-adversarial` |
| Phase 16 | `gauntlet-r17-p16-final` |

The `<run-id>` is the orchestrator's stable handle (e.g., `r17` for the 17th gauntlet run on this project; or `r17-rebase-3.53` for a rebase variant). The `<bucket>` segments the work for parallel resolution.

**Rule:** an Agent Mail message that names no recipient is a broadcast on the thread. A subagent that picks up the message reserves the lane (see Reservations below) and posts back with progress + artifact paths.

---

## Reservations

Reservations prevent two subagents from running `comprehensive-bench` on the same machine simultaneously (which would invalidate both runs). All reservations have TTLs.

| Reservation | Owner | Default TTL | Notes |
|---|---|---|---|
| `tool://comprehensive-bench` | cc_2 | 30 min | Single-machine exclusive; `rch`-offloaded runs use a separate reservation per worker. |
| `tool://oracle-runner` | cc_1 | 10 min | Multiple concurrent OK if they don't share fixture corpus; reserve per-fixture-set. |
| `tool://fuzz-corpus` | cc_1, cc_4 | 60 min | Concurrent reads OK; writes are exclusive. |
| `tool://golden-fixtures` | cc_1, cc_3 | 20 min | Reads concurrent; writes exclusive. |
| `tool://samply` | cc_2 | 15 min | Single perf-event capture at a time per machine. |
| `tool://cargo-flamegraph` | cc_2 | 15 min | Same — perf-event exclusive. |
| `resource://gpu-0` | cc_2, cc_4 | 60 min | Per-GPU exclusive for ML-class benches. |
| `resource://gpu-1` | cc_2, cc_4 | 60 min | Same. |
| `resource://rch-worker-pool` | all | 4 hr | Worker assignment from the pool; per-worker sub-reservations apply. |

**TTL semantics:** if a subagent crashes or stalls, the reservation auto-releases at TTL. The orchestrator does NOT wait synchronously; it checks the thread for a "done" post or for TTL expiry.

**Collision policy:** a subagent that attempts to reserve a busy slot posts to the thread with `BLOCKED_ON: <reservation>` and waits for a release notification (event-driven, not polled). The orchestrator can re-route to a different worker on `rch` if the wait is excessive.

---

## rch Offload Heuristic

> Anything >5 minutes wall time → `rch exec -- <command>`.

The cost discipline:
- A wasted 8-hour bench run is a real cost (worker electricity + delayed feedback loop + opportunity cost on other runs).
- A failed bench at hour 7 with no telemetry is a worse cost.
- Therefore: `rch` provides cost-controlled remote execution with structured telemetry; the orchestrator dispatches via `rch` for long jobs and gets back JSON results, not opaque text.

| Job type | Local OK? | rch recommended? |
|---|---|---|
| Single criterion microbench (<2 min) | yes | no |
| Full `comprehensive-bench` matrix (15-90 min) | only on idle host | **yes** |
| Multi-day fuzz / miri / loom / shuttle | no | **mandatory** |
| Crash-boundary soak (multi-thousand iter) | no | **mandatory** |
| BOCPD soak (multi-day parity stream) | no | **mandatory** |
| `oracle-runner` smoke (<10 min) | yes | no |
| `mt_mvcc_bench --threads=8` (5-30 min) | borderline | **yes** if host shared |

**Same-host vs cross-host:** the keep-gate "same minute" rule means the focused + broad gates must run on the **same physical host within the same minute**. This typically means: use `rch` to dispatch *one* worker which then runs both benches serially. Do not split focused-on-A / broad-on-B; the host-specific noise (allocator, scheduler, CPU pinning) is a third variable.

**Example invocation:**
```bash
rch exec --worker cargo-bench-worker-3 --timeout 90m -- \
  'cd /workspace && cargo bench --bench comprehensive_bench --profile release-perf -- --output-format json > /tmp/cb.json && \
   cargo bench --bench mt_mvcc --profile release-perf -- --threads=8 --iters=3 > /tmp/mt8.json'
```

---

## Compaction Survival

Models compact context. Subagent threads get re-rolled. A new agent picks up the thread. The orchestrator must be re-instantiable mid-run.

### Mechanism

- **Workspace markdown files are source of truth.** The four hypothesis ledgers + three negative ledgers + `phase0_project_class.json` + `phase16_*.md` artifacts are committed every transition.
- **Per-round artifact directory.** Each Phase-11 round creates `tests/artifacts/round-N/` with all per-bucket findings. A new orchestrator agent can re-derive convergence state by walking these directories.
- **Iteration coordinator subagent.** `subagents/iteration-coordinator.md` is the *dropping-back-in* entry point. Given a workspace path, it reads ledgers, finds the latest round number, counts open hypotheses, and tells the orchestrator what to do next.
- **No in-memory state.** The orchestrator persists every decision to a workspace file. If the orchestrator dies, the next instance reads the same files.

### Coordinator commands

```bash
# Drop back in to round-N / snapshot current state with the provided helper.
./scripts/gauntlet-status.sh <workspace> --json
# Outputs current phase files, convergence state, active reservations hints,
# and enough durable state for the iteration-coordinator to pick the next lane.
```

---

## Communication Purgatory Anti-Pattern

**Symptom:** agents wait on each other forever. cc_1 needs a result from cc_2's bench. cc_2 is reading cc_1's oracle output. Both stall.

**Fix:** deadline-based reservations + auto-release on TTL + event-driven thread updates.

### Specific rules

1. **Never synchronously poll another agent.** Drop a message on the thread, set a deadline, do other work, check for the reply at deadline.
2. **Every reservation has a TTL.** No infinite waits.
3. **The orchestrator can override a stalled reservation.** If cc_2 is at 90% of its TTL on `tool://comprehensive-bench` and has produced no progress message, the orchestrator pings the thread; if cc_2 doesn't respond within 2 minutes, the orchestrator force-releases and re-dispatches.
4. **Stalled subagents close gracefully.** Post a `BLOCKED` message with the blocker name; the orchestrator routes around.
5. **"I'm waiting on X" is logged.** Every wait writes to the round's blocker log; convergence-tracker sees the wait pattern.

---

## "Other Agents' Edits Are Normal" Doctrine

**Verbatim from FrankenSQLite AGENTS.md "Note for Codex/GPT-5.5" section (reconstructed from MINING-1 + the project's own AGENTS.md):**

> When you `git status` and see files modified that you didn't touch, the default assumption is: **another agent edited them**, not "the working tree is dirty and needs reset". Do not `git stash` other agents' work. Do not `git checkout -- <file>` to revert. Do not run `git reset --hard`. Treat unfamiliar changes as your own — read them, build on them, integrate.
>
> If you genuinely need to revert a change you suspect is wrong, post to the Agent Mail thread first with the file and the suspected wrong-ness, and wait for the author to defend or concede.
>
> The exception: if a file is fully blank, has a single line "WIP", or has a commit hash that doesn't resolve, it's a partial write from a crashed agent; safe to redo. Even then, post on the thread.

This doctrine is why the cc_N lane convention works: most edits stay in-lane, so a cross-lane edit is rare and worth a thread post.

---

## Orchestration Tiers

| Tier | Shape | Trigger criteria |
|---|---|---|
| **Solo** | 1 worker, serial phases | Tiny port (<5 crates, <50K LOC, <2 named workloads). |
| **Pair** | 2 workers, fan-out only on Phase 5+6 | Single-crate port, 2-pillar focus (e.g., perf + conformance only, surface deferred). |
| **Squad** | 4-6 workers, lane-assigned | Typical Rust port; multi-crate workspace; all three pillars in scope. |
| **Swarm** | 8-12+ workers, lane-assigned + beads-driven + multi-model triangulation on Phase 14 | Multi-crate workspace; certification bundle target; large reference (SQLite/Redis/PyTorch class). |

Concrete swarm composition for a typical Rust-port gauntlet run:
- 1 orchestrator
- 2 cc_1 (one for oracle E2E, one for metamorphic + fault)
- 2 cc_2 (one for bench authoring, one for hot-path counters + samply)
- 1 cc_3 (FeatureUniverse + InvariantCatalog)
- 2 cc_4 (one on fuzz + miri soak, one on loom + shuttle + BOCPD)
- 1-3 floaters for Phase 14 fresh-eyes (multi-model triangulation: Opus + Codex GPT-5 + Gemini)

Multi-model triangulation on Phase 14 is mandatory for certification-bundle target: three different model families reading the same code; calibration against `multi-model-triangulation` skill.

---

## See Also

- [SKILL-BOOTSTRAP.md](SKILL-BOOTSTRAP.md) — Phase 0.5 detail (jsm install, OAuth, inline fallbacks)
- [BEADS-HANDOFF.md](BEADS-HANDOFF.md) — Plan-to-beads + polish loop + dependency validation
- [../methodology/CONVERGENCE.md](../methodology/CONVERGENCE.md) — Convergence-tracker math
- [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) — Same-window discipline
- [../exemplars/EXEMPLARS.md](../exemplars/EXEMPLARS.md) — Rituals (the sequences of literal commands)
