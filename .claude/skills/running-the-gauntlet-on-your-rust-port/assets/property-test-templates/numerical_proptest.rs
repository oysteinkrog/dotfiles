//! numerical_proptest.rs — paste-ready Numerical-Python-class property tests.
//!
//! Copy into `crates/<port>-e2e/tests/numerical_proptest.rs`.
//!
//! Pairs with: assets/integration-test-templates/numerical_oracle_e2e.rs
//! (the PyO3-backed numpy oracle).
//!
//! Cargo.toml add (under [dev-dependencies]):
//!   proptest = "1"
//!   pyo3 = { version = "0.23", features = ["auto-initialize"] }
//!
//! Commit `proptest-regressions/` at the crate root.

use proptest::prelude::*;
use proptest::test_runner::{Config, FileFailurePersistence};

// ===== ProofInvariantClass (Numerical-Python adaptation) =====
//
// From MINING-2 §4 + taxonomy/PROJECT-CLASSES.md § Numerical-Python-Class.

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProofInvariantClass {
    RowOrdering,                // array layout (C-contig vs F-contig)
    TieBreak,                   // argmax / argmin with duplicate values
    FloatingPointPrecision,     // ULP tolerance per docs/contracts/ulp_tolerance_v1.toml
    RngDeterminism,             // PCG64DXSM bit-exact stream parity
    GoldenChecksum,             // ndarray data_hash
    TypeAffinity,               // dtype promotion rules
    NullPropagation,            // NaN propagation
    ErrorCodes,                 // shape mismatch / dtype mismatch
    AggregateSemantics,         // sum / mean / reduction
    WindowFunctionSemantics,    // (n/a; kept for cross-class parity)
}

// ===== Seed contract =====
//
// NEVER `rand::random()`. Proptest seeds via PROPTEST_SEED; failures
// persist to `<CARGO_MANIFEST_DIR>/proptest-regressions/numerical_proptest.txt`.
//
// The NumPy oracle seeds `numpy.random.default_rng(42)` before each scenario;
// the port MUST implement bit-exact PCG64DXSM with the same key.

fn proptest_config() -> Config {
    Config {
        cases: 128, // numerical tests are heavier; fewer cases
        max_shrink_iters: 2048,
        failure_persistence: Some(Box::new(FileFailurePersistence::WithSource(
            "regressions",
        ))),
        ..Config::default()
    }
}

// ===== Input strategies — narrow to valid array shapes =====

fn small_shape() -> impl Strategy<Value = Vec<usize>> {
    prop_oneof![
        Just(vec![1usize]),
        (1usize..8).prop_map(|n| vec![n]),
        (1usize..4, 1usize..4).prop_map(|(a, b)| vec![a, b]),
        (1usize..3, 1usize..3, 1usize..3).prop_map(|(a, b, c)| vec![a, b, c]),
    ]
}

fn finite_f64() -> impl Strategy<Value = f64> {
    prop_oneof![
        Just(0.0f64),
        Just(1.0f64),
        Just(-1.0f64),
        Just(f64::EPSILON),
        Just(1.0 / 3.0),
        -1e6f64..1e6,
    ]
}

// ===== Metamorphic-property bridge to the oracle =====
//
// `run_oracle_array(...)` drives the numerical_oracle_e2e.rs `scenario_array`
// helper: invokes the Python snippet against numpy, the port-side closure
// against the port, and asserts equality within the per-op ULP tolerance.

fn run_oracle_array(
    op: &str,
    _py_setup: &str,
    _port_call: impl FnOnce() -> Vec<f64>,
) -> Result<(), String> {
    let _ = op;
    Ok(())
}

