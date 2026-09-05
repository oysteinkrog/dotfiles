# THREE-PILLARS.md — Performance / Conformance / Surface-Parity Decomposition

The gauntlet is the conjunction of three pillars. Each pillar has its own question, headline artifact, gate type, threshold table, detection arsenal, failure-mode catalog, and per-phase mapping. **The agent is forbidden from declaring victory on one pillar while another regresses.** Pillar isolation is the single most common failure mode of a "we shipped it" claim against a mature reference.

Cross-references: [`../SKILL.md`](../SKILL.md), [`PHASES.md`](PHASES.md), [`taxonomy/PROJECT-CLASSES.md`](taxonomy/PROJECT-CLASSES.md), [`taxonomy/FEATURE-UNIVERSE.md`](taxonomy/FEATURE-UNIVERSE.md), [`taxonomy/INVARIANT-CATALOG.md`](taxonomy/INVARIANT-CATALOG.md), [`tooling/ORACLE-TOOLCHAIN.md`](tooling/ORACLE-TOOLCHAIN.md), [`tooling/BENCH-TOOLCHAIN.md`](tooling/BENCH-TOOLCHAIN.md), [`methodology/KEEP-GATE-RULES.md`](methodology/KEEP-GATE-RULES.md), [`methodology/CONFORMAL-RATCHET.md`](methodology/CONFORMAL-RATCHET.md).

---

## Pillar (a): PERFORMANCE

### Question
"Is the port actually faster than the reference on this workload, measured honestly?"

### Headline Artifact
- `comprehensive-bench` JSON v3 report (`schema_version = "fsqlite-e2e.comprehensive-bench-report.v3"` or project equivalent)
- `.bench-history/<bench>.latest.json` committed to git
- Per-category weighted score (`per_category_weighted.score`) — NOT the raw average ratio

### Gate Type
**Pass-over-pass ratchet.** The previous run is committed to a file (`.bench-history/<bench>.latest.json`); the current run's gate is computed relative to that file. "Pass-over-pass gate is a *file*. `.bench-history/*.latest.json` is committed. You can't bench on your machine, see a 30% drop, and quietly not commit."

### Thresholds (Verbatim from `comprehensive_bench.rs` JSON v3)
```jsonc
"ci_regression_gate": {
  "schema_version": "fsqlite-e2e.comprehensive-bench-ci-regression-gate.v2",
  "primary_score_max_regression_pct": 0.03,        // primary score: -3%
  "geomean_max_regression_pct": 0.05,              // geomean: -5%
  "category_geomean_max_regression_pct": 0.10,     // per-category: -10%
  "p90_max_regression_pct": 0.15                   // p90: -15%
}
```

Plus, from the pass-over-pass logic in `.bench-history`:
```rust
const PASS_OVER_PASS_MAX_RATIO_DROP_PCT: f64 = 5.0;   // throughput: -5%
let ratio_drop_pct = ((previous_ratio - row.throughput_ratio) / previous_ratio) * 100.0;
if ratio_drop_pct > PASS_OVER_PASS_MAX_RATIO_DROP_PCT { /* RatioRegression */ }
```

**The full threshold table:**

| Metric | Max regression |
|---|---|
| Primary score (per_category_weighted.score) | **−3%** |
| Geomean ratio | **−5%** |
| Per-category geomean | **−10%** |
| p90 ratio | **−15%** |
| Pass-over-pass throughput ratio | **−5%** |

**Defaults for the regression detector (median + MAD; `performance_regression_detector.rs`):**

| Metric | Warning | Critical |
|--------|---------|----------|
| Latency ratio | 1.10x | 1.25x |
| Throughput drop | −10% | −20% |

