#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <backup.sql.gz|backup.sql> <scratch-database-url> [report-dir=reports/restore-drill]" >&2
  exit 1
fi

backup_path="$1"
scratch_db_url="$2"
report_dir="${3:-reports/restore-drill}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_json="${report_dir}/restore-drill.${timestamp}.json"
report_md="${report_dir}/restore-drill.${timestamp}.md"
redacted_db_url="$(sed -E 's#(://[^:/]+:)[^@]+@#\\1[REDACTED]@#' <<<"${scratch_db_url}")"

if [[ ! -f "${backup_path}" ]]; then
  echo "error: missing backup file: ${backup_path}" >&2
  exit 1
fi

if [[ "${scratch_db_url}" != *scratch* && "${scratch_db_url}" != *staging* && "${ALLOW_NON_SCRATCH:-0}" != "1" ]]; then
  echo "error: scratch database url does not look like a scratch/staging target; set ALLOW_NON_SCRATCH=1 to override" >&2
  exit 1
fi

mkdir -p "${report_dir}"

write_report() {
  local status="$1"
  local note="$2"
  printf '{\n  "status": "%s"\n}\n' "${status}" > "${report_json}"
  cat > "${report_md}" <<EOF
# Restore Drill Summary

- Status: ${status}
- Backup: \`${backup_path}\`
- Scratch DB URL: \`${redacted_db_url}\`
- Note: ${note}
EOF

  echo "wrote ${report_json}"
  echo "wrote ${report_md}"
}

fail() {
  local note="$1"
  write_report "failed" "${note}"
  echo "error: ${note}" >&2
  exit 1
}

if ! command -v psql >/dev/null 2>&1; then
  fail "psql not found in PATH"
fi

if [[ "${backup_path}" == *.gz ]] && ! command -v gunzip >/dev/null 2>&1; then
  fail "gunzip not found in PATH"
fi

if [[ "${backup_path}" == *.gz ]]; then
  if ! gunzip -c "${backup_path}" | psql "${scratch_db_url}" >/dev/null; then
    fail "restore command failed"
  fi
else
  if ! psql "${scratch_db_url}" < "${backup_path}" >/dev/null; then
    fail "restore command failed"
  fi
fi

write_report "success" "restore drill completed successfully"
