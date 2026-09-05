# Pattern 31 — SCHEMA-VERSION-MIGRATION-DUAL-READER

**Family:** Kernel — schema-evolution discipline for every artifact the gauntlet emits. Companion to [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) (where `format_version: u32` lives) and to every other schema-pinned artifact in the gauntlet ([`COMPACTION-SURVIVAL.md § convergence_tracker.json`](../methodology/COMPACTION-SURVIVAL.md), bench-history JSON, mismatch-signatures, failure bundles, parity-score reports, spec-tag catalog).

**When to apply:** Any time a `schema_version` field on a checked-in artifact bumps from `vN` to `vN+1`. The migration must support **both** versions for one full round (one full pass through the 16-phase loop), then deprecate `vN` with a CI gate on round N+2. This window is what lets downstream consumers (other agents, other machines, other branches mid-rebase) catch up without breaking mid-investigation.

## What

A serde-driven dual-deserializer wrapper that accepts both `vN` and `vN+1` shapes, plus a per-artifact migration-test that proves `vN → vN+1` is round-trip-correct on the corpus of every checked-in `vN` instance. On read, the wrapper logs a deprecation warning for `vN` (one per process, not per record). On write, the wrapper emits `vN+1` only. After one round, the orchestrator gates CI on "no `vN` records remain" by scanning the workspace; after the gate green-lights, the `vN` deserializer is removed and the artifact's `schema_version` floor is bumped.

This is a *contract* between rounds, not a one-shot migration. Every schema bump goes through the same five-step ritual, owned by the `schema-version-bumper` subagent ([`../../subagents/schema-version-bumper.md`](../../subagents/schema-version-bumper.md)).

## Why

> "**`format_version` bumped without migration.** A new format version invalidates every prior `artifact_id`. Bump only when truly necessary, and document the migration (old envelopes can be replayed with `--format-version 1`)." — [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) Pitfalls.

