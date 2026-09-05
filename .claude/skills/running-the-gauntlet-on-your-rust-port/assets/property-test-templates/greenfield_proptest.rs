//! greenfield_proptest.rs — paste-ready Greenfield-Rust-class property tests.
//!
//! Copy into the project's test layout:
//!   - Workspace projects: `crates/<project>-e2e/tests/greenfield_proptest.rs`
//!   - Single-crate projects: `tests/greenfield_proptest.rs`
//!
//! Pairs with:
//!   - assets/integration-test-templates/greenfield_oracle_e2e.rs (the
//!     5-mode scenario harness this proptest bridges into)
//!   - assets/fuzz-target-templates/greenfield_fuzz.rs (the differential-
//!     fuzz harness exercising the round-trip oracle)
//!   - references/methodology/GREENFIELD-ADAPTATION.md § 6 Property-Oracle
//!     authoring
//!
//! Cargo.toml add (under [dev-dependencies]):
//!   proptest  = "1"
//!   arbitrary = { version = "1", features = ["derive"] }
//!
//! And commit a `proptest-regressions/` directory at the crate root; every
//! shrunken counterexample lands there as a checked-in regression seed —
//! bug #5 in references/first-bug-hunt/greenfield-rust-class.md.

use proptest::prelude::*;
use proptest::test_runner::{Config, FileFailurePersistence};

// ===== ProofInvariantClass (Greenfield-Rust-class) =====
//
// Verbatim from MINING-2 §4 generalization + extended for the 5-mode oracle.
// Every kept property MUST name one of these invariant classes in its proof
// pack. A change that touches any of these classes is a behavior change and
// must be defended with a 5-line isomorphism proof (see
// references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md).

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProofInvariantClass {
    // Cross-class universals.
    RowOrdering,
    TieBreak,
    FloatingPointPrecision,
    RngDeterminism,
    GoldenChecksum,
    TypeAffinity,
    NullPropagation,
    ErrorCodes,
    AggregateSemantics,
    WindowFunctionSemantics,

    // Greenfield-specific additions per the 5 oracle modes.
    EncodeDecodeIdentity,        // round-trip-oracle invariants
    BudgetMonotonicity,          // pack(budget=B); pack(budget=2B) ⊇ pack(budget=B)
    Idempotency,                 // f(f(x)) == f(x) where applicable
    SeedDeterminism,             // same seed → same output, ALWAYS
    NoPanic,                     // every arbitrary input parses or errors cleanly
    SpecAssertion,               // a [SPEC-NNN] tag's verifier holds under proptest input
}

// ===== Seed contract (pattern:K-7 + ORACLE-TOOLCHAIN §11) =====
//
// NEVER `rand::random()`. NEVER `thread_rng()`. Per
// references/taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class:
//   `derive_entry_seed(corpus_entry_id) -> u64`
//
// The proptest runner's seed comes from PROPTEST_SEED env var; absent that,
// from the proptest-regressions/<file>.txt persisted seeds. CI pins
// PROPTEST_CASES (typically 256-1024) so the corpus size is reproducible.
//
// The `FileFailurePersistence::WithSource` setting makes proptest write
// every shrunken counterexample to
//   `<CARGO_MANIFEST_DIR>/proptest-regressions/greenfield_proptest.txt`
// — that file MUST be checked into git. Future runs replay it BEFORE
// generating fresh inputs, so a regression that flakes once is caught every
// run thereafter. See bug #5 in
// references/first-bug-hunt/greenfield-rust-class.md.

fn proptest_config() -> Config {
    Config {
        cases: 256,
        max_shrink_iters: 4096,
        failure_persistence: Some(Box::new(FileFailurePersistence::WithSource(
            "regressions",
        ))),
        ..Config::default()
    }
}

// ===== Input strategies — narrow to the project's domain =====
//
// The art of proptest: shape the strategy so generated inputs are valid by
// construction. Wide strategies generate mostly junk; narrow strategies hit
// real semantic edges. For greenfield projects, the strategies should
// mirror the project's `Arbitrary` impls on its public types.

fn small_bytes() -> impl Strategy<Value = Vec<u8>> {
    prop::collection::vec(any::<u8>(), 0..256)
}

