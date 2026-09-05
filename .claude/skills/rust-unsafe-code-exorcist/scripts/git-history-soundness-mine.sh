#!/usr/bin/env bash
# git-history-soundness-mine.sh — mine the project's git history for soundness-relevant decisions.
# Usage: ./git-history-soundness-mine.sh <project> <audit-dir>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/audit-dir-guard.sh"

PROJECT="${1:?usage: git-history-soundness-mine.sh <project> <audit-dir>}"
AUDIT_DIR="${2:?usage: git-history-soundness-mine.sh <project> <audit-dir>}"
PROJECT=$(audit_realpath "$PROJECT")
AUDIT_DIR=$(audit_require_under_project "$AUDIT_DIR" "$PROJECT")

mkdir -p "$AUDIT_DIR/audit/archeology/sites" \
         "$AUDIT_DIR/audit/archeology/rejections" \
         "$AUDIT_DIR/audit/archeology/beads"

cd "$PROJECT"

# NOTE: `--diff-filter=A/D` operates at FILE granularity (file added / file removed
# entirely), NOT at line granularity. To find commits that ADDED or REMOVED occurrences
# of `unsafe` within existing files, use the pickaxe (`-S <string>`) which finds
# commits that CHANGED the occurrence count of the literal string.
#
# Heuristic: pickaxe('unsafe') captures both directions (added + removed); we
# bucket each commit by net delta below.

echo "==> Mining commits that touched 'unsafe' occurrences (added or removed)"
git log --all -S 'unsafe' --pretty=format:'%H|%ad|%an|%s' --date=short \
        --max-count=600 -- '*.rs' 2>/dev/null \
  > "$AUDIT_DIR/audit/archeology/touched-commits.txt" || true

# Split into added vs removed by re-running diff per commit and counting +unsafe vs -unsafe lines.
: > "$AUDIT_DIR/audit/archeology/added-commits.txt"
: > "$AUDIT_DIR/audit/archeology/removed-commits.txt"
while IFS='|' read -r hash date author subject; do
  [ -n "$hash" ] || continue
  PLUS=$(git show --unified=0 "$hash" -- '*.rs' 2>/dev/null | grep -cE '^\+[^+].*\bunsafe\b' || true)
  MINUS=$(git show --unified=0 "$hash" -- '*.rs' 2>/dev/null | grep -cE '^-[^-].*\bunsafe\b' || true)
  PLUS=${PLUS:-0}; MINUS=${MINUS:-0}
  if [ "$PLUS" -gt "$MINUS" ]; then
    echo "$hash|$date|$author|$subject" >> "$AUDIT_DIR/audit/archeology/added-commits.txt"
  elif [ "$MINUS" -gt "$PLUS" ]; then
    echo "$hash|$date|$author|$subject" >> "$AUDIT_DIR/audit/archeology/removed-commits.txt"
  fi
done < "$AUDIT_DIR/audit/archeology/touched-commits.txt"

echo "==> Mining safety-related commits (by commit message keywords)"
git log --all --grep='unsafe\|miri\|loom\|\bUB\b\|soundness\|safety' \
  --pretty=format:'%H|%ad|%an|%s' --date=short --max-count=500 2>/dev/null \
  > "$AUDIT_DIR/audit/archeology/related-commits.txt" || true

ADDED=$(wc -l < "$AUDIT_DIR/audit/archeology/added-commits.txt" | tr -d ' ')
REMOVED=$(wc -l < "$AUDIT_DIR/audit/archeology/removed-commits.txt" | tr -d ' ')
RELATED=$(wc -l < "$AUDIT_DIR/audit/archeology/related-commits.txt" | tr -d ' ')

echo "    added: $ADDED, removed: $REMOVED, related: $RELATED"

echo "==> Sampling commits for full detail"
# Save the full diff for the top 20 most-recent removed-unsafe commits (refactor wins)
head -20 "$AUDIT_DIR/audit/archeology/removed-commits.txt" | while IFS='|' read -r hash date author subject; do
  [ -n "$hash" ] || continue
  git show "$hash" --stat > "$AUDIT_DIR/audit/archeology/commit-$hash.stat" 2>/dev/null || true
  git show "$hash" 2>/dev/null | head -300 > "$AUDIT_DIR/audit/archeology/commit-$hash.diff" || true
done

echo "==> Mining closed PRs (if gh available)"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh pr list --state closed --search 'unsafe OR safety OR refactor OR miri' --limit 30 \
    --json number,title,closedAt,body 2>/dev/null \
    > "$AUDIT_DIR/audit/archeology/closed-prs.json" || true
  if [ -f "$AUDIT_DIR/audit/archeology/closed-prs.json" ]; then
    jq -r '.[] | .number' "$AUDIT_DIR/audit/archeology/closed-prs.json" 2>/dev/null | head -10 | while read -r pr; do
      gh pr view "$pr" --json title,body,reviews,comments \
        > "$AUDIT_DIR/audit/archeology/rejections/pr-$pr.json" 2>/dev/null || true
    done
  fi
else
  echo "    (gh CLI unavailable or unauthenticated; skipping PR mining)" \
    > "$AUDIT_DIR/audit/archeology/pr-mining-skipped.md"
fi

echo "==> Mining beads (if .beads/ present)"
if [ -d "$PROJECT/.beads" ] && command -v br >/dev/null 2>&1; then
  br list --status closed --json 2>/dev/null \
    | jq '[.[] | select(.title | test("unsafe|safety|miri|loom|UB"; "i"))]' \
    > "$AUDIT_DIR/audit/archeology/related-beads.json" || true
fi

echo "==> Generating summary"
cat > "$AUDIT_DIR/audit/archeology/SUMMARY.md" <<EOF
# Archeology summary

Generated $(date -u +%Y-%m-%dT%H:%M:%SZ).

## Stats
- Commits that added unsafe: $ADDED
- Commits that removed unsafe: $REMOVED
- Safety-related commits: $RELATED

## Inputs to subsequent phases
- Per-site birth.md generation (Phase 0.5 follow-up)
- Refactor-wins catalog (informs Phase 4 classifier with confident-pattern signatures)
- Rejected-refactors catalog (informs Phase 5 planner: don't propose rejected patterns)
- Tribal-knowledge file (informs Phase 6 adversarial: project's institutional knowledge)

## Files
- added-commits.txt
- removed-commits.txt
- related-commits.txt
- commit-*.{stat,diff} (top 20 refactor wins)
- closed-prs.json (if available)
- rejections/pr-*.json (if available)
- related-beads.json (if available)
EOF

echo
echo "Archeology mining complete: $AUDIT_DIR/audit/archeology/SUMMARY.md"
echo "Next: the archeologist subagent reads these files + writes per-site birth.md + the catalogs."
