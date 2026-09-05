# asupersync-cancel-leak

> An async path under asupersync is suspected of leaking obligations on cancellation. Prove the leak, find the leaked resource, fix the cancel-correctness with the obligation pattern. Eidetic/fastmcp-style cancel-correctness discipline applied to any project with a custom asupersync runtime.

This is the cancel-correctness sibling of [embedding-cache-staleness.md](embedding-cache-staleness.md). Both are eidetic-engine-cli-specific patterns generalized for any sibling that builds on the asupersync substrate (`pi_agent_rust`, `fastapi_rust`, `fastmcp_rust`, `sqlmodel_rust`, `frankensqlite`, `frankenwhisper`, `frankenscipy`). Per [Q-263](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-263--codexmd-1616--inline-critical-vs-offloaded-is-a-safety-boundary), the inline-critical vs offloaded boundary is a safety boundary; obligation leaks defeat it.

## Trigger

Any of:

- `obligations_leaked_total` metric increments under load (per [Q-262](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-262--codexmd-1613--performance-claims-are-cell-level)).
- A `LabRuntime` test panics with `Leaked obligation: <name>` (per [Q-218](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-218--ccmd-110--dpor-practical-reduction-factor) — DPOR enumeration found a schedule that cancels mid-reserve).
- Production telemetry shows a count of `commit_send_permit_reserved` exceeding `commit_send_permit_released` by N over an hour.
- A reviewer flagged a `tokio::select!` (or `asupersync::select!`) branch that returns without releasing a held permit.
- The fastmcp-rust integration test `test_cancel_during_tool_dispatch` started failing on a recent commit.
- `bv --robot-insights | jq '.CancelLeaks'` shows a new entry.

## Why "It's Async, Cancellation Is Hard" Is Wrong

asupersync's obligation pattern is *specifically* designed to make cancel-correctness checkable mechanically. Per [Q-218](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-218--ccmd-110--dpor-practical-reduction-factor), DPOR enumerates Mazurkiewicz-distinct schedules in 4–6 orders of magnitude less time than naive enumeration; a leaked obligation surfaces in *some* enumerated schedule. The leak is *findable*; what's hard is *fixing* it without breaking the happy path.

