#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
phase2_skill_dir="$(cd "${script_dir}/.." && pwd)"
skills_root="$(cd "${phase2_skill_dir}/.." && pwd)"
phase1_skill_dir="${skills_root}/slack-migration-to-mattermost-phase-1-extraction"
phase1_scripts_dir="${phase1_skill_dir}/scripts"
phase1_migrate_sh="${phase1_skill_dir}/migrate.sh"
tmp_root="${E2E_REHEARSAL_ROOT:-}"

if [[ -z "${tmp_root}" ]]; then
  tmp_root="$(mktemp -d -t slack-mm-e2e-XXXXXX)"
else
  mkdir -p "${tmp_root}"
fi

phase1_export_dir="${tmp_root}/phase1-export-rehearsal"
phase1_pipeline_dir="${tmp_root}/phase1-pipeline"
phase2_workdir="${tmp_root}/phase2"
logs_dir="${tmp_root}/logs"
wrapper_dir="${tmp_root}/bin"
summary_json="${tmp_root}/e2e-summary.json"
summary_md="${tmp_root}/e2e-summary.md"
phase2_config="${tmp_root}/phase2.config.env"
phase1_config="${tmp_root}/phase1.config.env"
mkdir -p "${logs_dir}" "${wrapper_dir}" "${phase2_workdir}"

for cmd in docker python3 curl psql jq zip; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "error: required command not found: ${cmd}" >&2
    exit 1
  }
done

