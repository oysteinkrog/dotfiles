# mt8-attribution-flat

> The MT8 (or class-equivalent) attribution shows no frame ≥0.1% self-time. The easy gains are exhausted. Decide: switch workloads, broaden the bench, accept the perf ceiling, or invest in architectural rework.

## Trigger

Any of:

- The mt8-attribution-profiler subagent reports top-10 self-time frames all under 0.1%.
- A perf-regression-triage entered the `⤴ Attribute-To-MT8` step and found no candidate frame.
- `<workspace>/round_<N>/perf/mt8_attribution.json | jq '.top_frames[0].self_pct'` returns `< 0.1`.
- The flamegraph is visibly "flat" — no obvious wide bars; the work is spread across hundreds of small frames.
- A maintainer asks "where do we squeeze the next 5%?" and the profile has no obvious target.

This isn't a bug; it's a signal that the workload's easy-gain phase is over. Acting on a "win" from a sub-0.1% frame is the **micro-lever trap** — the change is below the bench's noise floor; the apparent win is sampling artifact.

## Operator Pipeline

```
⤴ ATTRIBUTE-TO-MT8         re-confirm the flatness; no frame ≥0.1%
↓
⟁ TRIANGULATE-PROFILE     do other profilers (samply / dhat / strace) reveal what flamegraph hides?
↓
⊕ ISOMORPHIC-REWRITE       enumerate 3 strategies: broaden bench, architectural rework, accept ceiling, switch workload
↓
🧪 EXPERIMENT-DESIGN       file the strategy + the falsifiability ("if this strategy fails to reveal a frame ≥0.1% within 2 weeks, accept the ceiling")
```

The pipeline is shorter than perf-regression-triage because there's no fix to land — the output is a strategic decision, not a code change.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
WORKLOAD=<the bench whose profile is flat, e.g., mt-mvcc-bench>

# 1. Re-confirm flatness
"$WORKSPACE/scripts/run-narrow-benches.sh" "$PORT" "$WORKSPACE" --benches "$WORKLOAD"
LANE="$WORKSPACE/artifacts/narrow/$WORKLOAD"
ls "$LANE"/flamegraph.svg "$LANE"/samply.json "$LANE"/strace.summary 2>/dev/null || true
# Dispatch the mt8-attribution-profiler subagent if the wrapper did not emit a
# top-frame table for this project class.

# If top-10 all < 0.1%, the workload is genuinely flat.

# 2. Triangulate: do other profilers show something flamegraph doesn't?
"$WORKSPACE/scripts/run-narrow-benches.sh" "$PORT" "$WORKSPACE" --benches "$WORKLOAD"
DHAT_MD="$LANE/dhat.md"

# Possible hidden signals:
# - dhat: heap pressure spread across many small allocations (cumulative > 0.1% but per-call < 0.1%)
# - strace: syscall storm (many lseek/write at < 0.01% each but cumulative high)
# - heaptrack: peak-heap memory pressure that doesn't show in CPU profile

cat "$DHAT_MD"
cat "$LANE/strace.summary" 2>/dev/null || true

# 3. Mine the ledger for prior flatness conclusions on this workload
"$WORKSPACE/scripts/mine-ledger.sh" "$WORKSPACE" --terms "$WORKLOAD" --filter "flat|saturated|micro.lever|ceiling"

# 4. File the strategy hypothesis
cat >> "$WORKSPACE/PERF_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — mt8-flat-$WORKLOAD — strategic
- target_workload: $WORKLOAD
- top_frame_self_pct: <value < 0.1>
- triangulation_hidden_signals: <heap | syscalls | none>
- strategy: broaden-bench | architectural-rework | accept-ceiling | switch-workload
- hypothesis: <one-sentence prediction>
- expected_signal: <which counter or which alternative workload would show a frame >= 0.1%>
- falsifiability: <e.g., "broadening bench from 8 threads to 32 fails to reveal a frame >= 0.1%">
- one_line_invocation: <the experiment command>
- results_inline: <fill after experiment>
EOF

# 5. Create the bead
br create \
  --title "mt8-flat-$WORKLOAD" \
  --priority 3 \
  --type investigation \
  --labels "pillar:perf,lane:cc_2,recipe:mt8-attribution-flat,workload:$WORKLOAD"