### Detection Arsenal
- `comprehensive_bench.rs` (6,040 LOC; 93+ scenarios; six timing constants `WARMUP_ITERS=2, MIN_ITERS=3, MAX_ITERS=10, TARGET_DURATION=5s`)
- `mt_mvcc_bench.rs` (1,445 LOC; N OS threads × file-backed DB × `BEGIN CONCURRENT`)
- `mt_oltp_bench.rs` (914 LOC; 4 readers + 2 writers; Jain fairness)
- `perf_update_delete.rs` (1,497 LOC; DML-isolation matrix)
- `swarm_multiprocess.rs` (79 KB; N child processes on same WAL DB; `DEFAULT_SECONDS=60`, `DEFAULT_SEED=0x4653_514C_5357_4152` "FSQLSWAR")
- `HotPathProfileSnapshot` per-domain counters (see [`taxonomy/PROJECT-CLASSES.md § hot-path counters`](taxonomy/PROJECT-CLASSES.md))
- `cargo-flamegraph` + `samply` + `dhat` + `heaptrack` + `strace` + `perf` triangulation
- `performance_regression_detector.rs` (median + MAD; distribution-free; outlier-robust)
- `perf_loop.rs` validator (asserts the 19-field proof-pack card populated)
- MT8 attribution discipline: profile under 8-thread multi-writer load; "**Each frame ≥0.1% is a *candidate***"; below 0.1% is the **micro-lever trap**

### Failure Modes
| Failure | Tell-tale | Defense |
|---|---|---|
| Cherry-picked baseline | "It was faster last week" without a committed file | `.bench-history/<bench>.latest.json` in git |
| Cold-start outlier | First sample after `target/` rebuild looks great | `WARMUP_ITERS=2` discards them; refresh entries are baseline captures only |
| Within-noise win | "≤ cv_pct band" claimed as improvement | "within noise" = not a win, technically also not a loss; quote cv_pct band |
| Focused improved, broad worsened | DML 10K improves, primary score drops | **Both gates must move in same run window** (same git, same `target/`, same machine, same minute) |
| Concurrent-mode silently off | Feb 2026 incident: agent disabled concurrent mode, project missed it | `concurrent_mode_default_guard.txt` in every artifact lane |
| Size-optimized release profile | `--release` instead of `release-perf` | LTO + codegen-units differences swamp signal; use `release-perf` profile |
| Population inside timed window | Setup work measured | `measure_with_teardown`: teardown OUTSIDE `start.elapsed()` |
| Behavior-changing "correctness-abandoned" | Oracle tests fail mid-optimization | A behavior-changing candidate is a different question entirely; `selections=` counts byte-identical required |
| No bounded micro-lever | Optimization effort on sub-0.1% hotspots | Reject; team looked and found no few-ns win |
| Plausible hypothesis without profile | "Parser is slow" without ranked hotspot table | Profile-first; no hotspot list → no change |
| Fused-design micro-optimization | Localized fix on one half of fused operator | Reject; "reconsider only inside the broader X redesign" |
| MT8 attribution missing | "It's faster" without quoted frame citation | Required form: "Closed 0.44% MT8 PublishedPages::clear residual" |

### Per-Phase Mapping
- **Phase 0:** `release-perf` profile installed; `concurrent_mode_default_guard.txt` template in place
- **Phase 5:** Build `comprehensive_bench.rs` + focused benches + `HotPathProfileSnapshot` per [`taxonomy/PROJECT-CLASSES.md`](taxonomy/PROJECT-CLASSES.md); seed `.bench-history/` baseline
- **Phase 8:** Seed `docs/progress/perf-negative-results.md` with the verbatim preamble + retry-condition vocabulary
- **Phase 9:** First full baseline run; commit `.bench-history/<bench>.latest.json`; produce per-focused-bench flamegraph / samply / dhat / strace
- **Phase 10:** Idea-wizard generates perf hypotheses → `GAUNTLET_EXPERIMENT_DESIGNS.md`
- **Phase 11:** Each round re-runs Phase 5–9; convergence-tracker counts new perf findings; ledger entries grow with retry-condition predicates
- **Phase 12:** Per-pillar perf architect enumerates 2+ isomorphic rewrites; per-proposal gate `Impact × Confidence / Effort ≥ 2.0`
- **Phase 14:** Fresh-eyes reviewer-c looks specifically for hidden perf regressions in remediation diffs
- **Phase 15:** Soak runs perf benches over multi-day window; BOCPD asserts `Stable` regime on parity-score stream
- **Phase 16:** `FINAL_GAUNTLET_REPORT.md` perf section embeds `.bench-history/<bench>.latest.json` content + flamegraphs

