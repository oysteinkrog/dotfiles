#!/usr/bin/env bash
# mattermost-upgrade.sh — upgrade Mattermost to MATTERMOST_TARGET_VERSION.
#
# Safety sequence: pre-upgrade pg_dump, apt install mattermost=<version>,
# wait for /api/v4/system/ping, verify migrations. On failure, optional
# auto-rollback from the pre-upgrade dump (MATTERMOST_UPGRADE_ROLLBACK=auto).

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

: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${MATTERMOST_URL:?MATTERMOST_URL required}"
: "${MATTERMOST_UPGRADE_ROLLBACK:=auto}"
: "${MATTERMOST_DB_NAME:=mattermost}"
: "${MATTERMOST_DB_OWNER:=mmuser}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./mm-upgrade-$(date -u +%Y%m%dT%H%M%SZ).json}"
TS="${PHASE3_STAGE_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

shell_quote() {
    local value="$1"
    local escaped="${value//\'/\'\\\'\'}"
    printf "'%s'" "${escaped}"
}

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

is_package_version() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.+:~_-]*$ ]]
}

package_app_version() {
    local version="$1"
    version="${version##*:}"
    version="${version%%-*}"
    printf '%s' "${version}"
}

is_sql_identifier() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

if [[ ! "${TS}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: PHASE3_STAGE_TIMESTAMP must be a safe filename segment" >&2
    exit 2
fi
if ! is_sql_identifier "${MATTERMOST_DB_NAME}"; then
    echo "ERROR: MATTERMOST_DB_NAME must be a simple SQL identifier" >&2
    exit 2
fi
if ! is_sql_identifier "${MATTERMOST_DB_OWNER}"; then
    echo "ERROR: MATTERMOST_DB_OWNER must be a simple SQL identifier" >&2
    exit 2
fi
case "${MATTERMOST_UPGRADE_ROLLBACK}" in
    auto|manual) ;;
    *)
        echo "ERROR: MATTERMOST_UPGRADE_ROLLBACK must be auto or manual" >&2
        mkdir -p "$(dirname "${OUT_JSON}")"
        printf '{"rollback_policy": %s, "status": "skipped", "reason": "invalid rollback policy"}\n' \
            "$(json_string "${MATTERMOST_UPGRADE_ROLLBACK}")" > "${OUT_JSON}"
        exit 2
        ;;
esac

# Find current version
current_version=$(
    curl -fsS --max-time 10 "${MATTERMOST_URL}/api/v4/config/client?format=old" 2>/dev/null \
        | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4 \
        || true
)
current_version="${current_version:-unknown}"
current_package_version=$(
    # shellcheck disable=SC2086
    ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "dpkg-query -W -f='\${Version}' mattermost 2>/dev/null || true" \
        2>/dev/null || true
)
current_package_version="${current_package_version:-unknown}"

target_version="${MATTERMOST_TARGET_VERSION:-}"
if [[ -z "${target_version}" ]]; then
    echo "MATTERMOST_TARGET_VERSION not set; showing candidates only."
    # shellcheck disable=SC2086
    ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "apt-cache madison mattermost 2>/dev/null | head -5"
    echo "Pick a version and set MATTERMOST_TARGET_VERSION in config.env."
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"current_version": %s, "status": "skipped", "reason": "MATTERMOST_TARGET_VERSION not set"}\n' \
        "$(json_string "${current_version}")" > "${OUT_JSON}"
    exit 0
fi
if ! is_package_version "${target_version}"; then
    echo "ERROR: MATTERMOST_TARGET_VERSION contains unsafe package-version characters" >&2
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"target_version": %s, "status": "skipped", "reason": "invalid target version"}\n' \
        "$(json_string "${target_version}")" > "${OUT_JSON}"
    exit 2
fi
target_app_version="${MATTERMOST_TARGET_APP_VERSION:-$(package_app_version "${target_version}")}"
if ! is_package_version "${target_app_version}"; then
    echo "ERROR: MATTERMOST_TARGET_APP_VERSION contains unsafe version characters" >&2
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"target_app_version": %s, "status": "skipped", "reason": "invalid target app version"}\n' \
        "$(json_string "${target_app_version}")" > "${OUT_JSON}"
    exit 2
fi

