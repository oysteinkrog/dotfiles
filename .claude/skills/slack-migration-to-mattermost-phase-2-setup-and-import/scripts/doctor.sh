#!/usr/bin/env bash
# Phase 2 environment doctor. Reports missing tools, credentials, SSH
# reachability, and mmctl wiring without attempting to install anything.
# Pair with scripts/bootstrap-tools.sh for the remediation path.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
config_path="${PHASE2_CONFIG:-${skill_dir}/config.env}"
out_mode="text"
require_mcp="0"
require_remote="0"

for arg in "$@"; do
  case "${arg}" in
    --json) out_mode="json" ;;
    --require-mcp) require_mcp="1" ;;
    --require-remote) require_remote="1" ;;
    -h|--help)
      cat <<'EOF'
usage: doctor.sh [--json] [--require-mcp] [--require-remote]

Checks Phase 2 prerequisites:
  - system commands (python3, jq, curl, ssh, scp, rsync)
  - migration tools (mmctl locally or via TARGET_HOST + ENABLE_LOCAL_MODE)
  - Python modules (requests, psycopg2 / psycopg when direct DB is planned)
  - credentials: HANDOFF_JSON, IMPORT_ZIP, MATTERMOST_URL/ADMIN_USER/ADMIN_PASS,
    POSTGRES_DSN or SMOKE_DATABASE_URL
  - SSH reachability to TARGET_HOST when DEPLOY_MODE=ssh or --require-remote
  - MCP servers (Mattermost + Playwright) when --require-mcp
Exits 0 if required items pass, 1 otherwise.
EOF
      exit 0
      ;;
  esac
done

json_entries=()
missing_required=()
missing_optional=()
warnings=()
required_total=0
required_ok=0

push_entry() {
  local name="$1" status="$2" detail="$3" required="$4"
  if [[ "${required}" == "true" ]]; then
    required_total=$(( required_total + 1 ))
    if [[ "${status}" == "ok" ]]; then
      required_ok=$(( required_ok + 1 ))
    fi
  fi
  if [[ "${out_mode}" == "json" ]]; then
    local detail_escaped
    detail_escaped="$(printf '%s' "${detail}" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))')"
    json_entries+=("{\"name\":\"${name}\",\"status\":\"${status}\",\"required\":${required},\"detail\":${detail_escaped}}")
  else
    local marker
    case "${status}" in
      ok) marker="[ok]" ;;
      missing) marker="[MISSING]" ;;
      warn) marker="[warn]" ;;
      *) marker="[${status}]" ;;
    esac
    printf '%-10s %-34s %s\n' "${marker}" "${name}" "${detail}"
  fi
  case "${status}" in
    missing)
      if [[ "${required}" == "true" ]]; then
        missing_required+=("${name}")
      else
        missing_optional+=("${name}")
      fi
      ;;
    warn)
      warnings+=("${name}: ${detail}")
      ;;
  esac
}

check_cmd() {
  local name="$1" required="$2"
  if command -v "${name}" >/dev/null 2>&1; then
    push_entry "cmd:${name}" ok "$(command -v "${name}")" "${required}"
  else
    push_entry "cmd:${name}" missing "not found in PATH" "${required}"
  fi
}

check_py_module() {
  local module="$1" required="$2"
  if python3 -c "import importlib,sys; importlib.import_module('${module}'); sys.exit(0)" >/dev/null 2>&1; then
    push_entry "py:${module}" ok "import ok" "${required}"
  else
    push_entry "py:${module}" missing "python3 -c 'import ${module}' failed" "${required}"
  fi
}

check_env_present() {
  local var="$1" required="$2" hint="${3:-}"
  local value="${!var:-}"
  if [[ -n "${value}" ]]; then
    push_entry "env:${var}" ok "set" "${required}"
  else
    push_entry "env:${var}" missing "unset${hint:+ -- ${hint}}" "${required}"
  fi
}

check_file() {
  local var="$1" required="$2"
  local value="${!var:-}"
  if [[ -z "${value}" ]]; then
    push_entry "file:${var}" missing "unset" "${required}"
  elif [[ -f "${value}" ]]; then
    push_entry "file:${var}" ok "${value}" "${required}"
  else
    push_entry "file:${var}" missing "not found: ${value}" "${required}"
  fi
}

if [[ -f "${config_path}" ]]; then
  # shellcheck disable=SC1090
  set -a; . "${config_path}"; set +a
fi

if [[ "${out_mode}" == "text" ]]; then
  printf '== Phase 2 Doctor ==\n'
  printf 'config: %s\n' "${config_path}"
  printf '\n-- System commands --\n'
fi

check_cmd python3 true
check_cmd jq true
check_cmd curl true
check_cmd ssh false
check_cmd scp false
check_cmd rsync false
check_cmd psql false
check_cmd openssl false

if [[ "${out_mode}" == "text" ]]; then
  printf '\n-- Python modules --\n'
fi
check_py_module requests true
check_py_module json true

if [[ "${out_mode}" == "text" ]]; then
  printf '\n-- Migration tools --\n'
fi
if [[ -n "${MMCTL_BIN:-}" ]]; then
  if [[ -x "${MMCTL_BIN}" ]]; then
    push_entry "cmd:mmctl-bin" ok "${MMCTL_BIN}" false
  else
    push_entry "cmd:mmctl-bin" missing "MMCTL_BIN not executable: ${MMCTL_BIN}" true
  fi
elif command -v mmctl >/dev/null 2>&1; then
  push_entry "cmd:mmctl" ok "$(command -v mmctl)" false
