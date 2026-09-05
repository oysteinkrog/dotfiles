//! numerical_oracle_e2e.rs — paste-ready Numerical-Python-class oracle test.
//!
//! Copy into `crates/<port>-e2e/tests/<op_family>_oracle_e2e.rs`.

use pyo3::prelude::*;
use pyo3::types::PyDict;

const SUBJECT_IDENTITY_LABEL: &str = "<port>";        // e.g. "franken_numpy"
const REFERENCE_IDENTITY_LABEL: &str = "numpy-oracle";

/// Drive an op through the PyO3 reference + the port; assert array equivalence
/// per ULP tolerance table.
fn scenario_array(op: &str, py_setup: &str, port_call: impl FnOnce() -> Vec<f64>, label: &str) {
    assert_ne!(SUBJECT_IDENTITY_LABEL, REFERENCE_IDENTITY_LABEL,
        "EngineIdentity self-comparison violation");

    Python::with_gil(|py| {
        // Determinism flags (pinned per python-reference-bridger).
        py.import_bound("numpy").unwrap().getattr("random").unwrap()
            .getattr("seed").unwrap().call1((42_u64,)).unwrap();

        let locals = PyDict::new_bound(py);
        py.run_bound(py_setup, None, Some(&locals)).expect("py_setup");
        let ref_result: Vec<f64> = locals.get_item("result").unwrap()
            .unwrap().extract().expect("extract result");

        let port_result = port_call();

        assert_eq!(ref_result.len(), port_result.len(),
            "{label}: length mismatch ref={} port={}", ref_result.len(), port_result.len());

        let ulp_tol = ulp_tolerance_for(op);  // from docs/contracts/ulp_tolerance_v1.toml
        for (i, (r, p)) in ref_result.iter().zip(port_result.iter()).enumerate() {
            if !approx_equal_ulp(*r, *p, ulp_tol) {
                panic!("{label}: divergence at [{i}]: ref={r:.17}, port={p:.17}, ulp_tol={ulp_tol}");
            }
        }
    });
}

fn ulp_tolerance_for(op: &str) -> u32 {
    // Defaults per pattern:35-NORMALIZED-VALUE for Numerical class.
    match op {
        "matmul_f32" => 4,
        "matmul_f64" => 2,
        _ => 2, // elementwise default
    }
}

fn approx_equal_ulp(a: f64, b: f64, ulp: u32) -> bool {
    if a == b { return true; }
    if a.is_nan() && b.is_nan() { return true; }
    if a.is_infinite() && b.is_infinite() && a.signum() == b.signum() { return true; }
    let a_bits = a.to_bits() as i64;
    let b_bits = b.to_bits() as i64;
    (a_bits - b_bits).unsigned_abs() <= ulp as u64
}

#[test]
fn sum_axis_basic() {
    scenario_array(
        "sum",
        r#"
import numpy as np
a = np.array([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
result = a.sum(axis=0).tolist()
"#,
        || {
            // <port>-side computation:
            // let a = port::Array::from(...);
            // a.sum_axis(0).into_vec()
            vec![5.0, 7.0, 9.0]  // stub: replace with real port call
        },
        "sum_axis_basic",
    );
}
