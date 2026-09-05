#!/usr/bin/env bash
# schedule-reboot.sh — if /var/run/reboot-required exists, schedule reboot in the next off-hours window.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a
# shellcheck disable=SC1090
source "${CONFIG_PATH}"
set +a

: "${TARGET_HOST:?TARGET_HOST required}"
: "${TARGET_SSH_USER:=deploy}"
: "${REBOOT_WINDOW_DAY:=Sun}"
: "${REBOOT_WINDOW_HOUR_START:=3}"
: "${REBOOT_WINDOW_HOUR_END:=5}"
: "${REBOOT_WINDOW_MAX_WAIT_HOURS:=168}"

SSH_OPTS="${TARGET_SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=10}"
OUT_JSON="${PHASE3_STAGE_OUT_JSON:-./schedule-reboot-$(date -u +%Y%m%dT%H%M%SZ).json}"

shell_quote() {
    local value="$1"
    local escaped="${value//\'/\'\\\'\'}"
    printf "'%s'" "${escaped}"
}

json_string() {
    local value="${1:-}"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "${value}" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1]))
PY
        return 0
    fi

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '"%s"' "${value}"
}

json_number_or_zero() {
    local value="${1:-0}"
    if [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s' "${value}"
    else
        printf '0'
    fi
}

write_failed_json() {
    local reason="$1" remote_rc="$2" remote_output="${3:-}"
    local reboot_state="${4:-unknown}"
    mkdir -p "$(dirname "${OUT_JSON}")"
    {
        printf '{\n'
        printf '  "generated_at": %s,\n' "$(json_string "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
        printf '  "target_host": %s,\n' "$(json_string "${TARGET_HOST}")"
        printf '  "reboot_needed": %s,\n' "$(json_string "${reboot_state}")"
        printf '  "status": "failed",\n'
        printf '  "reason": %s,\n' "$(json_string "${reason}")"
        printf '  "remote_exit_code": %d,\n' "${remote_rc}"
        printf '  "remote_output": %s\n' "$(json_string "${remote_output}")"
        printf '}\n'
    } > "${OUT_JSON}"
}

case "${REBOOT_WINDOW_DAY}" in
    Sun|Mon|Tue|Wed|Thu|Fri|Sat) ;;
    *) echo "ERROR: REBOOT_WINDOW_DAY must be one of Sun Mon Tue Wed Thu Fri Sat" >&2; exit 2 ;;
esac
for value_name in REBOOT_WINDOW_HOUR_START REBOOT_WINDOW_HOUR_END REBOOT_WINDOW_MAX_WAIT_HOURS; do
    value="${!value_name}"
    if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: ${value_name} must be an integer" >&2
        exit 2
    fi
done
if (( REBOOT_WINDOW_HOUR_START > 23 || REBOOT_WINDOW_HOUR_END > 24 || REBOOT_WINDOW_HOUR_START >= REBOOT_WINDOW_HOUR_END )); then
    echo "ERROR: reboot window hours must satisfy 0 <= start < end <= 24" >&2
    exit 2
fi

# Check reboot-required on target
reboot_check_rc=0
# shellcheck disable=SC2086
reboot_needed=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" \
    "test -f /var/run/reboot-required && echo yes || echo no" 2>&1) || reboot_check_rc=$?
if [[ "${reboot_check_rc}" -ne 0 ]]; then
    printf '%s\n' "${reboot_needed}" >&2
    write_failed_json "remote reboot-required check failed" "${reboot_check_rc}" "${reboot_needed}"
    echo "JSON: ${OUT_JSON}"
    exit "${reboot_check_rc}"
fi
reboot_needed=$(printf '%s\n' "${reboot_needed}" | tail -1)
case "${reboot_needed}" in
    yes|no) ;;
    *)
        write_failed_json "remote reboot-required check returned an unexpected value" 1 "${reboot_needed}"
        echo "JSON: ${OUT_JSON}"
        exit 1
        ;;
esac

if [[ "${reboot_needed}" != "yes" ]]; then
    echo "No reboot required on ${TARGET_HOST}"
    mkdir -p "$(dirname "${OUT_JSON}")"
    printf '{"reboot_needed": "no", "status": "skipped"}\n' > "${OUT_JSON}"
    exit 0
fi

# Compute next off-hours window in UTC using Python for date math (portable).
next_window=$(
REBOOT_WINDOW_DAY="${REBOOT_WINDOW_DAY}" REBOOT_WINDOW_HOUR_START="${REBOOT_WINDOW_HOUR_START}" python3 - <<'PY'
from datetime import datetime, timedelta, timezone
import os
day_map = {"Sun":6, "Mon":0, "Tue":1, "Wed":2, "Thu":3, "Fri":4, "Sat":5}
target_dow = day_map[os.environ["REBOOT_WINDOW_DAY"]]
start_h = int(os.environ["REBOOT_WINDOW_HOUR_START"])
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
        printf '  "next_window": %s,\n' "$(json_string "${next_ts}")"
        printf '  "wait_hours": %s,\n' "$(json_number_or_zero "${wait_hours}")"
        printf '  "status": "blocked_max_wait_exceeded"\n'
        printf '}\n'
    } > "${OUT_JSON}"
    exit 2
fi

# Schedule reboot at next_ts via `at`
# Format for at: "HH:MM YYYY-MM-DD"
at_time=$(
NEXT_TS="${next_ts}" python3 - <<'PY'
import datetime
import os
ts = os.environ["NEXT_TS"].rstrip("Z")
d = datetime.datetime.fromisoformat(ts)
print(d.strftime("%H:%M %Y-%m-%d"))
PY
)

at_time_q=$(shell_quote "${at_time}")
remote_env="AT_TIME=${at_time_q} bash -s"
schedule_rc=0
# shellcheck disable=SC2086,SC2029
schedule_out=$(ssh ${SSH_OPTS} "${TARGET_SSH_USER}@${TARGET_HOST}" "${remote_env}" <<'REMOTE' 2>&1
set -euo pipefail
if ! command -v at >/dev/null 2>&1; then
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -q at
  sudo -n systemctl enable --now atd
fi
# Queue the reboot as root so the at-job inherits the privileges needed to run
# shutdown. Running \`at\` as the deploy user would queue an unprivileged job
# that fails silently at the scheduled time.
printf '%s\n' "/sbin/shutdown -r +1 'Phase 3 scheduled reboot'" | sudo -n at "$AT_TIME"
REMOTE
) || schedule_rc=$?
printf '%s\n' "${schedule_out}"
if [[ "${schedule_rc}" -ne 0 ]]; then
    write_failed_json "remote reboot scheduling command failed" "${schedule_rc}" "${schedule_out}" "yes"
    echo "JSON: ${OUT_JSON}"
    exit "${schedule_rc}"
fi

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
    printf '  "next_window": %s,\n' "$(json_string "${next_ts}")"
    printf '  "wait_hours": %s,\n' "$(json_number_or_zero "${wait_hours}")"
    printf '  "at_time_utc": %s,\n' "$(json_string "${at_time}")"
    printf '  "status": "scheduled"\n'
    printf '}\n'
} > "${OUT_JSON}"

echo "Scheduled; history appended to ${history_path}"
echo "JSON: ${OUT_JSON}"
