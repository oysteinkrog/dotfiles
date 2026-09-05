//! ml_fuzz.rs — paste-ready ML-System-class differential-fuzz target.
//!
//! Copy into `fuzz/fuzz_targets/fuzz_tensor_oracle.rs` after running
//!   `cargo +nightly fuzz init`
//!   `cargo +nightly fuzz add fuzz_tensor_oracle`
//!
//! fuzz/Cargo.toml dependencies:
//!   libfuzzer-sys = "0.4"
//!   arbitrary     = { version = "1", features = ["derive"] }
//!   pyo3          = { version = "0.23", features = ["auto-initialize"] }
//!   <your-port>   = { path = "../" }
//!
//! Pairs with: assets/integration-test-templates/ml_oracle_e2e.rs.

#![no_main]

use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;
use pyo3::prelude::*;
use pyo3::types::PyDict;

// ===== Structure-aware input — narrow to valid TensorSpec + op =====

#[derive(Arbitrary, Debug, Clone)]
pub struct TensorSpec {
    pub shape: TensorShape,
    pub dtype: TensorDType,
    pub data: Vec<f32>,
}

#[derive(Arbitrary, Debug, Clone)]
pub enum TensorShape {
    D1(u8),
    D2(u8, u8),
    D3(u8, u8, u8),
    D4(u8, u8, u8, u8),
}

impl TensorShape {
    fn dims(&self) -> Vec<usize> {
        match self {
            Self::D1(n)         => vec![(*n as usize) % 16 + 1],
            Self::D2(a, b)      => vec![(*a as usize) % 8 + 1, (*b as usize) % 8 + 1],
            Self::D3(a, b, c)   => vec![(*a as usize) % 4 + 1, (*b as usize) % 4 + 1, (*c as usize) % 4 + 1],
            Self::D4(a, b, c, d)=> vec![(*a as usize) % 4 + 1, (*b as usize) % 4 + 1,
                                        (*c as usize) % 4 + 1, (*d as usize) % 4 + 1],
        }
    }
    fn total(&self) -> usize { self.dims().iter().product() }
}

#[derive(Arbitrary, Debug, Clone, Copy)]
pub enum TensorDType { F32, F64, I32, I64 }

impl TensorDType {
    fn torch_name(&self) -> &'static str {
        match self { Self::F32 => "torch.float32", Self::F64 => "torch.float64",
                     Self::I32 => "torch.int32", Self::I64 => "torch.int64" }
    }
}

#[derive(Arbitrary, Debug, Clone, Copy)]
pub enum TensorOp {
    Add, Mul, Sub, Div,
    Sum, Mean, Max,
    ReLU, Sigmoid, Tanh,
    Transpose,
}

impl TensorOp {
    fn torch_call(&self) -> &'static str {
        match self {
            Self::Add => "a + b", Self::Mul => "a * b", Self::Sub => "a - b", Self::Div => "a / b",
            Self::Sum => "a.sum()", Self::Mean => "a.float().mean()", Self::Max => "a.max()",
            Self::ReLU => "torch.relu(a)", Self::Sigmoid => "torch.sigmoid(a.float())",
            Self::Tanh => "torch.tanh(a.float())", Self::Transpose => "a.transpose(0, -1)",
        }
    }
    fn is_binary(&self) -> bool { matches!(self, Self::Add | Self::Mul | Self::Sub | Self::Div) }
    fn ulp_tol(&self, dt: TensorDType) -> u32 {
        match (self, dt) {
            (Self::Add | Self::Sub | Self::Mul, _) => 2,
            (Self::Div, _) => 4,
            (Self::Sum | Self::Mean, TensorDType::F32) => 8,
            (Self::Sum | Self::Mean, TensorDType::F64) => 4,
            (Self::Sigmoid | Self::Tanh, _) => 8,
            _ => 2,
        }
    }
}

#[derive(Arbitrary, Debug, Clone)]
pub struct DiffInput {
    pub op: TensorOp,
    pub lhs: TensorSpec,
    pub rhs: Option<TensorSpec>,
}

