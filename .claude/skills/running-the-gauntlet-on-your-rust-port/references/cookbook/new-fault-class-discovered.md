# new-fault-class-discovered

> A real-world failure surfaced that is NOT reproducible under any existing FaultKind in the fault VFS. Add it: design the FaultKind, build the injector, wire the crash boundary, add the recovery oracle, soak it.

## Trigger

Any of:

- A user-reported bug or post-mortem describes a failure mode the fault matrix doesn't exercise (e.g., "the disk returned partial-write under heavy IO pressure", "the kernel killed our process after writing N bytes of WAL", "the network connection silently dropped mid-handshake").
- A soak runner produces a `TrueDivergence` that none of the existing FaultKind scenarios reproduce.
- The CI `.github/workflows/fault-vfs-coverage.yml` posts an annotation noting the existing FaultKind set doesn't cover a class of behavior cited in the reference's spec.
- An upstream reference reports a fault-class fix; we need to test the port handles the same fault.

This is one of the larger gauntlet motions — adding a fault class typically takes 4-8 hours and produces 3-4 beads (FaultKind definition, injector, crash-boundary wiring, recovery oracle).

## Operator Pipeline

```
⚠ ESCALATE-TO-FRESH-REPRO   bundle the real-world failure with all available context
↓
⌘ REDUCE / MINIMIZE        find the minimal input pattern that exhibits the new failure mode
↓
⊞ SOAK                     after wiring, soak the new FaultKind through the recovery oracle
↓
🧪 EXPERIMENT-DESIGN       file the FaultKind design hypothesis BEFORE writing code
```

The Soak step is intentionally placed in the middle — once the injector is wired, the immediate question is whether the recovery oracle catches the failure deterministically over many iterations, not whether one repro works.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
FAULT_CLASS_NAME=<kebab-case name, e.g., partial-write-under-io-pressure>

# 1. Bundle the real-world failure (if available)
"$WORKSPACE/scripts/run-conformance-suite.sh" "$PORT" "$WORKSPACE" --no-fuzz
# Attach the real-world input path in the emitted FailureBundle / hypothesis ledger.

# 2. Mine: has this fault class been considered before?
"$WORKSPACE/scripts/mine-ledger.sh" "$WORKSPACE" --terms "$FAULT_CLASS_NAME" --filter "fault|crash|recovery|VFS"
"$WORKSPACE/scripts/mine-cass-cross-machine.sh" "$WORKSPACE" --term "$FAULT_CLASS_NAME" --window 60d

# 3. File the FaultKind design hypothesis
cat >> "$WORKSPACE/CONFORMANCE_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — fault-class-$FAULT_CLASS_NAME — investigating
- fault_class: $FAULT_CLASS_NAME
- precipitating_failure: <link to bundle>
- hypothesis: <one-sentence root cause; e.g., "WAL writer doesn't validate partial-write outcome before advancing checkpoint pointer">
- expected_signal: <which post-recovery assertion will fail until fixed>
- falsifiability: <e.g., "if injector exercises the path 1000x and recovery oracle is silent, fault class is mis-modeled">
- one_line_invocation: $WORKSPACE/scripts/run-fault-injection-matrix.sh $PORT $WORKSPACE
- results_inline: <fill after impl>
EOF

# 4. Create the umbrella bead + sub-beads
br create \
  --title "fault-class-$FAULT_CLASS_NAME" \
  --priority 1 \
  --type epic \
  --labels "pillar:conformance,lane:cc_4,recipe:new-fault-class-discovered,fault-class:$FAULT_CLASS_NAME"

EPIC_ID=$(br list --label "fault-class:$FAULT_CLASS_NAME" --json --limit 1 | jq -r '(.issues // .)[0].id')

for SUB in faultkind-definition injector crash-boundary-wiring recovery-oracle non-regression-test; do
  br create \
    --title "fault-class-$FAULT_CLASS_NAME-$SUB" \
    --priority 1 \
    --type task \
    --labels "pillar:conformance,lane:cc_4,recipe:new-fault-class-discovered,fault-class:$FAULT_CLASS_NAME" \
    --depends-on "$EPIC_ID"
done

# 5. Implement (via the fault-injector-author + crash-boundary-wirer subagents):

# 5a. FaultKind definition (in crates/conformance/src/fault_vfs/kinds.rs)
#     pub enum FaultKind {
#       ...,
#       PartialWriteUnderIoPressure {
#         bytes_actually_written: u32,
#         bytes_requested: u32,
#         io_queue_depth: u8,
#       },
#     }

# 5b. Injector (in crates/conformance/src/fault_vfs/injectors/)
#     impl FaultInjector for PartialWriteUnderIoPressure {
#       fn inject(&mut self, op: &mut WriteOp) -> InjectionOutcome { ... }
#     }

# 5c. Crash boundary wiring (in crates/conformance/src/crash_boundary/)
#     Identify which boundary the new fault hits (BeforeWalHeaderWrite, AfterFsync, etc.)
#     If none fit, add a new boundary (rare; the 8 named SQL boundaries are usually sufficient).

