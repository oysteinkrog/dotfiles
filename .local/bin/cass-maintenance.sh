#!/bin/bash
# CASS maintenance: re-index session search and reflect on recent sessions.
#
# Run manually with `cassm`, or scheduled via Windows Task Scheduler
# (\CASS-Maintenance, every 30 min via wscript.exe + cass-maintenance.vbs).
#
# Target data dir: platform default (%APPDATA%\coding-agent-search\...),
# NOT the legacy cass-old dir. The wrapper at ~/.local/bin/cass no longer
# injects --data-dir, so plain `cass` here resolves to the new default.
#
# All output is appended to ~/.local/share/cass-maintenance.log so that
# scheduled (hidden) runs are debuggable.

set -uo pipefail

# Explicit PATH — Task Scheduler invokes via wsl.exe with a minimal env.
export PATH="/c/users/oystein/.local/bin:/c/users/oystein/bin:/usr/local/bin:/usr/bin:/bin"
export HOME="/c/users/oystein"

# Bump frankensqlite page-buffer pool ceiling from the default 262_144 (≈1 GB
# at 4 KB pages) to 1_048_576 (≈4 GB). The default trips OOM during incremental
# index runs once the canonical DB grows past a few GB, especially during the
# cass#202 orphan-FK self-heal pass on `token_usage`.
export FSQLITE_PAGE_BUFFER_MAX="${FSQLITE_PAGE_BUFFER_MAX:-1048576}"

# GPU-accelerated semantic embedding (DirectML, gpu-embedding build 2026-08-07).
# Fail-open: if GPU init fails, cass logs a warning and embeds on CPU.
export CASS_SEMANTIC_GPU="${CASS_SEMANTIC_GPU:-1}"

# cass runs as a Windows exe; WSL env vars only cross the WSL->Windows boundary
# when named in WSLENV. Without this line the exports above never reach cass.exe.
export WSLENV="${WSLENV:+$WSLENV:}FSQLITE_PAGE_BUFFER_MAX:CASS_SEMANTIC_GPU"

LOG_DIR="$HOME/.local/share"
LOG_FILE="$LOG_DIR/cass-maintenance.log"
LOG_MAX_BYTES=$((10 * 1024 * 1024))  # 10 MiB before rotation
MARKER="$HOME/.cache/cass-last-reflect"

mkdir -p "$LOG_DIR" "$(dirname "$MARKER")"

# Rotate log if it gets too big (keep one backup).
if [ -f "$LOG_FILE" ] && [ "$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$LOG_MAX_BYTES" ]; then
  mv "$LOG_FILE" "$LOG_FILE.1"
fi

# Tee all output to the log from here on.
exec >> "$LOG_FILE" 2>&1

ts() { date '+%Y-%m-%d %H:%M:%S'; }

echo
echo "===== [$( ts )] CASS maintenance start (pid=$$) ====="

# 1. Incremental index with --semantic (GPU/DirectML vector index).
#    At 30-min cadence each run handles only a handful of new sessions, so
#    semantic build stays cheap and we avoid mega-jobs.
#    Memory bounded by fork patches: chunking (7e38ce3) + memo widening (a4e3110).
echo "[$( ts )] cass index --semantic (incremental + GPU semantic)..."
if cass index --semantic; then
  echo "[$( ts )]   cass index OK"
else
  rc=$?
  echo "[$( ts )]   cass index FAILED (exit $rc)"
fi

# 2. Reflect on recent main sessions.
echo "[$( ts )] cm reflect on recent sessions..."
if [ ! -f "$MARKER" ]; then
  # First run: last 3 days
  mapfile -t SESSIONS < <(find "$HOME/.claude/projects/" -maxdepth 2 -name '*.jsonl' -mtime -3 2>/dev/null | head -10)
else
  # Subsequent runs: only sessions newer than the marker
  mapfile -t SESSIONS < <(find "$HOME/.claude/projects/" -maxdepth 2 -name '*.jsonl' -newer "$MARKER" 2>/dev/null | head -10)
fi
echo "[$( ts )]   ${#SESSIONS[@]} sessions to reflect on"
for session in "${SESSIONS[@]}"; do
  [ -n "$session" ] || continue
  if out=$(cm reflect --session "$session" --json 2>&1); then
    processed=$(echo "$out" | grep -o '"Processed[^"]*"' || true)
    echo "[$( ts )]   reflected $(basename "$session") ${processed:+— $processed}"
  else
    echo "[$( ts )]   reflect FAILED on $(basename "$session"):"
    echo "$out" | sed 's/^/    /'
  fi
done
touch "$MARKER"

# 3. Playbook status.
echo "[$( ts )] Playbook status:"
cm playbook list 2>&1 | head -2 | sed 's/^/  /'

echo "===== [$( ts )] CASS maintenance done ====="
