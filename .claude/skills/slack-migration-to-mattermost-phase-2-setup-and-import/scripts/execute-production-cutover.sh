#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 6 ]]; then
  echo "usage: $0 <mattermost-url> <import-zip> <admin-user> <admin-pass> <handoff-json> <report-dir> [preflight-report]" >&2
  exit 1
fi

mm_url="$1"
import_zip="$2"
admin_user="$3"
admin_pass="$4"
handoff_json="$5"
report_dir="$6"
preflight_report="${7:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
monitor_script="${script_dir}/monitor-import.sh"
smoke_script="${script_dir}/run-import-smoke-tests.py"
reconcile_script="${script_dir}/reconcile-handoff-vs-import.py"
activation_script="${script_dir}/verify-user-activation.sh"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
watch_log="${report_dir}/production-import-watch.${timestamp}.jsonl"
error_snapshot="${report_dir}/production-import-error.${timestamp}.json"
smoke_json="${report_dir}/production-smoke.${timestamp}.json"
smoke_md="${report_dir}/production-smoke.${timestamp}.md"
reconcile_json="${report_dir}/production-reconciliation.${timestamp}.json"
activation_json="${report_dir}/activation-proof.${timestamp}.json"
activation_md="${report_dir}/activation-proof.${timestamp}.md"
cutover_json="${report_dir}/cutover-status.${timestamp}.json"
cutover_md="${report_dir}/cutover-status.${timestamp}.md"
import_filename=""
job_id=""

for cmd in mmctl jq python3; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: ${cmd} not found in PATH" >&2
    exit 1
  fi
done

[[ -f "${import_zip}" ]] || { echo "error: missing import zip: ${import_zip}" >&2; exit 1; }
[[ -f "${handoff_json}" ]] || { echo "error: missing handoff json: ${handoff_json}" >&2; exit 1; }
mkdir -p "${report_dir}"

if [[ -n "${preflight_report}" ]]; then
  [[ -f "${preflight_report}" ]] || { echo "error: missing preflight report: ${preflight_report}" >&2; exit 1; }
  if [[ "$(jq -r '.status // empty' "${preflight_report}")" != "ready" ]]; then
    echo "error: preflight report is not ready: ${preflight_report}" >&2
    exit 1
  fi
fi

write_report() {
  local status="$1"
  local note="$2"
  jq -n \
    --arg status "${status}" \
    --arg mattermost_url "${mm_url}" \
    --arg import_zip "${import_zip}" --arg job_id "${job_id}" \
    --arg import_filename "${import_filename}" \
    --arg watch_log "${watch_log}" \
    --arg error_snapshot "${error_snapshot}" \
    --arg smoke_report "${smoke_json}" \
    --arg reconciliation_report "${reconcile_json}" \
    --arg activation_report "${activation_json}" \
    --arg note "${note}" \
    '{
      status: $status,
      mattermost_url: $mattermost_url,
      import_zip: $import_zip, job_id: $job_id,
      import_filename: $import_filename,
      watch_log: $watch_log,
      error_snapshot: $error_snapshot,
      smoke_report: $smoke_report,
      reconciliation_report: $reconciliation_report,
      activation_report: $activation_report,
      note: $note
    }' > "${cutover_json}"

  cat > "${cutover_md}" <<EOF
# Production Cutover Status

