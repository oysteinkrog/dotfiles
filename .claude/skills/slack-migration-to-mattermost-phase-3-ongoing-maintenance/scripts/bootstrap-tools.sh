#!/usr/bin/env bash
# bootstrap-tools.sh — install Phase 3 workstation dependencies.
#
# Detects macOS / Linux / WSL and uses the native package manager.
# Installs: mmctl, rclone, postgresql-client (psql + pg_dump + pg_restore),
# jq, curl, ssh, rsync, Python 3 + requests. `at` is installed on the
# target host by schedule-reboot.sh; not needed on the workstation.
#
# Safe to re-run: every install step checks `command -v` first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '[bootstrap] %s\n' "$*"; }
warn() { printf '[bootstrap] WARN: %s\n' "$*" >&2; }
die() { printf '[bootstrap] FATAL: %s\n' "$*" >&2; exit 1; }

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            elif [[ -f /etc/debian_version ]]; then
                echo "debian"
            elif [[ -f /etc/redhat-release ]]; then
                echo "redhat"
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

PLATFORM="$(detect_platform)"
log "Platform detected: ${PLATFORM}"

need() {
    # Returns 0 if tool is missing (need to install), 1 if present.
    ! command -v "$1" >/dev/null 2>&1
}

ensure_brew() {
    if need brew; then
        log "Homebrew missing; installing"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}

install_macos() {
    ensure_brew

    for pkg in jq curl rsync go python@3.12 rclone libpq; do
        if need "$(echo "${pkg%@*}" | tr '.' '-')"; then
            log "brew install ${pkg}"
            brew install "${pkg}" >/dev/null 2>&1 || warn "brew install ${pkg} failed; continuing"
        fi
    done

    # libpq provides psql but is keg-only; nudge the user.
    if ! command -v psql >/dev/null 2>&1; then
        local libpq_bin
        libpq_bin="$(brew --prefix)/opt/libpq/bin"
        log "psql not on PATH; add this to your shell rc:"
        log "    export PATH=\"${libpq_bin}:\$PATH\""
    fi

    install_mmctl_via_go
}

install_debian() {
    # Works for WSL-Ubuntu too.
    sudo -n apt-get update -q || sudo apt-get update -q
    local pkgs=(jq curl rsync openssh-client postgresql-client python3 python3-pip python3-requests rclone)
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
            log "apt install ${pkg}"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${pkg}" >/dev/null 2>&1 \
                || warn "apt install ${pkg} failed; continuing"
        fi
    done

    # Go for mmctl build
    if need go; then
        log "Installing Go"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q golang-go >/dev/null 2>&1 || true
    fi

    install_mmctl_via_go
}

install_redhat() {
    sudo dnf install -y -q jq curl rsync openssh-clients postgresql python3 python3-pip python3-requests rclone golang \
        >/dev/null 2>&1 || warn "dnf install failed; continuing"
    install_mmctl_via_go
}

install_mmctl_via_go() {
    if command -v mmctl >/dev/null 2>&1; then
        log "mmctl already installed at $(command -v mmctl)"
        return
    fi
    if ! command -v go >/dev/null 2>&1; then
        warn "Go is not installed; cannot build mmctl. Install Go manually and re-run."
        return
    fi

    log "Building mmctl via 'go install'"
    GOPATH="$(go env GOPATH 2>/dev/null || echo "${HOME}/go")"
    GOBIN="${GOPATH}/bin"
    mkdir -p "${GOBIN}"
    if go install github.com/mattermost/mmctl/v6@latest 2>/dev/null \
       || go install github.com/mattermost/mmctl@latest 2>/dev/null; then
        log "mmctl installed to ${GOBIN}/mmctl"
        case ":${PATH}:" in
            *":${GOBIN}:"*) ;;
            *) log "Add ${GOBIN} to your PATH (e.g. in ~/.zshrc or ~/.bashrc)" ;;
        esac
    else
        warn "go install mmctl failed; install a release binary manually from https://github.com/mattermost/mmctl/releases"
    fi
}

install_python_deps() {
    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 missing; skipping Python deps"
        return
    fi
    log "Ensuring Python 'requests' is available"
    if ! python3 -c 'import requests' 2>/dev/null; then
        pip3 install --user requests >/dev/null 2>&1 \
            || python3 -m pip install --user requests >/dev/null 2>&1 \
            || warn "pip install requests failed"
    fi
}

case "${PLATFORM}" in
    macos) install_macos ;;
    debian|wsl) install_debian ;;
    redhat) install_redhat ;;
    *)
        warn "Unknown platform; please install manually: jq, curl, rsync, ssh, psql, pg_dump, pg_restore, mmctl, rclone, python3, python3-requests"
        ;;
esac

install_python_deps

log ""
log "Bootstrap complete. Verify with:"
log "  ./scripts/doctor.sh"
log "  ./scripts/doctor.sh --require-remote"
