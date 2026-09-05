# PHASES.md — 16-Phase Playbook

This is the operational source-of-truth for the gauntlet's 16-phase loop. For each phase you get: purpose, inputs, subagents, outputs, exit criteria, parallelism shape, MCP Agent Mail thread-ID pattern, required reservations, time-budget estimate, and common failures + remediation. The final section is the **Phase Coordination Matrix** — which phases run in parallel vs serial, which feed which, where the convergence iteration boundary sits.

Conventions:
- `<run-id>` = `YYYYMMDD-HHMMSS-<short-git-sha>` of the gauntlet workspace
- `<workspace>` = `<basename>__gauntlet_workspace/` sibling of the target port
- `<port>` = basename of target port (e.g. `frankensqlite`, `frankenredis`)
- `<reference>` = identifier of pinned reference (e.g. `csqlite`, `redis`, `pytorch`, `numpy`)
- Thread-ID pattern: `gauntlet-<run-id>-phase<N>-<bucket>` where `<bucket>` is phase-specific
- Reservation URIs: `tool://`, `resource://`, `workspace://<relative-path>`
- Time budgets: assume Squad-tier (4–6 workers); scale ±50% for Solo / Swarm

---

## Phase 0: TOOLCHAIN BOOTSTRAP + WORKSPACE INIT

### Purpose
Provision the host toolchain, initialize a `git init`-ed workspace beside the target port, auto-detect project class, inventory required helper skills, and run the oracle-preflight-doctor. Emits a single green/yellow/red **precondition verdict** — every downstream phase depends on green.

### Inputs
- Target port absolute path (`/data/projects/<port>` or cloned worktree)
- Workspace directory path (default `<basename>__gauntlet_workspace/` as sibling)
- Reference version to pin (e.g. `sqlite-3.52.0`, `redis-7.2.5`)
- Final-artifact tier (internal-only / public-release / certification-bundle)

### Subagents involved
- `subagents/workspace-bootstrapper.md` (solo)

### Outputs
- `<workspace>/phase0_workspace_init.md` — toolchain inventory + workspace skeleton manifest + green/yellow/red verdict
- `<workspace>/phase0_project_class.json` — `{ detected_class: "SQL-class|RESP-class|Numerical-Python-class|ML-System-class|HTTP-Protocol-class|UNKNOWN", confidence: 0..1, matching_reference, sibling_project_example, scores: {...} }`
- `<workspace>/phase0_skill_inventory.json` — helper-skill availability map + `jsm` state
- `<workspace>/phase0_oracle_preflight.json` — preflight doctor report (deterministic, reproducible)
- `<workspace>/AGENTS.md` — mandate paragraph seeded
- `<workspace>/docs/contracts/<reference>_version_contract.toml` — version-contract skeleton
- `<workspace>/docs/progress/{perf-negative-results.md, conformance-negative-results.md, surface-deferrals.md}` — three ledger seeds
- `<workspace>/.gitignore` + initial commit

### Exit criteria
- `phase0_oracle_preflight.json.aggregate_outcome == "green"` (yellow allowed only with explicit human waiver in `phase0_workspace_init.md`; red = halt)
- `phase0_project_class.json.confidence >= 0.8`
- `git log --oneline | head -1` shows the initial commit
- Every required toolchain entry has status `installed` in `phase0_workspace_init.md`

### Parallelism shape
**Solo.** Single agent. Sequential script invocations. No fan-out possible — every later phase requires Phase 0's verdict.

### MCP Agent Mail thread-ID pattern
`gauntlet-<run-id>-phase0-bootstrap`

### Required Reservations
- `workspace://<workspace>` exclusive write
- `tool://install-toolchain` exclusive (idempotent but single-writer)
- `tool://oracle-preflight-doctor` exclusive

### Time budget estimate
- 5–30 minutes (toolchain install dominates on cold host)
- 1–5 minutes on warm host

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Oracle preflight `red` because reference binary missing | Install reference (e.g. `apt install sqlite3==3.52.0` or build from pinned tag); re-run `scripts/oracle-preflight-doctor.sh` |
| Project class auto-detect `confidence < 0.8` | Inspect `phase0_project_class.json.scores`; set the confirmed class in `phase0_intake.json.project_class_confirmed`; document override rationale in `phase0_workspace_init.md` |
| `jsm` unauthenticated, helper skills missing | Run `jsm login` headless OAuth; fall back to inline-pipelined helper skills (every helper has an inline fallback in this skill) |

---

## Phase 1: RECON

### Purpose
Per-crate codebase archaeology of both subject and reference. Enumerate public surface, perf surface, conformance surface. Build reference-mapping (where in `<port>` is reference symbol X implemented?). Synthesize into one unified recon document.

### Inputs
- `<workspace>/phase0_*` outputs
- Target port crate list (`ls <target>/crates/`)
- Pinned reference source tree
- `/codebase-archaeology`, `/codebase-report` helper skills

### Subagents involved
- `subagents/surface-archaeologist.md` (one instance per crate, parallel)
- `subagents/synthesizer.md` (one collator, after all archaeologists return)

### Outputs
- `<workspace>/phase1_recon_<crate>.md` — one per crate; sections:
  - Public surface table (`pub fn`, `pub struct`, `pub trait`, `pub macro`, `pub use`)
  - Perf surface (hot paths identified by `grep -E '#\[inline\]|hot_path|fast_path'`, dispatch sites, allocation sites)
  - Conformance surface (every place behavior could diverge from reference)
  - Reference-mapping table (reference symbol → port location, present|partial|missing)
- `<workspace>/phase1_unified_recon.md` — synthesized cross-crate view; calls out duplicated surface, orphaned exports, surface gaps

### Exit criteria
- One `phase1_recon_<crate>.md` per crate, all containing all four sections
- `phase1_unified_recon.md` exists and references every per-crate file
- Reference-mapping coverage `>= 90%` (every reference public symbol appears in at least one per-crate file with a status)

### Parallelism shape
**Squad.** One subagent per crate. Synthesizer waits for all returns. Partition by crate boundary; each archaeologist owns its `phase1_recon_<crate>.md` file exclusively.

### MCP Agent Mail thread-ID pattern
- Per-crate: `gauntlet-<run-id>-phase1-recon-<crate>`
- Synthesizer: `gauntlet-<run-id>-phase1-synthesis`

### Required Reservations
- `workspace://phase1_recon_<crate>.md` per archaeologist
- `workspace://phase1_unified_recon.md` for synthesizer
- Read-only on `<target>/crates/<crate>/` per archaeologist (concurrent reads OK)

### Time budget estimate
- 30–90 minutes per crate (parallel)
- Wall time = max single-crate time + 15 min synthesis

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Reference symbol enumeration incomplete (some `pub` items missed) | Run `cargo doc --document-private-items` on reference; cross-check; rerun archaeologist with explicit `pub`-grep |
| Reference-mapping coverage < 90% | Re-run synthesizer with stricter symbol-matching; identify systematic gaps (e.g. macro-generated symbols) and document |
| Per-crate file too large to be useful | Split into `phase1_recon_<crate>_part_{N}.md` and update synthesizer index |

---

## Phase 2: REFERENCE PINNING + SURFACE CONTRACT

