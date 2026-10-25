#!/bin/bash
# Scheduled prune for the mcp-agent-mail live SQLite store.
#
# atc_experiences (the internal Adaptive Tool Calibration decision-experience
# ledger, unrelated to mail/file-reservation function) has no upstream
# retention tooling and regrows continuously with swarm activity. This keeps
# only the newest N rows by experience_id and reclaims the space with VACUUM.
#
# Safe-against-server method: stop agent-mail.service before touching the live
# file, operate via a stdin heredoc (VACUUM as a `-cmd` argument is a silent
# no-op on some sqlite3 builds), then restart and verify with both /health and
# a real JSON-RPC call before declaring success. The EXIT trap guarantees the
# server is restarted even if an earlier step fails, so a bad run never
# leaves the service down.
#
# The unit sets AM_ATC_ENABLED=false, so the table should not grow any more.
# Run this by hand if it ever does.

set -uo pipefail

DB="$HOME/.mcp_agent_mail_git_mailbox_repo/storage.sqlite3"
LOG="$HOME/bin/logs/agent-mail-prune.log"
KEEP=5000
HEALTH_URL="http://127.0.0.1:4809/health"
RPC_URL="http://127.0.0.1:4809/mcp/"
UNIT="agent-mail.service"
PROJECT_KEY="$HOME/work/desktop/metrics"

mkdir -p "$(dirname "$LOG")"

RESTARTED=0

log() {
  printf '%s %s\n' "$(date -Iseconds)" "$*" >>"$LOG"
}

restart_server() {
  if [[ "$RESTARTED" -eq 1 ]]; then
    return 0
  fi
  RESTARTED=1
  log "starting ${UNIT}"
  systemctl --user start "$UNIT" >>"$LOG" 2>&1 || log "ERROR: systemctl --user start ${UNIT} failed"
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
log "pre-stop file size=${BEFORE_SIZE} bytes"

log "stopping ${UNIT}"
systemctl --user stop "$UNIT" >>"$LOG" 2>&1 || { log "ERROR: systemctl --user stop ${UNIT} failed"; exit 1; }
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
for i in $(seq 1 90); do
  if curl -sf -m 3 "$HEALTH_URL" 2>/dev/null | grep -q '"status":"ready"'; then
    HEALTH_OK=1
    log "health check OK after ~$((i * 2))s"
    break
  fi
  sleep 2
done

if [[ $HEALTH_OK -ne 1 ]]; then
  log "ERROR: health check did not report ready within 180s ($(systemctl --user is-active "$UNIT"))"
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
