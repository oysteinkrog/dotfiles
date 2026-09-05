#!/usr/bin/env bash
# Phase 8: append patterns to .gitignore with SHADOWING-AUDIT.
# Usage: update-gitignore.sh <project> <patterns-file>
# patterns-file is one pattern per line; lines starting with # are comments.
set -euo pipefail

project="${1:?usage: update-gitignore.sh <project> <patterns-file>}"
patterns="${2:?missing patterns-file}"

cd "$project"
project_root="$(pwd -P)"
[[ -f "$patterns" ]] || { echo "ERROR: $patterns not found" >&2; exit 1; }
ws=".repo_janitor_workspace"
[[ -d "$ws" ]] || { echo "ERROR: $ws not found; run the earlier repo-janitor phases first" >&2; exit 2; }

# Read non-comment, non-blank lines
new_patterns=$(grep -v '^#' "$patterns" | grep -v '^$' || true)

# SHADOWING-AUDIT: for each pattern, check git ls-files
audit_log="$project_root/$ws/gitignore_shadowing_audit.log"
: > "$audit_log" || { echo "ERROR: cannot write gitignore shadowing audit log: $audit_log" >&2; exit 2; }
shadowed=0
while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    matches=$(git ls-files "$pat" 2>/dev/null | head -10)
    if [[ -n "$matches" ]]; then
        echo "SHADOW pattern=$pat" >> "$audit_log"
        printf '%s\n' "$matches" | sed 's/^/  /' >> "$audit_log"
        shadowed=$((shadowed + 1))
    else
        echo "OK pattern=$pat" >> "$audit_log"
    fi
done <<< "$new_patterns"

if [[ "$shadowed" -gt 0 ]]; then
    echo "WARN: $shadowed patterns shadow tracked files; see $audit_log"
    echo "Surface to user before committing; pair with git rm --cached if intended."
fi

# Append to .gitignore (preserve existing content)
[[ -f .gitignore ]] || touch .gitignore
{
    echo ""
    echo "# Added by repo-janitor on $(date -u +%Y-%m-%d)"
    cat "$patterns"
} >> .gitignore

# Verify each new pattern fires.
# git check-ignore takes paths as arguments and does NOT require them to exist on disk;
# it just consults the gitignore rule database. So we synthesize a hypothetical path
# from the pattern.
synthesize_test_path() {
    # For glob patterns like `*.bak`, substitute `*` → `repo-janitor-test`.
    # For literal patterns like `nohup.out`, use as-is.
    # For directory globs like `target/`, use `target/repo-janitor-test`.
    local p="$1"
    p="${p%/}"             # strip trailing slash
    p="${p#/}"             # strip leading anchor
    p="${p//\*\*/repo-janitor-test}"
    p="${p//\*/repo-janitor-test}"
    p="${p//\?/x}"
    [[ "$p" == */ ]] && p="${p}repo-janitor-test"
    echo "$p"
}

while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    [[ "$pat" == \!* ]] && continue   # negation rules don't fire on a probe
    test_path=$(synthesize_test_path "$pat")
    {
        echo "## probe pattern=$pat probe-path=$test_path"
        git check-ignore -v "$test_path" 2>&1 || echo "(probe NOT ignored — investigate)"
    } >> "$audit_log"
done <<< "$new_patterns"

echo "gitignore updated; audit at $audit_log"
