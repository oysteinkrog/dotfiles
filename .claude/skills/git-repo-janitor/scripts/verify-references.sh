#!/usr/bin/env bash
# Verify that no broken references survive after a move.
# Usage: verify-references.sh <project> <old-path> [old-path2 ...]
set -euo pipefail

project="${1:?usage: verify-references.sh <project> <old-path> [old-path2 ...]}"
shift
cd "$project"

stale=0
for path in "$@"; do
    bn=$(basename "$path")
    # Skip known false-positive prefixes (substrings of other names)
    matches=$(grep -rln -F "$path" --include="*.rs" --include="*.toml" --include="*.sh" \
              --include="*.py" --include="*.md" --include="*.json" --include="*.yml" \
              --include="*.yaml" --include="*.go" --include="*.js" --include="*.ts" \
              --include="*.tsx" --include="*.html" --include="Makefile" --include="Dockerfile" \
              --exclude-dir={.git,node_modules,target,dist,build,.venv,__pycache__,.next,.repo_janitor_workspace} \
              . 2>/dev/null | grep -v "^./docs/" || true)

    if [[ -n "$matches" ]]; then
        echo "STALE references to '$path':"
        echo "$matches" | sed 's/^/  /'
        stale=$((stale + 1))
    fi
done

if [[ "$stale" -gt 0 ]]; then
    echo ""
    echo "$stale stale reference(s) found"
    exit 1
fi

echo "no stale references"
