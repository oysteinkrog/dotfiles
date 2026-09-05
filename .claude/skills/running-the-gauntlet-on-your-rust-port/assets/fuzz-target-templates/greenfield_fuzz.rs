//! greenfield_fuzz.rs — paste-ready Greenfield-Rust-class differential-fuzz
//! target. Differential against the round-trip oracle (Mode 4 of the 5
//! greenfield oracle modes per references/methodology/GREENFIELD-ADAPTATION.md
//! § 8).
//!
//! Copy into `fuzz/fuzz_targets/fuzz_<feature>_roundtrip.rs` after running
//!   `cargo +nightly fuzz init`
//!   `cargo +nightly fuzz add fuzz_<feature>_roundtrip`
//!
//! For projects that explicitly opt out of fuzz/ via Cargo.toml `[workspace]
//! exclude = ["fuzz"]` (e.g., eidetic per its single-crate layout — see
//! references/cookbook/single-crate-vs-workspace-decision.md), this file
//! still lives at fuzz/fuzz_targets/; cargo-fuzz creates its own nested
//! sub-package so the exclusion is correct.
//!
//! fuzz/Cargo.toml dependencies:
//!   libfuzzer-sys = "0.4"
//!   arbitrary     = { version = "1", features = ["derive"] }
//!   <your-project> = { path = "../" }
//!
//! Pairs with:
//!   - assets/integration-test-templates/greenfield_oracle_e2e.rs (the
//!     30-line scenario() template; this fuzz target drives `RoundTrip` mode)
//!   - assets/property-test-templates/greenfield_proptest.rs (the proptest
//!     analog; fuzz catches inputs the proptest's bounded strategies miss)
//!   - references/first-bug-hunt/greenfield-rust-class.md § 3 (round-trip
//!     identity violations — the canonical bug class this target hunts)

#![no_main]

use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;

// ===== Structure-aware input — narrow to the project's round-trip surface =====
//
// Per FUZZ-TOOLCHAIN.md §3.3: the art of structure-aware fuzz is making the
// input type as narrow as possible while still generating diverse inputs.
// We bound list lengths and select from a small enum of "kinds" so the
// fuzzer spends its energy on the semantic edges of the encoder/decoder,
// not on syntactic noise.

#[derive(Arbitrary, Debug, Clone)]
pub struct RoundTripInput {
    pub kind: PayloadKind,
    pub body: Vec<u8>,
    pub tag: u8,
}

#[derive(Arbitrary, Debug, Clone, Copy)]
pub enum PayloadKind {
    /// A binary blob — exercises the encoder's framing.
    Blob,
    /// A UTF-8 string — exercises NFC/NFD normalization round-trips
    /// (bug #3 in references/first-bug-hunt/greenfield-rust-class.md).
    Utf8,
    /// A list of f64 values — exercises subnormal-float round-trips
    /// (the other half of bug #3).
    Floats,
    /// An empty payload — exercises the encoder's zero-length contract.
    Empty,
}

// Convert the structure-aware input into the byte form the subject's
// encoder expects. Narrow enough that random Vec<u8> generation hits
// real semantic boundaries.

fn normalize_input(input: &RoundTripInput) -> Vec<u8> {
    match input.kind {
        PayloadKind::Blob => input.body.iter().take(1024).copied().collect(),
        PayloadKind::Utf8 => {
            // Take valid UTF-8 prefix; if none, fall back to ASCII.
            let s = String::from_utf8_lossy(&input.body[..input.body.len().min(512)])
                .to_string();
            s.into_bytes()
        }
        PayloadKind::Floats => {
            // Each chunk of 8 bytes becomes one f64; include subnormals,
            // infinities, NaN.
            let mut out = Vec::new();
            for chunk in input.body.chunks(8).take(64) {
                if chunk.len() == 8 {
                    let mut buf = [0u8; 8];
                    buf.copy_from_slice(chunk);
                    let _f = f64::from_le_bytes(buf);
                    out.extend_from_slice(&buf);
                }
            }
            out
        }
        PayloadKind::Empty => Vec::new(),
    }
}

// Subject stubs — replace with the real encoder/decoder pair declared in
// spec_version_contract.toml#[[roundtrip_corpus]].

mod subject {
    pub fn encode(bytes: &[u8]) -> Vec<u8> {
        // Real impl: project's encode function for the (encode, decode) pair.
        bytes.to_vec()
    }
    pub fn decode(bytes: &[u8]) -> Result<Vec<u8>, String> {
        // Real impl: project's decode function.
        Ok(bytes.to_vec())
    }
}