---

## Pillar (b): CONFORMANCE

### Question
"Does the port produce the same answer as the reference for the same input, including under fault and crash?"

### Headline Artifact
- Differential V2 envelope: `artifact_id = SHA-256 of canonical JSON excluding run_id` (content-addressed; two runs with identical semantic inputs produce identical artifact ID even with different `run_id`)
- Metamorphic corpus (`crates/<port>-harness/src/metamorphic.rs` — `TransformFamily`, `EquivalenceExpectation`, `MismatchClassification`)
- Crash-boundary recovery proof (one paired arming test per `CrashBoundary` variant)
- E-process invariants (`crates/<port>-harness/src/eprocess.rs` — 8 monitored invariants for SQL, class-equivalent for others)
- `FailureBundle` per divergence with `first_divergence_jsonptr = /failure/first_divergence`

### Gate Type
**Conformal lower-bound ratchet.** Beta posterior per category × pass rate, distribution-free conformal band, release decisions use the **LOWER bound, not the point estimate**; `truncate_score` to 6 decimal places for cross-platform byte-identity.

Quoting the scoring model:
> Passing → success (1.0, weighted by feature weight)
> Partial → fractional success (0.5, weighted)
> Missing → failure (0.0, weighted)
> Per-category pass rate `theta_c ~ Beta(α_prior + Σ weighted_successes, β_prior + Σ weighted_failures)`
> Global score `S_t = weighted sum of category posterior means`
> **Lower confidence bound for release decisions**

Plus the e-process side:
> `P_{H_0}(∃t: E_t ≥ 1/α) ≤ α`. Anytime-valid: check after every operation, reject when crosses `1/α`, **no Bonferroni correction needed**.

### Thresholds (Verbatim)

**E-process calibration:**
- Hardware-enforced (CAS guarantees): `p₀ = 1e-9, λ = 0.999, α = 1e-6` (INV-1, INV-2, INV-7 for SQL)
- Software-enforced: `p₀ = 1e-6, λ = 0.9, α = 0.001` (INV-3, INV-4, INV-5, INV-6 for SQL)
- Global E-Value (arithmetic mean): `E_global(t) = Σ wᵢ Eᵢ(t)` with equal `wᵢ = 1/7`. "Arithmetic mean of e-processes is itself an e-process under the global null *regardless of dependence*."

**Conformal bands:** "Distribution-free finite-sample coverage. Calibrated from per-category residuals (frequentist vs Bayesian gap). `P(R_{n+1} ≤ q) ≥ 1 − α` for any distribution. Cost: wider intervals. Benefit: honest under heavy-tailed / bimodal / regime-shifting distributions."

**`truncate_score`:** "truncate to 6 decimal places. x86 vs ARM vs WASM differ at LSB; truncation ensures bytewise identical scores regardless of CPU."

**MismatchClassification:** "CI fails ONLY on `TrueDivergence`. Other classes flow into triage queue."
```rust
pub enum MismatchClassification {
    TrueDivergence { description: String },          // triage_priority 0
    OrderDependentDifference,                        // triage_priority 4
    TypeAffinityDifference,                          // triage_priority 2
    NullHandlingDifference,                          // triage_priority 1
    FloatingPointDifference { max_epsilon_str: String }, // triage_priority 3
    FalsePositive { reason: String },                // triage_priority 5
}
```

**Three-tier equivalence (golden artifacts):**
```rust
pub enum EquivalenceTier {
    Tier1Raw,         // raw SHA-256 byte equality
    Tier2Canonical,   // after normalization (VACUUM INTO + stable PRAGMAs / torch.use_deterministic_algorithms)
    Tier3Logical,     // logical deterministic SQL or tensor dump (row count + columns + values via ==)
}
```
> "Encode the distinction; never paper over it." A Tier2 match is not Tier1; the JSON report must name which tier succeeded.