### Purpose
Lock the reference version + write the surface contract. Every artifact downstream must embed this contract hash. Decisions made here (what's in scope, what's excluded, with rationale) are immutable for the run.

### Inputs
- `phase0_project_class.json` (class drives matrix axes)
- `phase1_unified_recon.md` (every reference symbol must end up classified)
- Reference version (pinned in Phase 0)

### Subagents involved
- `subagents/scope-decider.md` (solo — must be coherent, no fan-out)

### Outputs
- `<workspace>/docs/contracts/<reference>_version_contract.toml` — pinned version + commit SHA + tarball SHA-256 + ABI fingerprint
- `<workspace>/docs/contracts/supported_surface_matrix.toml` — every reference symbol with `present|partial|missing|n/a|excluded` + rationale
- `<workspace>/docs/contracts/canonical_parity_contract.md` — what "parity" means for this port (signature semantics: byte-identical / canonical-equivalent / logical-equivalent per category)
- `<workspace>/docs/contracts/parity_score_contract.toml` — per-category weights (must sum to 1.0; enforced by loader)

### Exit criteria
- Every reference symbol from `phase1_unified_recon.md` has a row in `supported_surface_matrix.toml`
- `parity_score_contract.toml` weights sum to `1.0` per category (script-enforced)
- Every `excluded` row has a non-empty `rationale` AND `retry_condition` field
- Version-contract embeds upstream tag + commit SHA + tarball SHA-256

### Parallelism shape
**Solo.** Scope decisions must be coherent. One agent. Two-phase commit: draft → 30-minute review window → final commit.

### MCP Agent Mail thread-ID pattern
`gauntlet-<run-id>-phase2-contract`

### Required Reservations
- `workspace://docs/contracts/` exclusive write (one writer)

### Time budget estimate
- 2–4 hours (mostly deliberation; the writing is mechanical)

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Weight sum != 1.0 per category | Loader rejects; re-normalize; document the rebalance in `parity_score_contract.toml` changelog |
| `excluded` row missing retry condition | Loader rejects; either supply retry condition or reclassify as `n/a` (out-of-scope by design, not deferred) |
| Reference symbol added to `phase1_recon` after contract finalized | Re-open Phase 2; bump contract version; re-normalize weights; audit existing scorecards for retroactive score change |

---

## Phase 3: ORACLE WIRING

### Purpose
Build the in-process or stable-subprocess bridge from subject to pinned reference. Wire `EngineIdentity` so subject can never compare against itself. Stand up the `oracle_preflight_doctor.rs` per project class.

### Inputs
- `phase0_project_class.json`
- `docs/contracts/<reference>_version_contract.toml`
- 30-line `scenario()` template from `references/THREE-PILLARS.md`
- `NormalizedValue` rendering rules per class (see `references/taxonomy/PROJECT-CLASSES.md`)

### Subagents involved
- `subagents/oracle-wirer.md` (one per project class — Squad)
- `subagents/oracle-preflight-doctor-builder.md` (one per class, runs in parallel with oracle-wirer)

### Outputs
- `crates/<port>-harness/src/oracle.rs` — `scenario()` template + `NormalizedValue` rendering
- `crates/<port>-harness/src/differential_v2.rs` — `ExecutionEnvelope` + `artifact_id()` SHA-256 of canonical JSON excluding `run_id`
- `crates/<port>-harness/src/oracle_preflight_doctor.rs` — per-class adaptations
- `crates/<port>-harness/src/engine_identity.rs` — discriminator + asserted-distinct check at comparator entry
- `<workspace>/phase3_oracle_wiring.md` — what was wired, how it's invoked, sample diagnostic output

### Exit criteria
- `cargo test -p <port>-harness oracle::tests` green (round-trip Subject==Subject, Subject!=Oracle, both-error agreement)
- `cargo run --bin oracle-preflight-doctor` exits 0 with `aggregate_outcome == "green"` and `certifying == true`
- `EngineIdentity::Subject == "<port>"` and `EngineIdentity::Oracle == "<reference>-oracle"` verified at every comparator boundary

### Parallelism shape
**Squad.** Wirer + preflight-doctor-builder per class, run in parallel. Within a class they share file ownership and coordinate via Agent Mail.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase3-oracle-<class>`
- `gauntlet-<run-id>-phase3-preflight-<class>`

### Required Reservations
- `workspace://crates/<port>-harness/src/oracle.rs`
- `workspace://crates/<port>-harness/src/differential_v2.rs`
- `workspace://crates/<port>-harness/src/oracle_preflight_doctor.rs`
- `tool://reference-binary` (preflight doctor needs exclusive access during identity check)

### Time budget estimate
- 4–12 hours per class (oracle wiring is the most subtle code in the harness)

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Preflight doctor emits `red` because reference identity not visible | Verify `EngineIdentity::Oracle` string matches `reference_identity` from contract; check process-isolation if subprocess bridge |
| Subject self-compared (apparent 100% pass rate) | EngineIdentity asserted-distinct check missing at comparator entry; add to `oracle.rs::compare()` |
| Differential V2 `artifact_id` non-deterministic across runs | `run_id` leaked into canonical JSON; ensure `CanonicalEnvelope` strips `run_id` before serializing |
| Both-error treated as failure | Comparator must treat `(Err(_), Err(_))` as agreement regardless of message text |

---

## Phase 4: GOLDEN CAPTURE

### Purpose
Capture per-tier golden artifacts (Tier 1 byte / Tier 2 canonical / Tier 3 logical) across every fixture source. Build `manifest.v1.json` with `checksums.sha256` integrity guardrails. Snapshot initial `feature_coverage_dashboard`.

### Inputs
- `phase3_oracle_wiring.md` (oracle must be green)
- Fixture sources (test fixtures, public corpora, generated property-test inputs)
- Three-tier equivalence rules from `references/THREE-PILLARS.md`

### Subagents involved
- `subagents/golden-capturer.md` — parameterized per tier × per fixture-source (Squad to Swarm depending on fixture-source count)

### Outputs
- `<workspace>/tests/artifacts/golden/tier1/` — raw SHA-256 byte-equal artifacts
- `<workspace>/tests/artifacts/golden/tier2/` — canonical-normalized artifacts (post-VACUUM, post-`use_deterministic_algorithms`, etc.)
- `<workspace>/tests/artifacts/golden/tier3/` — logical-equivalent dumps (row count + columns + values via `==`)
- `<workspace>/tests/artifacts/golden/manifest.v1.json` — every artifact's tier, source, path, hash, schema_version
- `<workspace>/tests/artifacts/golden/checksums.sha256` — file integrity guardrail
- `<workspace>/phase4_golden_capture.md` — capture log + initial `feature_coverage_dashboard` snapshot

### Exit criteria
- `sha256sum -c checksums.sha256` exits 0
- `manifest.v1.json` is well-formed JSON with `schema_version = "1.0.0"`
- Every fixture source has at least one artifact at the highest applicable tier
- `feature_coverage_dashboard` initial snapshot exists at `<workspace>/reports/coverage/dashboard_round_0.json`

### Parallelism shape
**Squad to Swarm.** One subagent per (tier × fixture-source) pair. Capturers write into disjoint subdirectories of `tests/artifacts/golden/`.