// ===== EngineIdentity guard for the round-trip oracle =====
//
// SUBJECT is the current code at HEAD; ORACLE is "round-trip" (the
// identity contract). Per pattern:15-ENGINE-IDENTITY, the two MUST be
// distinct — `assert_ne!(SUBJECT, ORACLE)` at every entry point.

const SUBJECT_IDENTITY_LABEL: &str = "<project>";
const ORACLE_IDENTITY_LABEL: &str = "round-trip";

// ===== Differential driver =====
//
// Verbatim shape from FUZZ-TOOLCHAIN §4: any input that produces
// `decode(encode(x)) != x` (or panics, or fails to decode what encode
// produced) is a bug. libfuzzer minimizes the input and saves the
// crash to fuzz/artifacts/fuzz_<feature>_roundtrip/crash-<sha>.
//
// Triage via the mismatch-minimizer in ORACLE-TOOLCHAIN §12 +
// references/first-bug-hunt/greenfield-rust-class.md § 3 fix pattern.

fuzz_target!(|input: RoundTripInput| {
    assert_ne!(SUBJECT_IDENTITY_LABEL, ORACLE_IDENTITY_LABEL,
        "EngineIdentity self-comparison violation");

    let normalized = normalize_input(&input);

    // 1. Encode.
    let encoded = subject::encode(&normalized);

    // 2. Decode.
    let decoded = match subject::decode(&encoded) {
        Ok(d) => d,
        Err(e) => {
            // Decode failure on output of our own encoder is ALWAYS a bug.
            // No "both-error agreement" exit here — the encoder produced
            // bytes the decoder rejected.
            panic!(
                "ROUND-TRIP DECODE FAILURE\n  kind: {:?}\n  input_len: {}\n  encoded_len: {}\n  decode_err: {}",
                input.kind, normalized.len(), encoded.len(), e
            );
        }
    };

    // 3. Identity check.
    if normalized != decoded {
        // Find the first-divergence offset for first_divergence_jsonptr-style
        // localization (pattern:95-FIRST-FAILURE-EXPLAINER).
        let first_div = normalized.iter().zip(decoded.iter())
            .position(|(a, b)| a != b)
            .unwrap_or(normalized.len().min(decoded.len()));

        panic!(
            "ROUND-TRIP IDENTITY VIOLATION\n  kind: {:?}\n  input_len: {}\n  decoded_len: {}\n  first_divergence_offset: {}\n  input:   {:?}\n  decoded: {:?}",
            input.kind,
            normalized.len(),
            decoded.len(),
            first_div,
            &normalized[..normalized.len().min(64)],
            &decoded[..decoded.len().min(64)],
        );
    }

    // 4. Double-round-trip — idempotency on second pass. encode(decode
    //    (encode(x))) MUST equal encode(x); a divergence here surfaces
    //    encoder-state bugs (encoder behaves differently on re-entry).
    let re_encoded = subject::encode(&decoded);
    if encoded != re_encoded {
        panic!(
            "ENCODER NON-IDEMPOTENT\n  kind: {:?}\n  encoded_len: {}\n  re_encoded_len: {}",
            input.kind, encoded.len(), re_encoded.len()
        );
    }
});

// ===== How this fits into the gauntlet's 5-mode oracle =====
//
// This fuzz target is the RUNTIME of `OracleMode::RoundTrip { encoder,
// decoder }` from assets/integration-test-templates/greenfield_oracle_e2e.rs.
// The proptest version exercises bounded inputs (256-1024 cases per CI
// run); this fuzz target exercises the long tail (millions of cases per
// soak run per references/methodology/SOAK-PROTOCOL.md).
//
// Per references/methodology/SPEC-PINNING-FOR-GREENFIELD.md § 2
// [[roundtrip_corpus]]: every (encoder, decoder) pair in the project gets
// its own fuzz target. Naming convention: `fuzz_<pair_name>_roundtrip.rs`
// (e.g., `fuzz_context_pack_roundtrip.rs`, `fuzz_embedding_v1_roundtrip.rs`).
//
// Soak schedule (per Phase 15 soak protocol):
//   - Continuous: 5-minute smoke per CI run
//   - Nightly: 1-hour run with seed corpus from proptest-regressions/
//   - Weekly: 24-hour run; any crash files a high-priority bead
//
// Cross-link:
//   - references/methodology/GREENFIELD-ADAPTATION.md § 8 Round-trip-Oracle
//   - references/first-bug-hunt/greenfield-rust-class.md § 3
//   - assets/property-test-templates/greenfield_proptest.rs (Property 1)
//   - patterns/40-METAMORPHIC-TRANSFORMS.md § Literal (TransformFamily)
//   - patterns/95-FIRST-FAILURE-EXPLAINER.md (first_divergence_jsonptr)
