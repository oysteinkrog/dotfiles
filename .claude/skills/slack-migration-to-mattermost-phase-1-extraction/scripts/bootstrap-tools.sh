#!/usr/bin/env bash
# Phase 1 operator-workstation bootstrap. Detects the host platform and
# installs the tools that migrate.sh expects. Safe to re-run: skips installs
# when the tool already resolves in PATH. Does not touch MCP servers --
# see install-mcp-servers.sh for that.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"

mode="install"
for arg in "$@"; do
  case "${arg}" in
    --dry-run) mode="dry-run" ;;
    --print-plan) mode="plan" ;;
    -h|--help)
      cat <<'EOF'
usage: bootstrap-tools.sh [--dry-run|--print-plan]

Installs missing Phase 1 tooling on macOS (Homebrew), Ubuntu/Debian (apt),
or WSL/Linux. For Windows PowerShell operators, prints a plan that can be
pasted into an Administrator PowerShell session.

Tools installed if missing:
  python3, pip, jq, zip, unzip, curl, rsync, git, sha256sum,
  slackdump (Go),
  slack-advanced-exporter (Go),
  mmetl (Go),
  mmctl (Go or APT),
  Python packages: requests, beautifulsoup4

Pass --dry-run to print actions without executing.
Pass --print-plan to emit a shell-agnostic checklist (no execution).
EOF
      exit 0
      ;;
  esac
done

log() { printf '[bootstrap] %s\n' "$*"; }
warn() { printf '[bootstrap warn] %s\n' "$*" >&2; }

platform=""
case "$(uname -s 2>/dev/null || printf unknown)" in
  Darwin) platform="mac" ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      platform="wsl"
    elif [[ -f /etc/debian_version ]]; then
      platform="ubuntu"
    else
      platform="linux"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*) platform="windows" ;;
  *) platform="unknown" ;;
esac
log "detected platform: ${platform}"

have() { command -v "$1" >/dev/null 2>&1; }

run_cmd() {
  if [[ "${mode}" == "install" ]]; then
    log "exec: $*"
    "$@"
  else
    log "plan: $*"
  fi
}

if [[ "${platform}" == "windows" ]]; then
  cat <<'EOF'
[bootstrap] Windows / MINGW detected. Paste the following into an Admin PowerShell:

  # Install Chocolatey (if missing), then:
  choco install -y python3 jq zip unzip curl git mkcert
  # slackdump / slack-advanced-exporter / mmetl / mmctl — grab the latest Windows
  # release binaries from GitHub:
  #   https://github.com/rusq/slackdump/releases
  #   https://github.com/grundleborg/slack-advanced-exporter/releases
  #   https://github.com/mattermost/mmetl/releases
  #   https://github.com/mattermost/mmctl/releases
  # Extract each into a folder on PATH (e.g. C:\Tools\slack-migration).
  python -m pip install --user requests beautifulsoup4

EOF
  exit 0
fi

case "${platform}" in
  mac)
    if ! have brew; then
      log "installing Homebrew"
      run_cmd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      # The installer writes to PATH config files but not the parent shell.
      # Source shellenv so subsequent `brew install` and `have <tool>` checks
      # in this script see Homebrew without requiring a fresh shell.
      if [[ "${mode}" == "install" ]]; then
        for prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
          if [[ -x "${prefix}/bin/brew" ]]; then
            eval "$("${prefix}/bin/brew" shellenv)"
            break
          fi
        done
      fi
    fi
    sys_pkgs=()
    have python3 || sys_pkgs+=(python3)
    have jq || sys_pkgs+=(jq)
    have zip || sys_pkgs+=(zip)
    have unzip || sys_pkgs+=(unzip)
    have curl || sys_pkgs+=(curl)
    have rsync || sys_pkgs+=(rsync)
    have git || sys_pkgs+=(git)
    have go || sys_pkgs+=(go)
    have sha256sum || sys_pkgs+=(coreutils)
    if (( ${#sys_pkgs[@]} )); then
      run_cmd brew install "${sys_pkgs[@]}"
    fi
    ;;
  ubuntu|wsl|linux)
    apt_pkgs=()
    have python3 || apt_pkgs+=(python3)
    have pip3 || apt_pkgs+=(python3-pip)
    have jq || apt_pkgs+=(jq)
    have zip || apt_pkgs+=(zip)
    have unzip || apt_pkgs+=(unzip)
    have curl || apt_pkgs+=(curl)
    have rsync || apt_pkgs+=(rsync)
    have git || apt_pkgs+=(git)
    have go || apt_pkgs+=(golang-go)
    if (( ${#apt_pkgs[@]} )); then
      if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        run_cmd apt-get update
        run_cmd apt-get install -y "${apt_pkgs[@]}"
      else
        run_cmd sudo apt-get update
        run_cmd sudo apt-get install -y "${apt_pkgs[@]}"
      fi
    fi
    ;;
  *)
    warn "unknown platform; skipping system-package install"
    ;;
esac

pip_pkgs=()
python3 -c "import requests" 2>/dev/null || pip_pkgs+=(requests)
python3 -c "import bs4" 2>/dev/null || pip_pkgs+=(beautifulsoup4)
if (( ${#pip_pkgs[@]} )); then
  if python3 -m pip install --help >/dev/null 2>&1; then
    run_cmd python3 -m pip install --user --break-system-packages "${pip_pkgs[@]}" || \
      run_cmd python3 -m pip install --user "${pip_pkgs[@]}"
  else
    warn "pip not available; install these manually: ${pip_pkgs[*]}"
  fi
fi

install_go_tool() {
  local name="$1" import_path="$2"
  if have "${name}"; then
    log "${name} already present at $(command -v "${name}")"
    return 0
  fi
  if ! have go; then
    warn "go not installed; cannot install ${name}; add manually from release page"
    return 0
  fi
  # Soften set -e so a single tool's install failure (wrong import path, network
  # hiccup) does not abort the whole bootstrap and leave the remaining tools
  # uninstalled. The warn below tells the operator what to do.
  if ! run_cmd go install "${import_path}@latest"; then
    warn "go install ${import_path}@latest failed; download a ${name} release binary and place it on PATH"
    return 0
  fi
  if [[ -z "${GOBIN:-}" ]]; then
    local gopath
    gopath="$(go env GOPATH 2>/dev/null || printf '%s/go' "${HOME}")"
    local gobin="${gopath}/bin"
    case ":${PATH}:" in
      *":${gobin}:"*) ;;
      *) warn "add ${gobin} to PATH so ${name} is discoverable; e.g. export PATH=\"${gobin}:\$PATH\"" ;;
    esac
  fi
}

install_go_tool slackdump github.com/rusq/slackdump/v3/cmd/slackdump
install_go_tool slack-advanced-exporter github.com/grundleborg/slack-advanced-exporter
install_go_tool mmetl github.com/mattermost/mmetl
install_go_tool mmctl github.com/mattermost/mmctl/v6

log "done. run ./scripts/doctor.sh to verify, then ./scripts/install-mcp-servers.sh for Claude Code / Codex MCP wiring"
