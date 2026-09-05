#!/usr/bin/env bash
# smoke-test-phase3.sh — dry-run every Phase 3 stage to verify config + reachability.
#
# Touches nothing destructive. For each stage, either a --dry-run flag is
# passed or a read-only variant runs. The point is to catch misconfig before
# a real run. Writes a summary JSON to workdir-phase3/reports/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${PHASE3_CONFIG:-${SCRIPT_DIR}/../config.env}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
    echo "ERROR: config.env not found at ${CONFIG_PATH}" >&2
    exit 2
fi

set -a
# shellcheck disable=SC1090
source "${CONFIG_PATH}"
set +a

: "${PHASE3_WORKSPACE_ROOT:=${SCRIPT_DIR}/../workdir-phase3}"
REPORTS_DIR="${PHASE3_WORKSPACE_ROOT}/reports"
mkdir -p "${REPORTS_DIR}"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${REPORTS_DIR}/smoke-test-${TS}.json"
LATEST="${REPORTS_DIR}/latest-smoke-test.json"

results=()
pass=0
fail=0
skip=0

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

http_status() {
    local code
    if code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null); then
        if [[ "${code}" =~ ^[0-9][0-9][0-9]$ ]]; then
            printf '%s' "${code}"
        else
            printf '000'
        fi
    else
        printf '000'
    fi
}

check() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        results+=("{\"check\":$(json_string "${name}"),\"status\":\"ok\"}")
        pass=$((pass+1))
        printf '  %-40s ok\n' "${name}"
    else
        results+=("{\"check\":$(json_string "${name}"),\"status\":\"fail\"}")
        fail=$((fail+1))
        printf '  %-40s FAIL\n' "${name}"
    fi
}

check_optional() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        results+=("{\"check\":$(json_string "${name}"),\"status\":\"ok\"}")
        pass=$((pass+1))
        printf '  %-40s ok\n' "${name}"
    else
        results+=("{\"check\":$(json_string "${name}"),\"status\":\"skip\"}")
        skip=$((skip+1))
        printf '  %-40s skip\n' "${name}"
    fi
}

config_set() {
    local var="$1"
    [[ -n "${!var:-}" ]]
}

mattermost_pat_reachable() {
    local code
    code=$(http_status \
        -H "Authorization: Bearer ${MATTERMOST_ADMIN_TOKEN:-x}" \
        "${MATTERMOST_URL:-http://unset}/api/v4/users/me")
    [[ "$code" == "200" ]]
}

ssh_target() {
    # Remote probes are fixed read-only command strings; config values are
    # passed as argv or shell-quoted before interpolation.
    # shellcheck disable=SC2029
    ssh "${SSH_OPTS[@]}" "${TARGET_SSH_USER:-deploy}@${TARGET_HOST:-unset}" "$@"
}

echo "=== Phase 3 smoke test ==="
echo "Config: ${CONFIG_PATH}"
echo "Target: ${TARGET_HOST:-<unset>} / ${MATTERMOST_URL:-<unset>}"
echo

echo "Workstation tools"
for t in ssh scp rsync jq curl psql pg_dump mmctl; do
    check "tool:${t}" command -v "$t"
done
check_optional "tool:rclone (optional)" command -v rclone

echo
echo "Config completeness"
for var in WORKSPACE_NAME MATTERMOST_URL MATTERMOST_ADMIN_TOKEN TARGET_HOST TARGET_SSH_USER POSTGRES_DSN BACKUP_PATH ROLLBACK_OWNER; do
    check "config:${var}" config_set "$var"
done
check_optional "config:OFFSITE_REMOTE (optional)" config_set OFFSITE_REMOTE
check_optional "config:SCRATCH_DB_URL (for restore-drill)" config_set SCRATCH_DB_URL

echo
echo "Reachability"
read -r -a SSH_OPTS <<< "${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
check "ssh:target" ssh_target true
check "http:mattermost_ping" curl -fsS --max-time 10 -o /dev/null "${MATTERMOST_URL:-http://unset}/api/v4/system/ping"
check "http:mattermost_pat" mattermost_pat_reachable

if [[ -n "${OFFSITE_REMOTE:-}" ]]; then
    check "rclone:offsite_reachable" rclone --max-depth 1 lsd "$OFFSITE_REMOTE"
fi

if [[ -n "${SCRATCH_DB_URL:-}" ]]; then
    check "psql:scratch_db_reachable" psql "$SCRATCH_DB_URL" -c "SELECT 1"
fi

echo
echo "Stage dry-runs (read-only queries only)"
# health-check.sh does not yet accept --dry-run; assert the script exists + is executable.
# os-update, backup, db-health are probed via read-only remote queries.
check "stage:health_script_present" test -x "${SCRIPT_DIR}/health-check.sh"
check "stage:os-update_dryrun" ssh_target "apt list --upgradable 2>/dev/null | head -1"
backup_path_q=$(printf '%q' "${BACKUP_PATH:-/var/backups/mattermost}")
check "stage:backup_dryrun" ssh_target "sudo -n test -d $backup_path_q || sudo -n test -w /var/backups"
check "stage:db-health_dryrun" ssh_target 'sudo -n -u postgres psql -tAc "SELECT 1"'

echo
echo "=== Summary: ${pass} passed, ${fail} failed, ${skip} skipped ==="

{
    printf '{\n'
    printf '  "generated_at": %s,\n' "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    printf '  "target_host": %s,\n' "$(json_string "${TARGET_HOST:-}")"
    printf '  "mattermost_url": %s,\n' "$(json_string "${MATTERMOST_URL:-}")"
    printf '  "passed": %d,\n' "${pass}"
    printf '  "failed": %d,\n' "${fail}"
    printf '  "skipped": %d,\n' "${skip}"
    printf '  "status": %s,\n' "$(json_string "$([[ ${fail} -eq 0 ]] && echo ok || echo fail)")"
    printf '  "checks": [\n    %s\n  ]\n' "$(IFS=,; echo "${results[*]}")"
    printf '}\n'
} > "${OUT}"

ln -sfn "$(basename "${OUT}")" "${LATEST}"

echo "JSON: ${OUT}"
[[ ${fail} -eq 0 ]] || exit 1
