#!/usr/bin/env bash
# Phase 2 operator-workstation bootstrap. Detects the host platform and
# installs mmctl + jq + psql + the Python deps operate.sh needs. Idempotent.
# Does NOT provision the remote Mattermost host -- that is what
# `./operate.sh provision` does.
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

Installs missing Phase 2 operator tooling:
  - python3, pip, jq, curl, ssh, rsync, openssl
  - postgresql-client (for psql)
  - mmctl (Go install or release binary)
  - Python packages: requests

Does not touch the remote Mattermost host; use `./operate.sh provision` for
that (which supports plan / local / ssh modes).
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
    if grep -qi microsoft /proc/version 2>/dev/null; then platform="wsl"
    elif [[ -f /etc/debian_version ]]; then platform="ubuntu"
    else platform="linux"; fi ;;
  MINGW*|MSYS*|CYGWIN*) platform="windows" ;;
  *) platform="unknown" ;;
esac
log "detected platform: ${platform}"

have() { command -v "$1" >/dev/null 2>&1; }
run_cmd() { if [[ "${mode}" == "install" ]]; then log "exec: $*"; "$@"; else log "plan: $*"; fi; }

if [[ "${platform}" == "windows" ]]; then
  cat <<'EOF'
[bootstrap] Windows detected. In an Admin PowerShell:

  choco install -y python3 jq curl openssh postgresql golang
  python -m pip install --user requests
  # Download mmctl from https://github.com/mattermost/mmctl/releases/latest
  # and extract mmctl.exe to somewhere on PATH.
EOF
  exit 0
fi

case "${platform}" in
  mac)
    if ! have brew; then
      log "installing Homebrew"
      run_cmd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if [[ "${mode}" == "install" ]]; then
        for prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
          if [[ -x "${prefix}/bin/brew" ]]; then
            eval "$("${prefix}/bin/brew" shellenv)"
            break
          fi
        done
      fi
    fi
    pkgs=()
    have python3 || pkgs+=(python3)
    have jq || pkgs+=(jq)
    have curl || pkgs+=(curl)
    have ssh || pkgs+=(openssh)
    have rsync || pkgs+=(rsync)
    have openssl || pkgs+=(openssl)
    have psql || pkgs+=(libpq)
    have go || pkgs+=(go)
    if (( ${#pkgs[@]} )); then run_cmd brew install "${pkgs[@]}"; fi
    if ! have psql; then
      brew_prefix="$(brew --prefix 2>/dev/null || printf '')"
      if [[ -n "${brew_prefix}" && -x "${brew_prefix}/opt/libpq/bin/psql" ]]; then
        warn "psql is installed at ${brew_prefix}/opt/libpq/bin but not on PATH; run: echo 'export PATH=\"${brew_prefix}/opt/libpq/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
      else
        warn "psql not on PATH after brew install libpq; check brew --prefix output and add \$(brew --prefix)/opt/libpq/bin to PATH"
      fi
    fi
    ;;
  ubuntu|wsl|linux)
    pkgs=()
    have python3 || pkgs+=(python3)
    have pip3 || pkgs+=(python3-pip)
    have jq || pkgs+=(jq)
    have curl || pkgs+=(curl)
    have ssh || pkgs+=(openssh-client)
    have rsync || pkgs+=(rsync)
    have openssl || pkgs+=(openssl)
    have psql || pkgs+=(postgresql-client)
    have go || pkgs+=(golang-go)
    if (( ${#pkgs[@]} )); then
      if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        run_cmd apt-get update
        run_cmd apt-get install -y "${pkgs[@]}"
      else
        run_cmd sudo apt-get update
        run_cmd sudo apt-get install -y "${pkgs[@]}"
      fi
    fi
    ;;
esac

pip_pkgs=()
python3 -c "import requests" 2>/dev/null || pip_pkgs+=(requests)
if (( ${#pip_pkgs[@]} )); then
  run_cmd python3 -m pip install --user --break-system-packages "${pip_pkgs[@]}" || \
    run_cmd python3 -m pip install --user "${pip_pkgs[@]}"
fi

if ! have mmctl; then
  if have go; then
    if run_cmd go install github.com/mattermost/mmctl/v6@latest; then
      gobin="${GOBIN:-$(go env GOPATH 2>/dev/null)/bin}"
      case ":${PATH}:" in *":${gobin}:"*) ;; *) warn "add ${gobin} to PATH" ;; esac
    else
      warn "go install mmctl failed; grab a release binary from https://github.com/mattermost/mmctl/releases/latest or set TARGET_HOST + ENABLE_LOCAL_MODE=1 in config.env to use the SSH-backed wrapper"
    fi
  else
    warn "mmctl not installed and go not available; download a release binary from https://github.com/mattermost/mmctl/releases/latest and place it on PATH, or rely on the SSH-backed wrapper by setting TARGET_HOST + ENABLE_LOCAL_MODE=1"
  fi
fi

log "done. run ./scripts/doctor.sh to verify, then ./scripts/install-mcp-servers.sh for MCP wiring"