### Detection Arsenal
- 30-line `scenario()` template (`crates/<port>-harness/src/oracle.rs`): both-error = agreement, one-error-one-OK = hard failure
- `differential_v2.rs` (`ExecutionEnvelope` + `artifact_id()` SHA-256 of canonical JSON excluding `run_id`)
- `EngineIdentity` discriminator (`SUBJECT_IDENTITY_LABEL = "frankensqlite"`, `REFERENCE_IDENTITY_LABEL = "csqlite-oracle"`) — prevents oracle-on-oracle false greens
- `oracle_preflight_doctor.rs` (green/yellow/red verdict; `certifying: true` ONLY for green)
- `metamorphic.rs` — four `TransformFamily` variants: Predicate / Projection / Structural / Literal
- `mismatch_minimizer.rs` — binary partition → recursive narrowing → 1-minimal → schema preservation
- `replay_harness.rs` with BOCPD regime detection (`Regime::{Stable, Improving, Regressing, ShiftDetected}`; hazard `H = 1/250`; Normal-Gamma for throughput, Beta-Binomial for abort rates)
- `fault_vfs.rs` with 8 `FaultKind` variants (TornWrite / PartialWrite / PowerCut / IoError / ReadFailure / WriteFailure / Latency / DiskFull); `DEFAULT_FAULT_SEED = 0xD1A6_A3F4_9B17_0C5E`
- 8 named crash boundaries for SQL (see [`taxonomy/PROJECT-CLASSES.md § crash boundaries`](taxonomy/PROJECT-CLASSES.md))
- `eprocess.rs` 8 monitored MVCC invariants for SQL; class-equivalent invariants for other classes
- `failure_bundle.rs` with `first_divergence_jsonptr` populated
- `e2e_log_schema.rs`: `LOG_SCHEMA_VERSION = "1.0.0"`; required event fields `run_id, timestamp, phase, event_type`; replayability keys `scenario_id, seed, phase, context.invariant_ids, context.artifact_paths`
- `cargo-fuzz` / `cargo-afl` / `bolero` differential targets
- `loom` + `shuttle` for concurrency conformance

### Failure Modes
| Failure | Tell-tale | Defense |
|---|---|---|
| Oracle compared against itself | Apparent 100% pass rate | `EngineIdentity` discriminator + preflight doctor check `subject_identity != reference_identity` |
| Both-error treated as failure | Comparator panics on `(Err, Err)` | `(Err(_), Err(_)) => agreement REGARDLESS of message text` |
| One-error-one-OK swept under rug | Test passes despite mismatch | `(Ok, Err)` or `(Err, Ok)` → **hard failure** |
| `artifact_id` non-deterministic | Two identical semantic runs produce different IDs | `CanonicalEnvelope` MUST strip `run_id` before hashing |
| First-divergence pointer empty | `/failure/first_divergence` not set | Mismatch-minimizer must reach 1-minimal before bundling |
| Metamorphic relation too weak | `SetEquivalence` where `ExactRowMatch` is sound | Tighten to strongest sound class; add soundness-proof sketch |
| Mismatch dedup broken | Same root cause reopens as new beads | `MismatchSignature.hash` (truncated SHA-256 of canonical minimal repro) for dedup |
| Fault VFS non-deterministic | Torn-write valid-bytes count drifts | Pin `DEFAULT_FAULT_SEED`; `FaultSpec.trigger_count` and `match_count` deterministic |
| Crash recovery non-deterministic | Same crash boundary yields different state | Add `assert!(state.is_initialized())` at recovery entry |
| E-process global e-value > 1/α with no real violation | False rejection | Calibration too tight; adjust per-invariant `p₀` or `λ` per [`taxonomy/INVARIANT-CATALOG.md § calibration`](taxonomy/INVARIANT-CATALOG.md) |
| Tier-2 match labeled as Tier-1 | Byte-equal claim is actually canonical | "Encode the distinction; never paper over it" — JSON report must name which tier |
| `FailureBundle` skipped on partial state | "Couldn't bundle, no state to dump" | "A partial bundle with provenance is more valuable than no bundle. **Never skip manifest writing on failure.**" |

