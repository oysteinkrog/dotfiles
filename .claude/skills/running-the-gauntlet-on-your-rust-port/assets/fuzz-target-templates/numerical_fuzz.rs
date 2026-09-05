//! numerical_fuzz.rs — paste-ready Numerical-Python-class differential-fuzz target.
//!
//! Copy into `fuzz/fuzz_targets/fuzz_ufunc_oracle.rs` after running
//!   `cargo +nightly fuzz init`
//!   `cargo +nightly fuzz add fuzz_ufunc_oracle`
//!
//! fuzz/Cargo.toml dependencies:
//!   libfuzzer-sys = "0.4"
//!   arbitrary     = { version = "1", features = ["derive"] }
//!   pyo3          = { version = "0.23", features = ["auto-initialize"] }
//!   <your-port>   = { path = "../" }
//!
//! Pairs with: assets/integration-test-templates/numerical_oracle_e2e.rs.

#![no_main]

use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;
use pyo3::prelude::*;
use pyo3::types::PyDict;

// ===== Structure-aware input — narrow to valid ArraySpec + ufunc =====
//
// `ArraySpec` is bounded so the fuzzer doesn't generate 100MB tensors; the
// ufunc set is small so we exercise semantic edges (broadcasting, dtype
// promotion, NaN propagation) rather than syntactic ones.

#[derive(Arbitrary, Debug, Clone)]
pub struct ArraySpec {
    pub shape: Shape,
    pub dtype: DType,
    pub data: Vec<f64>,
}

#[derive(Arbitrary, Debug, Clone)]
pub enum Shape {
    D1(u8),       // length 0..32
    D2(u8, u8),   // rows × cols, each 0..8
    D3(u8, u8, u8),
}

impl Shape {
    fn dims(&self) -> Vec<usize> {
        match self {
            Shape::D1(n)        => vec![(*n as usize) % 32],
            Shape::D2(a, b)     => vec![(*a as usize) % 8, (*b as usize) % 8],
            Shape::D3(a, b, c)  => vec![(*a as usize) % 4, (*b as usize) % 4, (*c as usize) % 4],
        }
    }
    fn total(&self) -> usize { self.dims().iter().product() }
}

#[derive(Arbitrary, Debug, Clone, Copy)]
pub enum DType { F32, F64, I32, I64 }

impl DType {
    fn np(&self) -> &'static str {
        match self { Self::F32 => "float32", Self::F64 => "float64", Self::I32 => "int32", Self::I64 => "int64" }
    }
}

#[derive(Arbitrary, Debug, Clone, Copy)]
pub enum Ufunc {
    Add, Subtract, Multiply, Divide,
    Sum, Mean, Min, Max,
    Abs, Negative,
}

impl Ufunc {
    fn np_name(&self) -> &'static str {
        match self {
            Self::Add => "add", Self::Subtract => "subtract",
            Self::Multiply => "multiply", Self::Divide => "divide",
            Self::Sum => "sum", Self::Mean => "mean",
            Self::Min => "min", Self::Max => "max",
            Self::Abs => "abs", Self::Negative => "negative",
        }
    }
    fn is_binary(&self) -> bool { matches!(self, Self::Add | Self::Subtract | Self::Multiply | Self::Divide) }
    fn is_reduction(&self) -> bool { matches!(self, Self::Sum | Self::Mean | Self::Min | Self::Max) }
}

#[derive(Arbitrary, Debug, Clone)]
pub struct DiffInput {
    pub ufunc: Ufunc,
    pub lhs: ArraySpec,
    pub rhs: Option<ArraySpec>,
}

// ===== Differential driver =====
//
// Drives both numpy (PyO3, in-process) and the port through the same input;
// any byte-divergence after ULP normalization is a bug. The 4 ULP / 2 ULP
// table from ORACLE-TOOLCHAIN §7 drives the per-op tolerance.