elif [[ -n "${TARGET_HOST:-}" && "${ENABLE_LOCAL_MODE:-0}" == "1" ]]; then
  push_entry "cmd:mmctl" ok "will use SSH-backed wrapper at ${TARGET_HOST}" false
else
  push_entry "cmd:mmctl" missing "install mmctl or set TARGET_HOST + ENABLE_LOCAL_MODE=1" true
fi

if [[ "${out_mode}" == "text" ]]; then
  printf '\n-- Intake + credentials --\n'
fi
check_file HANDOFF_JSON true
check_file IMPORT_ZIP false
check_env_present MATTERMOST_URL true
check_env_present MATTERMOST_ADMIN_USER true
check_env_present MATTERMOST_ADMIN_PASS true
check_env_present MATTERMOST_TEAM_NAME false

if [[ -z "${SMOKE_DATABASE_URL:-${POSTGRES_DSN:-${DATABASE_URL:-${STAGING_DATABASE_URL:-}}}}" ]]; then
  push_entry "env:DATABASE_URL" missing "set SMOKE_DATABASE_URL / POSTGRES_DSN / DATABASE_URL for post-import smoke tests" true
else
  push_entry "env:DATABASE_URL" ok "at least one DB DSN set" true
fi

if [[ "${require_remote}" == "1" || "${DEPLOY_MODE:-plan}" == "ssh" || "${PROVISION_MODE:-plan}" == "ssh" ]]; then
  if [[ "${out_mode}" == "text" ]]; then
    printf '\n-- Remote reachability --\n'
  fi
  if [[ -z "${TARGET_HOST:-}" ]]; then
    push_entry "env:TARGET_HOST" missing "required for ssh deploy/provision mode" true
  elif ! command -v ssh >/dev/null 2>&1; then
    push_entry "cmd:ssh" missing "ssh not on PATH; cannot reach TARGET_HOST" true
  else
    if ssh -o BatchMode=yes -o ConnectTimeout=8 "${TARGET_SSH_USER:-deploy}@${TARGET_HOST}" "echo ok" >/dev/null 2>&1; then
      push_entry "ssh:target" ok "${TARGET_SSH_USER:-deploy}@${TARGET_HOST} reachable" true
    else
      push_entry "ssh:target" missing "cannot ssh to ${TARGET_SSH_USER:-deploy}@${TARGET_HOST} non-interactively" true
    fi
  fi
fi

if [[ "${require_mcp}" == "1" ]]; then
  if [[ "${out_mode}" == "text" ]]; then
    printf '\n-- MCP servers --\n'
  fi
  mcp_any_cli=0
  if command -v claude >/dev/null 2>&1; then
    mcp_any_cli=1
    for server in mattermost playwright; do
      if claude mcp get "${server}" >/dev/null 2>&1; then
        push_entry "mcp:claude:${server}" ok "configured in Claude Code" false
      else
        push_entry "mcp:claude:${server}" missing "run scripts/install-mcp-servers.sh to add" false
      fi
    done
  fi
  if command -v codex >/dev/null 2>&1; then
    mcp_any_cli=1
    for server in mattermost playwright; do
      if codex mcp get "${server}" >/dev/null 2>&1; then
        push_entry "mcp:codex:${server}" ok "configured in Codex" false
      else
        push_entry "mcp:codex:${server}" missing "run scripts/install-mcp-servers.sh to add" false
      fi
    done
  fi
  if (( ! mcp_any_cli )); then
    push_entry "cmd:claude-or-codex" warn "Neither claude nor codex CLI on PATH; MCP checks skipped" false
  fi
fi

health_percent=0
if (( required_total > 0 )); then
  health_percent=$(( (required_ok * 100) / required_total ))
fi

if [[ "${out_mode}" == "json" ]]; then
  printf '{"summary":{"required_missing":%s,"optional_missing":%s,"warnings":%s,"required_total":%s,"required_ok":%s,"health_percent":%s},"entries":[' \
    "$(printf '%s' "${#missing_required[@]}")" \
    "$(printf '%s' "${#missing_optional[@]}")" \
    "$(printf '%s' "${#warnings[@]}")" \
    "${required_total}" \
    "${required_ok}" \
    "${health_percent}"
  first=1
  for entry in "${json_entries[@]}"; do
    if (( first )); then first=0; else printf ','; fi
    printf '%s' "${entry}"
  done
  printf ']}\n'
else
  printf '\n-- Summary --\n'
  if (( ${#missing_required[@]} )); then
    printf 'required missing (%d): %s\n' "${#missing_required[@]}" "${missing_required[*]}"
  else
    printf 'required: all present\n'
  fi
  if (( ${#missing_optional[@]} )); then
    printf 'optional missing (%d): %s\n' "${#missing_optional[@]}" "${missing_optional[*]}"
  fi
  if (( ${#warnings[@]} )); then
    printf 'warnings (%d):\n' "${#warnings[@]}"
    for warning in "${warnings[@]}"; do
      printf '  - %s\n' "${warning}"
    done
  fi
  printf '\n'
  if (( ${#missing_required[@]} == 0 )); then
    printf '=== Health score: %d/%d required passing (%d%%) — READY ===\n' \
      "${required_ok}" "${required_total}" "${health_percent}"
  else
    printf '=== Health score: %d/%d required passing (%d%%) — BLOCKED ===\n' \
      "${required_ok}" "${required_total}" "${health_percent}"
  fi
  printf 'remediation: ./scripts/bootstrap-tools.sh\n'
fi

if (( ${#missing_required[@]} )); then
  exit 1
fi
exit 0
