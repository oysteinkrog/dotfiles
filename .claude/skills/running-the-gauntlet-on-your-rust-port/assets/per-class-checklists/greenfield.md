# Greenfield-Rust-class Adoption Checklist

For projects in the Greenfield-Rust-class — novel non-port Rust projects with no external reference implementation. The canonical member is `eidetic_engine_cli`; the meta-pattern is [`references/methodology/GREENFIELD-ADAPTATION.md`](../../references/methodology/GREENFIELD-ADAPTATION.md). Verify each item; tick as adopted; record exceptions in `<workspace>/GREENFIELD_CHECKLIST_DEVIATIONS.md` with justification.

The defining difference from port-class checklists: there is no upstream reference to wrap. The Oracle is constructed from one or more of the 5 modes (Spec / Property / Self / Round-trip / External-tool) and dispatched per-scenario via the `OracleMode` enum — see [`subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md). Most projects use 3-4 modes in combination.

---

## Project shape sanity

- [ ] `<target>/Cargo.toml` read; layout classified as **workspace** (multi-crate under `crates/`) or **single-crate** (one `[package]` with optional `[workspace] exclude = [...]` opt-out). Rationale: harness module path depends on the layout — `crates/<port>-harness/src/...` vs `src/harness/...`.
- [ ] If single-crate AND `AGENTS.md` (or analog) contains a "single binary crate ... not a workspace" comment, the layout is **intentional**: do not promote to workspace without user signoff. See [`references/cookbook/single-crate-vs-workspace-decision.md`](../../references/cookbook/single-crate-vs-workspace-decision.md).
- [ ] `AGENTS.md` (or analog) read for project-specific hard constraints: "NO WORKTREES" rules, file-deletion prohibitions, branch policies. The gauntlet OBEYS these — never override.
- [ ] Spec sources enumerated: typically `docs/spec/v1/`, `README.md § Hard Requirements`, `AGENTS.md § Hard Requirements (Non-Negotiable)`, `COMPREHENSIVE_PLAN_*.md`. All pinned by SHA-256 in `docs/contracts/spec_version_contract.toml` per [`references/methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../../references/methodology/SPEC-PINNING-FOR-GREENFIELD.md).
- [ ] `scripts/detect-project-class.sh <target> --workspace <workspace>` writes `<workspace>/phase0_project_class.json.detected_class == "UNKNOWN"` (the greenfield trigger) OR user explicitly invoked `--mode gauntlet-greenfield`.

## Phase 0 — Workspace

