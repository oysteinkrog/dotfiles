#!/usr/bin/env bash
# Rebuild codedb with WSL1 compatibility patch.
#
# Background: Zig 0.15's stdlib File.stat() and Dir.statFile() use the statx
# syscall on Linux with no ENOSYS fallback. WSL1 kernel 4.4 doesn't support
# statx (added in 4.11), so every stat call fails with error.Unexpected —
# causing 0 files indexed and broken data persistence.
#
# The patch (src/compat.zig) adds a runtime probe: if statx returns ENOSYS,
# all stat calls fall back to fstat/fstatat64. Zero overhead on normal Linux.
#
# Because Zig 0.15 itself uses statx internally, we must cross-compile from
# Windows Zig targeting x86_64-linux.
#
# Prerequisites:
#   - Windows Zig 0.15.0+ at C:\tools\zig-0.15.0\zig-x86_64-windows-0.15.0\
#   - codedb repo cloned at /c/work/codedb with the compat.zig patch applied
#
# Usage: ./codedb-build.sh [--install]

set -euo pipefail

CODEDB_REPO="/c/work/codedb"
ZIG_WIN="C:\\tools\\zig-0.15.0\\zig-x86_64-windows-0.15.0\\zig.exe"
OUTPUT="$CODEDB_REPO/zig-out/bin/codedb"
INSTALL_TO="$(dirname "$0")/codedb"

cd "$CODEDB_REPO"

echo "Building codedb (cross-compile Windows→Linux)..."
cmd.exe /c "$ZIG_WIN build -Dtarget=x86_64-linux"

echo "Built: $OUTPUT"
file "$OUTPUT"

if [[ "${1:-}" == "--install" ]]; then
    cp "$OUTPUT" "$INSTALL_TO"
    echo "Installed to: $INSTALL_TO"
fi
