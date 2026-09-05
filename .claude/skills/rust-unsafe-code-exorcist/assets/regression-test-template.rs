//! Regression test template — copy to <project>/tests/regression_<incident_id>.rs.
//!
//! Per [INCIDENT-RESPONSE-PLAYBOOK.md](../references/methodology/INCIDENT-RESPONSE-PLAYBOOK.md)
//! § Phase 2 reconstruction. The test must FAIL on the pre-fix version and PASS
//! on the post-fix version.

//! # Regression test for <INCIDENT-ID>
//!
//! - **Symptom.** <one-line>
//! - **RCA.** <link to audit/incident-rca.md>
//! - **Fix.** <link to audit/plans/site-<id>.md>
//!
//! Without the fix, this test should fail with:
//! ```text
//! <expected miri / panic / wrong-result message>
//! ```

#[test]
fn regression_<incident_id>_<short_description>() {
    // ARRANGE: construct the state that triggered the bug.
    let problematic_input = vec![/* the input the reporter found */];

    // ACT: invoke the affected operation.
    let result = mycrate::affected_fn(&problematic_input);

    // ASSERT: post-fix expected behavior.
    assert_eq!(result, Ok(expected_value));
}

#[test]
fn regression_<incident_id>_under_miri() {
    // The same shape, ensuring it's runnable under miri.
    //
    // If miri can't run this test (e.g., FFI-touching), mark it
    // #[cfg_attr(miri, ignore)] and rely on cargo-careful.
    let input = vec![/* ... */];
    let result = mycrate::affected_fn(&input);
    assert_eq!(result, Ok(expected_value));
}

#[cfg(loom)]
#[test]
fn regression_<incident_id>_under_loom() {
    // For concurrency bugs: model the interleavings.
    loom::model(|| {
        // Reproduce the bug under loom's interleavings.
        // Bound the model:
        // loom::model::Builder::new().preemption_bound(3).check(|| { ... })

        let shared = std::sync::Arc::new(/* shared state */);
        let s2 = shared.clone();
        let t = loom::thread::spawn(move || {
            // Producer
        });
        // Consumer
        t.join().unwrap();
        // Assert post-conditions.
    });
}

// Property-based equivalence test (where applicable, for (C) refactors)
proptest::proptest! {
    #![proptest_config(proptest::test_runner::Config { cases: 10_000, ..Default::default() })]

    #[test]
    fn regression_<incident_id>_property(x in proptest::collection::vec(0u8..=255, 0..256)) {
        // For arbitrary inputs in a bounded space, the affected fn must:
        // 1. Not panic.
        // 2. Not produce UB.
        // 3. Match the safe rewrite's output.
        let result = mycrate::affected_fn(&x);
        // The "should match" varies by the fix:
        //   - For (C) refactor: result must equal `mycrate::safe_rewrite(&x)`.
        //   - For (A) hardening: result is Ok if input satisfies obligation, Err otherwise.
        match expected_outcome(&x) {
            Some(v) => proptest::prop_assert_eq!(result, Ok(v)),
            None => proptest::prop_assert!(result.is_err()),
        }
    }
}

// === Helpers ===

fn expected_outcome(input: &[u8]) -> Option<u32> {
    // Replicate the EXPECTED behavior, independent of the rewrite under test.
    // This is the "specification" the test pins.
    compile_error!("fill in expected_outcome per the per-site plan's specification before using this template");
}