Failure mode prevented: *mid-round schema-rip*. Agent A in Round N+1 emits a `vN+1` mismatch-signature; Agent B reading the negative-ledger built in Round N can't deserialize it; B's session blocks at deserialize-error and silently skips the entry. Future agents reference a half-migrated ledger and silently lose evidence. Without the dual-reader window, the rule "the workspace is authoritative" from [`COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md) breaks.

The second failure mode prevented: *breaking downstream consumers mid-round*. The `bench-history-ratchet` ([pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md)) is a CI artifact read by every perf bead's keep-gate. Bumping its schema from `v2` to `v3` without dual-reader means every open perf bead's CI fails the moment the bump lands; rollback is messy because the bump might already have rewritten `.bench-history/*.latest.json` on one machine.

The third failure mode prevented: *deprecation-debt accumulation*. Without a hard gate on "remove vN after one round", projects accumulate four-five-six concurrent schema versions, each with its own deserialization branch. Eventually nobody knows which version a given record uses and the codebase carries dead deserializers for years.

The fourth failure mode prevented: *cross-machine artifact drift*. Workspace A on Machine 1 is on `vN+1`; Workspace B on Machine 2 (a different rch worker, or a stale clone) is on `vN`. Without the dual-reader window, syncing between them via git produces deserialize errors. The dual-reader is the cross-machine compatibility envelope.

## The pattern

### The dual-deserializer struct (canonical shape)

```rust
//! crates/<port>-harness/src/schema_evolution.rs

use serde::{Deserialize, Serialize};

/// The current writeable schema version for `MismatchSignature`.
/// Bumped by the schema-version-bumper subagent.
pub const MISMATCH_SIGNATURE_SCHEMA_VERSION_CURRENT: &str = "v3";

/// The earliest schema version we still ACCEPT on read.
/// This MUST equal `_CURRENT - 1` during a dual-reader window;
/// after one round, the gate forces this to equal `_CURRENT`.
pub const MISMATCH_SIGNATURE_SCHEMA_VERSION_FLOOR: &str = "v2";

/// On-disk shape: tag-based union over all currently-acceptable versions.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "schema_version")]
enum MismatchSignatureOnDisk {
    #[serde(rename = "v2")]
    V2(MismatchSignatureV2),
    #[serde(rename = "v3")]
    V3(MismatchSignatureV3),
}

/// In-memory canonical form (always the LATEST version).
pub type MismatchSignature = MismatchSignatureV3;

impl MismatchSignatureOnDisk {
    /// Promote on-disk shape to canonical form. Logs deprecation once per process
    /// per stale version via OnceLock.
    fn to_canonical(self) -> MismatchSignatureV3 {
        match self {
            Self::V2(v2) => {
                log_deprecation_once("MismatchSignature::v2 → v3");
                migrate_v2_to_v3(v2)
            }
            Self::V3(v3) => v3,
        }
    }
}

/// Public read API: returns canonical form regardless of stored version.
pub fn read_mismatch_signature(path: &Path) -> Result<MismatchSignature, ReadError> {
    let text = std::fs::read_to_string(path)?;
    let on_disk: MismatchSignatureOnDisk = serde_json::from_str(&text)?;
    Ok(on_disk.to_canonical())
}

/// Public write API: always emits the CURRENT version (v3).
pub fn write_mismatch_signature(
    sig: &MismatchSignature,
    path: &Path,
) -> Result<(), WriteError> {
    let wrapped = MismatchSignatureOnDisk::V3(sig.clone());
    let json = serde_json::to_string_pretty(&wrapped)?;
    std::fs::write(path, json)?;
    Ok(())
}
```

### The migration function (the proof obligation)

```rust
/// The literal v2 → v3 field migration.
/// MUST be lossless OR document every dropped/derived field in the bump's rationale doc.
fn migrate_v2_to_v3(v2: MismatchSignatureV2) -> MismatchSignatureV3 {
    MismatchSignatureV3 {
        signature_hash: v2.signature_hash,
        category: v2.category,
        // NEW in v3: per-mode oracle attribution (default to "unknown" for v2 records).
        oracle_mode: v2.oracle_mode.unwrap_or_else(|| OracleMode::Unknown {
            note: "migrated from v2; oracle mode not recorded at capture time".into(),
        }),
        // RENAMED in v3: `count` → `occurrence_count`.
        occurrence_count: v2.count,
        // SPLIT in v3: v2's `first_seen` becomes `first_seen` + `first_seen_run_id`.
        first_seen: v2.first_seen,
        first_seen_run_id: v2.first_seen_run_id.unwrap_or_else(|| "pre-migration".into()),
        // UNCHANGED.
        last_seen: v2.last_seen,
        examples: v2.examples,
        // NEW: link back to the migration that produced this record.
        migrated_from_version: Some("v2".into()),
    }
}
```

### One-shot deprecation logger

```rust
use once_cell::sync::OnceCell;
use std::collections::HashMap;
use std::sync::Mutex;

static DEPRECATION_LOG: OnceCell<Mutex<HashMap<String, ()>>> = OnceCell::new();

fn log_deprecation_once(message: &str) {
    let map = DEPRECATION_LOG.get_or_init(|| Mutex::new(HashMap::new()));
    let mut guard = map.lock().unwrap();
    if guard.insert(message.to_string(), ()).is_none() {
        // First time we've seen this message in this process.
        tracing::warn!(
            schema_evolution.deprecation = true,
            "{message} — dual-reader window; will be removed in round N+2"
        );
    }
}
```

### The migration test (the unit-test contract)

```rust
//! crates/<port>-harness/tests/migration_v2_to_v3.rs

use <port>_harness::schema_evolution::*;

/// Every v2 fixture in the workspace's checked-in corpus MUST migrate to v3
/// without error. A checked-in v2 fixture that fails to migrate is a release blocker.
#[test]
fn every_v2_fixture_migrates_to_v3() {
    let fixtures_dir = std::path::Path::new("tests/migration-fixtures/v2/");
    let mut errors = Vec::new();
    for entry in std::fs::read_dir(fixtures_dir).expect("fixtures dir exists") {
        let path = entry.unwrap().path();
        match read_mismatch_signature(&path) {
            Ok(v3) => {
                // Round-trip: write the migrated v3 back and re-read; must equal.
                let tmp = tempfile::NamedTempFile::new().unwrap();
                write_mismatch_signature(&v3, tmp.path()).unwrap();
                let v3_reread = read_mismatch_signature(tmp.path()).unwrap();
                assert_eq!(v3, v3_reread, "round-trip drift on {}", path.display());
            }
            Err(e) => errors.push(format!("{}: {e}", path.display())),
        }
    }
    if !errors.is_empty() {
        panic!("v2→v3 migration errors:\n{}", errors.join("\n"));
    }
}

/// The canonical golden: a v2 fixture with every field populated must produce
/// a v3 record that matches `tests/migration-fixtures/v3/full_field_golden.json` byte-for-byte.
#[test]
fn full_field_v2_to_v3_byte_exact() {
    let v2_path = std::path::Path::new("tests/migration-fixtures/v2/full_field.json");
    let v3_golden = std::path::Path::new("tests/migration-fixtures/v3/full_field_golden.json");
    let migrated = read_mismatch_signature(v2_path).unwrap();
    let tmp = tempfile::NamedTempFile::new().unwrap();
    write_mismatch_signature(&migrated, tmp.path()).unwrap();
    let migrated_bytes = std::fs::read(tmp.path()).unwrap();
    let golden_bytes = std::fs::read(v3_golden).unwrap();
    assert_eq!(migrated_bytes, golden_bytes,
               "byte-drift in v2→v3 migration; update golden or fix migration");
}
```

### The deprecation-gate CI check (after one round)

```bash
#!/usr/bin/env bash
# scripts/check-no-stale-schema-versions.sh
# Run by CI on round N+2 after a vN+1 bump in round N.
# Refuses to merge if any vN record remains in the workspace.
set -euo pipefail
workspace="${1:?usage: $0 <workspace>}"
floor="${2:?usage: $0 <workspace> <floor_version>}"  # e.g., "v3"

stale=$(find "$workspace" -name '*.json' -print0 \
        | xargs -0 grep -l "\"schema_version\":\s*\"v[0-9]\"" \
        | xargs -I{} sh -c 'jq -r ".schema_version" {} 2>/dev/null | grep -v "$0" | xargs -I[] echo "{}"' "$floor")

if [[ -n "$stale" ]]; then
  echo "ERROR: stale schema-version records found (floor: $floor):"
  echo "$stale"
  exit 64
fi
```

### The bumper ritual (five-step)

The `schema-version-bumper` subagent owns this:

1. **Author `vN+1` struct** alongside `vN`; add to `OnDisk` enum.
2. **Implement `migrate_vN_to_vN+1`** (lossless, or document drops in `docs/schema-bumps/{artifact}_vN_to_vN+1.md`).
3. **Add migration tests** (`every_vN_fixture_migrates_to_vN+1` + `full_field_vN_to_vN+1_byte_exact`).
4. **Bump `_CURRENT` constant** to `vN+1`; keep `_FLOOR` at `vN` for one round.
5. **Schedule the deprecation gate** for round N+2: at round-N+2 entry, the orchestrator runs `scripts/check-no-stale-schema-versions.sh <workspace> vN+1`; if green, removes the `vN` variant from `OnDisk` enum + bumps `_FLOOR` to `vN+1`.

## Variants per project class

The pattern is class-agnostic; the artifacts that participate are class-shaped:

| Class | Artifacts that follow this pattern |
|---|---|
| **All** | `ExecutionEnvelope` (`format_version`), `MismatchSignature` (`schema_version`), `FailureBundle` (`schema_version`), `convergence_tracker.json`, parity-score reports, retry-condition ledger entries |
| **SQL** | Plus: `pragma_config.json`, `wal_frame_envelope.json`, `crash_boundary_manifest.json` |
| **RESP** | Plus: `resp_frame_envelope.json`, `aof_replay_manifest.json` |
| **Numerical-Python** | Plus: `tensor_spec.json`, `ulp_tolerance_table.json` |
| **ML-System** | Plus: `autograd_capture.json`, `determinism_witness.json` |
| **HTTP-Protocol** | Plus: `route_invariants.json`, `openapi_schema_snapshot.json` |
| **Greenfield-Rust** | Plus: `SPEC-TAGS.json`, `phase3_layout_decision.json`, `phase2_spec_conflict.md` (markdown but with frontmatter schema) |

### Per-artifact migration tables

A central catalog at `docs/schema-bumps/CATALOG.md`:

```markdown
# Schema Migration Catalog

| Artifact | Current | Floor | In-flight bump | Migration test path | Bump rationale doc |
|---|---|---|---|---|---|
| ExecutionEnvelope | v2 | v2 | (none) | tests/migration_envelope.rs | n/a |
| MismatchSignature | v3 | v2 | v2 → v3 (round 17, dual-reader window) | tests/migration_v2_to_v3.rs | docs/schema-bumps/mismatch_v2_to_v3.md |
| FailureBundle | v1 | v1 | (none) | tests/migration_failure_bundle.rs | n/a |
| ConvergenceTracker | v1 | v1 | (none) | n/a | n/a |
| BenchHistoryEntry | v3 | v3 | (none) | tests/migration_bench_history.rs | docs/schema-bumps/bench_history_v2_to_v3.md |
| ParityScoreReport | v2 | v1 | v1 → v2 (round 17, dual-reader window) | tests/migration_parity_v1_to_v2.rs | docs/schema-bumps/parity_v1_to_v2.md |
```

## Failure modes

| Failure | Symptom | Detection | Fix |
|---|---|---|---|
| **Skipping the dual-reader window** | Round N writes `vN+1`; Round N's already-running session reads it back; deserialize error; round halts. | First-write-after-bump session crashes. | Mandatory two-round window: write-vN+1, accept-both for one round, then gate-remove-vN. The bumper subagent enforces. |
| **Breaking downstream consumers mid-round** | Bump lands on Round N day 1; a perf bead opened on Round N day 0 reads the bumped artifact next session and fails. | CI's `every_bead_can_read_artifacts` test breaks. | Bumps land at Round-N boundary only (not mid-round); orchestrator refuses to land a bumper PR during active Phase 11 work unless the tracker is already `converged: true`. |
| **Migration function loses fields silently** | A v2 field has no v3 home; migrator drops it; one round later, queries that depended on that field return None. | Migration golden test compares full-field v2 to full-field v3 byte-for-byte; any dropped field must be documented. | Lossy migrations are *allowed* but must be documented in the bump rationale doc; the doc gets a `# Dropped fields` section listing each + the rationale + the cass-mining query to find downstream consumers. |
| **Deprecation warning spammed once per record** | Process logs 50k warnings; warning channel becomes unreadable. | Manual log review or grep. | `log_deprecation_once` keyed on the message string; one warning per (process × stale version). |
| **`_FLOOR` constant never bumped after gate green** | One round passes, gate green-lights removal, but PR to remove `vN` variant never lands; deprecation tech-debt accumulates. | Round-end checklist: orchestrator scans `_CURRENT` vs `_FLOOR`; if `_CURRENT - _FLOOR > 1`, opens a remediation bead. | Bumper subagent auto-opens the removal PR after gate green-lights; orchestrator merges. |
| **Two simultaneous bumps on the same artifact** | Round N: bumper PR-A bumps `MismatchSignature v2→v3`; Round N: another bumper PR-B bumps `v2→v3` with different fields. | PR conflict at merge; one path wins silently. | Per-artifact serialization: `schema-version-bumper` agent has a per-artifact lock; second bumper waits for first to complete the full ritual (including the gate). |
| **CI gate matches stale records inside scratch directories** | Gate script scans `<workspace>/` and finds `vN` records in `/data/tmp/<project>-scratch/`; refuses merge. | Gate output lists paths. | Scope gate to `<workspace>/round_*/` + `<workspace>/sessions/` + `docs/`; explicitly exclude `/data/tmp/` per [pattern:280-SCRATCH-WORKTREE-CONVENTION](280-SCRATCH-WORKTREE-CONVENTION.md). |
| **Migration test uses runtime-generated fixtures** | Tests pass locally; checked-in `tests/migration-fixtures/v2/*.json` is missing; CI on cold-clone fails. | CI's first run on a fresh clone exposes the gap. | Migration fixtures MUST be checked into git; bumper-subagent's PR includes them; CI verifies `git ls-files tests/migration-fixtures/` is non-empty. |
| **Field-rename without dual-deserializer support** | A v2 field `count` was simply renamed to `occurrence_count` in v3 with no compatibility layer; v2 records error out. | Migration test fails on full-field v2 fixture. | The migrator handles renames explicitly (`v2.count` → `v3.occurrence_count`); the dual-reader enum tags it for free. |
| **Schema bump on `ExecutionEnvelope.format_version` invalidates content-addressed artifact_ids** | A v2 → v3 bump on envelope changes every `artifact_id` for the same semantic inputs; the negative-ledger's content-addressed references break. | `artifact_id_stability_test` fails. | Envelope bumps are *banned* unless absolutely necessary (e.g., security fix); when needed, the bump includes a one-time re-hash of the entire negative-ledger to map old `artifact_id` → new. |

## Cross-references

- [pattern:06-5-MODE-ORACLE-DISPATCH](06-5-MODE-ORACLE-DISPATCH.md) — `OracleMode` enum gains a variant → this pattern applies.
- [pattern:11-SPEC-TAG-EXTRACTION](11-SPEC-TAG-EXTRACTION.md) — `SPEC-TAGS.json` schema evolves over time → this pattern applies.
- [pattern:12-SPEC-CONFLICT-DETECTION](12-SPEC-CONFLICT-DETECTION.md) — `SpecConflict` enum gains a variant → this pattern applies.
- [pattern:13-SINGLE-CRATE-VS-WORKSPACE-DECISION](13-SINGLE-CRATE-VS-WORKSPACE-DECISION.md) — `LayoutDecision` enum gains a variant → this pattern applies.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — the canonical example: `format_version: u32` is the same idea, but the `artifact_id` content-addressing makes bumps especially destructive.
- [pattern:45-MISMATCH-MINIMIZER](45-MISMATCH-MINIMIZER.md) — `MismatchSignature` is the most-frequently-bumped artifact in the gauntlet; this pattern's worked example.
- [pattern:55-INSTA-GOLDEN-SNAPSHOTS](55-INSTA-GOLDEN-SNAPSHOTS.md) — insta's `.snap` files have their own version-line header; treat the same way.
- [pattern:75-BAYESIAN-CONFORMAL-SCORE](75-BAYESIAN-CONFORMAL-SCORE.md) — parity score JSON is schema-pinned; bumps require this pattern.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — failure bundles carry their own `schema_version`; bumps via this pattern.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — verification contract's `fail-mixed` arises when a session is half-migrated.
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — `.bench-history/*.latest.json` schema bumps are the highest-stakes; affects every open perf bead.
- [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) — ledger entries are schema-pinned; bumps require this pattern.
- [pattern:185-RETRY-CONDITION-PREDICATE](185-RETRY-CONDITION-PREDICATE.md) — the 8 verbatim forms have a version; bumps via this pattern.
- [pattern:195-RUN-IDENTITY-STACK](195-RUN-IDENTITY-STACK.md) — `run_id` format itself is schema-pinned; bumps via this pattern.
- [pattern:280-SCRATCH-WORKTREE-CONVENTION](280-SCRATCH-WORKTREE-CONVENTION.md) — scratch directories are excluded from the deprecation-gate scan.
- [`../methodology/COMPACTION-SURVIVAL.md`](../methodology/COMPACTION-SURVIVAL.md) — every Layer 5 (`convergence_tracker.json`) schema bump goes through this pattern.
- [`../methodology/SPEC-PINNING-FOR-GREENFIELD.md`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md) §6 — spec versioning + migration cross-ref.
- [`../../subagents/schema-version-bumper.md`](../../subagents/schema-version-bumper.md) — the subagent that owns this ritual end-to-end.
