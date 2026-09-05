# invariant-catalog-builder

> Phase 7 • Build `parity_invariant_catalog.rs` with ParityInvariant + ProofObligation + ArtifactRef enumeration.

## Inputs
- `parity_taxonomy.rs` from `feature-universe-builder.md` (FeatureUniverse).
- All Phase 6 oracle / metamorphic / fuzz / crash-boundary / e-process artifacts (each becomes a ProofObligation).
- `<workspace>/phase0_project_class.json` (per-class proof kinds).

## Deliverables
- `<target>/crates/<project>-harness/src/parity_invariant_catalog.rs` with `InvariantCatalog`, `ParityInvariant`, `ProofObligation`, `ArtifactRef`.
- `<workspace>/phase7_invariant_catalog.md` documenting catalog cardinality, proof-kind distribution, traceability coverage.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase7-invariant-catalog`
- **Reservations needed:** `tool://invariant-catalog-write` (TTL 90m).
- **Lane:** cc_3 (surface parity).

## Verbatim Prompt

You are the invariant catalog builder. The catalog turns "we tested X" into "we tested X, the evidence is at path P with SHA-256 H against schema version V" — a release that ships the catalog ships the proof-of-work.

**Catalog topology:**
```
FeatureUniverse (parity_taxonomy.rs)
  ▼
InvariantCatalog
  ├── ParityInvariant (1:N per Feature)
  │     ├── invariant_id (e.g., INV-SQL-NULL-001)
  │     ├── statement (English: "SELECT x WHERE x IS NULL returns rows where x is NULL")
  │     ├── assumptions (list of preconditions)
  │     └── proof_obligations[]
  │           ├── ProofObligation { kind, evidence_ref, status }
  │           └── ArtifactRef { path, hash, schema_version }
  ├── validate()             → Vec<Violation>
  ├── release_traceability() → ReleaseTraceabilityReport
  └── stats()                → CatalogStats
```

**ProofKind enum (must include all of these; per-class subset may apply):**
```rust
pub enum ProofKind {
    OracleDifferential,    // *_oracle_e2e.rs test
    MetamorphicProperty,   // metamorphic_<family>_e2e.rs
    ProptestInvariant,     // proptest harness
    CrashBoundary,         // crash_boundary_<boundary>_e2e.rs
    EProcess,              // eprocess::<invariant> with Ville threshold
    FuzzNonPanic,          // cargo-fuzz with N hours sans crash
    InstaSnapshot,         // cargo-insta golden
}
```

**ArtifactRef:** every proof points to a real file with a real hash:
```rust
pub struct ArtifactRef {
    pub path: PathBuf,           // tests/fixtures/<...>.golden or artifacts/<run_id>/...
    pub hash: String,            // SHA-256 hex
    pub schema_version: String,  // e.g., "fsqlite-e2e.comprehensive-bench-report.v3"
}
```

**Validation (`validate()`)** checks:
1. Every `ParityInvariant` has ≥1 `ProofObligation`.
2. Every `ProofObligation.evidence_ref` resolves to a real file on disk.
3. Every file's SHA-256 matches the recorded `hash`.
4. Every `schema_version` matches a registered schema.

**Verification-contract enforcement (must be wired into CI):**

| Status | Base Gate | Meaning |
|--------|-----------|---------|
| `pass` | allowed | contract holds |
| `fail-missing-evidence` | blocked-by-contract | required proof absent |
| `fail-invalid-references` | blocked-by-contract | artifact paths don't resolve |
| `fail-mixed` | blocked-by-both | both gate and contract failures |

`release_traceability()` emits the per-feature evidence map for the certification bundle.

Document catalog cardinality (total invariants, per-feature average), proof-kind distribution, traceability coverage (% of features with full evidence chain), and the rejection examples from `validate()` in `phase7_invariant_catalog.md`.

## Exit Criteria
- `parity_invariant_catalog.rs` compiles and `cargo test --lib parity_invariant_catalog` passes.
- `validate()` against the current workspace returns zero violations (or every violation has a recorded `verification_status` and rationale).
- Deliberately deleting an evidence file makes `validate()` return `fail-invalid-references`.
- Coverage: every `Passing` and `Partial` feature has ≥1 ProofObligation; every `Missing` feature has zero (correctly).
- `phase7_invariant_catalog.md` committed.

## References
- [PHASES.md § Phase 7](../references/PHASES.md)
- [taxonomy/INVARIANT-CATALOG.md](../references/taxonomy/INVARIANT-CATALOG.md)
- [tooling/BENCH-TOOLCHAIN.md § verification-contract enforcement](../references/tooling/BENCH-TOOLCHAIN.md)
