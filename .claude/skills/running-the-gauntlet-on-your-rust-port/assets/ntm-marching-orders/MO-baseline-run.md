# MO-baseline-run.md — Phase 9 Per-Pillar Baseline Runner

**Phase:** 9 (BASELINE) — also reused by Phase 11 round re-baselines
**Parameters:** `<PANE_N>`, `<ROLE>`, `<MODEL>`, `<SESSION_ID>`, `<WORKSPACE_PATH>`, `<PORT_PATH>`, `<PILLAR>` (perf | conformance | surface), `<PROJECT_CLASS>`, `<REFERENCE_VERSION>`, `<COORDINATION_MODE>`, `<THREAD_ID>`, `<RCH_WORKER>` (optional), `<ROUND>`

---

You are pane `<PANE_N>` (model `<MODEL>`) in gauntlet swarm `<SESSION_ID>`, dispatched as the **`<PILLAR>` baseline runner** for round `<ROUND>` against port `<PORT_PATH>` and reference `<REFERENCE_VERSION>`.

Your output is `<WORKSPACE_PATH>/phase9_baseline_<PILLAR>.md` (for round_0) or `<WORKSPACE_PATH>/round_<ROUND>/baseline_<PILLAR>.md` (for round ≥1).

**Step 1 — Read the governing instructions.**

- `<PORT_PATH>/AGENTS.md` and any repo-level `AGENTS.md`.
- `<WORKSPACE_PATH>/AGENTS.md` for the gauntlet mandate (negative-ledger + cass-mining).
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/PHASES.md` § Phase 9
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/methodology/KEEP-GATE-RULES.md` (THIS IS THE CORE; reread every time)
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/methodology/CONFORMAL-RATCHET.md`

**Step 2 — Read pillar-specific subagent.**

- For `<PILLAR>` = perf: `~/.claude/skills/running-the-gauntlet-on-your-rust-port/subagents/baseline-runner-perf.md`
- For `<PILLAR>` = conformance: `~/.claude/skills/running-the-gauntlet-on-your-rust-port/subagents/baseline-runner-conformance.md`
- For `<PILLAR>` = surface: `~/.claude/skills/running-the-gauntlet-on-your-rust-port/subagents/baseline-runner-surface.md`

The subagent file is your detailed procedure. This marching order is the dispatch shell.

**Step 3 — Register Agent Mail identity.**

```text
register_agent(
  project_key="<WORKSPACE_PATH>",
  program="<your-cli>",
  model="<your-model>",
  task_description="gauntlet <SESSION_ID> pane <PANE_N> phase9 baseline pillar=<PILLAR> round=<ROUND>"
)
```

**Step 4 — Acknowledge on `<THREAD_ID>`.**

```
Subject: [<SESSION_ID>] Phase 9 baseline-<PILLAR> dispatch ack — pane=<PANE_N>, round=<ROUND>
Body:
  Pane: <PANE_N>
  Role: <ROLE>
  Pillar: <PILLAR>
  Round: <ROUND>
  rch worker: <RCH_WORKER>
  Started: <UTC timestamp>
```

**Step 5 — Negative-ledger pre-flight (MANDATORY for `<PILLAR>` = perf).**

Before running any bench, grep the three ledgers + 60 days of cass:

```bash
~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/mine-ledger.sh \
  --workspace <WORKSPACE_PATH> --pillar <PILLAR> --out /tmp/ledger_check_<PANE_N>.json

~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/mine-cass-cross-machine.sh \
  --days 60 \
  --terms "rejected,reverted,abandoned,slower,regressed,didn't help,within noise,no improvement,failed to improve,rolled back,backed out,not a keep,keep gate" \
  --out /tmp/cass_check_<PANE_N>.json
```

If either script reports candidate blockers, attach to your dispatch ack with the candidate-blocker list. If neither is available (degraded source), record a blocker entry in your output file rather than silently skipping — per the mandate paragraph.

**Step 6 — Reserve the pillar resources.**

For `<PILLAR>` = perf:

```text
reserve(
  paths=["tool://comprehensive-bench", "resource://bench-host"],
  scope="phase9-perf-round-<ROUND>",
  ttl_seconds=21600,
  reason="phase9 baseline perf round <ROUND>"
)
```

If `<RCH_WORKER>` is non-empty: additionally reserve `resource://rch-worker-<RCH_WORKER>` (TTL 480 min).

For `<PILLAR>` = conformance: reserve `tool://oracle-runner` + `tool://fuzz-corpus` (read).

For `<PILLAR>` = surface: reserve `tool://feature-coverage-compute`.

**Step 7 — Execute per the pillar's subagent procedure.**

### If `<PILLAR>` = perf

Strict keep-gate discipline (per KEEP-GATE-RULES.md):

1. Build `release-perf` profile only (`cargo build --profile release-perf`). NEVER `--release`.
2. Drop the project-class proof file into the artifact lane BEFORE running benches:
   - SQL: `concurrent_mode_default_guard.txt` with `CONCURRENT_MODE_DEFAULT=true`
   - RESP: `resp_version_guard.txt` with `RESP_VERSION=3`
   - ML: `deterministic_algs_guard.txt` with `DETERMINISTIC_ALGS=true` + `CUDA_DEVICE_COUNT=N`
   - HTTP: `deterministic_clock_guard.txt` with `DETERMINISTIC_CLOCK=true`
