#!/usr/bin/env bash
# doctor.sh — Phase 3 workstation + target health check.
#
# Layers:
#   default        : tool + config completeness (fast)
#   --require-remote : + SSH reachability, MM ping, PAT check (medium)
#   --require-mcp  : + MCP server registration + connectivity (slow)
#
# Emits a plain-text table + a JSON report + a "health score" banner that
# matches the phase-1 and phase-2 doctor.sh idiom.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_PATH="${PHASE3_CONFIG:-${SKILL_DIR}/config.env}"

REQUIRE_REMOTE=0
REQUIRE_MCP=0
for arg in "$@"; do
    case "${arg}" in
        --require-remote) REQUIRE_REMOTE=1 ;;
        --require-mcp) REQUIRE_MCP=1 ;;
        --help|-h)
            cat <<'USAGE'
Usage: ./doctor.sh [--require-remote] [--require-mcp]

Default:         tool + config completeness only.
--require-remote: additionally verify SSH + MM ping + PAT validity.
--require-mcp:    additionally verify MCP server registration + reachability.

Exit 0 = all required checks passed. Exit 1 = at least one red.
USAGE
            exit 0
            ;;
    esac
done

if [[ -f "${CONFIG_PATH}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${CONFIG_PATH}"
    set +a
    CONFIG_LOADED=1
else
    CONFIG_LOADED=0
fi

required_total=0
required_ok=0
entries=()

push_entry() {
    # $1 = required (1|0), $2 = name, $3 = status (ok|fail|skip|warn), $4 = detail
    local req="$1" name="$2" status="$3" detail="$4"
    if [[ "${req}" == "1" ]]; then
        required_total=$((required_total + 1))
        [[ "${status}" == "ok" ]] && required_ok=$((required_ok + 1))
    fi
    entries+=("${req}|${name}|${status}|${detail}")
}

check_tool() {
    local tool="$1" required="$2"
    if command -v "${tool}" >/dev/null 2>&1; then
        push_entry "${required}" "${tool}" "ok" "$(command -v "${tool}")"
    else
        push_entry "${required}" "${tool}" "fail" "not found on PATH"
    fi
}

check_config_field() {
    local field="$1" required="$2"
    local value="${!field:-}"
    if [[ -n "${value}" ]]; then
        push_entry "${required}" "config:${field}" "ok" "set (${#value} chars)"
    else
        push_entry "${required}" "config:${field}" "fail" "empty"
    fi
}

# === Layer 1: workstation tools ==========================================

check_tool ssh 1
check_tool scp 1
check_tool rsync 1
check_tool jq 1
check_tool curl 1
check_tool psql 1
check_tool pg_dump 1
check_tool mmctl 1
check_tool python3 1
check_tool rclone 0

# === Layer 2: config.env completeness ====================================

if [[ "${CONFIG_LOADED}" == "1" ]]; then
    push_entry 1 "config.env" "ok" "${CONFIG_PATH}"
    check_config_field WORKSPACE_NAME 1
    check_config_field MATTERMOST_URL 1
    check_config_field MATTERMOST_ADMIN_TOKEN 1
    check_config_field TARGET_HOST 1
    check_config_field TARGET_SSH_USER 1
    check_config_field POSTGRES_DSN 1
    check_config_field BACKUP_PATH 1
    check_config_field ROLLBACK_OWNER 0
    check_config_field OFFSITE_REMOTE 0
    check_config_field SCRATCH_DB_URL 0
else
    push_entry 1 "config.env" "fail" "not found at ${CONFIG_PATH}"
fi

# === Layer 3 (--require-remote): live reachability =======================

if [[ "${REQUIRE_REMOTE}" == "1" ]]; then
    if [[ "${CONFIG_LOADED}" == "1" ]] && [[ -n "${MATTERMOST_URL:-}" ]]; then
        if curl -fsS --max-time 10 -o /dev/null "${MATTERMOST_URL}/api/v4/system/ping"; then
            push_entry 1 "mattermost:ping" "ok" "${MATTERMOST_URL}"
        else
            push_entry 1 "mattermost:ping" "fail" "${MATTERMOST_URL}/api/v4/system/ping not reachable"
        fi

        if [[ -n "${MATTERMOST_ADMIN_TOKEN:-}" ]]; then
            http_code=$(curl -fsS --max-time 10 -o /dev/null -w '%{http_code}' \
                -H "Authorization: Bearer ${MATTERMOST_ADMIN_TOKEN}" \
                "${MATTERMOST_URL}/api/v4/users/me" || true)
            if [[ "${http_code}" == "200" ]]; then
                push_entry 1 "mattermost:pat" "ok" "PAT is valid (HTTP 200)"
            else
                push_entry 1 "mattermost:pat" "fail" "PAT check returned HTTP ${http_code:-?}"
            fi
        else
            push_entry 1 "mattermost:pat" "fail" "MATTERMOST_ADMIN_TOKEN empty"
        fi
    else
        push_entry 1 "mattermost:ping" "skip" "MATTERMOST_URL not set"
    fi

    if [[ "${CONFIG_LOADED}" == "1" ]] && [[ -n "${TARGET_HOST:-}" ]]; then
        # shellcheck disable=SC2086
        if ssh ${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10} \
                "${TARGET_SSH_USER:-deploy}@${TARGET_HOST}" 'true' >/dev/null 2>&1; then
            push_entry 1 "ssh:target" "ok" "${TARGET_SSH_USER:-deploy}@${TARGET_HOST}"
        else
            push_entry 1 "ssh:target" "fail" "ssh ${TARGET_SSH_USER:-deploy}@${TARGET_HOST} failed (BatchMode)"
        fi

        # Check the remote host key hasn't changed unexpectedly (a silent MitM risk).
        # We don't fail on first-run (no known_hosts entry); we only fail on a mismatch.
        # shellcheck disable=SC2086
        if ssh-keygen -F "${TARGET_HOST}" >/dev/null 2>&1; then
            if ssh -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10 \
                    "${TARGET_SSH_USER:-deploy}@${TARGET_HOST}" 'true' >/dev/null 2>&1; then
                push_entry 1 "ssh:host_key" "ok" "matches known_hosts"
            else
                push_entry 1 "ssh:host_key" "fail" "host key mismatch; investigate before proceeding"
            fi
        else
            push_entry 0 "ssh:host_key" "warn" "no known_hosts entry; first connection will establish one"
        fi
    else
        push_entry 1 "ssh:target" "skip" "TARGET_HOST not set"
    fi

    if [[ -n "${OFFSITE_REMOTE:-}" ]]; then
        if command -v rclone >/dev/null 2>&1 && \
           rclone --max-depth 1 lsd "${OFFSITE_REMOTE}" >/dev/null 2>&1; then
            push_entry 0 "offsite:reachable" "ok" "${OFFSITE_REMOTE}"
        else
            push_entry 0 "offsite:reachable" "warn" "rclone cannot reach ${OFFSITE_REMOTE} (backups will keep local copies only)"
        fi
    fi

    if [[ -n "${SCRATCH_DB_URL:-}" ]]; then
        # Build a redacted display form: keep scheme://user@host/db, drop the password.
        # ${URL%%@*} keeps the credentials including password — unsafe to log.
        scratch_host="${SCRATCH_DB_URL##*@}"   # host[:port]/dbname
        scratch_scheme="${SCRATCH_DB_URL%%://*}://"
        scratch_userinfo="${SCRATCH_DB_URL#*://}"
        scratch_userinfo="${scratch_userinfo%%@*}"
        scratch_user="${scratch_userinfo%%:*}"
        scratch_redacted="${scratch_scheme}${scratch_user}:***@${scratch_host}"
        if psql "${SCRATCH_DB_URL}" -c 'SELECT 1' >/dev/null 2>&1; then
            push_entry 0 "scratch_db:reachable" "ok" "${scratch_redacted}"
        else
            push_entry 0 "scratch_db:reachable" "warn" "cannot connect to SCRATCH_DB_URL (${scratch_redacted})"
        fi
    fi
fi

# === Layer 4 (--require-mcp): MCP server registration ====================

if [[ "${REQUIRE_MCP}" == "1" ]]; then
    MCP_NAME="mattermost-phase3"
    found_in_claude=0
    found_in_codex=0

    if command -v claude >/dev/null 2>&1; then
        if claude mcp list 2>/dev/null | grep -q "${MCP_NAME}"; then
            found_in_claude=1
            push_entry 1 "mcp:claude_registered" "ok" "'${MCP_NAME}' present in claude CLI"
        else
            push_entry 1 "mcp:claude_registered" "fail" "run scripts/install-mcp-servers.sh"
        fi
    else
        push_entry 0 "mcp:claude_registered" "skip" "claude CLI not installed"
    fi

    if command -v codex >/dev/null 2>&1; then
        if codex mcp list 2>/dev/null | grep -q "${MCP_NAME}"; then
            found_in_codex=1
            push_entry 0 "mcp:codex_registered" "ok" "'${MCP_NAME}' present in codex CLI"
        else
            push_entry 0 "mcp:codex_registered" "warn" "run scripts/install-mcp-servers.sh"
        fi
    else
        push_entry 0 "mcp:codex_registered" "skip" "codex CLI not installed"
    fi

    if (( found_in_claude == 0 && found_in_codex == 0 )); then
        push_entry 1 "mcp:any_agent" "fail" "MCP is not registered with any agent CLI"
    else
        push_entry 1 "mcp:any_agent" "ok" "at least one agent CLI has the MCP registered"
    fi
fi

# === Print table + score + JSON ==========================================

printf '\n%-30s %-8s %s\n' "CHECK" "STATUS" "DETAIL"
printf '%-30s %-8s %s\n' "------------------------------" "--------" "------------------------------------------------------------"
for entry in "${entries[@]}"; do
    IFS='|' read -r req name status detail <<< "${entry}"
    printf '%-30s %-8s %s\n' "${name}" "${status}" "${detail}"
done

if (( required_total > 0 )); then
    pct=$(( required_ok * 100 / required_total ))
else
    pct=0
fi
verdict="BLOCKED"
(( pct == 100 )) && verdict="READY"

echo
echo "=== Health score: ${required_ok}/${required_total} required passing (${pct}%); ${verdict} ==="
echo

OUT_JSON="${PHASE3_STAGE_OUT_JSON:-${SKILL_DIR}/workdir-phase3/reports/doctor-$(date -u +%Y%m%dT%H%M%SZ).json}"
mkdir -p "$(dirname "${OUT_JSON}")"

{
    printf '{\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "require_remote": %s,\n' "${REQUIRE_REMOTE}"
    printf '  "require_mcp": %s,\n' "${REQUIRE_MCP}"
    printf '  "required_total": %d,\n' "${required_total}"
    printf '  "required_ok": %d,\n' "${required_ok}"
    printf '  "health_percent": %d,\n' "${pct}"
    printf '  "verdict": "%s",\n' "${verdict}"
    printf '  "checks": [\n'
    first=1
    for entry in "${entries[@]}"; do
        IFS='|' read -r req name status detail <<< "${entry}"
        [[ "${first}" == "1" ]] || printf ',\n'
        first=0
        printf '    {"name": "%s", "required": %s, "status": "%s", "detail": "%s"}' \
            "${name}" "${req}" "${status}" "${detail//\"/\\\"}"
    done
    printf '\n  ]\n'
    printf '}\n'
} > "${OUT_JSON}"

echo "JSON report: ${OUT_JSON}"

[[ "${verdict}" == "READY" ]] || exit 1
