#!/usr/bin/env bash
# Run commands on, push files to, and pull logs from the lab PC (Windows "Hawk").
# Uses the "labpc" host entry in ~/.ssh/config (key login only).
#
# Usage:
#   lab-deploy.sh run '<powershell>'           run PowerShell on the lab PC
#   lab-deploy.sh push <local-path> [dir]      copy a file or folder (default dir: C:/lab-drop)
#   lab-deploy.sh logs [N]                     pull the N newest Swing Catalyst logs (default 3)

set -euo pipefail

HOST="${LAB_SSH_HOST:-labpc}"
DROP_DIR="C:/lab-drop"
LOG_DIR="C:/ProgramData/Swing Catalyst/logs"

die() { printf 'lab-deploy: %s\n' "$*" >&2; exit 1; }

# Encoding the script as UTF-16LE base64 avoids every layer of cmd.exe quoting.
run_ps() {
    local enc
    enc=$(printf '%s' "\$ProgressPreference='SilentlyContinue'; $1" | iconv -t UTF-16LE | base64 -w0)
    ssh -o BatchMode=yes "$HOST" "powershell -NoProfile -NonInteractive -EncodedCommand $enc"
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
    run)
        [ $# -eq 1 ] || die "usage: run '<powershell>'"
        run_ps "$1"
        ;;
    push)
        [ $# -ge 1 ] || die "usage: push <local-path> [remote-dir]"
        src="$1"; dir="${2:-$DROP_DIR}"
        [ -e "$src" ] || die "no such file: $src"
        run_ps "New-Item -ItemType Directory -Force -Path '$dir' | Out-Null"
        scp -q -r -o BatchMode=yes "$src" "$HOST:/$dir/"
        echo "copied $src to $dir"
        ;;
    logs)
        n="${1:-3}"
        out="$HOME/.lab-logs/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$out"
        run_ps "Get-ChildItem '$LOG_DIR' -File | Sort-Object LastWriteTime -Descending | Select-Object -First $n -ExpandProperty Name" |
            tr -d '\r' | while IFS= read -r name; do
                [ -n "$name" ] || continue
                scp -q -o BatchMode=yes "$HOST:/$LOG_DIR/$name" "$out/"
                echo "$out/$name"
            done
        ;;
    *)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        [ -z "$cmd" ] || exit 1
        ;;
esac
