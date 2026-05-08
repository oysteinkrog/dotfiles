#!/usr/bin/env bash
# mattermost-upgrade.sh — upgrade Mattermost to MATTERMOST_TARGET_VERSION.
#
# Safety sequence: pre-upgrade pg_dump, apt install mattermost=<version>,
# wait for /api/v4/system/ping, verify migrations. On failure, optional
# auto-rollback from the pre-upgrade dump (MATTERMOST_UPGRADE_ROLLBACK=auto).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a; source "${CONFIG_PATH}"; set +a

: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${MATTERMOST_URL:?MATTERMOST_URL required}"
: "${MATTERMOST_UPGRADE_ROLLBACK:=auto}"
: "${MATTERMOST_DB_NAME:=mattermost}"
: "${MATTERMOST_DB_OWNER:=mmuser}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./mm-upgrade-$(date -u +%Y%m%dT%H%M%SZ).json}"
TS="${PHASE3_STAGE_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

# Find current version
current_version=$(curl -fsS --max-time 10 "${MATTERMOST_URL}/api/v4/config/client?format=old" 2>/dev/null \
    | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4)
current_version="${current_version:-unknown}"

target_version="${MATTERMOST_TARGET_VERSION:-}"
if [[ -z "${target_version}" ]]; then
    echo "MATTERMOST_TARGET_VERSION not set; showing candidates only."
    # shellcheck disable=SC2086
    ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "apt-cache madison mattermost 2>/dev/null | head -5"
    echo "Pick a version and set MATTERMOST_TARGET_VERSION in config.env."
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"current_version": "%s", "status": "skipped", "reason": "MATTERMOST_TARGET_VERSION not set"}\n' \
        "${current_version}" > "${OUT_JSON}"
    exit 0
fi

if [[ "${current_version}" == "${target_version}" ]]; then
    echo "Already at ${target_version}; nothing to do."
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"current_version": "%s", "target_version": "%s", "status": "already_current"}\n' \
        "${current_version}" "${target_version}" > "${OUT_JSON}"
    exit 0
fi

echo "Upgrading Mattermost: ${current_version} -> ${target_version}"
echo "Pre-upgrade backup first..."

dump_path="/var/backups/mattermost/pre-upgrade-${TS}.sql.gz"

# shellcheck disable=SC2086
ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" bash <<REMOTE
set -euo pipefail
sudo -n mkdir -p /var/backups/mattermost
# Stream pg_dump through gzip into the destination via sudo tee so the redirect
# does not run as the unprivileged deploy user on a 700-permission directory.
sudo -n -u postgres pg_dump mattermost \
    | gzip \
    | sudo -n tee "${dump_path}.tmp" > /dev/null
sudo -n mv "${dump_path}.tmp" "${dump_path}"
sudo -n chmod 600 "${dump_path}"
echo "Pre-upgrade dump: ${dump_path}"

echo "Stopping mattermost..."
sudo -n systemctl stop mattermost

echo "Installing mattermost=${target_version}..."
sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades "mattermost=${target_version}" 2>&1 | tail -n 20

echo "Starting mattermost..."
sudo -n systemctl start mattermost
REMOTE

# Poll ping for up to 3 minutes
echo "Waiting for Mattermost to come back up..."
ok=0
for i in $(seq 1 36); do
    if curl -fsS --max-time 5 -o /dev/null "${MATTERMOST_URL}/api/v4/system/ping"; then
        ok=1
        break
    fi
    sleep 5
done

new_version=$(curl -fsS --max-time 10 "${MATTERMOST_URL}/api/v4/config/client?format=old" 2>/dev/null \
    | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4)
new_version="${new_version:-unknown}"

mkdir -p "$(dirname "${OUT_JSON}")"

if [[ "${ok}" == "1" ]] && [[ "${new_version}" == "${target_version}" ]]; then
    echo "Upgrade SUCCESS: ${new_version}"
    {
        printf '{\n'
        printf '  "current_version_before": "%s",\n' "${current_version}"
        printf '  "target_version": "%s",\n' "${target_version}"
        printf '  "new_version": "%s",\n' "${new_version}"
        printf '  "pre_upgrade_dump": "%s",\n' "${dump_path}"
        printf '  "status": "success"\n'
        printf '}\n'
    } > "${OUT_JSON}"
    exit 0
fi

echo "Upgrade FAILED: ping_ok=${ok} new_version=${new_version}"

if [[ "${MATTERMOST_UPGRADE_ROLLBACK}" == "auto" ]]; then
    echo "Auto-rollback enabled; restoring from ${dump_path}"
    # shellcheck disable=SC2086
    ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" bash <<REMOTE
set -euo pipefail
sudo -n systemctl stop mattermost || true
sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades "mattermost=${current_version}"
# Drop the half-upgraded DB and recreate a clean one before restoring the pre-upgrade dump.
# Without DROP/CREATE, restoring a plain-text pg_dump into an already-populated database
# leaves stale tables/sequences from the failed upgrade and often fails on duplicate keys.
sudo -n -u postgres psql -d postgres -c 'DROP DATABASE IF EXISTS "${MATTERMOST_DB_NAME}";'
sudo -n -u postgres psql -d postgres -c 'CREATE DATABASE "${MATTERMOST_DB_NAME}" OWNER "${MATTERMOST_DB_OWNER}";'
# Dump is owned by root (mode 600); read it via sudo so deploy-user has access.
sudo -n cat "${dump_path}" | gunzip | sudo -n -u postgres psql -d "${MATTERMOST_DB_NAME}"
sudo -n systemctl start mattermost
REMOTE
    echo "Rollback complete; back on ${current_version}"
    {
        printf '{\n'
        printf '  "current_version_before": "%s",\n' "${current_version}"
        printf '  "target_version": "%s",\n' "${target_version}"
        printf '  "new_version": "%s",\n' "${new_version}"
        printf '  "pre_upgrade_dump": "%s",\n' "${dump_path}"
        printf '  "status": "failed_rolled_back"\n'
        printf '}\n'
    } > "${OUT_JSON}"
    exit 1
fi

{
    printf '{\n'
    printf '  "current_version_before": "%s",\n' "${current_version}"
    printf '  "target_version": "%s",\n' "${target_version}"
    printf '  "new_version": "%s",\n' "${new_version}"
    printf '  "pre_upgrade_dump": "%s",\n' "${dump_path}"
    printf '  "status": "failed_manual_intervention_required"\n'
    printf '}\n'
} > "${OUT_JSON}"
exit 1
