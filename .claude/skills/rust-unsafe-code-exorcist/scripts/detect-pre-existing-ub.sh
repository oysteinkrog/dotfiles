#!/usr/bin/env bash
# detect-pre-existing-ub.sh — scan miri/loom/fuzz/mutants logs and partition findings.
# Usage: ./detect-pre-existing-ub.sh <audit-dir>
#
# Reads <audit-dir>/audit/phase7/verification-log.md plus per-tool outputs and
# emits two files:
#   - <audit-dir>/audit/phase7/in-scope-findings.md   (findings in code we touched)
#   - <audit-dir>/audit/synthesis/pre-existing-ub.md  (findings OUT of refactor scope)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

AUDIT_DIR="${1:?usage: detect-pre-existing-ub.sh <audit-dir>}"
AUDIT_DIR=$(audit_realpath "$AUDIT_DIR")
PROJECT_ROOT=$(audit_project_root_from_dir "$AUDIT_DIR")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT_ROOT")

VERIFY_LOG="$AUDIT_DIR/audit/phase7/verification-log.md"
PLAN_DIR="$AUDIT_DIR/audit/plans"
IN_SCOPE="$AUDIT_DIR/audit/phase7/in-scope-findings.md"
OUT_SCOPE="$AUDIT_DIR/audit/synthesis/pre-existing-ub.md"
mkdir -p "$(dirname "$IN_SCOPE")" "$(dirname "$OUT_SCOPE")"

if [ ! -f "$VERIFY_LOG" ]; then
  echo "error: $VERIFY_LOG not found. Run Phase 7 first." >&2
  exit 1
fi

# Heuristic: a finding's file:line is IN-SCOPE iff that file appears in any audit/plans/site-*.md
# as a touched file. We extract `<crate>/src/...` references from plan files.
TOUCHED=$(mktemp); trap 'rm -f "$TOUCHED" "$FINDINGS"' EXIT
FINDINGS=$(mktemp)

if [ -d "$PLAN_DIR" ]; then
  grep -hEo '`[a-zA-Z0-9_/.-]+\.rs`' "$PLAN_DIR"/*.md 2>/dev/null \
    | tr -d '`' \
    | sort -u > "$TOUCHED"
fi

# Extract finding lines (file:line: pattern) from verify log
grep -hE '^\s*([a-zA-Z0-9_/.-]+\.rs):[0-9]+' "$VERIFY_LOG" 2>/dev/null \
  | sed 's/^\s*//' \
  | head -200 > "$FINDINGS" || true

{
  echo "# In-scope findings (Phase 7)"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Findings in code the current refactor pass touched. Address by refining the relevant plan; rerun the harness."
  echo
} > "$IN_SCOPE"

{
  echo "# Pre-existing UB (out of refactor scope)"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Findings in code the current refactor did NOT touch. Per operator ⚑ Pre-Existing-UB-Isolator,"
  echo "each is filed as a separate \`pre-existing-ub-N\` bead. NEVER fold into the current refactor."
  echo
} > "$OUT_SCOPE"

i_in=0
i_out=0
while IFS= read -r line; do
  file=$(echo "$line" | sed -E 's/^([a-zA-Z0-9_/.-]+\.rs):.*$/\1/')
  if [ -z "$file" ]; then continue; fi
  if [ -s "$TOUCHED" ] && grep -qFx "$file" "$TOUCHED"; then
    i_in=$((i_in+1))
    echo "- \`$line\`" >> "$IN_SCOPE"
  else
    i_out=$((i_out+1))
    echo "## pre-existing-ub-$i_out" >> "$OUT_SCOPE"
    echo "" >> "$OUT_SCOPE"
    echo "File reference: \`$line\`" >> "$OUT_SCOPE"
    echo "" >> "$OUT_SCOPE"
    echo "Bead: TO BE FILED via \`br create\` in Phase 8 with title \"pre-existing-ub-$i_out [NOT IN REFACTOR SCOPE]\"" >> "$OUT_SCOPE"
    echo "" >> "$OUT_SCOPE"
  fi
done < "$FINDINGS"

echo "In-scope findings: $i_in (-> $IN_SCOPE)"
echo "Pre-existing UB:   $i_out (-> $OUT_SCOPE)"