- [ ] `<workspace>/` initialized as its own git repo (NEVER inside the target's repo — keeps the gauntlet's evidence separable from the project's history).
- [ ] `<workspace>/phase0_intake.json` records `mode == "gauntlet-greenfield"` and the chosen `oracle_modes_enabled` subset (typically 3-5 of the 5 modes).
- [ ] `<workspace>/phase0_project_class.json` records `detected_class == "UNKNOWN"` + reason.
- [ ] Layout decision (workspace vs single-crate) recorded in `<workspace>/phase0_layout.json` with rationale, file paths affected, and user-signoff timestamp if promoted.

## Phase 2 — Spec pinning (replaces Reference pinning)

- [ ] `docs/contracts/spec_version_contract.toml` pins all 5 contract families per [`references/methodology/SPEC-PINNING-FOR-GREENFIELD.md § 2`](../../references/methodology/SPEC-PINNING-FOR-GREENFIELD.md): `[[spec_sources]]`, `[property_suite]`, `[golden_snapshots]`, `[[roundtrip_corpus]]`, `[external_tools.{miri,clippy,cargo_deny,cargo_audit}]`.
- [ ] Every `[[spec_sources]]` entry has SHA-256 pinned + a section anchor (e.g., `path = "AGENTS.md#hard-requirements-non-negotiable"`).
- [ ] Spec-conflict scan run via `scripts/check-spec-coherence.sh`; output is empty (no contradictory pairs) OR `<workspace>/phase2_spec_conflict.md` documents each conflict for user resolution per [`references/cookbook/spec-conflict-detected.md`](../../references/cookbook/spec-conflict-detected.md).
- [ ] `docs/spec/SPEC-TAGS.md` enumerates every `[SPEC-<area>-NNN]` tag extracted; each row has Tag / Statement / Source / Verifier.
- [ ] Unverifiable / aspirational assertions moved to `docs/CHARTER.md`; they do NOT get `[SPEC-NNN]` tags.
- [ ] `[oracle_modes_enabled]` block names exactly which of the 5 modes this project uses (most use 3-4).

## Phase 3 — Oracle wiring (5-mode dispatch)

- [ ] `OracleMode` enum present with variants `Spec(...) | Property(...) | Self_(...) | RoundTrip(...) | ExternalTool(...)`.
- [ ] 30-line `scenario()` template dispatches across `OracleMode` per [`references/methodology/GREENFIELD-ADAPTATION.md § 2 Conformance`](../../references/methodology/GREENFIELD-ADAPTATION.md). Both-error = agreement + one-error-one-OK = hard failure rules apply to ALL 5 modes.
- [ ] `spec_oracle.rs` — one `verify_spec_<tag>` function per `[SPEC-NNN]` tag; tag-without-verifier orphans surface via `scripts/check-spec-tag-orphans.sh` per [`references/cookbook/spec-tag-orphan-cleanup.md`](../../references/cookbook/spec-tag-orphan-cleanup.md).
- [ ] `property_oracle.rs` — bridges proptest's `TestRunner` into `MismatchSignature` pipeline; `FileFailurePersistence::WithSource("regressions")` set; `proptest-regressions/` directory committed to git.
- [ ] `self_oracle.rs` — wraps insta's `assert_snapshot!`; `tests/snapshots/*.snap` committed; `bless_policy = "manual"` in contract.
- [ ] `roundtrip_oracle.rs` — one `roundtrip_<name>(input, label)` function per (encode, decode) / (serialize, parse) / (pack, unpack) / (sign, verify) pair listed in `[[roundtrip_corpus]]`.
- [ ] `external_tool_oracle.rs` — Miri + Clippy + cargo-deny + cargo-audit adapters; each treats nonzero exit as `TrueDivergence`-equivalent.
- [ ] `oracle_preflight_doctor.rs` (greenfield variant) verifies: spec SHA-256 matches contract; every `[SPEC-NNN]` tag has a verifier; every property test has a regressions file; every emitted format has a snapshot; every roundtrip pair has a golden; all external tools' `--version` succeeds.
- [ ] `EngineIdentity` discriminator: `SUBJECT_IDENTITY_LABEL = "<project>"`; `REFERENCE_IDENTITY_LABEL ∈ {"spec-vN", "property-suite-vN", "prior-commit-<sha>", "round-trip", "miri", "clippy"}` per per-scenario mode. Self-comparison panics.
- [ ] `tests/spec_oracle_smoke.rs` — one trivial `#[test]` per oracle mode + a preflight-doctor green-on-current-workspace test.

## Phase 4 — Golden capture (Self-Oracle)

- [ ] For every emitted output format (`text`, `json`, `markdown`, `csv`, etc.): one `assert_snapshot!` per canonical scenario.
- [ ] Tier 2 canonical normalizer applied BEFORE `assert_snapshot!` (sort JSON keys; collapse whitespace; strip help-text version suffix). Snapshot the normalized form per [pattern:55-INSTA-GOLDEN-SNAPSHOTS § Tier 2 Normalization](../../references/patterns/55-INSTA-GOLDEN-SNAPSHOTS.md).
- [ ] Round-trip golden artifacts in `tests/golden/<feature>_v<N>.golden` for every `[[roundtrip_corpus]]` entry.
- [ ] `scripts/bless-golden.sh` exists; runs only on explicit operator invocation; produces a `golden_bump_<N>.md` rationale per bless. NEVER auto-bless in CI.
- [ ] Snapshot count floor (`spec_version_contract.toml#/golden_snapshots.snapshot_count_floor`) enforced by CI gate — a regen that drops the count is a release blocker until reviewed.

## Performance harness

- [ ] `comprehensive_bench.rs` extends the project's existing bench surface (NOT replaces — many greenfield projects already have a strong `benches/` directory; honor it).
- [ ] `release-perf` profile in `Cargo.toml`: inherits release, `opt-level=3`, `lto="thin"`, `codegen-units=1`, `debug="line-tables-only"`, `strip=false`, `RUSTFLAGS="-C force-frame-pointers=yes"`.
- [ ] JSON v3 self-describing report with `DetectedEnvironment` top-level field for every bench.
- [ ] `.bench-history/<bench>.latest.json` committed to git per bench; pass-over-pass ratchet wired per [pattern:155-BENCH-HISTORY-RATCHET](../../references/patterns/155-BENCH-HISTORY-RATCHET.md).
- [ ] `concurrent_mode_default_guard.txt` (or project-specific analog like `single_writer_invariant_guard.txt` for SQLite-backed projects) dropped in every artifact lane.
- [ ] MT8-equivalent bench: 8-thread shared-writer + N-thread readers, configured per the project's actual concurrency surface. For eidetic: `mt8_remember_bench.rs`.
- [ ] Hot-path counters: project-specific set per [`references/taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../../references/taxonomy/PROJECT-CLASSES.md). For eidetic: `remember_latency_ns, recall_latency_ns, pack_assembly_time_ns, embed_dedup_ratio, sqlite_busy_retries, index_rebuild_progress_pct, arena_alloc_bytes`. Every shared counter uses `AtomicU64` (lost-update bug #8 in [`references/first-bug-hunt/greenfield-rust-class.md`](../../references/first-bug-hunt/greenfield-rust-class.md)).
- [ ] Pass-over-pass gate thresholds: primary `-3%`, geomean `-5%`, per-category `-10%`, p90 `-15%`, throughput `-5%` (unchanged from other classes).
- [ ] Prior-commit baseline serves as the implicit "second engine" in Differential V2 envelope; `EngineVersions.reference_identity = "prior-commit-<sha>"`.

## Conformance harness

- [ ] Per-behavior oracle E2E tests in `tests/<behavior>_oracle_e2e.rs`, one file per behavior class (e.g., `pack_budget_oracle_e2e.rs`, `recall_determinism_oracle_e2e.rs`).
- [ ] Property tests in `tests/<area>_proptest.rs` with `proptest-regressions/` committed; minimum 5 properties per behavior class per [`assets/property-test-templates/greenfield_proptest.rs`](../property-test-templates/greenfield_proptest.rs).
- [ ] 4 TransformFamily metamorphic transforms per [pattern:40-METAMORPHIC-TRANSFORMS](../../references/patterns/40-METAMORPHIC-TRANSFORMS.md): Predicate / Projection / Structural / Literal. Per-family `soundness_proof_sketch` mandatory.
- [ ] `MismatchClassification` triage; CI fails only on `TrueDivergence`. Greenfield-specific extensions: `SpecConflict`, `UnverifiedSpecTag`, `SeedContractViolation`, `SurfaceDrift` (see [`references/first-bug-hunt/greenfield-rust-class.md`](../../references/first-bug-hunt/greenfield-rust-class.md)).
- [ ] Differential fuzz targets in `fuzz/fuzz_targets/`: one per round-trip pair + one per spec-tag cluster. Template at [`assets/fuzz-target-templates/greenfield_fuzz.rs`](../fuzz-target-templates/greenfield_fuzz.rs).
- [ ] E-processes on 5-10 project-defining invariants per [pattern:70-E-PROCESSES](../../references/patterns/70-E-PROCESSES.md). For eidetic: `remember_collision_rate_below_1e-15`, `recall_determinism_under_same_query`, `pack_budget_respected_within_1pct`, etc.

## Surface inventory

- [ ] FeatureUniverse built from union of: (a) every `clap` subcommand + flag; (b) every `pub` item in `src/lib.rs`; (c) every `[SPEC-NNN]` tag's promise; (d) every documented user-facing invariant. Per [`references/methodology/GREENFIELD-ADAPTATION.md § 2 Surface parity`](../../references/methodology/GREENFIELD-ADAPTATION.md).
- [ ] `parity_taxonomy.rs` enumerates `Feature { id: F-{CAT}-{SEQ}, ... }` with weights summing to 1.0 per category.
- [ ] `supported_surface_matrix.toml` declares every feature `present | partial | missing | n/a | excluded`.
- [ ] Every `Excluded` item has `exclusion_rationale` + retry-condition predicate per [pattern:185-RETRY-CONDITION-PREDICATE](../../references/patterns/185-RETRY-CONDITION-PREDICATE.md).
- [ ] `scripts/compare-cli-vs-spec.sh` wired as CI gate — drift between clap surface and spec surface caught at PR-time per bug #10 in [`references/first-bug-hunt/greenfield-rust-class.md`](../../references/first-bug-hunt/greenfield-rust-class.md).
- [ ] Closure-Wave discipline applied per [pattern:115-CLOSURE-WAVE](../../references/patterns/115-CLOSURE-WAVE.md): stage-by-stage coverage deltas; never accumulate blind spots; pipeline-stage-by-stage closure with explicit dirty-bit per stage.

## Fault surface (project-specific)

- [ ] Project's actual fault surface enumerated. For storage-class greenfield (eidetic): SQLite-backed fault VFS with 5 storage-boundary fault kinds + 2 long-running-procedure fault kinds (per [`references/taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../../references/taxonomy/PROJECT-CLASSES.md)).
- [ ] For network-class greenfield: connection-drop, slow-loris, partial-read, partial-write fault kinds.
- [ ] For compute-class greenfield: OOM-mid-allocation, signal-mid-syscall, fd-exhausted fault kinds.
- [ ] `FaultSpec` schema + injection harness; each FaultKind has a recovery oracle per [pattern:60-FAULT-VFS](../../references/patterns/60-FAULT-VFS.md).
- [ ] New fault classes discovered during soak go through [`references/cookbook/new-fault-class-discovered.md`](../../references/cookbook/new-fault-class-discovered.md).

