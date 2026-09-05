#!/usr/bin/env bash
# restore-drill.sh — quarterly backup restore verification.
# Downloads newest off-site backup, restores into SCRATCH_DB_URL, sanity-checks row counts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
    echo "ERROR: config.env not found at ${CONFIG_PATH}" >&2
    exit 2
fi

set -a
# shellcheck disable=SC1090
source "${CONFIG_PATH}"
set +a

: "${SCRATCH_DB_URL:?SCRATCH_DB_URL required for restore-drill}"
: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${BACKUP_PATH:=/var/backups/mattermost}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./restore-drill-$(date -u +%Y%m%dT%H%M%SZ).json}"

json_string() {
    local value="${1:-}"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "${value}" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1]))
PY
        return 0
    fi

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '"%s"' "${value}"
}

json_number_or_zero() {
    local value="${1:-0}"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${value}"
    else
        printf '0'
    fi
}

write_failure() {
    local reason="$1"
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"status":"failed","reason":%s}\n' "$(json_string "${reason}")" > "${OUT_JSON}"
}

shell_quote() {
    local value="$1"
    local escaped="${value//\'/\'\\\'\'}"
    printf "'%s'" "${escaped}"
}

for threshold_name in RESTORE_MIN_USERS RESTORE_MIN_CHANNELS RESTORE_MIN_POSTS; do
    threshold_value="${!threshold_name:-0}"
    if [[ ! "${threshold_value}" =~ ^[0-9]+$ ]]; then
        echo "Invalid ${threshold_name}: ${threshold_value}" >&2
        write_failure "invalid ${threshold_name}"
        exit 2
    fi
done

echo "Selecting newest backup..."

if [[ -n "${OFFSITE_REMOTE:-}" ]]; then
    offsite_remote_q=$(shell_quote "${OFFSITE_REMOTE}/")
    # shellcheck disable=SC2086,SC2029
    newest=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n rclone lsf ${offsite_remote_q} 2>/dev/null | grep '^mm_.*\.sql\.gz$' | sort | tail -1" \
        || echo "")
    source_kind="offsite"
    source_path="${OFFSITE_REMOTE}/${newest}"
else
    backup_path_q=$(shell_quote "${BACKUP_PATH}")
    # shellcheck disable=SC2086,SC2029
    newest=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n find ${backup_path_q} -maxdepth 1 -name 'mm_*.sql.gz' -printf '%f\n' 2>/dev/null | sort | tail -1" \
        || echo "")
    source_kind="local"
    source_path="${BACKUP_PATH}/${newest}"
fi

if [[ -z "${newest}" ]]; then
    echo "No backup found" >&2
    write_failure "no backup found"
    exit 1
fi

echo "Restoring ${source_path} -> SCRATCH_DB_URL (recreating DB)"

# Recreate scratch DB to ensure a clean slate
db_name=$(echo "${SCRATCH_DB_URL}" | sed -E 's|.*/([^?]+).*|\1|')
admin_url=$(echo "${SCRATCH_DB_URL}" | sed -E 's|/[^/?]+(\?.*)?$|/postgres\1|')
if [[ ! "${db_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Invalid scratch database name parsed from SCRATCH_DB_URL: ${db_name}" >&2
    write_failure "invalid scratch database name"
    exit 2
fi

psql "${admin_url}" -c "DROP DATABASE IF EXISTS \"${db_name}\";" >/dev/null
psql "${admin_url}" -c "CREATE DATABASE \"${db_name}\";" >/dev/null

# Stream the backup through psql
source_path_q=$(shell_quote "${source_path}")
if [[ "${source_kind}" == "offsite" ]]; then
    # shellcheck disable=SC2086,SC2029
    ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n rclone cat ${source_path_q}" | gunzip | psql "${SCRATCH_DB_URL}" > /dev/null
else
    # shellcheck disable=SC2086,SC2029
    ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n cat ${source_path_q}" | gunzip | psql "${SCRATCH_DB_URL}" > /dev/null
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
if [[ ! "${users}" =~ ^[0-9]+$ ]]; then
    status="failed"
    notes+=("users count invalid")
    users=0
fi
if [[ ! "${channels}" =~ ^[0-9]+$ ]]; then
    status="failed"
    notes+=("channels count invalid")
    channels=0
fi
if [[ ! "${posts}" =~ ^[0-9]+$ ]]; then
    status="failed"
    notes+=("posts count invalid")
    posts=0
fi

min_users="${RESTORE_MIN_USERS:-0}"
min_channels="${RESTORE_MIN_CHANNELS:-0}"
min_posts="${RESTORE_MIN_POSTS:-0}"
(( users < min_users )) && { status="failed"; notes+=("users ${users} < min ${min_users}"); }
(( channels < min_channels )) && { status="failed"; notes+=("channels ${channels} < min ${min_channels}"); }
(( posts < min_posts )) && { status="failed"; notes+=("posts ${posts} < min ${min_posts}"); }

note_str=$(IFS='; '; echo "${notes[*]}")

mkdir -p "$(dirname "${OUT_JSON}")"
{
    printf '{\n'
    printf '  "generated_at": %s,\n' "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    printf '  "source_kind": %s,\n' "$(json_string "${source_kind}")"
    printf '  "source_path": %s,\n' "$(json_string "${source_path}")"
    printf '  "scratch_db": %s,\n' "$(json_string "${db_name}")"
    printf '  "users": %s,\n' "$(json_number_or_zero "${users}")"
    printf '  "channels": %s,\n' "$(json_number_or_zero "${channels}")"
    printf '  "posts": %s,\n' "$(json_number_or_zero "${posts}")"
    printf '  "min_users": %s,\n' "$(json_number_or_zero "${min_users}")"
    printf '  "min_channels": %s,\n' "$(json_number_or_zero "${min_channels}")"
    printf '  "min_posts": %s,\n' "$(json_number_or_zero "${min_posts}")"
    printf '  "note": %s,\n' "$(json_string "${note_str}")"
    printf '  "status": %s\n' "$(json_string "${status}")"
    printf '}\n'
} > "${OUT_JSON}"

echo "users=${users} channels=${channels} posts=${posts}"
echo "Status: ${status}"
echo "JSON: ${OUT_JSON}"

[[ "${status}" == "failed" ]] && exit 1
exit 0
