<!-- parity-runbook-template.md — skeleton for PARITY_RUNBOOK.md
     Copied by runbook-author at Phase 16 into <workspace>/.
     Maintenance-mode document the project's owners will read when wiring CI,
     onboarding contributors, or responding to a regression alert. -->

---
name: PARITY_RUNBOOK
schema_version: gauntlet.parity-runbook.v1
generated_at_utc: "<ISO_8601>"
run_id: "<run_id>"
port_name: "<port>"
project_class: "<sql|resp|numerical-python|ml-system|http-protocol>"
---

# PARITY_RUNBOOK — Keeping `<port>` at Parity with `<reference>` `<X.Y.Z>`

This runbook is the maintenance-mode operations manual. Read it when (a) onboarding a new contributor, (b) wiring CI gates, (c) responding to a regression alert. It is the durable counterpart to `FINAL_GAUNTLET_REPORT.md` (the snapshot at gauntlet exit).

## 1. CI Gates to Wire

Paste-ready GitHub Actions step blocks. Wire all 11.

### 1.1 Per-category-weighted score ratchet
```yaml
- name: Parity score ratchet
  run: |
    ./scripts/compute-parity-score.sh <workspace>
    ./scripts/apply-ratchet.sh <workspace>
  # exits non-zero on Block; Allow updates reports/ratchet_state.json
```

### 1.2 Pass-over-pass throughput gate
```yaml
- name: Bench pass-over-pass
  run: |
    ./scripts/run-bench-matrix.sh <target> <workspace>
    baseline=<workspace>/.bench-history/comprehensive_bench.latest.json
    candidate=<workspace>/artifacts/bench/comprehensive_bench/comprehensive_bench_report.json
    diff_pct=$(jq -n \
      --slurpfile baseline "$baseline" \
      --slurpfile candidate "$candidate" \
      '($candidate[0].summary.geomean_ratio / $baseline[0].summary.geomean_ratio - 1) * 100')
    # gate at -5% per parity_score_contract.toml
```

### 1.3 Conformance-lower-bound ratchet
```yaml
- name: Conformance ratchet
  run: ./scripts/compute-parity-score.sh <workspace>
```

### 1.4 Feature-coverage release-gate
```yaml
- name: Surface coverage
  run: ./scripts/compute-feature-coverage.sh <workspace>
```

### 1.5 E-process alarms
```yaml
- name: E-process Ville threshold
  run: |
    # any e-value crossing 1/α fails build + attaches FailureBundle
    cargo test --test eprocess_smoke -- --release
```

### 1.6 BOCPD regime alarms
```yaml
- name: BOCPD regime check
  run: |
    regime=$(jq -r '.terminal_regime' <workspace>/phase15_soak_bocpd/summary.json)
    case "$regime" in
      Stable) ;;
      ShiftDetected) echo "::error::BOCPD ShiftDetected"; exit 1 ;;
      *) echo "::warning::regime=$regime" ;;
    esac
```

### 1.7 Fault-VFS budget
```yaml
- name: Fault-VFS budget
  run: |
    # ensure every named fault profile was exercised at least once this CI run
    cargo test --test fault_vfs_coverage_smoke -- --release
```

### 1.8 Crash-boundary coverage
```yaml
- name: Crash boundaries all-armed
  run: |
    # assert every named CrashBoundary armed at least once per release
    cargo test --test crash_boundary_coverage_smoke -- --release
```

### 1.9 Flake budget
```yaml
- name: cv_pct flake budget
  run: |
    # quarantine microbenches with cv_pct > 5 on 3 consecutive runs
    python3 scripts/check_flake_budget.py .bench-history/
```

### 1.10 Bead-graph validator
```yaml
- name: Bead graph
  run: ./scripts/bead-graph-validator.sh <target> --output-root <workspace>
```

### 1.11 Convergence-tracker (advisory after release)
```yaml
- name: Convergence advisory
  if: always()
  run: ./scripts/convergence-tracker.sh <workspace> || true
```

## 2. Snapshots to Keep Green

`insta` snapshots the harness maintains. Regenerate ONLY when the underlying contract changes; never to make a red test green.

| Path | Regenerate command | Discipline |
|---|---|---|
| `<port>/tests/snapshots/planner__*.snap` | `cargo insta test --review -- planner` | Plan output; regenerate on planner-rule change |
| `<port>/tests/snapshots/vdbe__*.snap` | `cargo insta test --review -- vdbe` | Bytecode; regenerate on opcode change |
| `<port>/tests/snapshots/resp_frames__*.snap` | `cargo insta test --review -- resp_frames` | (RESP-class only) frame ordering |
| `<port>/tests/snapshots/openapi__*.snap` | `cargo insta test --review -- openapi` | (HTTP-class only) schema diff |
| `<port>/tests/snapshots/jit_ir__*.snap` | `cargo insta test --review -- jit` | (ML-class only) JIT-compiled IR |

## 3. Fuzz Corpora to Preserve

| Directory | Size (entries) | Last minimization | Regeneration cost |
|---|---|---|---|
| `<port>/fuzz/corpus/<target>/` | `<N>` | `<ISO>` | `<H>` hours @ rch |
| `<port>/proptest-regressions/` | `<N>` | (manual) | minutes |

## 4. `// SAFETY:` Template

