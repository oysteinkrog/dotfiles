#!/usr/bin/env bash
# handoff-report.sh — Phase 10: emit the final handoff report.
#
# Reads apply_log.tsv, partial_split_log.tsv, cleanup_log.tsv, triage.tsv,
# project_profile.json. Writes handoff_report.md.

set -euo pipefail

PROJECT="${1:?Usage: handoff-report.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
BUNDLE="$(cat "$WORKSPACE/bundle_path.txt" 2>/dev/null || echo '<unknown>')"
PROFILE="$WORKSPACE/project_profile.json"
TRIAGE="$WORKSPACE/triage.tsv"
APPLY_LOG="$WORKSPACE/apply_log.tsv"
PARTIAL_LOG="$WORKSPACE/partial_split_log.tsv"
CLEANUP_LOG="$WORKSPACE/cleanup_log.tsv"
RUN_DATE=$(date -u +%Y-%m-%d)

profile_json_value() {
  local key="$1" out
  if [[ ! -f "$PROFILE" ]]; then
    printf ''
    return
  fi
  if command -v jq >/dev/null 2>&1; then
    if out=$(jq -r --arg key "$key" '.[$key] | if . == null then "" elif type == "boolean" then tostring elif type == "string" then . else tostring end' "$PROFILE" 2>/dev/null); then
      printf '%s' "$out"
      return
    fi
    printf ''
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    if out=$(python3 - "$PROFILE" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
value = data.get(sys.argv[2], "")
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(str(value))
PY
    ); then
      printf '%s' "$out"
      return
    fi
  fi
  printf ''
}
PRIMARY_BRANCH=$(profile_json_value primary_branch)
PRIMARY_BRANCH="${PRIMARY_BRANCH:-main}"

# Determine the actual recovery branch. Priority order:
#   1. RECOVERY_BRANCH_OVERRIDE env var
#   2. The branch the most-recent applied keeper landed on
#   3. The current branch (if it looks like a recovery branch)
#   4. Fallback: stash-recovery-<DATE>
detect_recovery_branch() {
  if [[ -n "${RECOVERY_BRANCH_OVERRIDE:-}" ]]; then
    printf '%s' "$RECOVERY_BRANCH_OVERRIDE"
    return
  fi
  # If apply_log.tsv has any committed keepers, find the branches containing
  # the latest one — pick the first that looks like a recovery branch.
  if [[ -f "$APPLY_LOG" ]]; then
    local latest_sha
    latest_sha=$(awk -F'\t' 'NR > 1 && $3 != "" {sha=$3} END {print sha}' "$APPLY_LOG")
    if [[ -n "$latest_sha" ]]; then
      local rb
      rb=$(git -C "$PROJECT_ABS" branch --contains "$latest_sha" --format='%(refname:short)' 2>/dev/null \
            | grep -E '^stash-recovery-' | sed -n '1p')
      if [[ -n "$rb" ]]; then printf '%s' "$rb"; return; fi
    fi
  fi
  # Fall back to current branch if it's a recovery branch.
  local cur
  cur=$(git -C "$PROJECT_ABS" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  case "$cur" in stash-recovery-*) printf '%s' "$cur"; return ;; esac
  # Final fallback: today's default name.
  printf 'stash-recovery-%s' "$RUN_DATE"
}
RECOVERY_BRANCH="$(detect_recovery_branch)"
BUNDLE_SHELL=$(printf '%q' "$BUNDLE")
PROJECT_ABS_SHELL=$(printf '%q' "$PROJECT_ABS")
RECOVERY_BRANCH_SHELL=$(printf '%q' "$RECOVERY_BRANCH")

OUT="$WORKSPACE/handoff_report.md"

# Counts (any missing file → 0; awk would error otherwise)
count_rows() {
  if [[ -f "$1" ]]; then
    awk -F'\t' "$2" "$1" 2>/dev/null | wc -l
  else
    echo 0
  fi
}
INITIAL_COUNT=$(count_rows "$WORKSPACE/inventory.tsv" 'NR > 1')
# These are awk programs; the $3/$5 references must be evaluated by awk.
# shellcheck disable=SC2016
APPLIED_COUNT=$(count_rows "$APPLY_LOG" 'NR > 1 && $3 != "" && $5 == "passed"')
# shellcheck disable=SC2016
PARTIAL_COUNT=$(count_rows "$PARTIAL_LOG" 'NR > 1 && $3 != ""')
DROPPED_COUNT=$(count_rows "$CLEANUP_LOG" 'NR > 1')
FINAL_STASH_COUNT=$(git -C "$PROJECT_ABS" stash list 2>/dev/null | wc -l)

verdict_count() {
  if [[ ! -f "$TRIAGE" ]]; then echo 0; return; fi
  awk -F'\t' -v v="$1" 'NR > 1 && $2 == v' "$TRIAGE" | wc -l
}

