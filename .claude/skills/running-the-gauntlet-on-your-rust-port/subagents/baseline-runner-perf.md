# baseline-runner-perf

> Phase 9 • Run comprehensive-bench full mode (93+ scenarios); commit first `.bench-history/*.latest.json`; capture flamegraphs / samply / dhat / strace under MT8-equivalent load.

## Inputs
- `comprehensive_bench` binary from `bench-author.md`.
- Per-workload focused benches from `bench-author.md`.
- `phase5_counters_<class>.md` (hot-path counter wiring).
- rch worker pool (if any single workload >5 min wall time).

## Deliverables
- `<target>/.bench-history/<family>.latest.json` per workload family (committed to git).
- `<workspace>/artifacts/phase9_baseline_perf/<run_id>/proof_pack/` with flamegraph.svg / samply.json / dhat.out / strace.out per canonical workload.
- `<workspace>/artifacts/phase9_baseline_perf/concurrent_mode_default_guard.txt` (or class-equivalent proof file).
- `<workspace>/phase9_baseline_perf.md` with the per-category weighted score table, the geomean ratio, top-10 slowest scenarios, top-10 hottest profile frames ≥0.1%.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase9-baseline-perf`
- **Reservations needed:** `resource://bench-host` (TTL 480m), `tool://comprehensive-bench` (TTL 240m), `resource://rch-worker-pool` (TTL 480m if offloaded).
- **Lane:** cc_2 (performance).

## Verbatim Prompt

You are the perf baseline runner. Run the full comprehensive-bench matrix (all 93+ scenarios across the three orthogonal axes), all focused per-workload benches, and capture profiling artifacts under the canonical concurrent workload (MT8 = 8 threads × file-backed DB × BEGIN CONCURRENT for SQL-class; class-equivalent for others).

**Order of operations:**

1. Build `release-perf` profile only (never `--release`):
```bash
cargo build --profile release-perf --bin comprehensive_bench
cargo build --profile release-perf --benches
```

2. Drop the proof file into the artifact lane BEFORE running benches:
```
echo "CONCURRENT_MODE_DEFAULT=true\nGIT_SHA=$(git rev-parse HEAD)\nTIMESTAMP=$(date -u +%FT%TZ)" \
  > artifacts/phase9_baseline_perf/concurrent_mode_default_guard.txt
```
(For RESP: `RESP_VERSION=3`. For ML: `CUDA_DEVICE_COUNT=N` + `DETERMINISTIC_ALGS=true`. For HTTP: `DETERMINISTIC_CLOCK=true`.)

3. Run `comprehensive_bench` in full mode against subject + reference; emit JSON v3:
```bash
cargo run --profile release-perf --bin comprehensive_bench -- \
  --mode full --reference <oracle> --out artifacts/phase9_baseline_perf/comprehensive.v3.json
```

4. Run each focused per-workload bench:
```bash
cargo bench --profile release-perf --bench <family>
```

5. Under MT8-equivalent load, capture profiling artifacts (use `cargo flamegraph`, `samply`, `dhat-rs` (compile with `--features dhat-heap`), `strace -c -p <pid>`). Per workload write to `artifacts/phase9_baseline_perf/<run_id>/proof_pack/`:
```
baseline_profile.flame.svg
baseline_profile.samply.json
baseline_profile.dhat.out
baseline_profile.strace.out
```

6. Commit `.bench-history/<family>.latest.json` per family. **Both gates must move in the same run window** — same git SHA, same target/, same machine, same minute. If you discover a regression vs prior baseline, do NOT commit overwrite; file a regression-investigation bead.

7. Write `phase9_baseline_perf.md` with:
- Per-category weighted score table.
- Geomean ratio (`fsqlite/csqlite` or equivalent).
- Top-10 slowest scenarios (`p99 desc`).
- Top-10 hottest profile frames ≥0.1% self-time, formatted as "Closed N.NN% MT8 `<symbol>`".
- The `cv_pct` distribution; any scenario with `cv_pct > 5` flagged for re-run with more iterations.

**rch-offload heuristic:** if comprehensive_bench wall-time exceeds 5 minutes locally, dispatch via `rch exec -- cargo run --profile release-perf --bin comprehensive_bench -- --mode full`. See `../references/orchestration/ORCHESTRATION.md § rch offload heuristic`.

## Exit Criteria
- All 93+ scenarios produce a row in the JSON v3 output.
- `concurrent_mode_default_guard.txt` (or equivalent) exists in artifact lane.
- `.bench-history/<family>.latest.json` per family committed.
- Proof pack contains flamegraph + samply + dhat + strace per canonical workload.
- `phase9_baseline_perf.md` committed with all five sections (categories, geomean, top-10 slowest, top-10 hot frames, cv_pct).
- Top-10 hot frames each ≥0.1% self-time.

## References
- [PHASES.md § Phase 9](../references/PHASES.md)
- [tooling/BENCH-TOOLCHAIN.md](../references/tooling/BENCH-TOOLCHAIN.md)
- [methodology/KEEP-GATE-RULES.md](../references/methodology/KEEP-GATE-RULES.md)
- [methodology/OPERATORS.md § Attribute-To-MT8 § Pass-Over-Pass-Gate § Triangulate-Profile](../references/methodology/OPERATORS.md)
- [orchestration/ORCHESTRATION.md § rch offload](../references/orchestration/ORCHESTRATION.md)
