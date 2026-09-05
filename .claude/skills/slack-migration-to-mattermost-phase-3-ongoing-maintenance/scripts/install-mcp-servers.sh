#!/usr/bin/env bash
# install-mcp-servers.sh — register MCP servers that Phase 3 benefits from.
#
# Registers:
#   - Mattermost MCP (community): lets the agent drive `mmctl`-equivalent admin
#     ops via MCP instead of shelling out. Useful for user lookups, PAT
#     management, plugin state, channel / team admin.
#
# Detects Claude Code CLI and Codex CLI. Uses `claude mcp add` / `codex mcp add`
# when available; if a CLI refuses registration, prints a manual config snippet
# instead of editing config files directly.
#
# Pulls MATTERMOST_URL + MATTERMOST_ADMIN_TOKEN from config.env, so run
# doctor.sh first to confirm those are set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${PHASE3_CONFIG:-${SCRIPT_DIR}/../config.env}"

log() { printf '[install-mcp] %s\n' "$*"; }
warn() { printf '[install-mcp] WARN: %s\n' "$*" >&2; }
die() { printf '[install-mcp] FATAL: %s\n' "$*" >&2; exit 1; }

[[ -f "${CONFIG_PATH}" ]] || die "config.env not found at ${CONFIG_PATH}; copy from config.env.example and fill in values"

set -a
# shellcheck disable=SC1090
source "${CONFIG_PATH}"
set +a

: "${MATTERMOST_URL:?MATTERMOST_URL required in config.env}"
: "${MATTERMOST_ADMIN_TOKEN:?MATTERMOST_ADMIN_TOKEN required in config.env}"

MCP_NAME="mattermost-phase3"

json_string() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    printf '"%s"' "${value}"
}

print_manual_snippet() {
    local target_name="$1"
    local target_config="$2"

    warn "Manual ${target_name} MCP registration required"
    log "  Insert this into ${target_config} under \"mcpServers\":"
    cat <<EOF
  "${MCP_NAME}": {
    "command": "npx",
    "args": ["-y", "mattermost-mcp-server"],
    "env": {
      "MATTERMOST_URL": $(json_string "${MATTERMOST_URL}"),
      "MATTERMOST_TOKEN": $(json_string "<copy MATTERMOST_ADMIN_TOKEN from ${CONFIG_PATH}>")
    }
  }
EOF
}

register_claude_mcp() {
    if ! command -v claude >/dev/null 2>&1; then
        warn "claude CLI not found; skipping Claude Code MCP registration"
        return 1
    fi

    log "Registering MCP '${MCP_NAME}' with Claude Code"
    # Two invocation forms in current Claude Code CLIs; try both.
    if claude mcp add "${MCP_NAME}" \
        --command "npx" \
        --args "-y" "mattermost-mcp-server" \
        --env "MATTERMOST_URL=${MATTERMOST_URL}" \
        --env "MATTERMOST_TOKEN=${MATTERMOST_ADMIN_TOKEN}" 2>/dev/null
    then
        log "Registered via 'claude mcp add' (flag form)"
        return 0
    fi

    if claude mcp add "${MCP_NAME}" \
        --env "MATTERMOST_URL=${MATTERMOST_URL}" \
        --env "MATTERMOST_TOKEN=${MATTERMOST_ADMIN_TOKEN}" \
        --scope user \
        "npx" "-y" "mattermost-mcp-server" 2>/dev/null
    then
        log "Registered via 'claude mcp add' (short form with env)"
        return 0
    fi

    warn "'claude mcp add' refused both forms"
    print_manual_snippet "Claude Code" "${HOME}/.claude/config.json"
    return 1
}

register_codex_mcp() {
    if ! command -v codex >/dev/null 2>&1; then
        warn "codex CLI not found; skipping Codex MCP registration"
        return 1
    fi

    log "Registering MCP '${MCP_NAME}' with Codex"
    if codex mcp add "${MCP_NAME}" \
        --command "npx" \
        --args "-y" "mattermost-mcp-server" \
        --env "MATTERMOST_URL=${MATTERMOST_URL}" \
        --env "MATTERMOST_TOKEN=${MATTERMOST_ADMIN_TOKEN}" 2>/dev/null
    then
        log "Registered via 'codex mcp add'"
        return 0
    fi

    warn "'codex mcp add' refused; fall back to manual registration via ${HOME}/.codex/config.json"
    print_manual_snippet "Codex" "${HOME}/.codex/config.json"
    return 1
}

claude_registered=0
codex_registered=0
if register_claude_mcp; then
    claude_registered=1
fi
if register_codex_mcp; then
    codex_registered=1
fi

if [[ "${claude_registered}" -eq 0 && "${codex_registered}" -eq 0 ]]; then
    die "No MCP registration completed; apply the manual snippet above or install a supported CLI and rerun"
fi

log ""
log "Done. Restart your Claude Code / Codex session for the MCP to be picked up."
log "Verify with:"
log "  ./scripts/doctor.sh --require-mcp"
log ""
log "See references/MATTERMOST-MCP-SETUP.md for the Mattermost MCP server's capabilities."
