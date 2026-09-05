# Glossary

Compact alphabetical glossary of every term-of-art the gauntlet uses. Each entry: verbatim definition + cross-link to its full treatment.

**adversarial search** — Active probing of every gate to find boundary flips. See [`pattern:85-ADVERSARIAL-SEARCH`](../patterns/85-ADVERSARIAL-SEARCH.md). Distinct from drift-monitor (passive).

**ArtifactRef** — `{path, hash, schema_version}` triple. Pins evidence to a content-addressable, schema-versioned artifact. See [`pattern:110-INVARIANT-CATALOG`](../patterns/110-INVARIANT-CATALOG.md).

**artifact_id** — `SHA-256` of canonical JSON of an `ExecutionEnvelope` **excluding** `run_id`. Two semantically-identical runs produce identical artifact IDs. See [Q-041 in `exemplars/QUOTE-BANK.md`](../exemplars/QUOTE-BANK.md). Pattern: [`30-DIFFERENTIAL-V2-ENVELOPE`](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md).

**BEAD_ID** — Convention: every harness module declares the bead it serves (e.g., `bd-1dp9.1.2`). Pairs with `SCHEMA_VERSION`. K-10 in [`methodology/KERNEL.md`](KERNEL.md).

**BOCPD** — Bayesian Online Change-Point Detection (Adams-MacKay 2007). Detects regime shift in a metric stream. Labels: `Stable | Improving | Regressing | ShiftDetected`. See [`pattern:80-BOCPD-REGIME-DETECTION`](../patterns/80-BOCPD-REGIME-DETECTION.md).

**both gates must move in the same run window** — The non-negotiable rule for kept perf changes: focused gate + broad gate must both pass within the same git state, same `target/`, same machine, same minute. [Q-002].

**broad gate** — The `comprehensive-bench` primary score gate. Contrasts with **focused gate**.

**cc_1 / cc_2 / cc_3 / cc_4** — Lane convention for parallel subagents. cc_1 = conformance/oracle/differential. cc_2 = perf/benches. cc_3 = surface/coverage/feature-universe. cc_4 = fault/crash/soak/e-process. See [`orchestration/ORCHESTRATION.md`](../orchestration/ORCHESTRATION.md).

**certification bundle** — Strict-conformant-release.v1 evidence pack assembled at Phase 16 by `certification-bundler`. See [`assets/release-certification-template.md`](../../assets/release-certification-template.md).

**closure wave** — Per-pipeline-stage gap-closure pattern: enumerate expected behaviors first, then test against both reference and subject. See [`pattern:115-CLOSURE-WAVE`](../patterns/115-CLOSURE-WAVE.md).

**concurrent_mode_default_guard.txt** — Per-project honesty file dropped into every artifact lane proving the project's defining feature was enabled. SQL example. For RESP it might be `resp_protocol_v3_guard.txt`; for ML `cuda_deterministic_guard.txt`. [Q-033].

**conformal band** — Distribution-free confidence band (Vovk-Gammerman-Shafer 2005). Release decisions use the LOWER bound. Pattern: [`75-BAYESIAN-CONFORMAL-SCORE`](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md). [Q-052].

**correctness-abandoned** — Status marker: a candidate killed before perf measurement because correctness failed. Distinct from "perf-rejected". [Q-094].

**cv_pct** — Coefficient of variation, percent. Microbench result with `cv_pct > 5%` is flaky and not eligible for keep. Used to gate the **micro-lever trap** ([Q-013, Q-035]).

**Diátaxis** — Four-quadrant docs model (Tutorial / How-to / Reference / Explanation). Used by `documentation-website-for-software-project`; informs this skill's reference vs methodology vs pattern decomposition.

**differential fuzz** — `arbitrary`-generated input driving both reference and subject through the comparator; any divergence = bug. Pattern: [`tooling/FUZZ-TOOLCHAIN.md`](../tooling/FUZZ-TOOLCHAIN.md).

**Differential V2 envelope** — Content-addressed envelope: `{schema_version, run_id?, scenario_id, seed, engines, pragmas, schema, workload, canonicalization}`. `artifact_id = SHA-256(canonical JSON \ run_id)`. Pattern: [`30-DIFFERENTIAL-V2-ENVELOPE`](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md).

