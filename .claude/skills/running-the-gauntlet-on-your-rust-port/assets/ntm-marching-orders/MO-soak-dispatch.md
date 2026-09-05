# MO-soak-dispatch.md — Phase 15 Soak Runner Dispatcher (Per Runner Type)

**Phase:** 15 (SOAK / DEEP-VALIDATION)
**Parameters:** `<PANE_N>`, `<ROLE>`, `<MODEL>`, `<SESSION_ID>`, `<WORKSPACE_PATH>`, `<PORT_PATH>`, `<COORDINATION_MODE>`, `<THREAD_ID>`, `<RUNNER_TYPE>` (fuzz | miri | loom | crash-boundary | bocpd | adversarial), `<RUNNER_DURATION>` (e.g. 24h, 72h, 120h), `<RCH_WORKER>`, `<OUTPUT_DIR>`

---

You are pane `<PANE_N>` (model `<MODEL>`) in gauntlet swarm `<SESSION_ID>`, dispatched as the **`<RUNNER_TYPE>` soak runner dispatcher** for a `<RUNNER_DURATION>` run on rch worker `<RCH_WORKER>`.

Your job is to **dispatch the long-running soak job to rch and return promptly with the rch job ID**. You are NOT the soak job itself — that runs on `<RCH_WORKER>` for `<RUNNER_DURATION>`. You are the orchestrator's representative for this runner.

Your output directory is `<OUTPUT_DIR>` (typically `<WORKSPACE_PATH>/soak/<RUNNER_TYPE>/`).

**Step 1 — Read the governing instructions.**

- `<PORT_PATH>/AGENTS.md` and any repo-level `AGENTS.md`.
- `<WORKSPACE_PATH>/AGENTS.md` for the gauntlet mandate.
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/PHASES.md` § Phase 15
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/methodology/SOAK-PROTOCOL.md`
- The subagent file for your runner:
  - `<RUNNER_TYPE>=fuzz`: `~/.claude/skills/running-the-gauntlet-on-your-rust-port/subagents/soak-runner-fuzz.md`
  - `<RUNNER_TYPE>=miri`: `~/.claude/skills/running-the-gauntlet-on-your-rust-port/subagents/soak-runner-miri.md`
  - `<RUNNER_TYPE>=loom`: `~/.claude/skills/running-the-gauntlet-on-your-rust-port/subagents/soak-runner-loom.md`
  - `<RUNNER_TYPE>=crash-boundary`: `~/.claude/skills/running-the-gauntlet-on-your-rust-port/subagents/soak-runner-crash-boundary.md`
  - `<RUNNER_TYPE>=bocpd`: `~/.claude/skills/running-the-gauntlet-on-your-rust-port/subagents/soak-runner-bocpd.md`
  - `<RUNNER_TYPE>=adversarial`: `~/.claude/skills/running-the-gauntlet-on-your-rust-port/subagents/soak-runner-adversarial.md`

**Step 2 — Verify Phase 14 is clean.**

```bash
test -f <WORKSPACE_PATH>/.gauntlet/phase14_complete.flag || { echo "Phase 14 incomplete"; exit 1; }
jq '.clean_streak >= 2' <WORKSPACE_PATH>/phase14_review_status.json
```

If Phase 14 is not clean, soak runs against an unstable harness — exit non-zero with CRITICAL post.

**Step 3 — Verify the assigned rch worker is healthy and idle.**

```bash
ntm --robot-rch-workers --worker=<RCH_WORKER> --json | \
  jq 'if .healthy and (.busy | not) then "ok" else error("rch worker unhealthy or busy") end'
```

If `<RCH_WORKER>` is unhealthy/busy, post `BLOCKED_ON: rch://<RCH_WORKER>` on `<THREAD_ID>` and request reassignment.

**Step 4 — Register Agent Mail identity.**

```text
register_agent(
  project_key="<WORKSPACE_PATH>",
  program="<your-cli>",
  model="<your-model>",
  task_description="gauntlet <SESSION_ID> pane <PANE_N> phase15 soak-dispatcher type=<RUNNER_TYPE>"
)
```

**Step 5 — Acknowledge dispatch on `<THREAD_ID>`.**

