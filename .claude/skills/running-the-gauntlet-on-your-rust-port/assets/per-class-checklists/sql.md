# SQL-class Adoption Checklist

For ports in the SQL-class (frankensqlite, sqlmodel_rust, future SQLite-shaped reimplementations). Verify each item; tick as adopted; record exceptions in `<workspace>/SQL_CHECKLIST_DEVIATIONS.md` with justification.

## Phase 0 — Workspace
- [ ] `<workspace>/` initialized as its own git repo
- [ ] `docs/contracts/sqlite_version_contract.toml` pins the exact SQLite version (e.g., `3.52.0`)
- [ ] Reference SQLite source amalgamation downloaded + SHA-256 verified
- [ ] `rusqlite` + `libsqlite3-sys` dev-dep pinned to the contract version

## Phase 3 — Oracle wiring
- [ ] `crates/<port>-harness/src/oracle.rs` contains the 30-line `scenario()` template verbatim
- [ ] `NormalizedValue::{Null, Integer, Real, Text, Blob}` enum present
- [ ] Render-to-canonical-string comparator (NULL capitalized, floats `{:.15}`, blob as `X'<hex>'`)
- [ ] `EngineIdentity` constants: `SUBJECT_IDENTITY_LABEL = "<port>"`, `REFERENCE_IDENTITY_LABEL = "csqlite-oracle"`
- [ ] `oracle_preflight_doctor.rs` verifies sqlite3 binary path + version + identity strings + fixture corpus
- [ ] Both-error = agreement rule; one-error-one-OK = hard failure

## Phase 4 — Golden capture
- [ ] Real-world `.db` corpus under `sample_sqlite_db_files/` with `manifest.v1.json`
- [ ] `checksums.sha256` integrity guardrail
- [ ] Three-tier equivalence: Tier 1 byte (`VACUUM INTO` hashed), Tier 2 canonical (PRAGMA-normalized), Tier 3 logical (deterministic SQL dump)

## Phase 5 — Performance
- [ ] `comprehensive_bench.rs` with the 6 timing constants verbatim
- [ ] `measure()` + `measure_with_teardown()` (teardown OUTSIDE timed window)
- [ ] Six weighted scenario categories sum to 1.0: ReadSingle 0.35, ReadAggregate 0.15, WriteSingle 0.30, WriteBulk 0.10, ConcurrentWriters 0.05, MixedOltp 0.05
- [ ] `release-perf` profile in Cargo.toml (inherits release, `opt-level=3`, `lto="thin"`, `codegen-units=1`, `debug="line-tables-only"`, `strip=false`, `RUSTFLAGS="-C force-frame-pointers=yes"`)
- [ ] JSON v3 self-describing report with `DetectedEnvironment` top-level field
- [ ] `concurrent_mode_default_guard.txt` dropped in every artifact lane
- [ ] Focused narrow benches: `mt-mvcc-bench`, `mt-oltp-bench`, `perf-update-delete`, `swarm-multiprocess`
- [ ] `HotPathProfileSnapshot` with the §23.6 SQL row counters: prepared_lookup_time_ns, begin_setup_time_ns, execute_body_time_ns, commit_finalize_seq_time_ns, concurrent_commit_plan_*, prepared_direct_*, B-tree seek/insert/delete/page_splits, swizzle_*, arena_alloc_bytes, page_buffer_pool_{hits,misses}
- [ ] `.bench-history/comprehensive_bench.latest.json` + `.bench-history/mt-mvcc-bench.latest.json` committed to git
- [ ] Pass-over-pass gate thresholds: primary `-3%`, geomean `-5%`, per-category `-10%`, p90 `-15%`, throughput `-5%`

