# Case Study — eidetic_engine_cli

A worked walkthrough of running the gauntlet on a **non-port, greenfield** Rust project. Demonstrates how the same Subject/Oracle/Comparator discipline applies when there's no upstream reference to diff against — the Oracle is constructed from the project's own spec + property suite + prior-commit baseline + round-trip tests + external tools.

Reference: `/dp/eidetic_engine_cli` (path: `/data/projects/eidetic_engine_cli/`).

Cross-link: [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md), [`methodology/MODE-ROUTER.md § gauntlet-greenfield`](../methodology/MODE-ROUTER.md), [`taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../taxonomy/PROJECT-CLASSES.md).

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Project class** | Greenfield-Rust-class (with storage-class adjacency: SQLite-backed) |
| **Tier** | T3 (single-crate package with 24+ criterion benches; rch recommended for full bench sweep) |
| **Recommended mode** | `gauntlet-greenfield` |
| **What it is** | `ee` — a durable, local-first, explainable memory layer for coding agents |
| **Stack** | Rust 2024, asupersync (NO tokio), SQLite-backed, single-binary CLI with library surface in same package |
| **README claim summary** | "ee stores facts, decisions, procedural rules, anti-patterns, session evidence; indexes lexical + semantic; connects with graph features; emits compact context packs with provenance" |
| **Reference** | NONE (novel project) — Oracle is the project's own spec + property suite + prior-commit baseline + round-trip tests + Miri/Clippy |
| **Existing bench surface** | 24+ criterion benches under `benches/` (remember, recall, search, pack, graph_*, ppr, hits, ktruss, louvain, etc.) — already at gauntlet-grade |

## 2. Adoption matrix (greenfield-adapted)

| Pillar machinery | Status | Notes |
|---|:---:|---|
| Differential V2 envelope | ⚠️ partial | Need to switch `EngineVersions.reference_identity` from "upstream" model to `"spec-v1"` + `"prior-commit-<sha>"` |
| EngineIdentity discriminator | ❌ | greenfield discriminator naming convention needs adopting (Subject = `ee`; Oracle = whichever of the 5 modes per scenario) |
| Oracle preflight doctor | ❌ | greenfield variant verifies spec SHA-256 + property-suite SHA-256 + golden-snapshot freshness |
| Fixture root contract | ⚠️ partial | `tests/fixtures/` exists with golden artifacts; manifest SHA-256 + cardinality floors not yet pinned |
| 30-line scenario template | ❌ | greenfield variant (spec_scenario / property_scenario / roundtrip_scenario) per [`GREENFIELD-ADAPTATION.md § 5-8`](../methodology/GREENFIELD-ADAPTATION.md) |
| Metamorphic transforms | ⚠️ partial | Round-trip tests exist (e.g., `import_cass` bench implies); per-family TransformFamily catalog not authored |
| Mismatch minimizer | ❌ | needed for `TrueDivergence` triage |
| Three-tier equivalence | ⚠️ partial | Insta snapshots used (`tests/snapshots/`) but the Tier 1/2/3 distinction isn't explicit |
| Fault VFS | ⚠️ partial | SQLite-backed → need SQLite-specific fault VFS (see crash boundaries below) |
| Crash boundaries (named) | ❌ | greenfield/storage-class boundaries listed below |
| E-processes (5-10 invariants) | ❌ | strong candidates listed below |
| Bayesian + conformal score | ❌ | adopt per-CLI-subcommand category weights |
| BOCPD regime detection | ❌ | wire on the per-round latency-stream from `cargo bench` |
| Adversarial search | ❌ | gates exist (clippy `-D warnings`, miri, benchmark budgets in `benches/budgets.toml`) but not adversarially probed |
| FeatureUniverse | ⚠️ partial | `clap` subcommand tree implicit; explicit `parity_taxonomy.rs`-style enumeration not yet authored |
| Invariant catalog | ⚠️ partial | Hard Requirements in AGENTS.md serve as informal invariants; not formalized as `ParityInvariant + ProofObligation` |
| Closure-Wave | ❌ | per-CLI-subcommand × per-flag closure not enumerated |
| Verification contract enforcement | ❌ | beads exist (`.beads/`) but verification-contract gating not wired |
| comprehensive-bench skeleton | ⚠️ partial | 24+ benches exist with budgets; missing JSON v3 self-describing report + DetectedEnvironment + `.bench-history/<bench>.latest.json` ratchet |
| HotPathProfileSnapshot | ❌ | greenfield counter set (below) needs authoring |
| Profile-first card + proof pack | ❌ | not adopted |
| MT8 attribution | ❌ | needs `mt8`-equivalent multi-writer concurrency bench (current `concurrent_writes.rs` is a starting point) |
| Pass-over-pass gate | ❌ | gate thresholds set in `benches/budgets.toml` but not in `.bench-history/*.latest.json` self-comparing form |
| Robust regression detector (MAD) | ⚠️ partial | criterion provides some — need median+MAD wrapper |
| Negative ledger (3 files) | ❌ | seed from `assets/negative-ledger-seed.md` |
| AGENTS.md mandate paragraph | ⚠️ partial | AGENTS.md has many rules but not the explicit "60-day cass mine + ledger grep" mandate |
| cass mining (60-day cross-machine) | ❌ | wire per [`pattern:190-CASS-MINING`](../patterns/190-CASS-MINING.md) |
| FailureBundle v1.0.0 | ❌ | not authored |
| First-failure explainer | ❌ | wire per [`pattern:95-FIRST-FAILURE-EXPLAINER`](../patterns/95-FIRST-FAILURE-EXPLAINER.md) |
| E2E log schema (logs-as-API) | ⚠️ partial | structured logging exists; per-event schema not pinned at `LOG_SCHEMA_VERSION` |

**Net status:** strong informal floor (24+ benches, insta snapshots, beads, very disciplined AGENTS.md); needs the gauntlet's *formalization* layer to convert informal practice into release-certifiable evidence.

## 3. Per-pillar deep dive

### Perf (pillar a) — likely first 3 gaps the gauntlet would surface

1. **No `.bench-history/<bench>.latest.json` committed** — every existing bench would benefit from pass-over-pass ratchet wiring. First-week win: pick `search.rs` and `pack_size.rs` as primary benches; commit baseline `.bench-history` files; gate at `-5%` throughput, `-15%` p90 latency.
2. **MT8-equivalent missing** — `concurrent_writes.rs` exercises concurrency but not at the "8-thread shared writer + N-thread readers" shape that surfaces SQLite-backed-storage hot-path contention. Add `mt8_remember_bench.rs` with the comprehensive-bench scenarios pattern.
3. **No HotPathProfileSnapshot for the ee-specific counters** — `remember_latency_ns`, `recall_latency_ns`, `pack_assembly_time_ns`, `embed_dedup_ratio`, `sqlite_busy_retries`, `index_rebuild_progress_pct`, `arena_alloc_bytes`. These are the per-domain counters per [`pattern:145-HOT-PATH-COUNTERS § HTTP-Class analog row`](../patterns/145-HOT-PATH-COUNTERS.md).

### Conformance (pillar b) — likely first 3 gaps

1. **Spec assertions not tagged** — the project has `COMPREHENSIVE_PLAN_TO_MAKE_EE.md`, README "Hard Requirements", AGENTS.md "Hard Requirements (Non-Negotiable)", `CLOSE_THE_GAP_PLAN.md`. Audit pass would extract every assertion → tag with `[SPEC-ee-NNN]` → author one verifier per tag → drive via spec-oracle. Estimated 80-150 assertions to surface.
2. **Round-trip oracles missing for serialization paths** — `pack` produces a context-pack; `import_cass` consumes them. A round-trip `pack→import→pack == identity` test would surface format-drift bugs. Same for: every embedding's vector-roundtrip; every graph-edge's add-then-query roundtrip.
3. **No metamorphic transforms catalog** — for example: `remember(x); remember(y); recall(q)` semantics should hold under permutation of remember-ordering when the items are independent (Predicate-family transform); `pack(query, budget=B)` then `pack(query, budget=2B)` should produce a strict superset of items (Structural-family transform).

### Surface (pillar c) — likely first 3 gaps

1. **CLI subcommand enumeration not pinned** — `clap`'s help output is the de-facto surface; `parity_taxonomy.rs`-style enumeration with weights summing to 1.0 per category needs authoring. Categories: `query` (search, recall, pack, why), `mutate` (remember, link, outcome), `admin` (status, index_rebuild, workspace_init), `audit` (audit_query, baselines).
2. **Spec promises not mapped to FeatureUniverse entries** — every "Hard Requirement" in AGENTS.md should be a `Feature { id: F-INVAR-NNN, ... }` with weight; current state has them as prose-only.
3. **`partial` features not declared** — likely several CLI flags or behaviors are documented as "Phase 0 doesn't yet support X"; these should explicitly be Excluded with `exclusion_rationale` + `retry_condition_predicate` per [`pattern:185-RETRY-CONDITION-PREDICATE`](../patterns/185-RETRY-CONDITION-PREDICATE.md), not silently absent.

## 4. First-pass recipe (paste-ready)

```bash
# Phase 0 (15-30 min)
cd /data/projects/eidetic_engine_cli
~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/install-toolchain.sh
~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/init-workspace.sh \
  /data/projects/eidetic_engine_cli /data/projects/eidetic_engine_cli__gauntlet_workspace
~/.claude/skills/running-the-gauntlet-on-your-rust-port/scripts/detect-project-class.sh \
  /data/projects/eidetic_engine_cli --workspace /data/projects/eidetic_engine_cli__gauntlet_workspace
# → detected_class: UNKNOWN; orchestrator confirms greenfield mode with user.

# Phase 1 RECON (1-2h; per-crate archaeology — eidetic is single-crate so 1 archaeologist)
# Dispatch surface-archaeologist subagent against /data/projects/eidetic_engine_cli/src/
# Output: phase1_recon_eidetic-engine.md mapping every pub fn, every clap subcommand, every Hard Requirement.

# Phase 2 SPEC PINNING (greenfield variant) — author 4 contracts (1-2h)
#   docs/contracts/spec_version_contract.toml       (pin spec doc SHA-256)
#   docs/contracts/supported_surface_matrix.toml    (every CLI subcommand + every pub fn + every Hard Requirement)
#   docs/canonical_parity_contract.md               (definition of "done" for ee v1)
#   docs/contracts/parity_score_contract.toml       (per-category weights)

# Phase 3 ORACLE WIRING (greenfield 5-mode) — 3-4h
# NOTE: eidetic is intentionally a single-binary-crate per its Cargo.toml comment
# ("single binary crate with a library surface in the same package; not a workspace
# in phase 0") and AGENTS.md Rule #2 "NO WORKTREES. EVER. NO EXCEPTIONS." So harness
# modules live INSIDE the existing crate under src/harness/, NOT in a new crates/
# subdirectory. Promoting to a workspace requires user signoff and updating the
# Cargo.toml [workspace] block — DO NOT do this unprompted.
#   src/harness/spec_oracle.rs                      (one verifier per [SPEC-ee-NNN] tag)
#   src/harness/property_oracle.rs                  (5-20 properties per behavior)
#   src/harness/self_oracle.rs                      (insta-snapshot bridge)
#   src/harness/roundtrip_oracle.rs                 (pack-import / embed / graph-edge / ulid round-trips)
#   src/harness/external_tool_oracle.rs             (Miri + Clippy + cargo-deny adapters)
#   src/harness/oracle_preflight_doctor.rs          (greenfield variant: verifies spec SHA-256, property-suite version, golden-snapshot freshness)
#   src/harness/mod.rs                              (pub mod declarations; `#[cfg(any(test, feature = "harness"))]` gated)

# Phase 4 GOLDEN CAPTURE — Tier 2 canonical snapshots for every output format (2-3h)
#   tests/golden/context_pack_v1.golden
#   tests/golden/embedding_format_v1.golden
#   tests/golden/audit_event_v1.golden
#   ... per format ...

# Phase 5 PERF HARNESS (1-2 days)
# Honors the single-crate constraint: extend the existing benches/ directory; new
# bins live in src/bin/ (cargo auto-discovered) NOT in crates/ee-e2e/src/bin/.
#   benches/comprehensive_bench.rs                  (wraps existing benches with JSON v3 + DetectedEnvironment)
#   benches/mt8_remember_bench.rs                   (8-thread shared-writer concurrency)
#   src/harness/hot_path_counters.rs                (ee-specific counter set, behind `harness` feature)
#   .bench-history/comprehensive_bench.latest.json  (initial commit)

# Phase 6 CONFORMANCE HARNESS (3-5 days)
#   Per-behavior oracle E2E tests (~10-15 files)
#   Metamorphic transforms catalog (4 families)
#   Property tests with proptest-regressions/
#   FaultSpec + greenfield-storage crash boundaries (5 SQLite + 2 long-running)
#   E-processes on the 5-10 ee invariants

# Phase 7 SURFACE INVENTORY (1 day)
# Phase 8 LEDGER + AGENTS.md MANDATE (2h)
# Phase 9 BASELINE RUN (1-2 days incl. rch dispatch)
# Phase 10+ — proceed per the 16-phase loop.
```

**Estimated wall-time to first BASELINE complete (Phase 9 exit):** ~7-10 days with a single orchestrator + 4-6 panes via NTM; or ~3-5 days with full T3 swarm + rch on the soak phases.

## 5. Expected pillar findings (top 5-10 per pillar)

### Perf

1. SQLite `SQLITE_BUSY` retry counter is invisible; likely contention under MT8 that needs surfacing.
2. `pack_assembly_time_ns` has a long tail for large queries (graph-traversal-dominated) — easy MT8 attribution target.
3. ULID tiebreak under high-cardinality remember-bursts: existing `ulid_tiebreak.rs` bench surfaces a cluster; pass-over-pass ratchet would catch regression.
4. Embedding-dedup ratio likely drops as the corpus grows; needs continuous monitoring.
5. `index_rebuild` is a deferred batch op; latency distribution likely has a 99th-percentile cliff at corpus-size boundaries.
6-10. Per-bench per-budget overruns visible in `benches/budgets.toml` will surface as candidates for the ratchet.

### Conformance

1. **`why` provenance staleness** — if a fact is updated, does `why <id>` cite the prior evidence or the current? Likely a `TrueDivergence` until the spec is explicit.
2. **`recall` non-determinism under tied scores** — ULID tiebreak should make this deterministic; needs e-process invariant.
3. **`pack` budget overspill** — if the configured token budget is N, does `pack` ever emit >N? Likely property-violation worth proptest'ing.
4. **`outcome` ordering** — if outcomes arrive concurrently with the same timestamp, what's the resolution? Likely an invariant gap.
5. **Embed-cache staleness** — when does the cache invalidate? Cross-pillar between perf (cache-key audit per [`pattern:245-CACHE-KEY-EVICTION-AUDIT`](../patterns/245-CACHE-KEY-EVICTION-AUDIT.md)) and conformance (does a stale embed produce a wrong recall?).
6. **Miri findings on the asupersync runtime adapter** — UB potential in custom async runtime; Miri would surface.
7. **Concurrent-writer invariant under `BEGIN IMMEDIATE` contention** — if two writers race, does the second wait or fail? Spec needs to state.
8-10. Various round-trip identity violations in the import/export paths.

### Surface

1. **Excluded items currently absent** — for Phase 0 release, several v2 features (graph_ktruss?, graph_louvain?) may be deferred but not declared as Excluded with rationale.
2. **CLI flag combinations not enumerated** — Closure-Wave on `remember --tag X --confidence Y --ttl Z` cross-product.
3. **Output formats** (JSON, text, markdown, ...) — surface enumeration per output mode.
4. **Hermeticity claim coverage** — every external-tool dependency (`embed-server-url`, etc.) needs an explicit invariant about graceful degradation.
5. **Backwards-compat policy** — AGENTS.md says "no backwards compat in Phase 0"; this needs to be a Surface declaration so future agents don't add shims.

## 6. Project-specific patterns to apply first

1. **[`pattern:55-INSTA-GOLDEN-SNAPSHOTS`](../patterns/55-INSTA-GOLDEN-SNAPSHOTS.md)** — already partial; formalize per Tier 2 canonical.
2. **[`pattern:30-DIFFERENTIAL-V2-ENVELOPE`](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md)** with greenfield-adapted `EngineVersions.reference_identity`.
3. **[`pattern:155-BENCH-HISTORY-RATCHET`](../patterns/155-BENCH-HISTORY-RATCHET.md)** — convert existing `benches/budgets.toml` into a `.bench-history/` ratchet.
4. **[`pattern:70-E-PROCESSES`](../patterns/70-E-PROCESSES.md)** — wire 5-10 ee-specific invariants (see §3 conformance findings).
5. **[`pattern:115-CLOSURE-WAVE`](../patterns/115-CLOSURE-WAVE.md)** — enumerate CLI surface stage-by-stage.

## 7. Estimated rounds to convergence

**10-13 rounds** (the gauntlet minimum is 10). Reasoning:
- Round 1-3: surface-coverage build-out (Closure-Wave per pipeline stage); most findings.
- Round 4-6: perf-attribution sweep; MT8 + cache-key audit + SQLITE_BUSY tuning.
- Round 7-9: conformance — metamorphic catalog completion; round-trip exhaustive fuzz.
- Round 10+: BOCPD shows Stable regime; <3 new findings per round; consecutive clean rounds achieved.

Greenfield projects with strong informal floors (like eidetic) typically converge faster than a fresh port that's far from parity — most of the work is *formalizing* what already exists.

## 8. Risk register

1. **Asupersync determinism** — custom non-tokio runtime; gauntlet's loom/shuttle assumes tokio-style. Need a custom concurrency-testing approach.
2. **SQLite-backed storage on different OS** — fsync semantics differ across Linux/macOS/Windows; the FaultVfs needs per-OS calibration.
3. **Single-binary-with-library architecture** — fewer test surfaces than a multi-crate workspace; some patterns (per-crate fan-out) collapse to single-archaeologist.
4. **Spec is still being authored** — multiple `COMPREHENSIVE_PLAN_TO_MAKE_EE.md`-style docs; the gauntlet's Phase 2 must canonicalize one source of truth before proceeding.

## 9. What ships from convergence

The certification bundle for eidetic_engine_cli v0.1.0 would contain:

- `confidence_gate.json` — conformal lower bound ≥ 0.85 across all 4 CLI categories (query/mutate/admin/audit).
- `verification_contract.json` — every [SPEC-ee-NNN] tag's verifier status; release requires 100% pass.
- `release_certificate.json` — strict-conformant-release.v1; `certifying: true` only when all 4 required-pass constants hold.
- `benchmark_summary.json` — per-bench primary score + cv_pct; gates at the budgets in `benches/budgets.toml`.
- `scorecards.json` — per-category Beta posterior + conformal band.
- `eprocess_state.json` — current e-value for each of the 5-10 monitored invariants; all below 1/α.
- `ratchet_state.json` — monotonic per-pillar lower bounds.
- `bocpd_summary.json` — terminal regime `Stable` over 24h+ window.

## 10. Cross-references

- [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) — the meta-pattern.
- [`methodology/MODE-ROUTER.md`](../methodology/MODE-ROUTER.md) — `gauntlet-greenfield` mode definition.
- [`taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class`](../taxonomy/PROJECT-CLASSES.md) — the project-class row.
- [`first-bug-hunt/sql-class.md`](../first-bug-hunt/sql-class.md) — borrow SQL-class bug-hunt items for the SQLite-backed storage layer.
- `/data/projects/eidetic_engine_cli/AGENTS.md` — the project's existing discipline (already strong; gauntlet formalizes).
- `/data/projects/eidetic_engine_cli/COMPREHENSIVE_PLAN_TO_MAKE_EE.md` — primary source for spec assertions.
