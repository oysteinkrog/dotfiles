# NTM Quickstart — Run the Gauntlet in 5 Commands

You have:
- A Rust port at `/data/projects/<port>` (e.g. `/data/projects/frankensqlite`).
- NTM installed (`ntm deps -v` shows green).
- `NTM_PROJECTS_BASE` set to `/data/projects/` so `ntm spawn <port>` resolves the directory.
- (Optional but recommended) `rch` available for >5 min jobs.

This is the 5-command happy path that gets you from "fresh checkout" to "gauntlet running". For the full integration contract, see [NTM-INTEGRATION.md](NTM-INTEGRATION.md). For deeper NTM mechanics, see `~/.claude/skills/ntm/SKILL.md`.

---

## The 5 commands

### 1. Bootstrap the workspace

```bash
~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/init-workspace.sh \
  /data/projects/<port> \
  /data/projects/<port>__gauntlet_workspace
```

This creates `<port>__gauntlet_workspace/` as a sibling of your port, `git init`s it, drops the AGENTS.md mandate paragraph, seeds the three negative-result ledgers, and writes the version-contract skeleton. Idempotent — safe to re-run.

### 2. Spawn the cc_N labeled sessions

For T3+ (squad / swarm), four labeled sessions, one per lane:

```bash
PORT=<port>     # e.g. frankensqlite, frankenredis, franken_numpy
ntm spawn $PORT --label conformance --cc=3 --cod=1 --stagger-mode=smart --no-user
ntm spawn $PORT --label perf        --cc=2 --cod=2 --stagger-mode=smart --no-user
ntm spawn $PORT --label surface     --cc=2 --gmi=1 --stagger-mode=smart --no-user
ntm spawn $PORT --label soak        --cc=2 --cod=1 --gmi=1 --stagger-mode=smart --no-user
```

For T1/T2 (solo / pair) collapse into one session:

```bash
ntm spawn $PORT --cc=2 --cod=1 --gmi=1 --no-user --stagger-mode=smart
```

Verify with `ntm list --project $PORT` — should show 4 sessions (or 1 for solo).

### 3. Run Phase 0 (bootstrap + project class detect + oracle preflight)

```bash
ntm --robot-send=${PORT}--surface --panes=2 --type=cc --msg="$(cat <<'EOF'
You are pane 2 (cc_3 surface lane) doing Phase 0 bootstrap.

Read these in order:
  1. /data/projects/<port>__gauntlet_workspace/AGENTS.md
  2. ~/.claude/skills/running-the-gauntlet-on-your-rust-port/SKILL.md
  3. ~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/PHASES.md § Phase 0

Then run, in order:
  ~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/install-toolchain.sh --workspace /data/projects/<port>__gauntlet_workspace
  ~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/detect-project-class.sh /data/projects/<port> --workspace /data/projects/<port>__gauntlet_workspace
  ~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/check-skills.sh /data/projects/<port>__gauntlet_workspace
  ~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/oracle-preflight-doctor.sh /data/projects/<port> --workspace /data/projects/<port>__gauntlet_workspace

Exit criteria:
  /data/projects/<port>__gauntlet_workspace/phase0_oracle_preflight.json.aggregate_outcome == "green"
  /data/projects/<port>__gauntlet_workspace/phase0_project_class.json.confidence >= 0.8
  mkdir -p /data/projects/<port>__gauntlet_workspace/.gauntlet
  touch /data/projects/<port>__gauntlet_workspace/.gauntlet/phase0_complete.flag

When done, reply "Phase 0 complete; class=<class>; preflight=green".
EOF
)"
```

Wait for the pane to settle:

```bash
ntm --robot-wait=${PORT}--surface --wait-until=idle --timeout=30m
```

### 4. Run Phases 1–10 via the per-phase pipelines

Once Phase 0 is green, dispatch the phase pipelines in order. For each phase, the orchestrator (you, or the `ntm-orchestrator` subagent) does:

