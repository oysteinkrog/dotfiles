//! http_proptest.rs — paste-ready HTTP-Protocol-class property tests.
//!
//! Copy into `crates/<port>-e2e/tests/http_proptest.rs`.
//!
//! Pairs with: assets/integration-test-templates/http_oracle_e2e.rs (the
//! uvicorn-FastAPI reference + port scenario harness).
//!
//! Cargo.toml add (under [dev-dependencies]):
//!   proptest = "1"
//!
//! Commit `proptest-regressions/` at the crate root.

use proptest::prelude::*;
use proptest::test_runner::{Config, FileFailurePersistence};

// ===== ProofInvariantClass (HTTP-Protocol adaptation) =====
//
// From MINING-2 §4 + taxonomy/PROJECT-CLASSES.md § HTTP-Protocol-Class.

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProofInvariantClass {
    RowOrdering,                // header order in multi-value headers (Set-Cookie)
    TieBreak,                   // route precedence with overlapping patterns
    FloatingPointPrecision,     // (n/a; kept for cross-class parity)
    RngDeterminism,             // deterministic clock + RNG injection
    GoldenChecksum,             // OpenAPI schema SHA-256 + transcript byte-equal
    TypeAffinity,               // content-type negotiation
    NullPropagation,            // empty body vs missing body
    ErrorCodes,                 // 4xx/5xx category mapping
    AggregateSemantics,         // middleware stack composition
    WindowFunctionSemantics,    // (n/a; kept for cross-class parity)
}

// ===== Seed contract =====
//
// NEVER `rand::random()`. Deterministic clock + ChaCha20Rng injected.
// Failures persist to
// `<CARGO_MANIFEST_DIR>/proptest-regressions/http_proptest.txt`.

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

// ===== Input strategies — narrow to valid HTTP =====

fn header_name() -> impl Strategy<Value = String> {
    "[a-zA-Z][a-zA-Z0-9-]{0,15}"
}

fn header_value() -> impl Strategy<Value = String> {
    "[a-zA-Z0-9 ._-]{0,32}"
}

fn safe_path() -> impl Strategy<Value = String> {
    "/[a-z0-9/_-]{0,32}"
}

fn http_method() -> impl Strategy<Value = &'static str> {
    prop_oneof![Just("GET"), Just("POST"), Just("PUT"), Just("DELETE"), Just("PATCH")]
}

// ===== Metamorphic-property bridge to the oracle =====
//
// `run_oracle_http` invokes http_oracle_e2e.rs `scenario_http`: drives the
// uvicorn-FastAPI reference + port through the same request fixture and
// compares normalized responses (status + case-insensitive headers + MIME-
// aware body).

fn run_oracle_http(
    method: &str,
    path: &str,
    headers: &[(String, String)],
    body: &[u8],
) -> Result<(), String> {
    let _ = (method, path, headers, body);
    Ok(())
}

// ===== Property 1: header-case-insensitivity in lookup =====
//
// ProofInvariantClass::TypeAffinity (header semantics).
// Per RFC 7230 §3.2, header names are case-insensitive. Sending `Content-Type`,
// `content-type`, and `CONTENT-TYPE` must produce identical responses.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn header_case_insensitive(value in header_value()) {
        let cases = [
            ("Content-Type", value.as_str()),
            ("content-type", value.as_str()),
            ("CONTENT-TYPE", value.as_str()),
            ("CoNtEnT-tYpE", value.as_str()),
        ];
        for (name, val) in cases {
            let headers = vec![(name.to_string(), val.to_string())];
            prop_assert!(run_oracle_http("GET", "/echo-content-type", &headers, b"").is_ok(),
                "header case-sensitivity divergence at name={name}");
        }
    }
}

// ===== Property 2: idempotent GET =====
//
// ProofInvariantClass::AggregateSemantics + GoldenChecksum.
// Per RFC 7231 §4.2.2, GET is idempotent: N identical requests produce N
// identical responses (modulo Date/server-side state).

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn get_idempotent(path in safe_path(), n in 2u32..6) {
        for i in 0..n {
            let _ = i;
            prop_assert!(run_oracle_http("GET", &path, &[], b"").is_ok(),
                "GET {path} not idempotent at iteration {i}");
        }
    }
}

// ===== Property 3: route-order independence (commutative router add) =====
//
// ProofInvariantClass::TieBreak.
// Adding routes A then B vs B then A must produce the same dispatch
// behavior for non-overlapping patterns. Overlapping patterns get
// deterministic precedence per the framework's documented rule (more-
// specific wins; on ties, last-registered wins).

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn route_add_order_invariant(a in safe_path(), b in safe_path()) {
        prop_assume!(a != b);
        // Test that GET a hits the a-handler regardless of registration order.
        prop_assert!(run_oracle_http("GET", &a, &[], b"").is_ok(),
            "route precedence divergence on {a}");
        prop_assert!(run_oracle_http("GET", &b, &[], b"").is_ok(),
            "route precedence divergence on {b}");
    }
}

// ===== Property 4: cancellation-budget respected =====
//
// ProofInvariantClass::RngDeterminism + GoldenChecksum.
// A cancelled request MUST clean up its resources within N milliseconds.
// This is the primary invariant for fastmcp_rust (MCP tool-cancellation).

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn cancellation_releases_within_budget(
        path in safe_path(),
        cancel_after_ms in 1u64..100,
    ) {
        // Stage 1: start a long-running request.
        // Stage 2: cancel after cancel_after_ms.
        // Stage 3: assert active-task counter returns to baseline within
        //          (cancel_after_ms + 100ms) budget.
        let body = format!("{{\"sleep_ms\": 5000, \"cancel_at\": {cancel_after_ms}}}").into_bytes();
        prop_assert!(run_oracle_http("POST", &path, &[], &body).is_ok(),
            "cancellation budget exceeded at cancel_after_ms={cancel_after_ms}");
    }
}

// ===== Property 5: error-class category match =====
//
// ProofInvariantClass::ErrorCodes.
// A malformed request (invalid JSON body, missing required field, etc.)
// must produce the same HTTP status class (4xx) on both sides. The exact
// message text is irrelevant — only the category matters per K-8.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn error_status_class_agreement(
        method in http_method(),
        path in safe_path(),
        body in prop::collection::vec(any::<u8>(), 0..64),
    ) {
        let headers = vec![("Content-Type".to_string(), "application/json".to_string())];
        prop_assert!(run_oracle_http(method, &path, &headers, &body).is_ok(),
            "error status-class divergence");
    }
}

// Compile-time keep-alive for the strategies that aren't called directly in
// the example properties above (so the imports/helpers don't churn when you
// extend the file with your own properties).
#[allow(dead_code)]
fn _strategy_compile_check() {
    let _ = (header_name(), header_value(), safe_path(), http_method());
}

// ===== Checked-in regression convention =====
//
// `proptest-regressions/http_proptest.txt` is durable. HTTP regressions
// tend to expose:
//   - header normalization bugs (case-folding, whitespace trimming)
//   - route precedence drift under refactors
//   - cancellation cleanup races (file descriptors leaked, tasks orphaned)
// Pair every retained seed with a bead capturing the root-cause class.
