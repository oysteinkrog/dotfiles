# UB Test Matrix — Adversarial Multi-Pattern Test Templates

When a UB shape has several known variants (use-after-free, dangling alias, wild pointer, double-free), the user's recurring practice is to author a **matrix test** that exercises every variant at scale and asserts `detected × classification × strict_expectation × hardened_expectation`.

Anchor: cass Q-101 — frankenlibc `adversarial_pointer_fault_injection_matrix_has_zero_false_negatives` (100K probes, gated on zero false negatives).

---

## When to write a matrix test

After a Phase 8 remediation, when:
- The remediation eliminates a *class* of UB (not just one site)
- Multiple variants of the class exist (temporal, spatial, allocator-paired, etc.)
- The detection must be 100% reliable in production (security-critical)

Examples:
- Pointer fault injection (UAF / dangling / wild / double-free)
- Locking-protocol violations (held-too-long / not-held / wrong-lock)
- Allocator pairing (Rust-Box / libc-malloc / arena / mmap)
- FFI calling convention (`cdecl` / `stdcall` / `vectorcall` / `aapcs`)

---

## The matrix template

From cass Q-101 (lightly cleaned for clarity):

```rust
#[test]
#[allow(unsafe_code)]
fn adversarial_pointer_fault_injection_matrix_has_zero_false_negatives() {
    let mut rows: Vec<FaultInjectionRow> = Vec::new();

    // === Use-after-free: vary delay and allocation size ===
    for (delay, size) in [(0usize, 32usize), (1, 128), (100, 1024)] {
        let pipeline = build_pipeline();
        let addr = pipeline.alloc(size);
        let first = pipeline.free(addr);
        assert!(
            matches!(first, FreeResult::Freed | FreeResult::FreedWithCanaryCorruption),
            "first free should succeed in uaf setup"
        );
        churn_allocator_state(&pipeline, delay);
        let out = pipeline.validate(addr);
        rows.push(FaultInjectionRow {
            pattern: "use_after_free",
            variant: format!("delay={}, size={}", delay, size),
            mode: "strict",
            detected: matches!(out, ValidationOutcome::TemporalViolation(_)),
            classification: "TemporalViolation",
            strict_expectation: "Deny",
            hardened_expectation: "Deny + ReturnSafeDefault at API boundary",
        });
    }

    // === Dangling aliases ===
    for variant in DANGLING_ALIAS_VARIANTS {
        // ... build, free, check, classify
        rows.push(FaultInjectionRow { /* ... */ });
    }

    // === Wild pointers: null+offset, stack pointer, high canonical address ===
    for variant in WILD_POINTER_VARIANTS {
        // ...
        rows.push(FaultInjectionRow { /* ... */ });
    }

    // === Double-free with delay variation ===
    for delay in [0usize, 1usize, 10_000usize] {
        // ...
    }

    // === Assert zero false negatives ===
    let false_negatives: Vec<_> = rows.iter()
        .filter(|r| r.strict_expectation == "Deny" && !r.detected)
        .collect();

    assert!(
        false_negatives.is_empty(),
        "{} false negatives: {:?}",
        false_negatives.len(),
        false_negatives
    );

    // === Optionally persist the artifact ===
    let artifact_path = format!(
        "tests/cve_arena/results/{}/uaf_adversarial_detection.v1.json",
        env!("CARGO_BEAD_ID"),  // injected via build.rs from the current bead
    );
    std::fs::write(
        &artifact_path,
        serde_json::to_string_pretty(&rows).unwrap(),
    ).unwrap();
}
```

The `FaultInjectionRow` schema:

```rust
#[derive(Debug, Serialize, Deserialize)]
struct FaultInjectionRow {
    pattern: &'static str,              // "use_after_free" | "dangling_alias" | "wild_pointer" | "double_free"
    variant: String,                    // human-readable parameter combo
    mode: &'static str,                 // "strict" | "hardened"
    detected: bool,                     // did the system catch it?
    classification: &'static str,       // "TemporalViolation" | "SpatialViolation" | "Foreign" | "ForeignFastPath"
    strict_expectation: &'static str,   // "Deny" | "Allow"
    hardened_expectation: &'static str, // human-readable expectation in hardened mode
}
```

---

## Sweep dimensions

For each pattern, vary:

| Dimension | Examples |
|---|---|
| **Size** | 32, 128, 1024, 4096, page-boundary |
| **Delay** | 0, 1, 100, 10⁴ allocator-state churn cycles |
| **Address style** | Heap (Rust), Heap (libc), Stack, mmap, MMIO, high-canonical |
| **Concurrency** | Single-thread, 2-thread, N-thread |
| **Mode** | `strict` (Deny), `hardened` (Deny + telemetry) |

A 4×4×4×3×2 matrix = 384 probes per pattern; with 4 patterns = ~1.5K probes; cass Q-101 reports 100K probes via repeated sampling.

---

## The zero-false-negatives gate

The assertion's structure:

```rust
let false_negatives: Vec<_> = rows.iter()
    .filter(|r| r.strict_expectation == "Deny" && !r.detected)
    .collect();
assert!(false_negatives.is_empty(), ...);
```

The user **only** gates on false negatives (missed UB), not false positives. Rationale:
- False negative = silent UB = production bug
- False positive = noisy logs / dropped legitimate operation = ops cost

For the remediation to land, false negatives must be zero. False positives are budget-able.

---

## CVE Arena artifact layout

Each matrix-test run produces a JSON artifact persisted to the CVE arena:

```
tests/cve_arena/
└── results/
    └── <bead-id>/                          # e.g., bd-18qq.4
        ├── artifact_index.json             # manifest of this bead's artifacts
        ├── trace.jsonl                     # per-probe trace
        └── <scenario>.v1.json              # e.g., uaf_adversarial_detection.v1.json
```

The `v1` suffix lets the schema evolve without breaking older artifacts.

See [CVE-ARENA-LAYOUT.md](CVE-ARENA-LAYOUT.md) for the full schema.

---

## When the matrix test fails

If `false_negatives` is non-empty:
- The specific (pattern, variant, mode) tuples that missed are now CONFIRMED_UB findings.
- File each as a new `F-NNN` in `phase4_unified_findings.md`.
- Loop back to Phase 8 with the new findings.

The matrix test is itself a *regression gate* — once it passes, it stays in CI forever, guarding against re-introductions.

---

## CI integration

```yaml
# .github/workflows/cve-arena.yml
on: [push, pull_request]
jobs:
  matrix-tests:
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo test --release --test adversarial_pointer_fault_injection_matrix
      - uses: actions/upload-artifact@v4
        with:
          name: cve-arena-results
          path: tests/cve_arena/results/
```

The artifact upload preserves the JSON results for trend analysis (did detection coverage improve across releases?).

---

## Cross-references

- [CVE-ARENA-LAYOUT.md](CVE-ARENA-LAYOUT.md) — artifact schema
- [UB-BEAD-LADDER.md](UB-BEAD-LADDER.md) — bead structure where matrix tests live
- [SHAPE-SWEEP.md](SHAPE-SWEEP.md) — finding the variants to sweep
- cass Q-101 — verbatim source
