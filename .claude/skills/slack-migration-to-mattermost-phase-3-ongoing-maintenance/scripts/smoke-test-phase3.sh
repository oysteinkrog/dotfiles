#!/usr/bin/env bash
# smoke-test-phase3.sh — dry-run every Phase 3 stage to verify config + reachability.
#
# Touches nothing destructive. For each stage, either a --dry-run flag is
# passed or a read-only variant runs. The point is to catch misconfig before
# a real run. Writes a summary JSON to workdir-phase3/reports/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${PHASE3_CONFIG:-${SCRIPT_DIR}/../config.env}"
set -a; source "${CONFIG_PATH}"; set +a

: "${PHASE3_WORKSPACE_ROOT:=${SCRIPT_DIR}/../workdir-phase3}"
REPORTS_DIR="${PHASE3_WORKSPACE_ROOT}/reports"
mkdir -p "${REPORTS_DIR}"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${REPORTS_DIR}/smoke-test-${TS}.json"
LATEST="${REPORTS_DIR}/latest-smoke-test.json"

results=()
pass=0
fail=0

check() {
    local name="$1" cmd="$2"
    if eval "${cmd}" >/dev/null 2>&1; then
        results+=("{\"check\":\"${name}\",\"status\":\"ok\"}")
        pass=$((pass+1))
        printf '  %-40s ok\n' "${name}"
    else
        results+=("{\"check\":\"${name}\",\"status\":\"fail\"}")
        fail=$((fail+1))
        printf '  %-40s FAIL\n' "${name}"
    fi
}

echo "=== Phase 3 smoke test ==="
echo "Config: ${CONFIG_PATH}"
echo "Target: ${TARGET_HOST:-<unset>} / ${MATTERMOST_URL:-<unset>}"
echo

echo "Workstation tools"
for t in ssh scp rsync jq curl psql pg_dump mmctl; do
    check "tool:${t}" "command -v ${t}"
done
check "tool:rclone (optional)" "command -v rclone"

echo
echo "Config completeness"
for var in WORKSPACE_NAME MATTERMOST_URL MATTERMOST_ADMIN_TOKEN TARGET_HOST TARGET_SSH_USER POSTGRES_DSN BACKUP_PATH ROLLBACK_OWNER; do
    check "config:${var}" "[[ -n \"\${${var}:-}\" ]]"
done
check "config:OFFSITE_REMOTE (optional)" "[[ -n \"\${OFFSITE_REMOTE:-}\" ]]"
check "config:SCRATCH_DB_URL (for restore-drill)" "[[ -n \"\${SCRATCH_DB_URL:-}\" ]]"

echo
echo "Reachability"
SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
check "ssh:target" "ssh ${SSH_OPTS} ${TARGET_SSH_USER:-deploy}@${TARGET_HOST:-unset} true"
check "http:mattermost_ping" "curl -fsS --max-time 10 -o /dev/null ${MATTERMOST_URL:-http://unset}/api/v4/system/ping"
check "http:mattermost_pat" "[[ \$(curl -fsS --max-time 10 -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer ${MATTERMOST_ADMIN_TOKEN:-x}' ${MATTERMOST_URL:-http://unset}/api/v4/users/me 2>/dev/null) == '200' ]]"

if [[ -n "${OFFSITE_REMOTE:-}" ]]; then
    check "rclone:offsite_reachable" "rclone --max-depth 1 lsd '${OFFSITE_REMOTE}'"
fi

if [[ -n "${SCRATCH_DB_URL:-}" ]]; then
    check "psql:scratch_db_reachable" "psql '${SCRATCH_DB_URL}' -c 'SELECT 1'"
fi

echo
echo "Stage dry-runs (read-only queries only)"
# health-check.sh does not yet accept --dry-run; assert the script exists + is executable.
# os-update, backup, db-health are probed via read-only remote queries.
check "stage:health_script_present" "[[ -x '${SCRIPT_DIR}/health-check.sh' ]]"
check "stage:os-update_dryrun" "ssh ${SSH_OPTS} ${TARGET_SSH_USER:-deploy}@${TARGET_HOST:-unset} 'apt list --upgradable 2>/dev/null | head -1'"
check "stage:backup_dryrun" "ssh ${SSH_OPTS} ${TARGET_SSH_USER:-deploy}@${TARGET_HOST:-unset} 'sudo -n test -d ${BACKUP_PATH:-/var/backups/mattermost} || sudo -n test -w /var/backups'"
check "stage:db-health_dryrun" "ssh ${SSH_OPTS} ${TARGET_SSH_USER:-deploy}@${TARGET_HOST:-unset} 'sudo -n -u postgres psql -tAc \"SELECT 1\"'"

echo
echo "=== Summary: ${pass} passed, ${fail} failed ==="

{
    printf '{\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "target_host": "%s",\n' "${TARGET_HOST:-}"
    printf '  "mattermost_url": "%s",\n' "${MATTERMOST_URL:-}"
    printf '  "passed": %d,\n' "${pass}"
    printf '  "failed": %d,\n' "${fail}"
    printf '  "status": "%s",\n' "$([[ ${fail} -eq 0 ]] && echo ok || echo fail)"
    printf '  "checks": [\n    %s\n  ]\n' "$(IFS=,; echo "${results[*]}")"
    printf '}\n'
} > "${OUT}"

ln -sfn "$(basename "${OUT}")" "${LATEST}"

echo "JSON: ${OUT}"
[[ ${fail} -eq 0 ]] || exit 1
