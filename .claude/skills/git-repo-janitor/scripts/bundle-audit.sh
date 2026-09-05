#!/usr/bin/env bash
# Deep audit of the bundle (beyond byte-equality).
# Usage: bundle-audit.sh <project> <bundle-path>
set -euo pipefail

project="${1:?usage: bundle-audit.sh <project> <bundle-path>}"
bundle="${2:?missing bundle-path}"

project_root="$(git -C "$project" rev-parse --show-toplevel)"
cd "$project_root"
project="$project_root"
ws=".repo_janitor_workspace"
log="$project/$ws/bundle_audit.log"

case "$bundle" in
    /*) bundle_abs="$(realpath -m "$bundle")" ;;
    *) bundle_abs="$(realpath -m "$project/$bundle")" ;;
esac
case "$bundle_abs" in
    "$project"/*) ;;
    *)
        echo "ERROR: bundle path must be inside the project: $bundle" >&2
        exit 2
        ;;
esac
bundle="$bundle_abs"
[[ -d "$ws" ]] || { echo "ERROR: $ws not found; run the earlier repo-janitor phases first" >&2; exit 2; }
: > "$log" || { echo "ERROR: cannot write bundle audit log: $log" >&2; exit 2; }

issues=0

# Every candidate has: bundle copy, meta file, index entry
while IFS=$'\t' read -r id _blob_sha path _size _mtime _smell _first_sha; do
    [[ "$id" == "id" ]] && continue
    [[ -z "$id" ]] && continue
    case "$path" in
        ""|/*|../*|*/../*)
            echo "BAD-PATH: $id $path" >> "$log"
            issues=$((issues + 1))
            continue
            ;;
    esac
    if [[ ! -f "$bundle/working-tree-copies/$path" ]]; then
        echo "MISSING-COPY: $id $path" >> "$log"
        issues=$((issues + 1))
    fi
    if [[ ! -f "$bundle/meta/${id}.txt" ]]; then
        echo "MISSING-META: $id" >> "$log"
        issues=$((issues + 1))
    fi
done < "$ws/candidates.tsv"

# Bundle has README + index.tsv + reference-graph + gitignore-before
for f in README.md index.tsv gitignore-before.txt; do
    if [[ ! -f "$bundle/$f" ]]; then
        echo "MISSING-BUNDLE-FILE: $f" >> "$log"
        issues=$((issues + 1))
    fi
done

# Backup ref exists
date_str=$(date -u +%Y-%m-%d)
if ! git rev-parse "refs/repo-janitor-backup/${date_str}-pre-cleanup" >/dev/null 2>&1; then
    echo "MISSING-BACKUP-REF" >> "$log"
    issues=$((issues + 1))
fi

if [[ "$issues" -gt 0 ]]; then
    echo "FAIL: $issues issues; see $log"
    exit 1
fi

echo "audit clean"