## Crash boundaries

- [ ] Named crash boundaries enumerated for the project's actual durability surface. For eidetic (storage class): `BeforeBeginImmediate, BeforeCommit, BetweenCommitAndFsync, BeforeWalCheckpoint, AfterCheckpoint, MidIndexRebuild, MidContextStreamSpill`.
- [ ] For each boundary: at least one crash-recovery test that crashes at the boundary and asserts the recovery contract (durability / atomicity / consistency / isolation as applicable).
- [ ] Boundaries × FaultKinds product is the fault matrix; CI `.github/workflows/fault-vfs-coverage.yml` exercises at least one cell per (boundary, fault_kind) pair per release.

## Hot-path counters

- [ ] Project-specific counter set declared in `src/harness/hot_path_counters.rs`. For eidetic: 7 counters per [`references/taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class § Hot-path counters`](../../references/taxonomy/PROJECT-CLASSES.md).
- [ ] Every shared counter is `AtomicU64` with documented `Ordering`. Monotonic counters: `Ordering::Relaxed`. Ordered-w.r.t.-data counters: `Acquire`/`Release`.
- [ ] MT8 invariant: `sum_per_thread(counter) == global(counter)` as an e-process per bug #8 in [`references/first-bug-hunt/greenfield-rust-class.md`](../../references/first-bug-hunt/greenfield-rust-class.md).
- [ ] Each counter surfaces in `HotPathProfileSnapshot` JSON output of every bench; ratchet-blocked if any counter regresses by >10% pass-over-pass.

