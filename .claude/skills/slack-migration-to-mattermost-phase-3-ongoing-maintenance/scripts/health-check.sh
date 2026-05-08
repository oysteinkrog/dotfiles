#!/usr/bin/env bash
# health-check.sh — live health probe for the Mattermost stack.
#
# Checks: HTTPS ping, WebSocket upgrade, SMTP reachability (if creds),
# disk % on target, PG connection count, Mattermost error-log rate,
# fail2ban + UFW service status. Emits JSON + human summary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"

set -a; source "${CONFIG_PATH}"; set +a

: "${MATTERMOST_URL:?MATTERMOST_URL required}"
: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${HEALTH_DISK_PCT_RED:=85}"
: "${HEALTH_DISK_PCT_YELLOW:=75}"
: "${HEALTH_PG_CONN_PCT_RED:=80}"
: "${HEALTH_PG_CONN_PCT_YELLOW:=60}"
: "${HEALTH_LOG_ERR_PER_MIN_RED:=10}"
: "${HEALTH_LOG_ERR_PER_MIN_YELLOW:=3}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./health-$(date -u +%Y%m%dT%H%M%SZ).json}"

checks=()
add_check() {
    # $1=name, $2=status (ok|yellow|red|skip), $3=value, $4=detail
    checks+=("$1|$2|$3|$4")
}

# --- HTTPS ping ----------------------------------------------------------

ping_code=$(curl -fsS --max-time 10 -o /dev/null -w '%{http_code}' \
    "${MATTERMOST_URL}/api/v4/system/ping" || echo "000")
if [[ "${ping_code}" == "200" ]]; then
    add_check "mattermost_ping" "ok" "200" "/api/v4/system/ping"
else
    add_check "mattermost_ping" "red" "${ping_code}" "/api/v4/system/ping returned ${ping_code}"
fi

# --- WebSocket upgrade --------------------------------------------------

ws_code=$(curl -fsS --max-time 10 -o /dev/null -w '%{http_code}' \
    -H "Connection: Upgrade" \
    -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
    -H "Sec-WebSocket-Version: 13" \
    "${MATTERMOST_URL}/api/v4/websocket" 2>/dev/null || echo "000")
if [[ "${ws_code}" == "101" ]]; then
    add_check "websocket_upgrade" "ok" "101" "WebSocket upgrade accepted"
elif [[ "${ws_code}" == "401" ]]; then
    add_check "websocket_upgrade" "ok" "401" "WebSocket endpoint reachable (auth required, expected)"
else
    add_check "websocket_upgrade" "red" "${ws_code}" "WebSocket upgrade failed"
fi

# --- SMTP reachability (best-effort) -----------------------------------

if [[ -n "${SMTP_SERVER:-}" && -n "${SMTP_PORT:-}" ]]; then
    if timeout 8 bash -c "exec 3<>/dev/tcp/${SMTP_SERVER}/${SMTP_PORT}" 2>/dev/null; then
        add_check "smtp_tcp" "ok" "${SMTP_SERVER}:${SMTP_PORT}" "TCP open"
        exec 3>&- 2>/dev/null || true
    else
        add_check "smtp_tcp" "red" "${SMTP_SERVER}:${SMTP_PORT}" "TCP closed or blocked"
    fi
else
    add_check "smtp_tcp" "skip" "" "SMTP_SERVER/SMTP_PORT not set"
fi

# --- SSH-side checks in one round trip ----------------------------------

# shellcheck disable=SC2086
remote_out=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" bash <<'REMOTE' 2>/dev/null || true
set -u
# Disk % on root and /opt/mattermost
root_pct=$(df -P / | awk 'NR==2 {sub("%","",$5); print $5}')
mm_pct=$(df -P /opt/mattermost 2>/dev/null | awk 'NR==2 {sub("%","",$5); print $5}')
# PG connection count % of max
pg_usage=$(sudo -n -u postgres psql -tAc "SELECT round(100.0 * count(*) / (SELECT setting::int FROM pg_settings WHERE name='max_connections'),1) FROM pg_stat_activity" 2>/dev/null || echo "")
# Error lines in last 5 min. journalctl filters by log-write time so the window
# is real, not the whole file. Fallback: -mmin returns files modified in the
# last 5 min but then grep sees the whole file, which massively over-counts.
if command -v journalctl >/dev/null 2>&1; then
  err_count=$(sudo -n journalctl -u mattermost --since '5 minutes ago' --no-pager 2>/dev/null \
              | grep -cE '"level":"error"|level=error' || echo "0")
else
  err_count=$(sudo -n find /opt/mattermost/logs/mattermost.log -mmin -5 2>/dev/null | head -1 | xargs -r sudo -n grep -c 'level=error' 2>/dev/null || echo "0")
fi
# Systemd status
fail2ban_active=$(systemctl is-active fail2ban 2>/dev/null || echo "unknown")
ufw_active=$(systemctl is-active ufw 2>/dev/null || echo "unknown")
mm_active=$(systemctl is-active mattermost 2>/dev/null || echo "unknown")
nginx_active=$(systemctl is-active nginx 2>/dev/null || echo "unknown")
printf 'root_pct=%s\nmm_pct=%s\npg_usage=%s\nerr_count=%s\nfail2ban=%s\nufw=%s\nmm=%s\nnginx=%s\n' \
  "$root_pct" "$mm_pct" "$pg_usage" "$err_count" "$fail2ban_active" "$ufw_active" "$mm_active" "$nginx_active"