### MCP Agent Mail thread-ID pattern
`gauntlet-<run-id>-phase4-golden-tier<N>-<fixture-source>`

### Required Reservations
- `workspace://tests/artifacts/golden/tier<N>/<fixture-source>/` per capturer
- `workspace://tests/artifacts/golden/manifest.v1.json` — append-only via coordinated commit

### Time budget estimate
- 1–4 hours per fixture source (parallel)
- Wall time = max single-source time + 30 min manifest collation

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Tier 1 byte-equality fails on apparently-identical artifacts | Inspect for trailing whitespace, line-ending, timestamp leakage; either canonicalize and demote to Tier 2, or fix the source of non-determinism |
| `manifest.v1.json` schema_version mismatch across capturers | Pin schema version in capturer prompt; rerun affected capturers |
| Fixture source produces non-deterministic output | Document in `phase4_golden_capture.md`; either inject deterministic seed or demote to Tier 3 |

---

## Phase 5: PERFORMANCE HARNESS

### Purpose
Stand up the full perf machinery: `comprehensive-bench` skeleton (with the six timing constants verbatim), focused per-workload benches, `HotPathProfileSnapshot` counters, `.bench-history/` initialization, profile-first proof-pack template + directory, `perf_loop.rs` validator, robust regression detector (median + MAD).

### Inputs
- `phase0_project_class.json` (drives `HotPathProfileSnapshot` row from `references/taxonomy/PROJECT-CLASSES.md` § hot-path counters)
- `docs/contracts/parity_score_contract.toml` (drives category weights)
- `oracle.rs` (perf must be measured against same comparator)

### Subagents involved
- `subagents/bench-author.md` — one per workload family (Squad to Swarm)
- `subagents/hot-path-counter-instrumenter.md` — one per crate that owns a hot path (Squad)

### Outputs
- `crates/<port>-e2e/src/bin/comprehensive_bench.rs` — six timing constants verbatim (`WARMUP_ITERS=2, MIN_ITERS=3, MAX_ITERS=10, TARGET_DURATION=5s`); `measure()` + `measure_with_teardown()` with teardown OUTSIDE timed window
- `crates/<port>-e2e/src/bin/<focused-bench>.rs` — one per workload family (DML / read / aggregate / mixed-OLTP / concurrent-writers)
- `crates/<port>-core/src/hot_path_profile_snapshot.rs` — counters per the project-class row from `references/taxonomy/PROJECT-CLASSES.md`
- `<workspace>/.bench-history/<bench>.latest.json` — initial committed baseline (placeholder until Phase 9)
- `<workspace>/artifacts/proof_pack_template/` — 19-field card template + directory skeleton
- `crates/<port>-harness/src/perf_loop.rs` — validator (asserts 19 fields populated, baseline_profile exists)
- `crates/<port>-harness/src/performance_regression_detector.rs` — median + MAD; warning 1.10x / critical 1.25x latency; warning −10% / critical −20% throughput
- `<workspace>/phase5_perf_harness.md` — index of what's wired

### Exit criteria
- `cargo bench --bench <focused-bench> -- --quick` exits 0 for every focused bench
- `cargo run --bin comprehensive_bench -- --quick` exits 0; emits JSON v3 with `schema_version = "fsqlite-e2e.comprehensive-bench-report.v3"` (or project equivalent)
- `concurrent_mode_default_guard.txt` (or class-equivalent: `RESP_VERSION=3` for Redis, `CUDA_DEVICE_COUNT=N` for Torch, etc.) dropped into every artifact lane
- `cargo build --profile=release-perf` succeeds with `RUSTFLAGS="-C force-frame-pointers=yes"`

### Parallelism shape
**Squad to Swarm.** One subagent per workload family. Counter instrumenter parallel per crate. Coordinate on shared files (`comprehensive_bench.rs`) via Agent Mail reservation.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase5-bench-<workload-family>`
- `gauntlet-<run-id>-phase5-counters-<crate>`

### Required Reservations
- `workspace://crates/<port>-e2e/src/bin/comprehensive_bench.rs` (single writer; bench-authors take turns)
- `workspace://crates/<port>-e2e/src/bin/<focused-bench>.rs` per author
- `tool://comprehensive-bench` (exclusive — only one bench process at a time to avoid host noise)

### Time budget estimate
- 1–3 days for full harness stand-up
- Per-workload-family bench: 4–8 hours

### Common failures and remediation
| Failure | Remediation |
|---|---|
| `measure_with_teardown` teardown inside timed window | Code review — `start.elapsed()` MUST be captured BEFORE `teardown()` runs; reference verbatim from `references/THREE-PILLARS.md` |
| Bench cv_pct > 5% across runs | Host noise; pin to dedicated cores via `taskset`; disable turbo; use `release-perf` profile not `release` |
| Hot-path counters not visible in profile | Counter is sub-0.1% (micro-lever); either elevate via wider workload shape (e.g. MT8) or remove from counter set |
| `.bench-history/<bench>.latest.json` not committed | Baseline is a FILE not a memory; CI must enforce its presence; rerun `scripts/run-bench-matrix.sh` and `git add -f .bench-history/` |

---

## Phase 6: CONFORMANCE HARNESS

### Purpose
Stand up every conformance lane: per-behavior-class oracle E2E, per-`TransformFamily` metamorphic, per-fault-category fault injection, per-protocol-boundary crash injection, per-target differential fuzz, per-invariant e-process. This phase has the highest fan-out.

### Inputs
- `oracle.rs` + `differential_v2.rs` from Phase 3
- `references/THREE-PILLARS.md § Conformance pillar`
- `references/taxonomy/PROJECT-CLASSES.md § per-class crash boundaries`
- `references/taxonomy/INVARIANT-CATALOG.md` (proof-obligation taxonomy)

### Subagents involved
- `subagents/oracle-test-author.md` — one per behavior class (NULL semantics, three-valued logic, GROUP BY edges, JOIN semantics, trigger semantics, RETURNING, generated columns, window functions, …)
- `subagents/metamorphic-author.md` — one per `TransformFamily` (Predicate / Projection / Structural / Literal)
- `subagents/mismatch-minimizer-builder.md` — solo; delta-debugging binary partition + project-specific schema-preservation rule
- `subagents/fault-injector-author.md` — one per `FaultKind` (TornWrite / PartialWrite / PowerCut / IoError / ReadFailure / WriteFailure / Latency / DiskFull)
- `subagents/crash-boundary-wirer.md` — one per `CrashBoundary` (8 for SQL, 6+ for RESP, 5 for Torch, 5 for HTTP)
- `subagents/fuzz-author.md` — one per differential fuzz target
- `subagents/eprocess-modeler.md` — one per `MvccInvariant` (or class-equivalent)