```bash
# Get the reference version + project class out of phase0 outputs
WS=/data/projects/${PORT}__gauntlet_workspace
TARGET=/data/projects/${PORT}
REF=$(awk -F\" '/^version =/ {print $2; exit}' "$WS"/docs/contracts/*_version_contract.toml 2>/dev/null || echo UNPINNED)
CLASS=$(jq -r '.detected_class' $WS/phase0_project_class.json)
RUN_ID=r$(date +%Y%m%d-%H%M%S)-$(cd $TARGET && git rev-parse --short HEAD)

# Phase 1 RECON (per-crate fan-out)
CRATE_LIST=$(ls $TARGET/crates/ | tr '\n' ',' | sed 's/,$//')
ntm pipeline run ~/.claude/skills/running-the-gauntlet-on-your-rust-port/assets/ntm-pipelines/gauntlet-phase-01-recon.yaml \
  --session ${PORT}--surface \
  --var workspace_path=$WS --var port_path=$TARGET --var run_id=$RUN_ID \
  --var crate_list="$CRATE_LIST" --var session_name=${PORT}--surface \
  --var reference_version=$REF \
  --background

# Phase 3 Oracle wiring
ntm pipeline run ~/.claude/skills/running-the-gauntlet-on-your-rust-port/assets/ntm-pipelines/gauntlet-phase-03-oracle-wiring.yaml \
  --session ${PORT}--conformance \
  --var workspace_path=$WS --var port_path=$TARGET --var run_id=$RUN_ID \
  --var session_name=${PORT}--conformance \
  --var project_class=$CLASS --var reference_version=$REF \
  --background

# Phase 6 Conformance harness
ntm pipeline run ~/.claude/skills/running-the-gauntlet-on-your-rust-port/assets/ntm-pipelines/gauntlet-phase-06-conformance-harness.yaml \
  --session ${PORT}--conformance \
  --var workspace_path=$WS --var port_path=$TARGET --var run_id=$RUN_ID \
  --var session_name=${PORT}--conformance \
  --var project_class=$CLASS \
  --var behavior_classes="null-semantics,three-valued-logic,group-by-having,recursive-cte,..." \
  --var fault_kinds="TornWrite,PartialWrite,PowerCut,IoError,ReadFailure,WriteFailure,Latency,DiskFull" \
  --var crash_boundaries="BeforeWalHeaderWrite,...,AfterCheckpoint" \
  --var fuzz_targets="sql_fuzz,resp_fuzz,..." \
  --var invariants="INV-1,INV-2,INV-3,INV-4,INV-5" \
  --background

# Phase 9 Baseline (three pillars in parallel)
ntm pipeline run ~/.claude/skills/running-the-gauntlet-on-your-rust-port/assets/ntm-pipelines/gauntlet-phase-09-baseline.yaml \
  --session ${PORT}--perf \
  --var workspace_path=$WS --var port_path=$TARGET --var run_id=$RUN_ID \
  --var session_name=${PORT}--perf \
  --var project_class=$CLASS --var reference_version=$REF \
  --var rch_worker=cargo-bench-worker-3 \
  --background
```

(Phases 2, 4, 5, 7, 8, 10 are one-shot sends; the orchestrator subagent does these automatically — see `subagents/ntm-orchestrator.md`.)

### 5. Run Phases 11 (iterate to convergence), 14 (fresh eyes), 15 (soak)

These are the heavy phases — they run for days. Use `--background` and poll via `ntm pipeline status`.

```bash
# Phase 11 — iterate until converged (>=10 rounds, >=2 clean, 0 open hypotheses)
ntm pipeline run ~/.claude/skills/running-the-gauntlet-on-your-rust-port/assets/ntm-pipelines/gauntlet-phase-11-iterate.yaml \
  --session ${PORT}--perf \
  --var workspace_path=$WS --var port_path=$TARGET --var run_id=$RUN_ID \
  --var session_name=${PORT}--perf \
  --var project_class=$CLASS --var reference_version=$REF \
  --var max_rounds=20 --var min_rounds=10 \
  --var rch_worker=cargo-bench-worker-3 \
  --background

# Phase 14 — 3 reviewers (+ triangulator + red-team for T3+) per round
ntm pipeline run ~/.claude/skills/running-the-gauntlet-on-your-rust-port/assets/ntm-pipelines/gauntlet-phase-14-fresh-eyes.yaml \
  --session ${PORT}--conformance \
  --var workspace_path=$WS --var port_path=$TARGET --var run_id=$RUN_ID \
  --var session_name=${PORT}--conformance \
  --var tier=T4 --var max_rounds=6 \
  --background

# Phase 15 — 6 soak runners (24h-120h) to rch
ntm pipeline run ~/.claude/skills/running-the-gauntlet-on-your-rust-port/assets/ntm-pipelines/gauntlet-phase-15-soak.yaml \
  --session ${PORT}--soak \
  --var workspace_path=$WS --var port_path=$TARGET --var run_id=$RUN_ID \
  --var session_name=${PORT}--soak \
  --var project_class=$CLASS \
  --var rch_worker_pool="soak-fuzz,soak-miri,soak-loom,soak-crash,soak-bocpd,soak-adversarial" \
  --background
```

---

## Where to look for live state