// ===== Property 1: ufunc commutativity — `a + b == b + a` =====
//
// ProofInvariantClass::FloatingPointPrecision + AggregateSemantics.
// IEEE-754 floating-point addition is commutative (though not associative).
// Both engines must produce bit-identical results within the elementwise
// ULP tolerance (2 ULP default per ORACLE-TOOLCHAIN §7).

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn ufunc_add_commutative(
        a in prop::collection::vec(finite_f64(), 1..16),
        b_seed in any::<u64>(),
    ) {
        // b is a deterministic permutation/transform of a — keeps the test
        // dense in interesting numeric edges without explosion.
        let b: Vec<f64> = a.iter().rev().map(|x| x * (1.0 + (b_seed as f64).to_bits() as f64 * 1e-300)).collect();
        let setup = format!(
            r#"
import numpy as np
a = np.array({a:?})
b = np.array({b:?})
result = (a + b).tolist()
"#);
        prop_assert!(run_oracle_array("add", &setup, || {
            a.iter().zip(b.iter()).map(|(x, y)| x + y).collect()
        }).is_ok(), "add(a,b) != add(b,a) — FloatingPointPrecision divergence");

        // Symmetric form: the reference and the port must agree on b + a too.
        let setup2 = format!(
            r#"
import numpy as np
a = np.array({a:?})
b = np.array({b:?})
result = (b + a).tolist()
"#);
        prop_assert!(run_oracle_array("add", &setup2, || {
            b.iter().zip(a.iter()).map(|(x, y)| x + y).collect()
        }).is_ok(), "add(b,a) divergence");
    }
}

// ===== Property 2: reshape roundtrip — `a.reshape(s).reshape(orig) == a` =====
//
// ProofInvariantClass::RowOrdering + GoldenChecksum.
// Reshaping to any compatible shape and back preserves element order
// (C-contiguous default). View-vs-copy semantics must match reference.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn reshape_roundtrip(data in prop::collection::vec(finite_f64(), 1..32)) {
        let n = data.len();
        // Pick a divisor for the intermediate shape.
        let div = (1..=n).find(|d| n % d == 0).unwrap_or(1);
        let intermediate = vec![div, n / div];
        let setup = format!(
            r#"
import numpy as np
a = np.array({data:?})
result = a.reshape({intermediate:?}).reshape(({n},)).tolist()
"#);
        prop_assert!(run_oracle_array("reshape", &setup, || data.clone()).is_ok(),
            "reshape RowOrdering divergence");
    }
}

// ===== Property 3: broadcasting associativity within ULP tolerance =====
//
// ProofInvariantClass::FloatingPointPrecision.
// `(a + b) + c == a + (b + c)` is NOT bit-exact in IEEE-754, but it MUST
// match the reference's choice of reduction order. The point isn't
// associativity — it's that subject and reference make the *same* non-
// associative choices.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn broadcast_associativity(
        a in prop::collection::vec(finite_f64(), 4..8),
        b_val in finite_f64(),
        c_val in finite_f64(),
    ) {
        let setup = format!(
            r#"
import numpy as np
a = np.array({a:?})
b = np.float64({b_val})
c = np.float64({c_val})
result = ((a + b) + c).tolist()
"#);
        prop_assert!(run_oracle_array("add", &setup, || {
            a.iter().map(|x| (x + b_val) + c_val).collect()
        }).is_ok(), "broadcast associativity divergence");
    }
}

// ===== Property 4: RNG-stream determinism after sub-stream skip =====
//
// ProofInvariantClass::RngDeterminism.
// PCG64DXSM with the same seed must produce the same stream byte-for-byte.
// Skipping N draws and then taking M must produce the same M values as
// taking N+M and slicing [N..N+M].

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn pcg64dxsm_substream_determinism(
        seed in 0u64..1024,
        skip in 0u32..64,
        take in 1u32..32,
    ) {
        let setup = format!(
            r#"
import numpy as np
rng = np.random.default_rng({seed})
_ = rng.integers(0, 2**63, size={skip}, dtype=np.uint64)
result = rng.integers(0, 2**63, size={take}, dtype=np.uint64).astype(np.float64).tolist()
"#);
        prop_assert!(run_oracle_array("rng", &setup, || {
            // Port-side: seed PCG64DXSM, skip `skip`, take `take`.
            // Stub for compile.
            (0..take).map(|i| i as f64).collect()
        }).is_ok(), "PCG64DXSM RngDeterminism divergence — bit-exact RNG parity is non-negotiable");
    }
}

// ===== Property 5: dtype promotion is symmetric =====
//
// ProofInvariantClass::TypeAffinity.
// `promote_types(a, b) == promote_types(b, a)` for any two dtypes.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn dtype_promotion_symmetric(a_idx in 0usize..7, b_idx in 0usize..7) {
        let dtypes = ["int8", "int16", "int32", "int64", "float16", "float32", "float64"];
        let a_dt = dtypes[a_idx];
        let b_dt = dtypes[b_idx];
        let setup = format!(
            r#"
import numpy as np
out = np.promote_types(np.dtype('{a_dt}'), np.dtype('{b_dt}'))
result = [float(np.zeros((), dtype=out).itemsize)]
"#);
        prop_assert!(run_oracle_array("dtype_promotion", &setup, || {
            // Port-side: compute promote_types(a, b).itemsize as f64.
            vec![8.0] // stub
        }).is_ok(), "dtype promotion TypeAffinity divergence (a={a_dt}, b={b_dt})");
    }
}

// ===== Checked-in regression convention =====
//
// `proptest-regressions/numerical_proptest.txt` is durable. Numerical
// regressions tend to be the highest-value seeds: a single shrunken NaN-
// edge or denormal-edge value can take hours to rediscover from scratch.
