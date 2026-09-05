#!/usr/bin/env bash
# db-health.sh — Postgres health snapshot: sizing, connections, vacuum, locks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a
# shellcheck disable=SC1090
source "${CONFIG_PATH}"
set +a

: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./db-health-$(date -u +%Y%m%dT%H%M%SZ).json}"

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

int_or_zero() {
    local value="${1:-0}"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${value}"
    else
        printf '0'
    fi
}

write_failed_json() {
    local reason="$1" remote_rc="$2" remote_output="${3:-}"
    mkdir -p "$(dirname "${OUT_JSON}")"
    {
        printf '{\n'
        printf '  "generated_at": %s,\n' "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
        printf '  "target_host": %s,\n' "$(json_string "${TARGET_HOST}")"
        printf '  "overall": "red",\n'
        printf '  "status": "failed",\n'
        printf '  "reason": %s,\n' "$(json_string "${reason}")"
        printf '  "remote_exit_code": %d,\n' "${remote_rc}"
        printf '  "remote_output": %s\n' "$(json_string "${remote_output}")"
        printf '}\n'
    } > "${OUT_JSON}"
}

remote_rc=0
# shellcheck disable=SC2086
remote_out=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" bash <<'REMOTE' 2>&1
set -euo pipefail
PSQL='sudo -n -u postgres psql -tAc'
DB='mattermost'

echo "---DB_SIZE---"
$PSQL "SELECT pg_size_pretty(pg_database_size('${DB}'))"

echo "---TOP_TABLES---"
$PSQL "SELECT schemaname||'.'||relname||'|'||pg_size_pretty(pg_total_relation_size(relid))||'|'||n_live_tup FROM pg_stat_user_tables WHERE schemaname='public' ORDER BY pg_total_relation_size(relid) DESC LIMIT 10" -d ${DB}

echo "---CONNECTION_USAGE---"
$PSQL "SELECT count(*)||'|'||(SELECT setting FROM pg_settings WHERE name='max_connections') FROM pg_stat_activity"

echo "---VACUUM_STATUS---"
$PSQL "SELECT schemaname||'.'||relname||'|'||COALESCE(last_vacuum::text,'never')||'|'||COALESCE(last_autovacuum::text,'never')||'|'||n_dead_tup FROM pg_stat_user_tables WHERE schemaname='public' ORDER BY n_dead_tup DESC LIMIT 10" -d ${DB}

echo "---LOCK_WAITS---"
$PSQL "SELECT count(*) FROM pg_locks WHERE NOT granted"

echo "---LONGEST_QUERY---"
$PSQL "SELECT COALESCE(extract(epoch FROM (now() - query_start))::int, 0)||'|'||COALESCE(left(query, 100), '') FROM pg_stat_activity WHERE state='active' AND query NOT ILIKE '%pg_stat_activity%' ORDER BY query_start ASC NULLS LAST LIMIT 1"
REMOTE
) || remote_rc=$?

if [[ "${remote_rc}" -ne 0 ]]; then
    printf '%s\n' "${remote_out}" >&2
    write_failed_json "remote db health command failed" "${remote_rc}" "${remote_out}"
    echo "JSON: ${OUT_JSON}"
    exit "${remote_rc}"
fi

get_section() {
    echo "${remote_out}" | awk -v tag="$1" 'BEGIN{p=0} /^---/{p=0} p==1{print} /^---'"$1"'---$/{p=1}'
}

db_size=$(get_section DB_SIZE | head -1)
top_tables=$(get_section TOP_TABLES)
conn_line=$(get_section CONNECTION_USAGE | head -1)
vacuum_lines=$(get_section VACUUM_STATUS)
lock_waits=$(get_section LOCK_WAITS | head -1)
longest=$(get_section LONGEST_QUERY | head -1)

conn_used=$(echo "${conn_line}" | cut -d'|' -f1)
conn_max=$(echo "${conn_line}" | cut -d'|' -f2)
conn_used=$(int_or_zero "${conn_used}")
conn_max=$(int_or_zero "${conn_max}")
if [[ -n "${conn_used}" && -n "${conn_max}" && "${conn_max}" != "0" ]]; then
    conn_pct=$(( conn_used * 100 / conn_max ))
else
    conn_pct=0
fi

longest_secs=$(echo "${longest}" | cut -d'|' -f1)
longest_secs=$(int_or_zero "${longest_secs}")
longest_query=$(echo "${longest}" | cut -d'|' -f2- | tr '\n' ' ')
lock_waits=$(int_or_zero "${lock_waits}")

overall="ok"
[[ "${conn_pct}" -ge "${HEALTH_PG_CONN_PCT_RED:-80}" ]] && overall="red"
[[ "${conn_pct}" -ge "${HEALTH_PG_CONN_PCT_YELLOW:-60}" && "${overall}" == "ok" ]] && overall="yellow"
[[ "${lock_waits}" -gt 5 ]] && overall="red"

mkdir -p "$(dirname "${OUT_JSON}")"
{
    printf '{\n'
    printf '  "generated_at": %s,\n' "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    printf '  "target_host": %s,\n' "$(json_string "${TARGET_HOST}")"
    printf '  "db_size": %s,\n' "$(json_string "${db_size}")"
    printf '  "connections_used": %s,\n' "${conn_used}"
    printf '  "connections_max": %s,\n' "${conn_max}"
    printf '  "connection_pct": %d,\n' "${conn_pct}"
    printf '  "lock_waits": %s,\n' "${lock_waits}"
    printf '  "longest_query_secs": %s,\n' "${longest_secs}"
    printf '  "longest_query": %s,\n' "$(json_string "${longest_query}")"
    printf '  "top_tables": [\n'
    first=1
    while IFS='|' read -r name sz rows; do
        [[ -z "${name}" ]] && continue
        [[ "${first}" == "1" ]] || printf ',\n'
        first=0
        printf '    {"name":%s,"size":%s,"rows":%s}' \
            "$(json_string "${name}")" \
            "$(json_string "${sz}")" \
            "$(int_or_zero "${rows}")"
    done <<< "${top_tables}"
    printf '\n  ],\n'
    printf '  "vacuum_status": [\n'
    first=1
    while IFS='|' read -r name last_vacuum last_autovacuum dead_tup; do
        [[ -z "${name}" ]] && continue
        [[ "${first}" == "1" ]] || printf ',\n'
        first=0
        printf '    {"name":%s,"last_vacuum":%s,"last_autovacuum":%s,"dead_tuples":%s}' \
            "$(json_string "${name}")" \
            "$(json_string "${last_vacuum}")" \
            "$(json_string "${last_autovacuum}")" \
            "$(int_or_zero "${dead_tup}")"
    done <<< "${vacuum_lines}"
    printf '\n  ],\n'
    printf '  "overall": %s\n' "$(json_string "${overall}")"
    printf '}\n'
} > "${OUT_JSON}"

echo "DB size: ${db_size}"
echo "Connections: ${conn_used}/${conn_max} (${conn_pct}%)"
echo "Lock waits: ${lock_waits:-0}"
echo "Overall: ${overall}"
echo "JSON: ${OUT_JSON}"

[[ "${overall}" == "red" ]] && exit 1
exit 0
