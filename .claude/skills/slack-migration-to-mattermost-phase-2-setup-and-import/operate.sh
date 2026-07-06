#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="${script_dir}/scripts"
config_path="${PHASE2_CONFIG:-${script_dir}/config.env}"

if [[ -f "${config_path}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${config_path}"
  set +a
fi

workspace_name="${WORKSPACE_NAME:-slack-workspace}"
work_root="${PHASE2_WORKSPACE_ROOT:-${script_dir}/workdir}"
if [[ "${work_root}" != /* ]]; then
  work_root="${script_dir}/${work_root}"
fi
intake_dir="${work_root}/intake"
rendered_dir="${work_root}/rendered"
reports_dir="${work_root}/reports"

handoff_json="${HANDOFF_JSON:-}"
import_zip="${IMPORT_ZIP:-}"
rendered_config="${rendered_dir}/config.json"
rendered_nginx="${rendered_dir}/mattermost.nginx.conf"
intake_manifest="${intake_dir}/phase2-intake-manifest.json"
intake_report="${reports_dir}/phase2-intake-report.json"
config_report="${reports_dir}/config-validation.json"
live_report_json="${reports_dir}/live-stack.json"
live_report_md="${reports_dir}/live-stack.md"
provision_report="${reports_dir}/provision-host.json"
deploy_report="${reports_dir}/deploy-stack.json"
edge_provision_report="${reports_dir}/cloudflare-provision.json"
edge_report="${reports_dir}/cloudflare-edge.json"
staging_report_dir="${reports_dir}/staging"
restore_report_dir="${reports_dir}/restore"
latest_restore_report="${reports_dir}/latest-restore.json"
latest_staging_report="${reports_dir}/latest-staging.json"
latest_smoke_report="${reports_dir}/latest-smoke.json"
latest_reconcile_report="${reports_dir}/latest-reconciliation.json"
latest_activation_report="${reports_dir}/latest-activation.json"
cutover_readiness_report="${reports_dir}/cutover-readiness.json"
readiness_score_json="${reports_dir}/readiness-score.json"
readiness_score_md="${reports_dir}/readiness-score.md"
phase2_readiness_md="${reports_dir}/phase2-readiness.md"
cutover_report_dir="${reports_dir}/cutover"
evidence_pack="${EVIDENCE_PACK:-}"
rendered_origin_cert="${rendered_dir}/origin.pem"
rendered_origin_key="${rendered_dir}/origin-key.pem"

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
  mkdir -p "${intake_dir}" "${rendered_dir}" "${reports_dir}" "${staging_report_dir}" "${restore_report_dir}" "${cutover_report_dir}"
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || fail "required command not found: ${cmd}"
}

parse_csv_into_array() {
  local value="$1"
  local -n out_ref="$2"
  out_ref=()
  if [[ -z "${value}" ]]; then
    return
  fi
  IFS=',' read -r -a out_ref <<< "${value}"
}

url_hostname() {
  python3 - "$1" <<'PY'
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
print(parsed.hostname or "")
PY
}

resolve_handoff_json() {
  [[ -n "${handoff_json}" ]] || fail "HANDOFF_JSON must be set in config.env or env"
  [[ -f "${handoff_json}" ]] || fail "missing handoff json: ${handoff_json}"
}

resolve_import_zip() {
  if [[ -n "${import_zip}" && -f "${import_zip}" ]]; then
    printf '%s\n' "${import_zip}"
    return 0
  fi
  if [[ -n "${handoff_json}" && -f "${handoff_json}" ]]; then
    local resolved
    if ! resolved="$(python3 - "${handoff_json}" <<'PY'
import json
from pathlib import Path

handoff_path = Path(__import__("sys").argv[1]).resolve()
handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
raw_path = handoff.get("final_package", {}).get("path", "")
path = Path(raw_path)
if path.is_absolute():
    print(path)
else:
    print((handoff_path.parent / path).resolve())
PY
    )"; then
      fail "unable to resolve import zip from handoff json: ${handoff_json}"
    fi
    printf '%s\n' "${resolved}"
    return 0
  fi
  return 1
}

latest_matching_file() {
  local pattern="$1"
  local search_dir="$2"
  find "${search_dir}" -type f -name "${pattern}" | sort | tail -n 1
}

database_ssh_target() {
  local database_url="${1:-}"
  local needs_ssh
  [[ -n "${TARGET_HOST:-}" ]] || return 0
  if ! command -v psql >/dev/null 2>&1; then
    printf '%s@%s\n' "${TARGET_SSH_USER:-deploy}" "${TARGET_HOST}"
    return 0
  fi
  [[ -n "${database_url}" ]] || return 0
  if ! needs_ssh="$(python3 - "${database_url}" <<'PY'
from urllib.parse import urlparse
import sys

host = (urlparse(sys.argv[1]).hostname or "").strip().lower()
print("1" if host in ("", "localhost", "127.0.0.1", "::1") else "0")
PY
  )"; then
    needs_ssh="1"
  fi
  if [[ "${needs_ssh}" == "1" ]]; then
    printf '%s@%s\n' "${TARGET_SSH_USER:-deploy}" "${TARGET_HOST}"
  fi
}

ensure_mmctl_path() {
  ensure_dirs

  local wrapper_dir="${work_root}/bin"
  local wrapper_path="${wrapper_dir}/mmctl"
  local state_dir="${work_root}/state"
  local state_file="${state_dir}/mmctl-wrapper-state.json"
  mkdir -p "${wrapper_dir}" "${state_dir}"

  if [[ -n "${MMCTL_BIN:-}" ]]; then
    [[ -x "${MMCTL_BIN}" ]] || fail "MMCTL_BIN is not executable: ${MMCTL_BIN}"
    cat > "${wrapper_path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec $(printf '%q' "${MMCTL_BIN}") "\$@"
EOF
    chmod +x "${wrapper_path}"
    export PATH="${wrapper_dir}:${PATH}"
    return
  fi

  if [[ -n "${TARGET_HOST:-}" && "${DEPLOY_MODE:-plan}" == "ssh" && "${ENABLE_LOCAL_MODE:-0}" == "1" ]]; then
    local ssh_target="${TARGET_SSH_USER:-deploy}@${TARGET_HOST}"
    local service_name="${MATTERMOST_SERVICE_NAME:-mattermost}"
    local remote_mmctl_bin="${REMOTE_MMCTL_BIN:-/opt/mattermost/bin/mmctl}"
    local deploy_method="${DEPLOY_METHOD:-apt}"
    local remote_import_dir="${MMCTL_REMOTE_IMPORT_DIR:-}"
    local remote_stage_dir="/tmp/mattermost-import-staging"
    local container_import_dir="${MMCTL_CONTAINER_IMPORT_DIR:-/mattermost/data/imports}"
    if [[ -z "${remote_import_dir}" ]]; then
      if [[ "${deploy_method}" == "docker" ]]; then
        remote_import_dir="${MATTERMOST_DATA_PATH:-/opt/mattermost/data}/imports"
      else
        remote_import_dir="/tmp/mattermost-imports"
      fi
    fi

    cat > "${wrapper_path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

ssh_target='${ssh_target}'
remote_import_dir='${remote_import_dir}'
remote_stage_dir='${remote_stage_dir}'
container_import_dir='${container_import_dir}'
state_file='${state_file}'
service_name='${service_name}'
deploy_method='${deploy_method}'
remote_mmctl_bin='${remote_mmctl_bin}'

run_remote_command() {
  local -a remote_cmd=("\$@")
  local payload
  printf -v payload '%q ' "\${remote_cmd[@]}"
  ssh "\${ssh_target}" "bash -lc \$(printf '%q' "\${payload}")"
}

install_remote_import() {
  local staged_path="\$1"
  local final_path="\$2"
  ssh "\${ssh_target}" "bash -se" -- "\${staged_path}" "\${final_path}" <<'EOS'
set -euo pipefail

staged_path="\$1"
final_path="\$2"
final_dir="\$(dirname "\${final_path}")"

if [[ "\${EUID:-\$(id -u)}" -eq 0 ]]; then
  mkdir -p "\${final_dir}"
  cp "\${staged_path}" "\${final_path}"
  chmod 0644 "\${final_path}"
  rm -f "\${staged_path}"
elif command -v sudo >/dev/null 2>&1; then
  sudo mkdir -p "\${final_dir}"
  sudo cp "\${staged_path}" "\${final_path}"
  sudo chmod 0644 "\${final_path}"
  rm -f "\${staged_path}"
else
  mkdir -p "\${final_dir}"
  cp "\${staged_path}" "\${final_path}"
  chmod 0644 "\${final_path}"
  rm -f "\${staged_path}"
fi
EOS
}

run_remote_mmctl() {
  local -a base_cmd
  if [[ "\${deploy_method}" == "docker" ]]; then
    base_cmd=(docker exec -i "\${service_name}" /mattermost/bin/mmctl --local)
  else
    base_cmd=("\${remote_mmctl_bin}" --local)
  fi
  run_remote_command "\${base_cmd[@]}" "\$@"
}

save_state() {
  python3 - "\${state_file}" "\$1" "\$2" "\$3" <<'PY'
import json
from pathlib import Path
import sys

state_path = Path(sys.argv[1])
state_path.parent.mkdir(parents=True, exist_ok=True)
payload = {
    "archive_name": sys.argv[2],
    "upload_path": sys.argv[3],
    "process_path": sys.argv[4],
}
state_path.write_text(json.dumps(payload, indent=2) + "\\n", encoding="utf-8")
PY
}

print_available_json() {
  python3 - "\${state_file}" <<'PY'
import json
from pathlib import Path
import sys

state_path = Path(sys.argv[1])
if not state_path.exists():
    print("[]")
    raise SystemExit(0)
state = json.loads(state_path.read_text(encoding="utf-8"))
archive_name = state.get("archive_name", "")
if archive_name:
    print(json.dumps([{"filename": archive_name}]))
else:
    print("[]")
PY
}

print_available_text() {
  python3 - "\${state_file}" <<'PY'
import json
from pathlib import Path
import sys

state_path = Path(sys.argv[1])
if not state_path.exists():
    raise SystemExit(0)
state = json.loads(state_path.read_text(encoding="utf-8"))
archive_name = state.get("archive_name", "")
if archive_name:
    print(archive_name)
PY
}

resolve_remote_path() {
  python3 - "\${state_file}" "\$1" <<'PY'
import json
from pathlib import Path
import sys

state_path = Path(sys.argv[1])
requested = sys.argv[2]
if not state_path.exists():
    print("")
    raise SystemExit(0)
state = json.loads(state_path.read_text(encoding="utf-8"))
archive_name = state.get("archive_name", "")
remote_path = state.get("process_path", "")
if not requested or requested == archive_name:
    print(remote_path)
else:
    print("")
PY
}

if [[ "\${1:-}" == "auth" && "\${2:-}" == "login" ]]; then
  exit 0
fi

if [[ "\${1:-}" == "import" && "\${2:-}" == "upload" ]]; then
  src_path="\${3:-}"
  [[ -f "\${src_path}" ]] || { echo "error: missing import zip: \${src_path}" >&2; exit 1; }
  archive_name="\$(basename "\${src_path}")"
  timestamp="\$(date -u +%Y%m%dT%H%M%SZ)"
  staged_path="\${remote_stage_dir}/\${timestamp}-\${archive_name}"
  remote_path="\${remote_import_dir}/\${timestamp}-\${archive_name}"
  process_path="\${remote_path}"
  if [[ "\${deploy_method}" == "docker" ]]; then
    process_path="\${container_import_dir}/\${timestamp}-\${archive_name}"
  fi
  run_remote_command mkdir -p "\${remote_stage_dir}"
  scp "\${src_path}" "\${ssh_target}:\${staged_path}" >/dev/null
  install_remote_import "\${staged_path}" "\${remote_path}"
  save_state "\${archive_name}" "\${remote_path}" "\${process_path}"
  printf '%s\\n' "\${remote_path}"
  exit 0
fi

if [[ "\${1:-}" == "import" && "\${2:-}" == "list" && "\${3:-}" == "available" ]]; then
  if [[ " \$* " == *" --json "* ]]; then
    print_available_json
  else
    print_available_text
  fi
  exit 0
fi

if [[ "\${1:-}" == "import" && "\${2:-}" == "process" ]]; then
  requested_name="\${3:-}"
  remote_path="\$(resolve_remote_path "\${requested_name}")"
  [[ -n "\${remote_path}" ]] || { echo "error: no staged import archive found for \${requested_name}" >&2; exit 1; }
  run_remote_mmctl import process "\${remote_path}" --bypass-upload --extract-content=false
  exit \$?
fi

if [[ "\${1:-}" == "import" && "\${2:-}" == "job" ]]; then
  shift 2
  run_remote_mmctl import job "\$@"
  exit \$?
fi

run_remote_mmctl "\$@"
EOF
    chmod +x "${wrapper_path}"
    export PATH="${wrapper_dir}:${PATH}"
    return
  fi

  command -v mmctl >/dev/null 2>&1 || fail "mmctl not found in PATH; install mmctl or set TARGET_HOST with ENABLE_LOCAL_MODE=1"
}

run_intake() {
  ensure_dirs
  resolve_handoff_json
  local effective_import_zip
  effective_import_zip="$(resolve_import_zip)"
  [[ -n "${effective_import_zip}" && -f "${effective_import_zip}" ]] || fail "missing import zip for intake validation"

  python3 "${scripts_dir}/build-phase2-intake-manifest.py" \
    --workspace "${workspace_name}" \
    --environment "${PHASE2_ENVIRONMENT:-staging}" \
    --output "${intake_manifest}" \
    "${handoff_json}" "${effective_import_zip}"

  python3 "${scripts_dir}/validate-phase2-intake.py" \
    --handoff-json "${handoff_json}" \
    --intake-manifest "${intake_manifest}" \
    --output-json "${intake_report}"
}

run_render_config() {
  ensure_dirs
  [[ -n "${MATTERMOST_URL:-}" ]] || fail "MATTERMOST_URL must be set"
  [[ -n "${POSTGRES_DSN:-}" ]] || fail "POSTGRES_DSN must be set"

  local mm_hostname
  mm_hostname="$(url_hostname "${MATTERMOST_URL}")"
  [[ -n "${mm_hostname}" ]] || fail "MATTERMOST_URL must include a hostname"

  local -a cors_origins materialize_cmd
  parse_csv_into_array "${ALLOW_CORS_ORIGINS:-}" cors_origins
  materialize_cmd=(
    python3 "${scripts_dir}/materialize-mattermost-config.py"
    --output "${rendered_config}"
    --site-url "${MATTERMOST_URL}"
    --listen-address "${MATTERMOST_LISTEN_ADDRESS:-127.0.0.1:8065}"
    --data-source "${POSTGRES_DSN}"
    --max-file-size "${MAX_FILE_SIZE_BYTES:-52428800}"
    --max-post-size "${MAX_POST_SIZE:-16383}"
    --open-server
    --signup-enabled
    --disable-email-verification
  )
  if [[ -n "${SMTP_SERVER:-}" ]]; then
    materialize_cmd+=(
      --smtp-server "${SMTP_SERVER}"
      --smtp-port "${SMTP_PORT:-587}"
      --smtp-username "${SMTP_USERNAME:-}"
      --smtp-password "${SMTP_PASSWORD:-}"
    )
  fi
  if [[ "${ENABLE_LOCAL_MODE:-0}" == "1" ]]; then
    materialize_cmd+=(--enable-local-mode --local-mode-socket "${LOCAL_MODE_SOCKET_PATH:-/var/tmp/mattermost_local.socket}")
  fi
  local origin
  for origin in "${cors_origins[@]}"; do
    [[ -n "${origin}" ]] && materialize_cmd+=(--allow-origin "${origin}")
  done
  "${materialize_cmd[@]}"

  "${scripts_dir}/render-nginx-config.sh" \
    "${mm_hostname}" \
    "${MATTERMOST_LISTEN_ADDRESS:-127.0.0.1:8065}" \
    "$(
      if [[ "${NGINX_ENABLE_TLS:-0}" == "1" || "${CLOUDFLARE_ENABLED:-0}" == "1" ]]; then
        printf '%s' "${NGINX_CERT_PATH:-/etc/nginx/ssl/origin.pem}"
      fi
    )" \
    "$(
      if [[ "${NGINX_ENABLE_TLS:-0}" == "1" || "${CLOUDFLARE_ENABLED:-0}" == "1" ]]; then
        printf '%s' "${NGINX_KEY_PATH:-/etc/nginx/ssl/origin-key.pem}"
      fi
    )" \
    "${MAX_UPLOAD_BODY:-50M}" > "${rendered_nginx}"

  local -a validate_cmd
  validate_cmd=(
    python3 "${scripts_dir}/validate-mattermost-config.py"
    "${rendered_config}"
    --expected-site-url "${MATTERMOST_URL}"
    --expected-listen "${MATTERMOST_LISTEN_ADDRESS:-127.0.0.1:8065}"
    --require-open-server
    --require-signup-enabled
    --require-email-verification-disabled
    --output-json "${config_report}"
  )
  if [[ -n "${SMTP_SERVER:-}" ]]; then
    validate_cmd+=(--require-smtp)
  fi
  for origin in "${cors_origins[@]}"; do
    [[ -n "${origin}" ]] && validate_cmd+=(--allow-origin "${origin}")
  done
  "${validate_cmd[@]}"
}

run_edge() {
  ensure_dirs
  [[ "${CLOUDFLARE_ENABLED:-0}" == "1" ]] || fail "CLOUDFLARE_ENABLED must be set to 1 for edge automation"
  [[ -n "${MATTERMOST_URL:-}" ]] || fail "MATTERMOST_URL must be set"
  [[ -n "${ORIGIN_SERVER_IP:-}" ]] || fail "ORIGIN_SERVER_IP must be set"

  local mm_hostname
  mm_hostname="$(url_hostname "${MATTERMOST_URL}")"
  [[ -n "${mm_hostname}" ]] || fail "MATTERMOST_URL must include a hostname"

  local -a edge_cmd
  edge_cmd=(
    python3 "${scripts_dir}/provision-cloudflare-edge.py"
    --mode "${CLOUDFLARE_MODE:-plan}"
    --hostname "${mm_hostname}"
    --origin-ip "${ORIGIN_SERVER_IP}"
    --origin-cert-out "${rendered_origin_cert}"
    --origin-key-out "${rendered_origin_key}"
    --output-json "${edge_provision_report}"
  )
  [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] && edge_cmd+=(--api-token "${CLOUDFLARE_API_TOKEN}")
  [[ -n "${CF_ZONE_ID:-}" ]] && edge_cmd+=(--zone-id "${CF_ZONE_ID}")
  [[ -n "${CALLS_HOSTNAME:-}" ]] && edge_cmd+=(--calls-hostname "${CALLS_HOSTNAME}")
  [[ -n "${CALLS_SERVER_IP:-}" ]] && edge_cmd+=(--calls-origin-ip "${CALLS_SERVER_IP}")

  local -a origin_hostnames
  parse_csv_into_array "${CLOUDFLARE_ORIGIN_HOSTNAMES:-}" origin_hostnames
  local item
  for item in "${origin_hostnames[@]}"; do
    [[ -n "${item}" ]] && edge_cmd+=(--origin-hostname "${item}")
  done
  "${edge_cmd[@]}"
}

run_provision() {
  ensure_dirs
  "${scripts_dir}/provision-mattermost-host.sh" "${PROVISION_MODE:-plan}" "${TARGET_HOST:-}" "${provision_report}"
}

run_deploy() {
  ensure_dirs
  [[ -f "${rendered_config}" ]] || run_render_config
  if [[ "${CLOUDFLARE_ENABLED:-0}" == "1" && ! -f "${rendered_origin_cert}" && "${CLOUDFLARE_MODE:-plan}" != "plan" ]]; then
    run_edge
  fi

  local -a deploy_env
  deploy_env=()
  if [[ -f "${rendered_origin_cert}" && -f "${rendered_origin_key}" ]]; then
    deploy_env+=("SOURCE_CERT_PATH=${rendered_origin_cert}" "SOURCE_KEY_PATH=${rendered_origin_key}")
  fi
  env "${deploy_env[@]}" \
    "${scripts_dir}/deploy-mattermost-stack.sh" \
    "${DEPLOY_MODE:-plan}" \
    "${rendered_config}" \
    "${rendered_nginx}" \
    "${deploy_report}" \
    "${TARGET_HOST:-}"
}

run_verify_live() {
  ensure_dirs
  [[ -n "${MATTERMOST_URL:-}" ]] || fail "MATTERMOST_URL must be set"
  local -a live_cmd
  live_cmd=(
    python3 "${scripts_dir}/verify-mattermost-live.py"
    --mattermost-url "${MATTERMOST_URL}"
    --output-json "${live_report_json}"
    --output-md "${live_report_md}"
    --retries "${LIVE_VERIFY_RETRIES:-6}"
    --retry-delay "${LIVE_VERIFY_RETRY_DELAY:-5}"
  )
  if [[ -n "${SMTP_SERVER:-}" ]]; then
    live_cmd+=(--smtp-host "${SMTP_SERVER}")
    if [[ -n "${SMTP_PORT:-}" ]]; then
      live_cmd+=(--smtp-port "${SMTP_PORT}")
    fi
  fi
  "${live_cmd[@]}"

  if [[ "${CLOUDFLARE_ENABLED:-0}" == "1" ]]; then
    [[ -n "${ORIGIN_SERVER_IP:-}" ]] || fail "ORIGIN_SERVER_IP must be set when CLOUDFLARE_ENABLED=1"
    local mm_hostname
    mm_hostname="$(url_hostname "${MATTERMOST_URL}")"
    local -a edge_verify_cmd
    edge_verify_cmd=(
      python3 "${scripts_dir}/verify-cloudflare-edge.py"
      --hostname "${mm_hostname}"
      --mattermost-url "${MATTERMOST_URL}"
      --origin-ip "${ORIGIN_SERVER_IP:-}"
      --output-json "${edge_report}"
    )
    [[ -f "${rendered_origin_cert}" ]] && edge_verify_cmd+=(--origin-cert-file "${rendered_origin_cert}")
    [[ -n "${CALLS_HOSTNAME:-}" ]] && edge_verify_cmd+=(--calls-hostname "${CALLS_HOSTNAME}")
    [[ -n "${CALLS_SERVER_IP:-}" ]] && edge_verify_cmd+=(--calls-origin-ip "${CALLS_SERVER_IP}")
    "${edge_verify_cmd[@]}"
  fi
}

run_staging() {
  ensure_dirs
  ensure_mmctl_path
  resolve_handoff_json
  local effective_import_zip
  local db_ssh_target
  local smoke_database_url="${SMOKE_DATABASE_URL:-${POSTGRES_DSN:-${STAGING_DATABASE_URL:-${DATABASE_URL:-}}}}"
  effective_import_zip="$(resolve_import_zip)"
  db_ssh_target="$(database_ssh_target "${smoke_database_url}")"
  [[ -n "${effective_import_zip}" && -f "${effective_import_zip}" ]] || fail "missing import zip for staging rehearsal"
  [[ -n "${STAGING_URL:-${MATTERMOST_URL:-}}" ]] || fail "STAGING_URL or MATTERMOST_URL must be set"
  [[ -n "${MATTERMOST_ADMIN_USER:-}" && -n "${MATTERMOST_ADMIN_PASS:-}" ]] || fail "admin credentials are required"
  if [[ "${REQUIRE_POST_IMPORT_SMOKE:-1}" == "1" && -z "${smoke_database_url}" ]]; then
    fail "SMOKE_DATABASE_URL, POSTGRES_DSN, STAGING_DATABASE_URL, or DATABASE_URL must be set for post-import smoke tests"
  fi

  HANDOFF_JSON="${handoff_json}" DATABASE_URL="${smoke_database_url}" DATABASE_SSH_TARGET="${db_ssh_target}" \
    "${scripts_dir}/run-staging-rehearsal.sh" \
    "${STAGING_URL:-${MATTERMOST_URL}}" \
    "${effective_import_zip}" \
    "${MATTERMOST_ADMIN_USER}" \
    "${MATTERMOST_ADMIN_PASS}" \
    "${staging_report_dir}"

  local latest
  latest="$(latest_matching_file 'staging-summary.*.json' "${staging_report_dir}")"
  [[ -n "${latest}" ]] && cp "${latest}" "${latest_staging_report}"
  latest="$(latest_matching_file 'smoke-tests.*.json' "${staging_report_dir}")"
  if [[ -n "${latest}" ]]; then
    cp "${latest}" "${latest_smoke_report}"
  fi
  latest="$(latest_matching_file 'reconciliation.*.json' "${staging_report_dir}")"
  if [[ -n "${latest}" ]]; then
    cp "${latest}" "${latest_reconcile_report}"
  fi
}

run_restore() {
  ensure_dirs
  [[ -n "${BACKUP_PATH:-}" && -f "${BACKUP_PATH}" ]] || fail "BACKUP_PATH must reference a backup file"
  [[ -n "${SCRATCH_DB_URL:-}" ]] || fail "SCRATCH_DB_URL must be set"
  "${scripts_dir}/restore-drill.sh" "${BACKUP_PATH}" "${SCRATCH_DB_URL}" "${restore_report_dir}"
  local latest
  latest="$(latest_matching_file 'restore-drill.*.json' "${restore_report_dir}")"
  [[ -n "${latest}" ]] && cp "${latest}" "${latest_restore_report}"
}

run_ready() {
  ensure_dirs
  resolve_handoff_json
  [[ -f "${intake_report}" ]] || run_intake
  [[ -f "${config_report}" ]] || run_render_config
  [[ -f "${live_report_json}" ]] || run_verify_live
  [[ -f "${latest_staging_report}" ]] || run_staging

  local -a readiness_cmd
  readiness_cmd=(
    python3 "${scripts_dir}/validate-cutover-readiness.py"
    --handoff-json "${handoff_json}"
    --config-report "${config_report}"
    --staging-report "${latest_staging_report}"
    --output-json "${cutover_readiness_report}"
    --rollback-owner "${ROLLBACK_OWNER:-unassigned}"
  )
  [[ -f "${live_report_json}" ]] && readiness_cmd+=(--live-report "${live_report_json}")
  [[ -f "${latest_smoke_report}" ]] && readiness_cmd+=(--smoke-report "${latest_smoke_report}")
  [[ -f "${latest_reconcile_report}" ]] && readiness_cmd+=(--reconciliation-report "${latest_reconcile_report}")
  [[ -f "${latest_restore_report}" ]] && readiness_cmd+=(--restore-report "${latest_restore_report}")
  [[ -f "${evidence_pack:-}" ]] && readiness_cmd+=(--evidence-pack "${evidence_pack}")
  [[ -f "${latest_activation_report}" ]] && readiness_cmd+=(--activation-report "${latest_activation_report}")
  [[ -f "${edge_report}" ]] && readiness_cmd+=(--edge-report "${edge_report}")
  "${readiness_cmd[@]}"

  local -a score_cmd
  score_cmd=(
    python3 "${scripts_dir}/generate-readiness-score.py"
    --handoff-json "${handoff_json}"
    --intake-report "${intake_report}"
    --config-report "${config_report}"
    --staging-report "${latest_staging_report}"
    --cutover-report "${cutover_readiness_report}"
    --output-json "${readiness_score_json}"
    --output-md "${readiness_score_md}"
  )
  [[ -f "${live_report_json}" ]] && score_cmd+=(--live-report "${live_report_json}")
  [[ -f "${latest_smoke_report}" ]] && score_cmd+=(--smoke-report "${latest_smoke_report}")
  [[ -f "${latest_reconcile_report}" ]] && score_cmd+=(--reconciliation-report "${latest_reconcile_report}")
  [[ -f "${latest_activation_report}" ]] && score_cmd+=(--activation-report "${latest_activation_report}")
  [[ -f "${latest_restore_report}" ]] && score_cmd+=(--restore-report "${latest_restore_report}")
  [[ -f "${edge_report}" ]] && score_cmd+=(--edge-report "${edge_report}")
  "${score_cmd[@]}"

  local -a readiness_summary_cmd
  readiness_summary_cmd=(
    python3 "${scripts_dir}/generate-phase2-readiness.py"
    --output-md "${phase2_readiness_md}"
    --handoff-json "${handoff_json}"
    --intake-report "${intake_report}"
    --config-report "${config_report}"
    --score-json "${readiness_score_json}"
    --staging-report "${latest_staging_report}"
    --cutover-report "${cutover_readiness_report}"
  )
  [[ -f "${live_report_json}" ]] && readiness_summary_cmd+=(--live-report "${live_report_json}")
  [[ -f "${latest_smoke_report}" ]] && readiness_summary_cmd+=(--smoke-report "${latest_smoke_report}")
  [[ -f "${latest_reconcile_report}" ]] && readiness_summary_cmd+=(--reconciliation-report "${latest_reconcile_report}")
  [[ -f "${latest_activation_report}" ]] && readiness_summary_cmd+=(--activation-report "${latest_activation_report}")
  [[ -f "${edge_report}" ]] && readiness_summary_cmd+=(--edge-report "${edge_report}")
  "${readiness_summary_cmd[@]}"
}

run_cutover() {
  ensure_dirs
  ensure_mmctl_path
  resolve_handoff_json
  local effective_import_zip
  local db_ssh_target
  local smoke_database_url="${SMOKE_DATABASE_URL:-${POSTGRES_DSN:-${DATABASE_URL:-}}}"
  effective_import_zip="$(resolve_import_zip)"
  db_ssh_target="$(database_ssh_target "${smoke_database_url}")"
  [[ -n "${effective_import_zip}" && -f "${effective_import_zip}" ]] || fail "missing import zip for cutover"
  [[ -n "${MATTERMOST_URL:-}" ]] || fail "MATTERMOST_URL must be set"
  [[ -n "${MATTERMOST_ADMIN_USER:-}" && -n "${MATTERMOST_ADMIN_PASS:-}" ]] || fail "admin credentials are required"
  [[ -n "${smoke_database_url}" ]] || fail "SMOKE_DATABASE_URL, POSTGRES_DSN, or DATABASE_URL must be set for production smoke checks"
  [[ -f "${cutover_readiness_report}" ]] || run_ready

  DATABASE_URL="${smoke_database_url}" DATABASE_SSH_TARGET="${db_ssh_target}" SMTP_TEST_EMAIL="${SMTP_TEST_EMAIL:-}" "${scripts_dir}/execute-production-cutover.sh" "${MATTERMOST_URL}" "${effective_import_zip}" "${MATTERMOST_ADMIN_USER}" "${MATTERMOST_ADMIN_PASS}" "${handoff_json}" "${cutover_report_dir}" "${cutover_readiness_report}"

  local latest
  latest="$(latest_matching_file 'activation-proof.*.json' "${cutover_report_dir}")"
  if [[ -n "${latest}" ]]; then
    cp "${latest}" "${latest_activation_report}"
  fi
}

run_rollback() {
  ensure_dirs
  local backup="${ROLLBACK_DB_BACKUP:-${BACKUP_PATH:-}}"
  [[ -n "${backup}" ]] || fail "ROLLBACK_DB_BACKUP or BACKUP_PATH must be set"
  [[ -n "${DATABASE_URL:-}" ]] || fail "DATABASE_URL must be set"
  "${scripts_dir}/rollback-cutover.sh" "${backup}" "${DATABASE_URL}" "${reports_dir}/rollback"
}

run_all() {
  run_intake
  run_render_config
  if [[ "${CLOUDFLARE_ENABLED:-0}" == "1" ]]; then
    run_edge
  fi
  run_provision
  run_deploy
  run_verify_live
  run_staging
  run_restore
  run_ready
}

usage() {
  cat <<'EOF'
usage: ./operate.sh <intake|render-config|edge|provision|deploy|verify-live|staging|restore|ready|cutover|rollback|all>
EOF
}

main() {
  local command="${1:-}"
  case "${command}" in
    intake) run_intake ;;
    render-config) run_render_config ;;
    edge) run_edge ;;
    provision) run_provision ;;
    deploy) run_deploy ;;
    verify-live) run_verify_live ;;
    staging) run_staging ;;
    restore) run_restore ;;
    ready) run_ready ;;
    cutover) run_cutover ;;
    rollback) run_rollback ;;
    all) run_all ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