REMOTE
)

parse_field() {
    echo "${remote_out}" | awk -F= -v k="$1" '$1==k {print $2}'
}

root_pct=$(parse_field root_pct)
mm_pct=$(parse_field mm_pct)
pg_usage=$(parse_field pg_usage)
err_count=$(parse_field err_count)
fail2ban=$(parse_field fail2ban)
ufw=$(parse_field ufw)
mm=$(parse_field mm)
nginx=$(parse_field nginx)

classify_pct() {
    local name="$1" value="$2" red_t="$3" yel_t="$4" detail="$5"
    if [[ -z "${value}" || "${value}" == "-" ]]; then
        add_check "${name}" "skip" "" "${detail}: unable to read"
        return
    fi
    local status="ok"
    # shellcheck disable=SC2086
    (( $(printf '%.0f' "${value}") >= red_t )) && status="red"
    # shellcheck disable=SC2086
    (( $(printf '%.0f' "${value}") >= yel_t )) && [[ "${status}" == "ok" ]] && status="yellow"
    add_check "${name}" "${status}" "${value}%" "${detail}"
}

classify_pct "disk_root" "${root_pct}" "${HEALTH_DISK_PCT_RED}" "${HEALTH_DISK_PCT_YELLOW}" "/ usage"
[[ -n "${mm_pct}" ]] && classify_pct "disk_mattermost" "${mm_pct}" "${HEALTH_DISK_PCT_RED}" "${HEALTH_DISK_PCT_YELLOW}" "/opt/mattermost usage"
[[ -n "${pg_usage}" ]] && classify_pct "pg_connections" "${pg_usage}" "${HEALTH_PG_CONN_PCT_RED}" "${HEALTH_PG_CONN_PCT_YELLOW}" "connections % of max"

# Error-rate: lines-per-minute approx = err_count / 5
if [[ -n "${err_count}" ]]; then
    err_per_min=$(( err_count / 5 ))
    if (( err_per_min >= HEALTH_LOG_ERR_PER_MIN_RED )); then
        add_check "mattermost_errors" "red" "${err_per_min}/min" "level=error in last 5 min"
    elif (( err_per_min >= HEALTH_LOG_ERR_PER_MIN_YELLOW )); then
        add_check "mattermost_errors" "yellow" "${err_per_min}/min" "level=error in last 5 min"
    else
        add_check "mattermost_errors" "ok" "${err_per_min}/min" "level=error in last 5 min"
    fi
fi

for svc in fail2ban ufw mm nginx; do
    val="${!svc}"
    name="service_${svc}"
    [[ "${svc}" == "mm" ]] && name="service_mattermost"
    if [[ "${val}" == "active" ]]; then
        add_check "${name}" "ok" "active" "systemd"
    elif [[ -z "${val}" || "${val}" == "unknown" ]]; then
        add_check "${name}" "skip" "" "systemd status unreadable"
    else
        add_check "${name}" "red" "${val}" "systemd reports ${val}"
    fi
done

# --- Aggregate -----------------------------------------------------------

red_count=0
yellow_count=0
for c in "${checks[@]}"; do
    IFS='|' read -r _ status _ _ <<< "${c}"
    [[ "${status}" == "red" ]] && red_count=$((red_count + 1))
    [[ "${status}" == "yellow" ]] && yellow_count=$((yellow_count + 1))
done

overall="ok"
(( yellow_count > 0 )) && overall="yellow"
(( red_count > 0 )) && overall="red"

# --- Output --------------------------------------------------------------

mkdir -p "$(dirname "${OUT_JSON}")"
{
    printf '{\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "mattermost_url": "%s",\n' "${MATTERMOST_URL}"
    printf '  "target_host": "%s",\n' "${TARGET_HOST}"
    printf '  "overall": "%s",\n' "${overall}"
    printf '  "red_count": %d,\n' "${red_count}"
    printf '  "yellow_count": %d,\n' "${yellow_count}"
    printf '  "checks": [\n'
    first=1
    for c in "${checks[@]}"; do
        IFS='|' read -r name status value detail <<< "${c}"
        [[ "${first}" == "1" ]] || printf ',\n'
        first=0
        printf '    {"name": "%s", "status": "%s", "value": "%s", "detail": "%s"}' \
            "${name}" "${status}" "${value//\"/\\\"}" "${detail//\"/\\\"}"
    done
    printf '\n  ]\n}\n'
} > "${OUT_JSON}"

echo
echo "=== Mattermost health ==="
printf '%-25s %-8s %-10s %s\n' "CHECK" "STATUS" "VALUE" "DETAIL"
for c in "${checks[@]}"; do
    IFS='|' read -r name status value detail <<< "${c}"
    printf '%-25s %-8s %-10s %s\n' "${name}" "${status}" "${value}" "${detail}"
done
echo
echo "Overall: ${overall} (${red_count} red, ${yellow_count} yellow)"
echo "JSON: ${OUT_JSON}"

# Optional webhook alert on red
if [[ "${overall}" == "red" && -n "${ALERT_WEBHOOK_URL:-}" ]]; then
    curl -fsS -X POST -H 'Content-Type: application/json' \
        -d "$(printf '{"text":"[phase-3] health RED for %s; red_count=%d"}' "${MATTERMOST_URL}" "${red_count}")" \
        "${ALERT_WEBHOOK_URL}" >/dev/null 2>&1 || true
fi

[[ "${overall}" == "red" ]] && exit 1
exit 0
