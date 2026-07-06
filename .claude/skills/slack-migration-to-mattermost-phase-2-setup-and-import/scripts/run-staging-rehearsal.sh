#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: $0 <mattermost-url> <import-zip> <admin-user> <admin-pass> [report-dir=reports/staging-rehearsal]" >&2
  exit 1
fi

mm_url="$1"
import_zip="$2"
admin_user="$3"
admin_pass="$4"
report_dir="${5:-reports/staging-rehearsal}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
monitor_script="${script_dir}/monitor-import.sh"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_json="${report_dir}/staging-summary.${timestamp}.json"
report_md="${report_dir}/staging-summary.${timestamp}.md"
watch_log="${report_dir}/import-watch.${timestamp}.jsonl"
error_snapshot="${report_dir}/import-error.${timestamp}.json"
smoke_json="${report_dir}/smoke-tests.${timestamp}.json"
smoke_md="${report_dir}/smoke-tests.${timestamp}.md"
reconcile_json="${report_dir}/reconciliation.${timestamp}.json"
smoke_status="not-run"
import_filename=""
job_id=""

if [[ ! -f "${import_zip}" ]]; then
  echo "error: missing import zip: ${import_zip}" >&2
  exit 1
fi

if [[ "${mm_url}" != http://localhost:* && "${mm_url}" != http://127.0.0.1:* && "${mm_url}" != *staging* && "${ALLOW_NON_STAGING:-0}" != "1" ]]; then
  echo "error: ${mm_url} does not look like a staging URL; set ALLOW_NON_STAGING=1 to override" >&2
  exit 1
fi

for cmd in mmctl jq; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: ${cmd} not found in PATH" >&2
    exit 1
  fi
done

mkdir -p "${report_dir}"

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
      --arg smoke_json "${smoke_json}" \
      --arg reconcile_json "${reconcile_json}" \
      --arg smoke_status "${smoke_status}" \
      --arg note "${note}" \
    '{
      status: $status,
      mattermost_url: $mattermost_url,
      import_zip: $import_zip, job_id: $job_id,
      import_filename: $import_filename,
      watch_log: $watch_log,
      error_snapshot: $error_snapshot,
      smoke_report: $smoke_json,
      reconciliation_report: $reconcile_json,
      post_import_smoke_status: $smoke_status,
      note: $note
    }' > "${report_json}"

  cat > "${report_md}" <<EOF
# Staging Rehearsal Summary

- Status: ${status}
- Mattermost URL: \`${mm_url}\`
- Import ZIP: \`${import_zip}\`
- Import job id: \`${job_id:-unknown}\`
- Import filename: \`${import_filename:-unknown}\`
- Watch log: \`${watch_log}\`
- Error snapshot path: \`${error_snapshot}\`
- Smoke report: \`${smoke_json}\`
- Reconciliation report: \`${reconcile_json}\`
- Post-import smoke: \`${smoke_status}\`
- Note: ${note}
EOF

  echo "wrote ${report_json}"
  echo "wrote ${report_md}"
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

fail() {
  local note="$1"
  write_report "failed" "${note}"
  echo "error: ${note}" >&2
  exit 1
}

if ! mmctl auth login "${mm_url}" --name staging-rehearsal --username "${admin_user}" --password "${admin_pass}" >/dev/null; then
  fail "mmctl auth login failed"
fi
if ! import_filename="$(mmctl import upload "${import_zip}" | tail -n 1)"; then
  fail "mmctl import upload failed"
fi

available_payload="$(mmctl import list available --json 2>/dev/null || true)"
if ! jq -e . >/dev/null <<<"${available_payload}"; then
  fail "unable to parse mmctl import list available output"
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
  fail "could not determine import filename from mmctl import list available"
fi

process_output=""
if ! process_output="$(mmctl import process "${import_filename}" 2>&1)"; then
  fail "mmctl import process failed for ${import_filename}"
fi
job_id="$(extract_job_id "${process_output}")"
if [[ -z "${job_id}" ]]; then
  fail "could not determine import job id for ${import_filename}"
fi

if ! WATCH_LOG="${watch_log}" ERROR_SNAPSHOT="${error_snapshot}" "${monitor_script}" "${job_id}"; then
  fail "import monitoring reported failure"
fi

if [[ "${REQUIRE_POST_IMPORT_SMOKE:-1}" == "1" ]]; then
  if [[ -z "${HANDOFF_JSON:-}" || -z "${DATABASE_URL:-}" ]]; then
    fail "HANDOFF_JSON and DATABASE_URL must be set for post-import smoke tests"
  fi
  if ! python3 "${script_dir}/run-import-smoke-tests.py" \
    --handoff-json "${HANDOFF_JSON}" \
    --database-url "${DATABASE_URL}" \
    --mattermost-url "${mm_url}" \
    --output-json "${smoke_json}" \
    --output-md "${smoke_md}" \
    ${DATABASE_SSH_TARGET:+--ssh-target "${DATABASE_SSH_TARGET}"}; then
    smoke_status="failed"
    fail "post-import smoke tests failed"
  fi
  smoke_status="passed"
  if ! python3 "${script_dir}/reconcile-handoff-vs-import.py" \
    --handoff-json "${HANDOFF_JSON}" \
    --observed-json "${smoke_json}" \
    --output-json "${reconcile_json}"; then
    fail "handoff reconciliation failed after staging import"
  fi
else
  smoke_status="skipped"
fi

write_report "success" "staging rehearsal completed successfully"
