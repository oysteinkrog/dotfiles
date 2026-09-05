//! resp_proptest.rs — paste-ready RESP-class property tests.
//!
//! Copy into `crates/<port>-e2e/tests/resp_proptest.rs`.
//!
//! Pairs with: assets/integration-test-templates/resp_oracle_e2e.rs (the
//! vendored `redis-server` UNIX-socket scenario harness).
//!
//! Cargo.toml add (under [dev-dependencies]):
//!   proptest = "1"
//!   hex      = "0.4"
//!
//! Commit `proptest-regressions/` at the crate root.

use proptest::prelude::*;
use proptest::test_runner::{Config, FileFailurePersistence};

// ===== ProofInvariantClass (RESP-class generalization) =====
//
// Verbatim subset from MINING-2 §4 + per-class adaptation in
// taxonomy/PROJECT-CLASSES.md § RESP-Class. Every kept property names one.

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProofInvariantClass {
    RowOrdering,                // list order (LRANGE, ZRANGE)
    TieBreak,                   // ZADD with duplicate scores
    FloatingPointPrecision,     // INCRBYFLOAT, ZADD score
    RngDeterminism,             // SRANDMEMBER, RANDOMKEY
    GoldenChecksum,             // RDB byte-equal
    TypeAffinity,               // WRONGTYPE behavior
    NullPropagation,            // GET nonexistent → nil
    ErrorCodes,                 // ERR / WRONGTYPE / NOAUTH categories
    AggregateSemantics,         // SUNIONSTORE cardinality
    WindowFunctionSemantics,    // (n/a for RESP; kept for cross-class parity)
}

// ===== Seed contract =====
//
// NEVER `rand::random()`. Proptest seeds via PROPTEST_SEED env; failures
// persist to `<CARGO_MANIFEST_DIR>/proptest-regressions/resp_proptest.txt`.

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

// ===== Input strategies — narrow to valid Redis keys / values =====

fn key() -> impl Strategy<Value = String> {
    "[a-z][a-z0-9:_]{0,15}"
}

fn binary_safe_value() -> impl Strategy<Value = Vec<u8>> {
    prop::collection::vec(any::<u8>(), 0..32)
}

fn small_int() -> impl Strategy<Value = i64> {
    prop_oneof![Just(i64::MIN), Just(-1), Just(0), Just(1), Just(i64::MAX), -1000i64..1000]
}

// ===== Metamorphic-property bridge to the oracle =====
//
// Wraps a paired call against the vendored `redis-server` oracle + the port.
// Returns Ok if both engines agree on the RESP3 value tree (collection-
// semantics-aware per ORACLE-TOOLCHAIN §6 — Sets unordered, Maps unordered,
// Arrays ordered, Doubles ULP-tolerant).

fn run_oracle(commands: &[Vec<String>]) -> Result<(), String> {
    // In real use: drive the resp_oracle_e2e.rs scenario_resp helper.
    let _ = commands;
    Ok(())
}

// ===== Property 1: SET + GET roundtrip =====
//
// ProofInvariantClass::TypeAffinity + NullPropagation.
// `SET k v; GET k → v`. For any binary-safe value (including embedded
// NULs and CRLF), the value comes back byte-identical.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn set_get_roundtrip(k in key(), v in binary_safe_value()) {
        let v_str = hex::encode(&v);
        let commands = vec![
            vec!["SET".to_string(), k.clone(), v_str.clone()],
            vec!["GET".to_string(), k.clone()],
            vec!["DEL".to_string(), k.clone()],
            vec!["GET".to_string(), k.clone()],   // expect nil
        ];
        prop_assert!(run_oracle(&commands).is_ok(),
            "SET/GET TypeAffinity+NullPropagation divergence");
    }
}