### Outputs
Per subagent, a paired implementation + test file:
- `crates/<port>-e2e/tests/<behavior-class>_oracle_e2e.rs`
- `crates/<port>-harness/src/metamorphic.rs` — `TransformFamily`, `EquivalenceExpectation`, `MismatchClassification`
- `crates/<port>-harness/src/mismatch_minimizer.rs` — `Subsystem`, `MismatchSignature`, binary-partition algorithm
- `crates/<port>-harness/src/fault_vfs.rs` — `FaultKind`, `FaultSpec`, `FaultInjectingVfs`, F-1..F-8 checklist
- `crates/<port>-{wal,storage,replication,…}/src/fault_hooks.rs` — `CrashBoundary` enum + `arm_crash_boundary()`
- `crates/<port>-fuzz/fuzz_targets/<target>.rs` — differential fuzz harness
- `crates/<port>-harness/src/eprocess.rs` — 8 monitored invariants (or class-equivalent); hardware-enforced `p₀=1e-9, λ=0.999, α=1e-6`; software-enforced `p₀=1e-6, λ=0.9, α=0.001`; arithmetic-mean global e-value
- `crates/<port>-harness/src/failure_bundle.rs` — `FailureType`, `FailureBundle` schema with `first_divergence_jsonptr`
- `<workspace>/phase6_conformance_harness.md` — index of every wired lane

### Exit criteria
- Every behavior class has at least one `*_oracle_e2e.rs` test green
- `cargo fuzz list` shows every planned target
- Every `CrashBoundary` variant has a paired arming test
- E-process invariant catalog `cargo test -p <port>-harness eprocess::tests` green
- `MismatchClassification` distinguishes `TrueDivergence` from the 5 known classes; CI fails ONLY on `TrueDivergence`

### Parallelism shape
**Swarm.** Highest fan-out phase. Sub-buckets per behavior class × per `TransformFamily` × per `FaultKind` × per `CrashBoundary` × per fuzz target × per invariant. Each lane owns its file; metamorphic, minimizer, eprocess share `<port>-harness/src/` via Agent Mail reservation.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase6-oracle-<behavior-class>`
- `gauntlet-<run-id>-phase6-metamorphic-<transform-family>`
- `gauntlet-<run-id>-phase6-fault-<fault-kind>`
- `gauntlet-<run-id>-phase6-crash-<boundary>`
- `gauntlet-<run-id>-phase6-fuzz-<target>`
- `gauntlet-<run-id>-phase6-eprocess-<invariant>`

### Required Reservations
- Per lane: `workspace://crates/<port>-e2e/tests/<behavior-class>_oracle_e2e.rs`
- Shared (coordinated): `workspace://crates/<port>-harness/src/metamorphic.rs`, `mismatch_minimizer.rs`, `eprocess.rs`, `failure_bundle.rs`
- `tool://fuzz-corpus` (exclusive — fuzz corpus is large; one writer at a time)

### Time budget estimate
- 3–7 days for full harness (highest fan-out, longest aggregate wall time)
- Per-lane subagent: 2–6 hours

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Metamorphic relation too weak (`SetEquivalence` where `ExactRowMatch` is provably sound) | `/testing-metamorphic` rejects; tighten to strongest sound class; add soundness-proof sketch comment |
| Fault VFS non-deterministic | Pin `DEFAULT_FAULT_SEED`; ensure `FaultSpec.match_count` and `trigger_count` are deterministic |
| Crash boundary recovery non-deterministic | Recovery code reading uninitialized state; add `assert!(state.is_initialized())` at recovery entry |
| E-process global e-value > 1/α but no invariant violated | Calibration too tight; per-invariant `p₀` or `λ` needs adjustment; check `references/taxonomy/INVARIANT-CATALOG.md § calibration` |

---

## Phase 7: SURFACE PARITY INVENTORY

### Purpose
Build the `FeatureUniverse`, `InvariantCatalog`, `feature_coverage_dashboard`, `validation_manifest`, and `verification_contract_enforcement` modules. This phase enforces the weight-normalization, iteration-order, and `truncate_score` invariants that make the parity scorecard reproducible.

### Inputs
- `docs/contracts/supported_surface_matrix.toml`
- `docs/contracts/parity_score_contract.toml`
- `phase6_conformance_harness.md` (every behavior class with at least one `*_oracle_e2e.rs` test contributes a `Feature`)

### Subagents involved
- `subagents/feature-universe-builder.md` (solo)
- `subagents/invariant-catalog-builder.md` (solo)
- `subagents/coverage-dashboard-builder.md` (solo, runs after the above two)

### Outputs
- `crates/<port>-harness/src/parity_taxonomy.rs` — `Feature`, `FeatureId`, `FeatureUniverse::features()` sorted iteration
- `crates/<port>-harness/src/invariant_catalog.rs` — `ParityInvariant`, `ProofObligation`, `ArtifactRef`, `validate()`, `release_traceability()`, `stats()`
- `crates/<port>-harness/src/feature_coverage_dashboard.rs` — per-family verdict (`none | partial | full`); release-gate
- `crates/<port>-harness/src/validation_manifest.rs` — aggregated proof index
- `crates/<port>-harness/src/verification_contract_enforcement.rs` — `pass | fail-missing-evidence | fail-invalid-references | fail-mixed` × `allowed | blocked-by-base-gate | blocked-by-contract | blocked-by-both` matrix
- `<workspace>/phase7_surface_parity.md` — coverage table + initial verdict

### Exit criteria
- `cargo test -p <port>-harness parity_taxonomy::tests` green; loader rejects weight sums != 1.0 per category
- `FeatureUniverse::features()` returns deterministically sorted by `FeatureId`
- `truncate_score()` produces byte-identical output on x86 / ARM / WASM
- `invariant_catalog::validate()` returns empty `Vec<Violation>` (every invariant has at least one `ProofObligation`)
- `feature_coverage_dashboard.rs` renders a per-family verdict against the current matrix

### Parallelism shape
**Solo serial.** Three subagents, run in order: feature-universe-builder → invariant-catalog-builder → coverage-dashboard-builder. Each produces output the next consumes.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase7-feature-universe`
- `gauntlet-<run-id>-phase7-invariant-catalog`
- `gauntlet-<run-id>-phase7-coverage-dashboard`

### Required Reservations
- Sequential exclusive on `workspace://crates/<port>-harness/src/parity_taxonomy.rs`, `invariant_catalog.rs`, `feature_coverage_dashboard.rs`

### Time budget estimate
- 6–12 hours total (serial)

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Weight sum != 1.0 per category | Loader rejects at startup; renormalize in `parity_score_contract.toml`; rerun |
| Iteration non-deterministic (HashMap ordering) | Use `BTreeMap` or sort-on-iteration; verify with cross-platform CI |
| `truncate_score` differs across platforms | Truncation must use integer arithmetic, not f64-rounded; see `references/methodology/CONFORMAL-RATCHET.md § truncate_score` |
| Invariant catalog has invariant with zero `ProofObligation` | Either add a proof obligation, or mark invariant as `Excluded` with rationale |

---

## Phase 8: NEGATIVE-LEDGER + AGENTS.MD MANDATE

### Purpose
Seed the three durable negative-evidence ledgers with the verbatim FrankenSQLite preamble + the AGENTS.md mandate paragraph + the cass-mining 60-day grep paragraph + the ledger-grep-before-perf-work mandate. This phase is short but load-bearing: future perf/conformance work is gated on these ledgers existing and being grep-able.

### Inputs
- `assets/agents-md-mandate-paragraph.md`
- `assets/negative-ledger-seed.md`
- `references/methodology/RETRY-CONDITION-VOCABULARY.md`

