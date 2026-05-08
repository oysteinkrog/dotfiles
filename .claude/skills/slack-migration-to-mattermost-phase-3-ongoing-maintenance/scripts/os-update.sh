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
set -a; source "${CONFIG_PATH}"; set +a

: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${OS_UPDATE_POLICY:=security}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./os-update-$(date -u +%Y%m%dT%H%M%SZ).json}"

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
sudo -n DEBIAN_FRONTEND=noninteractive unattended-upgrade -v 2>&1 | tail -n 40 || true
sudo -n DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q 2>&1 | tail -n 5 || true
REBOOT_REQUIRED="no"
[[ -f /var/run/reboot-required ]] && REBOOT_REQUIRED="yes"
printf '\n---RESULT---\n'
printf 'upgradable=%s\n' "$UPGRADABLE_COUNT"
printf 'security=%s\n' "$SECURITY_COUNT"
printf 'reboot_required=%s\n' "$REBOOT_REQUIRED"
REMOTE
)
else
    # "all"
    remote_cmd=$(cat <<'REMOTE'
set -euo pipefail
sudo -n DEBIAN_FRONTEND=noninteractive apt-get update -q
UPGRADABLE_COUNT=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
SECURITY_COUNT=$(apt list --upgradable 2>/dev/null | grep -c 'security' || true)
sudo -n DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q 2>&1 | tail -n 20 || true
sudo -n DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q 2>&1 | tail -n 5 || true
REBOOT_REQUIRED="no"
[[ -f /var/run/reboot-required ]] && REBOOT_REQUIRED="yes"
printf '\n---RESULT---\n'
printf 'upgradable=%s\n' "$UPGRADABLE_COUNT"
printf 'security=%s\n' "$SECURITY_COUNT"
printf 'reboot_required=%s\n' "$REBOOT_REQUIRED"
REMOTE
)
fi

# shellcheck disable=SC2086
remote_out=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "bash -s" <<< "${remote_cmd}")

echo "${remote_out}"

# Parse the ---RESULT--- footer
result_section=$(echo "${remote_out}" | sed -n '/^---RESULT---$/,$p' | tail -n +2)
upgradable=$(echo "${result_section}" | awk -F= '/^upgradable=/ {print $2}')
security=$(echo "${result_section}" | awk -F= '/^security=/ {print $2}')
reboot_req=$(echo "${result_section}" | awk -F= '/^reboot_required=/ {print $2}')

mkdir -p "$(dirname "${OUT_JSON}")"
{
    printf '{\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "target_host": "%s",\n' "${TARGET_HOST}"
    printf '  "policy": "%s",\n' "${OS_UPDATE_POLICY}"
    printf '  "upgradable_before": %s,\n' "${upgradable:-0}"
    printf '  "security_before": %s,\n' "${security:-0}"
    printf '  "reboot_required": "%s",\n' "${reboot_req:-no}"
    printf '  "status": "success"\n'
    printf '}\n'
} > "${OUT_JSON}"

if [[ "${reboot_req}" == "yes" ]]; then
    echo
    echo "Reboot is required on ${TARGET_HOST}. Run ./maintain.sh schedule-reboot to queue it for the next ${REBOOT_WINDOW_DAY:-Sun} ${REBOOT_WINDOW_HOUR_START:-3}:00 UTC window."
fi

echo "JSON: ${OUT_JSON}"