# 5d. Recovery oracle (in crates/conformance/tests/fault_recovery.rs)
#     Post-fault, the recovery oracle asserts: durability, atomicity, consistency, no-data-loss.

# 5e. Add to the fault matrix; verify it's exercised at least once per release CI run
$EDITOR "$PORT/crates/conformance/src/fault_vfs/matrix.rs"

# 6. Soak the new fault class
"$WORKSPACE/scripts/run-soak-campaign.sh" "$PORT" "$WORKSPACE" 24 --campaigns crash

# Expect: every iteration either: (a) doesn't trigger the fault, OR (b) triggers + recovery oracle catches it
# Any iteration where the fault triggers and the recovery oracle is silent = unfixed bug.

# 7. If real-world failure: ALSO fix the engine (not just add the fault class)
# Then re-soak: every iteration that triggers the fault now produces a clean recovery.

# 8. Ratchet
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/apply-ratchet.sh" "$WORKSPACE"
```

## Beads to claim (or create)

- Epic: `fault-class-<name>`.
- Sub-beads: `fault-class-<name>-faultkind-definition`, `-injector`, `-crash-boundary-wiring`, `-recovery-oracle`, `-non-regression-test`.
- Dependency: `pattern:60-FAULT-VFS` — fault VFS contract.
- Dependency: `pattern:65-CRASH-BOUNDARIES` — named boundary enumeration.
- Dependency: `pattern:70-E-PROCESSES` — recovery oracle invariants are typically e-process-monitored.
- Dependency: `pattern:90-FAILURE-BUNDLE` — real-world failure bundled.
- If engine fix also lands: chained to `oracle-div-<sig>` bead.
- Dependency (test): `test-fault-class-<name>-soak-10k-iters-green`.
- Dependency (bench): not typically required (fault paths are rarely perf-critical) but include if the new injector adds non-trivial cost to non-faulted paths.
- Dependency (doc): `doc-fault-class-<name>-design` — entry under `docs/progress/fault-classes/` describing the failure mode + the recovery contract.

## Exit Criteria

- [ ] Real-world failure bundled (if available); otherwise the synthetic motivating example is documented.
- [ ] Ledger mined for prior consideration.
- [ ] Hypothesis filed before code.
- [ ] FaultKind enum variant added with fields covering the fault's parameters.
- [ ] Injector implementation lands; `cargo test -p conformance --test fault_vfs_smoke` exercises it.
- [ ] Crash boundary wired (or new boundary added with rationale).
- [ ] Recovery oracle catches every triggering iteration; soak (10k iters minimum) reports zero silent failures.
- [ ] If real-world bug: engine fix also lands; soak rerun is clean.
- [ ] Fault matrix updated; CI workflow `fault-vfs-coverage.yml` exercises the new fault class.
- [ ] `apply-ratchet.sh` returns `Allow`; conformance lower bound stable or higher.
- [ ] Two fresh-eyes clean rounds.
- [ ] Documentation entry summarizes the failure mode + recovery contract.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Adding the FaultKind without the recovery oracle. | Injectors that fire without assertions are decorative; the gate is the oracle. |
| Adding the recovery oracle without the injector. | Untested invariants. The contract is "injector + oracle land together." |
| Skipping soak. | A FaultKind that "works" on one iteration may be silent 999 / 1000 times — that's not coverage. |
| Engine fix without FaultKind. | The bug recurs in 6 months; nothing exercises the path. |
| Reusing an existing crash boundary that doesn't match. | If the fault hits a boundary mid-stream that isn't named, add the boundary; don't shoehorn. |
| Closing the bead without the matrix update. | The fault class exists in code but never runs in CI; it's effectively undefined. |
| Fault parameters that aren't deterministic. | Schedule fingerprint contract: every injector must be deterministic given seed + schedule. |
| Treating the fault class as one-time, no non-regression test. | Test pins the contract; without it, the next refactor silently drops the coverage. |

## Cross-references

- [../patterns/60-FAULT-VFS.md](../patterns/60-FAULT-VFS.md) — fault VFS spec.
- [../patterns/65-CRASH-BOUNDARIES.md](../patterns/65-CRASH-BOUNDARIES.md) — named boundary enumeration.
- [../patterns/70-E-PROCESSES.md](../patterns/70-E-PROCESSES.md) — invariant-monitoring contract.
- [../patterns/90-FAILURE-BUNDLE.md](../patterns/90-FAILURE-BUNDLE.md) — real-world failure bundle.
- [../patterns/85-ADVERSARIAL-SEARCH.md](../patterns/85-ADVERSARIAL-SEARCH.md) — adversarial-search subagent often discovers new fault classes.
- [../taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md) — per-class crash boundaries.
- [../tooling/FUZZ-TOOLCHAIN.md](../tooling/FUZZ-TOOLCHAIN.md) — fuzz harness often produces the precipitating bundle.
- [../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) — soak duration per fault class severity.
- Related motions: [oracle-divergence-triage.md](oracle-divergence-triage.md), [e-process-rejection.md](e-process-rejection.md), [bocpd-shift-detected.md](bocpd-shift-detected.md).
