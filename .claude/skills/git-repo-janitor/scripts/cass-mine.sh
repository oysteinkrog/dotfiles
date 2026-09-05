#!/usr/bin/env bash
# Mine cass for prior cleanup runs against this repo.
# Usage: cass-mine.sh <project> <workspace>
set -euo pipefail

project="${1:?usage: cass-mine.sh <project> <workspace>}"
ws="${2:?missing workspace}"
out="$ws/cass_findings.md"

if ! command -v cass >/dev/null 2>&1; then
    echo "cass not available; skipping" > "$out"
    exit 0
fi

if ! cass health >/dev/null 2>&1; then
    echo "# CASS findings" > "$out"
    echo "" >> "$out"
    echo "cass index unhealthy; run 'cass index --full' if you want priors" >> "$out"
    exit 0
fi

basename=$(basename "$project")
{
    echo "# CASS findings — repo-janitor pre-flight for $project"
    echo ""
    echo "## Direct prior cleanups"
    cass search "$basename cleanup" --robot --limit 5 --fields minimal --days 180 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for hit in data.get("hits", []):
        print(f"- {hit[\"source_path\"]}:L{hit[\"line_number\"]} ({hit[\"agent\"]})")
except Exception:
    pass
'
    echo ""
    echo "## Repo-janitor mentions"
    cass search "$basename repo janitor" --robot --limit 5 --fields minimal --days 180 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for hit in data.get("hits", []):
        print(f"- {hit[\"source_path\"]}:L{hit[\"line_number\"]} ({hit[\"agent\"]})")
except Exception:
    pass
'
} > "$out"

echo "cass findings at $out"
