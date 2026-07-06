#!/usr/bin/env bash
# Phase 1 MCP server wiring. Installs / registers the MCP servers the
# extraction pipeline benefits from (Slack MCP for live workspace exploration
# and gap-fill, Playwright MCP for admin-UI export automation) inside Claude
# Code AND Codex, if either is present. Idempotent: re-running is safe.
#
# Flags:
#   --include slack|slack-koro|playwright   (repeatable; default: slack+playwright
#                                            plus slack-koro when its credentials
#                                            are set in config.env)
#   --skip-codex
#   --skip-claude
#   --dry-run
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
config_path="${PHASE1_CONFIG:-${skill_dir}/config.env}"
want_slack=1
want_slack_koro=-1   # -1 = auto-enable when SLACK_MCP_TOKEN + SLACK_MCP_COOKIE are set
want_playwright=1
skip_codex=0
skip_claude=0
dry_run=0
selected_explicit=0

include_only() {
  if (( ! selected_explicit )); then
    selected_explicit=1
    want_slack=0
    want_slack_koro=0
    want_playwright=0
  fi
  case "$1" in
    slack) want_slack=1 ;;
    slack-koro) want_slack_koro=1 ;;
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
usage: install-mcp-servers.sh [--include slack|slack-koro|playwright] [--skip-codex] [--skip-claude] [--dry-run]

Adds Slack + Playwright MCP servers to Claude Code / Codex for Phase 1. Prereqs:
  - node + npx   (for @modelcontextprotocol/server-slack and @playwright/mcp)
  - at least one Slack credential:
      SLACK_BOT_TOKEN + SLACK_TEAM_ID  (official Anthropic server)
      SLACK_MCP_TOKEN + SLACK_MCP_COOKIE (korotovsky stealth server)
Credentials are read from config.env / environment. The script never prints
them to stdout. Re-run after rotating tokens to re-register the servers.
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

run() {
  if (( dry_run )); then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

have_claude=0
have_codex=0
have claude && have_claude=1 || warn "claude CLI not in PATH; Claude Code wiring will be skipped"
have codex && have_codex=1 || warn "codex CLI not in PATH; Codex wiring will be skipped"

if ! have npx; then
  warn "npx not found; install Node.js first (e.g. brew install node / apt install nodejs npm / nvm install --lts)"
fi
if ! have node; then
  warn "node not found; MCP servers that run via npx will fail at launch"
fi

claude_add_stdio() {
  local name="$1"; shift
  local env_pairs=()
  while [[ "${1:-}" == "-e" ]]; do env_pairs+=("-e" "$2"); shift 2; done
  # Caller's remaining args are expected to start with "--" followed by the
  # server command; pass through as-is so we don't duplicate the separator.
  if (( have_claude && ! skip_claude )); then
    if claude mcp get "${name}" >/dev/null 2>&1; then
      log "claude mcp: ${name} already registered"
    else
      log "claude mcp add ${name}"
      run claude mcp add ${env_pairs[@]+"${env_pairs[@]}"} "${name}" "$@"
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
      log "codex mcp add ${name}"
      run codex mcp add ${env_pairs[@]+"${env_pairs[@]}"} "${name}" "$@"
    fi
  fi
}

# Resolve auto-enable default for slack-koro: if the operator put the stealth
# credentials in config.env and did not explicitly --include anything else,
# turn the stealth server on alongside the official Slack + Playwright ones.
if (( want_slack_koro == -1 )); then
  if [[ -n "${SLACK_MCP_TOKEN:-}" && -n "${SLACK_MCP_COOKIE:-}" ]]; then
    want_slack_koro=1
  else
    want_slack_koro=0
  fi
fi

if (( want_slack )); then
  if [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_TEAM_ID:-}" ]]; then
    claude_add_stdio slack \
      -e "SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN}" \
      -e "SLACK_TEAM_ID=${SLACK_TEAM_ID}" \
      -- npx -y @modelcontextprotocol/server-slack
    codex_add_stdio slack \
      -e "SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN}" \
      -e "SLACK_TEAM_ID=${SLACK_TEAM_ID}" \
      -- npx -y @modelcontextprotocol/server-slack
  else
    warn "slack MCP skipped: SLACK_BOT_TOKEN + SLACK_TEAM_ID not set in config.env / env"
  fi
fi

if (( want_slack_koro )); then
  if [[ -n "${SLACK_MCP_TOKEN:-}" && -n "${SLACK_MCP_COOKIE:-}" ]]; then
    if ! have slack-mcp-server; then
      warn "slack-mcp-server binary not found; build it from github.com/korotovsky/slack-mcp-server or add to PATH"
    fi
    claude_add_stdio slack-koro \
      -e "SLACK_MCP_TOKEN=${SLACK_MCP_TOKEN}" \
      -e "SLACK_MCP_COOKIE=${SLACK_MCP_COOKIE}" \
      -- slack-mcp-server
    codex_add_stdio slack-koro \
      -e "SLACK_MCP_TOKEN=${SLACK_MCP_TOKEN}" \
      -e "SLACK_MCP_COOKIE=${SLACK_MCP_COOKIE}" \
      -- slack-mcp-server
  else
    warn "slack-koro skipped: SLACK_MCP_TOKEN + SLACK_MCP_COOKIE not set"
  fi
fi

if (( want_playwright )); then
  # Microsoft's official Playwright MCP server; used for admin-export UI drive
  # on the operator workstation where Slack desktop / Slack admin is already
  # logged in on the default browser profile.
  claude_add_stdio playwright -- npx -y @playwright/mcp@latest
  codex_add_stdio playwright -- npx -y @playwright/mcp@latest
fi

log "done. verify with: claude mcp list   (and/or codex mcp list)"
log "diagnostic check: ./scripts/doctor.sh --require-mcp"