### Subagents involved
- `subagents/ledger-seeder.md` (solo, short)

### Outputs
- `<workspace>/docs/progress/perf-negative-results.md` — preamble + retry-condition vocabulary + first example entry
- `<workspace>/docs/progress/conformance-negative-results.md` — same structure for conformance gaps
- `<workspace>/docs/progress/surface-deferrals.md` — same structure for surface gaps
- `<workspace>/AGENTS.md` — append: mandate paragraph + cass-mining 60-day paragraph + ledger-grep-before-perf-work paragraph
- `<workspace>/phase8_ledgers_seeded.md` — confirmation, with grep-test verification

### Exit criteria
- Three ledger files exist with the verbatim preamble (`This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass...`)
- AGENTS.md contains the mandate paragraph verbatim (text from `assets/agents-md-mandate-paragraph.md`)
- `scripts/mine-ledger.sh <workspace>` exits 0 and returns the first example entry
- `scripts/mine-cass-cross-machine.sh` is invocable (smoke-test against last 7 days returns valid JSON)

### Parallelism shape
**Solo.** Single short agent. No fan-out.

### MCP Agent Mail thread-ID pattern
`gauntlet-<run-id>-phase8-ledgers`

### Required Reservations
- `workspace://docs/progress/` exclusive write
- `workspace://AGENTS.md` exclusive append

### Time budget estimate
- 30–60 minutes

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Preamble text drifts from FrankenSQLite verbatim | Re-source from `assets/negative-ledger-seed.md`; the preamble is part of the contract (downstream agents grep for specific phrases) |
| `cass` unavailable on this host | Document blocker in `phase8_ledgers_seeded.md`; do NOT silently skip; install cass via `jsm install cass` or fall back to inline-pipelined `rg` over `~/.claude/projects/` |
| AGENTS.md already has a competing mandate paragraph | Append, don't replace; downstream agents read full file |

---

## Phase 9: BASELINE RUN

### Purpose
First full sweep across all three pillars. Every divergence becomes a `FailureBundle` with `first_divergence_jsonptr`. comprehensive-bench full mode (93+ scenarios). Focused per-workload benches with flamegraphs / samply / dhat / strace. Always-on integrity guardrails.

### Inputs
- All prior phases green
- `oracle_preflight_doctor` green
- `phase7_surface_parity.md` (initial coverage)

### Subagents involved
- `subagents/baseline-runner-perf.md` (one)
- `subagents/baseline-runner-conformance.md` (one)
- `subagents/baseline-runner-surface.md` (one)

### Outputs
- `<workspace>/round_0/perf/comprehensive_bench.json` — JSON v3, 93+ scenarios, schema_version embedded
- `<workspace>/round_0/perf/<focused-bench>.json` per workload family
- `<workspace>/round_0/perf/profiles/` — flamegraph.svg / samply.json / dhat.json / strace.log per focused bench
- `<workspace>/round_0/conformance/oracle_corpus.jsonl` — Differential V2 envelopes
- `<workspace>/round_0/conformance/metamorphic_corpus.jsonl`
- `<workspace>/round_0/conformance/failures/<failure-id>.bundle.json` — `FailureBundle` per divergence with `first_divergence_jsonptr` populated
- `<workspace>/round_0/surface/feature_coverage.json` — per-family dashboard
- `<workspace>/round_0/surface/parity_score.json` — Beta posterior + conformal-band + lower-bound + `truncate_score`'d
- `<workspace>/.bench-history/<bench>.latest.json` — committed (real baseline now)
- `<workspace>/phase9_baseline.md` — top-line summary

### Exit criteria
- All three baseline runners exited 0 (with non-empty findings allowed)
- `.bench-history/<bench>.latest.json` committed for every focused bench
- Every divergence has a `FailureBundle` with `first_divergence_jsonptr` set
- `comprehensive_bench.json` has `schema_version`, `detected_environment`, `summary`, `ci_regression_gate`, `sections[]` populated
- `concurrent_mode_default_guard.txt` (or class-equivalent) present in every artifact lane

### Parallelism shape
**Squad parallel by pillar.** Perf + conformance + surface baseline runners run concurrently. They write into disjoint subdirectories of `round_0/`.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase9-baseline-perf`
- `gauntlet-<run-id>-phase9-baseline-conformance`
- `gauntlet-<run-id>-phase9-baseline-surface`

### Required Reservations
- `workspace://round_0/perf/` per perf runner
- `workspace://round_0/conformance/` per conformance runner
- `workspace://round_0/surface/` per surface runner
- `tool://comprehensive-bench` exclusive (only one bench process at a time on the host)
- `resource://host-cores` exclusive during bench (no concurrent CPU-heavy work)

### Time budget estimate
- 4–12 hours wall time (depends on whether bench dispatched to `rch`)
- Perf alone: 2–6 hours for full 93-scenario matrix

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Bench cv_pct > 5% across iterations | Host noise; pin cores via `taskset`; disable hyper-threading; rerun |
| `FailureBundle.first_divergence_jsonptr` empty | Bug in mismatch-minimizer; rerun with `RUST_LOG=mismatch_minimizer=trace`; ensure minimizer reaches 1-minimal before bundling |
| Differential V2 `artifact_id` collision (two different runs produce same id) | `CanonicalEnvelope` stripping `run_id` correctly but two semantically identical runs is expected; check intentional reuse |
| `concurrent_mode_default_guard.txt` missing | Mode default silently flipped; `scripts/oracle-preflight-doctor.sh` should have caught this; rerun with `-vvv` |

---

## Phase 10: IDEA-WIZARD ROUND

### Purpose
Generate clever non-obvious gauntlet techniques specific to THIS port via verbatim `/idea-wizard` Phase-2 prompt. Then run advanced-methods mining and frontier-math compilation rounds. Every generated idea lands in `GAUNTLET_EXPERIMENT_DESIGNS.md` with hypothesis / minimal-repro / expected-signal / falsifiability / one-line-invocation.

### Inputs
- `phase9_baseline.md` (idea-wizard needs the current gap landscape)
- `references/exemplars/EXEMPLARS.md` (FrankenSQLite quote-bank seeds the idea-wizard)
- `/idea-wizard` helper skill plus the in-skill advanced-methods mining playbook

### Subagents involved
- `subagents/idea-wizard-orchestrator.md`
- `subagents/advanced-methods-miner.md`

### Outputs
- `<workspace>/round_<N>/ideas/idea_wizard_phase2.md` — 30 clever non-obvious gauntlet techniques for THIS port, then winnow to top 5, then 10 more
- `<workspace>/round_<N>/ideas/advanced_methods.md` — public systems-technique candidates applied to the port (only the ≥0.1% candidates kept)
- `<workspace>/round_<N>/ideas/frontier_math.md` — frontier-math compilation output
- `<workspace>/GAUNTLET_EXPERIMENT_DESIGNS.md` — append every kept idea with the experiment-design template fields

### Exit criteria
- `idea_wizard_phase2.md` has ≥30 ideas, then a top-5, then a +10 list (total ≥45)
- `advanced_methods.md` has at least 10 entries (the ≥0.1% candidates)
- Every kept idea has a corresponding row in `GAUNTLET_EXPERIMENT_DESIGNS.md` with all template fields populated

