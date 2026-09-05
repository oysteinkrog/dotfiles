#!/usr/bin/env bash
# Phase 1/2: detect phantom deletions per Axiom 24 and PHANTOM-DELETIONS.md.
# Halts (exit 2) if more than 5 phantom deletions are present.
# Usage: detect-phantom-deletions.sh <project>
set -euo pipefail

project="${1:?usage: detect-phantom-deletions.sh <project>}"
cd "$project"
ws=".repo_janitor_workspace"
mkdir -p "$ws"

out_tsv="$ws/phantom_deletions.tsv"
# `printf` is portable; `echo -e` depends on bash's xpg_echo setting.
printf 'path\tlast_commit_op\tlast_commit_sha\tlast_commit_message\n' > "$out_tsv"

phantom_count=0

# Get all currently-deleted-but-tracked files. `git status --porcelain` rows
# always have status XY in columns 1-2 (one or both may be space) and the path
# starting at column 4. Filtering on $1 alone (the merged status field as awk
# splits on whitespace) catches both ` D` (unstaged delete) and `D ` / `DD`
# (staged or both). Filtering on $2 would over-match paths containing the
# letter "D" (e.g., `Documents/foo.txt`).
git status --porcelain | awk '$1 ~ /D/ {print substr($0, 4)}' | while IFS= read -r path; do
    [[ -z "$path" ]] && continue

    # What was the last commit's operation on this path?
    # --pretty=format: produces an empty header line; --name-status appends a single
    # tab-separated line like "M\tpath" or "R100\told\tnew". Take its first column.
    last_op=$(git log -1 --pretty=format: --name-status -- "$path" 2>/dev/null \
              | awk 'NF{print $1; exit}' || true)
    [[ -z "$last_op" ]] && last_op="?"

    last_sha=$(git log -1 --pretty=format:'%H' -- "$path" 2>/dev/null || true)
    last_msg=$(git log -1 --pretty=format:'%s' -- "$path" 2>/dev/null || true)

    # Phantom: file is deleted from working tree but its last commit op was NOT a deletion.
    # (Status codes: A=add, M=modify, D=delete, R=rename, C=copy, T=type-change.)
    case "$last_op" in
        D) ;;   # Last commit deleted it; current working-tree absence is intended
        *)
            printf '%s\t%s\t%s\t%s\n' "$path" "$last_op" "$last_sha" "$last_msg" >> "$out_tsv"
            ;;
    esac
done

# Re-count from the actual file (subshell variable lost)
phantom_count=$(tail -n +2 "$out_tsv" | wc -l)

echo "Phantom deletions detected: $phantom_count"

if [[ "$phantom_count" -gt 5 ]]; then
    # Per-subtree summary
    {
        echo "## Phantom deletions detected — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "Total: $phantom_count"
        echo ""
        echo "### By subtree"
        echo ""
        tail -n +2 "$out_tsv" | awk -F'\t' '{
            split($1, parts, "/")
            print parts[1]
        }' | sort | uniq -c | sort -rn | head -20
        echo ""
        echo "### Recent reflog operations (potential cause)"
        echo ""
        git reflog --date=iso | head -20
    } > "$ws/phantom_deletion_diagnostic.md"

    echo ""
    echo "DETAIL: $ws/phantom_deletions.tsv"
    echo "DIAGNOSTIC: $ws/phantom_deletion_diagnostic.md"
    echo ""
    echo "HALT: more than 5 phantom deletions. Review and decide:"
    echo "  (a) Restore via 'git checkout HEAD -- <paths>'"
    echo "  (b) Keep removed (intentional manual deletions)"
    echo "  (c) Investigate per-subtree"
    exit 2
fi

if [[ "$phantom_count" -gt 0 ]]; then
    echo ""
    echo "WARN: $phantom_count phantom deletion(s) — surface in Phase 5 plan"
fi

exit 0