## Negative-ledger seed terms

- [ ] `PERF_NEGATIVE_RESULTS.md`, `CONFORMANCE_NEGATIVE_RESULTS.md`, `SURFACE_DEFERRALS.md` seeded from [`assets/negative-ledger-seed.md`](../negative-ledger-seed.md).
- [ ] Project-specific failure terms appended to the seed vocabulary. For eidetic: `embed-cache-stale, ulid-tiebreak-loss, ppr-divergent, pack-overspill, why-stale-evidence, asupersync-cancel-leak` (per [`references/taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class § Negative-ledger failure terms`](../../references/taxonomy/PROJECT-CLASSES.md)).
- [ ] AGENTS.md mandate paragraph installed: "60-day cass mine + ledger grep before any perf candidate" per [`assets/agents-md-mandate-paragraph.md`](../agents-md-mandate-paragraph.md). For projects with an existing AGENTS.md, APPEND, never overwrite.
- [ ] Every ledger entry uses one of the 8 retry-condition predicate forms; forbidden phrases ("later", "TBD", "maybe", etc.) are CI-rejected by ledger-lint.

## Concurrency-honesty guard

- [ ] Project-specific concurrency-honesty rule documented. For eidetic: "every WriteApi call uses BEGIN IMMEDIATE on the writer connection; reader connections may not call BEGIN IMMEDIATE."
- [ ] `single_writer_invariant_guard.txt` (or project's analog of `concurrent_mode_default_guard.txt`) dropped into every artifact lane stating which connection mode was in effect.
- [ ] No `static mut` shared counters; ThreadSanitizer runs in CI per `tooling/SANITIZER-TOOLCHAIN.md`.
- [ ] Miri runs nightly on `--lib` covering the custom runtime adapter (if any) per bug #6 in [`references/first-bug-hunt/greenfield-rust-class.md`](../../references/first-bug-hunt/greenfield-rust-class.md).

## Certification-bundle additions

Same as other classes per [`references/methodology/CERTIFICATION.md`](../../references/methodology/CERTIFICATION.md), PLUS:

- [ ] `spec_source_sha256s.json` — every spec source's SHA-256 at certification time; auditor can reproduce the spec corpus.
- [ ] `property_suite_version.json` — property-suite git SHA + proptest version + `PROPTEST_CASES` floor at cert time.
- [ ] `golden_snapshot_manifest.json` — every snapshot file's SHA-256 + the bless rationale chain.
- [ ] `roundtrip_corpus_manifest.json` — every (encode, decode) pair's last passing seed + the differential-fuzz coverage hours.
- [ ] `external_tool_versions.json` — Miri nightly pin + Clippy version + cargo-deny advisory-DB SHA + cargo-audit advisory-DB SHA.
- [ ] `oracle_modes_enabled.json` — which of the 5 modes this release used + per-mode contribution to the parity score.
- [ ] Strict-conformant-release.v1 constants pass: `MIN_VERIFICATION_PCT=100`, `REQUIRED_SUITE_PASS_RATE_PCT=100`, `MAX_HIGH_SEVERITY_COUNTEREXAMPLES=0`, `MAX_EVIDENCE_AGE_HOURS=24`. For greenfield, `MIN_VERIFICATION_PCT=100` means EVERY `[SPEC-NNN]` tag has a passing verifier AND every emitted format has a current snapshot AND every roundtrip pair has a clean differential-fuzz run within 24h.

## Greenfield-class extras (beyond the base gauntlet)

- [ ] `docs/spec/SPEC-TAGS.md` updated on every spec edit; CI gate ensures it's in sync with the spec sources via `scripts/check-spec-tag-orphans.sh`.
- [ ] Differential fuzz against round-trip oracle: continuously run on dev machines + soak in CI for 24h+ per release.
- [ ] Self-oracle drift tolerance: prior-commit baseline serves as the implicit second engine; any departure-without-rationale (no `golden_bump_<N>.md`) is `TrueDivergence`.
- [ ] If the project has a custom async runtime (e.g., asupersync per eidetic), the custom runtime gets its own MT-stress test under `cargo +nightly miri test`; UB findings are critical.
- [ ] `scripts/compare-cli-vs-spec.sh` AND `scripts/check-spec-tag-orphans.sh` AND `scripts/check-spec-coherence.sh` all wired as CI gates; surface drift caught at PR-time.

## Cross-references

- [`references/methodology/GREENFIELD-ADAPTATION.md`](../../references/methodology/GREENFIELD-ADAPTATION.md) — the meta-pattern.
- [`references/methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../../references/methodology/SPEC-PINNING-FOR-GREENFIELD.md) — Phase 2 adaptation.
- [`references/case-studies/eidetic_engine_cli.md`](../../references/case-studies/eidetic_engine_cli.md) — concrete worked example.
- [`references/taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../../references/taxonomy/PROJECT-CLASSES.md) — the class row.
- [`references/first-bug-hunt/greenfield-rust-class.md`](../../references/first-bug-hunt/greenfield-rust-class.md) — 10 first-day bugs.
- [`subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md) — Phase 3 5-mode wiring.
- [`assets/integration-test-templates/greenfield_oracle_e2e.rs`](../integration-test-templates/greenfield_oracle_e2e.rs) — paste-ready E2E.
- [`assets/property-test-templates/greenfield_proptest.rs`](../property-test-templates/greenfield_proptest.rs) — paste-ready properties.
- [`assets/fuzz-target-templates/greenfield_fuzz.rs`](../fuzz-target-templates/greenfield_fuzz.rs) — paste-ready fuzz.
- [`references/cookbook/spec-conflict-detected.md`](../../references/cookbook/spec-conflict-detected.md)
- [`references/cookbook/single-crate-vs-workspace-decision.md`](../../references/cookbook/single-crate-vs-workspace-decision.md)
- [`references/cookbook/spec-tag-orphan-cleanup.md`](../../references/cookbook/spec-tag-orphan-cleanup.md)