### Parallelism shape
**Pair.** Idea-wizard and advanced-methods mining run in parallel; their outputs merge into `GAUNTLET_EXPERIMENT_DESIGNS.md` via append-only ledger.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase10-idea-wizard`
- `gauntlet-<run-id>-phase10-advanced-methods`

### Required Reservations
- `workspace://round_<N>/ideas/` per agent
- `workspace://GAUNTLET_EXPERIMENT_DESIGNS.md` append-only

### Time budget estimate
- 1–3 hours per round

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Idea-wizard produces ideas with no falsifiability | Reject the idea; idea must be falsifiable (specific expected-signal, specific gate threshold) or it goes into the negative-ledger as "not actionable" |
| Advanced-methods mining mostly produces ideas already in the codebase | Run with stricter "novel-to-port" filter; cross-check against `phase1_unified_recon.md` |
| Idea ledger grows without convergence | Apply "TRULY think even harder" + multi-model triangulation; force triage into CONFIRMED_GAP / NO_EVIDENCE / NEEDS_REFINEMENT / NEW_HYPOTHESIS_SPAWNED |

---

## Phase 11: ITERATE PHASES 5–10

### Purpose
The convergence loop. **MINIMUM 10 ROUNDS.** Each round adds new conformance slices, metamorphic transforms, fuzz targets, bench scenarios, FeatureUniverse entries, e-process invariants. The loop terminates only when convergence math is satisfied.

### Inputs
- All prior phases
- `<workspace>/round_<N-1>/` outputs
- `<workspace>/GAUNTLET_EXPERIMENT_DESIGNS.md` (open hypotheses drive new work)

### Subagents involved
- `subagents/iteration-coordinator.md` — convergence-tracker driver; gates the loop
- `subagents/synthesizer.md` — reads all per-bucket findings, writes the global picture
- Plus any subagent from Phases 5–10 that the coordinator dispatches

### Outputs
- `<workspace>/round_<N>/perf/...` (same shape as `round_0/perf/`)
- `<workspace>/round_<N>/conformance/...`
- `<workspace>/round_<N>/surface/...`
- `<workspace>/round_<N>/ideas/...`
- `<workspace>/round_<N>/synthesis.md` — round-level cross-pillar synthesis
- `<workspace>/reports/convergence_tracker.json` — generated round-over-round new-finding counts per ledger + open-hypothesis status
- Updates to all three ledgers; updates to `GAUNTLET_EXPERIMENT_DESIGNS.md`

### Exit criteria
- `scripts/convergence-tracker.sh` exits 0 (until then it exits non-zero; CI gate)
- `reports/convergence_tracker.json.round_count >= 10`
- `reports/convergence_tracker.json.clean_last_two == true` (where "clean" = `<3` new genuine findings for the last two rounds)
- `reports/convergence_tracker.json.open_hypothesis_count == 0` (every open hypothesis has been resolved, refuted, or respawned into a new tracked OPEN entry)

### Parallelism shape
**Swarm.** Coordinator dispatches per-bucket subagents in parallel each round. Synthesizer runs once per round, after all bucket workers return. Typical round dispatches 8–12 workers.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase11-round-<N>-coord`
- `gauntlet-<run-id>-phase11-round-<N>-<bucket>`
- `gauntlet-<run-id>-phase11-round-<N>-synthesis`

### Required Reservations
- `workspace://round_<N>/` per round
- `workspace://reports/convergence_tracker.json` exclusive write (coordinator only; generated by `scripts/convergence-tracker.sh`)
- Per-bucket reservations same as the originating phase

### Time budget estimate
- **Days per round.** Typical: 1–3 days per round.
- 10 rounds minimum → 10–30 days wall time
- Dispatch heavy benches to `rch` (see `references/orchestration/ORCHESTRATION.md § rch offload heuristic`)

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Round count plateaus at 8–9, never reaches 10 | The minimum is non-negotiable; either the agent is bored (push fresh idea-wizard rounds) or it's prematurely claiming convergence (rerun `scripts/convergence-tracker.sh <workspace>` and inspect `reports/convergence_tracker.json.open_hypothesis_count`) |
| New-finding count never drops below 3 | The harness keeps finding genuine bugs — this is desired; keep iterating; do NOT relax the gate |
| `NEW_HYPOTHESIS_SPAWNED` count grows unbounded | The agent is generating ideas faster than it resolves them; throttle Phase-10 idea-wizard; force triage |
| Round artifacts not under `round_<N>/` | Compaction-survival violated; agent dropped mid-round; coordinator must enforce per-round directory contract |

---

## Phase 12: REMEDIATION DESIGN

### Purpose
For every CONFIRMED_GAP from Phase 11, enumerate 2+ isomorphic rewrites. Score each on a fixed rubric (correctness margin / perf delta / diff blast radius / reviewability / maintainability / parity-preservation). Pick the best; record the alternatives in the negative-ledger.

### Inputs
- `<workspace>/round_<N>/synthesis.md` for the final round
- `<workspace>/reports/convergence_tracker.json` (converged)
- `references/remediation/REMEDIATION-PATTERNS.md` (10 winning patterns from FrankenSQLite)
- `references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md`

### Subagents involved
- `subagents/remediation-architect.md` — **one per pillar** (perf / conformance / surface)

### Outputs
- `<workspace>/remediation/<gap-id>/proposal.md` — 2+ isomorphic rewrites with rubric scores
- `<workspace>/remediation/<gap-id>/proof_of_isomorphism.md` — 5-line template from `references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md`
- `<workspace>/remediation/<gap-id>/expected_signal.md` — predicted bench delta / conformance delta / coverage delta
- `<workspace>/remediation/picked.md` — picked alternative per gap with rationale
- `<workspace>/remediation/rejected.md` — rejected alternatives → flows to negative-ledger
- Per-pillar specific gates:
  - Perf candidates: `Impact × Confidence / Effort ≥ 2.0` (otherwise rejected)
  - Conformance: conformal-lower-bound monotonicity (proposal must raise LOWER bound, not just point estimate, AND not lower any per-category bound)
  - Surface: `partial → full` feature-coverage check (proposal must not regress any feature from `Passing` to `Partial` or worse)

### Exit criteria
- Every CONFIRMED_GAP has at least 2 proposals
- Every proposal has a rubric score
- Every picked proposal passes the per-pillar specific gate
- Every rejected proposal has a retry-condition predicate

### Parallelism shape
**Squad.** Three architects (one per pillar) work in parallel. Within a pillar, per-gap design can also fan out.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase12-remediation-<pillar>-<gap-id>`

### Required Reservations
- `workspace://remediation/<gap-id>/` per architect

### Time budget estimate
- 1–3 days (per-gap depth, not breadth)

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Only 1 proposal per gap | Loop: force the architect to enumerate 2+; isomorphic-rewrite is a non-negotiable discipline |
| Perf proposal `Impact × Confidence / Effort < 2.0` | Reject; either find a better one or send to negative-ledger with retry-condition |
| Conformance proposal lowers a per-category bound | Reject; the conformal-ratchet is strictly monotone per category |
| Surface proposal regresses `Passing → Partial` | Reject; only `Partial → Full` or `Missing → Partial → Full` are allowed transitions |

