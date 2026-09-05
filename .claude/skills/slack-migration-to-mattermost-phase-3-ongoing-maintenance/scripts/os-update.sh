#!/usr/bin/env bash
# os-update.sh — apply OS updates on the target host.
#
# OS_UPDATE_POLICY=security (default): installs unattended-upgrades security set only
# OS_UPDATE_POLICY=all: apt upgrade -y (everything)
# OS_UPDATE_POLICY=none: does nothing
#
# If a reboot is required after upgrades, a marker file is written (we do NOT
# reboot immediately); schedule-reboot.sh handles that in the configured window.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a
# shellcheck disable=SC1090
source "${CONFIG_PATH}"
set +a

: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${OS_UPDATE_POLICY:=security}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./os-update-$(date -u +%Y%m%dT%H%M%SZ).json}"

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

case "${OS_UPDATE_POLICY}" in
    none|security|all) ;;
    *)
        echo "ERROR: OS_UPDATE_POLICY must be one of: none, security, all" >&2
        mkdir -p "$(dirname "${OUT_JSON}")"
        printf '{"status": "skipped", "reason": "invalid OS_UPDATE_POLICY", "policy": %s}\n' \
            "$(json_string "${OS_UPDATE_POLICY}")" > "${OUT_JSON}"
        exit 2
        ;;
esac

if [[ "${OS_UPDATE_POLICY}" == "none" ]]; then
    echo "OS_UPDATE_POLICY=none; skipping"
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"skipped": true, "reason": "OS_UPDATE_POLICY=none"}\n' > "${OUT_JSON}"
    exit 0
fi

echo "Starting os-update (policy=${OS_UPDATE_POLICY}) on ${TARGET_HOST}"

# Build remote command based on policy
if [[ "${OS_UPDATE_POLICY}" == "security" ]]; then
    remote_cmd=$(cat <<'REMOTE'
set -euo pipefail
sudo -n DEBIAN_FRONTEND=noninteractive apt-get update -q
UPGRADABLE_COUNT=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
SECURITY_COUNT=$(apt list --upgradable 2>/dev/null | grep -c 'security' || true)
UPDATE_STATUS=ok
AUTOREMOVE_STATUS=ok
if ! sudo -n DEBIAN_FRONTEND=noninteractive unattended-upgrade -v 2>&1 | tail -n 40; then
  UPDATE_STATUS=failed
fi
if ! sudo -n DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q 2>&1 | tail -n 5; then
  AUTOREMOVE_STATUS=failed
fi
REBOOT_REQUIRED="no"
[[ -f /var/run/reboot-required ]] && REBOOT_REQUIRED="yes"
printf '\n---RESULT---\n'
printf 'upgradable=%s\n' "$UPGRADABLE_COUNT"
printf 'security=%s\n' "$SECURITY_COUNT"
printf 'reboot_required=%s\n' "$REBOOT_REQUIRED"
printf 'update_status=%s\n' "$UPDATE_STATUS"
printf 'autoremove_status=%s\n' "$AUTOREMOVE_STATUS"
REMOTE
)
elif [[ "${OS_UPDATE_POLICY}" == "all" ]]; then
    remote_cmd=$(cat <<'REMOTE'
set -euo pipefail
sudo -n DEBIAN_FRONTEND=noninteractive apt-get update -q
UPGRADABLE_COUNT=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
SECURITY_COUNT=$(apt list --upgradable 2>/dev/null | grep -c 'security' || true)
UPDATE_STATUS=ok
AUTOREMOVE_STATUS=ok
if ! sudo -n DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q 2>&1 | tail -n 20; then
  UPDATE_STATUS=failed
fi
if ! sudo -n DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q 2>&1 | tail -n 5; then
  AUTOREMOVE_STATUS=failed
fi
REBOOT_REQUIRED="no"
[[ -f /var/run/reboot-required ]] && REBOOT_REQUIRED="yes"
printf '\n---RESULT---\n'
printf 'upgradable=%s\n' "$UPGRADABLE_COUNT"
printf 'security=%s\n' "$SECURITY_COUNT"
printf 'reboot_required=%s\n' "$REBOOT_REQUIRED"
printf 'update_status=%s\n' "$UPDATE_STATUS"
printf 'autoremove_status=%s\n' "$AUTOREMOVE_STATUS"
REMOTE
)
fi

