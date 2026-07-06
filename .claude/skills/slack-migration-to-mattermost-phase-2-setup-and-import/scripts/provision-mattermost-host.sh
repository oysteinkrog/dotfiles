#!/usr/bin/env bash
set -euo pipefail

mode="${1:-plan}"
target_host="${2:-${TARGET_HOST:-}}"
report_json="${3:-reports/provision-host.json}"
deploy_user="${TARGET_SSH_USER:-deploy}"
plan_script="${report_json%.json}.sh"
database_mode="${PROVISION_DATABASE_MODE:-auto}"

mkdir -p "$(dirname "${report_json}")"

cat > "${plan_script}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || { echo "error: sudo not found in PATH" >&2; exit 1; }
  SUDO=(sudo)
fi

psql_as_postgres() {
  if [[ "${#SUDO[@]}" -eq 0 ]]; then
    runuser -u postgres -- psql "$@"
  else
    "${SUDO[@]}" -u postgres psql "$@"
  fi
}

database_mode="${PROVISION_DATABASE_MODE:-auto}"
needs_local_postgres=0
if [[ "${database_mode}" == "local" ]]; then
  needs_local_postgres=1
elif [[ "${database_mode}" == "auto" && -n "${POSTGRES_DSN:-}" ]]; then
  needs_local_postgres="$(
    python3 - <<'PY'
from urllib.parse import urlparse
import os

dsn = os.environ.get("POSTGRES_DSN", "").strip()
host = (urlparse(dsn).hostname or "").lower()
print("1" if host in ("", "localhost", "127.0.0.1") else "0")
PY
  )"
fi

"${SUDO[@]}" apt-get update
if [[ "${needs_local_postgres}" == "1" ]]; then
  "${SUDO[@]}" apt-get install -y curl jq nginx ufw fail2ban unattended-upgrades postgresql
else
  "${SUDO[@]}" apt-get install -y curl jq nginx ufw fail2ban unattended-upgrades postgresql-client
fi
"${SUDO[@]}" ufw allow 22/tcp
"${SUDO[@]}" ufw allow 80/tcp
"${SUDO[@]}" ufw allow 443/tcp
"${SUDO[@]}" ufw allow 8443/udp
"${SUDO[@]}" ufw --force enable
"${SUDO[@]}" systemctl enable --now fail2ban
"${SUDO[@]}" systemctl enable --now unattended-upgrades
if [[ "${needs_local_postgres}" == "1" ]]; then
  [[ -n "${POSTGRES_DSN:-}" ]] || { echo "error: POSTGRES_DSN must be set when local PostgreSQL provisioning is enabled" >&2; exit 1; }
  "${SUDO[@]}" systemctl enable --now postgresql
  mapfile -t postgres_parts < <(
    python3 - <<'PY'
from urllib.parse import unquote, urlparse
import os

parsed = urlparse(os.environ["POSTGRES_DSN"])
print(unquote(parsed.username or ""))
print(unquote(parsed.password or ""))
print(parsed.path.lstrip("/"))
PY
  )
  pg_user="${postgres_parts[0]:-}"
  pg_password="${postgres_parts[1]:-}"
  pg_database="${postgres_parts[2]:-}"
  [[ -n "${pg_user}" ]] || { echo "error: POSTGRES_DSN is missing username" >&2; exit 1; }
  [[ -n "${pg_password}" ]] || { echo "error: POSTGRES_DSN is missing password" >&2; exit 1; }
  [[ -n "${pg_database}" ]] || { echo "error: POSTGRES_DSN is missing database name" >&2; exit 1; }
  [[ "${pg_user}" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]] || { echo "error: unsupported PostgreSQL username for auto-provisioning: ${pg_user}" >&2; exit 1; }
  [[ "${pg_database}" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]] || { echo "error: unsupported PostgreSQL database name for auto-provisioning: ${pg_database}" >&2; exit 1; }
  escaped_pg_password="${pg_password//\'/\'\'}"
  if ! psql_as_postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${pg_user}'" | grep -qx 1; then
    psql_as_postgres -c "CREATE USER ${pg_user} WITH PASSWORD '${escaped_pg_password}';"
  fi
  if ! psql_as_postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${pg_database}'" | grep -qx 1; then
    psql_as_postgres -c "CREATE DATABASE ${pg_database} OWNER ${pg_user};"
  fi
fi
EOF
chmod +x "${plan_script}"

status="planned"
note="plan only"

case "${mode}" in
  plan)
    ;;
  local)
    bash "${plan_script}"
    status="executed"
    note="executed locally"
    ;;
  ssh)
    [[ -n "${target_host}" ]] || { echo "error: target host is required for ssh mode" >&2; exit 1; }
    ssh "${deploy_user}@${target_host}" \
      "PROVISION_DATABASE_MODE=$(printf '%q' "${database_mode}") POSTGRES_DSN=$(printf '%q' "${POSTGRES_DSN:-}") bash -se" \
      < "${plan_script}"
    status="executed"
    note="executed via ssh"
    ;;
  *)
    echo "error: mode must be one of: plan, local, ssh" >&2
    exit 1
    ;;
esac

cat > "${report_json}" <<EOF
{
  "status": "${status}",
  "mode": "${mode}",
  "target_host": "${target_host}",
  "plan_script": "${plan_script}",
  "note": "${note}"
}
EOF
echo "wrote ${report_json}"
