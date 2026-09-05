# Pattern 25 — FIXTURE ROOT CONTRACT (manifest SHA-256 + cardinality floors + hash-locked roots)

## What

A typed Rust struct, `FixtureRootContract`, that turns a fixture corpus into auditable input. Pins: the manifest SHA-256, the fixture directory path, accepted aliases for that path, cardinality floors per category family, the list of required category families, hash-locked subdirectory roots (whose top-level content hash is committed), the file-extension allowlist, an optional expected root content hash, and a minimum included files count. Sourced from `[fixture_corpus]` in the version contract; verified by [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md).

## Why

> "Fixture root contracts turn corpora into auditable inputs. Source of truth for 'what am I testing against?'" — MINING-2 §14

Without a fixture contract, "we ran the conformance suite" means nothing. The corpus could have grown, shrunk, been silently rewritten, had categories accidentally deleted by a `find -name` cleanup, or had files re-encoded with line-ending changes that break byte-equality. The contract makes these failures loud: `oracle-preflight-doctor.sh` refuses to certify if any check fails.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/fixture_root_contract.rs` — the `FixtureRootContract` struct definition (MINING-2 §14)
- `tests/fixtures/manifest.txt` — the manifest file whose SHA-256 is pinned in the contract
- `tests/fixtures/<category>/` — per-category subdirectories with hash-locked roots
- The fixture contract is hashed into every Differential V2 envelope as part of `EngineVersions`.

## Verbatim shape — the struct

From MINING-2 §14, verbatim:

```rust
pub struct FixtureRootContract {
    pub manifest_sha256: String,
    pub fixture_directory: PathBuf,
    pub accepted_aliases: Vec<String>,
    pub cardinality_floors: CardinalityFloors,
    pub required_category_families: Vec<String>,
    pub hash_locked_roots: Vec<(PathBuf, String)>,
    pub included_extensions: Vec<String>,
    pub expected_root_content_hash: Option<String>,
    pub minimum_included_files: usize,
}
```

### `CardinalityFloors` shape (per-class; see Per-class instantiation)

```rust
pub struct CardinalityFloors {
    // Per-category minimum file counts. Keys are category-family names from
    // [fixture_corpus.required_category_families]. Below-floor → red verdict.
    pub per_family: BTreeMap<String, usize>,
}
```

### Verification (canonical form)

```rust
impl FixtureRootContract {
    pub fn verify(&self) -> Result<(), Vec<FixtureViolation>> {
        let mut v = Vec::new();
        // 1. manifest SHA-256
        let actual = sha256_hex_of_file(&self.fixture_directory.join("manifest.txt"))?;
        if actual != self.manifest_sha256 { v.push(FixtureViolation::ManifestHashDrift { expected: self.manifest_sha256.clone(), actual }); }
        // 2. cardinality floors per family
        for (family, floor) in &self.cardinality_floors.per_family {
            let count = count_files_in_family(&self.fixture_directory, family)?;
            if count < *floor { v.push(FixtureViolation::CardinalityViolation { family: family.clone(), floor: *floor, actual: count }); }
        }
        // 3. required category families present
        for family in &self.required_category_families {
            if !family_dir_exists(&self.fixture_directory, family) { v.push(FixtureViolation::MissingFamily { family: family.clone() }); }
        }
        // 4. hash-locked roots
        for (root_path, expected_hash) in &self.hash_locked_roots {
            let actual = top_level_content_hash(root_path)?;
            if &actual != expected_hash { v.push(FixtureViolation::RootHashDrift { root: root_path.clone(), expected: expected_hash.clone(), actual }); }
        }
        // 5. extension allowlist
        for entry in WalkDir::new(&self.fixture_directory) {
            let entry = entry?;
            if entry.file_type().is_file() {
                let ext = entry.path().extension().and_then(|s| s.to_str()).unwrap_or("");
                if !self.included_extensions.iter().any(|e| e == ext) { v.push(FixtureViolation::DisallowedExtension { path: entry.into_path() }); }
            }
        }
        // 6. minimum file count
        let total = count_files(&self.fixture_directory)?;
        if total < self.minimum_included_files { v.push(FixtureViolation::BelowMinimumFiles { actual: total, expected: self.minimum_included_files }); }
        if v.is_empty() { Ok(()) } else { Err(v) }
    }
}
```

## Per-class instantiation

| Class | `included_extensions` | `cardinality_floors.per_family` keys |
|---|---|---|
| **SQL** | `["sql", "db", "csv", "json", "snap"]` | `null_semantics_min: 50`, `group_by_min: 30`, `join_min: 100`, `window_function_min: 40`, `pragma_introspection_min: 20`, `recursive_cte_min: 15`, `trigger_min: 25`, `foreign_key_min: 30`, `conflict_resolution_min: 20`, `compound_select_min: 15`, `attach_temp_min: 10`, `alter_table_rename_min: 15` |
| **RESP** | `["resp", "rdb", "aof", "json"]` | `command_min: 200`, `pipeline_min: 50`, `pubsub_min: 20`, `stream_min: 30`, `cluster_min: 15`, `rdb_byte_fixture_min: 25`, `aof_byte_fixture_min: 25` |
| **Numerical** | `["npy", "npz", "json"]` | `ufunc_min: 100`, `reduction_min: 40`, `broadcast_min: 30`, `dtype_promotion_min: 50`, `rng_stream_min: 20`, `linalg_min: 30` |
| **ML** | `["pt", "safetensors", "json"]` | `tensor_op_min: 100`, `autograd_min: 50`, `optimizer_step_min: 30`, `transformer_block_min: 15`, `gradient_bundle_min: 40`, `state_dict_fixture_min: 20` |
| **HTTP** | `["http", "json", "yaml"]` | `route_transcript_min: 100`, `validation_error_min: 50`, `openapi_golden_min: 10`, `middleware_stack_min: 15`, `extractor_min: 30` |

### `required_category_families` per class (SQL example, verbatim from `assets/version-contract-template.toml`)

```toml
families = [
  "null_semantics", "three_valued_logic", "group_by_having", "recursive_cte",
  "join_type", "trigger", "returning", "generated_columns", "window_function",
  "pragma", "like_glob_escape", "subquery", "numeric_arithmetic", "blob_io",
  "foreign_key", "check_constraint", "conflict_resolution", "compound_select",
  "default_value", "attach_temp", "alter_table_rename"
]
```

## Composition

- [pattern:10-REFERENCE-PINNING](10-REFERENCE-PINNING.md) — `[fixture_corpus]` table in the version contract is the source of every field in this struct.
- [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md) — `FixtureRootContract::verify()` produces the `FixtureCardinalityViolation` / `FixtureManifestHashDrift` remediation classes.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — `manifest_sha256` is embedded in every envelope and contributes to the `artifact_id`.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — `fixture_id` field in the bundle indexes into the corpus governed by this contract.

## Pitfalls

- **Manifest file generated on-the-fly.** The manifest must be a committed file (`tests/fixtures/manifest.txt`) listing every fixture path with its SHA-256. Generating it at preflight time defeats the contract — the contract is comparing the recomputed disk hash against a pinned value.
- **`accepted_aliases` empty.** Useful when the fixture directory is mounted at different paths across hosts (`/data/projects/.../fixtures` vs `/home/runner/.../fixtures`). Without the alias list, CI doesn't recognize the corpus.
- **`hash_locked_roots` for the entire fixture tree.** This is too coarse — any single-file edit invalidates the whole tree's hash. Lock the *boundaries* between subsystems (e.g., `tests/fixtures/null_semantics/` as a unit) so authors can edit one category without disturbing others.
- **Below-floor cardinality silently allowed because "the deleted fixtures were obsolete".** No. If a fixture is obsolete, remove it from `required_category_families` AND lower the floor in `cardinality_floors`, in the same commit that deletes the files. Floors are versioned alongside corpus changes.
- **Extension allowlist includes `*`.** A wildcard defeats the allowlist's purpose (catching `.swp` files, editor backups, accidentally-checked-in binaries). Keep the list small and exhaustive.
- **`expected_root_content_hash` set to `None` "for now".** The whole tree hash is a cheap canary; setting it to None disables an entire layer of drift detection. Fill it on first commit even if you have to recompute and bump the version-contract `revision` later.
- **Verifying the contract once at process start.** Same pitfall as [pattern:20-ORACLE-PREFLIGHT-DOCTOR](20-ORACLE-PREFLIGHT-DOCTOR.md): a concurrent agent can `rm -rf` mid-run. Re-verify at every certification lane entry (the hash check is cheap; the cardinality check scales linearly with corpus size).
