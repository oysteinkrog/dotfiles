#!/usr/bin/env bash
# cass-mine.sh — Phase 0.5: mine prior agent sessions for context.
#
# Looks for prior runs of this skill on this project, related incidents,
# and convention discoveries. Writes findings to cass_findings.md.
#
# Skips gracefully if cass isn't installed or indexed.

set -euo pipefail

PROJECT="${1:?Usage: cass-mine.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
BASENAME="$(basename "$PROJECT_ABS")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
mkdir -p "$WORKSPACE"
OUT="$WORKSPACE/cass_findings.md"

if ! command -v cass >/dev/null 2>&1; then
  {
    printf '# CASS findings — Phase 0.5\n\n'
    printf 'Skipped: cass not installed.\n'
  } > "$OUT"
  echo "cass not installed; skipping (wrote stub to $OUT)"
  exit 0
fi

# Verify cass health
if ! cass health --json >/dev/null 2>&1; then
  {
    printf '# CASS findings — Phase 0.5\n\n'
    printf 'Skipped: cass not healthy.\n'
  } > "$OUT"
  echo "cass not healthy; skipping (wrote stub to $OUT)"
  exit 0
fi

mined_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
queries=(
  "stash janitor $BASENAME"
  "git stash $BASENAME"
)

# Add any beads ticket ids that appear in stash messages.
# `grep -oE` exits 1 when no matches; with `set -euo pipefail` that aborts the
# script. Wrap grep in `{ ... || true; }` to make "no matches" a no-op.
if [[ -f "$WORKSPACE/inventory.tsv" ]]; then
  # `head -10` closes its stdin after 10 lines; under pipefail that SIGPIPEs
  # the upstream `sort -u` (exit 141) and `var=$(failing)` aborts the script.
  # Use `sed -n '1,10p'` (reads all stdin, prints only first 10) — no SIGPIPE.
  ticket_ids=$(awk -F'\t' 'NR > 1 {print $7}' "$WORKSPACE/inventory.tsv" \
                 | { grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' || true; } \
                 | sort -u | sed -n '1,10p')
  while IFS= read -r tid; do
    [[ -n "$tid" ]] && queries+=("$tid")
  done <<< "$ticket_ids"
fi

{
  printf '# CASS findings — Phase 0.5\n\n'
  printf 'Mined: %s\n' "$mined_at"
  printf 'Queries: %s\n\n' "${queries[*]}"
} > "$OUT"

findings_count=0

for q in "${queries[@]}"; do
  results=$(cass search "$q" --robot --limit 5 --days 90 --fields minimal 2>/dev/null \
             | head -50 || true)
  if [[ -z "$results" || "$results" == "{}" ]]; then
    continue
  fi
  # Single-quoted format strings are intentional (markdown literal backticks).
  # shellcheck disable=SC2016
  {
    printf '## Query: `%s`\n\n' "$q"
    printf '```json\n%s\n```\n\n' "$results"
  } >> "$OUT"
  findings_count=$((findings_count + 1))
done

if [[ "$findings_count" -eq 0 ]]; then
  {
    printf '## Summary\n\nNo relevant prior sessions found in the last 90 days.\n'
    printf 'Skill-state: clean (no priors to factor in).\n'
  } >> "$OUT"
else
  {
    printf '## Summary\n\n'
    printf '%s queries returned matches. Review above for relevance and feed\n' "$findings_count"
    printf 'into Phase 4 triage rubric (e.g., convention discoveries) and Phase 5\n'
    printf 'user-facing context (e.g., "previous run authored 2 keepers").\n'
  } >> "$OUT"
fi

echo "wrote $OUT"
echo "Mined $findings_count queries; cass findings_count=$findings_count"
