#!/usr/bin/env bash
# rustdoc-call-graph-extract.sh — extract a call-graph slice from rustdoc JSON output.
# Used by Phase 3 synthesizer to compute reachability of `unsafe` from `pub`.
#
# Usage: ./rustdoc-call-graph-extract.sh <audit-dir> <crate-name>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: rustdoc-call-graph-extract.sh <audit-dir> <crate-name>}"
CRATE="${2:?usage: rustdoc-call-graph-extract.sh <audit-dir> <crate-name>}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ROOT")

RUSTDOC_JSON="$AUDIT_DIR/phase1/${CRATE}__rustdoc.json"
OUT="$AUDIT_DIR/phase1/${CRATE}__call_graph.json"

if [ ! -f "$RUSTDOC_JSON" ]; then
  echo "error: $RUSTDOC_JSON not found. Run enumerate-unsafe.sh first." >&2
  exit 1
fi

# Extract:
# 1. Every `pub` item's id + name + kind + span
# 2. Every function's signature (we DON'T have a full call graph from rustdoc, but we
#    have the trait/impl topology and the span ranges to cross-reference with the
#    inventory's site line ranges).
jq '{
  format_version: .format_version,
  crate_version: .crate_version,
  root: .root,
  pub_items: [
    .index | to_entries[]
      | select(.value.visibility == "public")
      | {
          id: .key,
          name: .value.name,
          kind: (.value.inner | keys[0]?),
          span: .value.span,
          docs: .value.docs
        }
  ],
  fns: [
    .index | to_entries[]
      | select(.value.inner.function != null)
      | {
          id: .key,
          name: .value.name,
          visibility: .value.visibility,
          span: .value.span,
          decl: .value.inner.function.decl
        }
  ]
}' "$RUSTDOC_JSON" > "$OUT"

PUB_COUNT=$(jq '.pub_items | length' "$OUT")
FN_COUNT=$(jq '.fns | length' "$OUT")

echo "Extracted $PUB_COUNT pub items + $FN_COUNT fns -> $OUT"
echo
echo "Note: rustdoc JSON does not contain a callee-list per fn. The synthesizer must:"
echo "  - Use the span ranges in $OUT to cross-reference inventory rows by (file, line_start)."
echo "  - Run \`cargo +nightly rustc -- -Zunpretty=hir\` if HIR-level call info is needed."
echo "  - Use \`cargo-call-stack\` (if installed) for a deeper callee analysis."
