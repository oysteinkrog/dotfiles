#!/usr/bin/env bash
# db-backup.sh — pg_dump of Mattermost DB on target, rotate, upload off-site, verify.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a; source "${CONFIG_PATH}"; set +a

: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${BACKUP_PATH:=/var/backups/mattermost}"
: "${BACKUP_RETENTION_DAILY_DAYS:=30}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./backup-$(date -u +%Y%m%dT%H%M%SZ).json}"
TS="${PHASE3_STAGE_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

backup_file="mm_${TS}.sql.gz"
remote_path="${BACKUP_PATH}/${backup_file}"

echo "Taking pg_dump on ${TARGET_HOST} -> ${remote_path}"

# shellcheck disable=SC2086
ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" bash <<REMOTE
set -euo pipefail
sudo -n mkdir -p "${BACKUP_PATH}"
sudo -n chmod 700 "${BACKUP_PATH}"
# Stream pg_dump through gzip and into the destination via sudo tee so the
# redirect does not run as the unprivileged deploy user on a 700-permission dir.
sudo -n -u postgres pg_dump --no-owner --no-privileges mattermost \
    | gzip \
    | sudo -n tee "${remote_path}.tmp" > /dev/null
sudo -n mv "${remote_path}.tmp" "${remote_path}"
sudo -n chmod 600 "${remote_path}"
# SHA-256 for verify — write via sudo tee for the same reason as above.
sudo -n sha256sum "${remote_path}" | awk '{print \$1}' | sudo -n tee "${remote_path}.sha256" > /dev/null
sudo -n chmod 600 "${remote_path}.sha256"
# Rotate: delete daily dumps + their sha256 sidecars older than retention.
sudo -n find "${BACKUP_PATH}" -maxdepth 1 \
    \( -name 'mm_*.sql.gz' -o -name 'mm_*.sql.gz.sha256' \) \
    -mtime +${BACKUP_RETENTION_DAILY_DAYS} -delete || true
REMOTE

# Read back SHA and size
# shellcheck disable=SC2086
sha=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "sudo -n cat '${remote_path}.sha256'" || echo "unknown")
# shellcheck disable=SC2086
size=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "sudo -n stat -c %s '${remote_path}'" || echo "0")

echo "Local dump: ${remote_path} (sha256=${sha}, size=${size})"

# --- Off-site upload ----------------------------------------------------

offsite_status="skipped"
offsite_note="OFFSITE_REMOTE not set"
if [[ -n "${OFFSITE_REMOTE:-}" ]]; then
    echo "Uploading to ${OFFSITE_REMOTE}"
    # shellcheck disable=SC2086
    if ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" bash <<REMOTE
set -euo pipefail
if command -v rclone >/dev/null 2>&1; then
  sudo -n rclone copy ${OFFSITE_RCLONE_OPTS:-} "${remote_path}" "${OFFSITE_REMOTE}/" 2>&1 | tail -n 5
  sudo -n rclone copy ${OFFSITE_RCLONE_OPTS:-} "${remote_path}.sha256" "${OFFSITE_REMOTE}/" 2>&1 | tail -n 5
else
  echo "rclone not installed on target; install via apt or skip off-site"
  exit 1
fi
REMOTE
    then
        offsite_status="success"
        offsite_note="uploaded to ${OFFSITE_REMOTE}/${backup_file}"
    else
        offsite_status="failed"
        offsite_note="rclone upload failed; local copy retained"
    fi
fi

# --- Verify (re-download hash only, compare) -----------------------------

verify_status="skipped"
if [[ "${offsite_status}" == "success" ]]; then
    # shellcheck disable=SC2086
    remote_sha=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n rclone cat '${OFFSITE_REMOTE}/${backup_file}.sha256' 2>/dev/null | awk '{print \$1}'" || echo "")
    if [[ -n "${remote_sha}" && "${remote_sha}" == "${sha}" ]]; then
        verify_status="ok"
    else
        verify_status="mismatch"
        offsite_note="upload hash mismatch: remote=${remote_sha}, local=${sha}"
    fi
fi

mkdir -p "$(dirname "${OUT_JSON}")"
{
    printf '{\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "target_host": "%s",\n' "${TARGET_HOST}"
    printf '  "backup_file": "%s",\n' "${backup_file}"
    printf '  "remote_path": "%s",\n' "${remote_path}"
    printf '  "sha256": "%s",\n' "${sha}"
    printf '  "size_bytes": %s,\n' "${size:-0}"
    printf '  "offsite_status": "%s",\n' "${offsite_status}"
    printf '  "offsite_remote": "%s",\n' "${OFFSITE_REMOTE:-}"
    printf '  "offsite_note": "%s",\n' "${offsite_note//\"/\\\"}"
    printf '  "verify_status": "%s",\n' "${verify_status}"
    printf '  "status": "%s"\n' "$([[ "${verify_status}" == "mismatch" || "${offsite_status}" == "failed" ]] && echo "failed" || echo "success")"
    printf '}\n'
} > "${OUT_JSON}"

echo "JSON: ${OUT_JSON}"
[[ "${verify_status}" == "mismatch" || "${offsite_status}" == "failed" ]] && exit 1
exit 0
