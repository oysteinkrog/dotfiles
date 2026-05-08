#!/usr/bin/env bash
# Phase 2 MCP wiring. Installs / registers the MCP servers that help drive
# and verify the Mattermost side of the migration:
#   - mattermost   : community mattermost-mcp servers for admin / channel /
#                    post / user operations against a running Mattermost
#   - playwright   : driving the System Console UI when an operation is
#                    easier to click than to express via config.json
# Idempotent; re-run after rotating the admin PAT.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
config_path="${PHASE2_CONFIG:-${skill_dir}/config.env}"
want_mattermost=1
want_playwright=1
skip_codex=0
skip_claude=0
dry_run=0
selected_explicit=0

include_only() {
  if (( ! selected_explicit )); then
    selected_explicit=1
    want_mattermost=0
    want_playwright=0
  fi
  case "$1" in
    mattermost) want_mattermost=1 ;;
    playwright) want_playwright=1 ;;
    *) printf 'unknown --include value: %s\n' "$1" >&2; exit 2 ;;
  esac
}

while (($#)); do
  case "$1" in
    --include) include_only "$2"; shift 2 ;;
    --skip-codex) skip_codex=1; shift ;;
    --skip-claude) skip_claude=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      cat <<'EOF'
usage: install-mcp-servers.sh [--include mattermost|playwright] [--skip-codex] [--skip-claude] [--dry-run]

Wires Mattermost + Playwright MCP servers into Claude Code / Codex.
Mattermost wiring requires:
  MATTERMOST_URL          public URL (or staging URL)
  MATTERMOST_ADMIN_TOKEN  personal access token with system_admin
(Create a PAT via: System Console -> Integrations -> Personal Access Tokens.)
EOF
      exit 0
      ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

log() { printf '[mcp] %s\n' "$*"; }
warn() { printf '[mcp warn] %s\n' "$*" >&2; }

if [[ -f "${config_path}" ]]; then
  # shellcheck disable=SC1090
  set -a; . "${config_path}"; set +a
fi

have() { command -v "$1" >/dev/null 2>&1; }
run() { if (( dry_run )); then printf '[dry-run] %s\n' "$*"; else "$@"; fi; }

have_claude=0; have_codex=0
have claude && have_claude=1 || warn "claude CLI not in PATH; Claude Code wiring skipped"
have codex && have_codex=1 || warn "codex CLI not in PATH; Codex wiring skipped"

have npx || warn "npx not found; install Node.js first"

claude_add_stdio() {
  local name="$1"; shift
  local env_pairs=()
  while [[ "${1:-}" == "-e" ]]; do env_pairs+=("-e" "$2"); shift 2; done
  # Caller's remaining args start with "--" + server command; pass through.
  if (( have_claude && ! skip_claude )); then
    if claude mcp get "${name}" >/dev/null 2>&1; then
      log "claude mcp: ${name} already registered"
    else
      log "claude mcp add ${name}"; run claude mcp add ${env_pairs[@]+"${env_pairs[@]}"} "${name}" "$@"
    fi
  fi
}
codex_add_stdio() {
  local name="$1"; shift
  local env_pairs=()
  while [[ "${1:-}" == "-e" ]]; do env_pairs+=("--env" "$2"); shift 2; done
  if (( have_codex && ! skip_codex )); then
    if codex mcp get "${name}" >/dev/null 2>&1; then
      log "codex mcp: ${name} already registered"
    else
      log "codex mcp add ${name}"; run codex mcp add ${env_pairs[@]+"${env_pairs[@]}"} "${name}" "$@"
    fi
  fi
}

if (( want_mattermost )); then
  if [[ -n "${MATTERMOST_URL:-}" && -n "${MATTERMOST_ADMIN_TOKEN:-}" ]]; then
    # The npm ecosystem has several community Mattermost MCP implementations
    # (mattermost-community/mattermost-mcp-server, @mattermost-mcp/server, and
    # a few uv/Docker-hosted variants). Let the operator pick by setting
    # MATTERMOST_MCP_COMMAND in config.env; otherwise use a best-effort default
    # and let Claude/Codex surface the actual package-resolution error.
    mcp_cmd_str="${MATTERMOST_MCP_COMMAND:-npx -y mattermost-mcp-server}"
    # shellcheck disable=SC2206
    mcp_cmd=(${mcp_cmd_str})
    if [[ -z "${MATTERMOST_MCP_COMMAND:-}" ]]; then
      warn "MATTERMOST_MCP_COMMAND not set; falling back to 'npx -y mattermost-mcp-server'. If that package does not resolve, pick a community server from github.com/mattermost-community and set MATTERMOST_MCP_COMMAND in config.env."
    fi
    claude_add_stdio mattermost \
      -e "MATTERMOST_URL=${MATTERMOST_URL}" \
      -e "MATTERMOST_TOKEN=${MATTERMOST_ADMIN_TOKEN}" \
      -- "${mcp_cmd[@]}"
    codex_add_stdio mattermost \
      -e "MATTERMOST_URL=${MATTERMOST_URL}" \
      -e "MATTERMOST_TOKEN=${MATTERMOST_ADMIN_TOKEN}" \
      -- "${mcp_cmd[@]}"
  else
    warn "mattermost MCP skipped: MATTERMOST_URL + MATTERMOST_ADMIN_TOKEN not set"
  fi
fi

if (( want_playwright )); then
  claude_add_stdio playwright -- npx -y @playwright/mcp@latest
  codex_add_stdio playwright -- npx -y @playwright/mcp@latest
fi

log "done. verify with: claude mcp list   (and/or codex mcp list)"
log "diagnostic check: ./scripts/doctor.sh --require-mcp"
