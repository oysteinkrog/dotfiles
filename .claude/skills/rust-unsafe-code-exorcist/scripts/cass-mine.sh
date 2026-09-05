#!/usr/bin/env bash
# cass-mine.sh — run CASS query pack against localhost + remote hosts
# Usage: ./cass-mine.sh <audit-dir> [--trim]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: cass-mine.sh <audit-dir> [--trim]}"
TRIM=false
[ "${2:-}" = "--trim" ] && TRIM=true

AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ROOT")
mkdir -p "$AUDIT_DIR"
RAW="$AUDIT_DIR/phase0_cass_raw.jsonl"
: > "$RAW"

HOSTS=(localhost css csd ts1 ts2)

if $TRIM; then
  # Trimmed pack: localhost only, focused queries
  QUERIES=(
    "unsafe to safe"
    "miri stacked borrows fix"
    "isomorphic safe rewrite"
  )
  HOSTS=(localhost)
else
  # Full pack
  QUERIES=(
    "unsafe to safe"
    "remove unsafe block"
    "isomorphic safe rewrite"
    "rewrite unsafe equivalent"
    "audit unsafe code"
    "soundness invariant"
    "raw pointer to NonNull migration"
    "transmute to zerocopy"
    "transmute bytemuck"
    "MaybeUninit::assume_init refactor"
    "array::from_fn replace MaybeUninit"
    "std::simd portable migration"
    "wide crate SIMD"
    "safe-only feature flag SIMD"
    "get_unchecked bounds-check elision"
    "arc-swap atomic config"
    "crossbeam queue replace mpsc"
    "dashmap replace sharded HashMap"
    "unsafe impl Send Sync removal"
    "SendPtr newtype audited"
    "FFI shim safe wrapper"
    "extern C panic boundary catch_unwind"
    "libc syscall wrapper safe"
    "longjmp Rust UB"
    "Pin::new_unchecked refactor"
    "pin-project migration"
    "self-referential async state machine"
    "async cancellation drop UB"
    "miri stacked borrows fix"
    "miri tree borrows"
    "miri provenance violation"
    "cargo-careful UB native"
    "cargo fuzz target unsafe"
    "cargo mutants behavior pin"
    "cargo-geiger delta vs baseline"
    "cargo expand macro output"
    "double drop panic in drop"
    "panic unwind through FFI extern C"
    "Drop glue lost resource"
    "allocator identity refactor"
  )
fi

for host in "${HOSTS[@]}"; do
  echo "==> Host: $host"
  for q in "${QUERIES[@]}"; do
    if [ "$host" = "localhost" ]; then
      cass search "$q" --robot --limit 30 --json 2>/dev/null | \
        jq -c --arg h "$host" --arg q "$q" '. + {_host: $h, _query: $q}' >> "$RAW" || true
    else
      cass search "$q" --robot --limit 30 --host "$host" --timeout 30s --json 2>/dev/null | \
        jq -c --arg h "$host" --arg q "$q" '. + {_host: $h, _query: $q}' >> "$RAW" || true
    fi
  done
done

# Dedupe by prompt_hash (or session_id if absent)
DEDUPED="$AUDIT_DIR/phase0_cass_dedup.jsonl"
jq -s 'unique_by(.prompt_hash // .session_id // .prompt) | .[]' < "$RAW" > "$DEDUPED"

COUNT=$(wc -l < "$DEDUPED" | tr -d ' ')
echo "Mined $COUNT unique hits across ${#HOSTS[@]} hosts. Written to $DEDUPED"
echo "Next: the cass-miner subagent reads $DEDUPED and writes $AUDIT_DIR/phase0_cass_findings.md"
