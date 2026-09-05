//! SQL-class recovery verifier.
//!
//! Reads the post-recovery database via the port's `Connection` and walks
//! every row in every named-by-test table. For each named CrashBoundary,
//! asserts that no row exists in a partially-committed state — every row
//! is either fully present (all declared columns populated to the
//! pre-crash intent) or fully absent.
//!
//! The 8 named SQL-class crash boundaries (verbatim from MINING-2 §9 /
//! taxonomy/PROJECT-CLASSES.md § SQL-Class):
//!
//!   BeforeWalHeaderWrite
//!   BeforeWalFrameAppend
//!   AfterWalFrameAppendBeforeFsync
//!   AfterFsyncBeforePublish
//!   BetweenPageTableRebuildSteps
//!   AfterPublishBeforeCheckpoint
//!   MidCheckpoint
//!   AfterCheckpoint
//!
//! Per-boundary "right state" expectations are the caller's responsibility
//! (some boundaries recover to empty, others to fully-committed). What this
//! verifier guarantees is the **universal no-partial claim** across all
//! eight.

use crate::{CrashBoundary, RecoveryError, RecoveryState, RecoveryVerifier, UnitId};

/// The 8 named SQL-class boundaries. Strings here MUST match the boundary
/// names used in the fault-VFS arming code so the same identifier flows
/// through `FailureBundle::boundary` end-to-end.
pub const SQL_CRASH_BOUNDARIES: &[&str] = &[
    "BeforeWalHeaderWrite",
    "BeforeWalFrameAppend",
    "AfterWalFrameAppendBeforeFsync",
    "AfterFsyncBeforePublish",
    "BetweenPageTableRebuildSteps",
    "AfterPublishBeforeCheckpoint",
    "MidCheckpoint",
    "AfterCheckpoint",
];

/// Adopter-side configuration. The verifier needs to know which tables to
/// scan and how to interpret a "partial" row (e.g., a NOT NULL column with
/// a sentinel meaning the writer crashed mid-commit). Most ports populate
/// this from a per-test fixture file.
pub struct SqlSchemaContract {
    /// Tables to scan after recovery. Each entry is `(table_name, pk_column)`.
    pub tables: Vec<(String, String)>,
    /// Row-level partial-detector. Given a row's (column → value) map,
    /// returns true iff the row looks half-written. Most ports key off a
    /// "sentinel" column that's set last in the commit protocol.
    pub is_partial: fn(&serde_json::Map<String, serde_json::Value>) -> bool,
}

/// The verifier. `Reader = ConnectionLike` — bring your own connection
/// type via the `ConnectionLike` trait.
pub struct SqlRecoveryVerifier {
    pub contract: SqlSchemaContract,
}

/// Trait the adopter implements for their post-recovery connection.
/// Pure-read; no PRAGMA changes; no replay.
pub trait ConnectionLike {
    fn query_rows(
        &self,
        sql: &str,
    ) -> Result<Vec<serde_json::Map<String, serde_json::Value>>, String>;
}

impl RecoveryVerifier for SqlRecoveryVerifier {
    type Reader = Box<dyn ConnectionLike>;

    fn read_post_recovery_state(&self, reader: &Self::Reader) -> RecoveryState {
        let mut state = RecoveryState::new();
        for (table, pk) in &self.contract.tables {
            let sql = format!("SELECT * FROM {table};");
            let rows = match reader.query_rows(&sql) {
                Ok(r) => r,
                Err(e) => {
                    state.diagnostic = serde_json::json!({
                        "scan_error": e,
                        "table": table,
                    });
                    return state;
                }
            };
            for row in rows {
                let id: UnitId = row
                    .get(pk)
                    .map(|v| v.to_string())
                    .unwrap_or_else(|| "<missing-pk>".to_string());
                let unit = format!("{table}#{id}");
                if (self.contract.is_partial)(&row) {
                    state.record_partial(unit);
                } else {
                    state.record_committed(unit);
                }
            }
        }
        state
    }
}

/// Convenience wrapper: arm every named boundary in turn and assert the
/// no-partial invariant after each. The caller supplies the
/// arm-crash-then-recover-then-read closure.
pub fn verify_all_sql_boundaries<F>(
    contract: SqlSchemaContract,
    mut arm_recover_read: F,
    expected_committed: &[UnitId],
) -> Result<(), RecoveryError>
where
    F: FnMut(&str) -> RecoveryState,
{
    let verifier = SqlRecoveryVerifier { contract };
    for boundary_name in SQL_CRASH_BOUNDARIES {
        let state = arm_recover_read(boundary_name);
        let boundary = CrashBoundary::new(*boundary_name);
        verifier.verify_no_partial(&boundary, &state, expected_committed)?;
    }
    Ok(())
}