### Per-Phase Mapping
- **Phase 3:** Wire `oracle.rs`, `differential_v2.rs`, `engine_identity.rs`, `oracle_preflight_doctor.rs`
- **Phase 4:** Golden capture per tier (Tier 1 byte / Tier 2 canonical / Tier 3 logical) + `manifest.v1.json` + `checksums.sha256`
- **Phase 6:** Build entire conformance harness — oracle E2E per behavior class, `metamorphic.rs`, `mismatch_minimizer.rs`, `fault_vfs.rs`, `fault_hooks.rs` per crash boundary, fuzz targets, `eprocess.rs` per invariant, `failure_bundle.rs`
- **Phase 8:** Seed `docs/progress/conformance-negative-results.md`
- **Phase 9:** First conformance baseline; every divergence emits a `FailureBundle` with `first_divergence_jsonptr` populated
- **Phase 11:** Each round adds new metamorphic transforms, fuzz targets, e-process invariants; convergence-tracker counts new `TrueDivergence` findings
- **Phase 12:** Conformance architect must propose changes that raise the conformal LOWER bound AND not lower any per-category bound
- **Phase 15:** Soak fuzz 24h+, Miri multi-day, loom/shuttle ≥10,000 interleavings, crash-boundary ≥1,000 iterations per boundary, BOCPD multi-day on parity-score stream (must be `Stable` regime)
- **Phase 16:** Certification bundle includes confidence-gate JSON + verification-contract JSON + release-certificate JSON

---

## Pillar (c): SURFACE-PARITY

### Question
"What fraction of the reference's declared surface does the port implement, and what fraction is explicitly excluded?"

### Headline Artifact
- `FeatureUniverse` (`crates/<port>-harness/src/parity_taxonomy.rs`): `Feature { id, title, weight, status, exclusion_rationale }`
- `SurfaceMatrix` (`docs/contracts/supported_surface_matrix.toml`): every feature declares `supported | partial | excluded` with rationale
- `InvariantCatalog` (`crates/<port>-harness/src/invariant_catalog.rs`): `ParityInvariant` + `ProofObligation` + `ArtifactRef` (see [`taxonomy/INVARIANT-CATALOG.md`](taxonomy/INVARIANT-CATALOG.md))
- `feature_coverage_dashboard` per-family verdict (`none | partial | full`)

### Gate Type
**Feature-coverage release-gate.** Per-family verdict mapped to release-gate verdict. **Partial never rounds up to success.** Excluded items still count as coverage debt for a strict-100% claim.

`ParityStatus` enum (see [`taxonomy/FEATURE-UNIVERSE.md`](taxonomy/FEATURE-UNIVERSE.md)):
```rust
pub enum ParityStatus {
    Passing,   // present + Tier-N equivalence holds
    Partial,   // present, conformance gaps known
    Missing,   // absent, would be in-scope
    Excluded,  // intentionally out of scope; counts as coverage debt for strict-100%
}
```

### Thresholds (Verbatim)

**Three loader-enforced invariants** (`parity_taxonomy.rs`):
1. `sum(weights) == 1.0` per category enforced by loader
2. `truncate_score` for cross-platform reproducibility (6 decimal places)
3. `FeatureUniverse::features()` returns sorted by `FeatureId` for deterministic iteration → deterministic scoring → meaningful SHA-256 of report

**Verification-contract enforcement** (`verification_contract_enforcement.rs`):

| Status | Base Gate | Meaning |
|--------|-----------|---------|
| `pass` | allowed | contract holds |
| `fail-missing-evidence` | blocked-by-contract | required proof absent |
| `fail-invalid-references` | blocked-by-contract | artifact paths don't resolve |
| `fail-mixed` | blocked-by-both | both gate and contract failures |

**Allowed feature-status transitions:**
- `Missing → Partial → Passing` — promotion direction (allowed)
- `Partial → Passing` — promotion (allowed)
- `Passing → Partial` — **regression; rejected** at Phase 12
- `Passing → Missing` — **regression; rejected** at Phase 12
- `Excluded → Partial → Passing` — promotion (allowed, but the exclusion-rationale needs retirement)
- Any → `Excluded` — allowed only with rationale + retry-condition predicate in `supported_surface_matrix.toml`

