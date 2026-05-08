#!/usr/bin/env bash
set -euo pipefail

if ! command -v mmctl >/dev/null 2>&1; then
  echo "error: mmctl not found in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq not found in PATH" >&2
  exit 1
fi

job_id="${1:-}"
poll_seconds="${POLL_SECONDS:-5}"
stall_polls="${STALL_POLLS:-0}"
max_wait_seconds="${MAX_WAIT_SECONDS:-7200}"
watch_log="${WATCH_LOG:-}"
error_snapshot="${ERROR_SNAPSHOT:-}"
last_signature=""
stalled=0
start_epoch="$(date +%s)"

write_error_snapshot() {
  if [[ -z "${error_snapshot}" ]]; then
    return
  fi
  mkdir -p "$(dirname "${error_snapshot}")"
  printf '%s\n' "${1:-}" > "${error_snapshot}"
}

require_nonnegative_integer() {
  local value="$1"
  local label="$2"

  [[ "${value}" =~ ^[0-9]+$ ]] || {
    echo "error: ${label} must be a non-negative integer" >&2
    exit 1
  }
}

require_nonnegative_integer "${poll_seconds}" "POLL_SECONDS"
require_nonnegative_integer "${stall_polls}" "STALL_POLLS"
require_nonnegative_integer "${max_wait_seconds}" "MAX_WAIT_SECONDS"

if [[ -z "${job_id}" ]]; then
  if ! jobs_payload="$(mmctl import job list --json 2>/dev/null)"; then
    write_error_snapshot ""
    echo "error: failed to list import jobs" >&2
    exit 1
  fi

  if ! jq -e . >/dev/null <<<"${jobs_payload}"; then
    write_error_snapshot "${jobs_payload}"
    echo "error: mmctl returned non-JSON output for import job list" >&2
    echo "${jobs_payload}" >&2
    exit 1
  fi

  job_id="$(jq -r 'if type == "array" and length > 0 then max_by(.update_at // .create_at // 0).id // empty else empty end' <<<"${jobs_payload}")"
fi

if [[ -z "${job_id}" ]]; then
  echo "error: could not determine import job id" >&2
  exit 1
fi

echo "monitoring import job ${job_id}"

while true; do
  if ! payload="$(mmctl import job show "${job_id}" --json 2>/dev/null)"; then
    write_error_snapshot ""
    echo "error: failed to fetch import job ${job_id}" >&2
    exit 1
  fi

  if ! jq -e . >/dev/null <<<"${payload}"; then
    write_error_snapshot "${payload}"
    echo "error: mmctl returned non-JSON output for import job ${job_id}" >&2
    echo "${payload}" >&2
    exit 1
  fi
  job_payload_valid="$(jq -r --arg requested_job_id "${job_id}" '
    if type == "array" then
      length > 0
      and ((.[0].id // "") | tostring == $requested_job_id)
      and ((.[0].status // "") | tostring | length > 0)
    elif type == "object" then
      ((.id // "") | tostring == $requested_job_id)
      and ((.status // "") | tostring | length > 0)
    else
      false
    end
  ' <<<"${payload}")"
  if [[ "${job_payload_valid}" != "true" ]]; then
    write_error_snapshot "${payload}"
    echo "error: import job ${job_id} payload was missing required id/status fields or did not match the requested job id" >&2
    exit 1
  fi

  compact_payload="$(jq -c . <<<"${payload}")"
  status="$(jq -r 'if type == "array" then (.[0].status // "unknown") else (.status // "unknown") end' <<<"${payload}")"
  signature="$(jq -r 'if type == "array" then [.[0].status // "unknown", (.[0].progress // "null"), (.[0].update_at // "null")] else [.status // "unknown", (.progress // "null"), (.update_at // "null")] end | join(":")' <<<"${payload}")"
  if [[ -n "${watch_log}" ]]; then
    mkdir -p "$(dirname "${watch_log}")"
    printf '%s\n' "${compact_payload}" >> "${watch_log}"
  fi
  echo "${payload}" | jq 'if type == "array" then ((.[0] // {}) | {id, status, create_at, update_at, progress, file_name}) else {id, status, create_at, update_at, progress, file_name} end'

  if [[ "${signature}" == "${last_signature}" ]]; then
    stalled=$((stalled + 1))
  else
    stalled=0
  fi
  last_signature="${signature}"

  case "${status}" in
    success)
      exit 0
      ;;
    error|failed|cancelled|canceled|timed_out|timeout)
      write_error_snapshot "${payload}"
      exit 1
      ;;
  esac

  elapsed_seconds=$(( $(date +%s) - start_epoch ))
  if [[ "${max_wait_seconds}" -gt 0 && "${elapsed_seconds}" -ge "${max_wait_seconds}" ]]; then
    echo "error: import job ${job_id} did not reach success within ${max_wait_seconds} seconds" >&2
    write_error_snapshot "${payload}"
    exit 1
  fi

  if [[ "${stall_polls}" -gt 0 && "${stalled}" -ge "${stall_polls}" ]]; then
    echo "error: import job ${job_id} appears stalled after ${stall_polls} identical polls" >&2
    write_error_snapshot "${payload}"
    exit 1
  fi

  sleep "${poll_seconds}"
done
