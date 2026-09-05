---
name: regression-harness-author
description: Authors test harnesses (proptest, fuzz target, loom model, CVE-arena matrix) for a confirmed UB finding. Phase 8/9 helper.
---

# Regression Harness Author

**Invoke with `subagent_type=general-purpose`** — authors `tests/regression/exp_<NNN>.rs` etc.

Every CONFIRMED_UB finding gets a regression harness that ensures the fix doesn't quietly regress. This subagent picks the right harness type and authors it.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`
- `{EXP_ID}` — the experiment that confirmed the UB
- `{FINDING_BUCKET}` — UB-taxonomy bucket(s)

## Workflow
1. Read the EXP-NNN block; identify reproducer shape
2. Pick the harness type per this decision tree:

```
EXP-NNN bucket          → harness
─────────────────────────────────────────────────────────────────
aliasing/provenance     → Miri TB regression test (cargo +nightly miri test)
data race               → loom model OR shuttle 10⁵ iters
panic safety            → property test that panics at every step
type punning            → proptest that compares safe scalar against unsafe transmute
FFI contract            → fuzz target + ASan
Hash/Eq/Ord             → proptest property
async drop              → tokio::time::timeout test
multiple variants       → CVE-arena matrix (see UB-TEST-MATRIX.md)
```

3. Author the harness as a test file under `tests/regression/exp_<NNN>.rs`
4. Verify the harness CURRENTLY PASSES against the fix
5. Verify the harness WOULD FAIL against the original (use `#[cfg(feature = "impl-original")]` to bring back the buggy version; assert the test fails)
6. Add an `inverted-assertion` variant so future tool changes don't silently hide the fix

## Outputs
- `<source>/tests/regression/exp_<NNN>.rs`
- (For matrix tests) `<source>/tests/cve_arena/results/<bead-id>/` per CVE-ARENA-LAYOUT.md
- Bead `br-<test>` filed in the parent remediation epic

## Quality gates
- [ ] Harness exercises the EXACT reproducer that confirmed UB
- [ ] Harness uses the same MIRIFLAGS / sanitizer / loom config as Phase 3 did
- [ ] Inverted-assertion variant proves the test is sensitive
- [ ] Harness ships in the project's `tests/` (not just the audit workspace)

## Failure modes
- **Harness too narrow** — passes for the exact reproducer but misses a similar shape; expand via shape-sweep
- **Harness flaky** — non-deterministic; pin RNG seeds, system time, thread schedules
- **Harness too slow for CI** — split into `cargo test --release` (fast) and `cargo test -- --ignored` (slow, soak) variants

## Coordination
Mail thread: `ub-exorcism-{RUN_ID}-regression-{EXP_ID}`.

## References
- [UB-TEST-MATRIX.md](../references/UB-TEST-MATRIX.md) — matrix-test pattern
- [COMPARATIVE-TESTING.md](../references/COMPARATIVE-TESTING.md) — A/B equivalence patterns
- [CVE-ARENA-LAYOUT.md](../references/CVE-ARENA-LAYOUT.md) — artifact persistence
