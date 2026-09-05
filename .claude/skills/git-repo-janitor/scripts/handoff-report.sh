#!/usr/bin/env bash
# Phase 10: emit handoff_report.md.
# Usage: handoff-report.sh <project>
set -euo pipefail

project="${1:?usage: handoff-report.sh <project>}"
cd "$project"
ws=".repo_janitor_workspace"
out="$ws/handoff_report.md"

bundle_path=""
[[ -f "$ws/bundle_path.txt" ]] && bundle_path=$(cat "$ws/bundle_path.txt")

date_str=$(date -u +%Y-%m-%d)
recovery_branch="repo-janitor-${date_str}"

# Counts
total_candidates=$(tail -n +2 "$ws/candidates.tsv" 2>/dev/null | wc -l || echo 0)

initial_files=$(git ls-files . 2>/dev/null | grep -cv / || echo 0)

# Per-verdict counts
counts_by_verdict=$(tail -n +2 "$ws/triage.tsv" 2>/dev/null | awk -F'\t' '{print $2}' | sort | uniq -c || echo "")

# Apply log
apply_count=0
[[ -f "$ws/apply_log.tsv" ]] && apply_count=$(tail -n +2 "$ws/apply_log.tsv" | wc -l)

cat > "$out" <<EOF
# Repo Janitor — Handoff Report

**Project:** $project
**Run date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Recovery branch:** ${recovery_branch}
**Bundle path:** ${bundle_path:-<not set>}

## Counts
- Initial tracked top-level files: ${initial_files}
- Candidates triaged: ${total_candidates}

### Per-verdict breakdown
\`\`\`
${counts_by_verdict}
\`\`\`

- Recovery commits authored: ${apply_count}

## Recovery recipes

If you regret any move/delete, the bundle has byte-identical copies:

\`\`\`bash
# By backup ref (preferred)
git checkout refs/repo-janitor-backup/${date_str}-pre-cleanup -- <path>

# By bundle copy
cp ${bundle_path}/working-tree-copies/<path> ${project}/<path>
git add <path>

# Bundle index:
cat ${bundle_path}/index.tsv
\`\`\`

See \`references/RECOVERY-RECIPES.md\` for the full guide.

## Push instructions

The skill never pushes. To land the cleanup:

\`\`\`bash
git push origin ${recovery_branch}
# Then open a PR against your primary branch for review
\`\`\`

If your repo pushes main → master synonym (frankensqlite/CASS pattern):

\`\`\`bash
git push origin ${recovery_branch}:master
\`\`\`

## Bundle lifecycle

The bundle lives at ${bundle_path}.
Keep it for at least one release cycle. Once you're sure nothing was
accidentally lost, move it to your normal archive/trash location with \`mv\`.
The skill never advises bypassing DCG or deleting the bundle itself.

EOF

# Append recovery commits if any
if [[ -f "$ws/apply_log.tsv" ]] && [[ "$apply_count" -gt 0 ]]; then
    echo "## Recovery commits" >> "$out"
    echo "" >> "$out"
    echo "| id | action | sha | files | gates |" >> "$out"
    echo "|----|--------|-----|-------|-------|" >> "$out"
    tail -n +2 "$ws/apply_log.tsv" | awk -F'\t' '{printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5}' >> "$out"
fi

echo "report written to $out"
