#!/usr/bin/env bash
# Repair a corrupt mcp-agent-mail SQLite database.
#
#   am-recover.sh --dry-run    diagnose and print the plan, change nothing
#   am-recover.sh              do it
#
# Picks the repair by damage type: REINDEX for index-only damage, sqlite3
# ".recover" for page damage. Never deletes the original. Refuses to touch
# anything while a live server holds the database.
#
# Deliberately does NOT use `am doctor reconstruct`: its output is clean but an
# acceptance gate rejects it, and it drops rows.
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

PM2_APP=mcp-agent-mail
ECOSYSTEM="$HOME/.config/pm2/ecosystem.config.js"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TABLES="projects agents messages message_recipients file_reservations"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- where is the database -------------------------------------------------
ROOT="${STORAGE_ROOT:-}"
if [ -z "$ROOT" ] && [ -f "$ECOSYSTEM" ]; then
    ROOT=$(grep -oP 'STORAGE_ROOT:\s*"\K[^"]+' "$ECOSYSTEM" | head -1 || true)
fi
ROOT="${ROOT:-$HOME/.mcp_agent_mail_git_mailbox_repo}"
DB="$ROOT/storage.sqlite3"
[ -f "$DB" ] || die "no database at $DB (set STORAGE_ROOT if it lives elsewhere)"
say "storage root: $ROOT"

SQLITE=$("$HERE/build-sqlite-recover.sh") || die "could not get a sqlite3 that can recover"
say "sqlite3:      $SQLITE"

counts() {  # counts <db> -> "table|n" lines, blank for tables that error
    local db=$1 t n
    for t in $TABLES; do
        n=$("$SQLITE" "file:$db?mode=ro" "select count(*) from $t;" 2>/dev/null || echo "?")
        printf '%s|%s\n' "$t" "$n"
    done
}

# --- classify the damage ---------------------------------------------------
step "integrity check"
CHECK=$("$SQLITE" "file:$DB?mode=ro" "PRAGMA integrity_check;" 2>&1 || true)
say "$CHECK" | head -20

if [ "$CHECK" = "ok" ]; then
    say ""
    say "Database is clean. Nothing to repair."
    say "If agent-mail is still misbehaving the problem is not the database:"
    say "  curl -s -o /dev/null -w '%{http_code}\\n' http://127.0.0.1:4809/health"
    say "  pm2 list | grep $PM2_APP"
    exit 0
fi

if echo "$CHECK" | grep -qE "2nd reference to page|cell extends past|out of order|freed earlier|referenced multiple times"; then
    MODE=recover
else
    MODE=reindex
fi
step "damage type"
if [ "$MODE" = reindex ]; then
    say "index-only damage -> REINDEX (table data is intact)"
else
    say "page-level damage -> sqlite3 .recover"
fi

step "row counts before"
BEFORE=$(counts "$DB"); say "$BEFORE"

if [ "$DRY_RUN" = 1 ]; then
    step "plan (dry run, nothing changed)"
    say "1. pm2 stop $PM2_APP"
    say "2. am doctor drain, require safe_to_mutate=true"
    if [ "$MODE" = reindex ]; then
        say "3. copy the database aside, then REINDEX in place"
    else
        say "3. copy database and sidecars to scratch, .recover into a new file"
        say "4. move the old database and every sidecar aside as storage.sqlite3.corrupt-<ts>"
        say "5. install the recovered file, journal_mode=WAL"
    fi
    say "6. pm2 start, verify health and a refreshed storage.sqlite3.bak"
    exit 0
fi

# --- stop the server -------------------------------------------------------
step "stopping the service"
pm2 stop "$PM2_APP" >/dev/null 2>&1 || die "pm2 stop failed"
sleep 6
DRAIN=$(am doctor drain 2>&1 || true)
echo "$DRAIN" | grep -q "safe_to_mutate: true" \
    || { echo "$DRAIN" | head -20; pm2 start "$PM2_APP" >/dev/null 2>&1 || true
         die "a live owner still holds the database; service restarted, nothing changed"; }
say "safe_to_mutate: true"

TS=$(date +%Y%m%d_%H%M%S)