---

## Phase 13: BEADS HANDOFF

### Purpose
Convert picked remediation proposals into a polished bead graph via `/beads-workflow`. 4–5 polish rounds. Validate: `br dep cycles --json | jq '(.cycles // []) | length == 0'` passes; `bv --robot-insights | jq '(.Cycles // []) | length == 0'` passes; every remediation bead has test-bead + bench-bead + doc-bead dependencies.

### Inputs
- `<workspace>/remediation/picked.md`
- Per-gap proposals
- `references/orchestration/BEADS-HANDOFF.md`
- `/beads-workflow` helper skill

### Subagents involved
- `subagents/bead-author.md` — plan → beads
- `subagents/bead-polisher.md` — 4–5 polish rounds; do not oversimplify

### Outputs
- `<target>/.beads/issues.jsonl` — new remediation beads with proper dependencies
- `<workspace>/phase13_bead_handoff.md` — bead-graph summary, cycle-validation output, dependency-coverage table

### Exit criteria
- `br dep cycles --json | jq '(.cycles // []) | length == 0'` passes
- `bv --robot-insights | jq '(.Cycles // []) | length == 0'` passes
- Every remediation bead has at least one test-bead dependency AND one bench-bead dependency AND one doc-bead dependency
- `bv --robot-stats` shows >0 beads in `ready` state (graph is ready for swarm execution)

### Parallelism shape
**Pair.** Bead-author writes first cut; bead-polisher iterates 4–5 rounds.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase13-bead-author`
- `gauntlet-<run-id>-phase13-bead-polisher`

### Required Reservations
- `tool://br` exclusive write (single-writer to `.beads/issues.jsonl`)

### Time budget estimate
- 4–8 hours

### Common failures and remediation
| Failure | Remediation |
|---|---|
| `br dep cycles` non-empty | Polish round: re-design dependency graph; the polisher's job is exactly this |
| Remediation bead missing test/bench/doc dep | Polish round adds them; never close a remediation bead without paired test+bench+doc completion |
| Beads oversimplified (e.g. one bead per pillar) | Polish round expands; granularity should match "one bead per file-level change" |

---

## Phase 14: FRESH-EYES REVIEW

### Purpose
Three calibrated fresh-eyes prompts (from `references/AGENT-PROMPTS.md § Phase 14`). Loop until two consecutive clean rounds. Then ubs + clippy + fmt + test + miri pass against harness internals. Fix everything regardless of source.

### Inputs
- Phases 12+13 complete
- `references/AGENT-PROMPTS.md § Phase 14` — three verbatim prompts (a, b, c)
- `/ubs`, `/multi-pass-bug-hunting` helper skills

### Subagents involved
- `subagents/fresh-eyes-reviewer-a.md` (first verbatim prompt)
- `subagents/fresh-eyes-reviewer-b.md` (second verbatim prompt — random-walk + AGENTS.md compliance)
- `subagents/fresh-eyes-reviewer-c.md` (third verbatim prompt — fellow-agent code review)

### Outputs
- `<workspace>/phase14_review_<reviewer>_round_<N>.md` per reviewer per round
- `<workspace>/phase14_fixes_round_<N>.md` — what was fixed each round
- `<workspace>/phase14_ubs_report.md` — final UBS pass report
- `<workspace>/phase14_clippy.log`, `phase14_clippy_pedantic.log`, `phase14_miri.log` — tool outputs

### Exit criteria
- Two consecutive review rounds produce zero NEW findings from all three reviewers
- `cargo check --all-targets` exits 0
- `cargo clippy --all-targets -- -D warnings` exits 0
- `cargo fmt --check` exits 0
- `cargo test --workspace` exits 0
- `cargo +nightly miri test -p <port>-harness` exits 0
- UBS scan returns zero unresolved issues

### Parallelism shape
**Squad per round.** Three reviewers in parallel. Fixers run serially within a round (fixes can interact). Loop is serial across rounds.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase14-round-<N>-reviewer-<a|b|c>`
- `gauntlet-<run-id>-phase14-round-<N>-fixer`

### Required Reservations
- `workspace://phase14_*` per agent

### Time budget estimate
- 1–2 days (1–3 review rounds typical; 4+ if findings are deep)

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Review never converges (each round produces new findings) | Either the codebase is genuinely deep, or reviewers are diverging in style; calibrate by re-reading the verbatim prompts; consider multi-model triangulation |
| Clippy pedantic explosion | Allow specific lints via `#[allow(clippy::...)]` with rationale comment; do NOT bulk-allow |
| Miri unsupported intrinsic | Gate the unsupported code with `#[cfg(not(miri))]`; document in `phase14_miri.log` |
| UBS finds issues in `<port>` not harness | Per the "fix all errors" rule: fix them; don't punt as "not mine" |

---

## Phase 15: SOAK / DEEP-VALIDATION

### Purpose
24h+ differential fuzz against previously-divergent APIs; multi-day Miri across harness internals; multi-thousand-iter loom + shuttle; multi-thousand-iter crash-boundary; multi-day BOCPD on parity-score stream (assert `Stable` regime); adversarial-search against every gate. Dispatch to `rch`. Late-breaking findings loop back to Phase 12.

### Inputs
- Phase 14 clean
- `references/methodology/SOAK-PROTOCOL.md`
- `rch` worker pool

### Subagents involved
- `subagents/soak-runner-fuzz.md` — 24h+ differential fuzz
- `subagents/soak-runner-miri.md` — multi-day Miri
- `subagents/soak-runner-loom.md` — multi-thousand-iter loom + shuttle
- `subagents/soak-runner-crash-boundary.md` — multi-thousand-iter deterministic fault VFS
- `subagents/soak-runner-bocpd.md` — multi-day BOCPD on parity-score stream
- `subagents/soak-runner-adversarial.md` — adversarial-search against every gate

### Outputs
- `<workspace>/soak/fuzz/{summary.json, corpus/, crashes/}`
- `<workspace>/soak/miri/{summary.json, ub-reports/}`
- `<workspace>/soak/loom/{summary.json, interleavings/}`
- `<workspace>/soak/crash-boundary/{summary.json, recovery-traces/}`
- `<workspace>/soak/bocpd/{regime-timeline.json, regime-summary.md}` — must show `Stable` regime throughout window
- `<workspace>/soak/adversarial/{counterexamples.json, gate-vulnerabilities.md}` — every counterexample becomes a regression test
- `<workspace>/phase15_soak.md` — summary
- If genuinely new gaps found: append to `GAUNTLET_EXPERIMENT_DESIGNS.md` and **loop back to Phase 12**

### Exit criteria
- Fuzz: 24h+ wall time, zero new `TrueDivergence` crashes, corpus growth saturated
- Miri: full harness internals pass; zero UB; zero memory leaks
- Loom + Shuttle: ≥10,000 interleavings per target, zero failures
- Crash-boundary: ≥1,000 iterations per boundary, all recoveries consistent
- BOCPD: regime classification `Stable` for the full window (no `ShiftDetected` in regression direction)
- Adversarial: every gate survives the adversarial-search; if it doesn't, the gate is updated and the counterexample becomes a regression test