3. Run `comprehensive_bench` in full mode against subject + reference, emit JSON v3 to `<WORKSPACE_PATH>/artifacts/phase9_baseline_perf/comprehensive.v3.json`.
4. Run every focused per-workload bench (`cargo bench --profile release-perf --bench <family>`).
5. Under MT8-equivalent load, capture `flamegraph.svg` + `samply.json` + `dhat.out` + `strace.out` into `<WORKSPACE_PATH>/artifacts/phase9_baseline_perf/<run_id>/proof_pack/`.
6. Commit `.bench-history/<family>.latest.json` per family — **both focused and broad gates must move in the same run window: same git SHA, same target/, same machine, same minute**.
7. If `<RCH_WORKER>` is set AND wall-time will exceed 5 min, offload via `rch exec --worker <RCH_WORKER> -- <cmd>`.

### If `<PILLAR>` = conformance

1. Run `oracle-runner` full suite against subject + oracle.
2. Run `differential_v2` corpus to completion.
3. Run every metamorphic family (`Predicate`, `Projection`, `Structural`, `Literal`, etc. per class).
4. For each `TrueDivergence`, emit `FailureBundle v1.0.0` with seed + fixture id + schedule fingerprint + exact repro command + state snapshots + diff hints + environment.
5. Dedup divergences by `MismatchSignature` (use `scripts/compute-mismatch-signature.sh`).
6. Classify every divergence as `TrueDivergence` OR one of `{Order, TypeAffinity, NullHandling, FloatingPoint, FalsePositive}`.

### If `<PILLAR>` = surface

1. Load `<WORKSPACE_PATH>/docs/contracts/supported_surface_matrix.toml`.
2. Verify `parity_score_contract.toml` weight invariant: `sum(weights) == 1.0` per category.
3. Run `feature_coverage_dashboard` against subject vs `<REFERENCE_VERSION>`.
4. For each category: compute Beta-posterior over pass rate; build distribution-free conformal band; emit the **LOWER bound** (not the point estimate).
5. `truncate_score` to exactly 6 decimal places.
6. Excluded items still count as coverage debt for any strict-100% claim.

**Step 8 — Write the output file with the required sections.**

For `<PILLAR>` = perf — five sections:

- Per-category weighted score table (subject vs reference, with delta and LOWER bound).
- Geomean ratio (subject/reference).
- Top-10 slowest scenarios by p99.
- Top-10 hottest profile frames ≥0.1% self-time, formatted as `Closed N.NN% MT8 <symbol>`.
- `cv_pct` distribution; any scenario with `cv_pct > 5` flagged for re-run with more iterations.

For `<PILLAR>` = conformance:

- Pass-rate per behavior class (with LOWER bound).
- Top divergences by frequency.
- Top divergences by surprise (low expected probability).
- The `FailureBundle` file paths (one per `TrueDivergence`).
- Classification tally `{TrueDivergence, Order, TypeAffinity, NullHandling, FloatingPoint, FalsePositive}`.

For `<PILLAR>` = surface:

- Per-family coverage verdict (`green | yellow | red`).
- `present | partial | missing | n/a | excluded` counts.
- Weight-normalized parity score with LOWER bound.
- Excluded-as-debt tally for strict-100% claim.
- Every weak-evidence bead the dashboard flagged (`fail-missing-evidence | fail-invalid-references | fail-mixed`).

**Step 9 — Ship-or-surface SLA.**

- `<PILLAR>` = perf: up to 6 hours wall time (rch-offloaded). Within that window, either commit the output OR post `BLOCKED` with the specific blocker (e.g., rch worker `<RCH_WORKER>` unhealthy, `cv_pct > 5` on >30% of scenarios, comprehensive-bench crashed at scenario N).
- `<PILLAR>` = conformance: up to 6 hours. Block reasons: oracle preflight no longer green, differential corpus exhausted with M unclassified divergences, mismatch-minimizer crashed.
- `<PILLAR>` = surface: up to 3 hours. Block reasons: FeatureUniverse weight invariant violated, dashboard exit non-zero, ledger files missing.

**Step 10 — Acknowledge completion on `<THREAD_ID>`.**

```
Subject: [<SESSION_ID>] Phase 9 baseline-<PILLAR> DONE — round=<ROUND>
Body:
  Output: <output path>
  Headline metric: <geomean | pass-rate | parity-score LOWER bound>
  Findings filed to ledger: <N>
  Open blockers: <list or "none">
  rch worker used: <RCH_WORKER or "local">
  Duration: <wall time>
```

**Step 11 — Universal gauntlet rules apply.**

Per AGENTS.md mandate: no destructive git, no file deletion, other agents' edits are normal, fix all errors regardless of source, no bare `cass`/`bv`/`cargo bench --workspace` — use `--robot-*`/`-p <crate>` forms.

---

**Reply with:** `Pane <PANE_N> ready, role=<ROLE>, pillar=<PILLAR>, round=<ROUND>`.
