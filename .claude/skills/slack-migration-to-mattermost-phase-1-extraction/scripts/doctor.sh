#!/usr/bin/env bash
# Phase 1 environment doctor. Reports missing tools, credentials, and disk
# space without attempting to install anything. Prints a machine-readable JSON
# summary when --json is passed. Pair with scripts/bootstrap-tools.sh for the
# remediation path.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
config_path="${PHASE1_CONFIG:-${skill_dir}/config.env}"
out_mode="text"
require_mcp="0"

for arg in "$@"; do
  case "${arg}" in
    --json) out_mode="json" ;;
    --require-mcp) require_mcp="1" ;;
    -h|--help)
      cat <<'EOF'
usage: doctor.sh [--json] [--require-mcp]

Checks Phase 1 prerequisites:
  - system commands (python3, jq, zip, unzip, curl, sha256sum, rsync)
  - migration tools (slackdump, slack-advanced-exporter, mmetl, mmctl)
  - Python modules used by scripts (requests, bs4, imaplib)
  - credentials presence (SLACK_TOKEN / SLACK_EXPORT_ZIP / SLACK_COOKIE)
  - disk space on $PHASE1_WORKSPACE_ROOT (warns if less than 3x expected)
  - MCP server reachability when --require-mcp is set
Exits 0 if required items are present, 1 if any required item is missing.
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
    local detail
    detail="$(command -v "${name}")"
    push_entry "cmd:${name}" ok "${detail}" "${required}"
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

check_file_exists() {
  local var="$1" required="$2" hint="${3:-}"
  local value="${!var:-}"
  if [[ -z "${value}" ]]; then
    push_entry "file:${var}" missing "unset${hint:+ -- ${hint}}" "${required}"
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
  printf '== Phase 1 Doctor ==\n'
  printf 'config: %s\n' "${config_path}"
  printf 'workspace root: %s\n' "${PHASE1_WORKSPACE_ROOT:-${skill_dir}/workdir}"
  printf '\n-- System commands --\n'
fi

check_cmd python3 true
check_cmd jq true
check_cmd zip true
check_cmd unzip true
check_cmd curl true
check_cmd sha256sum true
check_cmd rsync false
check_cmd git false

if [[ "${out_mode}" == "text" ]]; then
  printf '\n-- Python modules --\n'
fi
check_py_module requests true
check_py_module bs4 true
check_py_module json true

if [[ "${out_mode}" == "text" ]]; then
  printf '\n-- Migration tools --\n'
fi
check_cmd "${SLACKDUMP_BIN:-slackdump}" false
check_cmd "${SLACK_ADVANCED_EXPORTER_BIN:-slack-advanced-exporter}" false
check_cmd "${MMETL_BIN:-mmetl}" false
check_cmd mmctl false

if [[ "${out_mode}" == "text" ]]; then
  printf '\n-- Credentials / inputs --\n'
fi
if [[ -n "${SLACK_EXPORT_ZIP:-}" ]]; then
  check_file_exists SLACK_EXPORT_ZIP true "expected readable Slack export ZIP"
else
  push_entry "file:SLACK_EXPORT_ZIP" warn "empty; skip if using slackdump as primary extractor" "false"
  if [[ -z "${SLACK_TOKEN:-}" && -z "${SLACK_COOKIE:-}" ]]; then
    push_entry "env:SLACK_TOKEN_OR_COOKIE" warn "neither SLACK_TOKEN nor SLACK_COOKIE set; enrichment and slackdump will skip" "false"
  fi
fi
check_env_present WORKSPACE_NAME true
check_env_present MATTERMOST_TEAM_NAME false "required only for transform"
check_env_present SLACK_PLAN_TIER false "used for handoff routing"

if [[ "${out_mode}" == "text" ]]; then
  printf '\n-- Disk space --\n'
fi
workspace_root="${PHASE1_WORKSPACE_ROOT:-${skill_dir}/workdir}"
if [[ "${workspace_root}" != /* ]]; then
  workspace_root="${skill_dir}/${workspace_root}"
fi
mkdir -p "${workspace_root}" 2>/dev/null || true
if df_root="$(df -P "${workspace_root}" 2>/dev/null | awk 'NR==2 {print $4, $6}')"; then
  read -r avail_kb mount_point <<<"${df_root}"
  avail_gb=$(( avail_kb / 1024 / 1024 ))
  if (( avail_gb < 20 )); then
    push_entry "disk:workspace" warn "only ${avail_gb} GiB free on ${mount_point}; plan for 3x export size" "false"
  else
    push_entry "disk:workspace" ok "${avail_gb} GiB free on ${mount_point}" "false"
  fi
else
  push_entry "disk:workspace" warn "could not read df on ${workspace_root}" "false"
fi

if [[ "${require_mcp}" == "1" ]]; then
  if [[ "${out_mode}" == "text" ]]; then
    printf '\n-- MCP servers --\n'
  fi
  mcp_any_cli=0
  if command -v claude >/dev/null 2>&1; then
    mcp_any_cli=1
    for server in slack slack-koro playwright; do
      if claude mcp get "${server}" >/dev/null 2>&1; then
        push_entry "mcp:claude:${server}" ok "configured in Claude Code" false
      else
        push_entry "mcp:claude:${server}" missing "run scripts/install-mcp-servers.sh to add" false
      fi
    done
  fi
  if command -v codex >/dev/null 2>&1; then
    mcp_any_cli=1
    for server in slack slack-koro playwright; do
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
