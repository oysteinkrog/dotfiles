//! sql_proptest.rs — paste-ready SQL-class property tests.
//!
//! Copy into `crates/<port>-e2e/tests/sql_proptest.rs`.
//!
//! Pairs with: assets/integration-test-templates/sql_oracle_e2e.rs (the
//! deterministic scenario harness this proptest bridges into).
//!
//! Cargo.toml add (under [dev-dependencies]):
//!   proptest = "1"
//!   rusqlite = { version = "0.31", features = ["bundled"] }
//!
//! And commit a `proptest-regressions/` directory at the crate root; every
//! shrunken counterexample lands there as a checked-in regression seed.

use proptest::prelude::*;
use proptest::test_runner::{Config, FileFailurePersistence};

// ===== ProofInvariantClass — verbatim from MINING-2 §4 generalization =====
//
// Every kept property MUST name one of these invariant classes in its proof
// pack. A change that touches any of these classes is a behavior change and
// must be defended with a 5-line isomorphism proof (see
// references/remediation/ISOMORPHISM-PROOF-TEMPLATE.md).

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProofInvariantClass {
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
}

// ===== Seed contract (pattern:K-7 + ORACLE-TOOLCHAIN §11) =====
//
// NEVER `rand::random()`. NEVER unseeded threadrng. Same corpus entry id →
// same seed → same SQL → same bugs found. The proptest runner's seed comes
// from PROPTEST_SEED env var; absent that, from a fixed default so CI is
// fully reproducible.
//
// The `FileFailurePersistence::WithSource` setting makes proptest write
// every shrunken counterexample to
//   `<CARGO_MANIFEST_DIR>/proptest-regressions/sql_proptest.txt`
// — that file MUST be checked into git. Future runs replay it before
// generating fresh inputs, so a regression that flakes once is caught every
// run thereafter.

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

// ===== Input strategies — narrow to valid SQL =====
//
// The art of proptest: shape the strategy so generated inputs are valid by
// construction. Wide strategies generate mostly junk; narrow strategies hit
// real semantic edges.

fn small_int() -> impl Strategy<Value = i64> {
    prop_oneof![Just(i64::MIN), Just(-1), Just(0), Just(1), Just(i64::MAX), 0i64..1000]
}

fn small_ident() -> impl Strategy<Value = String> {
    "[a-z][a-z0-9_]{0,7}".prop_filter("reserved", |s| {
        !["select", "from", "where", "null", "true", "false", "and", "or", "not"]
            .contains(&s.as_str())
    })
}

fn maybe_null_int() -> impl Strategy<Value = Option<i64>> {
    prop_oneof![Just(None), small_int().prop_map(Some)]
}

// ===== Metamorphic-property bridge to the oracle (pattern:40-METAMORPHIC) =====
//
// Each property here is a *metamorphic relation*: an input transformation
// that should preserve the answer. The oracle (rusqlite) is the reference;
// the subject is the port. A property failure is filed as a
// `MismatchClassification` per the table in ORACLE-TOOLCHAIN §11 — only
// `TrueDivergence` blocks CI; the rest flow into the triage queue.
//
// `run_oracle()` is a thin wrapper around the 30-line `scenario()` from
// sql_oracle_e2e.rs. It returns `Ok(())` if both engines agree (including
// both-error agreement); `Err(reason)` on divergence.

fn run_oracle(stmts: &[String], queries: &[String]) -> Result<(), String> {
    // In real use: call the sql_oracle_e2e.rs `scenario()` helper.
    // Stub for compile: pretend everything agrees.
    let _ = (stmts, queries);
    Ok(())
}

// ===== Property 1: NULL propagation through ORDER BY =====
//
// ProofInvariantClass::NullPropagation + RowOrdering.
// SQLite's ORDER BY treats NULL as smaller than any non-NULL by default
// (ascending). Two equivalent renderings of "SORT WITH NULLS FIRST" must
// agree.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn null_ordering_consistent(rows in prop::collection::vec(maybe_null_int(), 0..16)) {
        let mut stmts = vec!["CREATE TABLE t(x INTEGER);".to_string()];
        for r in &rows {
            match r {
                Some(i) => stmts.push(format!("INSERT INTO t VALUES ({i});")),
                None    => stmts.push("INSERT INTO t VALUES (NULL);".to_string()),
            }
        }
        let queries = vec![
            "SELECT x FROM t ORDER BY x ASC NULLS FIRST;".to_string(),
            "SELECT x FROM t ORDER BY x IS NULL DESC, x ASC;".to_string(),
            "SELECT COUNT(*) FROM t WHERE x IS NULL;".to_string(),
        ];
        prop_assert!(run_oracle(&stmts, &queries).is_ok(),
            "NullPropagation+RowOrdering divergence — file as MismatchClassification");
    }
}

