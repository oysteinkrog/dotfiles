#!/usr/bin/env bash
# monitor-health.sh — continuous streaming health probe during an upgrade or incident.
#
# Polls live endpoints every N seconds and streams JSONL to stdout and to a
# file. Ctrl-C to stop; there's no clean exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
    echo "ERROR: config.env not found at ${CONFIG_PATH}" >&2
    exit 2
fi

set -a
# shellcheck disable=SC1090
source "${CONFIG_PATH}"
set +a

: "${MATTERMOST_URL:?MATTERMOST_URL required}"
INTERVAL="${1:-15}"
DURATION="${2:-0}"   # 0 = run until Ctrl-C

if [[ ! "${INTERVAL}" =~ ^[0-9]+$ || "${INTERVAL}" -lt 1 ]]; then
    echo "ERROR: interval must be a positive integer number of seconds" >&2
    exit 2
fi
if [[ ! "${DURATION}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: duration must be a non-negative integer number of seconds" >&2
    exit 2
fi

OUT_DIR="${PHASE3_WORKSPACE_ROOT:-${SCRIPT_DIR}/../workdir-phase3}/reports"
mkdir -p "${OUT_DIR}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="${OUT_DIR}/monitor-health-${TS}.jsonl"

echo "Streaming health every ${INTERVAL}s to ${OUT_FILE}"
echo "(Ctrl-C to stop)"
echo

START="$(date +%s)"

json_string() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json, sys; print(json.dumps(sys.argv[1]), end="")' "$1"
        return
    fi

    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\b'/\\b}
    value=${value//$'\f'/\\f}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '"%s"' "$value"
}

http_status() {
    local code
    if code=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null); then
        case "$code" in
            [0-9][0-9][0-9]) printf '%d' "$((10#$code))" ;;
            *) printf '0' ;;
        esac
    else
        printf '0'
    fi
}

sample() {
    local now_iso http_code ws_code pat_code mm_version
    now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    http_code=$(http_status "${MATTERMOST_URL}/api/v4/system/ping")

    ws_code=$(http_status \
        -H "Connection: Upgrade" \
        -H "Upgrade: websocket" \
        -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
        -H "Sec-WebSocket-Version: 13" \
        "${MATTERMOST_URL}/api/v4/websocket")

    pat_code="0"
    if [[ -n "${MATTERMOST_ADMIN_TOKEN:-}" ]]; then
        pat_code=$(http_status \
            -H "Authorization: Bearer ${MATTERMOST_ADMIN_TOKEN}" \
            "${MATTERMOST_URL}/api/v4/users/me")
    fi

    mm_version=$(curl -fsS --max-time 5 "${MATTERMOST_URL}/api/v4/config/client?format=old" 2>/dev/null \
        | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")

    printf '{"ts":%s,"ping":%s,"ws":%s,"pat":%s,"version":%s}\n' \
        "$(json_string "$now_iso")" "${http_code}" "${ws_code}" "${pat_code}" "$(json_string "$mm_version")"
}

while true; do
    line="$(sample)"
    echo "${line}" | tee -a "${OUT_FILE}"

    if (( DURATION > 0 )); then
        NOW="$(date +%s)"
        elapsed=$((NOW - START))
        if (( elapsed >= DURATION )); then
            break
        fi
        sleep_for="${INTERVAL}"
        remaining=$((DURATION - elapsed))
        if (( remaining < sleep_for )); then
            sleep_for="${remaining}"
        fi
    else
        sleep_for="${INTERVAL}"
    fi

    sleep "${sleep_for}"
done
