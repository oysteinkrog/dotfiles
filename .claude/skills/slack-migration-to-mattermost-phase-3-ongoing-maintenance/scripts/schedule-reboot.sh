#!/usr/bin/env bash
# schedule-reboot.sh — if /var/run/reboot-required exists, schedule reboot in the next off-hours window.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a; source "${CONFIG_PATH}"; set +a

: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${REBOOT_WINDOW_DAY:=Sun}"
: "${REBOOT_WINDOW_HOUR_START:=3}"
: "${REBOOT_WINDOW_HOUR_END:=5}"
: "${REBOOT_WINDOW_MAX_WAIT_HOURS:=168}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./schedule-reboot-$(date -u +%Y%m%dT%H%M%SZ).json}"

# Check reboot-required on target
# shellcheck disable=SC2086
reboot_needed=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "test -f /var/run/reboot-required && echo yes || echo no")

if [[ "${reboot_needed}" != "yes" ]]; then
    echo "No reboot required on ${TARGET_HOST}"
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"reboot_needed": "no", "status": "skipped"}\n' > "${OUT_JSON}"
    exit 0
fi

# Compute next off-hours window in UTC using Python for date math (portable).
next_window=$(python3 - <<PY
from datetime import datetime, timedelta, timezone
day_map = {"Sun":6, "Mon":0, "Tue":1, "Wed":2, "Thu":3, "Fri":4, "Sat":5}
target_dow = day_map["${REBOOT_WINDOW_DAY}"]
start_h = int("${REBOOT_WINDOW_HOUR_START}")
now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
candidate = now.replace(hour=start_h)
# Find next occurrence of target_dow at start_h
days_ahead = (target_dow - candidate.weekday()) % 7
if days_ahead == 0 and candidate <= now:
    days_ahead = 7
candidate = candidate + timedelta(days=days_ahead)
wait_hours = (candidate - now).total_seconds() / 3600.0
# Emit without timezone suffix so downstream fromisoformat() parses cleanly.
print(f"{candidate.strftime('%Y-%m-%dT%H:%M:%S')}Z|{wait_hours:.1f}")
PY
)

next_ts="${next_window%|*}"
wait_hours="${next_window#*|}"

echo "Reboot required; next window is ${next_ts} (${wait_hours}h away)"

# shellcheck disable=SC2086
if (( $(printf '%.0f' "${wait_hours}") > REBOOT_WINDOW_MAX_WAIT_HOURS )); then
    echo "Next window is beyond REBOOT_WINDOW_MAX_WAIT_HOURS=${REBOOT_WINDOW_MAX_WAIT_HOURS}h. Asking for human approval."
    mkdir -p "$(dirname "${OUT_JSON}")"
    {
        printf '{\n'
        printf '  "reboot_needed": "yes",\n'
        printf '  "next_window": "%s",\n' "${next_ts}"
        printf '  "wait_hours": %s,\n' "${wait_hours}"
        printf '  "status": "blocked_max_wait_exceeded"\n'
        printf '}\n'
    } > "${OUT_JSON}"
    exit 2
fi

# Schedule reboot at next_ts via `at`
# Format for at: "HH:MM YYYY-MM-DD"
at_time=$(python3 - <<PY
import datetime
ts = "${next_ts}".rstrip("Z")
d = datetime.datetime.fromisoformat(ts)
print(d.strftime("%H:%M %Y-%m-%d"))
PY
)

# shellcheck disable=SC2086
ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" bash <<REMOTE
set -euo pipefail
if ! command -v at >/dev/null 2>&1; then
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -q at
  sudo -n systemctl enable --now atd
fi
# Queue the reboot as root so the at-job inherits the privileges needed to run
# shutdown. Running \`at\` as the deploy user would queue an unprivileged job
# that fails silently at the scheduled time.
echo "/sbin/shutdown -r +1 'Phase 3 scheduled reboot'" | sudo -n at ${at_time}
REMOTE

# Append to reboot-history.json on the workstation
history_path="${SCRIPT_DIR}/../workdir-phase3/reboot-history.json"
mkdir -p "$(dirname "${history_path}")"
if [[ ! -f "${history_path}" ]]; then
    printf '{"history": []}\n' > "${history_path}"
fi
tmp=$(mktemp)
jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg window "${next_ts}" \
   '.history += [{"scheduled_at": $ts, "reboot_window": $window}]' \
   "${history_path}" > "${tmp}" && mv "${tmp}" "${history_path}"

mkdir -p "$(dirname "${OUT_JSON}")"
{
    printf '{\n'
    printf '  "reboot_needed": "yes",\n'
    printf '  "next_window": "%s",\n' "${next_ts}"
    printf '  "wait_hours": %s,\n' "${wait_hours}"
    printf '  "at_time_utc": "%s",\n' "${at_time}"
    printf '  "status": "scheduled"\n'
    printf '}\n'
} > "${OUT_JSON}"

echo "Scheduled; history appended to ${history_path}"
echo "JSON: ${OUT_JSON}"
