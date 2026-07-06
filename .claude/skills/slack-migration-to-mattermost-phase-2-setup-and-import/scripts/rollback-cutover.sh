#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <backup.sql.gz|backup.sql> <database-url> [report-dir=reports/rollback]" >&2
  exit 1
fi

backup_path="$1"
database_url="$2"
report_dir="${3:-reports/rollback}"
config_backup="${ROLLBACK_CONFIG_BACKUP:-}"
config_target="${ROLLBACK_CONFIG_TARGET:-/opt/mattermost/config}"
data_backup="${ROLLBACK_DATA_BACKUP:-}"
data_target="${ROLLBACK_DATA_TARGET:-/opt/mattermost/data}"
service_name="${MATTERMOST_SERVICE_NAME:-mattermost}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_json="${report_dir}/rollback.${timestamp}.json"
report_md="${report_dir}/rollback.${timestamp}.md"
service_stopped=0

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SUDO=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "error: sudo not found in PATH" >&2
    exit 1
  fi
  SUDO=(sudo)
fi

if [[ "${ROLLBACK_CONFIRMATION:-}" != "I_UNDERSTAND_THIS_RESTORES_BACKUPS" ]]; then
  echo "error: set ROLLBACK_CONFIRMATION=I_UNDERSTAND_THIS_RESTORES_BACKUPS to execute rollback" >&2
  exit 1
fi
[[ -f "${backup_path}" ]] || { echo "error: missing backup file: ${backup_path}" >&2; exit 1; }
mkdir -p "${report_dir}"

write_report() {
  local status="$1"
  local note="$2"
  cat > "${report_json}" <<EOF
{
  "status": "${status}",
  "backup_path": "${backup_path}",
  "config_backup": "${config_backup}",
  "data_backup": "${data_backup}",
  "service_name": "${service_name}",
  "note": "${note}"
}
EOF
  cat > "${report_md}" <<EOF
# Rollback Summary

- Status: ${status}
- Backup path: \`${backup_path}\`
- Config backup: \`${config_backup}\`
- Data backup: \`${data_backup}\`
- Service: \`${service_name}\`
- Note: ${note}
EOF
  echo "wrote ${report_json}"
  echo "wrote ${report_md}"
}

restart_service_best_effort() {
  if [[ "${service_stopped}" == "1" ]]; then
    "${SUDO[@]}" systemctl start "${service_name}" >/dev/null 2>&1 || true
    service_stopped=0
  fi
}

fail() {
  local note="$1"
  restart_service_best_effort
  write_report "failed" "${note}"
  echo "error: ${note}" >&2
  exit 1
}

for cmd in psql rsync systemctl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    write_report "failed" "missing required command: ${cmd}"
    exit 1
  fi
done
if [[ "${backup_path}" == *.gz ]] && ! command -v gunzip >/dev/null 2>&1; then
  write_report "failed" "missing required command: gunzip"
  exit 1
fi
if [[ -n "${config_backup}" && ! -d "${config_backup}" ]]; then
  write_report "failed" "missing config backup directory: ${config_backup}"
  exit 1
fi
if [[ -n "${data_backup}" && ! -d "${data_backup}" ]]; then
  write_report "failed" "missing data backup directory: ${data_backup}"
  exit 1
fi

if ! "${SUDO[@]}" systemctl stop "${service_name}"; then
  write_report "failed" "failed to stop service: ${service_name}"
  exit 1
fi
service_stopped=1

if [[ "${backup_path}" == *.gz ]]; then
  if ! gunzip -c "${backup_path}" | psql "${database_url}" >/dev/null; then
    fail "database restore failed from gzip backup"
  fi
else
  if ! psql "${database_url}" < "${backup_path}" >/dev/null; then
    fail "database restore failed"
  fi
fi

if [[ -n "${config_backup}" ]]; then
  if ! "${SUDO[@]}" mkdir -p "${config_target%/}"; then
    fail "failed to create config target directory: ${config_target}"
  fi
  if ! "${SUDO[@]}" rsync -a "${config_backup%/}/" "${config_target%/}/"; then
    fail "failed to restore config backup"
  fi
fi
if [[ -n "${data_backup}" ]]; then
  if ! "${SUDO[@]}" mkdir -p "${data_target%/}"; then
    fail "failed to create data target directory: ${data_target}"
  fi
  if ! "${SUDO[@]}" rsync -a "${data_backup%/}/" "${data_target%/}/"; then
    fail "failed to restore data backup"
  fi
fi

if ! "${SUDO[@]}" systemctl start "${service_name}"; then
  fail "failed to start service after rollback"
fi
service_stopped=0
write_report "success" "rollback completed successfully"