### Parallelism shape
**Swarm dispatched to `rch`.** Six soak runners in parallel, each on its own `rch` worker. The orchestrator polls completion via Agent Mail.

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase15-soak-<runner>`

### Required Reservations
- `resource://rch-worker-pool` shared (six concurrent claims)
- `workspace://soak/<runner>/` per runner

### Time budget estimate
- **Days.** Fuzz ≥24h. Miri 2–4 days. BOCPD 3–7 days. Adversarial 1–3 days. Run in parallel; gating wall time = max single-runner time.

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Fuzz finds genuine bug after Phase 14 was clean | Loop back to Phase 12 with the new gap; this is the intended late-breaking-findings path |
| Miri reports UB in `unsafe` block | Loop back to Phase 12; never paper over; UB is a hard failure |
| BOCPD detects `ShiftDetected` regression mid-window | Investigate; either real regression (loop back to Phase 12) or noise (calibrate hazard rate H or extend window) |
| Adversarial finds gate vulnerability | Update the gate; counterexample becomes regression test; loop back through Phase 14 |

---

## Phase 16: FINAL ARTIFACTS

### Purpose
Produce the three load-bearing documents + polished bead graph + certification bundle.

### Inputs
- Every prior phase
- `assets/final-gauntlet-report-template.md`, `assets/parity-runbook-template.md`, `assets/release-certification-template.md`

### Subagents involved
- `subagents/final-report-author.md`
- `subagents/runbook-author.md`
- `subagents/certification-bundler.md`

### Outputs
- `<workspace>/FINAL_GAUNTLET_REPORT.md` — executive summary; full findings table with severity; per-pillar remediation plan; unresolved-but-deferred list with retry-condition predicates; convergence-evidence appendix; certification-bundle manifest
- `<workspace>/PARITY_RUNBOOK.md` — maintainer-facing; CI gates, insta snapshots, fuzz corpora, AGENTS.md mandate paragraph, negative-ledger format
- `<workspace>/RELEASE_CERTIFICATION_TEMPLATE.md` — strict-conformant-release.v1: `CERTIFICATION_MIN_VERIFICATION_PCT = 100.0`, `CERTIFICATION_REQUIRED_SUITE_PASS_RATE_PCT = 100.0`, `CERTIFICATION_MAX_HIGH_SEVERITY_COUNTEREXAMPLES = 0`, `CERTIFICATION_MAX_EVIDENCE_AGE_HOURS = 24`
- `<workspace>/certification_bundle/` — confidence-gate JSON, verification-contract JSON, release-certificate JSON, CI artifact manifest, benchmark summary, `scorecards.json`, critical-path report, ratchet state
- `<target>/.beads/issues.jsonl` — polished bead graph (already from Phase 13, re-validated here)

### Exit criteria
- Three documents exist and are non-empty
- `certification_bundle/` contains every required JSON file
- `scripts/bead-graph-validator.sh <target> --output-root <workspace>` exits 0
- `scripts/final-report-builder.sh` exits 0
- Top of `FINAL_GAUNTLET_REPORT.md` says either `CERTIFIED` (all gates pass) or names the specific gate that blocked certification

### Parallelism shape
**Squad.** Three authors run in parallel; certification-bundler runs last (depends on the three documents).

### MCP Agent Mail thread-ID pattern
- `gauntlet-<run-id>-phase16-final-report`
- `gauntlet-<run-id>-phase16-runbook`
- `gauntlet-<run-id>-phase16-certification`

### Required Reservations
- `workspace://FINAL_GAUNTLET_REPORT.md`
- `workspace://PARITY_RUNBOOK.md`
- `workspace://RELEASE_CERTIFICATION_TEMPLATE.md`
- `workspace://certification_bundle/`

### Time budget estimate
- 4–8 hours

### Common failures and remediation
| Failure | Remediation |
|---|---|
| Certification bundler missing artifact | Trace to which Phase should have produced it; rerun that Phase's missing output; do NOT fabricate |
| `FINAL_GAUNTLET_REPORT.md` says `CERTIFIED` but a gate is yellow | Bundler must be strict: any non-green gate flips top-line to `BLOCKED`; investigate why bundler missed it |
| Runbook is generic / not project-specific | Re-read maintainer-facing audience requirement; runbook must name the specific files/scripts/CI workflows |

---

## Phase Coordination Matrix

| Phase | Runs in parallel with | Feeds | Convergence boundary | Required-before |
|---|---|---|---|---|
| 0 | — | 1, 2, 3 | pre-loop | (none) |
| 1 | — | 2, 7 | pre-loop | 0 |
| 2 | — | 3, 4, 5, 6, 7 | pre-loop | 0, 1 |
| 3 | (Phase 4 if oracle ready) | 4, 6, 9 | pre-loop | 0, 2 |
| 4 | 3 (after oracle wired) | 6, 9 | pre-loop | 3 |
| 5 | 6, 7 | 9, 11 | **loop boundary START** | 3 |
| 6 | 5, 7 | 9, 11 | **loop boundary START** | 3, 4 |
| 7 | 5, 6 | 9, 11 | **loop boundary START** | 2, 6 |
| 8 | (any) | 11 | pre-loop (load-bearing for loop) | 2 |
| 9 | (perf/conformance/surface lanes in parallel) | 10, 11 | round_0 | 5, 6, 7, 8 |
| 10 | — | 11 (drives next round) | round_N inputs | 9 (round_0) or prior round |
| 11 | (dispatches Phases 5–10 per round) | 12, 15 | **loop boundary END** | 9, 10 |
| 12 | (per-pillar architects parallel) | 13 | post-loop | 11 converged |
| 13 | — | 14 | post-loop | 12 |
| 14 | (three reviewers parallel per round) | 15 | post-loop convergence | 13 |
| 15 | (seven soak runners parallel via rch) | 16 OR back to 12 | post-loop | 14 clean ×2 |
| 16 | (three authors parallel) | (done) | post-loop | 15 |

### Loop boundary
The convergence iteration boundary is **Phase 11**. Phase 11 dispatches Phases 5, 6, 7 (harness expansion), then Phases 9, 10 (re-baseline + idea generation) per round. The loop terminates only when `scripts/convergence-tracker.sh` exits 0 — which requires ≥10 rounds, ≥2 consecutive clean rounds (<3 new genuine findings each), and zero open hypotheses.

### Late-breaking-findings loop-back
**Phase 15 → Phase 12 is the only post-loop loopback.** If soak finds a genuine new gap, the architect drafts a remediation, beads land, fresh-eyes runs again, soak runs again. There is no "we already shipped, skip it" branch.

### `rch`-offload heuristic
Dispatch anything >5 minutes wall-time to `rch` per `references/orchestration/ORCHESTRATION.md`. In practice this is: every full `comprehensive-bench`, every multi-day soak runner, every multi-thousand-iter loom/shuttle/crash-boundary run, every multi-day BOCPD. Phases 5, 9, 11, 15 are the heaviest dispatchers.

### Compaction-survival contract
Every phase writes its inputs/outputs to disk under `<workspace>/`. The agent can be dropped mid-phase, rehydrated, and resume from disk state. Phase records, round artifacts, MEMORY.md/session files, and the generated `reports/convergence_tracker.json` are the durable state; the agent's conversation context is ephemeral.