**DML mutation operator** — FrankenSQLite-specific deferred-architectural redesign. Many DELETE entries are rejected with `"reconsider only inside the broader DML mutation operator redesign"` predicate. [Q-023]. Generalizes to any project's deferred-architectural-redesign queue.

**EngineIdentity** — `Subject::<port>` vs `Oracle::<reference>` strict-distinct identity strings. Prevents self-comparison. K-9. Pattern: [`15-ENGINE-IDENTITY`](../patterns/15-ENGINE-IDENTITY.md).

**e-process** — Anytime-valid sequential test (Howard-Ramdas-McAuliffe-Sekhon 2021). Ville-bounded rejection: reject when e-value crosses `1/α`, no Bonferroni correction. Pattern: [`70-E-PROCESSES`](../patterns/70-E-PROCESSES.md). [Q-050].

**EquivalenceExpectation** — Enum: `ExactRowMatch | MultisetEquivalence | SetEquivalence | TypeCoercionEquivalent | FloatingPointPrecision[ULP=N] | PyTreeStructure`. Declared by the metamorphic transform itself; comparator strictness scales with the transform's guarantee.

**FailureBundle v1.0.0** — Schema-versioned bundle written on every E2E failure. Required fields: `failure_type, seed, fixture_id, schedule_fingerprint, repro_command, artifact_sha256, ..., first_divergence_jsonptr`. Pattern: [`90-FAILURE-BUNDLE`](../patterns/90-FAILURE-BUNDLE.md). [Q-043, Q-100].

**FeatureUniverse** — `Feature { id: F-{CAT}-{SEQ}, title, weight, status: Passing|Partial|Missing|Excluded, exclusion_rationale }` enumeration. Loader enforces `sum(weights) == 1.0 per category`. Pattern: [`105-FEATURE-UNIVERSE`](../patterns/105-FEATURE-UNIVERSE.md). [Q-070].

**first-divergence jsonptr** — `/failure/first_divergence` jsonptr in every FailureBundle pointing at the byte-offset where engines first disagreed. UX win that compounds with every CI failure. [Q-100].

**FixtureRootContract** — Pinned `{manifest_sha256, fixture_directory, cardinality_floors, ...}`. Makes fixture selection part of the evidence. Pattern: [`25-FIXTURE-ROOT-CONTRACT`](../patterns/25-FIXTURE-ROOT-CONTRACT.md).

**focused gate** — A targeted-workload gate (e.g., "10K DELETE keep gate"). Contrasts with **broad gate**.

**fresh-eyes pass** — Full re-review of recent code by an agent who didn't write it. Phase 14 runs three calibrated fresh-eyes prompts (a, b, c). [Q-011].

**HotPathProfileSnapshot** — Per-project-class struct holding the inner-loop counters that any kept perf win must cite. Per-class table in [`pattern:145-HOT-PATH-COUNTERS`](../patterns/145-HOT-PATH-COUNTERS.md).

**keep gate** — Numeric threshold an optimization must clear to be merged. Singular = `comprehensive-bench` primary score. Plural is named (focused / broad / MT8 / etc.). [Q-005].

**micro-lever trap** — Pursuing sub-`0.1%` self-time hotspots below `cv_pct` noise floor. Anti-pattern. [Q-013].

**MismatchClassification** — Enum: `TrueDivergence | OrderDependentDifference | TypeAffinityDifference | NullHandlingDifference | FloatingPointDifference | FalsePositive`. CI fails only on `TrueDivergence`.

**MismatchSignature** — Truncated SHA-256 of `(sig-v1:classification:subsystem:schema:workload)`. Dedup key: two failures with same signature = same root-cause bug. Pattern: [`45-MISMATCH-MINIMIZER`](../patterns/45-MISMATCH-MINIMIZER.md).

**MT8** — 8-thread multi-writer benchmark. Canonical concurrency-stress workload. Every kept perf win cites an MT8 frame ≥0.1% self-time. [Q-012, Q-034].

**NormalizedValue** — Per-class canonical-string rendering type for the comparator. SQL: `{Null, Integer, Real, Text, Blob}`. RESP: `RespValue` with 14 RESP3 variants. ML: `TensorSpec`. Pattern: [`35-NORMALIZED-VALUE`](../patterns/35-NORMALIZED-VALUE.md).

**oracle preflight doctor** — Green/yellow/red precondition gate before every parity/certification lane. Verifies reference binary path, version, identity strings, fixture corpus sanity, manifest hash. Pattern: [`20-ORACLE-PREFLIGHT-DOCTOR`](../patterns/20-ORACLE-PREFLIGHT-DOCTOR.md).

