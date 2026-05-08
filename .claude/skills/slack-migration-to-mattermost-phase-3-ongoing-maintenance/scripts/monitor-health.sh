#!/usr/bin/env bash
# monitor-health.sh — continuous streaming health probe during an upgrade or incident.
#
# Polls live endpoints every N seconds and streams JSONL to stdout and to a
# file. Ctrl-C to stop; there's no clean exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a; source "${CONFIG_PATH}"; set +a

: "${MATTERMOST_URL:?MATTERMOST_URL required}"
INTERVAL="${1:-15}"
DURATION="${2:-0}"   # 0 = run until Ctrl-C

OUT_DIR="${PHASE3_WORKSPACE_ROOT:-${SCRIPT_DIR}/../workdir-phase3}/reports"
mkdir -p "${OUT_DIR}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="${OUT_DIR}/monitor-health-${TS}.jsonl"

echo "Streaming health every ${INTERVAL}s to ${OUT_FILE}"
echo "(Ctrl-C to stop)"
echo

START="$(date +%s)"

sample() {
    local now_iso http_code ws_code pat_code mm_version
    now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    http_code=$(curl -fsS --max-time 5 -o /dev/null -w '%{http_code}' \
        "${MATTERMOST_URL}/api/v4/system/ping" 2>/dev/null || echo "000")

    ws_code=$(curl -fsS --max-time 5 -o /dev/null -w '%{http_code}' \
        -H "Connection: Upgrade" \
        -H "Upgrade: websocket" \
        -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
        -H "Sec-WebSocket-Version: 13" \
        "${MATTERMOST_URL}/api/v4/websocket" 2>/dev/null || echo "000")

    pat_code="000"
    if [[ -n "${MATTERMOST_ADMIN_TOKEN:-}" ]]; then
        pat_code=$(curl -fsS --max-time 5 -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer ${MATTERMOST_ADMIN_TOKEN}" \
            "${MATTERMOST_URL}/api/v4/users/me" 2>/dev/null || echo "000")
    fi

    mm_version=$(curl -fsS --max-time 5 "${MATTERMOST_URL}/api/v4/config/client?format=old" 2>/dev/null \
        | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")

    printf '{"ts":"%s","ping":%s,"ws":%s,"pat":%s,"version":"%s"}\n' \
        "${now_iso}" "${http_code}" "${ws_code}" "${pat_code}" "${mm_version}"
}

while true; do
    line="$(sample)"
    echo "${line}" | tee -a "${OUT_FILE}"

    if (( DURATION > 0 )); then
        NOW="$(date +%s)"
        if (( NOW - START >= DURATION )); then
            break
        fi
    fi

    sleep "${INTERVAL}"
done
