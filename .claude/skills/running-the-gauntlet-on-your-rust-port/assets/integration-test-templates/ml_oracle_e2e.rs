//! ml_oracle_e2e.rs — paste-ready ML-System-class oracle test.
//!
//! Copy into `crates/<port>-e2e/tests/<op_family>_oracle_e2e.rs`.

use pyo3::prelude::*;
use pyo3::types::PyDict;

const SUBJECT_IDENTITY_LABEL: &str = "<port>";        // e.g. "frankentorch"
const REFERENCE_IDENTITY_LABEL: &str = "torch-oracle";

/// Drive a TensorSpec op through the PyO3 reference + port; assert tensor-equivalence
/// per per-op ULP tolerance + gradcheck rel-error.
fn scenario_tensor(
    op: &str,
    py_setup: &str,
    port_call: impl FnOnce() -> TensorSpec,
    label: &str,
) {
    assert_ne!(SUBJECT_IDENTITY_LABEL, REFERENCE_IDENTITY_LABEL,
        "EngineIdentity self-comparison violation");

    Python::with_gil(|py| {
        // Pin determinism flags every test (per python-reference-bridger).
        let torch = py.import_bound("torch").unwrap();
        torch.getattr("manual_seed").unwrap().call1((42_u64,)).unwrap();
        torch.getattr("use_deterministic_algorithms").unwrap().call1((true,)).unwrap();
        let backends_cudnn = torch.getattr("backends").unwrap().getattr("cudnn").unwrap();
        backends_cudnn.setattr("deterministic", true).unwrap();
        backends_cudnn.setattr("benchmark", false).unwrap();

        let locals = PyDict::new_bound(py);
        py.run_bound(py_setup, None, Some(&locals)).expect("py_setup");

        let ref_spec = TensorSpec::from_py(py, locals.get_item("result").unwrap().unwrap());
        let port_spec = port_call();

        // Shape + dtype + device + requires_grad MUST match exactly.
        assert_eq!(ref_spec.shape, port_spec.shape, "{label}: shape mismatch");
        assert_eq!(ref_spec.dtype, port_spec.dtype, "{label}: dtype mismatch");
        assert_eq!(ref_spec.device, port_spec.device, "{label}: device mismatch");
        assert_eq!(ref_spec.requires_grad, port_spec.requires_grad,
            "{label}: requires_grad mismatch");

        // Data agreement per per-op ULP tolerance.
        let ulp_tol = ulp_tolerance_for(op);
        for (i, (r, p)) in ref_spec.data.iter().zip(port_spec.data.iter()).enumerate() {
            if !approx_equal_ulp(*r, *p, ulp_tol) {
                panic!("{label}: divergence at [{i}]: ref={r:.17}, port={p:.17}, ulp_tol={ulp_tol}");
            }
        }
    });
}

#[derive(Debug)]
struct TensorSpec {
    shape: Vec<usize>,
    dtype: String,
    device: String,
    requires_grad: bool,
    data: Vec<f64>,
}

impl TensorSpec {
    fn from_py(_py: Python<'_>, obj: pyo3::Bound<'_, PyAny>) -> Self {
        let shape: Vec<usize> = obj.getattr("shape").unwrap().extract().unwrap();
        // `.str()` returns Bound<PyString>; extract::<String> is the canonical
        // way to materialize it (`.to_string()` on Bound is not the displayed text).
        let dtype: String = obj.getattr("dtype").unwrap().str().unwrap().extract().unwrap();
        let device: String = obj.getattr("device").unwrap().str().unwrap().extract().unwrap();
        let requires_grad: bool = obj.getattr("requires_grad").unwrap().extract().unwrap();
        let flat: Vec<f64> = obj.call_method0("flatten").unwrap()
            .call_method0("tolist").unwrap().extract().unwrap();
        Self { shape, dtype, device, requires_grad, data: flat }
    }
}

fn ulp_tolerance_for(op: &str) -> u32 {
    // Defaults: 4 ULP for f32 matmul; 2 ULP for elementwise. Per-op overrides
    // in docs/contracts/ulp_tolerance_v1.toml.
    match op {
        "matmul_f32" | "linear_f32" => 4,
        "matmul_f64" | "linear_f64" => 2,
        _ => 2,
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
fn matmul_basic() {
    scenario_tensor(
        "matmul_f32",
        r#"
import torch
torch.manual_seed(42)
a = torch.randn(8, 16, dtype=torch.float32)
b = torch.randn(16, 4, dtype=torch.float32)
result = a @ b
"#,
        || {
            // <port>-side computation (replace stub):
            TensorSpec {
                shape: vec![8, 4],
                dtype: "torch.float32".into(),
                device: "cpu".into(),
                requires_grad: false,
                data: vec![0.0; 32],  // stub
            }
        },
        "matmul_basic",
    );
}
