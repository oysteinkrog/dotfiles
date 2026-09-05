#!/usr/bin/env bash
# Phase 2.5 / harden-secret-leak Step 1: create mirror backup before any history rewrite.
# Per references/MIRROR-BACKUP-DRILL.md.
# Usage: mirror-backup.sh <project> [--out=<path>]
set -euo pipefail

project="${1:?usage: mirror-backup.sh <project> [--out=<path>]}"
cd "$project"

ts=$(date -u +%Y%m%dT%H%M%SZ)
repo_basename=$(basename "$project")
out="/tmp/${repo_basename}-backup-${ts}.git"

for arg in "$@"; do
    case "$arg" in
        --out=*) out="${arg#*=}" ;;
    esac
done

if [[ -e "$out" ]]; then
    echo "ERROR: $out already exists; aborting" >&2
    exit 1
fi

echo "Creating mirror backup at $out ..."
git clone --mirror . "$out"

# Verify completeness
echo ""
echo "=== Verification ==="
ref_count_local=$(git for-each-ref | wc -l)
ref_count_backup=$(git --git-dir="$out" for-each-ref | wc -l)
echo "Local refs:   $ref_count_local"
echo "Backup refs:  $ref_count_backup"
[[ "$ref_count_backup" -ge "$ref_count_local" ]] || {
    echo "FAIL: backup has fewer refs than local"
    exit 1
}

# git fsck on the backup
echo ""
echo "=== Backup integrity ==="
git --git-dir="$out" fsck --no-progress 2>&1 | head -20

# Size
echo ""
size=$(du -sh "$out" | awk '{print $1}')
echo "Backup size: $size"

# Record in workspace. `echo -e` is non-portable (bash xpg_echo dependent),
# so use printf for the TSV header.
ws="$project/.repo_janitor_workspace"
mkdir -p "$ws"
if [[ ! -f "$ws/mirror_backups.tsv" ]]; then
    printf 'created_at\tpath\tsize\treason\toriginal_repo_sha\n' > "$ws/mirror_backups.tsv"
fi
head_sha=$(git rev-parse HEAD)
printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$out" \
    "$size" \
    "${REASON:-pre-filter-repo}" \
    "$head_sha" >> "$ws/mirror_backups.tsv"

echo ""
echo "BACKUP_PATH=$out"
echo ""
echo "DONE. Backup recorded in $ws/mirror_backups.tsv"