fuzz_target!(|input: DiffInput| {
    // Bound total size so we don't OOM the fuzzer.
    let lhs_n = input.lhs.shape.total();
    if lhs_n > 256 { return; }
    if lhs_n == 0 { return; }
    if input.lhs.data.len() < lhs_n { return; }

    let lhs_data: Vec<f64> = input.lhs.data.iter().take(lhs_n).copied().collect();
    let lhs_dims = input.lhs.shape.dims();

    let rhs = if input.ufunc.is_binary() {
        match &input.rhs {
            Some(r) if r.shape.dims() == lhs_dims && r.data.len() >= lhs_n => {
                Some((r.data.iter().take(lhs_n).copied().collect::<Vec<f64>>(), r.dtype))
            }
            _ => return,
        }
    } else {
        None
    };

    let np_dtype = input.lhs.dtype.np();
    let py_setup = if let Some((rhs_data, rhs_dtype)) = &rhs {
        format!(r#"
import numpy as np
a = np.array({lhs:?}, dtype='{np_dtype}').reshape({dims:?})
b = np.array({rhs:?}, dtype='{rdt}').reshape({dims:?})
result = np.{op}(a, b).astype(np.float64).flatten().tolist()
"#, lhs = lhs_data, np_dtype = np_dtype, dims = lhs_dims, rhs = rhs_data, rdt = rhs_dtype.np(), op = input.ufunc.np_name())
    } else if input.ufunc.is_reduction() {
        format!(r#"
import numpy as np
a = np.array({lhs:?}, dtype='{np_dtype}').reshape({dims:?})
result = [float(np.{op}(a))]
"#, lhs = lhs_data, np_dtype = np_dtype, dims = lhs_dims, op = input.ufunc.np_name())
    } else {
        format!(r#"
import numpy as np
a = np.array({lhs:?}, dtype='{np_dtype}').reshape({dims:?})
result = np.{op}(a).astype(np.float64).flatten().tolist()
"#, lhs = lhs_data, np_dtype = np_dtype, dims = lhs_dims, op = input.ufunc.np_name())
    };

    let ref_result: Vec<f64> = Python::with_gil(|py| {
        let locals = PyDict::new_bound(py);
        if py.run_bound(&py_setup, None, Some(&locals)).is_err() { return Vec::new(); }
        locals.get_item("result").ok().flatten()
            .and_then(|v| v.extract().ok())
            .unwrap_or_default()
    });
    if ref_result.is_empty() { return; }

    // Port-side computation — stub. Replace with real port call.
    let port_result: Vec<f64> = port_compute(&input, &lhs_data, &rhs, &lhs_dims);

    if port_result.len() != ref_result.len() {
        panic!("DIFFERENTIAL DIVERGENCE: length ref={} port={}", ref_result.len(), port_result.len());
    }

    let ulp_tol = ulp_tolerance_for(input.ufunc, input.lhs.dtype);
    for (i, (r, p)) in ref_result.iter().zip(port_result.iter()).enumerate() {
        if !approx_equal_ulp(*r, *p, ulp_tol) {
            panic!(
                "DIFFERENTIAL DIVERGENCE\n  op: {:?}\n  dtype: {}\n  at [{}]: ref={:.17}, port={:.17}, ulp_tol={}",
                input.ufunc, np_dtype, i, r, p, ulp_tol
            );
        }
    }
});

fn ulp_tolerance_for(op: Ufunc, dt: DType) -> u32 {
    match (op, dt) {
        (Ufunc::Sum | Ufunc::Mean, DType::F32) => 8,
        (Ufunc::Sum | Ufunc::Mean, DType::F64) => 4,
        _ => 2,
    }
}

fn approx_equal_ulp(a: f64, b: f64, ulp: u32) -> bool {
    if a == b { return true; }
    if a.is_nan() && b.is_nan() { return true; }
    if a.is_infinite() && b.is_infinite() && a.signum() == b.signum() { return true; }
    let ab = a.to_bits() as i64;
    let bb = b.to_bits() as i64;
    (ab - bb).unsigned_abs() <= ulp as u64
}

fn port_compute(_input: &DiffInput, lhs: &[f64], _rhs: &Option<(Vec<f64>, DType)>, _dims: &[usize]) -> Vec<f64> {
    // Stub: replace with real port call (e.g., port::Array::from(...).op(...)).
    lhs.to_vec()
}
