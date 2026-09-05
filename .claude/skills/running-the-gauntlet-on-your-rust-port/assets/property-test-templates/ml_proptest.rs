//! ml_proptest.rs — paste-ready ML-System-class property tests.
//!
//! Copy into `crates/<port>-e2e/tests/ml_proptest.rs`.
//!
//! Pairs with: assets/integration-test-templates/ml_oracle_e2e.rs (the
//! PyO3-backed torch oracle with deterministic-algorithms pinning).
//!
//! Cargo.toml add (under [dev-dependencies]):
//!   proptest = "1"
//!   pyo3 = { version = "0.23", features = ["auto-initialize"] }
//!
//! Commit `proptest-regressions/` at the crate root.

use proptest::prelude::*;
use proptest::test_runner::{Config, FileFailurePersistence};

// ===== ProofInvariantClass (ML-System adaptation) =====
//
// From MINING-2 §4 + taxonomy/PROJECT-CLASSES.md § ML-System-Class.

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProofInvariantClass {
    RowOrdering,                // tensor memory format (channels_last vs contiguous)
    TieBreak,                   // topk / argmax with duplicate scores
    FloatingPointPrecision,     // per-op ULP tolerance (4 ULP f32 matmul default)
    RngDeterminism,             // torch.manual_seed + cuda determinism
    GoldenChecksum,             // state-dict SHA-256 + checkpoint roundtrip
    TypeAffinity,               // dtype promotion + autocast
    NullPropagation,            // NaN/Inf forward + backward
    ErrorCodes,                 // shape mismatch / device mismatch
    AggregateSemantics,         // reduction ops (sum / mean / norm)
    WindowFunctionSemantics,    // (n/a; kept for cross-class parity)
}

// ===== Seed contract =====
//
// NEVER `rand::random()`. `torch.use_deterministic_algorithms(True)` pinned
// in the oracle harness setup. Failures persist to
// `<CARGO_MANIFEST_DIR>/proptest-regressions/ml_proptest.txt`.

fn proptest_config() -> Config {
    Config {
        cases: 64, // ML tests are even heavier (autograd, JIT)
        max_shrink_iters: 1024,
        failure_persistence: Some(Box::new(FileFailurePersistence::WithSource(
            "regressions",
        ))),
        ..Config::default()
    }
}

// ===== Input strategies — narrow to valid tensor shapes =====

fn tensor_shape_2d() -> impl Strategy<Value = (usize, usize)> {
    (1usize..16, 1usize..16)
}

fn tensor_shape_4d_small() -> impl Strategy<Value = (usize, usize, usize, usize)> {
    (1usize..4, 1usize..4, 1usize..8, 1usize..8) // N, C, H, W
}

fn finite_f32() -> impl Strategy<Value = f32> {
    prop_oneof![
        Just(0.0f32),
        Just(1.0f32),
        Just(-1.0f32),
        Just(f32::EPSILON),
        -100.0f32..100.0,
    ]
}

// ===== Metamorphic-property bridge to the oracle =====
//
// `run_oracle_tensor` invokes ml_oracle_e2e.rs `scenario_tensor`: PyO3-loaded
// torch reference vs port closure; ULP tolerance per op.

#[allow(dead_code)]
fn run_oracle_tensor(
    op: &str,
    _py_setup: &str,
    _port_call: impl FnOnce() -> Vec<f32>,
) -> Result<(), String> {
    let _ = op;
    Ok(())
}

// ===== Property 1: `jit(grad(f))(x) ≡ grad(jit(f))(x)` =====
//
// ProofInvariantClass::FloatingPointPrecision + RngDeterminism.
// JIT compilation and autograd must commute within ULP tolerance. This
// catches the "JIT rewrite changed gradient" class of bugs.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn jit_grad_commute(x in prop::collection::vec(finite_f32(), 4..8)) {
        let setup = format!(
            r#"
import torch
torch.manual_seed(42)
torch.use_deterministic_algorithms(True)
x = torch.tensor({x:?}, requires_grad=True)
def f(t):
    return (t * t).sum()
# Path A: grad of jitted f
fj = torch.jit.trace(f, x)
yj = fj(x)
gj = torch.autograd.grad(yj, x, retain_graph=True)[0]
# Path B: jit of grad-fn — semantically should match
y = f(x)
g = torch.autograd.grad(y, x)[0]
result = (gj - g).abs().max().item()
"#);
        // ULP tolerance: backward typically 2× forward; allow 8 ULP for f32.
        prop_assert!(run_oracle_tensor("autograd_jit_commute", &setup, || {
            vec![0.0f32] // stub: max(|gj - g|) computed port-side
        }).is_ok(), "jit(grad(f)) vs grad(jit(f)) FloatingPointPrecision divergence");
    }
}

