//! ML-System-class recovery verifier.
//!
//! Reads the post-recovery checkpoint manifest + every named shard, computes
//! the per-shard SHA-256, and asserts every shard's digest matches the
//! manifest entry. A mismatch means a half-written shard — the universal
//! no-partial claim per pattern:65-CRASH-BOUNDARIES.
//!
//! The 5 checkpoint-save crash boundaries (verbatim from MINING-2 §9 /
//! taxonomy/PROJECT-CLASSES.md § ML-System-Class):
//!
//!   BeforeSerialize
//!   MidShardWrite
//!   AfterShardBeforeMetadata
//!   MidMetadataUpdate
//!   AfterRenameBeforeFsync
//!
//! Plus 2 distributed-collective boundaries:
//!
//!   MidAllReduce
//!   BeforeRendezvousAck
//!
//! The distributed boundaries are class-specific (rendezvous + collective
//! state) and live next to this verifier in adopter code, not here.

use crate::{CrashBoundary, RecoveryError, RecoveryState, RecoveryVerifier, UnitId};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const ML_CHECKPOINT_BOUNDARIES: &[&str] = &[
    "BeforeSerialize",
    "MidShardWrite",
    "AfterShardBeforeMetadata",
    "MidMetadataUpdate",
    "AfterRenameBeforeFsync",
];

pub const ML_DISTRIBUTED_BOUNDARIES: &[&str] = &[
    "MidAllReduce",
    "BeforeRendezvousAck",
];

/// On-disk checkpoint manifest. One entry per shard. The manifest is
/// written LAST in the checkpoint-save protocol so its presence implies
/// every named shard's bytes were already fsynced.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CheckpointManifest {
    pub format_version: u32,
    pub shards: Vec<ShardEntry>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ShardEntry {
    /// Stable shard identifier (e.g., "layer.0.weight" or "shard-3-of-8").
    pub shard_id: String,
    /// Filesystem path relative to the checkpoint root.
    pub path: String,
    /// Expected SHA-256 of the shard's bytes, written at manifest-flush time.
    pub sha256_hex: String,
    /// Expected length in bytes.
    pub bytes: u64,
}

/// The verifier holds the manifest + a closure that reads shard bytes.
/// The closure is per-test so adopters can mock the filesystem (testing
/// behavior under torn writes) or read from S3 (post-recovery from a
/// distributed checkpoint).
pub struct MlRecoveryVerifier {
    pub manifest: CheckpointManifest,
}

/// Adopter-side reader contract.
pub trait ShardReader {
    fn read_shard(&self, path: &str) -> Result<Vec<u8>, String>;
}

pub struct MlReaderHandle<'a>(pub &'a dyn ShardReader);

impl RecoveryVerifier for MlRecoveryVerifier {
    type Reader = MlReaderHandle<'static>;

    fn read_post_recovery_state(&self, reader: &Self::Reader) -> RecoveryState {
        self.read_with_reader(reader.0)
    }
}

impl MlRecoveryVerifier {
    /// Inner shape that's usable without forcing a 'static reader.
    pub fn read_with_reader(&self, reader: &dyn ShardReader) -> RecoveryState {
        let mut state = RecoveryState::new();
        for shard in &self.manifest.shards {
            match reader.read_shard(&shard.path) {
                Ok(bytes) => {
                    let actual_len = bytes.len() as u64;
                    let actual_hash = sha256_hex(&bytes);
                    if actual_len != shard.bytes {
                        state.record_partial(format!(
                            "{}: length mismatch (manifest={}, on-disk={})",
                            shard.shard_id, shard.bytes, actual_len
                        ));
                    } else if actual_hash != shard.sha256_hex {
                        state.record_partial(format!(
                            "{}: SHA-256 mismatch (manifest={}, on-disk={})",
                            shard.shard_id, shard.sha256_hex, actual_hash
                        ));
                    } else {
                        state.record_committed(shard.shard_id.clone());
                    }
                }
                Err(e) => {
                    state.record_partial(format!("{}: read error: {e}", shard.shard_id));
                }
            }
        }
        state
    }
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    let digest = h.finalize();
    let mut s = String::with_capacity(digest.len() * 2);
    for b in digest { s.push_str(&format!("{b:02x}")); }
    s
}

/// Convenience: iterate checkpoint boundaries.
pub fn verify_all_checkpoint_boundaries<F>(
    mut arm_recover_read: F,
    expected_committed: &[UnitId],
) -> Result<(), RecoveryError>
where
    F: FnMut(&str) -> (MlRecoveryVerifier, Box<dyn ShardReader>),
{
    for boundary_name in ML_CHECKPOINT_BOUNDARIES {
        let (verifier, reader) = arm_recover_read(boundary_name);
        let state = verifier.read_with_reader(reader.as_ref());
        let boundary = CrashBoundary::new(*boundary_name);
        verifier.verify_no_partial(&boundary, &state, expected_committed)?;
    }
    Ok(())
}