write_upgrade_failure_json() {
    local status="$1" reason="$2" new_version_value="${3:-unknown}" remote_rc="${4:-1}" remote_output="${5:-}"
    mkdir -p "$(dirname "${OUT_JSON}")"
    {
        printf '{\n'
        printf '  "current_version_before": %s,\n' "$(json_string "${current_version}")"
        printf '  "current_package_version_before": %s,\n' "$(json_string "${current_package_version}")"
        printf '  "target_version": %s,\n' "$(json_string "${target_version}")"
        printf '  "target_app_version": %s,\n' "$(json_string "${target_app_version}")"
        printf '  "new_version": %s,\n' "$(json_string "${new_version_value}")"
        printf '  "pre_upgrade_dump": %s,\n' "$(json_string "${dump_path:-}")"
        printf '  "status": %s,\n' "$(json_string "${status}")"
        printf '  "reason": %s,\n' "$(json_string "${reason}")"
        printf '  "remote_exit_code": %d,\n' "${remote_rc}"
        printf '  "remote_output": %s\n' "$(json_string "${remote_output}")"
        printf '}\n'
    } > "${OUT_JSON}"
}

if [[ "${current_version}" == "${target_app_version}" || "${current_package_version}" == "${target_version}" ]]; then
    echo "Already at ${target_version}; nothing to do."
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"current_version": %s, "current_package_version": %s, "target_version": %s, "target_app_version": %s, "status": "already_current"}\n' \
        "$(json_string "${current_version}")" "$(json_string "${current_package_version}")" \
        "$(json_string "${target_version}")" "$(json_string "${target_app_version}")" > "${OUT_JSON}"
    exit 0
fi

echo "Upgrading Mattermost: app ${current_version} -> ${target_app_version}; package ${current_package_version} -> ${target_version}"
echo "Pre-upgrade backup first..."

dump_path="/var/backups/mattermost/pre-upgrade-${TS}.sql.gz"
dump_path_q=$(shell_quote "${dump_path}")
target_version_q=$(shell_quote "${target_version}")
db_name_q=$(shell_quote "${MATTERMOST_DB_NAME}")
upgrade_env="DUMP_PATH=${dump_path_q} TARGET_VERSION=${target_version_q} MATTERMOST_DB_NAME=${db_name_q} bash -s"

upgrade_rc=0
# shellcheck disable=SC2086,SC2029
upgrade_out=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "${upgrade_env}" <<'REMOTE' 2>&1
set -euo pipefail
sudo -n mkdir -p /var/backups/mattermost
# Stream pg_dump through gzip into the destination via sudo tee so the redirect
# does not run as the unprivileged deploy user on a 700-permission directory.
sudo -n -u postgres pg_dump "$MATTERMOST_DB_NAME" \
    | gzip \
    | sudo -n tee "${DUMP_PATH}.tmp" > /dev/null
sudo -n mv "${DUMP_PATH}.tmp" "$DUMP_PATH"
sudo -n chmod 600 "$DUMP_PATH"
echo "Pre-upgrade dump: ${DUMP_PATH}"

echo "Stopping mattermost..."
sudo -n systemctl stop mattermost

echo "Installing mattermost=${TARGET_VERSION}..."
sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades "mattermost=${TARGET_VERSION}" 2>&1 | tail -n 20

echo "Starting mattermost..."
sudo -n systemctl start mattermost
REMOTE
) || upgrade_rc=$?
printf '%s\n' "${upgrade_out}"
if [[ "${upgrade_rc}" -ne 0 ]]; then
    write_upgrade_failure_json "failed_manual_intervention_required" \
        "remote upgrade command failed before health verification" \
        "unknown" "${upgrade_rc}" "${upgrade_out}"
    echo "JSON: ${OUT_JSON}"
    exit "${upgrade_rc}"
fi

# Poll ping for up to 3 minutes
echo "Waiting for Mattermost to come back up..."
ok=0
for _ in $(seq 1 36); do
    if curl -fsS --max-time 5 -o /dev/null "${MATTERMOST_URL}/api/v4/system/ping"; then
        ok=1
        break
    fi
    sleep 5
done

new_version=$(
    curl -fsS --max-time 10 "${MATTERMOST_URL}/api/v4/config/client?format=old" 2>/dev/null \
        | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4 \
        || true
)
new_version="${new_version:-unknown}"

mkdir -p "$(dirname "${OUT_JSON}")"

if [[ "${ok}" == "1" ]] && [[ "${new_version}" == "${target_app_version}" ]]; then
    echo "Upgrade SUCCESS: ${new_version}"
    {
        printf '{\n'
        printf '  "current_version_before": %s,\n' "$(json_string "${current_version}")"
        printf '  "current_package_version_before": %s,\n' "$(json_string "${current_package_version}")"
        printf '  "target_version": %s,\n' "$(json_string "${target_version}")"
        printf '  "target_app_version": %s,\n' "$(json_string "${target_app_version}")"
        printf '  "new_version": %s,\n' "$(json_string "${new_version}")"
        printf '  "pre_upgrade_dump": %s,\n' "$(json_string "${dump_path}")"
        printf '  "status": "success"\n'
        printf '}\n'
    } > "${OUT_JSON}"
    exit 0