# shellcheck disable=SC2086
remote_rc=0
remote_out=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "bash -s" <<< "${remote_cmd}" 2>&1) || remote_rc=$?

echo "${remote_out}"

if [[ "${remote_rc}" -ne 0 ]]; then
    mkdir -p "$(dirname "${OUT_JSON}")"
    {
        printf '{\n'
        printf '  "generated_at": %s,\n' "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
        printf '  "target_host": %s,\n' "$(json_string "${TARGET_HOST}")"
        printf '  "policy": %s,\n' "$(json_string "${OS_UPDATE_POLICY}")"
        printf '  "remote_exit_code": %d,\n' "${remote_rc}"
        printf '  "remote_output": %s,\n' "$(json_string "${remote_out}")"
        printf '  "status": "failed"\n'
        printf '}\n'
    } > "${OUT_JSON}"
    echo "JSON: ${OUT_JSON}"
    exit "${remote_rc}"
fi

# Parse the ---RESULT--- footer
result_section=$(echo "${remote_out}" | sed -n '/^---RESULT---$/,$p' | tail -n +2)
upgradable=$(echo "${result_section}" | awk -F= '/^upgradable=/ {print $2}')
security=$(echo "${result_section}" | awk -F= '/^security=/ {print $2}')
reboot_req=$(echo "${result_section}" | awk -F= '/^reboot_required=/ {print $2}')
update_status=$(echo "${result_section}" | awk -F= '/^update_status=/ {print $2}')
autoremove_status=$(echo "${result_section}" | awk -F= '/^autoremove_status=/ {print $2}')
upgradable=$(int_or_zero "${upgradable}")
security=$(int_or_zero "${security}")
case "${reboot_req}" in
    yes|no) ;;
    *) reboot_req="unknown" ;;
esac
case "${update_status}" in
    ok|failed) ;;
    *) update_status="unknown" ;;
esac
case "${autoremove_status}" in
    ok|failed) ;;
    *) autoremove_status="unknown" ;;
esac

overall_status="success"
if [[ "${update_status}" != "ok" || "${autoremove_status}" != "ok" ]]; then
    overall_status="failed"
fi

mkdir -p "$(dirname "${OUT_JSON}")"
{
    printf '{\n'
    printf '  "generated_at": %s,\n' "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    printf '  "target_host": %s,\n' "$(json_string "${TARGET_HOST}")"
    printf '  "policy": %s,\n' "$(json_string "${OS_UPDATE_POLICY}")"
    printf '  "upgradable_before": %s,\n' "${upgradable}"
    printf '  "security_before": %s,\n' "${security}"
    printf '  "reboot_required": %s,\n' "$(json_string "${reboot_req}")"
    printf '  "update_status": %s,\n' "$(json_string "${update_status}")"
    printf '  "autoremove_status": %s,\n' "$(json_string "${autoremove_status}")"
    printf '  "status": %s\n' "$(json_string "${overall_status}")"
    printf '}\n'
} > "${OUT_JSON}"

if [[ "${reboot_req}" == "yes" ]]; then
    echo
    echo "Reboot is required on ${TARGET_HOST}. Run ./maintain.sh schedule-reboot to queue it for the next ${REBOOT_WINDOW_DAY:-Sun} ${REBOOT_WINDOW_HOUR_START:-3}:00 UTC window."
fi

echo "JSON: ${OUT_JSON}"
if [[ "${overall_status}" == "failed" ]]; then
    exit 1
fi
exit 0
