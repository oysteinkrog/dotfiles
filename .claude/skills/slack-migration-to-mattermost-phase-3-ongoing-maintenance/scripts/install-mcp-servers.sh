#!/usr/bin/env bash
# install-mcp-servers.sh — register MCP servers that Phase 3 benefits from.
#
# Registers:
#   - Mattermost MCP (community): lets the agent drive `mmctl`-equivalent admin
#     ops via MCP instead of shelling out. Useful for user lookups, PAT
#     management, plugin state, channel / team admin.
#
# Detects Claude Code CLI, Codex CLI, and (if present) writes to both. Uses
# `claude mcp add` / `codex mcp add` if available; falls back to editing
# ~/.claude/config.json / ~/.codex/config.json directly.
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

set -a; source "${CONFIG_PATH}"; set +a

: "${MATTERMOST_URL:?MATTERMOST_URL required in config.env}"
: "${MATTERMOST_ADMIN_TOKEN:?MATTERMOST_ADMIN_TOKEN required in config.env}"

MCP_NAME="mattermost-phase3"

register_claude_mcp() {
    if ! command -v claude >/dev/null 2>&1; then
        warn "claude CLI not found; skipping Claude Code MCP registration"
        return 0
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
        "npx -y mattermost-mcp-server" \
        --scope user 2>/dev/null
    then
        log "Registered via 'claude mcp add' (short form)"
        return 0
    fi

    warn "'claude mcp add' refused both forms; fall back to manual registration"
    log "  Paste this into ~/.claude/config.json under \"mcpServers\":"
    cat <<EOF
  "${MCP_NAME}": {
    "command": "npx",
    "args": ["-y", "mattermost-mcp-server"],
    "env": {
      "MATTERMOST_URL": "${MATTERMOST_URL}",
      "MATTERMOST_TOKEN": "${MATTERMOST_ADMIN_TOKEN}"
    }
  }
EOF
}

register_codex_mcp() {
    if ! command -v codex >/dev/null 2>&1; then
        warn "codex CLI not found; skipping Codex MCP registration"
        return 0
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

    warn "'codex mcp add' refused; fall back to manual registration via ~/.codex/config.json"
}

register_claude_mcp
register_codex_mcp

log ""
log "Done. Restart your Claude Code / Codex session for the MCP to be picked up."
log "Verify with:"
log "  ./scripts/doctor.sh --require-mcp"
log ""
log "See references/MATTERMOST-MCP-SETUP.md for the Mattermost MCP server's capabilities."
