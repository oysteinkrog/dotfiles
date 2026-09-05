#!/bin/bash
# Scheduled prune for the mcp-agent-mail live SQLite store.
#
# atc_experiences (the internal Adaptive Tool Calibration decision-experience
# ledger, unrelated to mail/file-reservation function) has no upstream
# retention tooling and regrows continuously with swarm activity. This keeps
# only the newest N rows by experience_id and reclaims the space with VACUUM.
#
# Safe-against-server method: stop the pm2 service before touching the live
# file, operate via a stdin heredoc (VACUUM as a `-cmd` argument is a silent
# no-op on this sqlite3 build), then restart and verify with both /health and
# a real JSON-RPC call before declaring success. The EXIT trap guarantees the
# server is restarted even if an earlier step fails, so a bad run never
# leaves the service down.

set -uo pipefail

HOME_DIR="${HOME:-/c/users/oystein}"
DB="$HOME_DIR/.mcp_agent_mail_git_mailbox_repo/storage.sqlite3"
LOG="$HOME_DIR/bin/logs/agent-mail-prune.log"
ECOSYSTEM="$HOME_DIR/.config/pm2/ecosystem.config.js"
KEEP=5000
HEALTH_URL="http://127.0.0.1:8765/health"
RPC_URL="http://127.0.0.1:8765/mcp/"
PM2_NAME="mcp-agent-mail"
PROJECT_KEY="/c/work/desktop/metrics"

export PATH="$HOME_DIR/.nvm/versions/node/v22.14.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

mkdir -p "$(dirname "$LOG")"

RESTARTED=0

log() {
  printf '%s %s\n' "$(date -Iseconds)" "$*" >>"$LOG"
}

pm2_status() {
  pm2 jlist 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(next((p['pm2_env']['status'] for p in d if p['name'] == '${PM2_NAME}'), 'missing'))
except Exception:
    print('unknown')
" 2>/dev/null
}

# `pm2 start <name>` only works if the app entry is still online/stopped in
# pm2's table. A process that crash-looped (errored / "waiting restart", or
# removed entirely) needs `pm2 restart` first, with a full reload from the
# ecosystem file as the last resort if the entry is gone outright. This
# distinction is why the first validation run of this script needed three
# manual `pm2 restart` interventions before the never-left-down guarantee
# actually held end to end.
ensure_running() {
  log "ensure_running: pm2 restart ${PM2_NAME} (current status: $(pm2_status))"
  if pm2 restart "$PM2_NAME" >>"$LOG" 2>&1; then
    pm2 save >>"$LOG" 2>&1
    return 0
  fi
  log "pm2 restart failed, falling back to full reload from ${ECOSYSTEM}"
  pm2 start "$ECOSYSTEM" --only "$PM2_NAME" >>"$LOG" 2>&1
  pm2 save >>"$LOG" 2>&1
}

restart_server() {
  if [[ "$RESTARTED" -eq 1 ]]; then
    return 0
  fi
  RESTARTED=1
  ensure_running
}

on_exit() {
  local ec=$?
  restart_server
  if [[ $ec -ne 0 ]]; then
    log "=== agent-mail-prune run FAILED (exit ${ec}) ==="
  fi
  exit $ec
}
trap on_exit EXIT

log "=== agent-mail-prune run start ==="

if [[ ! -f "$DB" ]]; then
  log "ERROR: db not found at $DB"
  exit 1
fi

BEFORE_SIZE=$(stat -c %s "$DB") || { log "ERROR: cannot stat db"; exit 1; }
log "pre-stop file size=${BEFORE_SIZE} bytes (row count deferred until after stop -- querying atc_experiences while the server holds the WAL trips the WSL1 'locking protocol' error)"

log "stopping pm2 service ${PM2_NAME}"
pm2 stop "$PM2_NAME" >>"$LOG" 2>&1 || { log "ERROR: pm2 stop failed"; exit 1; }
sleep 2

BEFORE_ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM atc_experiences;") || { log "ERROR: cannot query before-count after stop"; exit 1; }
log "before: size=${BEFORE_SIZE} bytes atc_experiences_rows=${BEFORE_ROWS}"

log "running prune + VACUUM + integrity_check via stdin heredoc (keep newest ${KEEP} rows)"
RESULT=$(sqlite3 "$DB" <<SQL
DELETE FROM atc_experiences WHERE experience_id NOT IN (
  SELECT experience_id FROM atc_experiences ORDER BY experience_id DESC LIMIT ${KEEP}
);
VACUUM;
PRAGMA integrity_check;
SQL
)
SQLITE_EC=$?
log "sqlite3 exit=${SQLITE_EC} integrity_check result: ${RESULT}"

if [[ $SQLITE_EC -ne 0 || "$RESULT" != "ok" ]]; then
  log "ERROR: prune/VACUUM/integrity_check did not succeed cleanly"
  exit 1
fi

AFTER_SIZE=$(stat -c %s "$DB")
AFTER_ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM atc_experiences;")
FREELIST=$(sqlite3 "$DB" "PRAGMA freelist_count;")
log "after: size=${AFTER_SIZE} bytes atc_experiences_rows=${AFTER_ROWS} freelist_count=${FREELIST}"

restart_server

HEALTH_OK=0
RESTART_ATTEMPTS=1
MAX_RESTART_ATTEMPTS=4
for i in $(seq 1 90); do
  if curl -sf -m 3 "$HEALTH_URL" 2>/dev/null | grep -q '"status":"ready"'; then
    HEALTH_OK=1
    log "health check OK after ~$((i * 2))s (restart attempts: ${RESTART_ATTEMPTS})"
    break
  fi
  # Every ~30s, if pm2 doesn't show the process online, escalate with another
  # restart rather than sit out the whole timeout waiting on a stuck
  # "waiting restart" state (observed in practice: pm2 can sit there
  # indefinitely without auto-retrying despite a 5s restart_delay).
  if (( i % 15 == 0 )) && [[ "$RESTART_ATTEMPTS" -lt "$MAX_RESTART_ATTEMPTS" ]]; then
    STATUS=$(pm2_status)
    if [[ "$STATUS" != "online" ]]; then
      RESTART_ATTEMPTS=$((RESTART_ATTEMPTS + 1))
      log "not healthy after $((i * 2))s, pm2 status=${STATUS}; escalating with restart attempt ${RESTART_ATTEMPTS}"
      ensure_running
    fi
  fi
  sleep 2
done

if [[ $HEALTH_OK -ne 1 ]]; then
  log "ERROR: health check did not report ready within timeout (restart attempts: ${RESTART_ATTEMPTS})"
  exit 1
fi

RPC_RESULT=$(curl -sf -m 5 -X POST "$RPC_URL" -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"list_agents\",\"arguments\":{\"project_key\":\"${PROJECT_KEY}\"}}}" 2>&1)
if echo "$RPC_RESULT" | grep -q '"result"'; then
  log "JSON-RPC list_agents verification call OK"
else
  log "ERROR: JSON-RPC list_agents verification failed: ${RPC_RESULT:0:300}"
  exit 1
fi

log "=== agent-mail-prune run end OK (size ${BEFORE_SIZE} -> ${AFTER_SIZE} bytes, rows ${BEFORE_ROWS} -> ${AFTER_ROWS}) ==="
exit 0