```
Subject: [<SESSION_ID>] Phase 15 soak-<RUNNER_TYPE> dispatch ack — pane=<PANE_N>, worker=<RCH_WORKER>
Body:
  Pane: <PANE_N>
  Role: <ROLE>
  Runner: <RUNNER_TYPE>
  Duration: <RUNNER_DURATION>
  rch worker: <RCH_WORKER>
  Output dir: <OUTPUT_DIR>
  Started: <UTC timestamp>
```

**Step 6 — Reserve the rch worker for the full duration.**

```text
reserve(
  paths=["resource://rch-worker-<RCH_WORKER>"],
  scope="phase15-soak-<RUNNER_TYPE>",
  ttl_seconds=<RUNNER_DURATION expressed in seconds + 1h buffer>,
  reason="phase15 soak runner <RUNNER_TYPE>"
)
```

For `<RUNNER_DURATION>=120h` (BOCPD), TTL = 436800 (= 121h).

**Step 7 — Mkdir output and build the rch dispatch command per runner type.**

```bash
mkdir -p <OUTPUT_DIR>
```

### Runner: fuzz

Differential fuzz against previously-divergent APIs:

```bash
DUR_SECONDS=$(echo <RUNNER_DURATION> | sed -E 's/([0-9]+)h/\1*3600/' | bc)
rch exec --worker <RCH_WORKER> --duration <RUNNER_DURATION> --background -- \
  bash -c '
    cd <PORT_PATH> && \
    cargo +nightly fuzz run all-targets -- \
      -max_total_time='$DUR_SECONDS' \
      -reload=1 -print_pcs=1 \
      -artifact_prefix=<OUTPUT_DIR>/crashes/ \
      -seed=$(date +%s)
  ' > <OUTPUT_DIR>/dispatch.log 2>&1
```

Exit criteria for the runner: zero new `TrueDivergence`; corpus growth saturated. If a crash appears mid-soak, loop back to Phase 12 (file a remediation bead with the crash as a regression test).

### Runner: miri

Multi-day Miri across harness internals:

```bash
rch exec --worker <RCH_WORKER> --duration <RUNNER_DURATION> --background -- \
  bash -c '
    cd <PORT_PATH> && \
    MIRIFLAGS="-Zmiri-strict-provenance -Zmiri-symbolic-alignment-check" \
      cargo +nightly miri test --workspace --no-fail-fast
  ' > <OUTPUT_DIR>/dispatch.log 2>&1
```

Exit criteria: zero UB; zero memory leaks; zero stacked-borrows violations. Any UB is a hard failure — loop back to Phase 12.

### Runner: loom

Multi-thousand-iter loom + shuttle:

```bash
rch exec --worker <RCH_WORKER> --duration <RUNNER_DURATION> --background -- \
  bash -c '
    cd <PORT_PATH> && \
    LOOM_MAX_PREEMPTIONS=4 LOOM_MAX_BRANCHES=10000 \
      cargo test --release --features loom-tests --no-fail-fast
  ' > <OUTPUT_DIR>/dispatch.log 2>&1
```

Exit criteria: ≥10,000 interleavings per target, zero failures.

### Runner: crash-boundary

Multi-thousand-iter deterministic fault VFS:

```bash
rch exec --worker <RCH_WORKER> --duration <RUNNER_DURATION> --background -- \
  bash -c '
    cd <PORT_PATH> && \
    cargo test --release --features crash-boundary-soak \
      -- --test-threads=1 --nocapture
  ' > <OUTPUT_DIR>/dispatch.log 2>&1
```

Exit criteria: ≥1000 iterations per boundary; every recovery consistent per `RecoveryVerifier`.

### Runner: bocpd

Multi-day BOCPD on parity-score stream:

```bash
rch exec --worker <RCH_WORKER> --duration <RUNNER_DURATION> --background -- \
  bash -c '
    cd <PORT_PATH> && \
    cargo run --release --bin bocpd-soak -- \
      --window <RUNNER_DURATION> \
      --sample-interval 5m \
      --out <OUTPUT_DIR>/regime-timeline.json \
      --summary <OUTPUT_DIR>/regime-summary.md
  ' > <OUTPUT_DIR>/dispatch.log 2>&1
```