## Phase 6 — Conformance
- [ ] Oracle E2E tests per behavior class: NULL semantics, three-valued logic, GROUP BY/HAVING edges, recursive CTEs, JOIN types, trigger semantics, RETURNING, generated columns, window functions, PRAGMA introspection, LIKE/GLOB/ESCAPE, subquery semantics, numeric arithmetic edges, BLOB I/O, foreign keys, CHECK, conflict resolution, compound SELECT, DEFAULT, ATTACH/TEMP, ALTER TABLE rename propagation
- [ ] `DifferentialV2 ExecutionEnvelope` with `artifact_id = SHA-256` of canonical JSON excluding `run_id`
- [ ] 4 TransformFamily metamorphic transforms: Predicate, Projection, Structural, Literal
- [ ] `MismatchClassification` triage; CI fails only on `TrueDivergence`
- [ ] Mismatch minimizer with DDL-preservation guard; `MismatchSignature` dedup
- [ ] Insta golden snapshots for: planner output, VDBE bytecode, `core_sql_golden_blake3.json`-style per-stage hash manifest
- [ ] Fault VFS with 8+ FaultKinds; F-1..F-8 adoption checklist complete
- [ ] 8 named crash boundaries verbatim: BeforeWalHeaderWrite, BeforeWalFrameAppend, AfterWalFrameAppendBeforeFsync, AfterFsyncBeforePublish, BetweenPageTableRebuildSteps, AfterPublishBeforeCheckpoint, MidCheckpoint, AfterCheckpoint
- [ ] Proptest harnesses with checked-in `proptest-regressions/`
- [ ] Differential fuzz: `fuzz_sql_parser`, `fuzz_expr_parser`, `fuzz_lexer`, `fuzz_record_roundtrip`, `xor_merge_guard`
- [ ] **TCL test suite lifted as regression corpus** (via `scripts/run-tcl-tests.sh`)
- [ ] E-processes on INV-1..INV-7 + INV-SSI-FP (hardware/software calibrations per `assets/eprocess-calibration-template.toml`)
- [ ] Replay harness with BOCPD `Regime::{Stable, Improving, Regressing, ShiftDetected}` on parity-score stream

## Phase 7 — Surface
- [ ] `parity_taxonomy.rs` with `Feature { id: F-SQL-NNN, ... }`; sum-of-weights == 1.0 per category enforced by loader
- [ ] `supported_surface_matrix.toml` declares every SQLite feature `present | partial | missing | n/a | excluded`
- [ ] Every Excluded item has `exclusion_rationale` + retry-condition predicate (one of 8 forms)
- [ ] `invariant_catalog.rs` with `ProofObligation` per invariant
- [ ] `feature_coverage_dashboard.rs` per-family verdict

## Phase 8 — Negative ledger
- [ ] `docs/progress/perf-negative-results.md` seeded with verbatim FrankenSQLite preamble
- [ ] AGENTS.md mandate paragraph installed with SQL-class failure terms: `within noise, micro-lever trap, focused vs broad, MT8 attribution, ratio frontier, fused-design, DML mutation operator`

## Phase 15 — Soak
- [ ] 24h+ differential fuzz against every previously-divergent SQL feature
- [ ] Multi-day Miri across harness internals
- [ ] Multi-thousand-iter loom on every concurrency primitive (MVCC plane especially)
- [ ] Multi-thousand-iter crash-boundary runs (all 8 boundaries armed × all FaultKinds)
- [ ] Multi-day BOCPD on parity stream → terminal `Stable`

## Phase 16 — Certification
- [ ] `FINAL_GAUNTLET_REPORT.md`, `PARITY_RUNBOOK.md`, `RELEASE_CERTIFICATION_TEMPLATE.md` rendered
- [ ] Strict-conformant-release.v1 constants pass: `MIN_VERIFICATION_PCT=100`, `REQUIRED_SUITE_PASS_RATE_PCT=100`, `MAX_HIGH_SEVERITY_COUNTEREXAMPLES=0`, `MAX_EVIDENCE_AGE_HOURS=24`
- [ ] `certification_bundle/` directory written + `BUNDLE_MANIFEST.json` SHA-256s pinned

## SQL-class extras (beyond the base gauntlet)
- [ ] `sample_sqlite_db_files/golden/` real-world `.db` files committed
- [ ] WAL self-healing via RaptorQ fountain codes (if MVCC plane present)
- [ ] `core_sql_golden_blake3.json` per-stage hash manifest
- [ ] `sqlite3 -cmd '.pragma list'` automated diff against `supported_surface_matrix.toml` for PRAGMA drift