fi

echo "Upgrade FAILED: ping_ok=${ok} new_version=${new_version}"

if [[ "${MATTERMOST_UPGRADE_ROLLBACK}" == "auto" ]]; then
    if [[ "${current_package_version}" == "unknown" ]] || ! is_package_version "${current_package_version}"; then
        echo "Auto-rollback unsafe: previous Mattermost package version is not known or not a valid package version." >&2
        {
            printf '{\n'
            printf '  "current_version_before": %s,\n' "$(json_string "${current_version}")"
            printf '  "current_package_version_before": %s,\n' "$(json_string "${current_package_version}")"
            printf '  "target_version": %s,\n' "$(json_string "${target_version}")"
            printf '  "target_app_version": %s,\n' "$(json_string "${target_app_version}")"
            printf '  "new_version": %s,\n' "$(json_string "${new_version}")"
            printf '  "pre_upgrade_dump": %s,\n' "$(json_string "${dump_path}")"
            printf '  "status": "failed_manual_intervention_required",\n'
            printf '  "reason": "previous package version unavailable for safe rollback"\n'
            printf '}\n'
        } > "${OUT_JSON}"
        exit 1
    fi
    echo "Auto-rollback enabled; restoring from ${dump_path}"
    current_package_version_q=$(shell_quote "${current_package_version}")
    db_owner_q=$(shell_quote "${MATTERMOST_DB_OWNER}")
    rollback_env="DUMP_PATH=${dump_path_q} CURRENT_PACKAGE_VERSION=${current_package_version_q} MATTERMOST_DB_NAME=${db_name_q} MATTERMOST_DB_OWNER=${db_owner_q} bash -s"
    rollback_rc=0
    # shellcheck disable=SC2086,SC2029
    rollback_out=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "${rollback_env}" <<'REMOTE' 2>&1
set -euo pipefail
sudo -n systemctl stop mattermost || true
sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades "mattermost=${CURRENT_PACKAGE_VERSION}"
# Drop the half-upgraded DB and recreate a clean one before restoring the pre-upgrade dump.
# Without DROP/CREATE, restoring a plain-text pg_dump into an already-populated database
# leaves stale tables/sequences from the failed upgrade and often fails on duplicate keys.
sudo -n -u postgres psql -d postgres -c "DROP DATABASE IF EXISTS \"${MATTERMOST_DB_NAME}\";"
sudo -n -u postgres psql -d postgres -c "CREATE DATABASE \"${MATTERMOST_DB_NAME}\" OWNER \"${MATTERMOST_DB_OWNER}\";"
# Dump is owned by root (mode 600); read it via sudo so deploy-user has access.
sudo -n cat "$DUMP_PATH" | gunzip | sudo -n -u postgres psql -d "$MATTERMOST_DB_NAME"
sudo -n systemctl start mattermost
REMOTE
) || rollback_rc=$?
    printf '%s\n' "${rollback_out}"
    if [[ "${rollback_rc}" -ne 0 ]]; then
        write_upgrade_failure_json "failed_manual_intervention_required" \
            "remote rollback command failed" \
            "${new_version}" "${rollback_rc}" "${rollback_out}"
        echo "JSON: ${OUT_JSON}"
        exit "${rollback_rc}"
    fi
    echo "Rollback complete; back on ${current_version}"
    {
        printf '{\n'
        printf '  "current_version_before": %s,\n' "$(json_string "${current_version}")"
        printf '  "current_package_version_before": %s,\n' "$(json_string "${current_package_version}")"
        printf '  "target_version": %s,\n' "$(json_string "${target_version}")"
        printf '  "target_app_version": %s,\n' "$(json_string "${target_app_version}")"
        printf '  "new_version": %s,\n' "$(json_string "${new_version}")"
        printf '  "pre_upgrade_dump": %s,\n' "$(json_string "${dump_path}")"
        printf '  "status": "failed_rolled_back"\n'
        printf '}\n'
    } > "${OUT_JSON}"
    exit 1
fi

{
    printf '{\n'
    printf '  "current_version_before": %s,\n' "$(json_string "${current_version}")"
    printf '  "current_package_version_before": %s,\n' "$(json_string "${current_package_version}")"
    printf '  "target_version": %s,\n' "$(json_string "${target_version}")"
    printf '  "target_app_version": %s,\n' "$(json_string "${target_app_version}")"
    printf '  "new_version": %s,\n' "$(json_string "${new_version}")"
    printf '  "pre_upgrade_dump": %s,\n' "$(json_string "${dump_path}")"
    printf '  "status": "failed_manual_intervention_required"\n'
    printf '}\n'
} > "${OUT_JSON}"
exit 1
