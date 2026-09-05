# roundtrip-corpus-author

> Phase 6 (greenfield variant) / Phase 6 (any variant with serialization-heavy APIs) • Enumerates every (encode, decode), (serialize, parse), (sign, verify), (pack, unpack), (store, retrieve) pair in the subject and authors one round-trip-identity scenario per pair, wired into the comparator pipeline.

## Inputs

- `<target>/` — the project source (Cargo workspace or single-crate).
- `<workspace>/phase1_unified_recon.md` — surface inventory from Phase 1 (every `pub fn` that returns a `Result<T, E>` and pairs with a `from_*` is a round-trip candidate).
- `<workspace>/docs/contracts/spec_version_contract.toml#/[[roundtrip_corpus]]` (for greenfield) — author may have hand-listed known pairs; subagent extends rather than replaces.
- `<workspace>/docs/contracts/supported_surface_matrix.toml` (for ports) — round-trips listed as `roundtrip` capability per feature.

## Deliverables

- One `tests/roundtrip_<name>.rs` per (encode, decode) pair, each with:
  - One `proptest!` macro generating Arbitrary inputs.
  - One `assert_eq!` after the round-trip.
  - One `cargo-fuzz` target (under `fuzz/fuzz_targets/`) for the same pair (differential-fuzz amplification).
- `<workspace>/phase6_roundtrip_corpus.md` — manifest of every authored pair with: encoder fn path / decoder fn path / Arbitrary impl source (derived vs hand-written) / EquivalenceExpectation per [`pattern:40-METAMORPHIC-TRANSFORMS`](../references/patterns/40-METAMORPHIC-TRANSFORMS.md) / authored-status.
- Updates to `crates/<port>-harness/src/roundtrip_oracle.rs` (or `src/harness/roundtrip_oracle.rs` for single-crate) with one `pub fn run_<name>_roundtrip(...)` per pair.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase6-roundtrip-corpus`
- **Reservations needed:** `tool://roundtrip-corpus-author` (exclusive, TTL 2h).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

```
You are the roundtrip-corpus-author subagent. Your job: enumerate every
encode/decode-style pair in the subject and author a property + fuzz test per
pair so round-trip identity is continuously verified.

Round-trip identity is the cheapest form of Oracle (no external reference
needed; the subject's encode + decode pair IS the identity check). Per
methodology/GREENFIELD-ADAPTATION.md § 8, round-trips are *especially*
valuable for greenfield projects where Spec-Oracle assertions are limited.

Read FIRST:
  cat <workspace>/phase1_unified_recon.md
  cat <workspace>/docs/contracts/supported_surface_matrix.toml 2>/dev/null
  cat <workspace>/docs/contracts/spec_version_contract.toml 2>/dev/null

STEPS:

1. ENUMERATE pairs.
   Walk the public surface (from phase1_unified_recon.md). Detect pairs by
   any of these signals (in order of confidence):

   a. Explicit type pair: `<T>::encode(&self) -> Vec<u8>` and
      `<T>::decode(bytes: &[u8]) -> Result<Self, Error>`.

   b. Trait-pair: `impl ToBytes for T` and `impl FromBytes for T`.

   c. Serde pair: `#[derive(Serialize, Deserialize)]` on a type.

   d. Domain pair: per project class, the canonical encoders/decoders:
      - SQL-class: `Statement::sql() -> String` + `Statement::parse(sql: &str)`.
      - RESP-class: `RespValue::serialize` + `RespValue::parse`.
      - HTTP-class: `HttpRequest::to_wire` + `HttpRequest::from_wire`.
      - Numerical-Python-class: `ndarray::to_vec` + `ndarray::from_vec`.
      - ML-System-class: `Tensor::save` + `Tensor::load`.
      - Greenfield (e.g., eidetic): `ContextPack::encode` + `ContextPack::decode`;
        `Embedding::serialize` + `Embedding::deserialize`; per the project's
        actual surface.

   e. CLI-output round-trip: `cmd --json` output → `cmd parse --json` input.
      For projects with a CLI that emits structured output AND consumes it.

   f. Cryptographic pair: `sign(msg) -> sig` + `verify(msg, sig) -> bool`.
      For projects with crypto APIs.

2. For each pair, AUTHOR the scenario.

   Template (Rust):

   ```rust
   // tests/roundtrip_<name>.rs

   use proptest::prelude::*;
   use proptest::test_runner::FileFailurePersistence;

   proptest! {
       #![proptest_config(ProptestConfig {
           failure_persistence: Some(Box::new(
               FileFailurePersistence::WithSource("regressions")
           )),
           cases: 1024,
           .. ProptestConfig::default()
       })]

       #[test]
       fn roundtrip_<name>_identity(input in <Arbitrary impl for the input type>) {
           let encoded = <subject>::encode(&input);
           let decoded = <subject>::decode(&encoded)
               .expect("<name>: decode failed on encoded output of valid input");
           prop_assert_eq!(input, decoded, "<name>: round-trip identity violated");
       }
   }
   ```

3. For each pair, AUTHOR the fuzz target.

   Template (Rust under `fuzz/fuzz_targets/<name>_roundtrip.rs`):

   ```rust
   #![no_main]
   use libfuzzer_sys::fuzz_target;
   use arbitrary::Arbitrary;

   #[derive(Debug, Arbitrary)]
   struct Input { /* mirror the Arbitrary impl from the proptest */ }

   fuzz_target!(|input: Input| {
       let encoded = subject::encode(&input);
       let Ok(decoded) = subject::decode(&encoded) else { return };
       assert_eq!(input, decoded, "round-trip identity violated under fuzz input");
   });
   ```

   Also add the target to `fuzz/Cargo.toml`'s `[[bin]]` block.