### Detection Arsenal
- `parity_taxonomy.rs` — `Feature`, `FeatureId`, `FeatureUniverse`
- `invariant_catalog.rs` — `ParityInvariant`, `ProofObligation` (7 `ProofKind` variants: `OracleDifferential`, `MetamorphicProperty`, `ProptestInvariant`, `CrashBoundary`, `EProcess`, `FuzzNonPanic`, `InstaSnapshot`); `ArtifactRef { path, hash, schema_version }`
- `feature_coverage_dashboard.rs` — per-family verdict
- `validation_manifest.rs` — aggregated proof index
- `verification_contract_enforcement.rs` — the 4×4 matrix above
- `closure_wave.rs` — enumerate the universe of behaviors for a pipeline stage, then observe which the engine handles (current domains: `Parser`, `Resolver`, `Pragma`)
- `ast-grep` + `syn`-walkers for surface enumeration: `pub fn`, `pub struct`, `impl ... for ...`, `#[no_mangle]`, `extern "C"`, `PRAGMA <name>`, `Opcode::<name>`, `pub const COMMAND_<name>`, `#[command]`, `#[pyfunction]`, `pub struct ... HandlerExt`
- `cargo doc --document-private-items` for reference-side enumeration
- `cargo-geiger` for unsafe-surface inventory
- `cargo-deny` + `cargo-audit` for dependency-surface inventory

### Failure Modes
| Failure | Tell-tale | Defense |
|---|---|---|
| Weight sum != 1.0 per category | Loader silently normalizes | Loader rejects; document rebalance in `parity_score_contract.toml` changelog |
| Iteration non-deterministic | HashMap ordering | Use `BTreeMap` or sort-on-iteration; verify with cross-platform CI |
| `truncate_score` differs across platforms | f64-rounded truncation | Use integer arithmetic; see [`methodology/CONFORMAL-RATCHET.md § truncate_score`](methodology/CONFORMAL-RATCHET.md) |
| Invariant with zero `ProofObligation` | Catalog passes validation despite gap | Add proof obligation or mark `Excluded` with rationale |
| Partial rounded up to full | "We have it" when 60% of edges fail | `Partial` never rounds up; per-family verdict shows `partial` |
| Excluded items dropped from coverage debt | Strict-100% claim hides exclusions | Excluded counts as coverage debt; `release_traceability()` lists them |
| Surface added without retry condition | "We'll get to it" | Loader rejects rows with empty `rationale` or `retry_condition` |
| `ArtifactRef.hash` stale | Proof obligation points at moved artifact | `validate()` returns `Vec<Violation>` with broken `ArtifactRef` |
| `pub` surface enumeration incomplete | Macro-generated symbols missed | Run `cargo doc --document-private-items`; cross-check |
| Surface regression on bead close | Bead closed without surface-impact check | `verification_contract_enforcement` blocks bead close with `fail-missing-evidence` |
| Architectural change dressed as micro-optimization | Surface signature changed without contract update | Reject; "reconsider only inside broader X redesign"; surface change requires Phase 2 reopen |

### Per-Phase Mapping
- **Phase 1:** Per-crate `phase1_recon_<crate>.md` enumerates `pub fn`, `pub struct`, `pub trait`, `pub macro`, `pub use` for both subject and reference
- **Phase 2:** `supported_surface_matrix.toml` — every reference symbol classified `present | partial | missing | n/a | excluded` with rationale; `parity_score_contract.toml` weights sum to 1.0 per category
- **Phase 7:** Build `parity_taxonomy.rs`, `invariant_catalog.rs`, `feature_coverage_dashboard.rs`, `validation_manifest.rs`, `verification_contract_enforcement.rs`
- **Phase 8:** Seed `docs/progress/surface-deferrals.md`
- **Phase 9:** Initial `feature_coverage.json` per-family verdict; `parity_score.json` with Beta posterior + conformal-band + lower-bound + truncated
- **Phase 11:** Each round expands `FeatureUniverse` entries, retires `Excluded` items with documented rationale, promotes `Partial → Passing`
- **Phase 12:** Surface architect must NOT regress any feature from `Passing` to `Partial` or worse
- **Phase 15:** Adversarial-search probes the feature-coverage gate (does it allow a `Partial` to slip through?)
- **Phase 16:** Certification template `RELEASE_CERTIFICATION_TEMPLATE.md` requires `CERTIFICATION_MIN_VERIFICATION_PCT = 100.0`

