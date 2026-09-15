#!/usr/bin/env bash
# Build a sqlite3 CLI that can actually run ".recover".
#
# Ubuntu's /usr/bin/sqlite3 links against the system libsqlite3, which is built
# without SQLITE_ENABLE_DBPAGE_VTAB. ".recover" then dies with
#   sql error: no such table: sqlite_dbpage (1)
# which reads like the database is beyond help when it is not.
#
# Prints the path to a working binary on stdout. Idempotent: rebuilds only when
# the cached binary is missing or cannot recover.
set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/agent-mail-ops"
BIN="$CACHE/sqlite3-full"
VERSION="3500400"
URL="https://sqlite.org/2025/sqlite-amalgamation-${VERSION}.zip"

log() { printf '%s\n' "$*" >&2; }

can_recover() {
    local bin=$1 tmp
    [ -x "$bin" ] || return 1
    tmp=$(mktemp -d)
    "$bin" "$tmp/probe.db" "create table t(a); insert into t values (1);" 2>/dev/null || {
        rm -rf "$tmp"; return 1
    }
    if "$bin" "$tmp/probe.db" ".recover" 2>&1 | grep -q "sqlite_dbpage"; then
        rm -rf "$tmp"; return 1
    fi
    rm -rf "$tmp"; return 0
}

if can_recover "$BIN"; then
    log "cached build is good"
    printf '%s\n' "$BIN"
    exit 0
fi

command -v gcc  >/dev/null || { log "gcc not found"; exit 1; }
command -v curl >/dev/null || { log "curl not found"; exit 1; }
command -v unzip >/dev/null || { log "unzip not found"; exit 1; }

mkdir -p "$CACHE"
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT

log "downloading $URL"
curl -sSL -o "$BUILD/amalg.zip" "$URL"
unzip -oq "$BUILD/amalg.zip" -d "$BUILD"
SRC="$BUILD/sqlite-amalgamation-${VERSION}"

log "compiling (about 40 seconds)"
gcc -O1 -o "$BIN" "$SRC/shell.c" "$SRC/sqlite3.c" \
    -DSQLITE_ENABLE_DBPAGE_VTAB \
    -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_JSON1 \
    -DSQLITE_ENABLE_RTREE \
    -DSQLITE_THREADSAFE=0 \
    -lm -lpthread -ldl

can_recover "$BIN" || { log "built binary still cannot recover"; exit 1; }
log "built $("$BIN" --version | cut -d' ' -f1-2)"
printf '%s\n' "$BIN"
