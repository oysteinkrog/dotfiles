# Pattern 06 — 5-MODE ORACLE DISPATCH

**Family:** Kernel — Greenfield-Rust-class extension to [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md). Pairs with the `△ REVIEW-SCORE` and `⊕ MULTIPLEX-ORACLE` operators in [`../methodology/OPERATORS.md`](../methodology/OPERATORS.md).

**When to apply:** Any project routed to `gauntlet-greenfield` mode (see [`../methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md)) where there is no single upstream reference. The Oracle is *constructed* from one or more of: Spec-as-Oracle, Property-Oracle, Self-Oracle, Round-trip-Oracle, External-tool-Oracle. The dispatcher routes a given test scenario to the right Oracle mode (or composes several) and returns a unified verdict.

## What

A typed Rust enum + dispatch function that lets every greenfield test scenario name *which* Oracle mode it expects to be evaluated under, and lets the harness route the Subject's output to the right Oracle adapter. The same `OracleMode` enum value participates in the [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — it lands in `EngineVersions.reference_identity` as one of `"spec-vN"`, `"property-suite-vN"`, `"prior-commit-<sha>"`, `"round-trip"`, `"external-tool-<name>"`. This is what makes the K-9 (engine identity) discriminator work in greenfield mode: a scenario authored against `OracleMode::Spec` cannot silently get evaluated against `OracleMode::SelfPriorCommit` and call it agreement.

The dispatcher also enforces the K-1 triple at type-system level: an `OracleMode` cannot be constructed without naming its Subject, Oracle, and Comparator concretely (each mode has its own adapter struct, each adapter is a `dyn OracleAdapter`).

## Why

> "The five oracle modes can be MIXED in one project — most projects use 3-4 of them." — [`GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) §1.

Failure mode prevented: *Oracle-mode drift*. Without an explicit `OracleMode` enum, scenarios slowly migrate to whichever Oracle is cheapest — usually Self-Oracle (compare to last commit), which is the weakest. A year in, the project has 500 scenarios that all verify "today's output matches yesterday's output" and zero scenarios that verify "today's output matches the spec." Tags + dispatcher + per-mode coverage report make this invisible-drift visible and ratchet-able (every release must increase or hold each mode's coverage; see [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) for the ratchet shape applied per-mode).

The second failure mode prevented: *false-agreement on weak oracles*. A Round-trip Oracle that says "encode→decode is identity" tells you nothing about whether the encoder respects the spec — only that decode inverts encode. Without the mode being explicit in the envelope, the gauntlet's parity score lumps round-trip passes in with spec passes and overstates conformance. The mode-tag makes the per-mode parity score reportable separately, and the keep-gate enforces a *floor* on the spec-mode score.

## The pattern

### The `OracleMode` enum + adapter trait

```rust
//! crates/<port>-harness/src/oracle_dispatch.rs

use serde::{Deserialize, Serialize};

/// Names which Oracle authored the expectation for a given scenario.
///
/// Lands verbatim in `EngineVersions.reference_identity` of the
/// [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) so the
/// content-addressed envelope's hash distinguishes "same subject result evaluated
/// under a different Oracle mode" — those are *different* tests, not duplicates.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub enum OracleMode {
    /// The Oracle is one or more spec assertions, each tagged `[SPEC-NNN]` per
    /// [pattern:11-SPEC-TAG-EXTRACTION](11-SPEC-TAG-EXTRACTION.md).
    Spec {
        version: String,                 // e.g., "spec-v3"
        contract_sha256: String,         // sha of the spec source the tags came from
        tags: Vec<String>,               // e.g., ["SPEC-EE-001", "SPEC-EE-002"]
    },
    /// The Oracle is a checked-in property suite under `tests/properties/`.
    Property {
        suite_version: String,           // e.g., "property-suite-v2"
        property_id: String,             // e.g., "prop_pack_token_budget_respected"
        regression_seeds: Vec<String>,   // checked-in seeds; see [pattern:56-PROPTEST-REGRESSION-DISCIPLINE]
    },
    /// The Oracle is the Subject's own behavior at a blessed prior commit.
    SelfPriorCommit {
        commit_sha: String,              // git SHA the golden was captured from
        golden_path: String,             // path under tests/golden/ or tests/snapshots/
        bless_reason_md: String,         // path to the rationale doc for the most recent re-bless
    },
    /// The Oracle is round-trip identity: encode→decode (or sign→verify).
    Roundtrip {
        corpus_name: String,             // e.g., "context_pack_v1"
        encoder_fn: String,              // fully-qualified Rust path
        decoder_fn: String,
    },
    /// The Oracle is a trusted external tool: Miri / Clippy / cargo-deny / etc.
    ExternalTool {
        tool: ExternalTool,
        toolchain: String,               // e.g., "nightly-2026-05-01"
        config_sha256: String,           // sha of MIRIFLAGS / clippy.toml / deny.toml
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ExternalTool {
    Miri,
    Clippy { lint_group: String },
    CargoDeny,
    CargoAudit,
    Asan,
    Tsan,
    /// Project-specific tool; e.g., a custom UB checker.
    Custom(String),
}

/// Every Oracle mode implements this trait. The harness owns one boxed adapter
/// per active mode and dispatches a scenario to the right one.
pub trait OracleAdapter: Send + Sync {
    /// Returns the reference_identity string that lands in the envelope.
    fn reference_identity(&self) -> String;

    /// Evaluate `subject_output` against this Oracle. Returns Ok(()) on agreement,
    /// Err(OracleDivergence) on disagreement (with a structured signature so
    /// [pattern:45-MISMATCH-MINIMIZER](45-MISMATCH-MINIMIZER.md) can dedup).
    fn evaluate(&self, scenario_id: &str, subject_output: &SubjectOutput)
        -> Result<(), OracleDivergence>;

    /// Self-check for preflight per [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md).
    /// Returns Green/Yellow/Red.
    fn preflight(&self) -> PreflightStatus;
}
```

### The dispatcher

```rust
pub struct OracleDispatcher {
    adapters: Vec<Box<dyn OracleAdapter>>,
}

impl OracleDispatcher {
    pub fn evaluate(&self, scenario: &Scenario, subject_output: &SubjectOutput)
        -> ScenarioVerdict
    {
        // Look up which Oracle modes the scenario declared.
        let matching: Vec<&dyn OracleAdapter> = self.adapters.iter()
            .filter(|a| scenario.expected_oracle_modes.iter()
                .any(|m| oracle_mode_matches_adapter(m, a.as_ref())))
            .map(|b| b.as_ref())
            .collect();

        if matching.is_empty() {
            // K-9 failure: scenario named no oracle. This is a HARD ERROR — refuse
            // to silently fall back to SelfPriorCommit.
            return ScenarioVerdict::OracleMissing {
                scenario_id: scenario.id.clone(),
                declared_modes: scenario.expected_oracle_modes.clone(),
            };
        }

        let mut per_mode_results = Vec::with_capacity(matching.len());
        for adapter in matching {
            let res = adapter.evaluate(&scenario.id, subject_output);
            per_mode_results.push((adapter.reference_identity(), res));
        }

        // Composite verdict: ALL modes must pass. Disagreement across modes
        // (Spec says OK, Property finds a counterexample) is itself a hard
        // finding — surface it, don't average it.
        if per_mode_results.iter().all(|(_, r)| r.is_ok()) {
            ScenarioVerdict::Agreement
        } else {
            ScenarioVerdict::Divergence { per_mode_results }
        }
    }
}

pub enum ScenarioVerdict {
    Agreement,
    Divergence { per_mode_results: Vec<(String, Result<(), OracleDivergence>)> },
    OracleMissing { scenario_id: String, declared_modes: Vec<OracleMode> },
}
```

### How a scenario declares its expected oracle modes

```rust
//! tests/spec_ee_remember_oracle_e2e.rs

#[test]
fn remember_collision_rate_under_property_and_spec() {
    let scenario = Scenario {
        id: "ee_remember_collision_under_load".into(),
        expected_oracle_modes: vec![
            OracleMode::Spec {
                version: "spec-v3".into(),
                contract_sha256: SPEC_SHA.into(),
                tags: vec!["SPEC-EE-001".into()],
            },
            OracleMode::Property {
                suite_version: "property-suite-v2".into(),
                property_id: "prop_remember_collision_bound".into(),
                regression_seeds: vec!["d3f5...".into()],
            },
        ],
        setup: |state| { /* ... */ },
        action: |state| { /* run subject's `remember` 1M times */ },
    };

    let dispatcher = OracleDispatcher::new_from_workspace_config();
    let subject_output = run_scenario(&scenario);
    let verdict = dispatcher.evaluate(&scenario, &subject_output);
    assert!(matches!(verdict, ScenarioVerdict::Agreement), "verdict: {verdict:?}");
}
```

## Variants per project class

| Class | Typical mode mix | Why |
|---|---|---|
| **SQL-class** | `Spec` + `SelfPriorCommit` + `ExternalTool(Miri)` | Spec from SQL standard; insta snapshots for plans; Miri on the harness crate |
| **RESP-class** | `Spec` + `Roundtrip` + `ExternalTool(Miri)` | Spec from RESP3 doc; round-trip on every RESP3 type; Miri on the parser |
| **Numerical-Python** | `Spec` (NumPy docs) + `Property` (per-op ULP) + `Roundtrip` (serialization) | ULP properties carry most of the load |
| **ML-System** | `Spec` (PyTorch ops docs) + `Property` (autograd vs JVP) + `ExternalTool(Asan)` | Property oracle (gradient symmetry) is irreplaceable |
| **HTTP-Protocol** | `Spec` (RFC + OpenAPI) + `Property` (request-response invariants) + `SelfPriorCommit` (OpenAPI schema diff) | OpenAPI is itself a spec source |
| **Greenfield-Rust** | All 5 typically active; `Spec` is required (release-blocker) | Mode-mix is the project's parity claim |

### Per-class adapter implementations

Each class registers its adapters at workspace init:

```rust
fn build_dispatcher_for_class(class: ProjectClass) -> OracleDispatcher {
    let mut adapters: Vec<Box<dyn OracleAdapter>> = Vec::new();

    // Spec adapter — required for all classes.
    adapters.push(Box::new(SpecOracleAdapter::load_from(
        "docs/contracts/spec_version_contract.toml")?));

    match class {
        ProjectClass::Sql => {
            adapters.push(Box::new(InstaSnapshotAdapter::default()));
            adapters.push(Box::new(MiriAdapter::new("nightly-2026-05-01")));
        }
        ProjectClass::Resp => {
            adapters.push(Box::new(RoundtripAdapter::for_corpus("resp3_frames")));
            adapters.push(Box::new(MiriAdapter::new("nightly-2026-05-01")));
        }
        ProjectClass::Numerical => {
            adapters.push(Box::new(PropertyAdapter::for_suite("numpy_ufunc_ulp")));
            adapters.push(Box::new(RoundtripAdapter::for_corpus("npy_serialize")));
        }
        ProjectClass::Ml => {
            adapters.push(Box::new(PropertyAdapter::for_suite("autograd_vs_jvp")));
            adapters.push(Box::new(AsanAdapter::default()));
        }
        ProjectClass::Http => {
            adapters.push(Box::new(PropertyAdapter::for_suite("http_invariants")));
            adapters.push(Box::new(InstaSnapshotAdapter::for_dir("tests/openapi-snapshots/")));
        }
        ProjectClass::Greenfield => {
            // All five modes; each adapter loaded conditionally based on
            // [oracle_modes_enabled] in spec_version_contract.toml.
            adapters.extend(build_all_five_for_greenfield());
        }
    }

    OracleDispatcher { adapters }
}
```

## Per-mode parity score reporting

The dispatcher's verdicts are aggregated by Oracle mode for a *per-mode parity score*:

```
parity_score_per_mode.json
{
  "spec_v3":            { "passes": 142, "fails":  3, "lower_bound": 0.952 },
  "property_v2":        { "passes":  87, "fails":  0, "lower_bound": 0.989 },
  "self_prior_commit":  { "passes": 311, "fails":  2, "lower_bound": 0.987 },
  "roundtrip":          { "passes":  44, "fails":  0, "lower_bound": 0.979 },
  "external_miri":      { "passes":  18, "fails":  0, "lower_bound": 0.950 }
}
```

The keep-gate (see [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md)) enforces a floor on EACH mode's lower bound, not just the composite. This blocks the "we got the composite from 0.92 to 0.94 by adding 100 cheap round-trip tests" gaming.

## Failure modes

| Failure | Symptom | Detection | Fix |
|---|---|---|---|
| **Mode silently downgraded** | A scenario declared `OracleMode::Spec` but the harness fell back to `SelfPriorCommit` because the spec adapter was missing. | `ScenarioVerdict::OracleMissing` is treated as PASS instead of HARD ERROR. | Make `OracleMissing` a release-blocker; add `assert!(matches!(v, Agreement))` not `assert!(!matches!(v, Divergence))`. |
| **Mode-coverage drift** | Round-trip mode grows from 50 → 500 tests; spec mode stays at 12. | Per-mode parity score report; alarm if spec/property mode count regresses by >10% across release. | Per-mode floor in keep-gate; refuse to certify a release where spec coverage shrank. |
| **Two modes disagree, harness picks the lenient one** | Spec says "must error"; round-trip says "encoded value round-trips fine". Harness reports agreement because round-trip passed. | Audit `per_mode_results` field of `ScenarioVerdict::Divergence`. | Any disagreement across modes is a hard divergence; emit `MismatchSignature::CrossModeDisagreement`. |
| **Adapter constructed without preflight** | The Miri adapter is registered but Miri isn't installed; every scenario routed to it silently passes. | [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) integration check; preflight returns Red. | Refuse to enter Phase 6 (oracle-test-authoring) if any registered adapter returns Red on preflight. |
| **`reference_identity` collisions** | Two adapters return `"prior-commit-<sha>"` with the same SHA — content-addressed envelope can't tell them apart. | Hash-bucket the reference_identity strings; warn on collision. | Append adapter-name suffix: `"prior-commit-<sha>::self_oracle_main"` vs `"prior-commit-<sha>::release_v1_baseline"`. |
| **Scenario declared no modes** | Brand-new scenario file copy-pasted from template; `expected_oracle_modes: vec![]`. | `OracleMissing` verdict on first run; CI must fail. | Empty vec is a *compile-time* error if scenarios are derived from a builder; use `ScenarioBuilder::with_mode(...).build()`. |
| **Property mode without checked-in regressions** | Property fails in CI, shrinks a counterexample, never persists it; next CI run, different seed, can't reproduce. | See [pattern:56-PROPTEST-REGRESSION-DISCIPLINE](56-PROPTEST-REGRESSION-DISCIPLINE.md). | `proptest-regressions/*.txt` committed; CI checks it's tracked by git. |
| **External-tool mode hides UB behind a panic** | Miri reports UB; harness catches the panic and reports "agreement". | UB report should yield `OracleDivergence { signature: UbCategory(...) }`, not panic. | Adapter parses Miri's stderr structured-error JSON; treats *any* UB as divergence. |

## Cross-references

- [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md) — the kernel triple this is the greenfield specialization of.
- [pattern:11-SPEC-TAG-EXTRACTION](11-SPEC-TAG-EXTRACTION.md) — feeds `OracleMode::Spec.tags`.
- [pattern:12-SPEC-CONFLICT-DETECTION](12-SPEC-CONFLICT-DETECTION.md) — gates whether the Spec adapter can be constructed at all.
- [pattern:13-SINGLE-CRATE-VS-WORKSPACE-DECISION](13-SINGLE-CRATE-VS-WORKSPACE-DECISION.md) — affects where `oracle_dispatch.rs` lives.
- [pattern:15-ENGINE-IDENTITY](15-ENGINE-IDENTITY.md) — the discriminator the `reference_identity` field populates.
- [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) — every registered adapter must return Green/Yellow before Phase 6.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — where `OracleMode` lands in the envelope.
- [pattern:31-SCHEMA-VERSION-MIGRATION-DUAL-READER](31-SCHEMA-VERSION-MIGRATION-DUAL-READER.md) — applies when `OracleMode` itself gains a variant.
- [pattern:45-MISMATCH-MINIMIZER](45-MISMATCH-MINIMIZER.md) — `OracleDivergence` signatures feed the minimizer.
- [pattern:56-PROPTEST-REGRESSION-DISCIPLINE](56-PROPTEST-REGRESSION-DISCIPLINE.md) — required for `OracleMode::Property`.
- [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) — per-mode lower-bound rachet.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — `fail-missing-evidence` if a declared mode has no adapter.
- [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — per-mode floor enforcement.
- [`../methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md) — the 5-mode taxonomy.
- [`../methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) — pins the per-mode contract.
- [`../../subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md) — the Phase 3 subagent that constructs the dispatcher.