free_port() {
  python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

suffix="$(date -u +%Y%m%d%H%M%S)-$$"
network_name="mm-e2e-net-${suffix}"
db_container="mm-e2e-db-${suffix}"
app_container="mm-e2e-app-${suffix}"
db_port="${E2E_DB_PORT:-$(free_port)}"
mm_port="${E2E_MM_PORT:-$(free_port)}"
db_password="${E2E_DB_PASSWORD:-mattermost-password}"
db_user="${E2E_DB_USER:-mmuser}"
db_name="${E2E_DB_NAME:-mattermost}"
db_url_host="postgres://${db_user}:${db_password}@127.0.0.1:${db_port}/${db_name}?sslmode=disable"
db_url_container="postgres://${db_user}:${db_password}@${db_container}:5432/${db_name}?sslmode=disable&connect_timeout=10"
mattermost_url="http://127.0.0.1:${mm_port}"
status="running"

write_summary() {
  cat > "${summary_json}" <<EOF
{
  "status": "${status}",
  "phase1_export_dir": "${phase1_export_dir}",
  "phase1_pipeline_dir": "${phase1_pipeline_dir}",
  "phase2_workdir": "${phase2_workdir}",
  "mattermost_url": "${mattermost_url}",
  "database_url": "${db_url_host}",
  "network_name": "${network_name}",
  "db_container": "${db_container}",
  "app_container": "${app_container}",
  "phase2_reports": {
    "intake": "${phase2_workdir}/workdir/reports/phase2-intake-report.json",
    "live": "${phase2_workdir}/workdir/reports/live-stack.json",
    "staging": "${phase2_workdir}/workdir/reports/latest-staging.json",
    "smoke": "${phase2_workdir}/workdir/reports/latest-smoke.json",
    "reconciliation": "${phase2_workdir}/workdir/reports/latest-reconciliation.json",
    "ready": "${phase2_workdir}/workdir/reports/cutover-readiness.json",
    "score": "${phase2_workdir}/workdir/reports/readiness-score.json",
    "summary": "${phase2_workdir}/workdir/reports/phase2-readiness.md"
  },
  "logs_dir": "${logs_dir}"
}
EOF

  cat > "${summary_md}" <<EOF
# Slack to Mattermost E2E Rehearsal

- Status: ${status}
- Phase 1 export rehearsal: \`${phase1_export_dir}\`
- Phase 1 pipeline: \`${phase1_pipeline_dir}\`
- Phase 2 workdir: \`${phase2_workdir}\`
- Mattermost URL: \`${mattermost_url}\`
- Database URL: \`${db_url_host}\`
- Logs: \`${logs_dir}\`
EOF
}

cleanup() {
  if docker ps -a --format '{{.Names}}' | grep -qx "${app_container}"; then
    docker logs "${app_container}" > "${logs_dir}/mattermost.log" 2>&1 || true
  fi
  if docker ps -a --format '{{.Names}}' | grep -qx "${db_container}"; then
    docker logs "${db_container}" > "${logs_dir}/postgres.log" 2>&1 || true
  fi
  write_summary
  if [[ "${KEEP_E2E_CONTAINERS:-0}" != "1" ]]; then
    docker rm -f "${app_container}" "${db_container}" >/dev/null 2>&1 || true
    docker network rm "${network_name}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "running Phase 1 official export rehearsal..."
PHASE1_EXPORT_REHEARSAL_ROOT="${phase1_export_dir}" "${phase1_scripts_dir}/rehearse-official-export.sh"

cat > "${phase1_config}" <<EOF
WORKSPACE_NAME="e2e-rehearsal"
PHASE1_WORKSPACE_ROOT="${phase1_pipeline_dir}/workdir"
MATTERMOST_TEAM_NAME="sample-team"
MATTERMOST_TEAM_DISPLAY_NAME="Sample Team"
SLACK_EXPORT_ZIP="${phase1_export_dir}/raw/slack-export.zip"
SLACK_CHANNEL_AUDIT_CSV="${phase1_export_dir}/raw/channel-audit.csv"
SLACK_MEMBER_CSV="${phase1_export_dir}/raw/member-list.csv"
MMETL_BIN="mmetl"
MMETL_DEFAULT_EMAIL_DOMAIN="example.com"
MMETL_EXTRA_FLAGS="--skip-empty-emails --discard-invalid-props"
EOF

echo "running Phase 1 executable pipeline with mmetl..."
(
  cd "${phase1_skill_dir}"
  PHASE1_CONFIG="${phase1_config}" "${phase1_migrate_sh}" all
)

handoff_json="${phase1_pipeline_dir}/workdir/artifacts/reports/handoff.json"
import_zip="${phase1_pipeline_dir}/workdir/artifacts/import-ready/mattermost-bulk-import.zip"
[[ -f "${handoff_json}" ]] || { echo "error: missing handoff json from phase1 pipeline" >&2; exit 1; }
[[ -f "${import_zip}" ]] || { echo "error: missing import zip from phase1 pipeline" >&2; exit 1; }

docker image inspect postgres:16-alpine >/dev/null 2>&1 || docker pull postgres:16-alpine >/dev/null
docker image inspect mattermost/mattermost-team-edition:latest >/dev/null 2>&1 || docker pull mattermost/mattermost-team-edition:latest >/dev/null

docker network create "${network_name}" >/dev/null

docker run -d \
  --name "${db_container}" \
  --network "${network_name}" \
  -e POSTGRES_DB="${db_name}" \
  -e POSTGRES_USER="${db_user}" \
  -e POSTGRES_PASSWORD="${db_password}" \
  -p "${db_port}:5432" \
  postgres:16-alpine >/dev/null

for _ in $(seq 1 60); do
  if docker exec "${db_container}" pg_isready -U "${db_user}" -d "${db_name}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "${db_container}" pg_isready -U "${db_user}" -d "${db_name}" >/dev/null

docker run -d \
  --name "${app_container}" \
  --network "${network_name}" \
  -p "${mm_port}:8065" \
  -e MM_SQLSETTINGS_DRIVERNAME=postgres \
  -e MM_SQLSETTINGS_DATASOURCE="${db_url_container}" \
  -e MM_SERVICESETTINGS_SITEURL="${mattermost_url}" \
  -e MM_SERVICESETTINGS_LISTENADDRESS=":8065" \
  -e MM_SERVICESETTINGS_ENABLELOCALMODE=true \
  -e MM_SERVICESETTINGS_ENABLEDEVELOPER=true \
  -e MM_TEAMSETTINGS_ENABLEOPENSERVER=true \
  -e MM_EMAILSETTINGS_ENABLESIGNUPWITHEMAIL=true \
  mattermost/mattermost-team-edition:latest >/dev/null

for _ in $(seq 1 120); do
  if curl -fsS "${mattermost_url}/api/v4/system/ping" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS "${mattermost_url}/api/v4/system/ping" >/dev/null

mmctl_state="${tmp_root}/mmctl-state.json"
printf '{}\n' > "${mmctl_state}"
cat > "${wrapper_dir}/mmctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

container="${MMCTL_E2E_CONTAINER:?}"
state_file="${MMCTL_E2E_STATE:?}"

if [[ "${1:-}" == "auth" && "${2:-}" == "login" ]]; then
  exit 0
fi

if [[ "${1:-}" == "import" && "${2:-}" == "upload" ]]; then
  archive_path="${3:?}"
  archive_name="$(basename "${archive_path}")"
  upload_id="e2e$(date -u +%s)"
  available_filename="${upload_id}_${archive_name}"
  container_path="/tmp/${available_filename}"
  docker cp "${archive_path}" "${container}:${container_path}" >/dev/null
  python3 - "${state_file}" "${archive_name}" "${available_filename}" "${container_path}" <<'PY'
import json
from pathlib import Path
import sys

state_path = Path(sys.argv[1])
state = {}
if state_path.exists():
    state = json.loads(state_path.read_text(encoding="utf-8"))
state["archive_name"] = sys.argv[2]
state["available_filename"] = sys.argv[3]
state["container_path"] = sys.argv[4]
state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
  printf '%s\n%s\n' "${upload_id}" "${available_filename}"
  exit 0
fi

if [[ "${1:-}" == "import" && "${2:-}" == "list" && "${3:-}" == "available" ]]; then
  python3 - "${state_file}" <<'PY'
import json
from pathlib import Path
import sys

state_path = Path(sys.argv[1])
state = {}
if state_path.exists():
    state = json.loads(state_path.read_text(encoding="utf-8"))
available_filename = state.get("available_filename", "")
if available_filename:
    print(json.dumps([{"filename": available_filename}]))
else:
    print("[]")
PY
  exit 0
fi

if [[ "${1:-}" == "import" && "${2:-}" == "process" ]]; then
  requested_name="${3:-}"
  container_path="$(
    python3 - "${state_file}" "${requested_name}" <<'PY'
import json
from pathlib import Path
import sys

state = {}
state_path = Path(sys.argv[1])
if state_path.exists():
    state = json.loads(state_path.read_text(encoding="utf-8"))
if sys.argv[2] and state.get("available_filename") == sys.argv[2]:
    print(state.get("container_path", ""))
PY
  )"
  [[ -n "${container_path}" ]] || { echo "error: requested import filename does not match staged upload" >&2; exit 1; }
  exec docker exec "${container}" /mattermost/bin/mmctl --local import process "${container_path}" --bypass-upload --extract-content=false
fi

if [[ "${1:-}" == "import" && "${2:-}" == "job" ]]; then
  shift 2
  exec docker exec "${container}" /mattermost/bin/mmctl --local import job "$@"
fi

exec docker exec "${container}" /mattermost/bin/mmctl --local "$@"
EOF
chmod +x "${wrapper_dir}/mmctl"
export PATH="${wrapper_dir}:${PATH}"
export MMCTL_E2E_CONTAINER="${app_container}"
export MMCTL_E2E_STATE="${mmctl_state}"

cat > "${phase2_config}" <<EOF
WORKSPACE_NAME="e2e-rehearsal"
PHASE2_WORKSPACE_ROOT="${phase2_workdir}/workdir"
HANDOFF_JSON="${handoff_json}"
IMPORT_ZIP="${import_zip}"
MATTERMOST_URL="${mattermost_url}"
STAGING_URL="${mattermost_url}"
MATTERMOST_ADMIN_USER="local-mode"
MATTERMOST_ADMIN_PASS="local-mode"
MATTERMOST_TEAM_NAME="sample-team"
POSTGRES_DSN="${db_url_host}"
DATABASE_URL="${db_url_host}"
STAGING_DATABASE_URL="${db_url_host}"
ROLLBACK_OWNER="e2e-rehearsal"
EOF

echo "running Phase 2 live rehearsal..."
(
  cd "${phase2_skill_dir}"
  PHASE2_CONFIG="${phase2_config}" ./operate.sh intake
  PHASE2_CONFIG="${phase2_config}" ./operate.sh render-config
  PHASE2_CONFIG="${phase2_config}" ./operate.sh verify-live
  PHASE2_CONFIG="${phase2_config}" ./operate.sh staging
  PHASE2_CONFIG="${phase2_config}" ./operate.sh ready
)

status="passed"
echo "e2e rehearsal artifacts: ${tmp_root}"