NOVEL=$(verdict_count novel-and-accretive)
PARTIAL=$(verdict_count partially-novel)
SUPERSEDED=$(verdict_count superseded)
GARBAGE=$(verdict_count garbage)
NOVEL_STALE=$(verdict_count novel-but-stale)
UNKNOWN=$(verdict_count unknown)

cat > "$OUT" <<EOF
# Stash Janitor — Handoff Report

**Project:** $PROJECT_ABS
**Run date:** $RUN_DATE
**Recovery branch:** $RECOVERY_BRANCH
**Bundle path:** $BUNDLE

## Counts

- **Initial stashes:** $INITIAL_COUNT
- **Triaged:**
  - novel-and-accretive: $NOVEL
  - partially-novel: $PARTIAL
  - superseded: $SUPERSEDED
  - garbage: $GARBAGE
  - novel-but-stale: $NOVEL_STALE
  - unknown: $UNKNOWN
- **Applied (Phase 6):** $APPLIED_COUNT
- **Split-applied (Phase 7):** $PARTIAL_COUNT
- **Dropped (Phase 9):** $DROPPED_COUNT
- **Final stash list:** $FINAL_STASH_COUNT

## Recovered commits
EOF

# Recovered commits table. Either Phase 6 or Phase 7 can be absent; emit the
# header once before the first row so partial-only runs still produce valid
# markdown.
echo >> "$OUT"
RECOVERED_TABLE_STARTED=false
start_recovered_table() {
  if [[ "$RECOVERED_TABLE_STARTED" != "true" ]]; then
    echo "| sha | from stash | gates | duration |" >> "$OUT"
    echo "|-----|------------|-------|----------|" >> "$OUT"
    RECOVERED_TABLE_STARTED=true
  fi
}
if [[ -f "$APPLY_LOG" ]] && awk 'NR > 1' "$APPLY_LOG" | grep -q .; then
  start_recovered_table
  awk -F'\t' 'NR > 1 && $3 != "" {
    short = substr($3, 1, 10)
    printf "| %s | %s | %s | %ss |\n", short, $2, $5, $6
  }' "$APPLY_LOG" >> "$OUT"
fi
if [[ -f "$PARTIAL_LOG" ]] && awk 'NR > 1' "$PARTIAL_LOG" | grep -q .; then
  start_recovered_table
  awk -F'\t' 'NR > 1 && $3 != "" {
    short = substr($3, 1, 10)
    printf "| %s | %s (split) | %s | %ss |\n", short, $2, $5, $6
  }' "$PARTIAL_LOG" >> "$OUT"
fi
if [[ "$RECOVERED_TABLE_STARTED" != "true" ]]; then
  echo "_No recovered commits recorded._" >> "$OUT"
fi

cat >> "$OUT" <<EOF

## Recovery recipes (verbatim)

If you regret any drop, every stash is recoverable from the bundle:

	\`\`\`bash
	# By backup ref (preferred):
	git cherry-pick -m 1 refs/stash-backup/NNN     # NNN = zero-padded stash index

	# By bundle diff (when ref already pruned):
	git apply --3way ${BUNDLE_SHELL}/diffs/NNN.diff

	# If index.tsv says has_untracked=true for that row, also copy:
	( cd ${BUNDLE_SHELL}/stashed-untracked/NNN && tar -cf - . ) | ( cd ${PROJECT_ABS_SHELL} && tar -xf - )

	# The bundle's full index:
	cat ${BUNDLE_SHELL}/index.tsv
\`\`\`

## Push instructions

The skill never pushes. To land the recovered work:

\`\`\`bash
git push origin ${RECOVERY_BRANCH_SHELL}
# Then open a PR against $PRIMARY_BRANCH for review
\`\`\`

## Bundle lifecycle

The bundle at \`$BUNDLE\` is yours to manage. Recommended:

- Keep for at least one release cycle (1–4 weeks)
- Once you're sure nothing was missed, \`mv\` it to a trash location
  (DCG would block \`rm -rf\`; \`mv\` works)
- The backup refs at \`refs/stash-backup/*\` inside the repo are independent
  of the bundle directory; they survive even if the bundle is deleted

## Backup refs in this repo

\`\`\`bash
$(git -C "$PROJECT_ABS" for-each-ref refs/stash-backup/ --format='%(refname:short) %(objectname:short)' 2>/dev/null | sed -n '1,10p')
$(test "$(git -C "$PROJECT_ABS" for-each-ref refs/stash-backup/ 2>/dev/null | wc -l)" -gt 10 && echo "... ($(git -C "$PROJECT_ABS" for-each-ref refs/stash-backup/ 2>/dev/null | wc -l) total) ...")
\`\`\`

## Done

The skill has finished its work. Push the recovery branch when ready.
EOF

echo "wrote $OUT"
echo
echo "Report summary:"
echo "  $INITIAL_COUNT stashes triaged → $APPLIED_COUNT applied + $PARTIAL_COUNT split-applied + $DROPPED_COUNT dropped"
echo "  Final stash list: $FINAL_STASH_COUNT"
echo "  Recovery branch: $RECOVERY_BRANCH"
echo "  Bundle: $BUNDLE"