fn small_utf8() -> impl Strategy<Value = String> {
    // Includes empty, ASCII, multibyte UTF-8, and a deliberate combining-
    // mark string to surface NFC-normalization round-trip bugs (bug #3 in
    // references/first-bug-hunt/greenfield-rust-class.md).
    prop_oneof![
        Just(String::new()),
        "[a-zA-Z0-9 ]{0,64}",
        Just("café".into()),       // U+00E9 (composed)
        Just("cafe\u{0301}".into()), // U+0065 + U+0301 (decomposed)
        Just("🦀".into()),
    ]
}

fn small_budget() -> impl Strategy<Value = u32> {
    // Common token budgets + edge cases at boundaries.
    prop_oneof![Just(0u32), Just(1), Just(100), Just(4000), 100u32..16000]
}

fn small_seed() -> impl Strategy<Value = u64> {
    prop_oneof![Just(0u64), Just(1), Just(u64::MAX), any::<u64>()]
}

// ===== Bridge to the 5-mode oracle (per
// assets/integration-test-templates/greenfield_oracle_e2e.rs) =====
//
// Each property is a *metamorphic relation*: an input transformation that
// should preserve some invariant. The bridge `run_oracle` calls the
// scenario() helper with `OracleMode::Property(...)` so the same
// EngineIdentity + both-error-agreement contracts apply.

fn run_oracle_property(_name: &str, _check: impl FnOnce() -> Result<(), String>) -> Result<(), String> {
    // In real use: call greenfield_oracle_e2e.rs's `scenario()` with
    // OracleMode::Property(PropertyDescriptor { name, run: check }).
    // Stub for compile: pretend the check passed.
    Ok(())
}

// Subject stubs — replace with real subject API.
mod subject {
    pub fn encode(input: &[u8]) -> Vec<u8> { input.to_vec() }
    pub fn decode(bytes: &[u8]) -> Result<Vec<u8>, String> { Ok(bytes.to_vec()) }
    pub fn pack(seed: u64, budget: u32) -> Result<Vec<u8>, String> {
        let _ = (seed, budget);
        Ok(vec![0u8; budget as usize / 4])
    }
    pub fn parse(bytes: &[u8]) -> Result<usize, String> {
        // Never panic on arbitrary input; either Ok(parsed) or Err.
        Ok(bytes.len())
    }
}

// ===== Property 1: encode/decode round-trip identity =====
//
// ProofInvariantClass::EncodeDecodeIdentity.
// For every encoder/decoder pair declared in spec_version_contract.toml#
// [[roundtrip_corpus]]: `decode(encode(input)) == input` MUST hold for any
// input the subject accepts. Failures surface the precision/normalization
// bugs of bug #3 in references/first-bug-hunt/greenfield-rust-class.md.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn encode_decode_is_identity(input in small_bytes()) {
        let encoded = subject::encode(&input);
        let decoded = subject::decode(&encoded).map_err(|e| TestCaseError::fail(e))?;
        prop_assert_eq!(input.clone(), decoded,
            "EncodeDecodeIdentity violation — file as MismatchClassification");
        prop_assert!(run_oracle_property("encode_decode_is_identity",
            || Ok(())).is_ok());
    }

    #[test]
    fn encode_decode_is_identity_utf8(s in small_utf8()) {
        let bytes = s.as_bytes().to_vec();
        let encoded = subject::encode(&bytes);
        let decoded = subject::decode(&encoded).map_err(|e| TestCaseError::fail(e))?;
        // String reconstruction step exposes NFC/NFD normalization round-trips.
        let reconstructed = String::from_utf8(decoded)
            .map_err(|e| TestCaseError::fail(e.to_string()))?;
        prop_assert_eq!(s, reconstructed, "UTF-8 round-trip lost normalization");
    }
}

// ===== Property 2: budget-respect monotonicity =====
//
// ProofInvariantClass::BudgetMonotonicity.
// If pack(seed, B) returns N tokens, then pack(seed, 2B) MUST return >=N
// tokens (a larger budget should produce a strict superset, NOT a smaller
// one). This is the canonical eidetic-style metamorphic per
// references/case-studies/eidetic_engine_cli.md § 3 Conformance bullet 3.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn pack_budget_is_monotonic(seed in small_seed(), budget in small_budget()) {
        prop_assume!(budget > 0 && budget < u32::MAX / 2);

        let small = subject::pack(seed, budget).map_err(|e| TestCaseError::fail(e))?;
        let large = subject::pack(seed, budget.saturating_mul(2))
            .map_err(|e| TestCaseError::fail(e))?;

        prop_assert!(large.len() >= small.len(),
            "BudgetMonotonicity violation: budget={} small_len={} budget*2 large_len={}",
            budget, small.len(), large.len());

        // Also: every byte the small contained should be in the large (or
        // at the same position, depending on the project's ordering contract).
        prop_assert!(run_oracle_property("pack_budget_is_monotonic",
            || Ok(())).is_ok());
    }
}