Every `unsafe` block must carry:

```rust
// SAFETY:
// - Invariant: <the invariant being upheld>
// - Precondition: <what the caller must guarantee>
// - Postcondition: <what this block establishes>
// - Witness: <test / fuzz / miri run that exercises it>
unsafe { /* … */ }
```

## 5. Clippy Lint Group Minimum

Add to root `Cargo.toml`:

```toml
[workspace.lints.rust]
unsafe_op_in_unsafe_fn = "forbid"
missing_docs = "warn"

[workspace.lints.clippy]
pedantic = "warn"
missing_safety_doc = "deny"
undocumented_unsafe_blocks = "deny"
# Per-class additions:
# SQL: `clippy::float_cmp = "deny"` (parity affected by FP equality)
# RESP: `clippy::needless_collect = "warn"` (allocation hot paths)
# ML: `clippy::float_cmp = "forbid"` (replace with ULP-tolerant compare)
# HTTP: `clippy::large_enum_variant = "warn"` (heap-allocate large request types)
```

## 6. AGENTS.md Mandate Paragraph

Paste-ready (from `assets/agents-md-mandate-paragraph.md`). The paragraph mandates 60-day cass mining + ledger-grep + recent-commits check before any perf/conformance/surface-affecting change. Includes the project-class failure-term list:

> `<TOKEN_FAILURE_TERMS>` for `<this project class>`: see assets/agents-md-mandate-paragraph.md for the per-class list.

## 7. Negative-Ledger Format

| Field | Required? | Allowed values |
|---|---|---|
| `date` | yes | ISO 8601 |
| `candidate_name` | yes | kebab-case slug; unique |
| `target_workload` | yes | bench/behavior/feature id |
| `files_touched` | yes | reverted-uncommitted | kept-in-scratch | … |
| `correctness_proof` | yes | "all oracle E2E pass + selections= byte-identical" or equivalent |
| `evidence_artifact_paths` | yes | under `tests/artifacts/<lane>/` |
| `baseline_configuration` | yes | git SHA + CARGO_TARGET_DIR + iters + profile |
| `candidate_configuration` | yes | same |
| `measured_result` | yes | numbers + cv_pct |
| `retry_condition_predicate` | yes | one of 8 forms |

Sample entries:

```
### 2026-04-25 — handleview-hashset-to-sorted-vec — kept
- target_workload: ssi-commit-bench
- measured_result: 1674.8 → 970.8 ns/build (-42.0%, ~1.7x); cv_pct 2.1%
- retry_condition_predicate: N/A — kept
```

```
### 2026-04-12 — rowid-equality-term-reuse — rejected (within noise)
- target_workload: point-lookup
- measured_result: ~2% improvement; cv_pct 3.4%; ±3-5% noise band
- retry_condition_predicate: "Retry only if a profiler attributes a clearly-above-noise share to rowid_equality_extraction on a workload shape wider than point-lookup."
```

## 8. Retry-Condition Vocabulary

The 8 verbatim templates (full detail: `references/methodology/RETRY-CONDITION-VOCABULARY.md`):

1. `"Retry only if a profiler attributes a clearly-above-noise share to <COUNTER> on <WORKLOAD_SHAPE>."`
2. `"Reconsider only inside the broader <X> redesign (track as <beads_id>)."`
3. `"Worth reconsidering when <GATE> crosses <THRESHOLD>."`
4. `"Not worth retrying as a standalone patch."`
5. `"Do not retry from a cold read; use comprehensive-bench attribution instead."`
6. `"Retry condition not applicable — the gain is structural, not numerical."`
7. `"Retry only if this workload class exhibits measurable <PROPERTY> below <THRESHOLD>."`
8. `"Blocked until <ARCHITECTURAL_DEPENDENCY> lands; track as <beads_id>."`

## 9. When To Escalate

- E-value crosses `1/α` on any monitored invariant.
- BOCPD reports `ShiftDetected` for 2+ consecutive windows.
- Conformal lower-bound drops below ratchet floor.
- FeatureUniverse loader rejects on `sum(weights) != 1.0` (catches accidental weight rebalance without an explicit revision bump).
- cv_pct > 5 three runs in a row on the primary bench.
- New `TrueDivergence` from a soak runner that wasn't in any prior round.

Escalation = open a P0 beads issue + page the on-call + freeze further merges until triaged.

## 10. Resuming the Gauntlet

When the port's main branch has moved forward and you want to re-run the gauntlet against the new state:

```bash
cd ~/.claude/skills/running-the-gauntlet-on-your-rust-port
./scripts/init-workspace.sh <target> <workspace>
./scripts/oracle-preflight-doctor.sh <target> --workspace <workspace>    # MUST be green before re-entering loop
./scripts/run-bench-matrix.sh <target> <workspace>            # writes new .bench-history entry
./scripts/run-conformance-suite.sh <target> <workspace>
./scripts/compute-parity-score.sh <workspace>
./scripts/apply-ratchet.sh <workspace>
```

If the new state introduces ANY regression vs the ratchet floor, the iteration-coordinator will refuse to enter the convergence loop until the regression is closed via Phase 12 remediation.

Full per-phase playbook: `references/PHASES.md`.

---

*Generated by the running-the-gauntlet-on-your-rust-port skill at Phase 16. Living document — update on every gauntlet pass.*