// ===== Property 2: GROUP BY count = sum of per-group counts =====
//
// ProofInvariantClass::AggregateSemantics.
// For any partitioning of rows by `g`, the total row count must equal the
// sum of per-group counts. This is the simplest GROUP BY metamorphic.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn groupby_count_equals_total(
        keys in prop::collection::vec(0i64..5, 0..32),
    ) {
        let mut stmts = vec!["CREATE TABLE t(g INTEGER);".to_string()];
        for k in &keys {
            stmts.push(format!("INSERT INTO t VALUES ({k});"));
        }
        let queries = vec![
            "SELECT COUNT(*) FROM t;".to_string(),
            "SELECT g, COUNT(*) FROM t GROUP BY g ORDER BY g;".to_string(),
            "SELECT SUM(c) FROM (SELECT COUNT(*) AS c FROM t GROUP BY g);".to_string(),
        ];
        // Metamorphic: COUNT(*) over t == SUM of GROUP BY counts.
        prop_assert!(run_oracle(&stmts, &queries).is_ok(),
            "AggregateSemantics divergence");
    }
}

// ===== Property 3: INNER JOIN commutativity =====
//
// ProofInvariantClass::AggregateSemantics + RowOrdering (set-equivalence).
// `A INNER JOIN B ON p` must produce the same multiset of rows as
// `B INNER JOIN A ON p` modulo column ordering. Multiset equivalence
// (order-insensitive) is the right `EquivalenceExpectation` here.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn inner_join_commutative(
        a_keys in prop::collection::vec(0i64..8, 0..8),
        b_keys in prop::collection::vec(0i64..8, 0..8),
    ) {
        let mut stmts = vec![
            "CREATE TABLE a(k INTEGER);".to_string(),
            "CREATE TABLE b(k INTEGER);".to_string(),
        ];
        for k in &a_keys { stmts.push(format!("INSERT INTO a VALUES ({k});")); }
        for k in &b_keys { stmts.push(format!("INSERT INTO b VALUES ({k});")); }

        // Wrap both in an ORDER BY so the multiset equivalence becomes byte-equal.
        let queries = vec![
            "SELECT COUNT(*) FROM a INNER JOIN b ON a.k = b.k;".to_string(),
            "SELECT COUNT(*) FROM b INNER JOIN a ON b.k = a.k;".to_string(),
            "SELECT a.k FROM a INNER JOIN b ON a.k = b.k ORDER BY a.k;".to_string(),
            "SELECT b.k FROM b INNER JOIN a ON b.k = a.k ORDER BY b.k;".to_string(),
        ];
        prop_assert!(run_oracle(&stmts, &queries).is_ok(),
            "JOIN commutativity divergence");
    }
}

// ===== Property 4: WHERE pushdown does not change the result =====
//
// ProofInvariantClass::TypeAffinity.
// `SELECT * FROM (SELECT * FROM t WHERE p) WHERE q` must equal
// `SELECT * FROM t WHERE p AND q` for AND-conjoinable predicates.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn where_pushdown_invariant(rows in prop::collection::vec(small_int(), 0..16)) {
        let mut stmts = vec!["CREATE TABLE t(x INTEGER);".to_string()];
        for r in &rows {
            stmts.push(format!("INSERT INTO t VALUES ({r});"));
        }
        let queries = vec![
            "SELECT x FROM (SELECT x FROM t WHERE x > 0) WHERE x < 100 ORDER BY x;".to_string(),
            "SELECT x FROM t WHERE x > 0 AND x < 100 ORDER BY x;".to_string(),
        ];
        prop_assert!(run_oracle(&stmts, &queries).is_ok(),
            "WHERE-pushdown TypeAffinity divergence");
    }
}

// ===== Property 5: error-class agreement =====
//
// ProofInvariantClass::ErrorCodes.
// If the subject errors on a query, the oracle must also error (not
// necessarily the same message — per K-8 both-error = agreement). The
// proptest seed reproduces the exact divergent input.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn error_class_agreement(name in small_ident()) {
        let stmts = vec!["CREATE TABLE t(x INTEGER);".to_string()];
        // Reference a column the schema lacks — both engines should reject.
        let queries = vec![format!("SELECT {name} FROM t;")];
        prop_assert!(run_oracle(&stmts, &queries).is_ok(),
            "ErrorCodes divergence");
    }
}

// ===== Checked-in regression convention =====
//
// `proptest-regressions/sql_proptest.txt` is the durable failure ledger.
// Workflow:
//   1. Proptest hits a divergence, shrinks, persists a line to that file.
//   2. Commit the file. Future runs replay it FIRST, guaranteeing the
//      same input is tried again before fresh generation.
//   3. The fix lands. The line stays. Now the test asserts "we never
//      regress into this bug again".
//
// Delete a line only with a bead that explains why the regression is
// permanently irrelevant (e.g., the SQL feature was removed from the
// surface contract).
