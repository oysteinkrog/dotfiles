#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: $0 <plan|local|ssh> <rendered-config> <rendered-nginx> <report-json> [target-host]" >&2
  exit 1
fi

mode="$1"
rendered_config="$2"
rendered_nginx="$3"
report_json="$4"
target_host="${5:-${TARGET_HOST:-}}"
deploy_user="${TARGET_SSH_USER:-deploy}"
deploy_method="${DEPLOY_METHOD:-apt}"
config_path="${MATTERMOST_CONFIG_PATH:-/opt/mattermost/config/config.json}"
nginx_site_path="${NGINX_SITE_PATH:-/etc/nginx/sites-available/mattermost.conf}"
nginx_site_link="${NGINX_SITE_LINK:-/etc/nginx/sites-enabled/mattermost.conf}"
nginx_cert_path="${NGINX_CERT_PATH:-/etc/nginx/ssl/origin.pem}"
nginx_key_path="${NGINX_KEY_PATH:-/etc/nginx/ssl/origin-key.pem}"
service_name="${MATTERMOST_SERVICE_NAME:-mattermost}"
mattermost_root="${MATTERMOST_ROOT_DIR:-/opt/mattermost}"
mattermost_data_path="${MATTERMOST_DATA_PATH:-${mattermost_root}/data}"
plan_script="${report_json%.json}.sh"
source_cert_path="${SOURCE_CERT_PATH:-}"
source_key_path="${SOURCE_KEY_PATH:-}"

[[ -f "${rendered_config}" ]] || { echo "error: missing rendered config: ${rendered_config}" >&2; exit 1; }
[[ -f "${rendered_nginx}" ]] || { echo "error: missing rendered nginx config: ${rendered_nginx}" >&2; exit 1; }
if [[ -n "${source_cert_path}" && ! -f "${source_cert_path}" ]]; then
  echo "error: missing source cert: ${source_cert_path}" >&2
  exit 1
fi
if [[ -n "${source_key_path}" && ! -f "${source_key_path}" ]]; then
  echo "error: missing source key: ${source_key_path}" >&2
  exit 1
fi
if [[ -n "${source_cert_path}" && -z "${source_key_path}" ]] || [[ -z "${source_cert_path}" && -n "${source_key_path}" ]]; then
  echo "error: SOURCE_CERT_PATH and SOURCE_KEY_PATH must be set together" >&2
  exit 1
fi
mkdir -p "$(dirname "${report_json}")"

cert_install_block=""
if [[ -n "${source_cert_path}" ]]; then
  cert_install_block=$'"${SUDO[@]}" mkdir -p "'"$(dirname "${nginx_cert_path}")"$'"\n"${SUDO[@]}" install -m 0600 /tmp/mattermost.origin.pem "'"${nginx_cert_path}"$'"\n"${SUDO[@]}" install -m 0600 /tmp/mattermost.origin-key.pem "'"${nginx_key_path}"$'"'
fi

if [[ "${deploy_method}" == "docker" ]]; then
  cat > "${plan_script}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${EUID:-\$(id -u)}" -eq 0 ]]; then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || { echo "error: sudo not found in PATH" >&2; exit 1; }
  SUDO=(sudo)
fi
"\${SUDO[@]}" apt-get update
"\${SUDO[@]}" apt-get install -y docker.io nginx
"\${SUDO[@]}" mkdir -p "$(dirname "${config_path}")" "${mattermost_data_path}"
"\${SUDO[@]}" mkdir -p "$(dirname "${nginx_site_path}")"
"\${SUDO[@]}" mkdir -p "$(dirname "${nginx_site_link}")"
"\${SUDO[@]}" mkdir -p "$(dirname "${nginx_cert_path}")"
"\${SUDO[@]}" install -m 0600 /tmp/mattermost.config.json "${config_path}"
"\${SUDO[@]}" install -m 0644 /tmp/mattermost.nginx.conf "${nginx_site_path}"
${cert_install_block}
"\${SUDO[@]}" ln -sfn "${nginx_site_path}" "${nginx_site_link}"
"\${SUDO[@]}" chown -R 2000:2000 "$(dirname "${config_path}")" "${mattermost_data_path}"
"\${SUDO[@]}" docker pull mattermost/mattermost-team-edition:latest
"\${SUDO[@]}" docker rm -f "${service_name}" >/dev/null 2>&1 || true
"\${SUDO[@]}" docker run -d \
  --name "${service_name}" \
  --restart unless-stopped \
  --network host \
  -v "$(dirname "${config_path}"):/mattermost/config" \
  -v "${mattermost_data_path}:/mattermost/data" \
  mattermost/mattermost-team-edition:latest
