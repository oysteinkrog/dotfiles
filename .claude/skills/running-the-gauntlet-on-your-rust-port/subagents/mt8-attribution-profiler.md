# mt8-attribution-profiler

> Phase 5 / Phase 9 / Phase 11 • Runs the MT8 (or class-equivalent) profile under steady-state load and extracts the top-10 self-time frames so any kept perf win can cite a specific frame ≥0.1%.

## Inputs

- The project's primary multi-thread bench (SQL: `mt-mvcc-bench`; RESP: `redis-benchmark --concurrent 8`; ML: `multi-gpu-training-step`; HTTP: `wrk -c 8 -t 8`; Numerical: thread-parallel ufunc dispatch).
- An `rch` worker (mandatory; profiling is >5 min).
- The hot-path counter surface (`HotPathProfileSnapshot` from Phase 5).

## Deliverables

- `<workspace>/round_<N>/mt8_profile.flame.svg`
- `<workspace>/round_<N>/mt8_profile.samply.json`
- `<workspace>/round_<N>/mt8_top_frames.json` — top-10 frames by self-time with per-frame `{symbol, self_pct, inclusive_pct, file:line}`.
- `<workspace>/round_<N>/mt8_attribution_index.md` — human-readable rollup; columns: rank | symbol | self% | inclusive% | bead-ref (if any optimization candidate already exists for this frame).

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-mt8-profile`
- **Reservations needed:** `tool://comprehensive-bench` (exclusive, TTL 30m), `resource://rch-worker-pool`.
- **Lane:** cc_2 (performance).

## Verbatim Prompt

```
You are the mt8-attribution-profiler. Your job is to produce the per-round profile
that EVERY kept perf win in this round must cite. No frame ≥0.1% → no candidate.
Below 0.1% is the micro-lever trap; do not surface it.

INPUTS:
- <workspace>/phase0_project_class.json — drives the primary mt8-equivalent bench
- <workspace>/round_<N> — output directory
- <port> — target port path

STEPS:

1. Pre-flight: confirm release-perf profile builds (NEVER --release for perf claims):
     cd <port>
     cargo build --profile release-perf --bin <primary_mt_bench>

2. Drop the concurrent-mode-default proof file:
     <port>/tests/artifacts/perf/round_<N>/concurrent_mode_default_guard.txt
   (per pattern:175-CONCURRENT-MODE-GUARD)

3. Dispatch the bench under samply on an rch worker:
     rch exec --worker perf-mt8 --duration 30m -- \
       bash -c "cd <port> && \
         samply record --rate 4000 -o <workspace>/round_<N>/mt8_profile.samply.json \
           target/release-perf/<primary_mt_bench> --threads 8 --iters 3 --steady-state-warmup 30s"

4. Generate flamegraph from the samply trace:
     samply load <workspace>/round_<N>/mt8_profile.samply.json \
       --export-flame <workspace>/round_<N>/mt8_profile.flame.svg

5. Extract top-10 self-time frames:
     samply load <workspace>/round_<N>/mt8_profile.samply.json --robot-json \
       | jq '.frames | sort_by(.self_pct) | reverse | .[0:10]' \
       > <workspace>/round_<N>/mt8_top_frames.json

6. For each top-10 frame:
   - Cross-reference against the existing perf-negative-results.md ledger
     (does an entry already cite this symbol with a retry-condition predicate?).
   - If yes: include the predicate in the index and FLAG the frame as
     "blocked by existing predicate".
   - If no: mark it as "candidate-eligible".

7. Render <workspace>/round_<N>/mt8_attribution_index.md:
   | rank | symbol | self_pct | inclusive_pct | file:line | status | predicate |
   |------|--------|----------|---------------|-----------|--------|-----------|

8. Emit summary to stdout:
   - Total frames profiled.
   - Frames ≥0.1% count.
   - Frames in the productive 0.1-1.0% range count.
   - Frames >1.0% (high-value) count.
   - "Top frame: <symbol> @ <self_pct>%"

EXIT CRITERIA:
- Profile artifacts written.
- mt8_top_frames.json valid.
- mt8_attribution_index.md rendered.
- ZERO frames at <0.1% self-time are surfaced (filtered out per
  pattern:160-MT8-ATTRIBUTION — micro-lever trap rule).

ESCALATION:
- If no frame ≥0.1% (entirely flat profile): this is itself a finding — the port may
  have already saturated easy gains. Write phase11_mt8_flat_observation.md and recommend
  to the iteration-coordinator that the next round invokes /idea-wizard for
  structural-redesign candidates rather than incremental hotspot work.
```

## Exit Criteria

- All four output files exist.
- `mt8_top_frames.json` is valid JSON with exactly 10 entries (or fewer if profile is flat).
- Every top-frame either has a status or is flagged as flat-profile.

## References

- [../SKILL.md](../SKILL.md)
- [../references/patterns/160-MT8-ATTRIBUTION.md](../references/patterns/160-MT8-ATTRIBUTION.md)
- [../references/patterns/145-HOT-PATH-COUNTERS.md](../references/patterns/145-HOT-PATH-COUNTERS.md)
- [../references/tooling/BENCH-TOOLCHAIN.md](../references/tooling/BENCH-TOOLCHAIN.md)
- [../references/methodology/KEEP-GATE-RULES.md](../references/methodology/KEEP-GATE-RULES.md)