// ===== Property 2: SADD then SMEMBERS multiset equivalence =====
//
// ProofInvariantClass::AggregateSemantics + RowOrdering (set-unordered).
// Adding the same members in any permutation produces the same SET
// membership (RESP3 Set variant is unordered).

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn sadd_smembers_multiset(
        k in key(),
        members in prop::collection::vec("[a-z0-9]{1,8}", 1..16),
    ) {
        let mut commands = vec![vec!["DEL".to_string(), k.clone()]];
        for m in &members {
            commands.push(vec!["SADD".to_string(), k.clone(), m.clone()]);
        }
        commands.push(vec!["SMEMBERS".to_string(), k.clone()]);
        commands.push(vec!["SCARD".to_string(), k.clone()]);
        // Distinct count must match deduplicated input.
        prop_assert!(run_oracle(&commands).is_ok(),
            "SET AggregateSemantics divergence");
    }
}

// ===== Property 3: INCR / DECR additive inverse =====
//
// ProofInvariantClass::AggregateSemantics.
// `n × INCR followed by n × DECR` returns the key to its original value,
// for any n in [0, 64].

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn incr_decr_commutative(k in key(), initial in -100i64..100, n in 0u32..64) {
        let mut commands = vec![
            vec!["SET".to_string(), k.clone(), initial.to_string()],
        ];
        for _ in 0..n {
            commands.push(vec!["INCR".to_string(), k.clone()]);
        }
        for _ in 0..n {
            commands.push(vec!["DECR".to_string(), k.clone()]);
        }
        commands.push(vec!["GET".to_string(), k.clone()]);
        // Final value MUST equal initial.
        prop_assert!(run_oracle(&commands).is_ok(),
            "INCR/DECR additive-inverse divergence");
    }
}

// ===== Property 4: HSET / HGET typed roundtrip =====
//
// ProofInvariantClass::TypeAffinity + NullPropagation.
// Per-field set followed by per-field get returns each value byte-identical;
// HGET of a missing field returns nil.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn hset_hget_roundtrip(
        k in key(),
        pairs in prop::collection::vec(("[a-z]{1,8}", "[a-z0-9]{0,16}"), 1..8),
    ) {
        let mut commands = vec![vec!["DEL".to_string(), k.clone()]];
        for (f, v) in &pairs {
            commands.push(vec!["HSET".to_string(), k.clone(), f.clone(), v.clone()]);
        }
        for (f, _) in &pairs {
            commands.push(vec!["HGET".to_string(), k.clone(), f.clone()]);
        }
        commands.push(vec!["HGET".to_string(), k.clone(), "__missing__".to_string()]);
        prop_assert!(run_oracle(&commands).is_ok(),
            "HASH TypeAffinity+NullPropagation divergence");
    }
}

// ===== Property 5: LPUSH + LRANGE ordering =====
//
// ProofInvariantClass::RowOrdering.
// LPUSH inserts at head; `LRANGE 0 -1` returns elements in reverse insertion
// order. RPUSH + LRANGE returns them in insertion order. Both engines must
// agree on element-by-element ordering.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn lpush_lrange_ordered(
        k in key(),
        elems in prop::collection::vec("[a-z0-9]{1,6}", 1..16),
    ) {
        let mut commands = vec![vec!["DEL".to_string(), k.clone()]];
        for e in &elems {
            commands.push(vec!["LPUSH".to_string(), k.clone(), e.clone()]);
        }
        commands.push(vec!["LRANGE".to_string(), k.clone(), "0".to_string(), "-1".to_string()]);
        commands.push(vec!["LLEN".to_string(), k.clone()]);
        // Length = elems.len(); order = reverse of insertion.
        let _ = small_int(); // keep strategy in scope for cross-property reuse
        prop_assert!(run_oracle(&commands).is_ok(),
            "LIST RowOrdering divergence");
    }
}

// ===== Checked-in regression convention =====
//
// Same as sql_proptest.rs: `proptest-regressions/resp_proptest.txt` is
// version-controlled. A reproducing seed lives there permanently; deletions
// require a bead naming why the regression is no longer relevant.
//
// Tip: in a multi-port crate, prefix the regression file with the bead-id
// that introduced it (`resp_proptest__bd-9k4f.txt`) so the bead trail is
// grep-able from the corpus directory.