# 6. Execute the chosen strategy (one example: broaden the bench)
#    a) broaden-bench: add new workload shapes to comprehensive-bench (different cardinalities,
#       different thread counts, different read/write ratios) and re-attribute on each.
#    b) architectural-rework: identify the cross-cutting cost (e.g., allocation strategy,
#       cache key design) and prototype a different design via pattern:245-CACHE-KEY-EVICTION-AUDIT.
#    c) accept-ceiling: file a negative-ledger entry "not worth retrying as a standalone patch"
#       with the perf-ceiling rationale; the next bench-history entry is the new floor.
#    d) switch-workload: choose a different bench that exercises the part of the system
#       still on the easy-gain curve.
```

## Beads to claim (or create)

- `mt8-flat-<workload>` (this recipe creates it).
- Dependency: `pattern:160-MT8-ATTRIBUTION` — the 0.1% threshold contract.
- Dependency: `pattern:150-PROFILE-FIRST-CARD` — profile-first discipline.
- Dependency: `pattern:245-CACHE-KEY-EVICTION-AUDIT` (if architectural-rework strategy) — Pattern 10 design audit.
- Dependency: `pattern:255-RCH-OFFLOAD-DISCIPLINE` (if broaden-bench strategy) — broader workloads are expensive; offload.
- Dependency: `pattern:180-NEGATIVE-LEDGER` (if accept-ceiling strategy) — the rationale is itself a ledger entry.
- Dependency (test): `test-mt8-flat-<workload>-strategy-applied` — verifies the chosen strategy executed.
- Dependency (doc): `doc-mt8-flat-<workload>-strategy` — the strategic decision is documented.

## Exit Criteria

- [ ] Flatness re-confirmed across at least two profilers (flamegraph + one other).
- [ ] Triangulation distinguishes "CPU-flat but heap-pressured" vs "syscall-bound" vs "genuinely-saturated."
- [ ] Hypothesis ledger entry filed with falsifiability criterion.
- [ ] Strategy chosen: `broaden-bench` | `architectural-rework` | `accept-ceiling` | `switch-workload`.
- [ ] If `broaden-bench`: new workloads added; re-attribution shows whether the new shape reveals a frame ≥0.1%.
- [ ] If `architectural-rework`: prototype landed in scratch; cross-cutting cost identified; new MT8 attribution shows a candidate frame.
- [ ] If `accept-ceiling`: negative-ledger entry filed with template-4 ("Not worth retrying as a standalone patch") OR template-2 ("Reconsider only inside the broader X redesign").
- [ ] If `switch-workload`: a different bench enters the gating set; previous workload may be downgraded to "informational" in the bench history.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Tuning a frame at 0.05% self-time. | **Micro-lever trap.** Below the bench's noise floor; the "win" is sampling artifact. |
| Accepting the ceiling without triangulation. | The CPU profile may be flat while heap or syscall profiles show clear targets. Triangulate before giving up. |
| Switching to a workload chosen to make the port look good. | That's cherry-picking. The new gating bench must be representative of real load, not optimized-for. |
| Broadening the bench without re-running the full comprehensive-bench matrix. | The new workload changes the geomean; the existing ratchet floor may need to be re-baselined. |
| Filing the ledger entry as "we'll come back to this." | Use template-2 or template-4 from the retry-condition vocabulary, not free-form. |
| Architectural rework without ≥2 design alternatives. | `⊕ Isomorphic-Rewrite` requires alternatives even for architectural changes. |
| Closing the bead without choosing a strategy. | "We profiled and the profile was flat" is not a resolution — the four strategy options each have a closure path. |
| Treating "no frame ≥0.1%" as a perf regression. | It's a saturation signal, not a regression. Route `perf-regression-triage` only if the geomean dropped. |

## Cross-references

- [../patterns/160-MT8-ATTRIBUTION.md](../patterns/160-MT8-ATTRIBUTION.md) — 0.1% threshold + micro-lever trap.
- [../patterns/150-PROFILE-FIRST-CARD.md](../patterns/150-PROFILE-FIRST-CARD.md) — profile-first card schema.
- [../patterns/145-HOT-PATH-COUNTERS.md](../patterns/145-HOT-PATH-COUNTERS.md) — counter ergonomics.
- [../patterns/245-CACHE-KEY-EVICTION-AUDIT.md](../patterns/245-CACHE-KEY-EVICTION-AUDIT.md) — Pattern-10 architectural audit.
- [../patterns/180-NEGATIVE-LEDGER.md](../patterns/180-NEGATIVE-LEDGER.md) — ledger schema.
- [../patterns/185-RETRY-CONDITION-PREDICATE.md](../patterns/185-RETRY-CONDITION-PREDICATE.md) — template 2 + template 4.
- [../tooling/BENCH-TOOLCHAIN.md](../tooling/BENCH-TOOLCHAIN.md) — profiler invocations.
- [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) — micro-lever trap + cv_pct discipline.
- Related motions: [perf-regression-triage.md](perf-regression-triage.md), [cv-pct-flake.md](cv-pct-flake.md), [ratchet-block.md](ratchet-block.md).