The discipline (per asupersync's own conventions):
1. Every async function takes `&Cx` as first parameter (the capability+cancellation+deadline carrier).
2. Every `Reserved` obligation has a paired `Committed` or `Released` resolution on *every* control path.
3. `LabRuntime` runs the function under DPOR-enumerated cancellation schedules; any leak panics the test runtime fast.

Cancel-correctness is therefore a *pattern-match-against-the-code* problem at review time, plus a *enumerated-test* problem in CI. Both have to pass.

## Operator Pipeline

```
⊙ DEBOUNCE-FALSE-POSITIVE     classify: is the leak deterministic or schedule-dependent?
↓
⌘ REDUCE/MINIMIZE             produce the minimal DPOR-enumerated schedule that triggers the leak
↓
⬡ INSTRUMENT-HOT-PATH         enable per-obligation tracing; dump reserve/release pairs from the failing schedule
↓
⤴ ATTRIBUTE-TO-MT8 (analog)   identify the unpaired Reserved obligation by name and call-site
↓
🧪 EXPERIMENT-DESIGN          hypothesis: "the leak originates at <file:line>; an explicit release on the cancel branch closes it"
↓
⊕ ISOMORPHIC-REWRITE          options: (a) Drop-impl release; (b) explicit release in cancel branch; (c) scoped obligation via RAII guard
↓
⚖ RATCHET-LOWER-BOUND         DPOR cancel-coverage must increase (more enumerated schedules pass); throughput must not drop >5%
↓
🪟 FRESH-EYES                three reviewers; one MUST be a red-team-attacker that enumerates new cancel-points
```

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
TEST=<the failing LabRuntime test, e.g., test_cancel_during_tool_dispatch>

# 1. Confirm leak is reproducible. Run the test under LabRuntime with verbose obligation tracing.
cd "$PORT"
LAB_DETERMINISTIC_SEED=42 \
  LAB_TRACE_OBLIGATIONS=1 \
  cargo test --profile release-perf -p <crate> -- "$TEST" --nocapture \
  > "$WORKSPACE/cancel-leak/test_pre.log" 2>&1

# Look for "Leaked obligation: <name>" lines:
grep -F 'Leaked obligation:' "$WORKSPACE/cancel-leak/test_pre.log"

# 2. Reduce to the minimal cancel schedule.
# LabRuntime exposes --reduce-schedule that delta-debugs the cancel-point sequence.
LAB_REDUCE_SCHEDULE=1 \
  cargo test --profile release-perf -p <crate> -- "$TEST" --nocapture \
  > "$WORKSPACE/cancel-leak/reduce.log" 2>&1

# The reduce output names: minimal schedule = [<step1>, <step2>, ..., <cancel-point>]
MINIMAL_SCHED=$(grep 'minimal_schedule:' "$WORKSPACE/cancel-leak/reduce.log" | head -1)
echo "Minimal cancel schedule: $MINIMAL_SCHED"

# 3. Replay the minimal schedule with full obligation tracing.
LAB_REPLAY_SCHEDULE="$MINIMAL_SCHED" \
  LAB_TRACE_OBLIGATIONS=full \
  cargo test --profile release-perf -p <crate> -- "$TEST" --nocapture \
  > "$WORKSPACE/cancel-leak/replay_full_trace.log" 2>&1

# Find the unpaired Reserved:
awk '/Reserved obligation/{ res[$NF]++ } /Released obligation|Committed obligation/{ res[$NF]-- } END { for (k in res) if (res[k] > 0) print k }' \
  "$WORKSPACE/cancel-leak/replay_full_trace.log"

# Output is the obligation name (e.g., `SendPermit::commit_pipeline_slot_42`).

# 4. Locate the reserve site in code.
OBLIGATION_NAME=<from step 3>
rg "reserve.*$OBLIGATION_NAME|$OBLIGATION_NAME.*reserve" "$PORT/src" -n \
  > "$WORKSPACE/cancel-leak/reserve_sites.txt"
cat "$WORKSPACE/cancel-leak/reserve_sites.txt"
# Typically 1-2 hits; the leaking one is whichever doesn't have a release on every path.

# 5. File the hypothesis BEFORE attempting a fix.
cat >> "$WORKSPACE/PERF_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — asupersync-cancel-leak-${OBLIGATION_NAME//[\/:]/-} — investigating
- target_workload: $TEST
- minimal_cancel_schedule: $MINIMAL_SCHED
- leaked_obligation: $OBLIGATION_NAME
- reserve_sites: $(cat "$WORKSPACE/cancel-leak/reserve_sites.txt")
- hypothesis: "the reserve at <file:line> has a cancel-branch path that returns without releasing the obligation"
- expected_signal: "after fix, replay of minimal_schedule shows reserve/release balanced"
- falsifiability: "if the fix introduces a release but the schedule still leaks, the obligation is being moved across a non-cancel-safe boundary — escalate"
- one_line_invocation: "LAB_REPLAY_SCHEDULE=\\"$MINIMAL_SCHED\\" cargo test --profile release-perf -p <crate> -- $TEST --nocapture"
- results_inline: <fill after step 7>
EOF

# 6. Apply the fix. Three canonical options (per asupersync's obligation pattern):
#
#    (a) Drop-impl release (most idiomatic; works when the obligation is owned by a struct):
#         impl Drop for ReservedSendPermit {
#             fn drop(&mut self) {
#                 if !self.released.swap(true, Ordering::Acquire) {
#                     self.pool.release_slot(self.slot_id);
#                 }
#             }
#         }
#         Then `select!` cancel branches naturally drop the value → release happens automatically.
#
#    (b) Explicit release in cancel branch (when ownership crosses boundaries):
#         select! {
#             res = work(cx, &permit) => res,
#             _ = cx.cancelled() => {
#                 permit.release();
#                 Err(Cancelled)
#             }
#         }
#
#    (c) Scoped RAII guard (when the obligation is short-lived and ownership is local):
#         let _guard = permit.scoped();
#         work(cx, &permit).await
#         // guard's Drop releases on any return path, cancellation or not
#
# Pick (a) for new types; (b) for fixing legacy code with complex ownership; (c) for read-modify-write critical sections.

# 7. Re-run the minimal-schedule replay; confirm balanced.
LAB_REPLAY_SCHEDULE="$MINIMAL_SCHED" \
  LAB_TRACE_OBLIGATIONS=full \
  cargo test --profile release-perf -p <crate> -- "$TEST" --nocapture \
  > "$WORKSPACE/cancel-leak/replay_postfix.log" 2>&1

awk '/Reserved obligation/{ res[$NF]++ } /Released obligation|Committed obligation/{ res[$NF]-- } END { for (k in res) if (res[k] > 0) print "LEAK:", k }' \
  "$WORKSPACE/cancel-leak/replay_postfix.log"
# No output = balanced = fix works.

# 8. Run full DPOR cancel-coverage; the test must pass under ALL enumerated schedules.
cargo test --profile release-perf -p <crate> -- "$TEST" --include-ignored --nocapture \
  > "$WORKSPACE/cancel-leak/dpor_full.log" 2>&1
grep -E 'schedule [0-9]+ : ok' "$WORKSPACE/cancel-leak/dpor_full.log" | wc -l
# Should be ≥ DPOR's enumerated schedule count from before the fix.

# 9. Check throughput hasn't regressed >5%.
"$WORKSPACE/scripts/run-narrow-benches.sh" "$PORT" "$WORKSPACE" --benches <perf-bench-touching-this-path>
diff <(jq '.summary' .bench-history/<bench>.latest.json) \
     <(jq '.summary' benchmark_report_*.json | tail -1)

# 10. Add `obligations_leaked_total == 0` as a permanent CI invariant.
# See assets/github-workflows/eprocess-ville-alarm.yml — add an `obligation_leak` invariant.

# 11. Create the bead.
br create \
  --title "asupersync-cancel-leak-${OBLIGATION_NAME//[\/:]/-}" \
  --priority 1 \
  --type bug \
  --labels "pillar:conformance,lane:cc_4,recipe:asupersync-cancel-leak,obligation:$OBLIGATION_NAME"

# 12. Three fresh-eyes reviewers, two clean rounds. One MUST be red-team-attacker.
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "asupersync-cancel-leak-${OBLIGATION_NAME//[\/:]/-}"
```

## Beads to claim (or create)

- `asupersync-cancel-leak-<obligation>` (this recipe creates it).
- Dependency: [`pattern:260-AGENT-MAIL-RESERVATIONS`](../patterns/260-AGENT-MAIL-RESERVATIONS.md) — the closest analog pattern (resource reservation lifecycle).
- Dependency: [`pattern:110-INVARIANT-CATALOG`](../patterns/110-INVARIANT-CATALOG.md) — the "obligations_leaked_total == 0" invariant goes here.
- Dependency: [`pattern:70-E-PROCESSES`](../patterns/70-E-PROCESSES.md) — `obligations_leaked_total` is monitored via e-process; rejection on Ville threshold means production leak.
- Dependency (test): `test-cancel-leak-${obligation}-minimal-schedule` — pins the minimal repro from this recipe.
- Dependency (test): `test-cancel-leak-${obligation}-dpor-coverage` — DPOR enumeration passes for all cancel schedules.
- Dependency (bench): `bench-${obligation}-path-throughput-postfix` — confirms throughput regression ≤5%.
- Dependency (doc): `doc-cancel-leak-${obligation}` — entry in `docs/progress/cancel-correctness/` summarizing leak + chosen fix shape.

## Exit Criteria

- [ ] Leak reproducible via minimal cancel schedule (saved under `<workspace>/cancel-leak/`).
- [ ] Leaked obligation pinned by name and reserve-site file:line.
- [ ] Hypothesis-ledger entry filed with all six fields.
- [ ] ≥2 isomorphic-rewrite options enumerated; chosen one has an isomorphism proof (cancel branch releases the same resources as the happy path).
- [ ] Minimal-schedule replay shows reserve/release balanced post-fix.
- [ ] Full DPOR cancel-coverage passes; enumerated schedule count ≥ pre-fix.
- [ ] Throughput regression on the affected path ≤ 5% (or explicit waiver with bead + rationale).
- [ ] `obligations_leaked_total == 0` invariant installed as e-process; production telemetry confirms.
- [ ] Three fresh-eyes reviewers ran; one was red-team-attacker enumerating new cancel points; two consecutive clean rounds.
- [ ] If the fix was rejected as "out of scope for this PR", a negative-ledger entry with the architectural-defer predicate per [Q-235](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-235--ccmd-43--architectural-defer-is-a-valid-retry-predicate) was filed.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Running the test once and concluding the leak is fixed. | Cancellation is schedule-dependent; without DPOR enumeration, you've tested one cancel point out of dozens. |
| Replacing `select!` with `if cancellation_token.is_cancelled() { return; }` style polling. | Defeats asupersync's cancel-at-await-points contract; reintroduces TOCTOU between check and reserve. |
| Adding a `tokio::spawn(async move { permit.release().await })` in the cancel branch. | The spawn itself can be cancelled; the release is now best-effort. Synchronous release in the cancel branch is the correct shape. |
| `let _ = permit;` to "drop" the obligation explicitly. | The `Drop` impl runs synchronously and may block on an async release; obligation pattern requires explicit `permit.release()` or async-safe Drop. |
| Skipping the throughput re-bench. | Adding a release on every cancel branch can introduce contention; per [Q-262](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-262--codexmd-1613--performance-claims-are-cell-level), cell-level perf must be verified. |
| "It's just a metric; production is fine." | Per [Q-212](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-212--ccmd-92--fourth-instance-universal-rule), there is almost always a fourth instance of any leak; the metric is the warning that you've shipped one. |
| Closing without the e-process invariant. | The next refactor reintroduces the leak; the e-process is the anti-repeat mechanism. |
| Treating cancel-correctness as a perf optimization. | It's a conformance issue: production correctness depends on bounded resource use. Per [Q-219](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-219--codexmd-1618--ssi-is-conformance-not-just-performance), correctness invariants land in the conformance pillar even when they "look like perf". |

## Cross-references

- [../patterns/260-AGENT-MAIL-RESERVATIONS.md](../patterns/260-AGENT-MAIL-RESERVATIONS.md) — closest analog: resource reservation lifecycle with TTL + audit.
- [../patterns/110-INVARIANT-CATALOG.md](../patterns/110-INVARIANT-CATALOG.md) — where `obligations_leaked_total == 0` lands.
- [../patterns/70-E-PROCESSES.md](../patterns/70-E-PROCESSES.md) — Ville-threshold monitoring for the leak rate in production.
- [../patterns/120-VERIFICATION-CONTRACT.md](../patterns/120-VERIFICATION-CONTRACT.md) — bead close requires the DPOR-coverage test + e-process invariant.
- [../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) — Phase 15 soak runs catch obligation-leak under long-duration load.
- [../methodology/TRIANGULATION.md](../methodology/TRIANGULATION.md) — DPOR is one of the two acceptable triangulators for concurrency claims.
- [../exemplars/QUOTE-BANK-V2-ADDITIONS.md § Q-218](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-218--ccmd-110--dpor-practical-reduction-factor) — DPOR practical reduction; explains why enumerated cancel testing is tractable.
- [../exemplars/QUOTE-BANK-V2-ADDITIONS.md § Q-263](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-263--codexmd-1616--inline-critical-vs-offloaded-is-a-safety-boundary) — inline-critical/offloaded safety boundary.
- [`embedding-cache-staleness.md`](embedding-cache-staleness.md) — sibling recipe for the cache-correctness side.
- Related motions: [`new-fault-class-discovered.md`](new-fault-class-discovered.md), [`e-process-rejection.md`](e-process-rejection.md), [`bocpd-shift-detected.md`](bocpd-shift-detected.md).
