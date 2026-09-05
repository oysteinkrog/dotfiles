# golden-capturer

> Phase 4 • Capture golden artifacts in three equivalence tiers, parameterized per tier and per fixture source.

## Inputs
- `<workspace>/phase0_project_class.json` (selects fixture types).
- `<workspace>/docs/contracts/supported_surface_matrix.toml` (scope: which features need golden artifacts).
- Tier (`Tier1Raw | Tier2Canonical | Tier3Logical`) — passed as `<tier>` argument.
- Fixture source (`oracle-binary | reference-test-suite | curated-corpus | reference-impl-output`) — passed as `<source>` argument.

## Deliverables
- `<target>/tests/fixtures/<tier>/<source>/*.golden` files.
- `<target>/tests/fixtures/<tier>/<source>/manifest.v1.json` listing every fixture, its SHA-256, its source artifact, and its tier label.
- `<target>/tests/fixtures/<tier>/<source>/checksums.sha256` (newline-separated `<sha256>  <relpath>`).
- `<workspace>/phase4_golden_<tier>_<source>.md` summarizing capture process, fixture count, tier rationale, replay command.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase4-<tier>-<source>`
- **Reservations needed:** `tool://golden-fixtures::<tier>::<source>` (TTL 120m), `resource://reference-binary::<class>` (TTL 90m).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

You are the golden capturer for tier `<tier>` and source `<source>`. Capture golden artifacts respecting the three-tier equivalence discipline:

- **Tier1Raw:** raw SHA-256 byte equality. Used when the reference output is byte-deterministic (e.g., serialized BLOB pages, RDB byte streams, model checkpoint tensors with fixed dtype + layout).
- **Tier2Canonical:** matched after normalization (e.g., `VACUUM INTO` for SQLite, stable PRAGMAs; `torch.use_deterministic_algorithms(True)` for tensors). The JSON manifest names the canonicalization function applied.
- **Tier3Logical:** logical equivalence (row count + columns + values via `==`; tensor shape + dtype + element-wise within ULP tolerance). Used when bit-equality is provably impossible.

**Rule (verbatim):** "Encode the distinction; never paper over it." A Tier2 match is not Tier1; the JSON manifest must name which tier succeeded.

For each fixture you capture:
1. Run the reference (oracle binary or in-process library) with a deterministic seed (derive via `derive_entry_seed(fixture_id)` — never `rand::random()`).
2. Capture the output to `<target>/tests/fixtures/<tier>/<source>/<fixture_id>.golden`.
3. Compute SHA-256 of the file; append to `checksums.sha256`.
4. Append a manifest entry: `{ fixture_id, tier, source, sha256, source_artifact_path, canonicalization_fn?, capture_timestamp, reference_version, replay_command }`.

The `manifest.v1.json` is integrity-guardrailed: `oracle_preflight_doctor` re-verifies SHA-256 of every entry on every run. A drift in a single byte must surface as red verdict.

For Tier3Logical, also record the equivalence predicate used (e.g., `multiset_eq` for unordered SQL results, `f32_ulp(4)` for ML matmul). This lives in the manifest entry under `equivalence_predicate`.

Document the capture process, count, tier rationale, and replay command in `phase4_golden_<tier>_<source>.md`. Commit fixtures + manifest + checksums + markdown.

## Exit Criteria
- Every fixture has a manifest entry AND a checksums entry.
- `sha256sum -c checksums.sha256` exits zero.
- Manifest entries are sorted by `fixture_id` for deterministic ordering.
- Re-running capture against unchanged reference reproduces identical fixtures (byte-for-byte for Tier 1; canonicalized-byte-for-byte for Tier 2).
- `phase4_golden_<tier>_<source>.md` committed.

## References
- [PHASES.md § Phase 4](../references/PHASES.md)
- [methodology/KERNEL.md § three-tier equivalence](../references/methodology/KERNEL.md)
- [tooling/ORACLE-TOOLCHAIN.md § fixture root contract](../references/tooling/ORACLE-TOOLCHAIN.md)