// ===== Differential driver =====
//
// PyO3 torch + `use_deterministic_algorithms(True)` pinned at process start.
// Any divergence beyond per-op ULP tolerance is a bug.

fuzz_target!(|input: DiffInput| {
    let lhs_n = input.lhs.shape.total();
    if lhs_n > 256 || lhs_n == 0 { return; }
    if input.lhs.data.len() < lhs_n { return; }

    let lhs_data: Vec<f32> = input.lhs.data.iter().take(lhs_n).copied().collect();
    let lhs_dims = input.lhs.shape.dims();

    let rhs = if input.op.is_binary() {
        match &input.rhs {
            Some(r) if r.shape.dims() == lhs_dims && r.data.len() >= lhs_n => {
                Some((r.data.iter().take(lhs_n).copied().collect::<Vec<f32>>(), r.dtype))
            }
            _ => return,
        }
    } else {
        None
    };

    let dt = input.lhs.dtype.torch_name();
    let call = input.op.torch_call();
    let py_setup = if let Some((rhs_data, rhs_dtype)) = &rhs {
        format!(r#"
import torch
torch.use_deterministic_algorithms(True)
torch.manual_seed(42)
a = torch.tensor({lhs:?}, dtype={dt}).reshape({dims:?})
b = torch.tensor({rhs:?}, dtype={rdt}).reshape({dims:?})
out = {call}
result = out.to(torch.float64).flatten().tolist() if out.dim() > 0 else [float(out)]
"#, lhs = lhs_data, dt = dt, dims = lhs_dims, rhs = rhs_data, rdt = rhs_dtype.torch_name(), call = call)
    } else {
        format!(r#"
import torch
torch.use_deterministic_algorithms(True)
torch.manual_seed(42)
a = torch.tensor({lhs:?}, dtype={dt}).reshape({dims:?})
out = {call}
result = out.to(torch.float64).flatten().tolist() if out.dim() > 0 else [float(out)]
"#, lhs = lhs_data, dt = dt, dims = lhs_dims, call = call)
    };

    let ref_result: Vec<f64> = Python::with_gil(|py| {
        let locals = PyDict::new_bound(py);
        if py.run_bound(&py_setup, None, Some(&locals)).is_err() { return Vec::new(); }
        locals.get_item("result").ok().flatten()
            .and_then(|v| v.extract().ok())
            .unwrap_or_default()
    });
    if ref_result.is_empty() { return; }

    // Port-side. Stub.
    let port_result: Vec<f64> = port_compute(&input, &lhs_data, &rhs, &lhs_dims);

    if port_result.len() != ref_result.len() {
        panic!("DIFFERENTIAL DIVERGENCE: length ref={} port={}", ref_result.len(), port_result.len());
    }

    let ulp_tol = input.op.ulp_tol(input.lhs.dtype);
    for (i, (r, p)) in ref_result.iter().zip(port_result.iter()).enumerate() {
        if !approx_equal_ulp_f64(*r, *p, ulp_tol) {
            panic!(
                "DIFFERENTIAL DIVERGENCE\n  op: {:?}\n  dtype: {}\n  at [{}]: ref={:.17}, port={:.17}, ulp_tol={}",
                input.op, dt, i, r, p, ulp_tol
            );
        }
    }
});

fn approx_equal_ulp_f64(a: f64, b: f64, ulp: u32) -> bool {
    if a == b { return true; }
    if a.is_nan() && b.is_nan() { return true; }
    if a.is_infinite() && b.is_infinite() && a.signum() == b.signum() { return true; }
    let ab = a.to_bits() as i64;
    let bb = b.to_bits() as i64;
    (ab - bb).unsigned_abs() <= ulp as u64
}

fn port_compute(_input: &DiffInput, lhs: &[f32], _rhs: &Option<(Vec<f32>, TensorDType)>, _dims: &[usize]) -> Vec<f64> {
    lhs.iter().map(|x| *x as f64).collect()
}