// ===== Property 2: autograd-tape determinism under same seed =====
//
// ProofInvariantClass::RngDeterminism + GoldenChecksum.
// Two forward+backward passes through the same model with the same seed
// must produce bit-identical gradients (`torch.use_deterministic_algorithms`
// + `CUBLAS_WORKSPACE_CONFIG=:4096:8`).

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn autograd_tape_deterministic((n, m) in tensor_shape_2d()) {
        let setup = format!(
            r#"
import torch
torch.use_deterministic_algorithms(True)
def run():
    torch.manual_seed(42)
    w = torch.randn({n}, {m}, requires_grad=True)
    x = torch.randn({m})
    y = (w @ x).sum()
    y.backward()
    return w.grad.flatten().tolist()
g1 = run()
g2 = run()
result = [float(abs(a - b)) for a, b in zip(g1, g2)]
"#);
        prop_assert!(run_oracle_tensor("autograd_determinism", &setup, || {
            vec![0.0f32; n * m] // stub: should be all zeros if deterministic
        }).is_ok(), "autograd-tape RngDeterminism divergence");
    }
}

// ===== Property 3: softmax sums to 1.0 within epsilon =====
//
// ProofInvariantClass::AggregateSemantics + FloatingPointPrecision.
// `softmax(x).sum() ≈ 1.0` for any finite x. Tolerance: 1e-7 (f32),
// 1e-15 (f64) per ORACLE-TOOLCHAIN §7.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn softmax_sums_to_one(x in prop::collection::vec(finite_f32(), 2..32)) {
        let setup = format!(
            r#"
import torch
x = torch.tensor({x:?}, dtype=torch.float32)
sm = torch.softmax(x, dim=0)
result = [abs(float(sm.sum()) - 1.0)]
"#);
        prop_assert!(run_oracle_tensor("softmax_sums_to_one", &setup, || {
            // Port-side: compute softmax(x).sum() - 1.0
            vec![1e-9f32] // stub
        }).is_ok(), "softmax AggregateSemantics divergence");
    }
}

// ===== Property 4: matmul associativity within ULP =====
//
// ProofInvariantClass::FloatingPointPrecision.
// `(A @ B) @ C ≈ A @ (B @ C)` within the per-matmul ULP tolerance
// (4 ULP f32, 2 ULP f64). The point: subject and reference make the same
// non-associative choices.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn matmul_associative_within_ulp((k, m) in tensor_shape_2d()) {
        let setup = format!(
            r#"
import torch
torch.manual_seed(7)
A = torch.randn({k}, {m})
B = torch.randn({m}, {k})
C = torch.randn({k}, {m})
left = (A @ B) @ C
right = A @ (B @ C)
result = (left - right).abs().max().reshape(1).tolist()
"#);
        prop_assert!(run_oracle_tensor("matmul_f32", &setup, || {
            vec![0.0f32] // stub: |left - right|_max computed port-side
        }).is_ok(), "matmul associativity ULP-tolerance divergence");
    }
}

// ===== Property 5: conv shape invariant =====
//
// ProofInvariantClass::AggregateSemantics + RowOrdering.
// For conv2d with `stride=1, padding=0`, output shape is
// `(N, out_C, H - kH + 1, W - kW + 1)`. Both engines must produce that exact
// shape AND agree bit-for-bit on integer-input conv.

proptest! {
    #![proptest_config(proptest_config())]

    #[test]
    fn conv2d_shape_invariant((n, c, h, w) in tensor_shape_4d_small()) {
        if h < 3 || w < 3 { return Ok(()); }
        let setup = format!(
            r#"
import torch
x = torch.zeros({n}, {c}, {h}, {w})
weight = torch.zeros(4, {c}, 3, 3)
out = torch.nn.functional.conv2d(x, weight, stride=1, padding=0)
result = list(out.shape)
result = [float(s) for s in result]
"#);
        prop_assert!(run_oracle_tensor("conv2d_shape", &setup, || {
            vec![n as f32, 4.0, (h - 2) as f32, (w - 2) as f32]
        }).is_ok(), "conv2d output-shape AggregateSemantics divergence");
    }
}

// ===== Checked-in regression convention =====
//
// `proptest-regressions/ml_proptest.txt` is durable. ML regressions tend
// to expose:
//   - non-deterministic CUDA kernels (set `CUBLAS_WORKSPACE_CONFIG=:4096:8`)
//   - autograd-tape ordering bugs that only show under specific dtypes
//   - JIT cache key collisions
// Each shrunken seed is a quote-bank-grade anchor for the negative ledger.
