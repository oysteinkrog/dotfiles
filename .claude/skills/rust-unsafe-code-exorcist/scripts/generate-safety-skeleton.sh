#!/usr/bin/env bash
# generate-safety-skeleton.sh — emit a hardened SAFETY-comment skeleton per (A) site.
# Usage: ./generate-safety-skeleton.sh <audit-dir>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: generate-safety-skeleton.sh <audit-dir>}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ROOT")

CLASS_DIR="$AUDIT_DIR/audit/classification"
OUT_DIR="$AUDIT_DIR/audit/safety-skeletons"
mkdir -p "$OUT_DIR"

if [ ! -d "$CLASS_DIR" ]; then
  echo "error: $CLASS_DIR not found." >&2
  exit 1
fi

A_COUNT=0
for class_file in "$CLASS_DIR"/site-*.md; do
  [ -f "$class_file" ] || continue
  bucket=$(grep -oE '\*\*Bucket\.\*\*\s+`?\(A\)' "$class_file" || true)
  if [ -z "$bucket" ]; then continue; fi

  site_id=$(basename "$class_file" .md)
  A_COUNT=$((A_COUNT+1))

  cat > "$OUT_DIR/${site_id}__safety.md" <<EOF
# Hardened SAFETY comment skeleton — $site_id

Read [00-CANONICAL-UNAVOIDABLE.md](../../references/patterns/00-CANONICAL-UNAVOIDABLE.md)
and the per-site classification at \`audit/classification/$site_id.md\` before filling in.

Place the comment AT the unsafe site in the project repo (only after Phase 8/8.5 authorizes
project-repo edits).

\`\`\`rust
/// <PROSE — what this operation does, ~3-5 sentences. Plain language. No jargon.>
///
/// # Safety
///
/// The caller MUST guarantee:
/// - <SPECIFIC INVARIANT 1 — testable; cite the validating function if any>
/// - <SPECIFIC INVARIANT 2>
/// - <SPECIFIC INVARIANT 3>
///
/// These invariants are enforced by:
/// - <CITED CODE 1 — file:line>
/// - <CITED CODE 2 — file:line>
///
/// What breaks if any invariant is violated:
/// - <SPECIFIC UB OR PANIC OUTCOME — e.g., "read past mapped region; segfault or read-of-invalid">
///
/// Unwinding:
/// - <Rust unwinding through this site is UB / safe under panic="abort" / handled via catch_unwind>
///
/// Async cancellation:
/// - <not reachable from async / fully unwind-safe / handled via guard struct>
///
/// Allocator identity:
/// - <preserved (specify allocator) / N/A — no allocation>
///
/// Co-aliasing:
/// - <list cross-site dependencies — sites that touch the same memory / atomic>
///
/// Reviewer attack surface:
/// - <one-sentence steel-man for an attack the reviewer might raise>
/// - <one-sentence rebuttal>
\`\`\`

## Proof-obligation clippy lint (if expressible)

If a clippy lint (or custom proc-macro lint) can catch caller-side violations
of any of the above invariants, add it to \`clippy.toml\`:

\`\`\`toml
disallowed-methods = [
    { path = "<VIOLATING CALL>", reason = "violates proof obligation for $site_id; use <SAFE WRAPPER> instead" },
]
\`\`\`

If clippy can't express the obligation, file a follow-up bead for a custom proc-macro lint;
do NOT block this hardening on the lint.

## Bead acceptance criteria

\`\`\`bash
# SAFETY comment landed and named
grep -B 2 -A 30 "fn <NAME>" <CRATE>/src/<FILE>.rs | grep -E "# Safety"
# Clippy lint clean
cargo clippy -p <CRATE>
# Geiger count unchanged (A sites stay (A); the comment, not the code, is the change)
cargo +nightly geiger -p <CRATE>
\`\`\`
EOF

done

echo "Generated $A_COUNT (A) safety skeletons under $OUT_DIR"