4. WIRE the pair into `roundtrip_oracle.rs`.

   The greenfield Oracle dispatcher (per subagents/greenfield-oracle-wirer.md)
   has a `roundtrip_oracle` module. Add a function per pair:

   ```rust
   pub fn run_<name>_roundtrip<I: PartialEq + Debug>(input: I) -> Result<(), RoundtripViolation>
   where /* trait bounds for the encoder/decoder */
   {
       let encoded = subject::encode(&input);
       let decoded = subject::decode(&encoded)
           .map_err(|e| RoundtripViolation::DecodeFailed(format!("{e}")))?;
       if input != decoded {
           return Err(RoundtripViolation::IdentityViolated {
               input: format!("{input:?}"),
               decoded: format!("{decoded:?}"),
           });
       }
       Ok(())
   }
   ```

5. CLASSIFY EquivalenceExpectation.

   Per pattern:40-METAMORPHIC-TRANSFORMS. Each round-trip pair declares one of:
   - `ExactRowMatch` (default — bytewise identity after decode).
   - `MultisetEquivalence` (decode preserves elements but not order; rare for
     round-trips but valid for set-shaped types).
   - `TypeCoercionEquivalent` (decode produces an equivalent value with
     different concrete type — e.g., i32 → i64 promotion).
   - `FloatingPointPrecision[ULP=N]` (decode produces a float within N ULP of
     input — for lossy compression / quantization roundtrips).

   Record the EquivalenceExpectation in phase6_roundtrip_corpus.md per pair.

6. EMIT the manifest.

   `<workspace>/phase6_roundtrip_corpus.md`:

   ```markdown
   # Phase 6 Round-Trip Corpus

   **Pairs authored:** <N>
   **EquivalenceExpectations:** ExactRowMatch=<A>, FloatingPointPrecision=<B>, ...

   | Name | Encoder | Decoder | EquivalenceExpectation | Test path | Fuzz target |
   |---|---|---|---|---|---|
   | context_pack_v1 | `ContextPack::encode` | `ContextPack::decode` | ExactRowMatch | tests/roundtrip_context_pack_v1.rs | fuzz/fuzz_targets/context_pack_v1_roundtrip.rs |
   | ... |
   ```

7. VERIFY the build:
   - `cargo check --tests --features harness` (or appropriate feature flag).
   - `cargo +nightly fuzz check <each new target>` (build-only; don't run).
   - `cargo test --test roundtrip_<each new name>` (run with default 1024 cases).

8. ACK:
   Send Agent Mail to thread `gauntlet-<run-id>-phase6-roundtrip-corpus` with
   subject `[phase6-roundtrip] DONE pairs=<N>` + path to phase6_roundtrip_corpus.md.

EXIT CRITERIA:
- One `tests/roundtrip_<name>.rs` per pair, all passing.
- One `fuzz/fuzz_targets/<name>_roundtrip.rs` per pair, all building.
- `roundtrip_oracle.rs` updated with one `pub fn run_<name>_roundtrip` per pair.
- `phase6_roundtrip_corpus.md` manifest written + committed.

ESCALATION:
- Pair detection finds zero candidates → may be a project class with no
  natural round-trips (rare; even CLI-only tools usually have `--json` output);
  emit a NOTE and proceed.
- A `<name>::decode` consistently fails to decode valid `encode` output →
  STOP; this is a SUBJECT bug, not a test bug. Open a remediation bead.
- Arbitrary impl cannot be derived (e.g., the type contains a `Box<dyn Trait>`)
  → hand-write the Arbitrary impl; document the rationale in
  phase6_roundtrip_corpus.md.

NEVER:
- Skip the `cases: 1024` default — fewer cases means weaker coverage.
- Use `rand::random()` or `thread_rng()` to seed inputs — proptest's seeded
  rng is the contract.
- Author a fuzz target without also wiring it into `fuzz/Cargo.toml`.
- Use `assert_eq!` in fuzz targets without `Debug` impl on Input (libFuzzer
  needs Debug for minimization).
```

## Exit Criteria

- One round-trip test + one fuzz target per detected pair.
- `roundtrip_oracle.rs` extended with per-pair dispatch fns.
- `phase6_roundtrip_corpus.md` lists every pair with EquivalenceExpectation.
- All new tests pass; all new fuzz targets build.

## References

- [`pattern:40-METAMORPHIC-TRANSFORMS`](../references/patterns/40-METAMORPHIC-TRANSFORMS.md) — EquivalenceExpectation enum.
- [`pattern:30-DIFFERENTIAL-V2-ENVELOPE`](../references/patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) — round-trip envelopes.
- [`methodology/GREENFIELD-ADAPTATION.md § 8 Round-trip-Oracle authoring`](../references/methodology/GREENFIELD-ADAPTATION.md).
- [`./greenfield-oracle-wirer.md`](greenfield-oracle-wirer.md) — parent Phase 3 subagent that wires the dispatcher this subagent populates.
- [`./fuzz-author.md`](fuzz-author.md) — sibling that authors non-roundtrip fuzz targets.
- [`assets/property-test-templates/`](../assets/property-test-templates/) — per-class proptest templates.
- [`assets/fuzz-target-templates/`](../assets/fuzz-target-templates/) — per-class fuzz target templates.