"\${SUDO[@]}" nginx -t
"\${SUDO[@]}" systemctl enable --now nginx
"\${SUDO[@]}" systemctl reload nginx
EOF
else
  cat > "${plan_script}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${EUID:-\$(id -u)}" -eq 0 ]]; then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || { echo "error: sudo not found in PATH" >&2; exit 1; }
  SUDO=(sudo)
fi
curl -o- https://deb.packages.mattermost.com/repo-setup.sh | "\${SUDO[@]}" bash -s mattermost
"\${SUDO[@]}" apt-get update
"\${SUDO[@]}" apt-get install -y mattermost nginx
"\${SUDO[@]}" mkdir -p "$(dirname "${config_path}")"
"\${SUDO[@]}" mkdir -p "$(dirname "${nginx_site_path}")"
"\${SUDO[@]}" mkdir -p "$(dirname "${nginx_site_link}")"
"\${SUDO[@]}" mkdir -p "$(dirname "${nginx_cert_path}")"
"\${SUDO[@]}" install -m 0600 -o mattermost -g mattermost /tmp/mattermost.config.json "${config_path}"
"\${SUDO[@]}" install -m 0644 /tmp/mattermost.nginx.conf "${nginx_site_path}"
${cert_install_block}
"\${SUDO[@]}" ln -sfn "${nginx_site_path}" "${nginx_site_link}"
"\${SUDO[@]}" nginx -t
"\${SUDO[@]}" systemctl enable --now nginx
"\${SUDO[@]}" systemctl enable --now "${service_name}"
"\${SUDO[@]}" systemctl restart "${service_name}"
"\${SUDO[@]}" systemctl reload nginx
EOF
fi
chmod +x "${plan_script}"

status="planned"
note="plan only"

case "${mode}" in
  plan)
    ;;
  local)
    install -m 0644 "${rendered_config}" /tmp/mattermost.config.json
    install -m 0644 "${rendered_nginx}" /tmp/mattermost.nginx.conf
    if [[ -n "${source_cert_path}" ]]; then
      install -m 0600 "${source_cert_path}" /tmp/mattermost.origin.pem
      install -m 0600 "${source_key_path}" /tmp/mattermost.origin-key.pem
    fi
    bash "${plan_script}"
    status="executed"
    note="executed locally"
    ;;
  ssh)
    [[ -n "${target_host}" ]] || { echo "error: target host is required for ssh mode" >&2; exit 1; }
    scp "${rendered_config}" "${deploy_user}@${target_host}:/tmp/mattermost.config.json"
    scp "${rendered_nginx}" "${deploy_user}@${target_host}:/tmp/mattermost.nginx.conf"
    if [[ -n "${source_cert_path}" ]]; then
      scp "${source_cert_path}" "${deploy_user}@${target_host}:/tmp/mattermost.origin.pem"
      scp "${source_key_path}" "${deploy_user}@${target_host}:/tmp/mattermost.origin-key.pem"
    fi
    ssh "${deploy_user}@${target_host}" 'bash -se' < "${plan_script}"
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
  "deploy_method": "${deploy_method}",
  "target_host": "${target_host}",
  "plan_script": "${plan_script}",
  "rendered_config": "${rendered_config}",
  "rendered_nginx": "${rendered_nginx}",
  "source_cert_path": "${source_cert_path}",
  "source_key_path": "${source_key_path}",
  "note": "${note}"
}
EOF
echo "wrote ${report_json}"