| You want to know | Command |
|---|---|
| What's NTM doing right now across all sessions | `ntm --robot-snapshot --robot-format=toon` |
| Which panes are working vs idle vs stuck | `ntm activity --watch --interval 5000` (human) or `ntm --robot-is-working=<session>` (script) |
| Tail of pane 2 in the perf session (50 lines) | `ntm --robot-tail=${PORT}--perf --panes=2 --lines=50` |
| Status of all in-flight pipelines | `ntm pipeline list --json | jq '.runs[] | {id, state, started}'` |
| One specific pipeline | `ntm pipeline status <run-id> --json` |
| Which rate-limited panes need rotation | `ntm --robot-health-oauth=${PORT}--<lane> --json | jq '.panes[] | select(.rate_limited)'` |
| Per-phase artifact landing | `ls -la $WS/phase*.md $WS/.gauntlet/*.flag` |
| Convergence state (Phase 11) | `jq '{round_count, last_two_findings, clean_last_two, open_hypothesis_count, converged}' $WS/reports/convergence_tracker.json` |
| Soak job liveness (Phase 15) | `ntm --robot-rch-workers --json | jq '.workers[] | {name, busy, current_job, last_heartbeat}'` |

---

## How to attach to a pane mid-run for inspection

NTM panes are live tmux sessions. To attach:

```bash
ntm attach ${PORT}--conformance      # opens the labeled session
# Or directly with tmux:
tmux attach -t ${PORT}--conformance
```

To **observe without attaching** (read-only), use the robot surface:

```bash
ntm --robot-tail=${PORT}--conformance --panes=2 --lines=200
ntm --robot-inspect-pane=${PORT}--conformance --inspect-index=2 --inspect-lines=200 --inspect-code
```

> **Never call `ntm view` from automation** — it retiles the operator's tmux layout and returns nothing useful. Use `--robot-tail` / `--robot-inspect-pane` from scripts.

To **detach from a tmux session you attached to**: `Ctrl-b d`.

---

## Common first-run gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `ntm spawn` errors "project not found" | `NTM_PROJECTS_BASE` doesn't contain `<port>` | `export NTM_PROJECTS_BASE=/data/projects` (or wherever your port lives) |
| `ntm pipeline run` errors "unknown schema version" | Pipeline YAML was written for a different NTM build | Re-run `ntm pipeline lint <yaml>` — fix what it complains about. The gauntlet pins schema_version "2.0". |
| `ntm send` hangs with `Continue anyway?` | CASS dedup detected a similar past prompt | Add `--no-cass-check`, or switch to `ntm --robot-send` (non-interactive) |
| Phase 1 RECON pane crashes mid-archaeology | Crate has 4000-line files that blow context | Smaller crates first; split large crates' archaeology into per-module sub-tasks (re-run the pipeline with a narrower `crate_list`) |
| Phase 9 perf "cv_pct > 5" warnings | Host noise (other processes, thermal throttling) | Reserve a quieter host via `rch`, or rerun with more iterations |
| Phase 11 not converging at round 15 | Real findings are still surfacing → continue. OR idea-wizard is over-producing → narrow the prompt scope. | Inspect `round_*/synthesis.md` — if the same hypothesis keeps respawning, escalate to multi-model triangulation early |
| Phase 15 soak runner ack never arrives | `rch` worker unhealthy at dispatch | `ntm --robot-rch-workers --worker=<name>`; reassign to a healthy worker in the pipeline `--var rch_worker_pool=` |

---

## Stopping cleanly

```bash
# Cancel any in-flight pipelines
for run in $(ntm pipeline list --json | jq -r '.runs[] | select(.state == "running") | .id'); do
  ntm pipeline cancel "$run"
done

# Gracefully stop the sessions (keeps panes around for inspection)
for lane in conformance perf surface soak; do
  ntm interrupt ${PORT}--$lane
done

# Or hard kill everything
ntm swarm stop "${PORT}--*"
```

The workspace state at `<port>__gauntlet_workspace/` is durable — committed to git on every phase boundary. You can resume from any point by re-dispatching the next pipeline.

---

## Next steps

- Read [NTM-INTEGRATION.md](NTM-INTEGRATION.md) for the full integration contract (anti-patterns, robot-mode discipline, failure recovery).
- Read [`subagents/ntm-orchestrator.md`](../../subagents/ntm-orchestrator.md) — the subagent that automates the per-phase dispatch loop end-to-end.
- Read [ORCHESTRATION.md](ORCHESTRATION.md) for the cc_N lane convention, reservations, and rch offload heuristic.
- Read [`/ntm`](~/.claude/skills/ntm/SKILL.md) for the underlying NTM command surface.
- Read [`/vibing-with-ntm`](~/.claude/skills/vibing-with-ntm/SKILL.md) when a pane gets stuck mid-run and you need the unstick ladder.