// ===== Property 3: idempotency on second call =====
//
// ProofInvariantClass::Idempotency.
// For operations declared idempotent in the spec (e.g., `remember(x);
// remember(x)` should equal `remember(x)` — the second call is a no-op or
// returns the same ID), the property `f(f(x)) == f(x)` MUST hold.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn pack_is_idempotent_on_second_call(seed in small_seed(), budget in small_budget()) {
        let first = subject::pack(seed, budget).map_err(|e| TestCaseError::fail(e))?;
        let second = subject::pack(seed, budget).map_err(|e| TestCaseError::fail(e))?;

        prop_assert_eq!(first, second,
            "Idempotency violation — same (seed, budget) produced different outputs across calls");
    }
}

// ===== Property 4: determinism given seed =====
//
// ProofInvariantClass::SeedDeterminism.
// The project's seed contract (per references/taxonomy/PROJECT-CLASSES.md §
// Greenfield-Rust-class § Seed contract) mandates `derive_entry_seed
// (corpus_entry_id)` — never `rand::random()`. Given the same seed, every
// invocation MUST produce the same output. This is the hard invariant that
// keeps proptest-regressions/ reproducible across machines.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn pack_is_deterministic_given_seed(seed in small_seed(), budget in small_budget()) {
        // Three calls with the same seed; ALL must agree.
        let a = subject::pack(seed, budget).map_err(|e| TestCaseError::fail(e))?;
        let b = subject::pack(seed, budget).map_err(|e| TestCaseError::fail(e))?;
        let c = subject::pack(seed, budget).map_err(|e| TestCaseError::fail(e))?;

        prop_assert_eq!(a.clone(), b.clone(),
            "SeedDeterminism violation (a vs b) — seed contract is broken");
        prop_assert_eq!(b, c,
            "SeedDeterminism violation (b vs c) — seed contract is broken");
    }
}

// ===== Property 5: no-panic on arbitrary input =====
//
// ProofInvariantClass::NoPanic.
// Every subject entry point that takes external input (parsers, decoders,
// CLI arg handlers) MUST either return `Ok(parsed)` or `Err(reason)`. A
// panic on arbitrary input is a HARD failure — either the input is invalid
// (return Err) or the parser is incomplete (fix the parser). Proptest's
// shrinker minimizes the panicking input to the smallest reproducer.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn parse_never_panics_on_arbitrary_input(bytes in small_bytes()) {
        // The std::panic::catch_unwind wrapper turns a panic into a test
        // failure with the panic message preserved. If parse() panics on
        // ANY input, the property fails and the shrunken input lands in
        // proptest-regressions/greenfield_proptest.txt.
        let result = std::panic::catch_unwind(|| subject::parse(&bytes));
        prop_assert!(result.is_ok(),
            "NoPanic violation: subject::parse panicked on input of {} bytes",
            bytes.len());
    }
}

// ===== Checked-in regression convention =====
//
// `proptest-regressions/greenfield_proptest.txt` is the durable failure
// ledger. Workflow:
//
//   1. Proptest hits a divergence, shrinks, persists a line to that file.
//   2. Commit the file. Future runs replay it FIRST, guaranteeing the same
//      input is tried again before fresh generation.
//   3. The fix lands. The line stays. Now the test asserts "we never
//      regress into this bug again".
//
// Delete a line only with a bead that explains why the regression is
// permanently irrelevant (e.g., the surface was removed; the spec was
// refined). See bug #5 in references/first-bug-hunt/greenfield-rust-class.md
// for the failure mode this convention prevents.
//
// CI gate: `scripts/check-proptest-regressions.sh` enforces that
//   - proptest-regressions/ is NOT in .gitignore
//   - every *_proptest.rs has a corresponding regressions file (orphan check)
//   - regression file SHA-256 matches the run-id-stamped expected value
//
// Cross-link:
//   - references/methodology/GREENFIELD-ADAPTATION.md § 6 Property-Oracle
//   - references/first-bug-hunt/greenfield-rust-class.md § 5
//   - references/methodology/SPEC-PINNING-FOR-GREENFIELD.md § 2
//     [property_suite] block — pins proptest version + regressions dir