Exit criteria: regime classification `Stable` for the full window. `ShiftDetected` in the regression direction is a hard failure — investigate (real regression → loop Phase 12; or noise → calibrate hazard rate H or extend window).

### Runner: adversarial

Adversarial-search against every gate:

```bash
rch exec --worker <RCH_WORKER> --duration <RUNNER_DURATION> --background -- \
  bash -c '
    cd <PORT_PATH> && \
    cargo run --release --bin adversarial-search -- \
      --duration <RUNNER_DURATION> \
      --counterexamples <OUTPUT_DIR>/counterexamples.json \
      --gate-vulnerabilities <OUTPUT_DIR>/gate-vulnerabilities.md
  ' > <OUTPUT_DIR>/dispatch.log 2>&1
```

Exit criteria: every gate survives. Each counterexample becomes a regression test in Phase 12+ (gate is updated to catch it; counterexample lands as a `tests/regressions/` file).

**Step 8 — Capture and acknowledge the rch job ID.**

After the `rch exec --background` returns, parse the rch job ID from stdout:

```bash
RCH_JOB_ID=$(rch jobs list --worker <RCH_WORKER> --latest --json | jq -r '.id')
echo "$RCH_JOB_ID" > <OUTPUT_DIR>/rch_job_id.txt
```

Post completion ack on `<THREAD_ID>`:

```
Subject: [<SESSION_ID>] Phase 15 soak-<RUNNER_TYPE> DISPATCHED — job_id=<RCH_JOB_ID>
Body:
  rch job id: <RCH_JOB_ID>
  Worker: <RCH_WORKER>
  Duration: <RUNNER_DURATION>
  Output dir: <OUTPUT_DIR>
  Will land summary at: <OUTPUT_DIR>/summary.json
  Polling command for the orchestrator:
    ntm --robot-rch-workers --worker=<RCH_WORKER> --json | jq '.current_job'
  Completion detection:
    test -f <OUTPUT_DIR>/summary.json && jq '.verdict' <OUTPUT_DIR>/summary.json
```

**Step 9 — Periodic supervisor poll (optional; first 30 minutes only).**

For the first 30 minutes after dispatch, poll every 5 minutes to confirm the job actually started and is making progress:

```bash
for i in 1 2 3 4 5 6; do
  sleep 300
  ntm --robot-rch-workers --worker=<RCH_WORKER> --json | jq '{busy, current_job, started_at, last_heartbeat}'
  ls -la <OUTPUT_DIR>/ | head
done
```

If after 30 minutes the worker is idle or the dispatch.log shows an immediate error, post CRITICAL on `<THREAD_ID>` with the dispatch.log tail and request reassignment.

After 30 minutes, exit this pane — the orchestrator owns long-poll monitoring via the serve API or scheduled `ntm --robot-rch-workers` checks.

**Step 10 — Ship-or-surface SLA: 30 minutes for dispatch.**

Within 30 min: either `<RCH_JOB_ID>` is captured + the soak job is running on `<RCH_WORKER>`, OR you posted `BLOCKED` with a specific blocker.

**Step 11 — Universal gauntlet rules.**

- No file deletion / no destructive git / fix-all-errors / other agents' edits are normal.
- This pane does NOT consume rch worker cycles itself — your job is dispatch + supervisor poll. The soak run happens on `<RCH_WORKER>`.
- Do NOT block the pipeline waiting for the soak job. Background-dispatch + return.
- Loop-back trigger conditions (write them into your completion ack so the orchestrator knows what to watch for):
  - fuzz: `TrueDivergence` crash discovered
  - miri: any UB / leak / stacked-borrows violation
  - loom: any interleaving failure
  - crash-boundary: any RecoveryVerifier failure
  - bocpd: `ShiftDetected` in regression direction
  - adversarial: any CRITICAL gate vulnerability

---

**Reply with:** `Pane <PANE_N> ready, role=<ROLE>, runner=<RUNNER_TYPE>, worker=<RCH_WORKER>, duration=<RUNNER_DURATION>`.