- Status: ${status}
- Mattermost URL: \`${mm_url}\`
- Import ZIP: \`${import_zip}\`
- Import job id: \`${job_id:-unknown}\`
- Import filename: \`${import_filename}\`
- Watch log: \`${watch_log}\`
- Error snapshot: \`${error_snapshot}\`
- Smoke report: \`${smoke_json}\`
- Reconciliation report: \`${reconcile_json}\`
- Activation report: \`${activation_json}\`
- Note: ${note}
EOF

  echo "wrote ${cutover_json}"
  echo "wrote ${cutover_md}"
}

extract_job_id() {
  local process_output="$1"
  local parsed_job_id=""

  if jq -e . >/dev/null 2>&1 <<<"${process_output}"; then
    parsed_job_id="$(jq -r '
      if type == "object" then (.id // .Id // empty)
      elif type == "array" and length > 0 then (.[0].id // .[0].Id // empty)
      else empty
      end
    ' <<<"${process_output}")"
  fi

  if [[ -z "${parsed_job_id}" ]]; then
    parsed_job_id="$(sed -nE 's/.*ID:[[:space:]]*([[:alnum:]]+).*/\1/p' <<<"${process_output}" | tail -n 1)"
  fi

  printf '%s' "${parsed_job_id}"
}

if ! mmctl auth login "${mm_url}" --name production-cutover --username "${admin_user}" --password "${admin_pass}" >/dev/null; then
  write_report "failed" "mmctl auth login failed"
  exit 1
fi
if ! import_filename="$(mmctl import upload "${import_zip}" | tail -n 1)"; then
  write_report "failed" "mmctl import upload failed"
  exit 1
fi

available_payload="$(mmctl import list available --json 2>/dev/null || true)"
if ! jq -e . >/dev/null <<<"${available_payload}"; then
  write_report "failed" "unable to parse mmctl import list available output"
  exit 1
fi

import_basename="$(basename "${import_zip}")"
import_filename="$(jq -r --arg uploaded "${import_filename}" --arg desired "${import_basename}" '
  if type == "array" and length > 0 then
    (
      map(if type == "object" then (.filename // empty) else . end) as $names
      | (
          ($names | map(select(. == $uploaded)) | .[0]) //
          ($names | map(select(. == $desired)) | .[0]) //
          ($names | map(select(($desired | length) > 0 and endswith("_" + $desired))) | .[0])
        )
    ) // (
      if ($uploaded | length) > 0 then $uploaded
      elif (.[0] | type) == "object" then (.[0].filename // empty)
      else .[0]
      end
    )
  else
    if ($uploaded | length) > 0 then $uploaded else empty end
  end
' <<<"${available_payload}")"
if [[ -z "${import_filename}" ]]; then
  write_report "failed" "could not determine import filename from mmctl import list available"
  exit 1
fi

process_output=""
if ! process_output="$(mmctl import process "${import_filename}" 2>&1)"; then
  write_report "failed" "mmctl import process failed"
  exit 1
fi
job_id="$(extract_job_id "${process_output}")"
if [[ -z "${job_id}" ]]; then
  write_report "failed" "could not determine import job id for ${import_filename}"
  exit 1
fi

if ! WATCH_LOG="${watch_log}" ERROR_SNAPSHOT="${error_snapshot}" "${monitor_script}" "${job_id}"; then
  write_report "failed" "import monitoring reported failure"
  exit 1
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  write_report "failed" "DATABASE_URL must be set for production smoke checks"
  exit 1
fi

if ! python3 "${smoke_script}" \
  --handoff-json "${handoff_json}" \
  --database-url "${DATABASE_URL}" \
  --mattermost-url "${mm_url}" \
  --output-json "${smoke_json}" \
  --output-md "${smoke_md}" \
  ${DATABASE_SSH_TARGET:+--ssh-target "${DATABASE_SSH_TARGET}"}; then
  write_report "failed" "post-import smoke tests failed"
  exit 1
fi

if ! python3 "${reconcile_script}" \
  --handoff-json "${handoff_json}" \
  --observed-json "${smoke_json}" \
  --output-json "${reconcile_json}"; then
  write_report "failed" "handoff reconciliation failed"
  exit 1
fi

if [[ -n "${SMTP_TEST_EMAIL:-}" ]]; then
  if ! "${activation_script}" "${mm_url}" "${SMTP_TEST_EMAIL}" "${activation_json}" "${activation_md}"; then
    write_report "failed" "activation verification failed"
    exit 1
  fi
fi

write_report "success" "production cutover completed successfully"
