#!/usr/bin/env bash
# restore-drill.sh — quarterly backup restore verification.
# Downloads newest off-site backup, restores into SCRATCH_DB_URL, sanity-checks row counts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a; source "${CONFIG_PATH}"; set +a

: "${SCRATCH_DB_URL:?SCRATCH_DB_URL required for restore-drill}"
: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${BACKUP_PATH:=/var/backups/mattermost}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./restore-drill-$(date -u +%Y%m%dT%H%M%SZ).json}"

echo "Selecting newest backup..."

if [[ -n "${OFFSITE_REMOTE:-}" ]]; then
    newest=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n rclone lsf '${OFFSITE_REMOTE}/' 2>/dev/null | grep '^mm_.*\.sql\.gz$' | sort | tail -1" \
        || echo "")
    source_kind="offsite"
    source_path="${OFFSITE_REMOTE}/${newest}"
else
    newest=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n ls -1 ${BACKUP_PATH}/mm_*.sql.gz 2>/dev/null | sort | tail -1 | xargs -r basename" \
        || echo "")
    source_kind="local"
    source_path="${BACKUP_PATH}/${newest}"
fi

if [[ -z "${newest}" ]]; then
    echo "No backup found" >&2
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"status": "failed", "reason": "no backup found"}\n' > "${OUT_JSON}"
    exit 1
fi

echo "Restoring ${source_path} -> SCRATCH_DB_URL (recreating DB)"

# Recreate scratch DB to ensure a clean slate
db_name=$(echo "${SCRATCH_DB_URL}" | sed -E 's|.*/([^?]+).*|\1|')
admin_url=$(echo "${SCRATCH_DB_URL}" | sed -E 's|/[^/?]+(\?.*)?$|/postgres\1|')

psql "${admin_url}" -c "DROP DATABASE IF EXISTS ${db_name};" >/dev/null
psql "${admin_url}" -c "CREATE DATABASE ${db_name};" >/dev/null

# Stream the backup through psql
if [[ "${source_kind}" == "offsite" ]]; then
    # shellcheck disable=SC2086
    ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n rclone cat '${source_path}'" | gunzip | psql "${SCRATCH_DB_URL}" > /dev/null
else
    # shellcheck disable=SC2086
    ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n cat '${source_path}'" | gunzip | psql "${SCRATCH_DB_URL}" > /dev/null
fi

echo "Restore complete; counting rows..."

# Mattermost tables use quoted PascalCase identifiers ("Users", "Channels", "Posts").
users=$(psql "${SCRATCH_DB_URL}" -tAc 'SELECT count(*) FROM "Users"' 2>/dev/null || echo 0)
channels=$(psql "${SCRATCH_DB_URL}" -tAc 'SELECT count(*) FROM "Channels"' 2>/dev/null || echo 0)
posts=$(psql "${SCRATCH_DB_URL}" -tAc 'SELECT count(*) FROM "Posts"' 2>/dev/null || echo 0)
# Strip any whitespace psql may emit
users="${users// /}"
channels="${channels// /}"
posts="${posts// /}"

status="ok"
notes=()
(( users < ${RESTORE_MIN_USERS:-0} )) && { status="failed"; notes+=("users ${users} < min ${RESTORE_MIN_USERS}"); }
(( channels < ${RESTORE_MIN_CHANNELS:-0} )) && { status="failed"; notes+=("channels ${channels} < min ${RESTORE_MIN_CHANNELS}"); }
(( posts < ${RESTORE_MIN_POSTS:-0} )) && { status="failed"; notes+=("posts ${posts} < min ${RESTORE_MIN_POSTS}"); }

note_str=$(IFS='; '; echo "${notes[*]}")

mkdir -p "$(dirname "${OUT_JSON}")"
{
    printf '{\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "source_kind": "%s",\n' "${source_kind}"
    printf '  "source_path": "%s",\n' "${source_path}"
    printf '  "scratch_db": "%s",\n' "${db_name}"
    printf '  "users": %s,\n' "${users}"
    printf '  "channels": %s,\n' "${channels}"
    printf '  "posts": %s,\n' "${posts}"
    printf '  "min_users": %s,\n' "${RESTORE_MIN_USERS:-0}"
    printf '  "min_channels": %s,\n' "${RESTORE_MIN_CHANNELS:-0}"
    printf '  "min_posts": %s,\n' "${RESTORE_MIN_POSTS:-0}"
    printf '  "note": "%s",\n' "${note_str}"
    printf '  "status": "%s"\n' "${status}"
    printf '}\n'
} > "${OUT_JSON}"

echo "users=${users} channels=${channels} posts=${posts}"
echo "Status: ${status}"
echo "JSON: ${OUT_JSON}"

[[ "${status}" == "failed" ]] && exit 1
exit 0