---

## Forbidden-Victory Rule

> **The agent is forbidden from declaring victory on one pillar while another regresses.**

Concrete enforcement:

| Scenario | Verdict |
|---|---|
| Perf primary score +5%, conformance lower bound −2% | **BLOCKED.** The conformance regression beats the perf win. |
| Conformance lower bound +3%, surface `Passing → Partial` on any feature | **BLOCKED.** Surface regression dominates. |
| Surface coverage `+10 Passing` features, perf p90 −20% | **BLOCKED.** Perf regression exceeds gate. |
| All three pillars within gate, one bead closed without retry-condition predicate | **BLOCKED.** Negative-ledger discipline is non-negotiable. |
| All three pillars green, Phase 14 fresh-eyes not run twice clean | **BLOCKED.** Phase 14 termination gate not satisfied. |

The `scripts/convergence-tracker.sh` reads all three ledgers AND the four hypothesis ledgers (`GAUNTLET_EXPERIMENT_DESIGNS.md`, `PERF_HYPOTHESIS_LEDGER.md`, `CONFORMANCE_HYPOTHESIS_LEDGER.md`, `SURFACE_PARITY_HYPOTHESIS_LEDGER.md`) and exits non-zero if any pillar shows a regression in the current round vs the previous round, regardless of the headline number on the other two pillars.

The `FINAL_GAUNTLET_REPORT.md` top-line verdict is `CERTIFIED` only when **all three** pillars pass simultaneously in the **same run window** (same git SHA, same `.bench-history/` state, same `feature_coverage.json` snapshot, same `parity_score.json` lower bound). Any pillar yellow flips the top-line to `BLOCKED`.

---

## Per-Pillar Subagent Lane Assignment (cc_N Convention)

Per FrankenSQLite's `cc_1 / cc_2 / cc_3 / cc_4` convention. Soft assignment by pillar; agents may cross lanes, but stay-in-lane minimizes MCP Agent Mail reservation collisions.

| Lane | Pillar | Subagents | Reservations |
|---|---|---|---|
| **cc_1** | Conformance / oracle / differential / metamorphic / fault / crash-boundary | `subagents/oracle-wirer.md`, `subagents/oracle-test-author.md`, `subagents/metamorphic-author.md`, `subagents/mismatch-minimizer-builder.md`, `subagents/baseline-runner-conformance.md` | `tool://oracle-runner`, `workspace://crates/<port>-harness/src/{oracle,differential_v2,metamorphic,mismatch_minimizer}.rs`, `workspace://round_<N>/conformance/` |
| **cc_2** | Performance / benches / profile-cards / hot-path counters / regression detector | `subagents/bench-author.md`, `subagents/hot-path-counter-instrumenter.md`, `subagents/baseline-runner-perf.md` | `tool://comprehensive-bench`, `workspace://crates/<port>-e2e/src/bin/{comprehensive_bench,*_bench}.rs`, `workspace://round_<N>/perf/`, `resource://host-cores` |
| **cc_3** | Surface parity / coverage / feature universe / invariant catalog | `subagents/feature-universe-builder.md`, `subagents/invariant-catalog-builder.md`, `subagents/coverage-dashboard-builder.md`, `subagents/baseline-runner-surface.md` | `workspace://crates/<port>-harness/src/{parity_taxonomy,invariant_catalog,feature_coverage_dashboard,validation_manifest,verification_contract_enforcement}.rs`, `workspace://docs/contracts/`, `workspace://round_<N>/surface/` |
| **cc_4** | Fault / crash / soak / e-process / BOCPD / adversarial search | `subagents/fault-injector-author.md`, `subagents/crash-boundary-wirer.md`, `subagents/eprocess-modeler.md`, `subagents/soak-runner-fuzz.md`, `subagents/soak-runner-miri.md`, `subagents/soak-runner-loom.md`, `subagents/soak-runner-crash-boundary.md`, `subagents/soak-runner-bocpd.md`, `subagents/soak-runner-adversarial.md` | `tool://fuzz-corpus`, `workspace://crates/<port>-harness/src/{fault_vfs,eprocess,failure_bundle}.rs`, `workspace://crates/<port>-wal/src/fault_hooks.rs`, `resource://rch-worker-pool`, `workspace://soak/` |

