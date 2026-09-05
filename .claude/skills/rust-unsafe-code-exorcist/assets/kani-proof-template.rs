//! Kani proof template — copy to <project>/proofs/site_<id>.rs.
//!
//! Per [FORMAL-VERIFICATION.md](../references/methodology/FORMAL-VERIFICATION.md).
//! Fill in the input symbols, the assumption bounds, and the invariant assertion.
//!
//! Run with:
//!   cargo install --locked kani-verifier
//!   cargo kani setup
//!   cargo kani --harness site_<id>_invariant

#![cfg(kani)]

#[cfg_attr(kani, kani::proof)]
#[cfg_attr(kani, kani::unwind(8))]
fn site_NNNN_invariant() {
    // === Step 1: Generate symbolic inputs ===
    //
    // kani::any() generates an unconstrained value of the inferred type.
    // For complex types, you may need to bound the input or use kani::Arbitrary.

    let input: u32 = kani::any();

    // === Step 2: Bound the input to make verification tractable ===
    //
    // kani::assume() restricts the input space. Without bounds, kani may not
    // terminate. With bounds, the proof is "valid for inputs within the bound."
    // Document the bound in the per-site plan.

    kani::assume(input < 1_000_000);

    // === Step 3: Invoke the rewrite ===
    //
    // This is the function under proof. Use the safe rewrite from the plan.

    let result = mycrate::safe_rewrite(input);

    // === Step 4: Assert the invariant ===
    //
    // The invariant is from the per-site write-up's "sound IFF [condition]" form.
    // Assertion failures mean kani found a counter-example.

    match result {
        Ok(value) => {
            // Forward invariant: for valid inputs, the result satisfies <property>.
            assert!(invariant_holds(input, value));
        }
        Err(_) => {
            // Some inputs validly produce an error. Check that the error itself
            // is correct (right variant, right code path).
            assert!(input_should_have_failed(input));
        }
    }
}

// === Helper predicates ===
//
// Define the invariant predicate in plain Rust. Kani will inline + analyze.

fn invariant_holds(input: u32, output: u32) -> bool {
    // The specific property the rewrite must satisfy.
    // Example: output is monotonic in input.
    output >= input || output == 0
}

fn input_should_have_failed(input: u32) -> bool {
    // The inputs that should cause Err to be returned.
    // Example: zero is an explicit invalid input.
    input == 0
}

// === Sanity-check stub ===
//
// To verify the proof actually tests what we think it does:
// 1. Deliberately break `safe_rewrite` (introduce an off-by-one).
// 2. Re-run `cargo kani --harness site_NNNN_invariant`.
// 3. Verify the proof FAILS with a counter-example.
// 4. Revert the deliberate bug.
//
// Document this sanity check in the per-site plan.
