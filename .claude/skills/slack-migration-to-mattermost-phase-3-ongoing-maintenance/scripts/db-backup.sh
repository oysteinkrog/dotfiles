#!/usr/bin/env bash
# db-backup.sh — pg_dump of Mattermost DB on target, rotate, upload off-site, verify.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a
# shellcheck disable=SC1090
source "${CONFIG_PATH}"
set +a

: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${BACKUP_PATH:=/var/backups/mattermost}"
: "${BACKUP_RETENTION_DAILY_DAYS:=30}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./backup-$(date -u +%Y%m%dT%H%M%SZ).json}"
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

json_number_or_zero() {
    local value="${1:-0}"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${value}"
    else
        printf '0'
    fi
}

if [[ ! "${TS}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: PHASE3_STAGE_TIMESTAMP must be a safe filename segment" >&2
    exit 2
fi
if [[ ! "${BACKUP_RETENTION_DAILY_DAYS}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: BACKUP_RETENTION_DAILY_DAYS must be a non-negative integer" >&2
    exit 2
fi
if [[ "${BACKUP_PATH}" != /* ]]; then
    echo "ERROR: BACKUP_PATH must be an absolute remote path" >&2
    exit 2
fi

backup_file="mm_${TS}.sql.gz"
remote_path="${BACKUP_PATH}/${backup_file}"

write_failed_json() {
    local reason="$1" remote_rc="$2" remote_output="${3:-}"
    mkdir -p "$(dirname "${OUT_JSON}")"
    {
        printf '{\n'
        printf '  "generated_at": %s,\n' "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
        printf '  "target_host": %s,\n' "$(json_string "${TARGET_HOST}")"
        printf '  "backup_file": %s,\n' "$(json_string "${backup_file}")"
        printf '  "remote_path": %s,\n' "$(json_string "${remote_path}")"
        printf '  "offsite_status": "skipped",\n'
        printf '  "verify_status": "failed",\n'
        printf '  "status": "failed",\n'
        printf '  "reason": %s,\n' "$(json_string "${reason}")"
        printf '  "remote_exit_code": %d,\n' "${remote_rc}"
        printf '  "remote_output": %s\n' "$(json_string "${remote_output}")"
        printf '}\n'
    } > "${OUT_JSON}"
}

echo "Taking pg_dump on ${TARGET_HOST} -> ${remote_path}"

backup_path_q=$(shell_quote "${BACKUP_PATH}")
remote_path_q=$(shell_quote "${remote_path}")
retention_q=$(shell_quote "${BACKUP_RETENTION_DAILY_DAYS}")
remote_env="BACKUP_PATH=${backup_path_q} REMOTE_PATH=${remote_path_q} BACKUP_RETENTION_DAILY_DAYS=${retention_q} bash -s"

backup_rc=0
# shellcheck disable=SC2086,SC2029
backup_out=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "${remote_env}" <<'REMOTE' 2>&1
set -euo pipefail
sudo -n mkdir -p "$BACKUP_PATH"
sudo -n chmod 700 "$BACKUP_PATH"
# Stream pg_dump through gzip and into the destination via sudo tee so the
# redirect does not run as the unprivileged deploy user on a 700-permission dir.
sudo -n -u postgres pg_dump --no-owner --no-privileges mattermost \
    | gzip \
    | sudo -n tee "${REMOTE_PATH}.tmp" > /dev/null
sudo -n mv "${REMOTE_PATH}.tmp" "$REMOTE_PATH"
sudo -n chmod 600 "$REMOTE_PATH"
# SHA-256 for verify — write via sudo tee for the same reason as above.
sudo -n sha256sum "$REMOTE_PATH" | awk '{print $1}' | sudo -n tee "${REMOTE_PATH}.sha256" > /dev/null
sudo -n chmod 600 "${REMOTE_PATH}.sha256"
# Rotate: delete daily dumps + their sha256 sidecars older than retention.
sudo -n find "$BACKUP_PATH" -maxdepth 1 \
    \( -name 'mm_*.sql.gz' -o -name 'mm_*.sql.gz.sha256' \) \
    -mtime "+${BACKUP_RETENTION_DAILY_DAYS}" -delete || true
REMOTE
) || backup_rc=$?
printf '%s\n' "${backup_out}"
if [[ "${backup_rc}" -ne 0 ]]; then
    write_failed_json "remote backup command failed" "${backup_rc}" "${backup_out}"
    echo "JSON: ${OUT_JSON}"
    exit "${backup_rc}"
fi

# Read back SHA and size
remote_sha_path_q=$(shell_quote "${remote_path}.sha256")
sha_rc=0
# shellcheck disable=SC2086,SC2029
sha=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "sudo -n cat ${remote_sha_path_q}" 2>&1) || sha_rc=$?
if [[ "${sha_rc}" -ne 0 ]]; then
    write_failed_json "remote backup sha readback failed" "${sha_rc}" "${sha}"
    echo "JSON: ${OUT_JSON}"
    exit "${sha_rc}"
fi
sha=$(printf '%s\n' "${sha}" | awk 'NF {print $1; exit}')
if [[ ! "${sha}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    write_failed_json "remote backup sha readback was not a SHA-256 digest" 1 "${sha}"
    echo "JSON: ${OUT_JSON}"
    exit 1
fi
size_rc=0
# shellcheck disable=SC2086,SC2029
size=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "sudo -n stat -c %s ${remote_path_q}" 2>&1) || size_rc=$?
if [[ "${size_rc}" -ne 0 ]]; then
    write_failed_json "remote backup size readback failed" "${size_rc}" "${size}"
    echo "JSON: ${OUT_JSON}"
    exit "${size_rc}"
fi
size=$(printf '%s\n' "${size}" | awk 'NF {print $1; exit}')
if [[ ! "${size}" =~ ^[1-9][0-9]*$ ]]; then
    write_failed_json "remote backup size readback was not a positive byte count" 1 "${size}"
    echo "JSON: ${OUT_JSON}"
    exit 1
fi

echo "Local dump: ${remote_path} (sha256=${sha}, size=${size})"

# --- Off-site upload ----------------------------------------------------

offsite_status="skipped"
offsite_note="OFFSITE_REMOTE not set"
if [[ -n "${OFFSITE_REMOTE:-}" ]]; then
    echo "Uploading to ${OFFSITE_REMOTE}"
    offsite_remote_q=$(shell_quote "${OFFSITE_REMOTE}")
    rclone_opts_q=$(shell_quote "${OFFSITE_RCLONE_OPTS:-}")
    upload_env="REMOTE_PATH=${remote_path_q} OFFSITE_REMOTE=${offsite_remote_q} OFFSITE_RCLONE_OPTS=${rclone_opts_q} bash -s"
    # shellcheck disable=SC2086,SC2029
    if ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "${upload_env}" <<'REMOTE'
set -euo pipefail
if command -v rclone >/dev/null 2>&1; then
  case "$OFFSITE_RCLONE_OPTS" in
    *$'\n'*|*$'\r'*)
      echo "OFFSITE_RCLONE_OPTS must be a single line"
      exit 1
      ;;
  esac
  rclone_opts=()
  if [[ -n "$OFFSITE_RCLONE_OPTS" ]]; then
    read -r -a rclone_opts <<< "$OFFSITE_RCLONE_OPTS"
  fi
  sudo -n rclone copy "${rclone_opts[@]}" "$REMOTE_PATH" "${OFFSITE_REMOTE}/" 2>&1 | tail -n 5
  sudo -n rclone copy "${rclone_opts[@]}" "${REMOTE_PATH}.sha256" "${OFFSITE_REMOTE}/" 2>&1 | tail -n 5
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
    remote_offsite_sha_q=$(shell_quote "${OFFSITE_REMOTE}/${backup_file}.sha256")
    # shellcheck disable=SC2086,SC2029
    remote_sha=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
        "sudo -n rclone cat ${remote_offsite_sha_q} 2>/dev/null | awk '{print \$1}'" || echo "")
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
    printf '  "generated_at": %s,\n' "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    printf '  "target_host": %s,\n' "$(json_string "${TARGET_HOST}")"
    printf '  "backup_file": %s,\n' "$(json_string "${backup_file}")"
    printf '  "remote_path": %s,\n' "$(json_string "${remote_path}")"
    printf '  "sha256": %s,\n' "$(json_string "${sha}")"
    printf '  "size_bytes": %s,\n' "$(json_number_or_zero "${size}")"
    printf '  "offsite_status": %s,\n' "$(json_string "${offsite_status}")"
    printf '  "offsite_remote": %s,\n' "$(json_string "${OFFSITE_REMOTE:-}")"
    printf '  "offsite_note": %s,\n' "$(json_string "${offsite_note}")"
    printf '  "verify_status": %s,\n' "$(json_string "${verify_status}")"
    printf '  "status": %s\n' "$(json_string "$([[ "${verify_status}" == "mismatch" || "${offsite_status}" == "failed" ]] && echo "failed" || echo "success")")"
    printf '}\n'
} > "${OUT_JSON}"

echo "JSON: ${OUT_JSON}"
[[ "${verify_status}" == "mismatch" || "${offsite_status}" == "failed" ]] && exit 1
exit 0
