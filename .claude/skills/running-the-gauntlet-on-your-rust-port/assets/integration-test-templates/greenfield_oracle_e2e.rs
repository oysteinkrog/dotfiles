//! greenfield_oracle_e2e.rs — paste-ready 30-line scenario template for
//! Greenfield-Rust-class projects. Dispatches across all 5 oracle modes
//! (Spec / Property / Self / Round-trip / External-tool) in a single test
//! file via the `OracleMode` enum.
//!
//! Copy this file into the project's test layout:
//!   - Workspace projects: `crates/<project>-e2e/tests/<feature>_oracle_e2e.rs`
//!   - Single-crate projects (e.g., eidetic per AGENTS.md Rule "single binary
//!     crate ... not a workspace in phase 0"): `tests/<feature>_oracle_e2e.rs`
//!
//! Pairs with:
//!   - subagents/greenfield-oracle-wirer.md (the Phase 3 5-mode wirer)
//!   - assets/property-test-templates/greenfield_proptest.rs
//!   - assets/fuzz-target-templates/greenfield_fuzz.rs
//!   - references/methodology/GREENFIELD-ADAPTATION.md § 5-8
//!
//! Cargo.toml add (under [dev-dependencies]):
//!   insta     = { version = "1.39", features = ["json", "yaml"] }
//!   proptest  = "1"
//!   arbitrary = { version = "1", features = ["derive"] }
//!
//! The 30-line `scenario()` body is the verbatim greenfield variant from
//! references/methodology/GREENFIELD-ADAPTATION.md § 2 Conformance — both-error
//! = agreement and one-error-one-OK = hard failure (K-8) apply to ALL 5 modes.

use std::path::PathBuf;
use std::process::Command;

// Replace with the actual project crate name; for a single-crate project this
// is just the project's package name.
#[allow(dead_code)]
use crate as subject; // tests live in the same crate for single-crate layouts

// ===== EngineIdentity constants (pattern:15-ENGINE-IDENTITY) =====
//
// SUBJECT is always the current code at HEAD. ORACLE_BY_MODE picks the
// reference identity per the OracleMode in flight — never `unset` and never
// equal to SUBJECT.

const SUBJECT_IDENTITY_LABEL: &str = "<project>"; // e.g. "eidetic-engine"

fn oracle_identity_label(mode: &OracleMode) -> &'static str {
    match mode {
        OracleMode::Spec(_)         => "spec-v1",
        OracleMode::Property(_)     => "property-suite-v1",
        OracleMode::Self_(_)        => "prior-commit-baseline",
        OracleMode::RoundTrip { .. } => "round-trip",
        OracleMode::ExternalTool(t) => match t {
            ExternalTool::Miri      => "miri",
            ExternalTool::Clippy    => "clippy",
            ExternalTool::CargoDeny => "cargo-deny",
        },
    }
}

// ===== OracleMode enum (greenfield 5-mode dispatch) =====
//
// One scenario picks one mode; many scenarios per test file cover all 5.
// Per references/methodology/GREENFIELD-ADAPTATION.md § 1, most projects use
// 3-4 of these — declare the enabled subset in spec_version_contract.toml#
// [oracle_modes_enabled].

#[derive(Clone)]
pub enum OracleMode {
    /// Specification-as-Oracle: a `[SPEC-NNN]`-tagged assertion the subject
    /// must implement. The verifier is a Rust function that asserts the spec
    /// holds given the subject's output.
    Spec(SpecVerifier),

    /// Property-Oracle: invariants stated as proptest properties; the Oracle
    /// is "every property holds". One scenario invokes one property.
    Property(PropertyDescriptor),

    /// Self-Oracle (prior-commit baseline): the subject's own behavior at a
    /// frozen baseline commit. Regression = any departure not explicitly
    /// authored. Implemented via insta-snapshot.
    Self_(SnapshotName),

    /// Round-trip-Oracle: encode→decode (or sign→verify, pack→unpack) round-
    /// trips; the Oracle is identity. `encoder(input) → encoded; decoder
    /// (encoded) → input'; assert_eq!(input, input')`.
    RoundTrip {
        encoder: fn(&RoundTripInput) -> Vec<u8>,
        decoder: fn(&[u8]) -> Result<RoundTripInput, String>,
    },