restart_and_verify() {
    step "starting the service"
    pm2 start "$ECOSYSTEM" --only "$PM2_APP" >/dev/null 2>&1 \
        || pm2 start "$PM2_APP" >/dev/null 2>&1 \
        || die "pm2 start failed; start it by hand"
    pm2 save >/dev/null 2>&1 || true
    sleep 30
    local code
    code=$(curl -s -m 20 -o /dev/null -w '%{http_code}' "http://127.0.0.1:4809/health" || true)
    say "health endpoint: $code"
    step "did the server accept the database?"
    say "It refreshes storage.sqlite3.bak only when the source passes its own"
    say "integrity gate, so a fresh timestamp here is real confirmation:"
    ls -la --time-style=+%Y-%m-%d\ %H:%M:%S "$ROOT/storage.sqlite3.bak" 2>/dev/null || say "  (no .bak yet)"
    say ""
    say "Old database kept at: $ROOT/storage.sqlite3.*-$TS*"
    say "Next: am doctor check, and health_check over MCP for the verdict list."
}

# --- repair ----------------------------------------------------------------
if [ "$MODE" = reindex ]; then
    step "reindex"
    cp "$DB" "$ROOT/storage.sqlite3.pre-reindex-$TS"
    say "kept a copy at storage.sqlite3.pre-reindex-$TS"
    "$SQLITE" "$DB" "PRAGMA wal_checkpoint(TRUNCATE); REINDEX; PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null
    AFTER_CHECK=$("$SQLITE" "file:$DB?mode=ro" "PRAGMA integrity_check;" 2>&1 || true)
else
    step "recover"
    WORK=$(mktemp -d)
    cp "$DB" "$WORK/"
    for ext in -wal -shm; do
        [ -f "$DB$ext" ] && cp "$DB$ext" "$WORK/"
    done
    "$SQLITE" "$WORK/storage.sqlite3" ".recover" > "$WORK/rec.sql" 2>"$WORK/rec.err" \
        || { say "recover failed:"; head -5 "$WORK/rec.err"; die "aborted, nothing changed"; }
    "$SQLITE" "$WORK/new.sqlite3" < "$WORK/rec.sql" 2>"$WORK/load.err" \
        || { say "reload failed:"; head -5 "$WORK/load.err"; die "aborted, nothing changed"; }

    AFTER_CHECK=$("$SQLITE" "$WORK/new.sqlite3" "PRAGMA integrity_check;" 2>&1 || true)
    [ "$AFTER_CHECK" = "ok" ] || { say "$AFTER_CHECK" | head -10; die "recovered file is still not clean; nothing changed"; }

    step "row counts after"
    AFTER=$(counts "$WORK/new.sqlite3"); say "$AFTER"
    LOST=0
    while IFS='|' read -r t n; do
        b=$(printf '%s\n' "$BEFORE" | grep "^$t|" | cut -d'|' -f2)
        case "$b$n" in *\?*) continue;; esac
        [ "$n" -lt "$b" ] && { say "LOST ROWS in $t: $b -> $n"; LOST=1; }
    done <<< "$AFTER"
    [ "$LOST" = 0 ] || die "recovery lost rows; the corrupt original is untouched, nothing changed"

    "$SQLITE" "$WORK/new.sqlite3" "PRAGMA journal_mode=WAL; PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null

    step "installing"
    # Every sidecar moves with the database it belongs to. A stale -wal or
    # -wal-cert left beside a new database is a fresh corruption risk.
    mv "$DB" "$ROOT/storage.sqlite3.corrupt-$TS"
    for ext in -wal -shm -wal-cert -wal-cert-head; do
        [ -f "$DB$ext" ] && mv "$DB$ext" "$ROOT/storage.sqlite3.corrupt-$TS$ext"
    done
    cp "$WORK/new.sqlite3" "$DB"
    chmod 644 "$DB"
    say "installed; corrupt original kept as storage.sqlite3.corrupt-$TS"
    rm -rf "$WORK"
fi

step "integrity check after repair"
say "$AFTER_CHECK" | head -10
[ "$AFTER_CHECK" = "ok" ] || die "still not clean; service left stopped for inspection"

restart_and_verify
