#!/usr/bin/env bash
# Phase 3: build the recovery bundle.
# Usage: build-bundle.sh <project> <bundle-path>
set -euo pipefail

project="${1:?usage: build-bundle.sh <project> <bundle-path>}"
bundle="${2:?missing bundle-path}"

project_root="$(git -C "$project" rev-parse --show-toplevel)"
cd "$project_root"
project="$project_root"
ws=".repo_janitor_workspace"
[[ -f "$ws/candidates.tsv" ]] || { echo "ERROR: candidates.tsv missing; run inventory first" >&2; exit 1; }

case "$bundle" in
    /*) bundle_abs="$(realpath -m "$bundle")" ;;
    *) bundle_abs="$(realpath -m "$project_root/$bundle")" ;;
esac
case "$bundle_abs" in
    "$project_root"/*) ;;
    *)
        echo "ERROR: bundle path must be inside the project: $bundle" >&2
        echo "       recommended: .repo_janitor_workspace/recovery-bundle-$(date -u +%Y-%m-%d)" >&2
        exit 2
        ;;
esac
bundle="$bundle_abs"

mkdir -p "$bundle"/{meta,working-tree-copies}
printf '%s\n' "$bundle" > "$ws/bundle_path.txt"

# Copy gitignore
cp .gitignore "$bundle/gitignore-before.txt" 2>/dev/null || touch "$bundle/gitignore-before.txt"

# Update backup ref
date_str=$(date -u +%Y-%m-%d)
git update-ref "refs/repo-janitor-backup/${date_str}-pre-cleanup" HEAD

# Copy reference graph if it exists
[[ -f "$ws/reference_graph.json" ]] && cp "$ws/reference_graph.json" "$bundle/reference-graph.json"

# Index header
{
    echo "# repo-janitor bundle index.tsv schema v1.0"
    printf 'id\tblob_sha\tpath_at_HEAD\tsize_bytes\tmtime_iso\tsmell_tags\tfirst_committed_in\thas_lfs_pointer\tcontent_hash_sha256\n'
} > "$bundle/index.tsv"

# Process each candidate
tail -n +2 "$ws/candidates.tsv" | while IFS=$'\t' read -r id blob_sha path size mtime smell first_sha; do
    [[ -z "$id" ]] && continue
    case "$path" in
        ""|/*|../*|*/../*)
            echo "ERROR: candidate path must be repo-relative and cannot escape: $path" >&2
            exit 2
            ;;
    esac
    src="$path"
    dest="$bundle/working-tree-copies/$path"
    mkdir -p "$(dirname "$dest")"

    # LFS smudge if applicable. The output of `git lfs ls-files` is `<sha> [-*] <path>`,
    # so we extract column 3+ and compare exactly to the candidate path.
    has_lfs="false"
    if command -v git-lfs >/dev/null 2>&1; then
        if git lfs ls-files 2>/dev/null | awk '{$1=""; $2=""; sub(/^  /, ""); print}' \
              | grep -Fxq -- "$path"; then
            has_lfs="true"
            git lfs smudge < "$src" > "$dest" 2>/dev/null || cp -p -- "$src" "$dest"
        else
            cp -p -- "$src" "$dest"
        fi
    else
        cp -p -- "$src" "$dest"
    fi

    # Hash for verification
    content_hash=$(sha256sum "$dest" | awk '{print $1}')

    # Meta file
    {
        echo "id=$id"
        echo "path=$path"
        echo "blob_sha=$blob_sha"
        echo "size_bytes=$size"
        echo "mtime_iso=$mtime"
        echo "smell_tags=$smell"
        echo ""
        if [[ -n "$first_sha" ]]; then
            git log -1 --format='first_commit=%H%nfirst_commit_message=%s%nfirst_commit_author=%an <%ae>%nfirst_commit_date=%ci' "$first_sha" 2>/dev/null || true
        fi
        echo ""
        git log -1 --format='last_commit=%H%nlast_commit_message=%s%nlast_commit_author=%an <%ae>%nlast_commit_date=%ci' -- "$path" 2>/dev/null || true
    } > "$bundle/meta/${id}.txt"

    # Index entry
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$blob_sha" "$path" "$size" "$mtime" "$smell" "$first_sha" "$has_lfs" "$content_hash" \
        >> "$bundle/index.tsv"
done

# README
cat > "$bundle/README.md" <<EOF
# Repo Cleanup Recovery Bundle

**Project:** $project
**Created:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Source skill:** git-repo-janitor

## Layout

- \`index.tsv\` — one row per candidate; the source of truth.
- \`meta/<id>.txt\` — provenance per candidate.
- \`working-tree-copies/<path>\` — byte-identical copy of each candidate.
- \`gitignore-before.txt\` — full .gitignore at run start.
- \`reference-graph.json\` — inbound references per candidate (if available).

## Recovery recipes

### Restore one file
\`\`\`bash
cp working-tree-copies/<path> <repo-root>/<path>
git -C <repo-root> add <path>
git -C <repo-root> commit -m "restore: <path>"
\`\`\`

### Restore from git's backup ref
\`\`\`bash
cd <repo-root>
git checkout refs/repo-janitor-backup/${date_str}-pre-cleanup -- <path>
\`\`\`
EOF

echo "bundle built at $bundle"