**pass-over-pass gate** — `.bench-history/<bench>.latest.json` committed to git; the gate's input. Thresholds: primary `-3%`, geomean `-5%`, per-category `-10%`, p90 `-15%`, throughput `-5%`. Pattern: [`155-BENCH-HISTORY-RATCHET`](../patterns/155-BENCH-HISTORY-RATCHET.md).

**ProofObligation** — `{kind: OracleDifferential | MetamorphicProperty | ProptestInvariant | CrashBoundary | EProcess | FuzzNonPanic | InstaSnapshot, evidence_ref: ArtifactRef, status}`. Pattern: [`110-INVARIANT-CATALOG`](../patterns/110-INVARIANT-CATALOG.md).

**pulled the pin** — Status marker: discarded a previously-committed-then-reverted candidate. [Q-014].

**ratchet state** — `<workspace>/reports/ratchet_state.json`. Monotonically-updated record of per-pillar lower bounds. Pattern: [`75-BAYESIAN-CONFORMAL-SCORE`](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md) + [`subagents/ratchet-curator.md`](../../subagents/ratchet-curator.md).

**rch offload heuristic** — Anything `>5 min` wall-time → `rch exec --`. Pattern: [`255-RCH-OFFLOAD-DISCIPLINE`](../patterns/255-RCH-OFFLOAD-DISCIPLINE.md).

**release-perf profile** — Cargo profile inherits release with `opt-level=3, lto="thin", codegen-units=1, debug="line-tables-only", strip=false, RUSTFLAGS="-C force-frame-pointers=yes"`. Never `--release` for perf claims. [Q-032].

**retry-condition predicate** — Load-bearing field on every negative-ledger entry. One of 8 verbatim forms; never "later" / "if it seems important" / "we should revisit" / "tracked elsewhere". Pattern: [`185-RETRY-CONDITION-PREDICATE`](../patterns/185-RETRY-CONDITION-PREDICATE.md).

**run identity stack** — `{run_id, trace_id, scenario_id, seed, commit_sha, fixture_hash, backend, placement_profile, artifact_path, artifact_hash, replay_command}`. Joinable across logs/JSON/scorecards/bundles/beads/commits/ledger. Pattern: [`195-RUN-IDENTITY-STACK`](../patterns/195-RUN-IDENTITY-STACK.md).

**SCHEMA_VERSION** — Per-emitted-artifact version string (e.g., `fsqlite-e2e.comprehensive-bench-report.v3`, `failure_bundle.v1.0.0`). K-10. When schema changes, version bumps; downstream readers upgrade or fail loudly.

**SeedContract** — `derive_entry_seed(corpus_entry_id) -> u64`. Deterministic; never `rand::random()`; never `thread_rng()`. [Q-044].

**selections= byte-identical** — Behavior-preservation proof: the bench harness exposes per-scenario selection counters; a change that preserves selection counts to the byte is verified non-behavior-affecting. [Q-016].

**Ssi** — Serializable Snapshot Isolation (Cahill-Röhm-Fekete VLDB 2008). FrankenSQLite MVCC plane uses this.

**three-tier equivalence** — Tier 1 raw SHA-256 byte / Tier 2 canonical (after normalization) / Tier 3 logical (deterministic dump). Pattern: [`50-THREE-TIER-EQUIVALENCE`](../patterns/50-THREE-TIER-EQUIVALENCE.md). [Q-042].

**TransformFamily** — Enum: `Predicate | Projection | Structural | Literal`. Metamorphic transform classification. Pattern: [`40-METAMORPHIC-TRANSFORMS`](../patterns/40-METAMORPHIC-TRANSFORMS.md).

**truncate_score** — `f64 → f64` truncating to 6 decimal places. x86/ARM/WASM differ at LSB; truncation = bytewise reproducibility. K-5. [Q-053].

**Ville's inequality** — `P_{H_0}(∃t: E_t ≥ 1/α) ≤ α`. Allows anytime-valid rejection without Bonferroni. Foundation of e-processes. [Q-050].

**within noise** — Improvement is `≤` the workload's `cv_pct` band (typically `±3-5%`). Not a win — technically also not a loss, but not durable evidence. [Q-010].

---

Cross-link any new term: add an entry here + cross-link to the full treatment.
