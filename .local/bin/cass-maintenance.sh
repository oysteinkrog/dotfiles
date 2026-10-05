#!/bin/bash
# CASS maintenance: re-index session search and reflect on recent sessions.
#
# Run manually with `cassm`, or scheduled by the systemd user timer
# cass-maintenance.timer (daily at 04:00, ~/.config/systemd/user/). The unit sets
# CASS_AUTO_REFRESH=0 and the memory caps.
#
# Linux port (2026-09-29): cass is the native Linux build and the data dir is
# the platform default ~/.local/share/coding-agent-search. The Windows-only GPU
# semantic backfill (cass-gpu.exe, DirectML) is not ported, so this runs the
# lexical index and cm reflect only.
#
# All output is appended to ~/.local/share/cass-maintenance.log so that
# scheduled runs are debuggable.

set -uo pipefail

# Explicit PATH: systemd user units start with a minimal env.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin"

# Bump frankensqlite page-buffer pool ceiling from the default 262_144 (≈1 GB
# at 4 KB pages) to 1_048_576 (≈4 GB). The default trips OOM during incremental
# index runs once the canonical DB grows past a few GB.
export FSQLITE_PAGE_BUFFER_MAX="${FSQLITE_PAGE_BUFFER_MAX:-1048576}"

# Widen the redact memo cache for catch-up runs (upstream #291; default 4096
# entries thrashes with CapacityLru evictions during bulk ingest).
export CASS_REDACT_MEMO_CAPACITY="${CASS_REDACT_MEMO_CAPACITY:-65536}"

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

# 1. Incremental lexical index, capped because cass index has hung under
#    contention. --quiet keeps warnings and errors only; without it cass logs
#    a line per document (241 MB in one catch-up run). Do NOT add --semantic
#    here: it would mix vectors of a different provenance into the vector
#    index (see docs/cass-setup.md).
echo "[$( ts )] cass index (incremental lexical)..."
if timeout 5400 /usr/bin/cass --quiet index --no-progress-events </dev/null; then
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