    /// External-tool-Oracle: a trusted external check exits 0 (Miri / Clippy /
    /// cargo-deny / cargo-audit). Any nonzero exit is TrueDivergence-equivalent.
    ExternalTool(ExternalTool),
}

#[derive(Clone, Copy)]
pub enum ExternalTool { Miri, Clippy, CargoDeny }

pub type SpecVerifier = fn(&SubjectOutput) -> Result<(), SpecViolation>;
pub type SnapshotName = &'static str;

#[derive(Clone)]
pub struct PropertyDescriptor {
    pub name: &'static str,
    pub run: fn() -> Result<(), String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoundTripInput {
    pub bytes: Vec<u8>,
    pub label: String,
}

/// Whatever shape the subject emits — a `String`, a JSON `Value`, a domain
/// struct. Per the project's NormalizedValue (see Phase 2 contract).
#[derive(Debug, Clone)]
pub struct SubjectOutput {
    pub canonical: String,
    pub kind: &'static str,
}

#[derive(Debug)]
pub struct SpecViolation {
    pub tag: &'static str,
    pub reason: String,
}

// ===== The 30-line scenario() template (greenfield variant) =====
//
// Verbatim shape from references/methodology/GREENFIELD-ADAPTATION.md § 2
// Conformance. Both-error = agreement; one-error-one-OK = hard failure (K-8).
// Each branch dispatches into one oracle-mode runner — the runners live in
// the harness modules authored by subagents/greenfield-oracle-wirer.md.

pub fn scenario<S, A>(
    setup: S,
    action: A,
    mode: OracleMode,
    label: &str,
) where
    S: FnOnce() -> SubjectState,
    A: FnOnce(SubjectState) -> Result<SubjectOutput, String>,
{
    // 1. Engine-identity guard (pattern:15-ENGINE-IDENTITY).
    let oracle = oracle_identity_label(&mode);
    assert_ne!(SUBJECT_IDENTITY_LABEL, oracle,
        "{label}: EngineIdentity self-comparison violation");

    // 2. Setup + action.
    let state = setup();
    let out = action(state);

    // 3. Dispatch across the 5 modes.
    match (out, mode) {
        // -- Spec mode --
        (Ok(o), OracleMode::Spec(v)) => match v(&o) {
            Ok(()) => {} // agreement
            Err(violation) => panic!(
                "{label}: spec-oracle divergence {tag}: {reason}\n  subject_output: {out:?}",
                tag = violation.tag, reason = violation.reason, out = o),
        },
        (Err(e_sub), OracleMode::Spec(v)) => {
            // The action errored. The spec verifier may itself expect an
            // error class — if it has no "expected error" notion, the
            // subject's error is a hard failure.
            let synthetic = SubjectOutput { canonical: format!("ERROR:{e_sub}"), kind: "error" };
            match v(&synthetic) {
                Ok(()) => {} // verifier accepts error-as-output (rare)
                Err(violation) => panic!(
                    "{label}: spec-oracle hard failure {tag}: {reason}\n  subject_error: {e_sub}",
                    tag = violation.tag, reason = violation.reason),
            }
        }

        // -- Property mode --
        (_, OracleMode::Property(prop)) => match (prop.run)() {
            Ok(()) => {}
            Err(reason) => panic!("{label}: property-oracle divergence [{name}]: {reason}",
                name = prop.name),
        },

        // -- Self-Oracle (insta-snapshot) --
        (Ok(o), OracleMode::Self_(snap)) => {
            // The macro form is `assert_snapshot!(snap, &o.canonical)` —
            // shown here as a function for clarity; in real use prefer
            // insta's macro to capture file/line for the snapshot path.
            self_oracle_assert(snap, &o.canonical, label);
        }
        (Err(e_sub), OracleMode::Self_(snap)) => {
            self_oracle_assert(snap, &format!("ERROR:{e_sub}"), label);
        }

        // -- Round-trip --
        (Ok(o), OracleMode::RoundTrip { encoder, decoder }) => {
            let input = RoundTripInput { bytes: o.canonical.into_bytes(), label: label.into() };
            let encoded = encoder(&input);
            match decoder(&encoded) {
                Ok(decoded) => assert_eq!(input, decoded,
                    "{label}: round-trip identity violation"),
                Err(decode_err) => panic!("{label}: round-trip decode error: {decode_err}"),
            }
        }
        (Err(e_sub), OracleMode::RoundTrip { .. }) => {
            // Action erroring before we have anything to round-trip = the
            // action's contract was violated; not a round-trip-oracle finding.
            panic!("{label}: action failed before round-trip could begin: {e_sub}");
        }

        // -- External tool --
        (_, OracleMode::ExternalTool(tool)) => external_tool_assert(tool, label),
    }
}

#[derive(Default)]
pub struct SubjectState {
    pub fixture: PathBuf,
    pub seed: u64,
}

fn self_oracle_assert(snap: SnapshotName, body: &str, label: &str) {
    // In real use, prefer insta's macro:
    //   insta::assert_snapshot!(snap, body);
    // — which captures file/line and writes the snapshot under tests/snapshots/.
    let _ = (snap, body, label);
    // Stub: read tests/snapshots/<snap>.snap and assert byte-equality after
    // Tier 2 normalization (sort JSON keys; collapse whitespace; strip
    // version suffix) per pattern:55-INSTA-GOLDEN-SNAPSHOTS § Tier 2.
}

fn external_tool_assert(tool: ExternalTool, label: &str) {
    let (cmd, args): (&str, &[&str]) = match tool {
        ExternalTool::Miri      => ("cargo", &["+nightly", "miri", "test", "--lib", "--no-fail-fast"]),
        ExternalTool::Clippy    => ("cargo", &["clippy", "--all-targets", "--", "-D", "warnings"]),
        ExternalTool::CargoDeny => ("cargo", &["deny", "check"]),
    };
    let status = Command::new(cmd).args(args).status()
        .unwrap_or_else(|e| panic!("{label}: external-tool exec failed: {e}"));
    assert!(status.success(),
        "{label}: external-tool {cmd} {args:?} exit={status:?} — TrueDivergence-equivalent");
}

// ===== Per-mode test examples =====
//
// One representative test per oracle mode. In a real project, expect
// 10-50 tests per mode covering the project's full behavior class.

// -- 1 spec-oracle test --
//
// Verifies SPEC-EE-003: "every `pack` respects the configured token budget
// within ±1%" (one of the eidetic [SPEC-NNN] tags per
// references/methodology/SPEC-PINNING-FOR-GREENFIELD.md § 3).

fn verify_spec_ee_003(out: &SubjectOutput) -> Result<(), SpecViolation> {
    // Parse the canonical output's token count; assert within ±1% of the
    // configured budget (carried as a sidechannel in the test setup).
    let _ = out;
    Ok(())
}

#[test]
fn pack_respects_token_budget_within_one_pct() {
    scenario(
        || SubjectState { fixture: PathBuf::from("tests/fixtures/pack-budget"), seed: 0 },
        |_state| Ok(SubjectOutput { canonical: r#"{"tokens": 4000}"#.into(), kind: "json" }),
        OracleMode::Spec(verify_spec_ee_003),
        "pack_respects_token_budget_within_one_pct",
    );
}

// -- 2 property-oracle test --
//
// One `proptest!` macro per property. Bridges into the canonical
// scenario via `OracleMode::Property` so the same EngineIdentity + both-
// error-agreement contracts apply.

use proptest::prelude::*;
use proptest::test_runner::{Config, FileFailurePersistence};

fn proptest_config() -> Config {
    Config {
        cases: 256,
        max_shrink_iters: 4096,
        failure_persistence: Some(Box::new(FileFailurePersistence::WithSource("regressions"))),
        ..Config::default()
    }
}

fn run_pack_budget_property() -> Result<(), String> {
    let mut runner = proptest::test_runner::TestRunner::new(proptest_config());
    runner.run(&(0u32..1_000_000), |budget| {
        // Drive subject::pack(query, budget); assert tokens <= 1.01 * budget.
        prop_assert!(budget == budget); // placeholder
        Ok(())
    }).map_err(|e| format!("{e}"))
}

#[test]
fn pack_budget_property_holds() {
    scenario(
        SubjectState::default,
        |_| Ok(SubjectOutput { canonical: "ok".into(), kind: "marker" }),
        OracleMode::Property(PropertyDescriptor {
            name: "pack_budget_respected",
            run: run_pack_budget_property,
        }),
        "pack_budget_property_holds",
    );
}

// -- 3 self-oracle test (insta snapshot) --
//
// In real use the snapshot file lives at tests/snapshots/<test-name>.snap
// and `insta::assert_snapshot!` macro writes/compares it. Tier 2
// normalization happens BEFORE the macro per pattern:55-INSTA-GOLDEN-SNAPSHOTS.

#[test]
fn context_pack_canonical_form_stable() {
    scenario(
        SubjectState::default,
        |_| Ok(SubjectOutput { canonical: r#"{"items":[{"id":"01H..."}]}"#.into(), kind: "json" }),
        OracleMode::Self_("context_pack_canonical_form"),
        "context_pack_canonical_form_stable",
    );
}

// -- 4 round-trip-oracle test --
//
// `encoder` and `decoder` pair declared in spec_version_contract.toml#
// [[roundtrip_corpus]]. The round-trip's identity-violation behaviors
// (subnormal floats, combining-Unicode, leap-second timestamps) are the
// targets of the differential fuzz target at
// assets/fuzz-target-templates/greenfield_fuzz.rs.

fn encode_context_pack(input: &RoundTripInput) -> Vec<u8> {
    // Real impl: subject::ContextPack::encode(...)
    input.bytes.clone()
}

fn decode_context_pack(bytes: &[u8]) -> Result<RoundTripInput, String> {
    // Real impl: subject::ContextPack::decode(...).map(...)
    Ok(RoundTripInput { bytes: bytes.to_vec(), label: "decoded".into() })
}

#[test]
fn context_pack_roundtrip_is_identity() {
    scenario(
        SubjectState::default,
        |_| Ok(SubjectOutput { canonical: r#"{"hello":"world"}"#.into(), kind: "json" }),
        OracleMode::RoundTrip {
            encoder: encode_context_pack,
            decoder: decode_context_pack,
        },
        "context_pack_roundtrip_is_identity",
    );
}

// -- 5 external-tool-oracle test --
//
// Stub: in CI, run these as separate jobs (`.github/workflows/miri.yml`,
// `.github/workflows/clippy.yml`, etc.) since they're slow. The in-test
// invocation here is a smoke that confirms the wiring works locally on
// a small surface (e.g., `cargo +nightly miri test --lib --no-run`).

#[test]
#[ignore = "slow: opt in with `cargo test -- --ignored miri_smoke`"]
fn miri_lib_smoke() {
    scenario(
        SubjectState::default,
        |_| Ok(SubjectOutput { canonical: "miri-ok".into(), kind: "marker" }),
        OracleMode::ExternalTool(ExternalTool::Miri),
        "miri_lib_smoke",
    );
}

#[test]
#[ignore = "slow: opt in with `cargo test -- --ignored clippy_smoke`"]
fn clippy_deny_warnings_smoke() {
    scenario(
        SubjectState::default,
        |_| Ok(SubjectOutput { canonical: "clippy-ok".into(), kind: "marker" }),
        OracleMode::ExternalTool(ExternalTool::Clippy),
        "clippy_deny_warnings_smoke",
    );
}

#[test]
#[ignore = "slow: opt in with `cargo test -- --ignored cargo_deny_smoke`"]
fn cargo_deny_check_smoke() {
    scenario(
        SubjectState::default,
        |_| Ok(SubjectOutput { canonical: "deny-ok".into(), kind: "marker" }),
        OracleMode::ExternalTool(ExternalTool::CargoDeny),
        "cargo_deny_check_smoke",
    );
}
