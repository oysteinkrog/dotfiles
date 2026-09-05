#!/usr/bin/env bash
# integrity-check.sh — Verify the audit dir hasn't been tampered with.
#
# Usage:
#   integrity-check.sh <audit-dir>
#
# Run periodically (cron / tripwire / pre-release). Catches:
#   - rubric.md modified out-of-band (sha256 in manifest.json no longer matches)
#   - non-standard commit messages in the audit dir's git log
#   - per-pass artifact tree SHA mismatch (a prior pass's files were edited)
#   - audit log suspiciously truncated
#
# Exit codes:
#   0  integrity OK (or no recorded baseline yet)
#   1  TAMPERING SUSPECTED — see stderr for the specific issues
#   2  invalid arguments / audit-dir not found
#
# If this script fails, follow the "What to do if compromised" runbook in
# references/ANTI-CORRUPTION.md.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

AUDIT_DIR="${1:?audit dir}"
[ -d "$AUDIT_DIR" ] || { echo "ERROR: $AUDIT_DIR not a directory" >&2; exit 2; }

ISSUES=()

# 1. rubric_sha256 in manifest still matches the file's content
RUBRIC_RECORDED=$(jq -r '.rubric_sha256 // empty' "$AUDIT_DIR/manifest.json" 2>/dev/null || true)
RUBRIC_ACTUAL=$(sha256sum "$AUDIT_DIR/rubric.md" 2>/dev/null | awk '{print $1}' || true)
if [ -n "$RUBRIC_RECORDED" ] && [ -n "$RUBRIC_ACTUAL" ] && [ "$RUBRIC_RECORDED" != "$RUBRIC_ACTUAL" ]; then
  ISSUES+=("rubric.md SHA mismatch: recorded=${RUBRIC_RECORDED:0:12}… actual=${RUBRIC_ACTUAL:0:12}… (rubric was edited out-of-band)")
fi

# 2. Git log: every commit follows expected audit-pass format. `grep -v` exits
# 1 when ALL lines match (the happy case — every commit is standard); we
# absorb that with `|| true` so set -e doesn't kill the script on success.
#
# Accepted prefixes (case-insensitive):
#   - `audit:` (any conventional-commit-style audit subject; covers
#     remediation, scorer fix, fresh-eyes, etc. — the most common shape
#     for hand-written audit-dir commits)
#   - `audit pass`, `single-bead audit`, `tripwire pass` — script-emitted
#     pass commits (run-pass.sh / single-bead-audit.sh / tripwire mode)
#   - `init`, `initial` — first-commit prefixes humans naturally use
#   - `sync` — JSONL/index sync commits when the audit dir tracks beads
#
# The `(?i)` PCRE case-insensitive flag isn't portable to BSD grep, so we
# use `-i` instead — supported by GNU grep, BSD grep, and busybox grep.
if [ -d "$AUDIT_DIR/.git" ]; then
  NON_STANDARD=$(git -C "$AUDIT_DIR" log --format='%s' 2>/dev/null \
    | { grep -v -i -E '^(audit:|audit pass|single-bead audit|tripwire pass|sync|init(ial)?)' || true; } \
    | head -5)
  [ -n "$NON_STANDARD" ] && ISSUES+=("Non-standard commit messages (first 5): $(echo "$NON_STANDARD" | tr '\n' '|')")
fi

# 3. Per-pass artifact_tree_sha256 matches the actual tree (skip raw/ which
# can grow if an agent re-ran tests; only the structured artifacts are pinned)
for pass_dir in "$AUDIT_DIR"/passes/*/; do
  [ -f "$pass_dir/manifest.json" ] || continue
  RECORDED=$(jq -r '.artifact_tree_sha256 // empty' "$pass_dir/manifest.json" 2>/dev/null || true)
  [ -z "$RECORDED" ] && continue   # older passes may not have it
  ACTUAL=$(find "$pass_dir" -type f -not -path '*/raw/*' -print0 \
           | sort -z \
           | xargs -0 sha256sum 2>/dev/null \
           | sha256sum \
           | awk '{print $1}' || true)
  if [ -n "$ACTUAL" ] && [ "$RECORDED" != "$ACTUAL" ]; then
    ISSUES+=("Pass $(basename "$pass_dir") artifact tree SHA mismatch")
  fi
done

# 4. AUDIT_LOG.jsonl has no obvious gaps (each pass should add lines)
if [ -f "$AUDIT_DIR/AUDIT_LOG.jsonl" ]; then
  LOG_LINES=$(wc -l < "$AUDIT_DIR/AUDIT_LOG.jsonl" | tr -d ' ')
  EXPECTED=$(ls -1d "$AUDIT_DIR/passes"/*/ 2>/dev/null | wc -l | tr -d ' ')
  if [ "${EXPECTED:-0}" -gt 0 ] && [ "${LOG_LINES:-0}" -lt $((EXPECTED * 5)) ]; then
    ISSUES+=("AUDIT_LOG suspiciously short: $LOG_LINES lines for $EXPECTED pass(es) (expected ≥ $((EXPECTED * 5)))")
  fi
fi

if [ "${#ISSUES[@]}" -gt 0 ]; then
  echo "TAMPERING SUSPECTED in $AUDIT_DIR:" >&2
  printf '  - %s\n' "${ISSUES[@]}" >&2
  exit 1
fi

echo "Integrity check: PASS ($AUDIT_DIR)"
exit 0
