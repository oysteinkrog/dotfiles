//! Recovery-verifier — per-class consistency-or-no-partial verifier.
//!
//! Given a crash-recovery state, asserts the canonical post-crash invariant:
//!   "every named effect is either fully present or fully absent — there is
//!    no partially-applied state observable to a subsequent reader."
//!
//! This is the verbatim shape from references/patterns/65-CRASH-BOUNDARIES.md
//! and ORACLE-TOOLCHAIN.md § crash-boundary protocol injection. Per-class
//! implementations live in `per_class/` — they consume the post-recovery
//! state of the subject and produce a `RecoveryState` for this crate to
//! verify against the expected-committed set the test author declared
//! before the crash was armed.
//!
//! Usage shape:
//!
//! ```ignore
//! use recovery_verifier::{assert_consistency_or_no_partial, RecoveryState};
//!
//! // Test author declares what they intend to commit.
//! let expected_committed = vec!["row#1", "row#2", "row#3"];
//!
//! // Crash is armed at a boundary (e.g., AfterFsyncBeforePublish).
//! arm_crash_boundary(CrashBoundary::AfterFsyncBeforePublish);
//! // ... do the work that crashes mid-flight ...
//!
//! // After recovery, the per-class verifier reads the recovered state.
//! let state = my_sql_verifier.read_post_recovery_state();
//!
//! // The invariant: every row is either fully committed or fully absent.
//! // (NOT "every expected row was committed" — that's a stronger claim that
//! // depends on the crash boundary. The weaker no-partial claim is what
//! // applies to every boundary.)
//! assert_consistency_or_no_partial(&state, &expected_committed);
//! ```

use serde::{Deserialize, Serialize};
use std::fmt;

// Per-class implementations live under `src/per_class/`. Each module is
// gated behind a Cargo feature so adopters compile only the classes they
// need. Declarations use `#[path]` so this crate's tree stays flat — there
// is no `per_class/mod.rs`; each submodule file is declared directly here.
#[cfg(feature = "sql_class")]
#[path = "per_class/sql.rs"]
pub mod sql;

#[cfg(feature = "resp_class")]
#[path = "per_class/resp.rs"]
pub mod resp;

#[cfg(feature = "ml_class")]
#[path = "per_class/ml.rs"]
pub mod ml;

// ===== Core types =====

/// Identity of a single committed-unit. The shape is opaque to this crate;
/// per-class verifiers choose what a unit means:
///   - SQL: a row primary key + table name
///   - RESP: a key + (AOF offset, RDB offset) pair
///   - ML: a checkpoint shard SHA-256
pub type UnitId = String;

/// State recovered from the subject after a crash.
///
/// Per-class verifiers populate this struct by reading the post-recovery
/// state of the subject through its public interface. The `committed_keys`
/// MUST contain only units that were observably-present after recovery;
/// `partial_keys` MUST contain any unit that is observably-incomplete.
///
/// The kernel invariant `partial_keys.is_empty()` is the "no partial state"
/// claim — passing that gate is mandatory for every named CrashBoundary.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct RecoveryState {
    pub committed_keys: Vec<UnitId>,
    pub partial_keys: Vec<UnitId>,
    /// Optional metadata for richer triage (per-class adopters fill).
    #[serde(default)]
    pub diagnostic: serde_json::Value,
}

impl RecoveryState {
    pub fn new() -> Self { Self::default() }

    pub fn record_committed(&mut self, id: impl Into<UnitId>) {
        self.committed_keys.push(id.into());
    }

    pub fn record_partial(&mut self, id: impl Into<UnitId>) {
        self.partial_keys.push(id.into());
    }
}

/// Named crash boundary. The per-class enum (see per_class/sql.rs etc.)
/// narrows this to a specific lifecycle phase. The string form is what
/// `RecoveryError` and any FailureBundle emit.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct CrashBoundary(pub String);

impl CrashBoundary {
    pub fn new(name: impl Into<String>) -> Self { Self(name.into()) }
}

impl fmt::Display for CrashBoundary {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.write_str(&self.0) }
}

// ===== Verifier trait =====

/// Per-class verifier contract. Implementations live in `per_class/`.
///
/// The trait deliberately keeps two operations separate:
///   1. `read_post_recovery_state` — observe the subject after recovery.
///      MUST be pure-read; no mutation, no PRAGMA changes, no implicit
///      replay. The test author already crashed-and-recovered; this is
///      the snapshot.
///   2. `verify_no_partial` — check the no-partial invariant for the
///      boundary at hand. Default implementation calls
///      `assert_consistency_or_no_partial` with the recovered state.
pub trait RecoveryVerifier {
    type Reader;