Coordination thread IDs: `gauntlet-<run-id>-phase<N>-<bucket>` where bucket includes the lane (e.g., `gauntlet-20260522-1430-abc123-phase6-fault-TornWrite`).

---

## Per-Pillar Negative Ledger

Each pillar has its own ledger; entries cannot migrate between ledgers without explicit reclassification.

### `docs/progress/perf-negative-results.md`
- Preamble (verbatim):
  > "This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass, and add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction."
- Mandatory fields per entry: `date`, `bead_id` (if applicable), `idea`, `measurement` (with `cv_pct`), `verdict` (`rejected | within-noise | correctness-abandoned | pulled | reconsider-architectural | deferred-architectural`), `retry_condition` (verbatim predicate from [`methodology/RETRY-CONDITION-VOCABULARY.md`](methodology/RETRY-CONDITION-VOCABULARY.md))
- Common verdicts: "within noise", "no bounded micro-lever found", "focused improved, broad worsened", "fused-design micro-optimization", "cold-start outlier"

### `docs/progress/conformance-negative-results.md`
- Same preamble adapted for conformance: ideas were measured and the conformance/oracle/metamorphic/crash/fault gates did not move in the intended direction
- Mandatory fields: `date`, `bead_id`, `idea`, `oracle_run_id`, `mismatch_signature_hash`, `classification` (one of the 6 `MismatchClassification` variants), `verdict`, `retry_condition`
- Common verdicts: "TrueDivergence root cause not in subject (reference quirk)", "metamorphic relation too weak; tightened", "fault-VFS schedule not reproducible", "BOCPD detected `ShiftDetected` but window calibration was wrong"

### `docs/progress/surface-deferrals.md`
- Preamble: surface items deferred or explicitly excluded; consulted before promoting `Missing → Partial → Passing`
- Mandatory fields: `date`, `feature_id` (e.g., `F-SQL-042`), `surface_category` (e.g., `recursive-CTE`, `JSON1-extension`), `current_status`, `target_status`, `blocker`, `retry_condition`
- Common verdicts: "Excluded; reference depends on PRNG seed we can't reproduce", "Partial; only 8 of 23 subcases pass", "Missing; architectural prereq is bd-XXXXX"

The cass-mining 60-day grep paragraph in AGENTS.md is mandatory before any perf/conformance work begins: failure terms `rejected, reverted, abandoned, slower, regressed, didn't help, within noise, no improvement, failed to improve, rolled back, backed out, not a keep, keep gate`, plus the project-specific terms from [`taxonomy/PROJECT-CLASSES.md § failure-terms`](taxonomy/PROJECT-CLASSES.md).

---

## Summary: Subject / Oracle / Comparator Across 8 Quality Concerns

Reproduced verbatim from MINING-2 §summary:

| Pillar | Subject | Oracle | Comparator |
|---|---|---|---|
| Behavioral oracle | `fsqlite::Connection` | `rusqlite::Connection` | string render of rows |
| Differential V2 | `FsqliteExecutor` | `CsqliteExecutor` | `NormalizedValue` after canonicalization |
| Metamorphic | Subject's answer to rewritten Q | Subject's answer to original Q | equivalence-expectation comparator |
| Insta snapshots | Current build's bytecode/plan | Last-committed `.snap` | text equality |
| Crash-boundary | Recovered state after crash at boundary B | "Some consistent prefix of committed txns" | consistency predicate |
| MVCC invariant | Live system | Mathematical invariant (INV-1..7) | e-process Ville threshold |
| Perf gate | Current build | Previous build (`.bench-history`) | ratio drop ≥ threshold |
| Conformance ratchet | Current parity score | Persisted high-water mark | lower-bound monotonicity |

This table is the entire skill in eight rows. Each pillar in this document instantiates one or more of these rows.
