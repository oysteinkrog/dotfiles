#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="${script_dir}/scripts"
config_path="${PHASE1_CONFIG:-${script_dir}/config.env}"

if [[ -f "${config_path}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${config_path}"
  set +a
fi

workspace_name="${WORKSPACE_NAME:-slack-workspace}"
work_root="${PHASE1_WORKSPACE_ROOT:-${script_dir}/workdir}"
if [[ "${work_root}" != /* ]]; then
  work_root="${script_dir}/${work_root}"
fi
artifact_root="${ARTIFACT_ROOT:-${work_root}/artifacts}"
raw_dir="${artifact_root}/raw"
enriched_dir="${artifact_root}/enriched"
import_dir="${artifact_root}/import-ready"
reports_dir="${artifact_root}/reports"
attachments_dir="${import_dir}/data/bulk-export-attachments"
emoji_assets_dir="${import_dir}/data/emoji"
sidecar_bundle_dir="${enriched_dir}/sidecar-bundle"
emoji_dir="${enriched_dir}/emoji"

raw_manifest="${raw_dir}/manifest.raw.json"
enriched_manifest="${enriched_dir}/manifest.enriched.json"
import_manifest="${import_dir}/manifest.import-ready.json"

raw_archive_default="${raw_dir}/slack-export.zip"
enriched_archive_default="${enriched_dir}/slack-export.enriched.zip"
jsonl_path="${import_dir}/mattermost_import.jsonl"
final_zip="${import_dir}/mattermost-bulk-import.zip"

artifact_report="${reports_dir}/artifact-validation.json"
jsonl_report="${reports_dir}/jsonl-validation.json"
enrichment_report="${reports_dir}/enrichment-report.json"
reconciliation_report="${reports_dir}/reconciliation-report.json"
integration_report_json="${reports_dir}/integration-inventory.json"
integration_report_md="${reports_dir}/integration-inventory.md"
evidence_pack="${reports_dir}/evidence-pack.json"
secret_scan_report="${reports_dir}/secret-scan.json"
secret_scan_redacted_dir="${reports_dir}/redacted"
handoff_md="${reports_dir}/handoff.md"
handoff_json="${reports_dir}/handoff.json"
verification_md="${reports_dir}/verification.md"
unresolved_gaps_md="${reports_dir}/unresolved-gaps.md"
patch_report="${reports_dir}/patch-summary.json"

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

ensure_dirs() {
  mkdir -p "${raw_dir}" "${enriched_dir}" "${import_dir}" "${reports_dir}" "${attachments_dir}"
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || fail "required command not found: ${cmd}"
}

optional_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    warn "optional command not found: ${cmd}"
  fi
}

parse_csv_into_array() {
  local value="$1"
  local -n out_ref="$2"
  out_ref=()
  if [[ -z "${value}" ]]; then
    return
  fi
  local item trimmed
  IFS=',' read -r -a out_ref <<< "${value}"
  for item in "${!out_ref[@]}"; do
    trimmed="$(printf '%s' "${out_ref[$item]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    out_ref[$item]="${trimmed}"
  done
}

find_latest_zip() {
  local search_dir="$1"
  if [[ ! -d "${search_dir}" ]]; then
    return 1
  fi
  find "${search_dir}" -maxdepth 1 -type f -name '*.zip' | sort | tail -n 1
}

find_raw_archive() {
  if [[ -f "${raw_archive_default}" ]]; then
    printf '%s\n' "${raw_archive_default}"
    return 0
  fi
  find_latest_zip "${raw_dir}"
}

find_enriched_archive() {
  if [[ -f "${enriched_archive_default}" ]]; then
    printf '%s\n' "${enriched_archive_default}"
    return 0
  fi
  find_latest_zip "${enriched_dir}"
}

current_input_archive() {
  local archive_path
  archive_path="$(find_enriched_archive 2>/dev/null || true)"
  if [[ -n "${archive_path}" ]]; then
    printf '%s\n' "${archive_path}"
    return 0
  fi
  archive_path="$(find_raw_archive 2>/dev/null || true)"
  if [[ -n "${archive_path}" ]]; then
    printf '%s\n' "${archive_path}"
    return 0
  fi
  return 1
}

run_setup() {
  ensure_dirs
  require_cmd python3
  require_cmd zip
  optional_cmd unzip
  optional_cmd jq
  optional_cmd "${MMETL_BIN:-mmetl}"
  optional_cmd "${SLACKDUMP_BIN:-slackdump}"
  optional_cmd "${SLACK_ADVANCED_EXPORTER_BIN:-slack-advanced-exporter}"
  log "prepared ${artifact_root}"
}

run_export() {
  ensure_dirs
  if [[ -n "${SLACK_EXPORT_ZIP:-}" ]]; then
    local -a intake_cmd
    intake_cmd=(
      python3 "${scripts_dir}/intake-official-export.py"
      --workspace "${workspace_name}"
      --archive "${SLACK_EXPORT_ZIP}"
      --output-dir "${raw_dir}"
      --manifest-out "${raw_manifest}"
      --summary-out "${reports_dir}/official-intake.json"
    )
    if [[ -n "${SLACK_CHANNEL_AUDIT_CSV:-}" ]]; then
      intake_cmd+=(--channel-audit-csv "${SLACK_CHANNEL_AUDIT_CSV}")
    fi
    if [[ -n "${SLACK_MEMBER_CSV:-}" ]]; then
      intake_cmd+=(--member-csv "${SLACK_MEMBER_CSV}")
    fi
    "${intake_cmd[@]}"
    return
  fi

  if [[ "${SLACK_EXPORT_AUTOMATION:-0}" == "1" ]]; then
    local -a automation_cmd
    automation_cmd=(
      python3 "${scripts_dir}/automate-official-export.py"
      --workspace "${workspace_name}"
      --output-dir "${raw_dir}"
      --manifest-out "${raw_manifest}"
      --summary-out "${reports_dir}/official-intake.json"
      --provenance-out "${reports_dir}/official-export-provenance.json"
      --archive-out "${raw_archive_default}"
      --export-page-url "${SLACK_EXPORT_PAGE_URL:-}"
      --poll-interval-seconds "${SLACK_EXPORT_POLL_INTERVAL_SECONDS:-60}"
      --timeout-seconds "${SLACK_EXPORT_TIMEOUT_SECONDS:-3600}"
    )
    [[ -n "${SLACK_WORKSPACE_URL:-}" ]] && automation_cmd+=(--workspace-url "${SLACK_WORKSPACE_URL}")
    [[ -n "${SLACK_COOKIE_JAR:-}" ]] && automation_cmd+=(--cookie-jar "${SLACK_COOKIE_JAR}")
    [[ -n "${SLACK_COOKIE_HEADER:-}" ]] && automation_cmd+=(--cookie-header "${SLACK_COOKIE_HEADER}")
    [[ -n "${SLACK_EXPORT_TRIGGER_COMMAND:-}" ]] && automation_cmd+=(--trigger-command "${SLACK_EXPORT_TRIGGER_COMMAND}")
    [[ -n "${SLACK_EXPORT_TRIGGER_MODE:-}" ]] && automation_cmd+=(--trigger-mode "${SLACK_EXPORT_TRIGGER_MODE}")
    [[ -n "${SLACK_IMAP_HOST:-}" ]] && automation_cmd+=(--imap-host "${SLACK_IMAP_HOST}")
    [[ -n "${SLACK_IMAP_PORT:-}" ]] && automation_cmd+=(--imap-port "${SLACK_IMAP_PORT}")
    [[ -n "${SLACK_IMAP_USERNAME:-}" ]] && automation_cmd+=(--imap-username "${SLACK_IMAP_USERNAME}")
    [[ -n "${SLACK_IMAP_PASSWORD:-}" ]] && automation_cmd+=(--imap-password "${SLACK_IMAP_PASSWORD}")
    [[ -n "${SLACK_IMAP_MAILBOX:-}" ]] && automation_cmd+=(--imap-mailbox "${SLACK_IMAP_MAILBOX}")
    [[ -n "${SLACK_EXPORT_MAILBOX_DIR:-}" ]] && automation_cmd+=(--mailbox-dir "${SLACK_EXPORT_MAILBOX_DIR}")
    [[ -n "${SLACK_CHANNEL_AUDIT_CSV:-}" ]] && automation_cmd+=(--channel-audit-out "${SLACK_CHANNEL_AUDIT_CSV}")
    [[ -n "${SLACK_MEMBER_CSV:-}" ]] && automation_cmd+=(--member-csv-out "${SLACK_MEMBER_CSV}")
    "${automation_cmd[@]}"
    return
  fi

  "${scripts_dir}/run-slackdump-export.sh" "${raw_dir}/slackdump-export" "${raw_archive_default}"

  python3 "${scripts_dir}/build-artifact-manifest.py" \
    --workspace "${workspace_name}" \
    --stage raw \
    --source slackdump \
    --output "${raw_manifest}" \
    "${raw_archive_default}"
}

run_enrich() {
  ensure_dirs
  local input_archive
  input_archive="$(find_raw_archive 2>/dev/null || true)"
  [[ -n "${input_archive}" ]] || fail "no raw archive available; run ./migrate.sh export first"

  local working_archive="${input_archive}"
  local email_archive="${enriched_dir}/slack-export.with-emails.zip"

  if [[ -n "${SLACK_TOKEN:-}" ]] && command -v "${SLACK_ADVANCED_EXPORTER_BIN:-slack-advanced-exporter}" >/dev/null 2>&1; then
    "${scripts_dir}/run-slack-advanced-exporter.sh" fetch-emails "${working_archive}" "${email_archive}"
    "${scripts_dir}/run-slack-advanced-exporter.sh" fetch-attachments "${email_archive}" "${enriched_archive_default}"
    working_archive="${enriched_archive_default}"
  else
    warn "advanced exporter or SLACK_TOKEN missing; carrying raw archive forward as the enriched archive"
    "${scripts_dir}/run-slack-advanced-exporter.sh" copy "${working_archive}" "${enriched_archive_default}"
    working_archive="${enriched_archive_default}"
  fi

  if [[ -n "${SLACK_TOKEN:-}" ]]; then
    python3 "${scripts_dir}/export-custom-emoji.py" \
      --workspace "${workspace_name}" \
      --token "${SLACK_TOKEN}" \
      --output-dir "${emoji_dir}" \
      --manifest-out "${emoji_dir}/emoji-manifest.json" \
      --aliases-out "${emoji_dir}/emoji-aliases.json"
  else
    warn "SLACK_TOKEN missing; skipping custom emoji export"
  fi

  local -a sidecar_inputs workflow_inputs manifest_inputs
  parse_csv_into_array "${PHASE1_SIDECAR_INPUTS:-}" sidecar_inputs
  parse_csv_into_array "${PHASE1_WORKFLOW_INPUTS:-}" workflow_inputs

  local sidecar_cmd=(
    python3 "${scripts_dir}/extract-phase1-sidecars.py"
    --workspace "${workspace_name}"
    --raw-archive "${input_archive}"
    --output-dir "${sidecar_bundle_dir}"
    --metadata-out "${sidecar_bundle_dir}/sidecar-summary.json"
  )
  local item
  for item in "${sidecar_inputs[@]}"; do
    [[ -n "${item}" ]] && sidecar_cmd+=(--sidecar-input "${item}")
  done
  for item in "${workflow_inputs[@]}"; do
    [[ -n "${item}" ]] && sidecar_cmd+=(--workflow-input "${item}")
  done
  "${sidecar_cmd[@]}"

  manifest_inputs=("${working_archive}" "${sidecar_bundle_dir}/sidecar-summary.json")
  if [[ -f "${emoji_dir}/emoji-manifest.json" ]]; then
    manifest_inputs+=("${emoji_dir}/emoji-manifest.json" "${emoji_dir}/emoji-aliases.json")
  fi

  python3 "${scripts_dir}/build-artifact-manifest.py" \
    --workspace "${workspace_name}" \
    --stage enriched \
    --source enrichment \
    --output "${enriched_manifest}" \
    "${manifest_inputs[@]}"
}

run_transform() {
  ensure_dirs
  require_cmd "${MMETL_BIN:-mmetl}"
  [[ -n "${MATTERMOST_TEAM_NAME:-}" ]] || fail "MATTERMOST_TEAM_NAME must be set in config.env"

  local input_archive
  input_archive="$(current_input_archive 2>/dev/null || true)"
  [[ -n "${input_archive}" ]] || fail "no input archive available; run export/enrich first"

  mkdir -p "${attachments_dir}" "$(dirname "${jsonl_path}")"

  local -a cmd extra_flags
  cmd=("${MMETL_BIN:-mmetl}" check slack --file "${input_archive}")
  "${cmd[@]}"

  cmd=(
    "${MMETL_BIN:-mmetl}"
    transform
    slack
    --team "${MATTERMOST_TEAM_NAME}"
    --file "${input_archive}"
    --output "${jsonl_path}"
    --attachments-dir "${attachments_dir}"
  )
  if [[ -n "${MMETL_DEFAULT_EMAIL_DOMAIN:-}" ]]; then
    cmd+=(--default-email-domain "${MMETL_DEFAULT_EMAIL_DOMAIN}")
  fi
  if [[ -n "${MMETL_EXTRA_FLAGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_flags=(${MMETL_EXTRA_FLAGS})
    cmd+=("${extra_flags[@]}")
  fi
  "${cmd[@]}"
}

run_package() {
  ensure_dirs
  [[ -f "${jsonl_path}" ]] || fail "missing jsonl output; run ./migrate.sh transform first"
  mkdir -p "${emoji_assets_dir}"

  local -a patch_cmd
  patch_cmd=(
    python3 "${scripts_dir}/patch-phase1-import.py"
    --workspace "${workspace_name}"
    --jsonl "${jsonl_path}"
    --attachments-root "${attachments_dir}"
    --emoji-assets-dir "${emoji_assets_dir}"
    --summary-out "${patch_report}"
  )
  if [[ -n "${PHASE1_ARCHIVE_USER:-}" ]]; then
    patch_cmd+=(--archive-user "${PHASE1_ARCHIVE_USER}")
  fi
  if [[ -n "${MATTERMOST_TEAM_DISPLAY_NAME:-}" ]]; then
    patch_cmd+=(--team-display-name "${MATTERMOST_TEAM_DISPLAY_NAME}")
  fi
  if [[ -f "${emoji_dir}/emoji-manifest.json" ]]; then
    patch_cmd+=(--emoji-manifest "${emoji_dir}/emoji-manifest.json")
  fi
  if [[ -f "${emoji_dir}/emoji-aliases.json" ]]; then
    patch_cmd+=(--emoji-aliases "${emoji_dir}/emoji-aliases.json")
  fi
  if [[ -d "${sidecar_bundle_dir}/sidecars" ]]; then
    patch_cmd+=(--sidecar-dir "${sidecar_bundle_dir}/sidecars")
  fi
  if [[ -d "${sidecar_bundle_dir}/workflows" ]]; then
    patch_cmd+=(--workflow-dir "${sidecar_bundle_dir}/workflows")
  fi
  "${patch_cmd[@]}"

  local -a package_cmd
  package_cmd=(
    python3 "${scripts_dir}/package-phase1-import.py"
    --workspace "${workspace_name}"
    --jsonl "${jsonl_path}"
    --output-zip "${final_zip}"
    --manifest-out "${import_manifest}"
    --summary-out "${reports_dir}/package-summary.json"
  )
  if [[ -d "${attachments_dir}" ]]; then
    package_cmd+=(--attachments-dir "${attachments_dir}")
  fi
  if [[ -d "${emoji_assets_dir}" ]]; then
    package_cmd+=(--emoji-asset-dir "${emoji_assets_dir}")
  fi
  if [[ -d "${sidecar_bundle_dir}/sidecars" ]]; then
    package_cmd+=(--sidecar-dir "${sidecar_bundle_dir}/sidecars")
  fi
  if [[ -d "${sidecar_bundle_dir}/workflows" ]]; then
    package_cmd+=(--workflow-dir "${sidecar_bundle_dir}/workflows")
  fi
  if [[ -d "${emoji_dir}" ]]; then
    package_cmd+=(--emoji-dir "${emoji_dir}")
  fi
  "${package_cmd[@]}"
}

run_verify() {
  ensure_dirs
  [[ -f "${jsonl_path}" ]] || fail "missing jsonl output; run ./migrate.sh transform first"

  local raw_archive enriched_archive
  raw_archive="$(find_raw_archive 2>/dev/null || true)"
  enriched_archive="$(find_enriched_archive 2>/dev/null || true)"
  [[ -n "${raw_archive}" ]] || fail "missing raw archive; run ./migrate.sh export first"

  python3 "${scripts_dir}/validate-phase1-artifacts.py" --root "${artifact_root}" --output-json "${artifact_report}"
  python3 "${scripts_dir}/validate-phase1-jsonl.py" "${jsonl_path}" --output-json "${jsonl_report}"
  python3 "${scripts_dir}/validate-enrichment-completeness.py" \
    --archive "${enriched_archive:-${raw_archive}}" \
    --output-json "${enrichment_report}"

  local -a reconcile_cmd
  reconcile_cmd=(
    python3 "${scripts_dir}/reconcile-phase1-counts.py"
    --raw-archive "${raw_archive}"
    --jsonl "${jsonl_path}"
    --output-json "${reconciliation_report}"
  )
  if [[ -n "${enriched_archive}" ]]; then
    reconcile_cmd+=(--enriched-archive "${enriched_archive}")
  fi
  if [[ -n "${SLACK_CHANNEL_AUDIT_CSV:-}" && -f "${SLACK_CHANNEL_AUDIT_CSV}" ]]; then
    reconcile_cmd+=(--channel-audit-csv "${SLACK_CHANNEL_AUDIT_CSV}")
  fi
  "${reconcile_cmd[@]}"

  python3 "${scripts_dir}/export-integration-inventory.py" \
    --archive "${raw_archive}" \
    --output-json "${integration_report_json}" \
    --output-md "${integration_report_md}"

  local -a evidence_paths evidence_inputs
  evidence_inputs=()
  local candidate
  for candidate in "${raw_manifest}" "${enriched_manifest}" "${import_manifest}" "${jsonl_path}" "${final_zip}" "${patch_report}" "${reports_dir}"; do
    [[ -e "${candidate}" ]] && evidence_inputs+=("${candidate}")
  done
  parse_csv_into_array "${PHASE1_EVIDENCE_PATHS:-}" evidence_paths
  local path
  for path in "${evidence_paths[@]}"; do
    [[ -n "${path}" && -e "${path}" ]] && evidence_inputs+=("${path}")
  done
  python3 "${scripts_dir}/build-migration-evidence-pack.py" \
    --workspace "${workspace_name}" \
    --output "${evidence_pack}" \
    "${evidence_inputs[@]}"

  if ! python3 "${scripts_dir}/scan-and-redact-migration-secrets.py" \
    --report-json "${secret_scan_report}" \
    --output-dir "${secret_scan_redacted_dir}" \
    "${reports_dir}" "${config_path}"; then
    warn "secret scan found potential secrets; see ${secret_scan_report}"
  fi
}

run_handoff() {
  ensure_dirs
  [[ -f "${final_zip}" ]] || fail "missing final import zip; run ./migrate.sh package first"

  local -a manifest_args known_gaps sidecar_channels
  local item
  for item in "${raw_manifest}" "${enriched_manifest}" "${import_manifest}"; do
    [[ -f "${item}" ]] && manifest_args+=(--manifest "${item}")
  done

  parse_csv_into_array "${PHASE1_KNOWN_GAPS:-}" known_gaps
  parse_csv_into_array "${PHASE1_SIDECAR_CHANNELS:-}" sidecar_channels

  local -a handoff_cmd
  handoff_cmd=(
    python3 "${scripts_dir}/generate-phase1-handoff.py"
    --workspace "${workspace_name}"
    --output "${handoff_md}"
    --json-output "${handoff_json}"
    --final-zip "${final_zip}"
    --jsonl "${jsonl_path}"
    --plan-tier "${SLACK_PLAN_TIER:-}"
    --export-basis "$( [[ -n "${SLACK_EXPORT_ZIP:-}" ]] && printf 'official-export' || printf 'slackdump' )"
  )
  if [[ ${#manifest_args[@]} -gt 0 ]]; then
    handoff_cmd+=("${manifest_args[@]}")
  fi
  for item in "${known_gaps[@]}"; do
    [[ -n "${item}" ]] && handoff_cmd+=(--known-gap "${item}")
  done
  for item in "${sidecar_channels[@]}"; do
    [[ -n "${item}" ]] && handoff_cmd+=(--sidecar-channel "${item}")
  done
  "${handoff_cmd[@]}"

  python3 "${scripts_dir}/generate-phase1-verification.py" \
    --workspace "${workspace_name}" \
    --output-md "${verification_md}" \
    --artifact-report "${artifact_report}" \
    --jsonl-report "${jsonl_report}" \
    --enrichment-report "${enrichment_report}" \
    --reconciliation-report "${reconciliation_report}" \
    --integration-report "${integration_report_json}" \
    --secret-scan-report "${secret_scan_report}" \
    --handoff-json "${handoff_json}"

  python3 "${scripts_dir}/generate-unresolved-gaps.py" \
    --workspace "${workspace_name}" \
    --output-md "${unresolved_gaps_md}" \
    --handoff-json "${handoff_json}" \
    --enrichment-report "${enrichment_report}" \
    --reconciliation-report "${reconciliation_report}" \
    --artifact-report "${artifact_report}"
}

run_all() {
  run_setup
  run_export
  run_enrich
  run_transform
  run_package
  run_verify
  run_handoff
}

run_split_import() {
  ensure_dirs
  [[ -f "${final_zip}" ]] || fail "missing final import zip; run ./migrate.sh package first"
  local -a split_cmd
  split_cmd=(
    python3 "${scripts_dir}/split-phase1-import.py"
    --input-zip "${final_zip}"
    --output-dir "${import_dir}/batches"
    --report-json "${reports_dir}/split-import-report.json"
  )
  if [[ -n "${SPLIT_IMPORT_YEARS:-}" ]]; then
    split_cmd+=(--years "${SPLIT_IMPORT_YEARS}")
  fi
  "${split_cmd[@]}"
}

usage() {
  cat <<'EOF'
usage: ./migrate.sh <setup|export|enrich|transform|package|verify|handoff|all|split-import>
EOF
}

main() {
  local command="${1:-}"
  case "${command}" in
    setup) run_setup ;;
    export) run_export ;;
    enrich) run_enrich ;;
    transform) run_transform ;;
    package) run_package ;;
    verify) run_verify ;;
    handoff) run_handoff ;;
    all) run_all ;;
    split-import) run_split_import ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