    /// Class-specific reader that materializes a `RecoveryState` from the
    /// post-recovery subject (e.g., a `rusqlite::Connection` already opened
    /// against the recovered file, or a `RedisClient` connected to the
    /// restarted server, or a checkpoint manifest reader).
    fn read_post_recovery_state(&self, reader: &Self::Reader) -> RecoveryState;

    /// Default no-partial check; per-class implementors may override to
    /// add class-specific assertions on top of the kernel one.
    fn verify_no_partial(
        &self,
        boundary: &CrashBoundary,
        state: &RecoveryState,
        expected_committed: &[UnitId],
    ) -> Result<(), RecoveryError> {
        check_consistency_or_no_partial(boundary, state, expected_committed)
    }
}

// ===== Error type =====

#[derive(Debug, thiserror::Error)]
pub enum RecoveryError {
    #[error("crash boundary {boundary}: partial state observed: {partial_count} key(s)\n  partial: {sample:?}")]
    PartialStateObserved {
        boundary: String,
        partial_count: usize,
        sample: Vec<UnitId>,
    },
    #[error("crash boundary {boundary}: committed unit not in expected set: {unit}")]
    UnexpectedCommit {
        boundary: String,
        unit: UnitId,
    },
}

// ===== Public assertion API =====

/// THE kernel invariant — "consistency-or-no-partial" per
/// pattern:65-CRASH-BOUNDARIES.
///
/// Returns Ok(()) iff:
///   1. `state.partial_keys.is_empty()` — no observably-partial unit, AND
///   2. every key in `state.committed_keys` is a subset of
///      `expected_committed` — the recovery may have skipped (lost) some
///      intended-committed units (that is allowed for some boundaries) but
///      MUST NOT have invented commits that the test author never started.
///
/// Per the verbatim quote from MINING-2 §9: the invariant is
/// **"not 'right state' but 'committed-or-not-committed-no-partial'"**.
/// Different boundaries have different "right state" expectations
/// (BeforeWalHeaderWrite recovers to empty; AfterCheckpoint recovers to
/// fully-committed); the universal claim is no-partial.
pub fn check_consistency_or_no_partial(
    boundary: &CrashBoundary,
    state: &RecoveryState,
    expected_committed: &[UnitId],
) -> Result<(), RecoveryError> {
    if !state.partial_keys.is_empty() {
        let sample: Vec<UnitId> = state.partial_keys.iter().take(8).cloned().collect();
        return Err(RecoveryError::PartialStateObserved {
            boundary: boundary.to_string(),
            partial_count: state.partial_keys.len(),
            sample,
        });
    }
    let expected: std::collections::HashSet<&UnitId> = expected_committed.iter().collect();
    for unit in &state.committed_keys {
        if !expected.contains(unit) {
            return Err(RecoveryError::UnexpectedCommit {
                boundary: boundary.to_string(),
                unit: unit.clone(),
            });
        }
    }
    Ok(())
}

/// Panicking convenience wrapper. Use in tests.
///
/// Per pattern:65 — this is the assertion that EVERY crash-boundary test
/// makes after recovery; the per-boundary "right state" check is a separate,
/// boundary-specific test that lives next to this one.
pub fn assert_consistency_or_no_partial(
    state: &RecoveryState,
    expected_committed: &[impl AsRef<str>],
) {
    let expected: Vec<UnitId> = expected_committed.iter().map(|s| s.as_ref().to_string()).collect();
    let boundary = CrashBoundary::new("<unspecified>");
    if let Err(e) = check_consistency_or_no_partial(&boundary, state, &expected) {
        panic!("no-partial invariant violated: {e}");
    }
}

// ===== Tests =====

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_state_is_consistent() {
        let state = RecoveryState::new();
        let expected: Vec<String> = vec!["a".into(), "b".into()];
        let r = check_consistency_or_no_partial(&CrashBoundary::new("test"), &state, &expected);
        assert!(r.is_ok());
    }

    #[test]
    fn partial_state_fails() {
        let mut state = RecoveryState::new();
        state.record_committed("a");
        state.record_partial("b");
        let expected: Vec<String> = vec!["a".into(), "b".into()];
        let r = check_consistency_or_no_partial(&CrashBoundary::new("test"), &state, &expected);
        assert!(matches!(r, Err(RecoveryError::PartialStateObserved { .. })));
    }

    #[test]
    fn invented_commit_fails() {
        let mut state = RecoveryState::new();
        state.record_committed("c");
        let expected: Vec<String> = vec!["a".into(), "b".into()];
        let r = check_consistency_or_no_partial(&CrashBoundary::new("test"), &state, &expected);
        assert!(matches!(r, Err(RecoveryError::UnexpectedCommit { .. })));
    }
}
